import AppKit
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
            // Выбранной копии больше нет (удалили клон) — молча возвращаемся к основному.
            return mainBundleIdentifier
        }
        return chosen
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

            let success = self.performDirectAXDelivery(prompt: cleanPrompt, autoSubmit: autoSubmit, newChat: newChat, background: background)

            if success {
                DispatchQueue.main.async {
                    let successMsg = background
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

        // Если включена автоотправка — нажимаем кнопку «Отправить»
        if autoSubmit {
            if let sendBtn = findElement(in: window, role: "AXButton", descMatch: ["Отправить", "Send", "submit"]) {
                let pressRes = AXUIElementPerformAction(sendBtn, kAXPressAction as CFString)
                if pressRes == .success {
                    if background { currentActiveApp?.activate() }
                    return true
                }
            }

            // Резервная эмуляция клавиши Enter
            let src = CGEventSource(stateID: .combinedSessionState)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)
            keyDown?.postToPid(pid)
            keyUp?.postToPid(pid)
        }

        if background { currentActiveApp?.activate() }
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

        let oldPasteboard = NSPasteboard.general.string(forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        let newChatCmd = newChat ? "delay 0.2\nkeystroke \"n\" using {command down}\ndelay 0.2" : ""
        let submitCmd = autoSubmit ? "delay 0.15\nkey code 36" : ""

        let script = """
        tell application id "\(Self.bundleIdentifier)" to activate
        delay 0.4
        tell application "System Events"
            set frontmost of (first process whose bundle identifier is "\(Self.bundleIdentifier)") to true
            delay 0.1
            \(newChatCmd)
            keystroke "v" using {command down}
            \(submitCmd)
        end tell
        """

        var errorDict: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&errorDict)
        }

        if let oldPasteboard {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(oldPasteboard, forType: .string)
            }
        }

        DispatchQueue.main.async {
            if let error = errorDict {
                let errorMsg = error[NSAppleScript.errorMessage] as? String ?? T("Ошибка отправки", "Failed to send")
                self.lastStatusMessage = errorMsg
                completion?(false, errorMsg)
            } else {
                let okMsg = T("Отправлено в Gemini", "Sent to Gemini")
                self.lastStatusMessage = okMsg
                completion?(true, okMsg)
            }
        }
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
