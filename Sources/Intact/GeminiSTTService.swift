import AppKit
import ApplicationServices
import Foundation

/// Распознавание речи встроенным микрофоном приложения Gemini.
///
/// Работает целиком через Accessibility, не выводя окно Gemini на передний план:
///   1. нажимаем кнопку «Использовать микрофон (⌘D)» в композере;
///   2. ДОЖИДАЕМСЯ появления кнопки «Остановить» — только после этого можно говорить;
///   3. пока идёт речь, читаем накапливающийся текст из поля ввода (живой черновик);
///   4. по отпусканию клавиши жмём «Остановить» и дослушиваем хвост расшифровки;
///   5. отдаём дельту относительно снимка, сделанного до старта, и чистим поле.
///
/// Замеры на живом приложении (они и задают константы ниже):
///   - кнопка «Остановить» появляется через ~190 мс после нажатия микрофона;
///   - расшифровка догоняет ещё ~700 мс ПОСЛЕ нажатия «Остановить»;
///   - если заговорить, не дождавшись шага 2, начало фразы теряется.
///
/// Важное отличие от удалённого моста ChatGPT: окно Gemini мы не трогаем вообще —
/// не разворачиваем, не активируем, не ставим фокус (см. AGENTS_SYNC.md, раздел 4).
final class GeminiSTTService {
    static let shared = GeminiSTTService()

    /// Сколько ждать подтверждения, что запись пошла (замер: ~190 мс, берём запас).
    private let startConfirmTimeout: TimeInterval = 3.0
    /// Запас после подтверждения. Появление кнопки «Остановить» — ещё НЕ доказательство,
    /// что микрофон уже пишет: на прогретом микрофоне подтверждение приходит за 20–35 мс
    /// и начало фразы цело, а на холодном — за ~200 мс, и первые слова терялись.
    /// Четверть секунды тишины дешевле потерянного начала фразы.
    private let micWarmup: TimeInterval = 0.25
    /// Шаг опроса поля ввода для живого черновика.
    private let pollInterval: TimeInterval = 0.15
    /// Сколько ждать, что текст перестанет расти после «Остановить» (замер: ~700 мс).
    private let tailQuietDuration: TimeInterval = 1.4
    /// Потолок ожидания хвоста, чтобы не подвиснуть навсегда.
    private let tailMaxDuration: TimeInterval = 8.0

    private let ax = DispatchQueue(label: "com.intact.gemini.stt", qos: .userInitiated)

    /// Поколение сессии: отменённая диктовка не должна дописать свой результат в следующую.
    private var generation = 0
    private var isRecording = false
    private var window: AXUIElement?
    private var textArea: AXUIElement?
    private var baseline = ""

    private init() {}

    var isAvailable: Bool { GeminiBridgeService.isAppAvailable }

    // MARK: - Старт

