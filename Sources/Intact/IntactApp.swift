import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct IntactApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var controller = DictationController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: menuIcon)
        }
    }

    private var menuIcon: String {
        switch controller.state {
        case .idle:         return "mic"
        case .recording:    return "mic.fill"
        case .transcribing: return "waveform"
        case .processingAI: return "sparkles"
        }
    }
}

struct MenuContent: View {
    @ObservedObject private var controller = DictationController.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var history = History.shared
    @ObservedObject private var modelManager = ModelManager.shared

    var body: some View {
        Text(statusLine)

        if controller.lastLatencyMs > 0 && !controller.lastResult.isEmpty {
            Text("Скорость: \(controller.lastLatencyMs) мс")
        }

        if let missing = Permissions.missingDescription {
            Divider()
            Text("⚠︎ \(missing)")
            Button("Выдать разрешения…") {
                if !Permissions.inputMonitoring {
                    Permissions.requestInputMonitoring()
                    Permissions.openInputMonitoringSettings()
                } else {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }
        }

        Divider()

        Button(controller.state == .recording ? "Остановить и распознать" : "Начать диктовку") {
            controller.toggle()
        }
        .keyboardShortcut("d")
        .disabled(controller.state == .transcribing || controller.state == .processingAI)

        if controller.state == .recording {
            Button("Отменить запись") { controller.cancel() }
        }

        if !controller.lastResult.isEmpty {
            Divider()
            Button("Скопировать последний результат") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(controller.lastResult, forType: .string)
            }
        }

        if !history.entries.isEmpty {
            Menu("Недавние записи (\(min(history.entries.count, 50)))") {
                ForEach(history.entries.prefix(8)) { entry in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                    } label: {
                        Text(entry.text.prefix(45) + (entry.text.count > 45 ? "…" : ""))
                    }
                }
                Divider()
                Button("Очистить историю") {
                    history.clear()
                }
            }
        }

        Divider()

        Menu("Язык: \(languageTitle)") {
            Button(action: { settings.language = "auto" }) {
                HStack {
                    Text("Автоопределение")
                    if settings.language == "auto" { Image(systemName: "checkmark") }
                }
            }
            Button(action: { settings.language = "ru" }) {
                HStack {
                    Text("Русский")
                    if settings.language == "ru" { Image(systemName: "checkmark") }
                }
            }
            Button(action: { settings.language = "en" }) {
                HStack {
                    Text("English")
                    if settings.language == "en" { Image(systemName: "checkmark") }
                }
            }
            Divider()
            Toggle("Переводить на английский", isOn: $settings.translateToEnglish)
        }

        Menu("Режим вставки: \(settings.outputMode.shortTitle)") {
            ForEach(OutputMode.allCases) { mode in
                Button {
                    settings.outputMode = mode
                } label: {
                    HStack {
                        Text(mode.shortTitle)
                        if settings.outputMode == mode { Image(systemName: "checkmark") }
                    }
                }
            }
        }

