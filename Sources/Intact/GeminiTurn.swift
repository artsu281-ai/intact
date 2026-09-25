import AppKit
import ApplicationServices
import Foundation

/// Один ход ассистента в Gemini.app: промпт с меткой `[INTACT id]` — ответ, найденный
/// по этому id. В отличие от `stream`, здесь ничего не угадывается по «последнему тексту»:
/// ответ — это всё, что лежит в дереве ПОСЛЕ нашего сообщения.
///
/// Замер 25.09.2026 на живой копии (AGENTS_SYNC 4.7):
///   - ответ целиком лежит в `AXDescription` одного `AXStaticText` строки ответа, сырым
///     markdown вместе с ```-оградами — парсеру достаточно строки;
///   - короткое сообщение пользователя — `AXButton` `userMessage.expandButton` с текстом
///     в описании, длинное (6 КБ) — `AXStaticText` с текстом в значении; ищем по обоим;
///   - кнопки различаются по `AXIdentifier`: `send_button` («Отправить», help «Отправить
///     (Return)»), `stop_button` («Остановить генерацию ответа»), `mic_button` (пропадает,
///     пока идёт генерация);
///   - промпт 6,3 КБ поле принимает целиком; генерация 3,9–5,5 с; фокус не уходит.
extension GeminiAIProvider {

