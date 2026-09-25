import AppKit
import ApplicationServices

// Снимок контекста нажатия правого ⌘ (план C.5, F.3, F.4).
//
// Собирается один раз, сразу после отпускания клавиши и вне главного потока:
// дерево Chromium к этому моменту уже разбужено `watchAppSwitches`, а сам снимок
// перекрывается с хвостом распознавания. В Google уходит только то, что прошло
// фильтры ниже; всё остальное остаётся в памяти Intact для проверок перед вставкой.

extension AssistantContext {

    /// Сколько символов выделения уходит в промпт. С этим пределом промпт
    /// укладывается в ~6,5 КБ — замер T0 показал, что поле ввода Gemini его берёт.
    static let selectionLimit = 4000

    /// Весь снимок — не дольше этого. Пока он идёт, человек ждёт расшифровку,
    /// но зависшее приложение не должно добавлять к ожиданию секунды: у каждого
    /// AX-запроса таймаут урезается до остатка бюджета, после исчерпания
    /// остальные поля просто остаются пустыми.
    private static let captureBudget: TimeInterval = 0.15

    /// Выделение длиннее (в UTF-16) целиком не читаем. «Выделить всё» в логе или
    /// большом документе — это мегабайты через IPC на каждое нажатие (§7.1.2);
    /// в промпт всё равно уйдёт только начало.
    private static let wholeReadLimit = 16_000

