import Foundation

// Разбор ответа Gemini на правый ⌘: из сырого текста — проверенный план или
// честный отказ (план D.3–D.4).
//
// Замер T0: ответ приходит описанием одного `AXStaticText` на строку ответа, и это
// сырой markdown вместе с ограждениями — ```json с объектом и, если текст длинный,
// ```text с ним же. Поэтому «сырые сегменты» из D.3 здесь — куски этого текста
// между ограждениями, а не отдельные элементы дерева.
//
// Разбор зовут на каждом опросе, пока ответ печатается, поэтому он чисто локальный
// и дешёвый, а недописанный хвост — не ошибка, а ремонт `truncated`: по нему движок
// понимает, что надо ждать дальше. Действий из прозы парсер не выводит никогда.

enum AssistantParser {

    /// Правило промпта. План длиннее — признак того, что модель не поняла задачу.
    static let maxSteps = 5

    static func extract(answer: String, context: AssistantParseContext) -> AssistantVerdict {
        let parts = Part.split(answer)
        var ours: [Found] = []
        var sawStale = false, sawIdless = false, sawUnreadOurs = false

        func consider(_ text: String, part: Int, fromFence: Bool, tail: () -> String?) {
            // Объект с нашим id, который не читается даже снисходительно (или читается
            // в мусор), — это наш ответ, просто сломанный; прозой его показывать нельзя.
            let mentionsUs = !context.id.isEmpty && text.contains(context.id)
            guard let (object, repairs) = parseObject(text) else {
                if mentionsUs { sawUnreadOurs = true }
                return
            }
            let id = idOf(object)
            let isOurs = id.map { $0.caseInsensitiveCompare(context.id) == .orderedSame } ?? false
            // Чужой JSON в ответе (пример конфига, код) — не план и не повод для `.stale`.
            guard isOurs || looksLikePlan(object) else {
                if mentionsUs { sawUnreadOurs = true }
                return
            }
            if isOurs {
                ours.append(Found(object: object, repairs: repairs, part: part, tail: tail(), fromFence: fromFence))
            } else if id == nil {
                sawIdless = true
            } else {
                sawStale = true
            }
        }

        // D.4 п. 1: сначала блоки ```json, затем прочие блоки, которые начинаются
        // с «{», затем проза между блоками.
        for (index, part) in parts.enumerated() where part.isJSONFence {
            for found in ObjectScanner.objects(in: part.body) {
                consider(found.text, part: index, fromFence: true) { nil }
            }
        }
        for (index, part) in parts.enumerated() where part.isFence && !part.isJSONFence && part.startsWithBrace {
            for found in ObjectScanner.objects(in: part.body) {
                consider(found.text, part: index, fromFence: true) { nil }
            }
        }
        for (index, part) in parts.enumerated() where !part.isFence {
            for found in ObjectScanner.objects(in: part.body) {
                consider(found.text, part: index, fromFence: false) { String(part.body.unicodeScalars[found.end...]) }
            }
        }
        // Последняя попытка — от первой «{» до последней «}» всего ответа, на случай
        // если сканер сбился на кавычках. Только когда в ответе вообще есть наш id.
        if ours.isEmpty && !sawStale && !sawIdless && !context.id.isEmpty && answer.contains(context.id),
           let first = answer.firstIndex(of: "{"), let last = answer.lastIndex(of: "}"), first < last {
            consider(String(answer[first...last]), part: parts.count, fromFence: false) { nil }
        }

        // `@N` не должен указывать на повтор самого плана, поэтому блоки с нашим
        // объектом из счёта исключены.
        let planFences = Set(ours.filter(\.fromFence).map(\.part))
        var plans: [AssistantPlan] = []
        var firstInvalid: AssistantVerdict?
        for found in ours {
            var normalizer = Normalizer(context: context, repairs: found.repairs) { n in
                blockText(n, after: found, parts: parts, planFences: planFences)
            }
            switch normalizer.run(found.object, fromCodeBlock: found.fromFence) {
            case .plan(let plan):
                if !plans.contains(where: { $0.steps == plan.steps && $0.say == plan.say }) { plans.append(plan) }
            case let verdict:
                if firstInvalid == nil { firstInvalid = verdict }
            }
        }

        if let plan = plans.first {
            guard plans.count > 1 else { return .plan(plan) }
            // Два разных плана на один запрос: какой из них имелся в виду, неизвестно,
            // поэтому берём первый (из ```json) и требуем подтверждения.
            return .plan(AssistantPlan(id: plan.id, steps: plan.steps, say: plan.say,
                                       repairs: plan.repairs.union([.multiplePlans]),
                                       fromCodeBlock: plan.fromCodeBlock))
        }
        if let firstInvalid { return firstInvalid }
        if sawUnreadOurs {
            return .invalid(say: nil, reason: T("JSON ответа не разобран", "The answer's JSON is unreadable"))
        }
        if sawStale { return .stale }
        if sawIdless {
            // Без id свежесть не проверить: это может быть ответ на прошлый запрос.
            return .invalid(say: nil, reason: T("В JSON ответа нет id", "The answer's JSON has no id"))
        }
        let prose = parts.map(\.body).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return .noPlan(prose: prose)
    }

    // MARK: - Объекты ответа

    /// Объект с нашим id и место, где он найден: от места зависит, куда смотрит `@N`.
    private struct Found {
        let object: [String: Any]
        let repairs: Set<AssistantRepair>
        let part: Int
        /// Для объекта из прозы — текст после него в той же части.
        let tail: String?
        let fromFence: Bool
    }