    /// Включает микрофон Gemini. `completion(true)` вызывается только когда запись
    /// ПОДТВЕРЖДЕНА — до этого момента говорить нельзя, начало фразы потеряется.
    func start(onDraft: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        ax.async { [weak self] in
            guard let self else { return }
            self.generation &+= 1
            let session = self.generation

            guard let ctx = self.resolveComposer() else {
                Log.write("Gemini STT: окно или поле ввода недоступны")
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.window = ctx.window
            self.textArea = ctx.textArea

            // Композер мог остаться непустым (свой же прошлый хвост, черновик пользователя).
            // Чистим и берём снимок: всё, что появится дальше, — это наша речь.
            self.clearComposer(ctx.textArea)
            self.baseline = self.readComposer(ctx.textArea)

            guard let mic = self.findButton(in: ctx.window, anyOf: ["использовать микрофон", "microphone"]) else {
                Log.write("Gemini STT: кнопка микрофона не найдена")
                DispatchQueue.main.async { completion(false) }
                return
            }
            AXUIElementPerformAction(mic, kAXPressAction as CFString)

            // Ждём подтверждения записи — появления кнопки «Остановить».
            let deadline = Date().addingTimeInterval(self.startConfirmTimeout)
            var confirmed = false
            while Date() < deadline {
                if self.findButton(in: ctx.window, anyOf: ["останов", "stop"]) != nil { confirmed = true; break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard confirmed else {
                Log.write("Gemini STT: запись не подтвердилась — микрофон не включился")
                DispatchQueue.main.async { completion(false) }
                return
            }

            // Даём микрофону догреться, прежде чем сказать пользователю «говорите».
            Thread.sleep(forTimeInterval: self.micWarmup)

            self.isRecording = true
            Log.write("Gemini STT: запись пошла")
            DispatchQueue.main.async { completion(true) }
            self.pollDraft(session: session, onDraft: onDraft)
        }
    }

    /// Живой черновик: поле ввода Gemini наполняется по мере распознавания.
    private func pollDraft(session: Int, onDraft: @escaping (String) -> Void) {
        ax.asyncAfter(deadline: .now() + pollInterval) { [weak self] in
            guard let self, self.isRecording, self.generation == session,
                  let ta = self.textArea else { return }
            let delta = Self.delta(full: self.readComposer(ta), base: self.baseline)
            if !delta.isEmpty {
                DispatchQueue.main.async { onDraft(delta) }
            }
            self.pollDraft(session: session, onDraft: onDraft)
        }
    }

    // MARK: - Остановка

    /// Останавливает запись и отдаёт расшифровку. Пустая строка означает, что Gemini
    /// ничего не вернул — вызывающий код должен подстраховаться локальным Whisper.
    func stop(completion: @escaping (String) -> Void) {
        ax.async { [weak self] in
            guard let self, self.isRecording else {
                DispatchQueue.main.async { completion("") }
                return
            }
            self.isRecording = false
            let session = self.generation

            guard let window = self.window, let ta = self.textArea else {
                DispatchQueue.main.async { completion("") }
                return
            }

            if let stop = self.findButton(in: window, anyOf: ["останов", "stop"]) {
                AXUIElementPerformAction(stop, kAXPressAction as CFString)
            } else {
                // Кнопка не нашлась — тот же ⌘D переключает микрофон обратно.
                if let mic = self.findButton(in: window, anyOf: ["использовать микрофон", "microphone"]) {
                    AXUIElementPerformAction(mic, kAXPressAction as CFString)
                }
            }

            // Хвост: расшифровка догоняет уже после нажатия «Остановить».
            let started = Date()
            var lastText = self.readComposer(ta)
            var lastChange = Date()
            while Date().timeIntervalSince(started) < self.tailMaxDuration {
                Thread.sleep(forTimeInterval: 0.1)
                let now = self.readComposer(ta)
                if now != lastText {
                    lastText = now
                    lastChange = Date()
                }
                let quiet = Date().timeIntervalSince(lastChange)
                if quiet >= self.tailQuietDuration && !Self.delta(full: lastText, base: self.baseline).isEmpty {
                    break
                }
            }

            let result = Self.delta(full: lastText, base: self.baseline)
            // Убираем за собой: наш текст не должен остаться в чужом композере.
            self.clearComposer(ta)

            guard self.generation == session else { return }
            Log.write("Gemini STT: расшифровка \(result.count) симв. за \(Int(Date().timeIntervalSince(started) * 1000)) мс")
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Диктовку прервали — глушим микрофон Gemini и чистим поле, результат не нужен.
    /// Без этого микрофон остался бы включённым и продолжал писать в композер.
    func cancel() {
        ax.async { [weak self] in
            guard let self, self.isRecording else { return }
            self.isRecording = false
            self.generation &+= 1
            guard let window = self.window else { return }
            if let stop = self.findButton(in: window, anyOf: ["останов", "stop"])
                ?? self.findButton(in: window, anyOf: ["использовать микрофон", "microphone"]) {
                AXUIElementPerformAction(stop, kAXPressAction as CFString)
                Thread.sleep(forTimeInterval: 0.4)
            }
            if let ta = self.textArea { self.clearComposer(ta) }
            Log.write("Gemini STT: запись отменена, микрофон выключен")
        }
    }

    // MARK: - Доступ к окну и полю

    private func resolveComposer() -> (window: AXUIElement, textArea: AXUIElement)? {
        let bundleId = GeminiBridgeService.bundleIdentifier
        var running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first

        // Gemini выключен — поднимаем его СКРЫТЫМ. Раньше распознавание тут молча
        // сдавалось и диктовка уезжала в Whisper; а обычный запуск (без hides)
        // выбрасывал окно Gemini на экран, что пользователь и видел как
        // «вызвался полноценный Gemini». Замерено: скрытый старт полностью рабочий.
        if running == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Log.write("Gemini STT: приложение не запущено — поднимаю скрытым")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.hides = true
            let sema = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
                running = app
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 12)
            // Композер появляется не мгновенно — ждём, пока веб-часть отрисуется.
            for _ in 0..<25 {
                Thread.sleep(forTimeInterval: 0.2)
                if let app = running ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                    let probe = AXUIElementCreateApplication(app.processIdentifier)
                    var wr: CFTypeRef?
                    AXUIElementCopyAttributeValue(probe, kAXWindowsAttribute as CFString, &wr)
                    if (wr as? [AXUIElement] ?? []).contains(where: { findTextArea(in: $0) != nil }) { break }
                }
            }
        }

        guard let app = running ?? NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId).first else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)

        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        var candidates = windowsRef as? [AXUIElement] ?? []
        // Свёрнутое окно не отдаётся через kAXWindows, но main-окно доступно,
        // а взятая ранее ссылка продолжает работать (см. AGENTS_SYNC.md, раздел 4.3).
        if let remembered = window { candidates.insert(remembered, at: 0) }
        if candidates.isEmpty {
            var mainRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainRef) == .success,
               let main = mainRef as! AXUIElement? {
                candidates = [main]
            }
        }
        for candidate in candidates {
            if let ta = findTextArea(in: candidate) { return (candidate, ta) }
        }
        return nil
    }

    private func readComposer(_ textArea: AXUIElement) -> String {
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(textArea, kAXValueAttribute as CFString, &valueRef)
        let text = ((valueRef as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Подсказка-заглушка полем не является.
        for placeholder in ["Спросить Gemini", "Ask Gemini"] where text == placeholder { return "" }
        return text
    }

    /// Чистим поле заменой выделения: подмену kAXValue веб-приложение не регистрирует
    /// (см. AGENTS_SYNC.md, раздел 4.1).
    private func clearComposer(_ textArea: AXUIElement) {
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(textArea, kAXValueAttribute as CFString, &valueRef)
        let length = ((valueRef as? String) ?? "").utf16.count
        guard length > 0 else { return }
        var range = CFRangeMake(0, length)
        if let rangeValue = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(textArea, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }
        AXUIElementSetAttributeValue(textArea, kAXSelectedTextAttribute as CFString, "" as CFTypeRef)
        Thread.sleep(forTimeInterval: 0.15)
    }

    // MARK: - Поиск элементов

    private func findTextArea(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 40 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        if role == "AXTextArea" { return element }
        if role == "AXOutline" { return nil }
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        for child in (childrenRef as? [AXUIElement]) ?? [] {
            if let found = findTextArea(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Кнопку ищем по вхождению подстроки в описание, но НЕ заходя в боковую панель:
    /// там сотни кнопок, а сообщения пользователя рендерятся кнопками с полным текстом
    /// внутри — по ним легко промахнуться (см. AGENTS_SYNC.md, раздел 4.6).
    private func findButton(in element: AXUIElement, anyOf needles: [String], depth: Int = 0) -> AXUIElement? {
        if depth > 40 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        if role == "AXOutline" { return nil }
        if role == "AXButton" {
            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
            let desc = (descRef as? String ?? "").lowercased()
            // Длинные описания — это сообщения диалога, а не органы управления.
            if desc.count < 45, needles.contains(where: { desc.contains($0) }) { return element }
            return nil
        }
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        for child in (childrenRef as? [AXUIElement]) ?? [] {
            if let found = findButton(in: child, anyOf: needles, depth: depth + 1) { return found }
        }
        return nil
    }

    // MARK: - Дельта

    /// Новая речь = текущее содержимое поля минус то, что было до старта.
    /// Снимок обычно пуст (поле чистится перед стартом), но пользователь мог что-то
    /// печатать в Gemini сам — его текст возвращать нельзя.
    static func delta(full: String, base: String) -> String {
        let current = full.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previous.isEmpty else { return current }
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Поле переписали целиком — старого текста в нём уже нет, значит всё новое.
        return current == previous ? "" : current
    }
}