    private static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    ]

    private static let passwordManagers: Set<String> = [
        "com.apple.Passwords", "com.apple.keychainaccess", "com.bitwarden.desktop",
    ]
    private static let passwordManagerPrefixes = ["com.1password.", "com.agilebits.", "com.lastpass.", "org.keepassxc."]

    /// Снимает контекст нажатия. Вызывать вне главного потока: это синхронные
    /// походы в чужой процесс.
    ///
    /// - Parameter sendSelection: настройка «отправлять выделение»; выключена —
    ///   выделение даже не читается.
    static func capture(target: NSRunningApplication?, sendSelection: Bool) -> AssistantContext {
        let now = Date()
        let started = CFAbsoluteTimeGetCurrent()
        func remaining() -> TimeInterval { captureBudget - (CFAbsoluteTimeGetCurrent() - started) }
        func bound(_ element: AXUIElement) {
            AXUIElementSetMessagingTimeout(element, Float(max(0.02, remaining())))
        }

        let bundleID = target?.bundleIdentifier
        var windowTitle: String?
        var hasTextField = false
        var selection: String?
        var truncated = false
        var fingerprint: Int?
        var dropReason: String?

        func snapshot() -> AssistantContext {
            AssistantContext(now: now, timeZone: .current,
                             appName: target?.localizedName, bundleID: bundleID,
                             windowTitle: windowTitle, hasTextField: hasTextField,
                             selection: selection, selectionTruncated: truncated,
                             selectionFingerprint: fingerprint,
                             isTerminal: bundleID.map { terminals.contains($0) } ?? false,
                             selectionDropReason: dropReason)
        }

        guard let target, target.processIdentifier > 0 else {
            dropReason = T("нет целевого приложения", "no target app")
            return snapshot()
        }

        // Приложения, у которых поле не читаем вовсе: сюда ассистент ничего не
        // вставит, а заголовок окна менеджера паролей — уже утечка.
        let id = bundleID ?? ""
        if id == Bundle.main.bundleIdentifier {
            dropReason = T("окно Intact", "Intact's own window")
            return snapshot()
        }
        if id == GeminiBridgeService.bundleIdentifier {
            dropReason = T("мост Gemini", "the Gemini bridge")
            return snapshot()
        }
        if passwordManagers.contains(id) || passwordManagerPrefixes.contains(where: { id.hasPrefix($0) }) {
            dropReason = T("менеджер паролей", "password manager")
            return snapshot()
        }
        // Человек успел уйти в другое приложение: то, что выделено у цели,
        // уже не то, на что он смотрит, — и не то, о чём спрашивает.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            dropReason = T("впереди уже другое приложение", "another app is in front now")
            return snapshot()
        }

        let app = AXUIElementCreateApplication(target.processIdentifier)
        bound(app)
        var windowRef: CFTypeRef?
        let windowError = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef)
        if windowError == .cannotComplete {
            // Приложение не ответило за весь бюджет — дальше спрашивать бессмысленно.
            dropReason = T("приложение не ответило", "the app did not respond")
            return snapshot()
        }
        if windowError == .success, let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
            let window = unsafeBitCast(windowRef, to: AXUIElement.self)
            bound(window)
            windowTitle = AXText.string(window, kAXTitleAttribute as String)
                .map { String($0.prefix(120)) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        // Фокус спрашиваем у того же `app`, а не через `AXText.focusedElement`:
        // тот ставит свои 0,25 с (на зависшем приложении это больше всего
        // бюджета) и перезаписывает `lastLookupError`, который читает лог вставки.
        guard remaining() > 0 else {
            dropReason = T("не успели прочитать", "ran out of time")
            return snapshot()
        }
        bound(app)
        var focusedRef: CFTypeRef?
        let focusError = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusError == .success, let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            if focusError == .cannotComplete { dropReason = T("приложение не ответило", "the app did not respond") }
            return snapshot()
        }
        let element = unsafeBitCast(focusedRef, to: AXUIElement.self)
        bound(element)
        if AXText.isSecureField(element) {
            dropReason = T("защищённое поле", "secure field")
            return snapshot()
        }
        hasTextField = AXText.isTextInput(element)

        // Вся семья Gemini, а не только мост: в основном Gemini.app вставлять
        // можно (это обычное приложение пользователя), но его переписка —
        // не материал для второго чата.
        if id.hasPrefix(GeminiBridgeService.mainBundleIdentifier) {
            dropReason = T("окно Gemini", "a Gemini window")
            return snapshot()
        }
        guard sendSelection else {
            dropReason = T("выключено в настройках", "turned off in settings")
            return snapshot()
        }
        guard remaining() > 0 else {
            dropReason = T("не успели прочитать", "ran out of time")
            return snapshot()
        }
        bound(element)

        let read: (text: String, complete: Bool)
        switch readSelection(element) {
        case .none:
            return snapshot()
        case .unreadable:
            dropReason = T("слишком большое, начало не читается", "too large, its beginning is unreadable")
            return snapshot()
        case .text(let text, let complete):
            read = (text, complete)
        }
        guard !read.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return snapshot() }
        if looksLikeSecret(read.text) {
            dropReason = T("похоже на ключ или пароль", "looks like a key or password")
            return snapshot()
        }

        selection = String(read.text.prefix(selectionLimit))
        truncated = !read.complete || read.text.count > selectionLimit
        // Отпечаток — только от выделения, прочитанного целиком: `text.replace`
        // сверяет его перед заменой, а про непрочитанный хвост сказать нечего.
        fingerprint = read.complete ? Self.fingerprint(read.text) : nil
        return snapshot()
    }

    // MARK: - Выделение

    private enum SelectionRead {
        case none
        case text(String, complete: Bool)
        /// Выделение огромное, а читать по диапазону приложение не умеет.
        case unreadable
    }

    /// Сначала дешёвая длина, потом текст: пустое выделение (частый случай)
    /// стоит одного запроса, огромное — читается только началом.
    private static func readSelection(_ element: AXUIElement) -> SelectionRead {
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(unsafeBitCast(rangeRef, to: AXValue.self), .cfRange, &range) {
                if range.length <= 0 { return .none }
                if range.length > wholeReadLimit {
                    var head = CFRange(location: range.location, length: wholeReadLimit)
                    var headRef: CFTypeRef?
                    guard let parameter = AXValueCreate(.cfRange, &head),
                          AXUIElementCopyParameterizedAttributeValue(
                              element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &headRef) == .success,
                          let text = headRef as? String else { return .unreadable }
                    return .text(text, complete: false)
                }
            }
        }
        guard let text = AXText.string(element, kAXSelectedTextAttribute as String), !text.isEmpty else { return .none }
        return .text(text, complete: true)
    }

    /// Отпечаток выделения для проверки «не сменилось ли» перед `text.replace`.
    /// FNV-1a по UTF-8, а не `hashValue`: тот засевается заново при каждом
    /// запуске, а отпечаток удобно сверять и в логе между запусками.
    static func fingerprint(_ text: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(bitPattern: UInt(hash))
    }

    // MARK: - Похоже на секрет

    /// Ключи с узнаваемым началом. Слева — граница слова: «task-list» и
    /// «desk-top» содержат `sk-`, но ключами не являются.
    private static let secretPatterns: [NSRegularExpression] = [
        "-----BEGIN",
        #"(?<![A-Za-z0-9])sk-[A-Za-z0-9_\-]{16,}"#,
        #"(?<![A-Za-z0-9])AKIA[0-9A-Z]{16}(?![A-Za-z0-9])"#,
        #"(?<![A-Za-z0-9])(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"#,
        #"(?<![A-Za-z0-9])xox[abprs]-[A-Za-z0-9\-]{10,}"#,
        // hex от 32 символов: токены, секреты вебхуков, md5 и sha.
        #"(?<![A-Za-z0-9])[0-9a-fA-F]{32,}(?![A-Za-z0-9])"#,
        // Ссылки ниже пропускаются как пути, поэтому секреты в них ловятся
        // отдельно: пароль в самой ссылке (postgres://user:пароль@host) и
        // параметр с говорящим именем (?key=, &access_token=, X-Amz-Signature=).
        #"://[^\s/:@]+:[^\s/@]+@"#,
        #"(?i)[?&#][A-Za-z0-9_.\-]*(?:key|token|secret|passw(?:or)?d|pwd|signature|sig)=[^&\s#]{12,}"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    /// Отрезок в алфавите base64/base64url.
    private static let tokenRun = try! NSRegularExpression(pattern: #"[A-Za-z0-9+/=_\-]{32,}"#)

    /// Похоже ли выделение на ключ, токен или приватный ключ. Такое выделение
    /// не уходит в Google вовсе: история копии Gemini хранится в аккаунте.
    ///
    /// Для «токена base64 от 32 символов» одной длины мало — под неё попадают
    /// пути и ссылки, а их выделяют постоянно. Поэтому отрезок должен смешивать
    /// цифры с буквами обоих регистров (у случайной строки такой длины это
    /// почти всегда так, у слов и путей почти никогда), а слово, которое
    /// начинается с `/`, `~/` или содержит `://`, считается путём или ссылкой.
    /// Ключ в параметре или пароль в ссылке ловят шаблоны выше; токен прямо
    /// в пути (вебхук Discord, бот Telegram) — нет, это известная дыра.
    static func looksLikeSecret(_ text: String) -> Bool {
        let whole = NSRange(text.startIndex..., in: text)
        if secretPatterns.contains(where: { $0.firstMatch(in: text, range: whole) != nil }) { return true }

        for word in text.split(whereSeparator: { $0.isWhitespace }) where word.count >= 32 {
            if word.hasPrefix("/") || word.hasPrefix("~/") || word.contains("://") { continue }
            let word = String(word)
            for match in tokenRun.matches(in: word, range: NSRange(word.startIndex..., in: word)) {
                guard let range = Range(match.range, in: word) else { continue }
                let run = word[range]
                if run.contains(where: \.isNumber), run.contains(where: \.isUppercase), run.contains(where: \.isLowercase) {
                    return true
                }
            }
        }
        return false
    }
}