    private static func parseObject(_ text: String) -> ([String: Any], Set<AssistantRepair>)? {
        guard !tooDeep(text) else { return nil }
        if let data = text.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return (object, [])
        }
        var lenient = Lenient(text)
        guard let object = (try? lenient.parse()) as? [String: Any] else { return nil }
        return (object, lenient.repairs)
    }

    /// `JSONSerialization` рекурсивен: на фоновом потоке (512 КБ стека) он падает
    /// уже на нескольких сотнях `[` — раньше собственного предела в 512. Плану
    /// хватает трёх уровней, так что глубокий объект — не план, и в разбор не идёт.
    private static func tooDeep(_ text: String) -> Bool {
        var depth = 0, inString = false, escaped = false
        for byte in text.utf8 {
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
            } else if byte == 0x22 {
                inString = true
            } else if byte == 0x7B || byte == 0x5B {
                depth += 1
                if depth > Lenient.maxDepth { return true }
            } else if byte == 0x7D || byte == 0x5D {
                depth -= 1
            }
        }
        return false
    }

    private static func idOf(_ object: [String: Any]) -> String? {
        switch object["id"] {
        case let id as String: return id.trimmingCharacters(in: .whitespacesAndNewlines)
        case let id as NSNumber: return id.stringValue
        default: return nil
        }
    }

    private static func looksLikePlan(_ object: [String: Any]) -> Bool {
        ["steps", "say", "do", "actions", "tool"].contains { object[$0] != nil }
    }

    /// Текст для `"@N"`: N-й блок после блока с планом (метки языка в счёт не идут —
    /// они в строке ограждения). Если блоков после плана нет, а просят `@1`, —
    /// весь текст после JSON: модель иногда забывает ограждение.
    ///
    /// У такого текста нет закрывающего ограждения, и дописан ли он, не узнать:
    /// пока печатается, это «Вот перевод:» или «``» от будущего блока ```text.
    /// Поэтому он всегда идёт как `truncated` — движок ждёт конца генерации и
    /// показывает план человеку, а не заменяет выделение обрывком.
    private static func blockText(_ n: Int, after found: Found, parts: [Part], planFences: Set<Int>) -> (text: String, truncated: Bool)? {
        let later = parts.indices.filter { $0 > found.part && parts[$0].isFence && !planFences.contains($0) }
        if n >= 1 && n <= later.count {
            let block = parts[later[n - 1]]
            let text = trimBlock(block.body)
            return text.isEmpty ? nil : (text, !block.closed)
        }
        guard later.isEmpty, n == 1 else { return nil }
        var pieces = found.tail.map { [$0] } ?? []
        if found.part + 1 < parts.count {
            pieces += parts[(found.part + 1)...].filter { !$0.isFence }.map(\.body)
        }
        var text = trimBlock(pieces.joined(separator: "\n"))
        // Код-виджет без ограждения оставляет метку языка отдельной строкой.
        if let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
           ["text", "json", "plaintext", "markdown", "md", "txt"].contains(firstLine.trimmingCharacters(in: .whitespaces).lowercased()) {
            text = trimBlock(String(text.dropFirst(firstLine.count)))
        }
        return text.isEmpty ? nil : (text, true)
    }

    /// Пустые строки по краям блока — артефакт разметки, а отступ первой строки
    /// кода — часть текста, его не трогаем.
    private static func trimBlock(_ text: String) -> String {
        var slice = Substring(text)
        while let c = slice.last, c.isWhitespace { slice = slice.dropLast() }
        while let c = slice.first, c.isNewline { slice = slice.dropFirst() }
        return String(slice)
    }
}

// MARK: - Разметка ответа

extension AssistantParser {

    /// Кусок ответа: проза или содержимое блока ```…``` без строк ограждения.
    struct Part {
        /// nil — проза; "" — блок без метки языка.
        let label: String?
        let body: String
        /// Закрывающее ограждение уже пришло; иначе блок ещё печатается.
        let closed: Bool

        var isFence: Bool { label != nil }
        var isJSONFence: Bool { label == "json" || label == "json5" || label == "jsonc" }
        var startsWithBrace: Bool { body.drop(while: { $0.isWhitespace }).first == "{" }

        /// Ограждения по CommonMark: строка из трёх и более ` или ~, закрывает
        /// строка из того же символа не короче открывающей. Незакрытый блок идёт
        /// до конца текста — ответ ещё печатается.
        static func split(_ text: String) -> [Part] {
            var parts: [Part] = []
            var lines: [Substring] = []
            var open: (marker: Character, count: Int, label: String)?

            func flush(_ label: String?, closed: Bool) {
                if label != nil || !lines.isEmpty {
                    parts.append(Part(label: label, body: lines.joined(separator: "\n"), closed: closed))
                }
                lines.removeAll(keepingCapacity: true)
            }

            for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
                if let fence = open {
                    if closes(line, marker: fence.marker, count: fence.count) {
                        flush(fence.label, closed: true)
                        open = nil
                    } else {
                        lines.append(line)
                    }
                } else if let fence = opener(line) {
                    flush(nil, closed: true)
                    open = fence
                } else {
                    lines.append(line)
                }
            }
            if let fence = open { flush(fence.label, closed: false) } else { flush(nil, closed: true) }
            return parts
        }

        private static func opener(_ line: Substring) -> (marker: Character, count: Int, label: String)? {
            let text = line.drop(while: { $0 == " " || $0 == "\t" })
            guard let marker = text.first, marker == "`" || marker == "~" else { return nil }
            let count = text.prefix(while: { $0 == marker }).count
            guard count >= 3 else { return nil }
            let info = text.dropFirst(count).trimmingCharacters(in: .whitespaces)
            // «```json {…}```» в одну строку — это не ограждение, а инлайн-код.
            if marker == "`" && info.contains("`") { return nil }
            let label = info.split(separator: " ").first.map { $0.lowercased() } ?? ""
            return (marker, count, label)
        }

        private static func closes(_ line: Substring, marker: Character, count: Int) -> Bool {
            let text = line.trimmingCharacters(in: .whitespaces)
            return text.count >= count && text.allSatisfy { $0 == marker }
        }
    }

    /// Сбалансированные `{…}` верхнего уровня. Кавычки любого вида учитываются только
    /// внутри объекта — апострофы и «ёлочки» прозы вокруг не сбивают счёт скобок.
    /// Незакрытый хвост тоже отдаётся: ответ мог ещё не допечататься.
    enum ObjectScanner {
        static func objects(in text: String) -> [(text: String, end: String.Index)] {
            let scalars = text.unicodeScalars
            var out: [(text: String, end: String.Index)] = []
            var depth = 0
            var start = scalars.startIndex
            var quote: Unicode.Scalar?
            var i = scalars.startIndex
            while i < scalars.endIndex {
                let c = scalars[i]
                if let q = quote {
                    if c == "\\" {
                        i = scalars.index(after: i)
                        if i < scalars.endIndex { i = scalars.index(after: i) }
                        continue
                    }
                    // Типографская или одинарная кавычка без пары не должна съесть
                    // остаток ответа: её строка кончается вместе с текстовой строкой.
                    if Lenient.pairs(q, c) || (c == "\n" && q != "\"") { quote = nil }
                } else if depth > 0 && Lenient.isQuote(c) {
                    quote = c
                } else if c == "{" {
                    if depth == 0 { start = i }
                    depth += 1
                } else if c == "}" && depth > 0 {
                    depth -= 1
                    if depth == 0 {
                        let next = scalars.index(after: i)
                        out.append((String(scalars[start..<next]), next))
                    }
                }
                i = scalars.index(after: i)
            }
            if depth > 0 { out.append((String(scalars[start...]), scalars.endIndex)) }
            return out
        }
    }
}

// MARK: - Снисходительный JSON

extension AssistantParser {

    /// Разбор того, что строгий `JSONSerialization` не принял. Каждая поблажка
    /// записывается ремонтом: по тяжёлым движок решает, нужна ли карточка
    /// подтверждения. Где закрывается строка, решает то, что идёт после кавычки:
    /// разметка Gemini съедает `\"`, а модель печатает внутренние кавычки как есть.
    struct Lenient {
        struct Failure: Error {}

        static let dQuotes: Set<Unicode.Scalar> = ["\"", "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}", "\u{2033}", "\u{FF02}"]
        static let sQuotes: Set<Unicode.Scalar> = ["'", "\u{2018}", "\u{2019}", "\u{201A}"]
        static let invisible: Set<Unicode.Scalar> = ["\u{00A0}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}", "\u{202F}", "\u{2028}", "\u{2029}"]

        static func isQuote(_ c: Unicode.Scalar) -> Bool { dQuotes.contains(c) || sQuotes.contains(c) }