    /// - Parameters:
    ///   - isComplete: парсер говорит, что в тексте уже есть валидный план с нашим id —
    ///     тогда ответ принимается, не дожидаясь конца генерации (двух одинаковых опросов
    ///     подряд достаточно).
    @discardableResult
    func runTurn(
        prompt: String,
        id: String,
        timeout: TimeInterval,
        isComplete: @escaping (String) -> Bool,
        completion: @escaping (Result<String, AIError>) -> Void
    ) -> AITask {
        guard isReady else {
            completion(.failure(.providerUnavailable))
            return AITask()
        }
        let tag = "[INTACT \(id)]"
        guard prompt.hasPrefix(tag) else {
            completion(.failure(.badResponse))
            return AITask()
        }

        let cancelFlag = TurnFlag()
        let task = AITask { cancelFlag.set() }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var reported = false
            var gateHeld = false
            let finish: (Result<String, AIError>) -> Void = { result in
                guard !reported else { return }
                reported = true
                if gateHeld { GeminiComposerGate.shared.release() }
                completion(result)
            }
            guard let self else { finish(.failure(.providerUnavailable)); return }
            let started = Date()

            // Промпт ассистента несёт выделение и заголовок окна — в личный Gemini
            // пользователя (когда копия не выбрана или пропала) он не уходит никогда.
            guard GeminiBridgeService.bundleIdentifier != GeminiBridgeService.mainBundleIdentifier else {
                Log.write("Ассистент: копия Gemini не найдена — в основной Gemini не пишу")
                finish(.failure(.notConfigured))
                return
            }

            // Поле ввода общее с распознаванием: сначала пусть оно закончит уборку.
            GeminiSTTService.shared.waitUntilIdle()
            if cancelFlag.isSet { finish(.failure(.timeout)); return }
            // Один пишущий в поле за раз: чат, сводка и причёсывание (`stream`) иначе
            // перезаписывали бы наш промпт между записью и «Отправить».
            guard GeminiComposerGate.shared.acquire("assistant", timeout: 8) else {
                Log.write("Ассистент: поле Gemini занято другим запросом (\(GeminiComposerGate.shared.holder)) — ход не начат")
                finish(.failure(.providerUnavailable))
                return
            }
            gateHeld = true
            if cancelFlag.isSet { finish(.failure(.timeout)); return }

            let previousFrontmost = NSWorkspace.shared.frontmostApplication
            guard let composer = self.acquireComposer(previousFrontmost: previousFrontmost) else {
                finish(.failure(.providerUnavailable))
                return
            }
            let (pid, window, textArea) = composer

            // Идёт чужая генерация (чат, сводка, «Джеминай») — ждём до 3 с. Её «Остановить»
            // не наша, нажимать её нельзя: оборвали бы чужой ответ.
            let busyDeadline = Date().addingTimeInterval(3)
            while Self.button(in: window, identifier: "stop_button") != nil {
                if Date() > busyDeadline || cancelFlag.isSet {
                    Log.write("Ассистент: Gemini занят другим ответом — ход не начат")
                    finish(.failure(.providerUnavailable))
                    return
                }
                Thread.sleep(forTimeInterval: 0.15)
            }

            // Запись промпта: строгая проверка чтением обратно — начало с нашей метки
            // и длина почти та же (веб-поле может схлопнуть пробелы).
            guard Self.insertAsUserInput(prompt, into: textArea) else {
                finish(.failure(.providerUnavailable))
                return
            }
            var written = false
            for _ in 0..<12 {
                Thread.sleep(forTimeInterval: 0.05)
                let back = Self.value(of: textArea)
                let expected = prompt.filter { !$0.isWhitespace }.count
                let got = back.filter { !$0.isWhitespace }.count
                if back.hasPrefix(tag), abs(got - expected) <= max(2, expected / 50) { written = true; break }
            }
            guard written, !cancelFlag.isSet else {
                Self.clear(textArea)
                Log.write("Ассистент: Gemini не принял промпт" + (cancelFlag.isSet ? " (отменено)" : ""))
                finish(.failure(cancelFlag.isSet ? .timeout : .providerUnavailable))
                return
            }

            // Отправка. Кнопка по идентификатору; поиск по подстроке «Отправить» ловил
            // «Отправить отзыв». Проверка — поле опустело.
            // «Отправлено» — поле прочитано И пустое: неудачное чтение AX тоже даёт пустую
            // строку, и его нельзя принять за отправку.
            func sentNow() -> Bool {
                var ref: CFTypeRef?
                guard AXUIElementCopyAttributeValue(textArea, kAXValueAttribute as CFString, &ref) == .success else { return false }
                return ((ref as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            var sent = false
            if let send = Self.button(in: window, identifier: "send_button") ?? Self.button(in: window, exactDescription: ["Отправить", "Send"]) {
                AXUIElementPerformAction(send, kAXPressAction as CFString)
                for _ in 0..<15 where !sent && !cancelFlag.isSet { Thread.sleep(forTimeInterval: 0.1); sent = sentNow() }
            }
            if !sent && cancelFlag.isSet {
                // ⎋ до отправки: Enter не жмём, поле чистим. Нажатие кнопки могло всё же
                // дойти с опозданием — тогда глушим свою генерацию.
                Self.clear(textArea)
                Self.restoreFocusIfStolen(pid: pid, previous: previousFrontmost)
                Self.stopOwnGeneration(in: window, waitForAppear: 1.5)
                Log.write("Ассистент: ход отменён до отправки")
                finish(.failure(.timeout))
                return
            }
            if !sent {
                Log.write("Ассистент: кнопка отправки не сработала — пробую Enter")
                let src = CGEventSource(stateID: .combinedSessionState)
                CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)?.postToPid(pid)
                CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)?.postToPid(pid)
                for _ in 0..<15 where !sent { Thread.sleep(forTimeInterval: 0.1); sent = sentNow() }
            }
            Self.restoreFocusIfStolen(pid: pid, previous: previousFrontmost)
            guard sent else {
                Self.clear(textArea)
                Log.write("Ассистент: сообщение в Gemini не ушло — поле очищено")
                finish(.failure(.providerUnavailable))
                return
            }
            let sentAt = Date()
            let rowsContainer = Self.rowsContainer(in: window)
            var slowestPoll: TimeInterval = 0

            // Опрос ответа. Генерация закончилась, когда «Остановить» была видна и пропала;
            // если её так и не увидели — ждём 6 с стабильности (раздел 4.4).
            var sawStop = false
            var pollsWithoutStop = 0
            var last = ""
            var stablePolls = 0
            var lastChange = Date()
            let deadline = sentAt.addingTimeInterval(timeout)
            while true {
                Thread.sleep(forTimeInterval: 0.15)
                Self.restoreFocusIfStolen(pid: pid, previous: previousFrontmost)
                let stop = Self.button(in: window, identifier: "stop_button")
                if stop != nil { sawStop = true; pollsWithoutStop = 0 } else { pollsWithoutStop += 1 }

                if cancelFlag.isSet || Date() > deadline {
                    // Свой ход обрываем: иначе Gemini допишет ответ, которого никто не ждёт,
                    // и следующий запрос увидит чужую генерацию. Отмена сразу после отправки
                    // приходит раньше, чем появляется «Остановить», — ждём её до 1,5 с.
                    Self.stopOwnGeneration(in: window, waitForAppear: (stop == nil && !sawStop) ? 1.5 : 0)
                    Log.write("Ассистент: ход \(cancelFlag.isSet ? "отменён" : "не уложился в \(Int(timeout)) с")")
                    finish(.failure(.timeout))
                    return
                }

                let pollStart = Date()
                let answer = rowsContainer.map { Self.answerText(after: tag, rows: $0) } ?? Self.answerText(after: tag, in: window)
                slowestPoll = max(slowestPoll, Date().timeIntervalSince(pollStart))
                if answer != last {
                    last = answer
                    stablePolls = 0
                    lastChange = Date()
                } else {
                    stablePolls += 1
                }
                guard !answer.isEmpty else { continue }

                let generating = stop != nil
                // Генерация кончилась — «Остановить» пропала на два опроса подряд (один
                // промах AX ещё не конец) и текст не менялся.
                let done = (sawStop && pollsWithoutStop >= 2 && stablePolls >= 1)
                    || (!sawStop && Date().timeIntervalSince(lastChange) >= 6)
                // Ранний приём: план с нашим id уже валиден и не менялся между опросами.
                let early = stablePolls >= 1 && isComplete(answer)
                if done || early {
                    if early && generating {
                        // План уже есть, а Gemini ещё что-то дописывает (обычно прозу после
                        // JSON). Ход наш — останавливаем, чтобы не держать поле занятым.
                        Self.stopOwnGeneration(in: window, waitForAppear: 0)
                    }
                    let rowCount = rowsContainer.map { Self.rows(of: $0).count } ?? -1
                    Log.write("Ассистент: ответ Gemini \(answer.count) симв. за \(Int(Date().timeIntervalSince(sentAt) * 1000)) мс"
                              + " (всего \(Int(Date().timeIntervalSince(started) * 1000)) мс\(early && generating ? ", принят досрочно" : "")"
                              + "; строк в чате \(rowCount), самый долгий опрос \(Int(slowestPoll * 1000)) мс, копия \(Self.bridgeVersion()))")
                    finish(.success(answer))
                    return
                }
            }
        }
        return task
    }

