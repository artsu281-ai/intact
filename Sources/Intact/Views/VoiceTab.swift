import SwiftUI
import AppKit

/// Объединённый экран «Диктовка» — горячая клавиша, устройство, язык, разрешения, тест.
/// Заменяет три отдельные вкладки: GeneralTab + MicrophoneTab + LanguageTab.
struct VoiceTab: View {
    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

    @ObservedObject var settings: AppSettings
    var onOpenSection: ((SettingsSection) -> Void)? = nil
    @ObservedObject private var controller = DictationController.shared
    @ObservedObject private var models = ModelManager.shared

    @State private var permInput = Permissions.inputMonitoring
    @State private var permAX = Permissions.accessibility
    @State private var devices: [InputDevice] = []
    @State private var advanced = false
    @State private var newTerm = ""

    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPage(title: T("Диктовка", "Dictation")) {

            // Баннер установки модели, если нужна
            if !models.hasAnyModelInstalled || models.downloading != nil {
                ModelOnboardingBanner()
            }

            // ── Проверка ────────────────────────────────────────────────
            // Первый вопрос к этому экрану — «работает ли вообще». Раньше
            // ответ на него лежал в пятой карточке сверху, между выбором
            // микрофона и языком.
            liveCheckCard

            // ── Горячая клавиша ─────────────────────────────────────────
            Card(header: T("ГОРЯЧАЯ КЛАВИША", "HOTKEY")) {
                Row(title: L10n.genHotKey,
                    subtitle: activationSubtitle,
                    first: true) {
                    if settings.activationMode == .modifierHold {
                        WisprDropdown(selection: $settings.triggerKey,
                                      options: TriggerKey.allCases) { key in
                            Text(key.title)
                        }
                    } else {
                        HotKeyRecorder(settings: settings)
                    }
                }
                Row(title: T("Режим активации", "Activation mode"),
                    subtitle: settings.activationMode.help) {
                    WisprDropdown(selection: $settings.activationMode,
                                  options: ActivationMode.allCases) { mode in
                        Text(mode.title)
                    }
                }
                Row(title: T("Вставка текста", "Text insertion"),
                    subtitle: settings.outputMode.help) {
                    WisprDropdown(selection: $settings.outputMode,
                                  options: OutputMode.allCases) { mode in
                        Text(mode.title)
                    }
                }
                // Движок распознавания больше не выбирается: локальный Whisper —
                // единственный вариант (STTEngineType — enum с одним кейсом). Дропдаун
                // с одной неизменной опцией только дублировал бы собственный подзаголовок.
            }

            // ── Причёсывание диктовки ───────────────────────────────────
            // Модель выбирается здесь же, где включается сама функция: раньше
            // тумблер жил в «Диктовке», а модель — в общих настройках, и связь
            // между ними приходилось держать в голове.
            Card(header: T("УМНОЕ ПРИЧЁСЫВАНИЕ", "SMART CLEANUP")) {
                Row(title: T("Причёсывать текст перед вставкой", "Clean up the text before inserting"),
                    subtitle: T("Убирает «э-э» и «короче», расставляет знаки препинания. Если модель не успела — вставляется исходный текст.", "Removes “uh” and “you know”, adds punctuation. If the model does not make it in time, the original text is inserted."),
                    first: true) {
                    Toggle("", isOn: $settings.enableAICleanup)
                        .toggleStyle(WisprToggleStyle())
                }
                if settings.enableAICleanup {
                    AIRoleRow(role: .cleanup,
                              onOpenSettings: { onOpenSection?(.settings) },
                              onOpenModels: { onOpenSection?(.models) })
                }
            }

            // ── Форматирование текста ───────────────────────────────────
            // Та же настройка, что и во вкладке «Брифы и заметки» (общий
            // AppSettings.trimTrailingPeriod/appendSpace) — здесь она логичнее
            // рядом с «Вставкой текста», где её и ищут в первую очередь.
            Card(header: T("ФОРМАТИРОВАНИЕ ТЕКСТА", "TEXT FORMATTING")) {
                Row(title: T("Убирать точку в конце", "Trim the trailing period"),
                    subtitle: T("Удалять завершающую точку при коротких фразах", "Remove the final period on short phrases"),
                    first: true) {
                    Toggle("", isOn: $settings.trimTrailingPeriod)
                        .toggleStyle(WisprToggleStyle())
                }
                Row(title: T("Добавлять пробел после текста", "Add a space after the text"),
                    subtitle: T("Автоматически ставить пробел после вставленного фрагмента", "Automatically add a space after the inserted fragment")) {
                    Toggle("", isOn: $settings.appendSpace)
                        .toggleStyle(WisprToggleStyle())
                }
            }

            // ── Микрофон ────────────────────────────────────────────────
            Card(header: T("МИКРОФОН", "MICROPHONE")) {
                Row(title: T("Источник звука", "Audio source"),
                    subtitle: T("Устройство записи для распознавания", "Recording device for speech recognition"),
                    first: true) {
                    WisprDropdown(selection: $settings.inputDeviceUID,
                                  options: availableDeviceUIDs) { uid in
                        Text(deviceName(for: uid))
                    }
                }
                Row(title: T("Обновить список устройств", "Refresh the device list"),
                    subtitle: T("Если подключили гарнитуру или внешний микрофон", "If you plugged in a headset or an external microphone")) {
                    PillButton(title: T("Обновить", "Refresh"), icon: .refresh) {
                        devices = AudioRecorder.availableInputDevices()
                    }
                }
            }

            // ── Язык ─────────────────────────────────────────────────────
            Card(header: T("ЯЗЫК ДИКТОВКИ", "DICTATION LANGUAGE")) {
                Row(title: T("Язык", "Language"),
                    subtitle: T("Автоопределение поддерживает смесь русского и английского", "Auto-detection handles a mix of Russian and English"),
                    first: true) {
                    SearchableLanguageDropdown(selection: $settings.language)
                }
                Row(title: T("Переводить речь на английский", "Translate speech into English"),
                    subtitle: T("Whisper автоматически переведёт сказанное в английский текст", "Whisper will translate what you said into English text")) {
                    Toggle("", isOn: $settings.translateToEnglish)
                        .toggleStyle(WisprToggleStyle())
                }
                Row(title: T("Подавлять пометки о шуме", "Suppress noise markers"),
                    subtitle: T("Игнорировать теги [МУЗЫКА], [АПЛОДИСМЕНТЫ]", "Ignore [MUSIC] and [APPLAUSE] tags")) {
                    Toggle("", isOn: $settings.suppressNonSpeech)
                        .toggleStyle(WisprToggleStyle())
                }
            }

            // ── Словарь ──────────────────────────────────────────────────
            dictionaryCard

            // ── Разрешения ───────────────────────────────────────────────
            // Выданные разрешения — это отсутствие проблемы, и занимать ими
            // полкарточки незачем: сворачиваем в одну строку.
            if permInput && permAX {
                Card(header: T("РАЗРЕШЕНИЯ СИСТЕМЫ", "SYSTEM PERMISSIONS")) {
                    Row(title: T("Все разрешения выданы", "All permissions granted"),
                        subtitle: T("Мониторинг ввода и универсальный доступ", "Input monitoring and accessibility"),
                        first: true) {
                        IntactIcon(kind: .success, size: 17)
                            .foregroundStyle(Palette.iconSuccess)
                    }
                }
            } else {
                Card(header: T("РАЗРЕШЕНИЯ СИСТЕМЫ", "SYSTEM PERMISSIONS")) {
                    PermissionRow(title: T("Мониторинг ввода", "Input monitoring"),
                                  subtitle: T("Чтобы читать удержание клавиши ⌥", "To read the held ⌥ key"),
                                  granted: permInput, first: true) {
                        Permissions.requestInputMonitoring()
                        Permissions.openInputMonitoringSettings()
                    }
                    PermissionRow(title: T("Универсальный доступ", "Accessibility"),
                                  subtitle: T("Чтобы автоматически вставлять распознанный текст", "To insert the recognised text automatically"),
                                  granted: permAX) {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                }
            }

            // ── Дополнительно ────────────────────────────────────────────
            AdvancedBlock(expanded: $advanced) {
                if settings.activationMode == .modifierHold {
                    Row(title: T("Игнорировать нажатия короче", "Ignore presses shorter than"),
                        subtitle: T("Защита от случайного касания клавиши-модификатора", "Guards against brushing the modifier key by accident"), first: true) {
                        SliderControl(
                            value: Binding(get: { Double(settings.minHoldMs) },
                                           set: { settings.minHoldMs = Int($0) }),
                            range: 100...800, step: 50,
                            caption: T("\(settings.minHoldMs) мс", "\(settings.minHoldMs) ms"))
                    }
                }
                Row(title: T("Таймаут карточки копирования", "Copy card timeout"),
                    subtitle: T("Через сколько секунд скрывать карточку, если вставить текст было некуда", "How many seconds before the card hides when there was nowhere to insert the text")) {
                    WisprDropdown(selection: $settings.copyDismissTimeoutSeconds,
                                  options: [3, 5, 10, 15, 30]) { sec in
                        Text(T("\(sec) сек\(sec == 5 ? " (по умолч.)" : "")", "\(sec) s\(sec == 5 ? " (default)" : "")"))
                    }
                }
                Row(title: T("Максимальная длина записи", "Maximum recording length"),
                    first: settings.activationMode != .modifierHold) {
                    SliderControl(
                        value: Binding(get: { Double(settings.maxSeconds) },
                                       set: { settings.maxSeconds = Int($0) }),
                        range: 30...1800, step: 30,
                        caption: T("\(settings.maxSeconds / 60) мин", "\(settings.maxSeconds / 60) min"))
                }
            }
        }
        .onAppear { devices = AudioRecorder.availableInputDevices() }
        .onReceive(poll) { _ in
            permInput = Permissions.inputMonitoring
            permAX = Permissions.accessibility
            devices = AudioRecorder.availableInputDevices()
        }
    }