        /// Закрывает ли `c` строку, открытую `open`. ASCII-кавычка закрывается только
        /// такой же: типографская внутри неё — обычный текст.
        static func pairs(_ open: Unicode.Scalar, _ c: Unicode.Scalar) -> Bool {
            switch open {
            case "\"": return c == "\""
            case "'": return c == "'"
            default: return dQuotes.contains(open) ? dQuotes.contains(c) : sQuotes.contains(c)
            }
        }

        private let s: [Unicode.Scalar]
        private var i = 0
        /// Разбор рекурсивный, а зовут его с фонового потока (512 КБ стека):
        /// несколько сотен `[` подряд уронили бы приложение. Плану хватает трёх уровней.
        private var depth = 0
        static let maxDepth = 32
        private(set) var repairs: Set<AssistantRepair> = []

        init(_ text: String) { s = Array(text.unicodeScalars) }

        mutating func parse() throws -> Any {
            skipWS()
            guard i < s.count else { throw Failure() }
            return try value(.top)
        }

        private enum Ctx { case top, objectValue, arrayItem, key }

        private func peek(_ k: Int = 0) -> Unicode.Scalar? { i + k < s.count ? s[i + k] : nil }

        private static func isWS(_ c: Unicode.Scalar) -> Bool {
            c == " " || c == "\n" || c == "\r" || c == "\t" || invisible.contains(c)
        }

        private static func isDigit(_ c: Unicode.Scalar) -> Bool { ("0"..."9").contains(c) }

        private mutating func skipWS() {
            while let c = peek() {
                if Self.isWS(c) {
                    if Self.invisible.contains(c) { repairs.insert(.invisibleChars) }
                    i += 1
                } else if c == "/" && peek(1) == "/" {
                    repairs.insert(.comments)
                    while let d = peek(), d != "\n" { i += 1 }
                } else if c == "/" && peek(1) == "*" {
                    repairs.insert(.comments)
                    i += 2
                    while i < s.count && !(peek() == "*" && peek(1) == "/") { i += 1 }
                    i = min(s.count, i + 2)
                } else {
                    break
                }
            }
        }

        /// Первый значимый символ начиная с `from` — без пробелов и комментариев.
        private func nextSignificant(from: Int) -> (Unicode.Scalar?, Int) {
            var j = from
            while j < s.count {
                if Self.isWS(s[j]) { j += 1; continue }
                if s[j] == "/" && j + 1 < s.count && s[j + 1] == "/" {
                    while j < s.count && s[j] != "\n" { j += 1 }
                    continue
                }
                if s[j] == "/" && j + 1 < s.count && s[j + 1] == "*" {
                    j += 2
                    while j + 1 < s.count && !(s[j] == "*" && s[j + 1] == "/") { j += 1 }
                    j += 2
                    continue
                }
                break
            }
            return (j < s.count ? s[j] : nil, j)
        }

        private mutating func value(_ ctx: Ctx) throws -> Any {
            skipWS()
            guard let c = peek() else { repairs.insert(.truncated); return NSNull() }
            if c == "{" || c == "[" {
                guard depth < Self.maxDepth else { throw Failure() }
                depth += 1
                defer { depth -= 1 }
                return c == "{" ? try object() : try array()
            }
            if Self.isQuote(c) { return string(ctx) }
            if c == "-" || Self.isDigit(c) { return number() }
            return bare()
        }

        private mutating func object() throws -> [String: Any] {
            i += 1
            var out: [String: Any] = [:]
            while true {
                skipWS()
                guard let c = peek() else { repairs.insert(.truncated); return out }
                if c == "}" { i += 1; return out }
                if c == "," { repairs.insert(.trailingCommas); i += 1; continue }
                let key: String
                if Self.isQuote(c) {
                    key = string(.key)
                } else {
                    var bareKey = String.UnicodeScalarView()
                    while let d = peek(), d != ":" && d != "=" && !Self.isWS(d) && d != "}" && d != "," {
                        bareKey.append(d)
                        i += 1
                    }
                    if bareKey.isEmpty { throw Failure() }
                    repairs.insert(.unquotedKeys)
                    key = String(bareKey)
                }
                skipWS()
                if peek() == ":" {
                    i += 1
                } else if peek() == "=" {
                    repairs.insert(.unquotedKeys)   // `key = value` в стиле Python — та же вольность синтаксиса ключа
                    i += 1
                } else if i >= s.count {
                    repairs.insert(.truncated)
                    return out
                } else {
                    throw Failure()
                }
                out[key] = try value(.objectValue)
                skipWS()
                guard let d = peek() else { repairs.insert(.truncated); return out }
                if d == "," {
                    i += 1
                    if nextSignificant(from: i).0 == "}" { repairs.insert(.trailingCommas) }
                    continue
                }
                if d == "}" { i += 1; return out }
                // Пропущенная запятая между членами — та же косметика, что и лишняя.
                if Self.isQuote(d) { repairs.insert(.trailingCommas); continue }
                throw Failure()
            }
        }

        private mutating func array() throws -> [Any] {
            i += 1
            var out: [Any] = []
            while true {
                skipWS()
                guard let c = peek() else { repairs.insert(.truncated); return out }
                if c == "]" { i += 1; return out }
                if c == "," { repairs.insert(.trailingCommas); i += 1; continue }
                out.append(try value(.arrayItem))
                skipWS()
                guard let d = peek() else { repairs.insert(.truncated); return out }
                if d == "," {
                    i += 1
                    if nextSignificant(from: i).0 == "]" { repairs.insert(.trailingCommas) }
                    continue
                }
                if d == "]" { i += 1; return out }
                if d == "{" || Self.dQuotes.contains(d) { repairs.insert(.trailingCommas); continue }
                throw Failure()
            }
        }

        /// Закрывает ли кавычка на позиции `q` строку — решает то, что после неё.
        private func closes(at q: Int, ctx: Ctx) -> Bool {
            let (n, j) = nextSignificant(from: q + 1)
            guard let n else { return true }
            switch ctx {
            case .key:
                return n == ":" || n == "="
            case .top:
                return true
            case .objectValue, .arrayItem:
                if n == "}" || n == "]" { return true }
                guard n == "," else { return false }
                // После запятой должен идти ключ (в объекте) или значение (в массиве).
                let (m, k) = nextSignificant(from: j + 1)
                guard let m else { return true }
                if ctx == .arrayItem {
                    return m == "{" || m == "[" || Self.isQuote(m) || m == "-" || Self.isDigit(m) || m == "t" || m == "f" || m == "n"
                }
                if m == "}" { return true }
                if Self.isQuote(m) {
                    var t = k + 1
                    while t < s.count, !Self.isQuote(s[t]), s[t] != "\n" { t += 1 }
                    let after = nextSignificant(from: t + 1).0
                    return after == ":" || after == nil
                }
                var t = k
                while t < s.count, s[t].properties.isAlphabetic || Self.isDigit(s[t]) || s[t] == "_" || s[t] == "." { t += 1 }
                return t > k && nextSignificant(from: t).0 == ":"
            }
        }

