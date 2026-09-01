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
            Image(nsImage: menuIcon.nsImage(size: 17))
        }
    }

    /// Состояние диктовки прямо в строке меню: покой → эфир → распознавание → ИИ.
    private var menuIcon: IntactIconKind {
        switch controller.state {
        case .idle:         return .voice
        case .recording:    return .voicePulse
        case .transcribing: return .waveform
        case .processingAI: return .aiStar
        case .answeringAI:  return .aiStar
        }
    }
}

/// Отметка выбранного пункта в меню строки состояния.
///
/// `NSMenu` умеет показывать только `NSImage`, поэтому векторная иконка
/// растеризуется — результат кэшируется в `IntactIconKind.nsImage`.
struct MenuCheckmark: View {
    var body: some View {
        Image(nsImage: IntactIconKind.copied.nsImage(size: 11))
    }
}

struct MenuContent: View {
    @ObservedObject private var controller = DictationController.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var history = History.shared
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var llmManager = LLMModelManager.shared

    var body: some View {
        Text(statusLine)

        // Скачивание модели идёт десятками минут, и всё это время окно
        // приложения обычно закрыто — прогресс должен быть виден отсюда.
        if let title = llmManager.downloadingTitle {
            Text("↓ \(title) — \(Int(llmManager.progress * 100))%")
        } else if let file = modelManager.downloading {
            Text("↓ \(file) — \(Int(modelManager.progress * 100))%")
        }

        if controller.lastLatencyMs > 0 && !controller.lastResult.isEmpty {
            Text(T("Скорость: \(controller.lastLatencyMs) мс", "Speed: \(controller.lastLatencyMs) ms"))
        }

        if let missing = Permissions.missingDescription {
            Divider()
            Text("⚠︎ \(missing)")
            Button(T("Выдать разрешения…", "Grant permissions…")) {
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

        Button(controller.state == .recording ? T("Остановить и распознать", "Stop and transcribe") : T("Начать диктовку", "Start dictation")) {
            controller.toggle()
        }
        .keyboardShortcut("d")
        .disabled(controller.state == .transcribing || controller.state == .processingAI)

        if controller.state == .recording {
            Button(T("Отменить запись", "Cancel recording")) { controller.cancel() }
        }

        if !controller.lastResult.isEmpty {
            Divider()
            Button(T("Скопировать последний результат", "Copy the last result")) {
                Clipboard.write(controller.lastResult, transient: false, session: nil)
            }
            if settings.geminiIntegrationEnabled && GeminiBridgeService.shared.isInstalled {
                Button(L10n.geminiSendLastResult) {
                    GeminiBridgeService.shared.sendToGemini(
                        prompt: controller.lastResult,
                        autoSubmit: settings.geminiAutoSubmit,
                        newChat: settings.geminiCreateNewChat
                    )
                }
            }
        }

        if !history.entries.isEmpty {
            Menu(T("Недавние записи (\(min(history.entries.count, 50)))", "Recent records (\(min(history.entries.count, 50)))")) {
                ForEach(history.entries.prefix(8)) { entry in
                    Button {
                        Clipboard.write(entry.text, transient: false, session: nil)
                    } label: {
                        Text(entry.text.prefix(45) + (entry.text.count > 45 ? "…" : ""))
                    }
                }
                Divider()
                Button(T("Очистить историю", "Clear history")) {
                    history.clear()
                }
            }
        }

        Divider()

        // Меню строки состояния раньше дублировало половину настроек:
        // язык, режим вставки, тема и восемь тумблеров. Всё это живёт
        // в окне, а здесь нужно то, что делают на бегу.
        Menu(T("Модель чата: \(shortModelTitle)", "Chat model: \(shortModelTitle)")) {
            Button {
                AIModelCatalog.apply(.gemini, to: .chat)
            } label: {
                HStack {
                    Text("Gemini.app (macOS)")
                    if AIModelCatalog.resolved(for: .chat) == .gemini { MenuCheckmark() }
                }
            }
            .disabled(!GeminiBridgeService.shared.isInstalled)

            let installed = LLMModelManager.shared.installedPairs
            if !installed.isEmpty {
                Divider()
                ForEach(installed, id: \.quant.filename) { pair in
                    Button {
                        AIModelCatalog.apply(.local(pair.quant.filename), to: .chat)
                    } label: {
                        HStack {
                            Text(LLMModel.displayName(model: pair.model, quant: pair.quant))
                            if AIModelCatalog.resolved(for: .chat) == .local(pair.quant.filename) { MenuCheckmark() }
                        }
                    }
                }
            }
        }

        Divider()

        Button(L10n.chatMenuTitle) { ChatWindow.shared.show() }
            .keyboardShortcut("i", modifiers: [.command, .shift])

        Button(T("Настройки…", "Settings…")) { SettingsWindow.shared.show() }
            .keyboardShortcut(",")

        Button(T("Выйти", "Quit")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Короткое имя модели чата — в строке меню длинное не помещается.
    private var shortModelTitle: String {
        let full = AIModelCatalog.title(for: AIModelCatalog.resolved(for: .chat))
        return full.split(separator: "·").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? full
    }

    private var statusLine: String {
        if !ModelManager.shared.hasAnyModelInstalled {
            return "⚠︎ " + T("Модель не установлена", "No model installed")
        }
        switch controller.state {
        case .recording:    return T("Запись ", "Recording ") + controller.elapsedText
        case .transcribing: return L10n.hudTranscribing
        case .processingAI: return L10n.hudProcessingAI
        case .answeringAI:  return L10n.hudAnsweringAI
        case .idle:
            let key = settings.activationMode == .modifierHold
                ? settings.triggerKey.symbol
                : HotKeyManager.describe(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
            let modelName = URL(fileURLWithPath: settings.modelPath).deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "ggml-", with: "")
            return controller.engineReady
                ? T("Intact готов · \(modelName) · \(key)", "Intact ready · \(modelName) · \(key)")
                : T("Загрузка модели (\(modelName))…", "Loading model (\(modelName))…")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var escMonitor: Any?
    private var permissionPoll: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings.shared

        settings.onHotKeyChange = { [weak self] in self?.applyActivation() }
        PipelineManager.shared.onChange = { [weak self] in self?.applyActivation() }
        settings.onEngineChange = { DictationController.shared.restartEngine() }
        settings.onAIProviderChange = { DictationController.shared.warmUpLocalAI() }
        // Прибираем за прошлым запуском до того, как поднимем свои серверы.
        //
        // Пул llama-server сам по себе этого не делает — и не должен: он
        // не может отличить чужой осиротевший процесс от собственного.
        // А завершение приложения не всегда успевает выполнить atexit
        // (pkill при пересборке, kill -9, падение), и тогда предыдущая
        // модель остаётся висеть в памяти целиком. На 27B это 17 ГБ,
        // которые никто больше не использует.
        WhisperServer.killAllOrphanedServers()
        LocalAIProvider.killAllOrphanedServers()

        applyActivation()
        DictationController.shared.warmUp()
        DictationController.shared.watchAppSwitches()
        // Раскладку считаем здесь, на главном потоке: очередь вставки трогать
        // Text Input Sources не имеет права — см. SyntheticKeyboard.pasteKeyCode.
        SyntheticKeyboard.watchKeyboardLayout()
        BriefService.shared.startScheduler()

        atexit {
            WhisperServer.killAllOrphanedServers()
            LocalAIProvider.killAllOrphanedServers()
        }

        // Если моделей ещё нет (первый запуск) — сразу открываем окно моделей для скачивания
        if !ModelManager.shared.hasAnyModelInstalled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainWindow.shared.show(section: .models)
            }
        }

        // ⎋ отменяет запись, если система дала права на слежение за клавишами.
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            let controller = DictationController.shared
            if controller.state == .recording {
                DispatchQueue.main.async { controller.cancel() }
            } else if controller.canSkipAIStage {
                // Причёсывание уже идёт — отдаём то, что распознал Whisper,
                // вместо того чтобы ждать модель до конца таймаута.
                DispatchQueue.main.async { controller.skipAIAndInsert() }
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
        MainWindow.shared.show(section: .home)
        return true
    }

    /// Меню Dock: правый клик или долгое нажатие на значке.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let ctl = DictationController.shared

        let chat = NSMenuItem(title: T("Чат с ИИ…", "AI Chat…"), action: #selector(dockOpenChat), keyEquivalent: "")
        chat.target = self
        menu.addItem(chat)

        let dictate = NSMenuItem(
            title: ctl.state == .recording ? T("Остановить и распознать", "Stop and transcribe") : T("Начать диктовку", "Start dictation"),
            action: #selector(dockToggleDictation), keyEquivalent: "")
        dictate.target = self
        dictate.isEnabled = ctl.state != .transcribing
        menu.addItem(dictate)

        if ctl.state == .recording {
            let cancel = NSMenuItem(title: T("Отменить запись", "Cancel recording"), action: #selector(dockCancel), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        }

        if !ctl.lastResult.isEmpty {
            menu.addItem(.separator())
            let copy = NSMenuItem(title: T("Копировать последний результат", "Copy the last result"),
                                  action: #selector(dockCopyLast), keyEquivalent: "")
            copy.target = self
            menu.addItem(copy)
        }

        menu.addItem(.separator())
        let prefs = NSMenuItem(title: T("Настройки…", "Settings…"), action: #selector(dockOpenSettings), keyEquivalent: "")
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

    @objc private func dockOpenChat() { MainWindow.shared.show(section: .chat) }
    @objc private func dockToggleDictation() { DictationController.shared.toggle() }
    @objc private func dockCancel() { DictationController.shared.cancel() }
    @objc private func dockOpenSettings() { MainWindow.shared.show(section: .settings) }
    @objc private func dockCopyLast() {
        Clipboard.write(DictationController.shared.lastResult, transient: false, session: nil)
    }

    private func applyActivation() {
        let s = AppSettings.shared
        let hk = HotKeyManager.shared
        let mod = ModifierKeyMonitor.shared
        let ctl = DictationController.shared

        // Одну и ту же клавишу ловили сразу два перехватчика: легаси-монитор обычной
        // диктовки и менеджер голосовых пайплайнов. По одному нажатию ⌥ стартовали обе
        // ветки, спорили за микрофон и за состояние контроллера. Пайплайн — более общий
        // механизм (свой движок распознавания и своё действие на выходе), поэтому
        // при пересечении клавиш он выигрывает, а легаси-монитор молча уступает.
        let pipelineKeyCodes: Set<Int64> = PipelineManager.shared.pipelines
            .filter { $0.enabled }
            .reduce(into: Set<Int64>()) { codes, pipeline in
                if case .modifierKey(let key) = pipeline.trigger { codes.formUnion(key.keyCodes) }
            }

        switch s.activationMode {
        case .modifierHold:
            hk.unregister()
            if pipelineKeyCodes.isDisjoint(with: s.triggerKey.keyCodes) {
                mod.onPress = { ctl.start() }
                mod.onRelease = { ctl.stop() }
                mod.onAbort = { ctl.abort() }
                mod.start(trigger: s.triggerKey)
                if !mod.isActive { watchForAccessibility() }
            } else {
                mod.stop()
                Log.write("клавиша \(s.triggerKey.symbol) занята голосовым пайплайном — обычная диктовка на ней не дублируется")
                if !Permissions.allGranted { watchForAccessibility() }
            }
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

        // Централизованный запуск пайплайнов (Хоткеи + Кнопки Мыши)
        InputEventManager.shared.onPipelineStart = { pipeline in
            Log.write("Запуск пайплайна «\(pipeline.name)» (\(pipeline.trigger.title))")
            ctl.startPipeline(pipeline)
        }
        InputEventManager.shared.onPipelineStop = { pipeline in
            Log.write("Остановка пайплайна «\(pipeline.name)»")
            ctl.stopPipeline(pipeline)
        }
        InputEventManager.shared.onPipelineAbort = {
            ctl.abort()
        }
        InputEventManager.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        permissionPoll?.invalidate()
        HotKeyManager.shared.unregister()
        ModifierKeyMonitor.shared.stop()
        InputEventManager.shared.stop()
        WhisperServer.shared.stop()
        LocalAIProvider.shared.stop()
        GemmaAudioProvider.shared.stop()
        MediaController.shared.end()
    }
}