        Menu("Тема оформления: \(settings.appTheme.title)") {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    settings.appTheme = theme
                } label: {
                    HStack {
                        Text(theme.title)
                        if settings.appTheme == theme { Image(systemName: "checkmark") }
                    }
                }
            }
        }

        Menu("Быстрые настройки") {
            Toggle("Заметки в Apple Notes", isOn: $settings.enableVoiceNotes)
            Toggle("Напоминания в Apple Reminders", isOn: $settings.enableVoiceReminders)
            Toggle("Заглушать звук при диктовке", isOn: $settings.muteAudioWhileDictating)
            Toggle("Пауза музыки (Apple Music/Spotify)", isOn: $settings.pauseMediaWhileDictating)
            Toggle("Плавающий мини-индикатор", isOn: $settings.showIndicator)
            Toggle("Звуковые сигналы", isOn: $settings.playSounds)
            Toggle("Убирать точку в конце", isOn: $settings.trimTrailingPeriod)
            Toggle("Добавлять пробел в конце", isOn: $settings.appendSpace)
            Divider()
            Toggle("Запуск при входе в macOS", isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { _, new in LoginItem.set(enabled: new) }
        }

        Divider()

        Button("Перезапустить движок Whisper") {
            DictationController.shared.restartEngine()
        }

        Button("Проверить обновления моделей…") {
            SettingsWindow.shared.show()
            modelManager.checkForUpdates()
        }

        Divider()

        Button(L10n.chatMenuTitle) { ChatWindow.shared.show() }
            .keyboardShortcut("i", modifiers: [.command, .shift])

        Button("Настройки…") { SettingsWindow.shared.show() }
            .keyboardShortcut(",")

        Button("Выйти") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var languageTitle: String {
        switch settings.language {
        case "ru": return "Русский"
        case "en": return "English"
        default:   return "Авто"
        }
    }

    private var statusLine: String {
        if !ModelManager.shared.hasAnyModelInstalled {
            return "⚠︎ " + (settings.interfaceLanguage == .russian ? "Модель не установлена" : "No model installed")
        }
        switch controller.state {
        case .recording:    return (settings.interfaceLanguage == .russian ? "Запись " : "Recording ") + controller.elapsedText
        case .transcribing: return L10n.hudTranscribing
        case .processingAI: return L10n.hudProcessingAI
        case .idle:
            let key = settings.activationMode == .modifierHold
                ? settings.triggerKey.symbol
                : HotKeyManager.describe(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
            let modelName = URL(fileURLWithPath: settings.modelPath).deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "ggml-", with: "")
            return controller.engineReady
                ? (settings.interfaceLanguage == .russian ? "Intact готов · \(modelName) · \(key)" : "Intact ready · \(modelName) · \(key)")
                : (settings.interfaceLanguage == .russian ? "Загрузка модели (\(modelName))…" : "Loading model (\(modelName))…")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var escMonitor: Any?
    private var permissionPoll: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings.shared

        settings.onHotKeyChange = { [weak self] in self?.applyActivation() }
        settings.onEngineChange = { DictationController.shared.restartEngine() }
        settings.onAIProviderChange = { DictationController.shared.warmUpLocalAI() }
        applyActivation()
        DictationController.shared.warmUp()

        atexit {
            WhisperServer.killAllOrphanedServers()
            LocalAIProvider.killAllOrphanedServers()
        }

        // Если моделей ещё нет (первый запуск) — сразу открываем окно настроек для скачивания
        if !ModelManager.shared.hasAnyModelInstalled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                SettingsWindow.shared.show()
            }
        }

        // ⎋ отменяет запись, если система дала права на слежение за клавишами.
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape),
               DictationController.shared.state == .recording {
                DispatchQueue.main.async { DictationController.shared.cancel() }
            }
        }

        // Настройки синхронизируем с реальным состоянием элемента автозапуска.
        if settings.launchAtLogin != LoginItem.isEnabled {
            LoginItem.set(enabled: settings.launchAtLogin)
        }

        settings.onDockIconChange = { Self.applyDockIcon() }
        Self.applyDockIcon()

        Log.write("запуск · мониторинг ввода: \(Permissions.inputMonitoring), универсальный доступ: \(Permissions.accessibility)")

        // Оба разрешения нужны для разного, и запросить надо оба:
        // чтение клавиши — «Мониторинг ввода», вставка текста — «Универсальный доступ».
        if !Permissions.inputMonitoring { Permissions.requestInputMonitoring() }
        if !Permissions.accessibility { Permissions.requestAccessibility() }
        if !Permissions.allGranted { watchForAccessibility() }
    }

    /// Права выдаются в системных настройках, событие об этом нам не приходит —
    /// поэтому просто ждём и подключаем клавишу, как только доступ появился.
    private func watchForAccessibility() {
        permissionPoll?.invalidate()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            DictationController.shared.permissionsOK = Permissions.allGranted
            guard Permissions.inputMonitoring, !ModifierKeyMonitor.shared.isActive else {
                if Permissions.allGranted {
                    timer.invalidate()
                    self?.permissionPoll = nil
                }
                return
            }
            Log.write("права появились — подключаю клавишу")
            self?.applyActivation()
        }
    }

    /// Приложение стартует фоновым (LSUIElement), а значок в Dock включается
    /// уже на ходу — так его можно выключить без перезапуска.
    static func applyDockIcon() {
        NSApp.setActivationPolicy(AppSettings.shared.showDockIcon ? .regular : .accessory)
        AppSettings.shared.applyTheme()
    }

    /// Клик по значку в Dock, когда открытых окон нет.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindow.shared.show()
        return true
    }

    /// Меню Dock: правый клик или долгое нажатие на значке.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let ctl = DictationController.shared

        let dictate = NSMenuItem(
            title: ctl.state == .recording ? "Остановить и распознать" : "Начать диктовку",
            action: #selector(dockToggleDictation), keyEquivalent: "")
        dictate.target = self
        dictate.isEnabled = ctl.state != .transcribing
        menu.addItem(dictate)

        if ctl.state == .recording {
            let cancel = NSMenuItem(title: "Отменить запись", action: #selector(dockCancel), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        }

        if !ctl.lastResult.isEmpty {
            menu.addItem(.separator())
            let copy = NSMenuItem(title: "Копировать последний результат",
                                  action: #selector(dockCopyLast), keyEquivalent: "")
            copy.target = self
            menu.addItem(copy)
        }

        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Настройки…", action: #selector(dockOpenSettings), keyEquivalent: "")
        prefs.target = self
        menu.addItem(prefs)

        if let missing = Permissions.missingDescription {
            let warn = NSMenuItem(title: "⚠︎ \(missing)", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(.separator())
            menu.addItem(warn)
        }
        return menu
    }

    @objc private func dockToggleDictation() { DictationController.shared.toggle() }
    @objc private func dockCancel() { DictationController.shared.cancel() }
    @objc private func dockOpenSettings() { SettingsWindow.shared.show() }
    @objc private func dockCopyLast() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DictationController.shared.lastResult, forType: .string)
    }

    private func applyActivation() {
        let s = AppSettings.shared
        let hk = HotKeyManager.shared
        let mod = ModifierKeyMonitor.shared
        let ctl = DictationController.shared

        switch s.activationMode {
        case .modifierHold:
            hk.unregister()
            mod.onPress = { ctl.start() }
            mod.onRelease = { ctl.stop() }
            mod.onAbort = { ctl.abort() }
            mod.start(trigger: s.triggerKey)
            if !mod.isActive { watchForAccessibility() }
            DictationController.shared.permissionsOK = Permissions.allGranted

        case .hotKeyHold:
            mod.stop()
            hk.onPress = { ctl.start() }
            hk.onRelease = { ctl.stop() }
            hk.register(keyCode: s.hotKeyCode, modifiers: s.hotKeyModifiers)

        case .hotKeyToggle:
            mod.stop()
            hk.onPress = { ctl.toggle() }
            hk.onRelease = nil
            hk.register(keyCode: s.hotKeyCode, modifiers: s.hotKeyModifiers)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        permissionPoll?.invalidate()
        HotKeyManager.shared.unregister()
        ModifierKeyMonitor.shared.stop()
        WhisperServer.shared.stop()
        LocalAIProvider.shared.stop()
        GemmaAudioProvider.shared.stop()
        MediaController.shared.end()
    }
}