        private mutating func string(_ ctx: Ctx) -> String {
            let open = s[i]
            if Self.sQuotes.contains(open) { repairs.insert(.singleQuotes) } else if open != "\"" { repairs.insert(.smartQuotes) }
            let closers = Self.sQuotes.contains(open) ? Self.sQuotes : Self.dQuotes
            i += 1
            var out = String.UnicodeScalarView()
            while true {
                guard let c = peek() else { repairs.insert(.truncated); return String(out) }
                if c == "\\" {
                    guard let e = peek(1) else { i += 1; repairs.insert(.truncated); return String(out) }
                    i += 2
                    switch e {
                    case "\"": out.append("\"")
                    case "\\": out.append("\\")
                    case "/": out.append("/")
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "r": out.append("\r")
                    case "b": out.append("\u{8}")
                    case "f": out.append("\u{C}")
                    case "u":
                        if let scalar = unicodeEscape() { out.append(scalar) } else { repairs.insert(.badEscapes); out.append("u") }
                    default:
                        // Экранирование разметки: \_ \* \# \[ — символ как есть.
                        repairs.insert(.badEscapes)
                        out.append(e)
                    }
                    continue
                }
                if closers.contains(c) {
                    if closes(at: i, ctx: ctx) {
                        if c != open && !Self.pairs(open, c) { repairs.insert(.smartQuotes) }
                        i += 1
                        return String(out)
                    }
                    // Кавычка того же вида посреди значения — модель не экранировала
                    // внутреннюю кавычку. Типографская внутри ASCII-строки — просто текст.
                    if Self.pairs(open, c) { repairs.insert(.innerQuote) }
                    out.append(c)
                    i += 1
                    continue
                }
                if c == "\n" || c == "\r" || c == "\t" { repairs.insert(.rawNewlines) }
                out.append(c)
                i += 1
            }
        }

        /// `\uXXXX` после уже съеденного `\u`, включая суррогатные пары.
        private mutating func unicodeEscape() -> Unicode.Scalar? {
            func hex(at k: Int) -> UInt32? {
                guard k + 4 <= s.count else { return nil }
                return UInt32(String(String.UnicodeScalarView(s[k..<k + 4])), radix: 16)
            }
            guard let high = hex(at: i) else { return nil }
            if (0xD800...0xDBFF).contains(high), i + 10 <= s.count, s[i + 4] == "\\", s[i + 5] == "u",
               let low = hex(at: i + 6), (0xDC00...0xDFFF).contains(low) {
                i += 10
                return Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))
            }
            guard let scalar = Unicode.Scalar(high) else { return nil }
            i += 4
            return scalar
        }

        private mutating func number() -> Any {
            var text = ""
            while let c = peek(), c == "-" || c == "+" || c == "." || c == "e" || c == "E" || Self.isDigit(c) {
                text.unicodeScalars.append(c)
                i += 1
            }
            if let n = Int(text) { return n }
            if let d = Double(text) { return d }
            return text   // «2026-09-25» без кавычек: проверка типа решит сама
        }

        private mutating func bare() -> Any {
            var text = ""
            while let c = peek(), c != "," && c != "}" && c != "]" && c != "\n" {
                text.unicodeScalars.append(c)
                i += 1
            }
            let word = text.trimmingCharacters(in: .whitespaces)
            switch word {
            case "true": return true
            case "false": return false
            case "null": return NSNull()
            case "True": repairs.insert(.pythonLiterals); return true
            case "False": repairs.insert(.pythonLiterals); return false
            case "None": repairs.insert(.pythonLiterals); return NSNull()
            default: repairs.insert(.unquotedKeys); return word
            }
        }
    }
}

// MARK: - Проверка плана

extension AssistantParser {

    static let tools: Set<String> = [
        "text.insert", "text.replace", "reminder.add", "calendar.add", "note.add", "timer.set",
        "app.open", "url.open", "volume.set", "message.draft", "clarify", "edit", "undo",
    ]

    /// Имена, которыми модель называет наши инструменты. Ключи — после замены `_ - /`
    /// на точку. Всё про отправку ведёт в черновик: отправлять Intact не умеет.
    static let toolAliases: [String: String] = [
        "timer.start": "timer.set", "timer": "timer.set", "timer.add": "timer.set", "timer.create": "timer.set",
        "volume": "volume.set", "sound.set": "volume.set",
        "last.undo": "undo", "last.change": "edit",
        "reminder": "reminder.add", "reminders.add": "reminder.add", "reminder.create": "reminder.add",
        "create.reminder": "reminder.add", "add.reminder": "reminder.add", "remind": "reminder.add",
        "event.add": "calendar.add", "calendar.create": "calendar.add", "calendar.event": "calendar.add",
        "event.create": "calendar.add", "create.event": "calendar.add", "add.event": "calendar.add",
        "note.create": "note.add", "notes.add": "note.add", "create.note": "note.add", "add.note": "note.add",
        "open.app": "app.open", "app.launch": "app.open", "app.start": "app.open", "open.application": "app.open",
        "open.url": "url.open", "url": "url.open", "link.open": "url.open", "browser.open": "url.open",
        "insert": "text.insert", "type": "text.insert", "text": "text.insert", "paste": "text.insert", "text.type": "text.insert",
        "replace": "text.replace", "text.rewrite": "text.replace",
        "message": "message.draft", "message.send": "message.draft", "sms": "message.draft",
        "send.message": "message.draft", "draft": "message.draft",
        "ask": "clarify", "question": "clarify",
    ]