    // MARK: - Дерево

    /// Контейнер строк переписки: элемент с атрибутом `AXRows`. Замер 25.09: список строк
    /// отдаётся мгновенно, а полный обход дерева с чтением каждого сообщения — 85–96 мс
    /// уже на 10 строках и растёт весь день (Intact не начинает новых чатов).
    static func rowsContainer(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 30 { return nil }
        let role = string(element, kAXRoleAttribute)
        if role == "AXOutline" || role == "AXRow" { return nil }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRowsAttribute as CFString, &ref) == .success,
           let rows = ref as? [AXUIElement], !rows.isEmpty {
            return element
        }
        for child in children(element) {
            if let found = rowsContainer(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    static func rows(of container: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(container, kAXRowsAttribute as CFString, &ref)
        return ref as? [AXUIElement] ?? []
    }

    /// Ответ на наше сообщение, читая строки С КОНЦА: только строки после нашей и до
    /// следующего чужого сообщения. Прошлые промпты и ответы не копируются вовсе.
    static func answerText(after tag: String, rows container: AXUIElement) -> String {
        var collected: [[String]] = []
        for row in rows(of: container).reversed() {
            let content = rowContent(row, tag: tag)
            switch content.kind {
            case .ours:
                return collected.reversed().flatMap { $0 }.joined(separator: "\n")
            case .otherUser:
                // Сообщение после нашего — всё, что ниже него, уже не наш ответ.
                collected.removeAll()
            case .answer:
                if !content.texts.isEmpty { collected.append(content.texts) }
            }
        }
        return ""
    }

    private enum RowKind { case ours, otherUser, answer }

    /// Что в строке: наше сообщение, чужое сообщение или ответ. Короткое сообщение
    /// пользователя — кнопка `userMessage.expandButton` с текстом в описании, длинное —
    /// `AXStaticText` с текстом в значении и без описания; ответ — `AXStaticText` с
    /// markdown в описании (значение — заглушка U+FFFC).
    private static func rowContent(_ row: AXUIElement, tag: String) -> (kind: RowKind, texts: [String]) {
        var texts: [String] = []
        var kind = RowKind.answer
        func walk(_ element: AXUIElement, depth: Int) {
            if depth > 20 || kind != .answer { return }
            let role = string(element, kAXRoleAttribute)
            if role == "AXButton" {
                if string(element, "AXIdentifier") == "userMessage.expandButton" {
                    kind = string(element, kAXDescriptionAttribute).hasPrefix(tag) ? .ours : .otherUser
                }
                return
            }
            if role == "AXStaticText" {
                let desc = string(element, kAXDescriptionAttribute)
                let value = string(element, kAXValueAttribute)
                // Наше длинное сообщение — текст в ЗНАЧЕНИИ; описание с меткой — это ответ,
                // который начался с её эха, его не путаем с нашим сообщением.
                if value.hasPrefix(tag) { kind = .ours; return }
                if desc.isEmpty, !value.isEmpty, value != "\u{FFFC}" {
                    // Длинное сообщение пользователя: чужое (наше поймано строкой выше).
                    kind = .otherUser
                    return
                }
                let text = (desc.isEmpty ? value : desc).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, text != "\u{FFFC}", !isDisclaimer(text) { texts.append(text) }
                return
            }
            for child in children(element) { walk(child, depth: depth + 1) }
        }
        walk(row, depth: 0)
        return (kind, texts)
    }

    /// Остановить СВОЮ генерацию и дождаться, пока «Остановить» пропадёт: шлюз
    /// отпускается после этого, иначе следующий писатель увидел бы нашу недописанную
    /// генерацию и принял бы её хвост за свой ответ.
    static func stopOwnGeneration(in window: AXUIElement, waitForAppear: TimeInterval) {
        var stop = button(in: window, identifier: "stop_button")
        if stop == nil, waitForAppear > 0 {
            let until = Date().addingTimeInterval(waitForAppear)
            while stop == nil, Date() < until {
                Thread.sleep(forTimeInterval: 0.1)
                stop = button(in: window, identifier: "stop_button")
            }
        }
        guard let stop else { return }
        AXUIElementPerformAction(stop, kAXPressAction as CFString)
        let until = Date().addingTimeInterval(2)
        while Date() < until, button(in: window, identifier: "stop_button") != nil {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    static func bridgeVersion() -> String {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: GeminiBridgeService.bundleIdentifier).first,
              let url = app.bundleURL else { return "?" }
        return Bundle(url: url)?.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// Текст ответа на наше сообщение: описания/значения всех текстовых узлов, которые
    /// идут в дереве ПОСЛЕ узла с нашей меткой. Кнопки (оценки, копирование) и
    /// дисклеймер «Gemini – это ИИ…» — не ответ.
    static func answerText(after tag: String, in window: AXUIElement) -> String {
        var passedOurMessage = false
        var parts: [String] = []
        func walk(_ element: AXUIElement, depth: Int) {
            if depth > 45 { return }
            let role = string(element, kAXRoleAttribute)
            if role == "AXOutline" { return }   // боковая панель с историей чатов
            let desc = string(element, kAXDescriptionAttribute)
            let value = string(element, kAXValueAttribute)
            let isOurMessage = (role == "AXButton" && string(element, "AXIdentifier") == "userMessage.expandButton" && desc.hasPrefix(tag))
                || (role == "AXStaticText" && value.hasPrefix(tag))
            if isOurMessage {
                // Ещё одно наше сообщение (повтор) — ответ считаем только после последнего.
                passedOurMessage = true
                parts.removeAll()
                return
            }
            if role == "AXButton" { return }
            if passedOurMessage, role == "AXStaticText" || role == "AXGroup" {
                let text = !desc.isEmpty ? desc : value
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != "\u{FFFC}", !isDisclaimer(trimmed), role == "AXStaticText" {
                    parts.append(trimmed)
                }
            }
            for child in children(element) { walk(child, depth: depth + 1) }
        }
        walk(window, depth: 0)
        return parts.joined(separator: "\n")
    }

    private static func isDisclaimer(_ text: String) -> Bool {
        text.hasPrefix("Gemini – это ИИ") || text.hasPrefix("Gemini is AI") || text.hasPrefix("Gemini can make mistakes")
    }

    /// Кнопки поля ввода (Отправить, Остановить, микрофон) живут вне строк переписки —
    /// строки не обходим: там сотни узлов и в том числе наши же сообщения.
    static func button(in element: AXUIElement, identifier: String, depth: Int = 0) -> AXUIElement? {
        if depth > 45 { return nil }
        let role = string(element, kAXRoleAttribute)
        if role == "AXOutline" || role == "AXRow" { return nil }
        if role == "AXButton" {
            return string(element, "AXIdentifier") == identifier ? element : nil
        }
        for child in children(element) {
            if let found = button(in: child, identifier: identifier, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Точное совпадение описания — подстрока «Отправить» совпадала с «Отправить отзыв».
    static func button(in element: AXUIElement, exactDescription names: [String], depth: Int = 0) -> AXUIElement? {
        if depth > 45 { return nil }
        let role = string(element, kAXRoleAttribute)
        if role == "AXOutline" || role == "AXRow" { return nil }
        if role == "AXButton" {
            return names.contains(string(element, kAXDescriptionAttribute)) ? element : nil
        }
        for child in children(element) {
            if let found = button(in: child, exactDescription: names, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Фокус возвращаем, только если он действительно ушёл к Gemini: безусловная
    /// активация отобрала бы его у приложения, в которое пользователь переключился сам.
    static func restoreFocusIfStolen(pid: pid_t, previous: NSRunningApplication?) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let previous, previous.processIdentifier != pid else { return }
        previous.activate()
    }

    private static func clear(_ textArea: AXUIElement) {
        _ = insertAsUserInput("", into: textArea)
    }

    private static func value(of element: AXUIElement) -> String {
        string(element, kAXValueAttribute)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        return ref as? String ?? ""
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref)
        return ref as? [AXUIElement] ?? []
    }
}

/// Флаг отмены, который пишут с главного потока, а читают с фонового.
private final class TurnFlag {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

/// Одно поле ввода Gemini — один пишущий за раз: ход ассистента, `stream` (чат, сводка,
/// причёсывание, ответ) и команда «Джеминай». Держится от записи промпта до конца ответа
/// (или до отказа). Ждать можно только вне главного потока.
final class GeminiComposerGate {
    static let shared = GeminiComposerGate()
    private let condition = NSCondition()
    private var busy = false
    private var holderLabel = ""

    var holder: String {
        condition.lock(); defer { condition.unlock() }
        return holderLabel
    }

    func acquire(_ label: String, timeout: TimeInterval) -> Bool {
        dispatchPrecondition(condition: .notOnQueue(.main))
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while busy {
            // Таймаут может совпасть с освобождением: перед отказом смотрим ещё раз.
            if !condition.wait(until: deadline) && busy { return false }
        }
        busy = true
        holderLabel = label
        return true
    }

    func release() {
        condition.lock()
        busy = false
        holderLabel = ""
        condition.broadcast()
        condition.unlock()
    }
}
