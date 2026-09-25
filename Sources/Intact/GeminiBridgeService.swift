import AppKit
import Carbon
import ApplicationServices
import Foundation

/// Сервис взаимодействия с установленным на Mac приложением Gemini (com.google.GeminiMacOS).
///
/// Использует нативный macOS Accessibility API (AXUIElement) для прямого и полностью фонового
/// ввода текста в поле ввода Gemini и нажатия кнопки отправки без переключения активного окна
/// и без затирания буфера обмена.
final class GeminiBridgeService: ObservableObject {
    static let shared = GeminiBridgeService()

    /// Идентификатор основного приложения Gemini из /Applications.
    static let mainBundleIdentifier = "com.google.GeminiMacOS"

    /// С каким экземпляром Gemini мы сейчас работаем. По умолчанию — установленное
    /// приложение; в настройках можно выбрать отдельную копию (Double Bubble),
    /// чтобы Intact не вмешивался в рабочую переписку пользователя.
    static var bundleIdentifier: String {
        let chosen = AppSettings.shared.geminiBundleIdentifier
        guard !chosen.isEmpty,
              NSWorkspace.shared.urlForApplication(withBundleIdentifier: chosen) != nil else {
            noteFallbackToMainApp(from: chosen)
            return mainBundleIdentifier
        }
        return chosen
    }

    /// Откат на основное приложение молчаливым быть не должен.
    ///
    /// Раньше здесь стояло «выбранной копии больше нет — молча возвращаемся к
    /// основному», и это ровно тот путь, которым чинимая ошибка возвращается:
    /// мостом становится основное приложение, и рабочее окно человека снова
    /// оказывается тем, куда диктовку не доставляют. Плюс с этого момента Intact
    /// начинает писать промпты в его личную переписку, а `clearComposer` —
    /// стирать его набранный текст.
    ///
    /// Пишем один раз на каждый несостоявшийся идентификатор: свойство выше
    /// читают на каждую доставку и из двух потоков, лог захлебнётся.
    private static var reportedFallback: String?
    private static let fallbackLock = NSLock()

    private static func noteFallbackToMainApp(from chosen: String) {
        // Пустая настройка — это не откат, а «экземпляр никогда не выбирали».
        guard !chosen.isEmpty, chosen != mainBundleIdentifier else { return }

        fallbackLock.lock()
        let isNew = reportedFallback != chosen
        if isNew { reportedFallback = chosen }
        fallbackLock.unlock()
        guard isNew else { return }

        Log.write("Gemini: выбранный экземпляр «\(chosen)» не найден — мостом стало основное приложение. "
                  + "Пока это так, запросы идут в рабочую переписку, а диктовка в её окно не доставляется")
    }

    /// Один доступный экземпляр Gemini: основное приложение или его копия.
    struct Instance: Identifiable, Hashable {
        let bundleId: String
        let title: String
        let path: String
        var isClone: Bool { bundleId != mainBundleIdentifier }
        var id: String { bundleId }
    }

    /// Все экземпляры Gemini, которые видит система: основное приложение плюс копии,
    /// сделанные Double Bubble (у них идентификатор вида
    /// `com.google.GeminiMacOS.doublebubble.<хеш>` и собственное хранилище данных).
    static func availableInstances() -> [Instance] {
        var found: [Instance] = []
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mainBundleIdentifier) {
            found.append(Instance(bundleId: mainBundleIdentifier,
                                  title: T("Основное приложение", "Main app"),
                                  path: url.path))
        }