    /// Точное имя, затем алиас, затем единственное близкое имя. Короткие имена
    /// (`edit`, `undo`) прощают только одну опечатку: «todo» не должен стать «undo».
    static func resolveTool(_ raw: String) -> (name: String, repair: AssistantRepair?)? {
        let visible = String(String.UnicodeScalarView(raw.unicodeScalars.filter { !Lenient.invisible.contains($0) }))
        let name = visible.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return nil }
        if tools.contains(name) { return (name, nil) }
        let dotted = String(name.map { "_- /:".contains($0) ? "." : $0 })
        if tools.contains(dotted) { return (dotted, .aliasedTool) }
        if let alias = toolAliases[dotted] { return (alias, .aliasedTool) }
        var best: (name: String, distance: Int)?
        var tie = false
        for tool in tools {
            let distance = levenshtein(dotted, tool)
            guard distance <= min(2, max(1, tool.count / 4)) else { continue }
            if best == nil || distance < best!.distance {
                best = (tool, distance)
                tie = false
            } else if distance == best!.distance {
                tie = true
            }
        }
        guard let best, !tie else { return nil }
        return (best.name, .fuzzyTool)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a.unicodeScalars), b = Array(b.unicodeScalars)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Проверяет один объект с нашим id (D.4 пп. 4–7) и собирает план.
    private struct Normalizer {
        let context: AssistantParseContext
        var repairs: Set<AssistantRepair>
        let resolve: (Int) -> (text: String, truncated: Bool)?
        let calendar: Calendar
        private var args: [String: Any] = [:]
        private var tool = ""

        struct Invalid: Error { let reason: String }

        init(context: AssistantParseContext, repairs: Set<AssistantRepair>, resolve: @escaping (Int) -> (text: String, truncated: Bool)?) {
            self.context = context
            self.repairs = repairs
            self.resolve = resolve
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = context.timeZone
            self.calendar = calendar
        }

        mutating func run(_ object: [String: Any], fromCodeBlock: Bool) -> AssistantVerdict {
            let root = Self.lowercasedKeys(object)
            let say = sayText(root)

            var rawSteps: [Any] = []
            if let steps = root["steps"] ?? aliased(root, ["actions", "plan"]) {
                switch steps {
                case let list as [Any]: rawSteps = list
                case is NSNull: break
                default: rawSteps = [steps]; repairs.insert(.aliasedArgument)
                }
            } else if root["do"] != nil || root["tool"] != nil {
                rawSteps = [root]   // один шаг прямо в корне
                repairs.insert(.aliasedArgument)
            }
            guard rawSteps.count <= AssistantParser.maxSteps else {
                return .invalid(say: say.isEmpty ? nil : say,
                                reason: T("В плане больше \(AssistantParser.maxSteps) шагов", "The plan has more than \(AssistantParser.maxSteps) steps"))
            }

            var steps: [AssistantStep] = []
            var problem: String?
            for raw in rawSteps {
                do {
                    steps.append(try step(raw))
                } catch {
                    repairs.insert(.droppedStep)
                    if problem == nil { problem = (error as? Invalid)?.reason }
                }
            }

            // Текст в чужое поле — один и последним: после него фокус уже не наш.
            let textSteps = steps.filter(\.isTextDelivery)
            if let last = textSteps.last {
                if textSteps.count > 1 { repairs.insert(.droppedStep) }
                steps = steps.filter { !$0.isTextDelivery } + [last]
            }

            if steps.isEmpty {
                if rawSteps.isEmpty && !say.isEmpty {
                    return .plan(AssistantPlan(id: context.id, steps: [], say: say, repairs: repairs, fromCodeBlock: fromCodeBlock))
                }
                return .invalid(say: say.isEmpty ? nil : say,
                                reason: problem ?? T("В плане нет ни шагов, ни ответа", "The plan has neither steps nor an answer"))
            }

            checkDates(steps)
            return .plan(AssistantPlan(id: context.id, steps: steps, say: say, repairs: repairs, fromCodeBlock: fromCodeBlock))
        }

        // MARK: Шаг

        private mutating func step(_ raw: Any) throws -> AssistantStep {
            guard let dict = raw as? [String: Any] else {
                throw Invalid(reason: T("Шаг плана — не объект", "A plan step is not an object"))
            }
            args = Self.lowercasedKeys(dict)
            // Аргументы, вложенные в "args"/"params", поднимаются к шагу.
            if let nested = aliased(args, ["args", "params", "arguments"]) as? [String: Any] {
                args.merge(Self.lowercasedKeys(nested)) { outer, _ in outer }
            }
            guard let rawName = (args["do"] ?? aliased(args, ["tool", "action"])) as? String else {
                throw Invalid(reason: T("У шага нет инструмента", "A step has no tool"))
            }
            guard let (name, repair) = AssistantParser.resolveTool(rawName) else {
                throw Invalid(reason: T("Неизвестный инструмент", "Unknown tool"))
            }
            if let repair { repairs.insert(repair) }
            tool = name

            switch name {
            case "text.insert":
                return .textInsert(text: try text("text", ["content", "body", "value", "message"], max: 20_000)!)
            case "text.replace":
                guard context.hasSelection else {
                    throw Invalid(reason: T("text.replace без выделения", "text.replace without a selection"))
                }
                return .textReplace(text: try text("text", ["content", "body", "value", "message"], max: 20_000)!)
            case "reminder.add":
                let title = try text("title", ["name", "text", "content", "task"], max: 200)!
                let due = try date("due", ["time", "at", "when", "date", "datetime", "due_date", "deadline"])
                return .reminderAdd(title: title, due: due)
            case "calendar.add":
                let title = try text("title", ["name", "summary", "text"], max: 200)!
                guard let start = try date("start", ["time", "at", "when", "date", "datetime", "from", "begin", "start_time"]) else {
                    throw missing("start")
                }
                let end = adjusted(end: try date("end", ["to", "until", "end_time", "finish"]), start: start)
                let place = try text("place", ["location", "where", "venue", "address"], max: 200, required: false)
                return .calendarAdd(title: title, start: start, end: end, place: place)
            case "note.add":
                let body = try text("body", ["text", "content", "note"], max: 4_000, required: false)
                var title = try text("title", ["name", "heading", "subject"], max: 200, required: body == nil)
                if title == nil, let body {
                    // Заметка без заголовка — заголовком становится первая строка.
                    title = body.split(whereSeparator: \.isNewline).first.map { String($0.prefix(80)).trimmingCharacters(in: .whitespaces) }
                    repairs.insert(.aliasedArgument)
                }
                guard let title, !title.isEmpty else { throw missing("title") }
                return .noteAdd(title: title, body: body)
            case "timer.set":
                var seconds = try number("seconds", ["duration", "sec", "secs"])
                if seconds == nil, let minutes = try number("minutes", ["min", "mins"]) {
                    seconds = minutes * 60
                    repairs.insert(.aliasedArgument)
                }
                guard let seconds else { throw missing("seconds") }
                guard let value = Int(exactly: seconds.rounded()), (5...86_400).contains(value) else {
                    throw Invalid(reason: T("timer.set: seconds вне 5…86400", "timer.set: seconds outside 5…86400"))
                }
                let label = try text("label", ["title", "name", "text"], max: 200, required: false)
                return .timerSet(seconds: value, label: label)
            case "app.open":
                return .appOpen(name: try text("name", ["app", "application", "title"], max: 200)!)
            case "url.open":
                let raw = try text("url", ["link", "href", "address"], max: 4_096)!
                guard let url = URL(string: raw), url.scheme?.lowercased() == "https",
                      let host = url.host(percentEncoded: false), !host.isEmpty,
                      url.user(percentEncoded: false) == nil, url.password(percentEncoded: false) == nil else {
                    throw Invalid(reason: T("url.open: только https-ссылка без логина", "url.open: https links without credentials only"))
                }
                return .urlOpen(url)
            case "volume.set":
                guard let level = try number("level", ["volume", "value", "percent"]) else { throw missing("level") }
                guard let value = Int(exactly: level.rounded()), (0...100).contains(value) else {
                    throw Invalid(reason: T("volume.set: level вне 0…100", "volume.set: level outside 0…100"))
                }
                return .volumeSet(level: value)
            case "message.draft":
                let to = try text("to", ["recipient", "who", "contact", "name"], max: 200)!
                let body = try text("text", ["body", "content", "message"], max: 20_000)!
                return .messageDraft(to: to, text: body)
            case "clarify":
                return .clarify(question: try text("question", ["text", "q", "ask", "message"], max: 500)!)
            case "edit":
                let ref = try reference()
                let title = try text("title", ["name", "new_title"], max: 200, required: false)
                let due = try date("due", ["time", "at", "when", "date"])
                let start = try date("start", ["from", "begin"])
                var end = try date("end", ["to", "until"])
                if let start { end = adjusted(end: end, start: start) }
                guard title != nil || due != nil || start != nil || end != nil else {
                    throw Invalid(reason: T("edit: нечего менять", "edit: nothing to change"))
                }
                return .edit(ref: ref, title: title, due: due, start: start, end: end)
            case "undo":
                return .undo(ref: try reference())
            default:
                throw Invalid(reason: T("Неизвестный инструмент", "Unknown tool"))
            }
        }

        // MARK: Аргументы

        private func missing(_ key: String) -> Invalid {
            Invalid(reason: T("\(tool): нет «\(key)»", "\(tool): no \(key)"))
        }

        /// Значение по имени или его алиасу; алиас записывается косметическим ремонтом.
        private mutating func value(_ key: String, _ aliases: [String]) -> Any? {
            if let v = args[key], !(v is NSNull) { return v }
            if let v = aliased(args, aliases) { return v }
            return nil
        }

        private mutating func aliased(_ dict: [String: Any], _ keys: [String]) -> Any? {
            for key in keys {
                if let v = dict[key], !(v is NSNull) {
                    repairs.insert(.aliasedArgument)
                    return v
                }
            }
            return nil
        }

        private mutating func text(_ key: String, _ aliases: [String], max: Int, required: Bool = true) throws -> String? {
            guard let raw = value(key, aliases) else {
                if required { throw missing(key) }
                return nil
            }
            var text: String
            switch raw {
            case let s as String: text = s
            case let n as NSNumber where !Self.isBool(n): text = n.stringValue
            default: throw Invalid(reason: T("\(tool): «\(key)» не текст", "\(tool): \(key) is not text"))
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let n = Self.blockNumber(text) {
                guard let block = resolve(n) else {
                    throw Invalid(reason: T("\(tool): блок @\(n) не найден", "\(tool): block @\(n) not found"))
                }
                if block.truncated { repairs.insert(.truncated) }
                text = block.text
            }
            text = Self.clean(text)
            if text.isEmpty {
                if required { throw missing(key) }
                return nil
            }
            // Модель повторила образец из промпта вместо значения.
            if text == "…" || text == "..." {
                throw Invalid(reason: T("\(tool): «\(key)» — заглушка", "\(tool): \(key) is a placeholder"))
            }
            if text.count > max {
                throw Invalid(reason: T("\(tool): «\(key)» длиннее \(max) символов", "\(tool): \(key) is longer than \(max) characters"))
            }
            return text
        }

        private mutating func date(_ key: String, _ aliases: [String]) throws -> AssistantDate? {
            var raw = value(key, aliases)
            // «date» и «time» по отдельности — склеиваем, если по имени поля ничего нет.
            if args[key] == nil, aliases.contains("date"), let day = args["date"] as? String, let time = args["time"] as? String,
               day.count == 10, !time.isEmpty, time.first?.isNumber == true {
                raw = day + "T" + time
            }
            guard let raw else { return nil }
            guard let string = raw as? String else {
                throw Invalid(reason: T("\(tool): «\(key)» не дата", "\(tool): \(key) is not a date"))
            }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            guard let (date, noOffset) = AssistantParser.parseDate(trimmed, timeZone: context.timeZone) else {
                throw Invalid(reason: T("\(tool): «\(key)» не в ISO 8601", "\(tool): \(key) is not ISO 8601"))
            }
            if noOffset { repairs.insert(.noOffset) }
            return date
        }

        /// Число или строка с числом («600», «50%»). Слова вроде «10 мин» не принимаются.
        private mutating func number(_ key: String, _ aliases: [String]) throws -> Double? {
            guard let raw = value(key, aliases) else { return nil }
            if let n = raw as? NSNumber, !Self.isBool(n), n.doubleValue.isFinite { return n.doubleValue }
            if let s = raw as? String {
                var t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
                if t.hasSuffix("%") { t.removeLast() }
                if let d = Double(t.trimmingCharacters(in: .whitespaces)), d.isFinite { return d }
            }
            throw Invalid(reason: T("\(tool): «\(key)» не число", "\(tool): \(key) is not a number"))
        }

        /// Ссылка A1… на недавнее действие Intact; чужую или устаревшую не принимаем.
        private mutating func reference() throws -> String {
            let raw = try text("ref", ["target", "item", "id"], max: 32)!
            guard let known = context.knownRefs.first(where: { $0.caseInsensitiveCompare(raw) == .orderedSame }) else {
                throw Invalid(reason: T("\(tool): ссылки \(raw) нет среди недавних действий", "\(tool): \(raw) is not a recent action"))
            }
            return known
        }

        /// Конец не позже начала — модель ошиблась: час по умолчанию. У события на
        /// весь день конец в тот же день просто не нужен.
        private mutating func adjusted(end: AssistantDate?, start: AssistantDate) -> AssistantDate? {
            guard let end else { return nil }
            if end.hasTime != start.hasTime {
                repairs.insert(.endAdjusted)
                return nil
            }
            guard end.date <= start.date else { return end }
            if !start.hasTime {
                if end.date < start.date { repairs.insert(.endAdjusted) }
                return nil
            }
            repairs.insert(.endAdjusted)
            return AssistantDate(date: start.date.addingTimeInterval(3600), hasTime: true)
        }

        private mutating func sayText(_ root: [String: Any]) -> String {
            let raw = root["say"] ?? root["answer"] ?? root["reply"]
            var say: String
            switch raw {
            case let s as String: say = s
            case let n as NSNumber where !Self.isBool(n): say = n.stringValue
            default: return ""
            }
            say = say.trimmingCharacters(in: .whitespacesAndNewlines)
            if say == "…" || say == "..." { return "" }
            // Длинный ответ модель тоже может вынести в блок; недописанный блок —
            // `truncated`, иначе ранний приём показал бы полответа.
            if let n = Self.blockNumber(say) {
                guard let block = resolve(n) else { return "" }
                if block.truncated { repairs.insert(.truncated) }
                say = block.text
            }
            return Self.clean(say)
        }

        // MARK: Даты

        /// Срок в прошлом или дальше года, либо расхождение с локальным разбором фразы
        /// («через час», «в пятницу») — повод показать план человеку, а не исполнять.
        private mutating func checkDates(_ steps: [AssistantStep]) {
            var dates: [AssistantDate] = []
            for step in steps {
                switch step {
                case .reminderAdd(_, let due?): dates.append(due)
                case .calendarAdd(_, let start, _, _): dates.append(start)
                case .edit(_, _, let due, let start, _): dates += [due, start].compactMap { $0 }
                default: break
                }
            }
            guard !dates.isEmpty else { return }
            let now = context.now
            let horizon = now.addingTimeInterval(366 * 86_400)
            let today = calendar.startOfDay(for: now)
            let outOfRange = dates.contains { date in
                date.hasTime
                    ? date.date < now.addingTimeInterval(-60) || date.date > horizon
                    : calendar.startOfDay(for: date.date) < today || date.date > horizon
            }
            if outOfRange { repairs.insert(.dateSanity) }
            if let check = LocalDateCheck(utterance: context.utterance, now: now, calendar: calendar),
               !dates.contains(where: check.agrees) {
                repairs.insert(.dateSanity)
            }
        }

        // MARK: Мелочи

        private static func lowercasedKeys(_ dict: [String: Any]) -> [String: Any] {
            var out: [String: Any] = [:]
            for (key, value) in dict {
                let k = key.trimmingCharacters(in: .whitespaces).lowercased()
                if out[k] == nil { out[k] = value }
            }
            return out
        }

        /// `true` из JSON — тоже NSNumber, и без этой проверки стал бы громкостью 1.
        private static func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

        /// Управляющие символы из JSON (`\u001b`, `\r`, `\u0000`) не видны на карточке,
        /// а в терминале `\r` — это Enter, а `ESC[201~` закрывает защищённую вставку.
        /// `\r` становится переводом строки, чтобы движок видел многострочность;
        /// остальные управляющие и символы смены направления текста выбрасываются.
        static func clean(_ text: String) -> String {
            guard text.unicodeScalars.contains(where: isControl) else { return text }
            let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            return String(String.UnicodeScalarView(unified.unicodeScalars.filter { !isControl($0) }))
        }

        private static func isControl(_ c: Unicode.Scalar) -> Bool {
            switch c.value {
            case 0x0A, 0x09: return false
            case 0x00...0x1F, 0x7F...0x9F, 0x202A...0x202E, 0x2066...0x2069: return true
            default: return false
            }
        }

        /// «@1» → 1.
        static func blockNumber(_ text: String) -> Int? {
            guard text.hasPrefix("@"), text.count <= 3 else { return nil }
            return Int(text.dropFirst()).flatMap { $0 >= 1 ? $0 : nil }
        }
    }

    /// ISO 8601: `2026-09-25T12:14+06:00`, с секундами и без, `Z`, `+0600`. Без
    /// смещения время читается в поясе нажатия (`noOffset`). Одна дата без времени —
    /// начало этого дня в поясе нажатия: напоминание без будильника, событие на весь день.
    static func parseDate(_ text: String, timeZone: TimeZone) -> (AssistantDate, noOffset: Bool)? {
        let s = Array(text.utf8)
        var i = 0
        func digits(_ minCount: Int, _ maxCount: Int) -> Int? {
            var value = 0, count = 0
            while count < maxCount, i < s.count, s[i] >= 48, s[i] <= 57 {
                value = value * 10 + Int(s[i] - 48)
                i += 1
                count += 1
            }
            return count >= minCount ? value : nil
        }
        func eat(_ c: UInt8) -> Bool {
            guard i < s.count, s[i] == c else { return false }
            i += 1
            return true
        }
        guard let year = digits(4, 4), eat(0x2D), let month = digits(2, 2), eat(0x2D), let day = digits(2, 2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        var components = DateComponents(year: year, month: month, day: day)
        var hasTime = false
        var offset: Int?
        if i < s.count {
            guard eat(0x54) || eat(0x74) || eat(0x20),   // T, t, пробел
                  let hour = digits(1, 2), eat(0x3A), let minute = digits(2, 2),
                  (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            components.hour = hour
            components.minute = minute
            if eat(0x3A) {
                guard let second = digits(2, 2), second <= 60 else { return nil }
                components.second = min(second, 59)
                if eat(0x2E) { _ = digits(1, 9) }   // доли секунды не нужны
            }
            hasTime = true
            if eat(0x5A) || eat(0x7A) {   // Z
                offset = 0
            } else if i < s.count, s[i] == 0x2B || s[i] == 0x2D {
                let sign = s[i] == 0x2D ? -1 : 1
                i += 1
                guard let hours = digits(2, 2), hours <= 14 else { return nil }
                _ = eat(0x3A)
                let minutes = digits(2, 2) ?? 0
                offset = sign * (hours * 3600 + minutes * 60)
            }
            guard i == s.count else { return nil }
        }

        if let offset {
            guard let zone = TimeZone(secondsFromGMT: offset) else { return nil }
            calendar.timeZone = zone
        } else {
            calendar.timeZone = timeZone
        }
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }   // 31 сентября не бывает
        return (AssistantDate(date: date, hasTime: hasTime), hasTime && offset == nil)
    }
}

// MARK: - Локальная сверка даты

extension AssistantParser {

    /// Сверка даты модели с тем, что можно уверенно прочитать в самой фразе:
    /// «через N минут/часов», «сегодня/завтра/послезавтра», дни недели, «в N (утра/
    /// дня/вечера/ночи)», «в N:MM». Модель по-прежнему считает сама; сверка только
    /// ловит явный промах (+2 часа вместо «через час») и отправляет план на карточку.
    ///
    /// Двусмысленность разворачивается в набор вариантов («в 8» — 8:00 или 20:00),
    /// и дата модели засчитывается, если совпала с любым: ложная тревога хуже
    /// пропущенной, она приучает не читать карточку.
    struct LocalDateCheck {
        private var instants: [Date] = []
        private var days: Set<Date>?
        private var times: Set<Int>?
        private let calendar: Calendar

        init?(utterance: String, now: Date, calendar: Calendar) {
            self.calendar = calendar
            let words = Self.tokens(utterance)
            guard !words.isEmpty else { return nil }
            // Промпт даёт модели время с точностью до минуты — от неё и считаем.
            let minute = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
            let weekdayToday = calendar.component(.weekday, from: now)
            var dayOffsets: Set<Int> = []
            var clock: Set<Int> = []
            for (index, word) in words.enumerated() {
                if word == "через", let seconds = Self.span(words, index + 1) {
                    instants.append(minute.addingTimeInterval(seconds))
                } else if let offset = Self.dayWords[word] {
                    dayOffsets.insert(offset)
                } else if let weekday = Self.weekdays[word] {
                    // Ближайший такой день; сегодняшний — если время ещё впереди,
                    // а какое время, здесь не всегда известно: годятся оба.
                    let delta = (weekday - weekdayToday + 7) % 7
                    dayOffsets.insert(delta)
                    if delta == 0 { dayOffsets.insert(7) }
                } else if word == "в" || word == "во" || word == "к", let minutes = Self.clock(words, index + 1) {
                    clock.formUnion(minutes)
                }
            }
            // «в следующую пятницу», «через неделю», «5 октября» — день здесь не
            // вычислить уверенно; время суток при этом сверять можно.
            let vague = words.contains { word in Self.vagueStems.contains { word.hasPrefix($0) } }
            let today = calendar.startOfDay(for: now)
            if !vague && !dayOffsets.isEmpty {
                days = Set(dayOffsets.compactMap { calendar.date(byAdding: .day, value: $0, to: today) })
            }
            if !clock.isEmpty { times = clock }
            if instants.isEmpty && days == nil && times == nil { return nil }
        }

        func agrees(_ date: AssistantDate) -> Bool {
            if date.hasTime && instants.contains(where: { abs($0.timeIntervalSince(date.date)) <= 60 }) { return true }
            guard days != nil || times != nil else { return false }
            if let days, !days.contains(calendar.startOfDay(for: date.date)) { return false }
            if let times {
                guard date.hasTime else { return false }
                let parts = calendar.dateComponents([.hour, .minute], from: date.date)
                guard let hour = parts.hour, let minute = parts.minute, times.contains(hour * 60 + minute) else { return false }
            }
            return true
        }

        // MARK: Словарь

        private static let dayWords = ["сегодня": 0, "завтра": 1, "послезавтра": 2]
        /// Номера дней недели `Calendar` (воскресенье — 1).
        private static let weekdays = [
            "понедельник": 2, "вторник": 3, "среду": 4, "среда": 4, "четверг": 5,
            "пятницу": 6, "пятница": 6, "субботу": 7, "суббота": 7, "воскресенье": 1,
        ]
        private static let vagueStems = [
            "следующ", "кажд", "прошл", "недел", "месяц", "числа", "январ", "феврал", "март", "апрел",
            "мая", "июн", "июл", "август", "сентябр", "октябр", "ноябр", "декабр",
        ]
        private static let units = [
            "один": 1, "одну": 1, "одна": 1, "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5, "шесть": 6,
            "семь": 7, "восемь": 8, "девять": 9, "десять": 10, "одиннадцать": 11, "двенадцать": 12,
            "тринадцать": 13, "четырнадцать": 14, "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17,
            "восемнадцать": 18, "девятнадцать": 19, "пару": 2, "пара": 2,
        ]
        private static let tens = ["двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50]
        private static let minuteWords: Set<String> = ["минута", "минуту", "минуты", "минут", "мин", "минутку", "минуток"]
        private static let hourWords: Set<String> = ["час", "часа", "часов", "ч", "часик", "часика"]
        private static let qualifiers: Set<String> = ["утра", "дня", "вечера", "ночи"]

        private static func tokens(_ text: String) -> [String] {
            let punctuation = CharacterSet(charactersIn: ".,!?;:«»\"'()[]—–-…“”„")
            return text.lowercased().replacingOccurrences(of: "ё", with: "е")
                .split(whereSeparator: \.isWhitespace)
                .map { $0.trimmingCharacters(in: punctuation) }
                .filter { !$0.isEmpty }
        }

        /// Число цифрами («15», «1,5») или словами («двадцать пять») и сколько слов оно заняло.
        private static func number(_ words: [String], _ i: Int) -> (Double, Int)? {
            guard i < words.count else { return nil }
            let word = words[i]
            if word.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "," || $0 == ".") }),
               let value = Double(word.replacingOccurrences(of: ",", with: ".")) {
                return (value, 1)
            }
            if let ten = tens[word] {
                if i + 1 < words.count, let unit = units[words[i + 1]], unit < 10 { return (Double(ten + unit), 2) }
                return (Double(ten), 1)
            }
            if let unit = units[word] { return (Double(unit), 1) }
            return nil
        }

        private static func unitSeconds(_ word: String) -> Double? {
            if minuteWords.contains(word) { return 60 }
            if hourWords.contains(word) { return 3600 }
            return nil
        }

        /// Интервал после «через»: «час», «полчаса», «полтора часа», «15 минут»,
        /// «два с половиной часа», «1 час 30 минут».
        private static func span(_ words: [String], _ i: Int) -> TimeInterval? {
            guard i < words.count else { return nil }
            let word = words[i]
            if word == "полчаса" || word == "полчасика" { return 1800 }
            var amount = 1.0   // «через час»
            var k = i
            if word == "полтора" || word == "полторы" {
                amount = 1.5
                k += 1
            } else if let (value, used) = number(words, i) {
                amount = value
                k += used
                if k + 1 < words.count, words[k] == "с", words[k + 1] == "половиной" {
                    amount += 0.5
                    k += 2
                }
            }
            guard k < words.count, let unit = unitSeconds(words[k]) else { return nil }
            // Минуты после часов: «1 час 30 минут». «Через час двадцать» без единицы
            // не угадываем — лучше не сверять, чем поднять ложную тревогу.
            if unit == 3600, let (minutes, used) = number(words, k + 1) {
                guard k + 1 + used < words.count, minuteWords.contains(words[k + 1 + used]) else { return nil }
                return amount * unit + minutes * 60
            }
            return amount * unit
        }

        /// Время суток после «в»/«к» — набор вариантов в минутах от полуночи.
        private static func clock(_ words: [String], _ i: Int) -> Set<Int>? {
            guard i < words.count else { return nil }
            let word = words[i]
            if word == "полдень" { return [720] }
            if word == "полночь" { return [0] }
            var hour: Int
            var minute = 0
            var k: Int
            var certain = false
            let pieces = word.split(whereSeparator: { $0 == ":" || $0 == "." })
            if pieces.count == 2, pieces[1].count == 2, let h = Int(pieces[0]), let m = Int(pieces[1]), (0...23).contains(h), (0...59).contains(m) {
                hour = h; minute = m; k = i + 1; certain = true           // «в 18:30»
            } else if word == "час" {
                hour = 1; k = i + 1                                         // «в час дня»
            } else if let (value, used) = number(words, i), value == value.rounded(), (0...23).contains(value) {
                hour = Int(value); k = i + used
            } else {
                return nil
            }
            if !certain, k < words.count, hourWords.contains(words[k]) {
                certain = true                                              // «в 8 часов [30 минут]»
                k += 1
                if let (value, used) = number(words, k), k + used < words.count, minuteWords.contains(words[k + used]),
                   value == value.rounded(), (0...59).contains(value) {
                    minute = Int(value)
                    k += used + 1
                }
            }
            let next = k < words.count ? words[k] : nil
            if let next, qualifiers.contains(next) {
                let h: Int
                switch next {
                case "утра": h = hour == 12 ? 0 : hour
                case "дня": h = hour < 12 ? hour + 12 : hour
                case "вечера": h = hour < 12 ? hour + 12 : (hour == 12 ? 0 : hour)
                default: h = hour == 12 ? 0 : (6...11).contains(hour) ? hour + 12 : hour   // ночи
                }
                return (0...23).contains(h) ? [h * 60 + minute] : nil
            }
            // «в 3 магазинах», «в 2 раза» — не время. Верим, только если за числом
            // ничего нет, идёт день или глагол («в 8 позвонить»).
            if !certain {
                guard let next else { return Self.ambiguous(hour, minute) }
                let plausible = dayWords[next] != nil || weekdays[next] != nil || ["и", "а", "ровно"].contains(next)
                    || next.hasSuffix("ть") || next.hasSuffix("ться") || next.hasSuffix("чь")
                guard plausible else { return nil }
            }
            return Self.ambiguous(hour, minute)
        }

        /// «в 8» без «утра/вечера» — 8:00 или 20:00; «в 12» — полдень или полночь.
        private static func ambiguous(_ hour: Int, _ minute: Int) -> Set<Int> {
            switch hour {
            case 1...11: return [hour * 60 + minute, (hour + 12) * 60 + minute]
            case 12: return [12 * 60 + minute, minute]
            default: return [hour * 60 + minute]
            }
        }
    }
}
