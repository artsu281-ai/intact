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
        }
    }
}

struct MenuContent: View {
    @ObservedObject private var controller = DictationController.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Text(statusLine)

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
            Divider()
        }

        Button(controller.state == .recording ? "Остановить и распознать" : "Начать диктовку") {
            controller.toggle()
        }
        .keyboardShortcut("d")
        .disabled(controller.state == .transcribing)

        if controller.state == .recording {
            Button("Отменить запись") { controller.cancel() }
        }

        if !controller.lastResult.isEmpty {
            Divider()
            Button("Копировать последний результат") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(controller.lastResult, forType: .string)
            }
        }

        Divider()

        Button("Настройки…") { SettingsWindow.shared.show() }
        .keyboardShortcut(",")

        Button("Выйти") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        switch controller.state {
        case .recording:    return "Запись \(controller.elapsedText)"
        case .transcribing: return "Распознаю…"
        case .idle:
            let key = settings.activationMode == .modifierHold
                ? settings.triggerKey.symbol
                : HotKeyManager.describe(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
            return controller.engineReady ? "Готов · держи \(key)" : "Модель загружается · \(key)"
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
        applyActivation()
        DictationController.shared.warmUp()

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
    }
}