    // MARK: - Живая проверка

    /// Записать фразу и увидеть результат, не уходя со страницы и ничего
    /// никуда не вставляя.
    private var liveCheckCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    controller.toggle()
                } label: {
                    HStack(spacing: 9) {
                        IntactIcon(kind: controller.state == .recording ? .stop : .voice, size: 16)
                        Text(checkButtonTitle)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(controller.state == .recording ? .white : Palette.accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(controller.state == .recording ? Palette.iconDanger : Palette.accent.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(controller.state == .recording ? Color.clear : Palette.accent.opacity(0.22), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!models.hasAnyModelInstalled)
                .opacity(models.hasAnyModelInstalled ? 1 : 0.45)

                if controller.state == .recording {
                    CompactEqualizer(level: controller.level, theme: settings.appTheme)
                        .frame(width: 54, height: 20)
                    Text(controller.elapsedText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                } else if controller.state == .transcribing || controller.state == .processingAI {
                    ThinkingDots(size: 16, tone: .voice)
                    Text(controller.state == .processingAI ? T("Причёсываю…", "Cleaning up…") : T("Распознаю…", "Transcribing…"))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    Text(T("Скажите фразу — текст появится здесь и никуда не вставится", "Say a phrase — the text appears here and is inserted nowhere"))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                if controller.lastLatencyMs > 0 {
                    Text(T("\(controller.lastLatencyMs) мс", "\(controller.lastLatencyMs) ms"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .help(T("Задержка последнего распознавания", "Latency of the last recognition"))
                }
            }

            if !controller.draftText.isEmpty && controller.state == .recording {
                checkResult(controller.draftText, muted: true)
            } else if !controller.lastResult.isEmpty {
                checkResult(controller.lastResult, muted: false)
            }

            if let err = controller.lastError {
                HStack(spacing: 8) {
                    IntactIcon(kind: .error, size: 14)
                        .foregroundStyle(Palette.iconDanger)
                    Text(err)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.iconDanger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        )
    }

    private var checkButtonTitle: String {
        switch controller.state {
        case .recording: return T("Остановить", "Stop")
        case .transcribing, .processingAI, .answeringAI: return T("Обработка…", "Working…")
        case .idle: return T("Проверить микрофон", "Test the microphone")
        }
    }

    private func checkResult(_ text: String, muted: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(muted ? Palette.textSecondary : Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if !muted {
                PillButton(title: T("Копировать", "Copy"), icon: .copy) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Palette.dropdownBg)
        )
    }

    // MARK: - Словарь

    /// Термины хранятся той же строкой, что уходит в `initialPrompt` Whisper,
    /// но редактируются по одному. Свободный текстовый блок выглядел как поле
    /// для заметок: в него писали фразы, а модель ждёт список слов.
    private var dictionaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Пользовательский словарь", "Custom dictionary"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 12) {
                Text(T("Термины, профессиональный сленг и имена, которые модель может слышать неверно. Добавляйте по одному.", "Terms, jargon and names the model may mishear. Add them one at a time."))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)

                if !dictionaryTerms.isEmpty {
                    FlowTags(items: dictionaryTerms) { term in removeTerm(term) }
                }

                HStack(spacing: 8) {
                    TextField(T("Например, Kubernetes", "For example, Kubernetes"), text: $newTerm)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Palette.dropdownBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(Palette.hairline, lineWidth: 1)
                                )
                        )
                        .frame(maxWidth: 260)
                        .onSubmit { addTerm() }
                    PillButton(title: T("Добавить", "Add"), icon: .plus) { addTerm() }
                    Spacer()
                }

                if dictionaryTerms.isEmpty {
                    Text(T("Пример: Kubernetes, Postgres, SwiftUI, деплой, коммит, рефакторинг", "For example: Kubernetes, Postgres, SwiftUI, deploy, commit, refactoring"))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    Text(T("Уходит в модель как подсказка: \(dictionaryTerms.count) \(Plural.form(dictionaryTerms.count, "термин", "термина", "терминов"))", "Sent to the model as a hint: \(dictionaryTerms.count) \(Plural.form(dictionaryTerms.count, "term", "terms", "terms"))"))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
        }
    }

    private var dictionaryTerms: [String] {
        settings.initialPrompt
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !dictionaryTerms.contains(term) else { newTerm = ""; return }
        settings.initialPrompt = (dictionaryTerms + [term]).joined(separator: ", ")
        newTerm = ""
    }

    private func removeTerm(_ term: String) {
        settings.initialPrompt = dictionaryTerms.filter { $0 != term }.joined(separator: ", ")
    }

    private var activationSubtitle: String {
        switch settings.activationMode {
        case .modifierHold:  return T("Удерживайте \(settings.triggerKey.symbol) во время речи", "Hold \(settings.triggerKey.symbol) while speaking")
        case .hotKeyHold:    return T("Удерживайте сочетание во время речи", "Hold the combination while speaking")
        case .hotKeyToggle:  return T("Нажмите один раз для старта, второй — для вставки", "Press once to start, again to insert")
        }
    }

    private var availableDeviceUIDs: [String] { [""] + devices.map { $0.id } }

    private func deviceName(for uid: String) -> String {
        if uid.isEmpty { return T("Системный по умолчанию", "System default") }
        return devices.first(where: { $0.id == uid })?.name ?? T("Неизвестный микрофон", "Unknown microphone")
    }
}