        let bundlesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".double_bubble/bundles", isDirectory: true)
        let dirs = (try? FileManager.default.contentsOfDirectory(at: bundlesDir,
                                                                 includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let apps = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for app in apps where app.pathExtension == "app" {
                guard let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
                      let bid = plist["CFBundleIdentifier"] as? String,
                      bid.hasPrefix(mainBundleIdentifier),
                      bid != mainBundleIdentifier else { continue }
                found.append(Instance(bundleId: bid,
                                      title: T("Копия · \(dir.lastPathComponent)", "Copy · \(dir.lastPathComponent)"),
                                      path: app.path))
            }
        }
        return found
    }

    @Published var isInstalled: Bool = false
    @Published var isRunning: Bool = false
    @Published var lastStatusMessage: String? = nil

    private var pollTimer: Timer?

    /// Дешёвая синхронная проверка наличия приложения. `isInstalled` публикуется через
    /// главную очередь и в первые мгновения после запуска ещё `false` — полагаться
    /// на него в проверках готовности провайдера нельзя.
    static var isAppAvailable: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
            || FileManager.default.fileExists(atPath: "/Applications/Gemini.app")
    }

    private init() {
        refreshState()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
    }

    /// Обновляет статус установки и работы приложения Gemini
    func refreshState() {
        let installed = Self.isAppAvailable
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty

        DispatchQueue.main.async {
            self.isInstalled = installed
            self.isRunning = running
        }
    }

    /// Открывает окно приложения Gemini
    func openGemini() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }


    /// Проверяет, является ли распознанный текст голосовой командой обращения к Gemini
    func extractGeminiCommand(from rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            "^(джеминай|джеммини|джейминай|джоминай|gemini)(\\s*(,|:|—|-|\\.)?\\s*|\\s+)",
            "^(спроси у джеминай|спроси джеминай|спроси у gemini|спроси gemini|отправь в джеминай|отправь в gemini)(\\s*(,|:|—|-|\\.)?\\s*|\\s+)",
            "^(ask gemini|send to gemini)(\\s*(,|:|—|-|\\.)?\\s*|\\s+)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: trimmed.utf16.count)
                if let match = regex.firstMatch(in: trimmed, options: [], range: range),
                   match.range.location == 0 {
                    let matchLength = match.range.length
                    let startIndex = trimmed.utf16.index(trimmed.utf16.startIndex, offsetBy: matchLength)
                    let remaining = String(trimmed[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleaned = remaining.trimmingCharacters(in: CharacterSet(charactersIn: ":,.-— \t\n"))
                    guard !cleaned.isEmpty else { return nil }
                    return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
                }
            }
        }
        return nil
    }

    /// Отправляет текст запроса напрямую в приложение Gemini через Accessibility API
    func sendToGemini(
        prompt: String,
        autoSubmit: Bool = true,
        newChat: Bool = false,
        background: Bool = AppSettings.shared.geminiBackgroundMode,
        completion: ((Bool, String?) -> Void)? = nil
    ) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else {
            completion?(false, T("Пустой запрос", "Empty request"))
            return
        }

        refreshState()
        // Проверяем синхронно: refreshState публикует isInstalled через главную очередь,
        // и на первой же отправке после запуска здесь читался ещё не заполненный false.
        guard Self.isAppAvailable else {
            let msg = T("Приложение Gemini не найдено в /Applications", "The Gemini app was not found in /Applications")
            DispatchQueue.main.async { self.lastStatusMessage = msg }
            completion?(false, msg)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // Поле ввода общее с распознаванием: сначала пусть оно закончит уборку.
            GeminiSTTService.shared.waitUntilIdle()
            // И с ассистентом, чатом и сводкой — один пишущий за раз. Без шлюза не пишем
            // вовсе, в том числе запасным AppleScript: он тоже печатает в то же поле.
            guard GeminiComposerGate.shared.acquire("bridge", timeout: 15) else {
                let msg = T("Gemini занят другим запросом — повторите чуть позже", "Gemini is busy with another request — try again shortly")
                Log.write("Джеминай: поле занято (\(GeminiComposerGate.shared.holder)) — не отправляю")
                DispatchQueue.main.async {
                    self.lastStatusMessage = msg
                    completion?(false, msg)
                }
                return
            }
            defer { GeminiComposerGate.shared.release() }

            let success = self.performDirectAXDelivery(prompt: cleanPrompt, autoSubmit: autoSubmit, newChat: newChat, background: background)

            if success {
                DispatchQueue.main.async {
                    let successMsg = !autoSubmit
                        ? T("Текст вставлен в поле Gemini — отправьте его сами", "The text is in Gemini's field — send it yourself")
                        : background
                        ? T("Запрос отправлен в Gemini в фоновом режиме!", "Sent to Gemini in the background!")
                        : T("Запрос успешно отправлен в Gemini!", "Sent to Gemini successfully!")
                    self.lastStatusMessage = successMsg
                    self.isRunning = true
                    completion?(true, successMsg)
                }
            } else {
                // Уже в фоновом потоке — не прыгаем на главный только затем,
                // чтобы тут же уйти обратно в фоновый ради AppleScript.
                self.performAppleScriptFallback(prompt: cleanPrompt, autoSubmit: autoSubmit,
                                                newChat: newChat, background: background, completion: completion)
            }
        }
    }

    /// Текст поля ввода Gemini, если его удаётся прочитать.
    private static func composerText(of app: NSRunningApplication) -> String? {
        guard let field = composerField(of: app) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value) == .success else { return nil }
        let text = value as? String ?? ""
        for placeholder in ["Спросить Gemini", "Ask Gemini"] where text == placeholder { return "" }
        return text
    }

    /// Поле ввода Gemini (первый AXTextArea вне списка сообщений).
    private static func composerField(of app: NSRunningApplication) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windowsRef)
        func find(_ node: AXUIElement, _ depth: Int) -> AXUIElement? {
            if depth > 40 { return nil }
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""
            if role == "AXTextArea" { return node }
            if role == "AXOutline" || role == "AXRow" { return nil }
            var kids: CFTypeRef?
            AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &kids)
            for child in (kids as? [AXUIElement]) ?? [] { if let found = find(child, depth + 1) { return found } }
            return nil
        }
        for window in (windowsRef as? [AXUIElement]) ?? [] {
            if let field = find(window, 0) { return field }
        }
        return nil
    }

    /// Прямая доставка текста в поле ввода Gemini через macOS Accessibility API (с поддержкой фона)
    private func performDirectAXDelivery(prompt: String, autoSubmit: Bool, newChat: Bool, background: Bool) -> Bool {
        let currentActiveApp = NSWorkspace.shared.frontmostApplication
        var geminiApp = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first

        if geminiApp == nil {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
                return false
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = !background
            config.hides = background
            let sema = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
                geminiApp = app
                sema.signal()
            }
            sema.wait()
            Thread.sleep(forTimeInterval: 0.8)
        }

        guard let app = geminiApp ?? NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first else {
            return false
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        var wins = windowsRef as? [AXUIElement] ?? []

        // Окно на другом рабочем столе: kAXWindows пуст, но main-окно доступно.
        // Раньше здесь был AppleScript reopen — он активировал Gemini.
        if wins.isEmpty {
            var mainRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainRef) == .success,
               let main = mainRef as! AXUIElement? {
                wins = [main]
            }
        }

        // Окон нет вообще (закрыто на крестик) — открываем новое без активации
        if wins.isEmpty {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                // Скрытый старт: иначе поднятие Gemini показывает его окно.
                config.hides = true
                NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
            var retries = 10
            while retries > 0 {
                Thread.sleep(forTimeInterval: 0.2)
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let newWins = windowsRef as? [AXUIElement], !newWins.isEmpty {
                    wins = newWins
                    break
                }
                retries -= 1
            }
            if background { currentActiveApp?.activate() }
        }

        guard let window = wins.first else {
            return false
        }

        // Окно пользователя не разворачиваем: у свёрнутого окна AX-дерево заморожено,
        // и запись в него молча не проходит — такой случай честно отдаём как неудачу
        // ниже, а не оживляем окно за спиной пользователя.

        // Если режим не фоновый — выводим окно на передний план
        if !background {
            app.activate()
            Thread.sleep(forTimeInterval: 0.2)
        }

        // Если нужен новый чат
        if newChat {
            if let newChatBtn = findElement(in: window, role: "AXButton", descMatch: ["Новый чат", "New chat"]) {
                AXUIElementPerformAction(newChatBtn, kAXPressAction as CFString)
                Thread.sleep(forTimeInterval: 0.2)
            }
        }

        // Ищем поле ввода текста (AXTextArea)
        guard let textArea = findElement(in: window, role: "AXTextArea") else {
            return false
        }

        // Устанавливаем текст напрямую в поле ввода Gemini и проверяем чтением обратно.
        // Код возврата тут не показатель: у свёрнутого окна дерево заморожено и
        // отвечает .success, хотя в поле ничего не появилось — без этой проверки
        // пользователь получал бодрое «Отправлено в Gemini» на пустом месте.
        // Текст вставляем как пользовательский ввод (выделить всё + заменить):
        // подмену kAXValue веб-приложение не регистрирует и отправка не срабатывает,
        // а установка kAXFocused выносила бы окно Gemini на передний план.
        guard GeminiAIProvider.insertAsUserInput(prompt, into: textArea) else {
            return false
        }
        var accepted = false
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.05)
            var back: CFTypeRef?
            AXUIElementCopyAttributeValue(textArea, kAXValueAttribute as CFString, &back)
            if let text = back as? String, text.contains(prompt.prefix(24)) { accepted = true; break }
        }
        guard accepted else {
            Log.write("Gemini: поле ввода не приняло текст (окно свёрнуто?) — прямая отправка не удалась")
            return false
        }

        Thread.sleep(forTimeInterval: 0.1)

        // Если включена автоотправка — нажимаем «Отправить» и проверяем факт: поле опустело.
        // Раньше успехом считалось «нажатие не вернуло ошибку» на кнопке, найденной по
        // подстроке «Отправить», — под неё подходили «Отправить отзыв» и старые сообщения
        // с этим словом, а в ответ звучало «Отправлено в Gemini» (AGENTS_SYNC 4.7).
        if autoSubmit {
            func sent() -> Bool {
                var ref: CFTypeRef?
                guard AXUIElementCopyAttributeValue(textArea, kAXValueAttribute as CFString, &ref) == .success else { return false }
                return ((ref as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            func waitSent() -> Bool {
                for _ in 0..<15 {
                    Thread.sleep(forTimeInterval: 0.1)
                    if sent() { return true }
                }
                return false
            }
            var delivered = false
            if let sendBtn = GeminiAIProvider.button(in: window, identifier: "send_button")
                ?? GeminiAIProvider.button(in: window, exactDescription: ["Отправить", "Send"]) {
                AXUIElementPerformAction(sendBtn, kAXPressAction as CFString)
                delivered = waitSent()
            }
            if !delivered {
                // Резервная эмуляция клавиши Enter — и снова по факту.
                let src = CGEventSource(stateID: .combinedSessionState)
                CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)?.postToPid(pid)
                CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)?.postToPid(pid)
                delivered = waitSent()
            }
            if background { GeminiAIProvider.restoreFocusIfStolen(pid: pid, previous: currentActiveApp) }
            guard delivered else {
                // Не ушло — убираем свой текст, чтобы запасной путь не вставил его второй раз.
                _ = GeminiAIProvider.insertAsUserInput("", into: textArea)
                Log.write("Джеминай: запрос в поле, но не отправился — поле очищено")
                return false
            }
            return true
        }

        if background { GeminiAIProvider.restoreFocusIfStolen(pid: pid, previous: currentActiveApp) }
        return true
    }

    /// Рекурсивный поиск UI-элемента в дереве доступности
    private func findElement(in el: AXUIElement, role: String, descMatch: [String]? = nil) -> AXUIElement? {
        var roleRef: CFTypeRef?
        var descRef: CFTypeRef?
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)

        let r = roleRef as? String ?? ""
        let d = descRef as? String ?? ""
        let t = titleRef as? String ?? ""

        if r == role {
            if let match = descMatch {
                for target in match {
                    if d.localizedCaseInsensitiveContains(target) || t.localizedCaseInsensitiveContains(target) {
                        return el
                    }
                }
            } else {
                return el
            }
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findElement(in: child, role: role, descMatch: descMatch) {
                    return found
                }
            }
        }
        return nil
    }

    /// Резервный метод отправки через AppleScript
    private func performAppleScriptFallback(
        prompt: String,
        autoSubmit: Bool,
        newChat: Bool,
        background: Bool,
        completion: ((Bool, String?) -> Void)?
    ) {
        // AppleScript «keystroke» через System Events физически идёт только в
        // активное приложение — обойти это нельзя. В фоновом режиме нарушать
        // обещание «не выводить Gemini на передний план» нельзя ни при каких
        // обстоятельствах, поэтому честно сообщаем о неудаче вместо того,
        // чтобы тайком вывести окно вперёд.
        guard !background else {
            let msg = T("Не удалось отправить в фоне: окно Gemini недоступно для прямого ввода", "Couldn\u{2019}t send in the background: the Gemini window isn\u{2019}t reachable for direct input")
            DispatchQueue.main.async {
                self.lastStatusMessage = msg
                completion?(false, msg)
            }
            return
        }

        func report(_ ok: Bool, _ message: String) {
            DispatchQueue.main.async {
                self.lastStatusMessage = message
                completion?(ok, message)
            }
        }

        // 1. Вывести Gemini вперёд — и проверить, что это видно: нажатия клавиш уходят в
        //    активное окно, и если окно Gemini на другом рабочем столе, скрыто или включён
        //    защищённый ввод, они улетят не туда (или никуда), а «скрипт без ошибок» —
        //    не доказательство отправки.
        var errorDict: NSDictionary?
        NSAppleScript(source: """
        tell application id "\(Self.bundleIdentifier)" to activate
        delay 0.4
        tell application "System Events" to set frontmost of (first process whose bundle identifier is "\(Self.bundleIdentifier)") to true
        delay 0.1
        """)?.executeAndReturnError(&errorDict)
        if let error = errorDict {
            report(false, Self.appleScriptFailure(error))
            return
        }
        guard let gemini = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == gemini.processIdentifier,
              WindowVisibility.visibleWindows(of: gemini.processIdentifier) > 0 else {
            report(false, T("Окно Gemini не вышло на этот рабочий стол — не отправляю вслепую", "Gemini's window didn't come to this desktop — not typing blind"))
            return
        }
        guard !IsSecureEventInputEnabled() else {
            report(false, T("Включён защищённый ввод — нажатия клавиш не дойдут до Gemini", "Secure input is on — keystrokes won't reach Gemini"))
            return
        }

        // Через общую машинерию буфера, а не руками.
        //
        // Здесь сохранялась только строка и возвращалась безусловно через
        // секунду: всё остальное — картинка, файл, форматированный текст —
        // пропадало, а возврат затирал и то, что человек успел скопировать
        // сам за эту секунду. `Clipboard` уже умеет и полный снимок, и охрану
        // по токену сессии: возврат случится, только если в буфере всё ещё
        // наше.
        func keys(_ script: String) -> Bool {
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"System Events\"\n\(script)\nend tell")?.executeAndReturnError(&error)
            if let error {
                report(false, Self.appleScriptFailure(error))
                return false
            }
            return true
        }
        if newChat {
            guard keys("keystroke \"n\" using {command down}") else { return }
            Thread.sleep(forTimeInterval: 0.4)
        }
        // Фокус — прямо в поле ввода: ⌘V уходит в сфокусированный элемент, а после смены
        // чата или клика по ответу это может быть не поле.
        if let field = Self.composerField(of: gemini) {
            AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        let session = UUID().uuidString
        let saved = Clipboard.userSnapshot()
        Clipboard.write(prompt, transient: true, session: session)
        let pasted = keys("keystroke \"v\" using {command down}")
        Clipboard.restore(saved, session: session, fallback: prompt, after: 1.0)
        guard pasted else { return }

        // 2. Вставка — по факту: запрос в поле. Иначе Return не жмём: вставка ушла не туда,
        //    а пустое поле потом читалось бы как «отправлено».
        Thread.sleep(forTimeInterval: 0.3)
        let marker = String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        let afterPaste = Self.composerText(of: gemini)
        if let afterPaste, !afterPaste.contains(marker) {
            report(false, T("Вставка не дошла до поля Gemini", "The paste didn't reach Gemini's field"))
            return
        }
        guard autoSubmit else {
            report(afterPaste != nil,
                   afterPaste != nil ? T("Текст вставлен в поле Gemini — отправьте его сами", "The text is in Gemini's field — send it yourself")
                                     : T("Вставка в Gemini не подтвердилась", "Couldn't confirm the paste into Gemini"))
            return
        }

        // 3. Отправка — по факту: поле с запросом опустело. Поле не читается — Return всё
        //    равно жмём (Gemini впереди, так было и раньше), но успехом это не называем.
        guard keys("key code 36") else { return }
        Thread.sleep(forTimeInterval: 0.6)
        switch Self.composerText(of: gemini) {
        case .some(let text) where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && afterPaste != nil:
            report(true, T("Отправлено в Gemini", "Sent to Gemini"))
        case .some(let text) where text.contains(marker):
            report(false, T("Запрос в поле Gemini, но не отправился", "The request is in Gemini's field but wasn't sent"))
        case .some:
            report(false, T("Отправка в Gemini не подтвердилась", "Couldn't confirm it was sent to Gemini"))
        case .none:
            report(false, T("Отправка в Gemini не подтвердилась", "Couldn't confirm it was sent to Gemini"))
        }
    }

    /// Текст ошибки AppleScript — с подсказкой для запрета «Автоматизации».
    private static func appleScriptFailure(_ error: NSDictionary) -> String {
        let number = error[NSAppleScript.errorNumber] as? Int ?? 0
        let message = error[NSAppleScript.errorMessage] as? String ?? T("Ошибка AppleScript", "AppleScript error")
        if number == -1743 {
            return T("Нет разрешения управлять Gemini: Системные настройки → Конфиденциальность и безопасность → Автоматизация → Intact",
                     "No permission to control Gemini: System Settings → Privacy & Security → Automation → Intact")
        }
        if number == 1002 || number == -25211 {
            return T("Нет разрешения на нажатия клавиш: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → Intact",
                     "No permission to send keystrokes: System Settings → Privacy & Security → Accessibility → Intact")
        }
        return message + " (\(number))"
    }

    /// Тестовая отправка запроса в Gemini
    func testSend(completion: ((Bool, String?) -> Void)? = nil) {
        let testPrompt = "Привет, Gemini! Это тихий фоновый тест из приложения Intact."
        let settings = AppSettings.shared
        sendToGemini(
            prompt: testPrompt,
            autoSubmit: settings.geminiAutoSubmit,
            newChat: settings.geminiCreateNewChat,
            background: settings.geminiBackgroundMode,
            completion: completion
        )
    }
}
