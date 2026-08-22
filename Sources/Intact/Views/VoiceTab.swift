import SwiftUI
import AppKit

/// Объединённый экран «Диктовка» — горячая клавиша, устройство, язык, разрешения, тест.
/// Заменяет три отдельные вкладки: GeneralTab + MicrophoneTab + LanguageTab.
struct VoiceTab: View {
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
        SettingsPage(title: "Диктовка") {

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
            Card(header: "ГОРЯЧАЯ КЛАВИША") {
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
                Row(title: "Режим активации",
                    subtitle: settings.activationMode.help) {
                    WisprDropdown(selection: $settings.activationMode,
                                  options: ActivationMode.allCases) { mode in
                        Text(mode.title)
                    }
                }
                Row(title: "Вставка текста",
                    subtitle: settings.outputMode.help) {
                    WisprDropdown(selection: $settings.outputMode,
                                  options: OutputMode.allCases) { mode in
                        Text(mode.title)
                    }
                }
            }

            // ── Причёсывание диктовки ───────────────────────────────────
            // Модель выбирается здесь же, где включается сама функция: раньше
            // тумблер жил в «Диктовке», а модель — в общих настройках, и связь
            // между ними приходилось держать в голове.
            Card(header: "УМНОЕ ПРИЧЁСЫВАНИЕ") {
                Row(title: "Причёсывать текст перед вставкой",
                    subtitle: "Убирает «э-э» и «короче», расставляет знаки препинания. Если модель не успела — вставляется исходный текст.",
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
            Card(header: "ФОРМАТИРОВАНИЕ ТЕКСТА") {
                Row(title: "Убирать точку в конце",
                    subtitle: "Удалять завершающую точку при коротких фразах",
                    first: true) {
                    Toggle("", isOn: $settings.trimTrailingPeriod)
                        .toggleStyle(WisprToggleStyle())
                }
                Row(title: "Добавлять пробел после текста",
                    subtitle: "Автоматически ставить пробел после вставленного фрагмента") {
                    Toggle("", isOn: $settings.appendSpace)
                        .toggleStyle(WisprToggleStyle())
                }
            }

            // ── Микрофон ────────────────────────────────────────────────
            Card(header: "МИКРОФОН") {
                Row(title: "Источник звука",
                    subtitle: "Устройство записи для распознавания",
                    first: true) {
                    WisprDropdown(selection: $settings.inputDeviceUID,
                                  options: availableDeviceUIDs) { uid in
                        Text(deviceName(for: uid))
                    }
                }
                Row(title: "Обновить список устройств",
                    subtitle: "Если подключили гарнитуру или внешний микрофон") {
                    PillButton(title: "Обновить", icon: .refresh) {
                        devices = AudioRecorder.availableInputDevices()
                    }
                }
            }

            // ── Язык ─────────────────────────────────────────────────────
            Card(header: "ЯЗЫК ДИКТОВКИ") {
                Row(title: "Язык",
                    subtitle: "Автоопределение поддерживает смесь русского и английского",
                    first: true) {
                    SearchableLanguageDropdown(selection: $settings.language)
                }
                Row(title: "Переводить речь на английский",
                    subtitle: "Whisper автоматически переведёт сказанное в английский текст") {
                    Toggle("", isOn: $settings.translateToEnglish)
                        .toggleStyle(WisprToggleStyle())
                }
                Row(title: "Подавлять пометки о шуме",
                    subtitle: "Игнорировать теги [МУЗЫКА], [АПЛОДИСМЕНТЫ]") {
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
                Card(header: "РАЗРЕШЕНИЯ СИСТЕМЫ") {
                    Row(title: "Все разрешения выданы",
                        subtitle: "Мониторинг ввода и универсальный доступ",
                        first: true) {
                        IntactIcon(kind: .success, size: 17)
                            .foregroundStyle(Palette.iconSuccess)
                    }
                }
            } else {
                Card(header: "РАЗРЕШЕНИЯ СИСТЕМЫ") {
                    PermissionRow(title: "Мониторинг ввода",
                                  subtitle: "Чтобы читать удержание клавиши ⌥",
                                  granted: permInput, first: true) {
                        Permissions.requestInputMonitoring()
                        Permissions.openInputMonitoringSettings()
                    }
                    PermissionRow(title: "Универсальный доступ",
                                  subtitle: "Чтобы автоматически вставлять распознанный текст",
                                  granted: permAX) {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                }
            }

            // ── Дополнительно ────────────────────────────────────────────
            AdvancedBlock(expanded: $advanced) {
                if settings.activationMode == .modifierHold {
                    Row(title: "Игнорировать нажатия короче",
                        subtitle: "Защита от случайного касания клавиши-модификатора", first: true) {
                        SliderControl(
                            value: Binding(get: { Double(settings.minHoldMs) },
                                           set: { settings.minHoldMs = Int($0) }),
                            range: 100...800, step: 50,
                            caption: "\(settings.minHoldMs) мс")
                    }
                }
                Row(title: "Таймаут карточки копирования",
                    subtitle: "Через сколько секунд скрывать карточку, если вставить текст было некуда") {
                    WisprDropdown(selection: $settings.copyDismissTimeoutSeconds,
                                  options: [3, 5, 10, 15, 30]) { sec in
                        Text("\(sec) сек\(sec == 5 ? " (по умолч.)" : "")")
                    }
                }
                Row(title: "Максимальная длина записи",
                    first: settings.activationMode != .modifierHold) {
                    SliderControl(
                        value: Binding(get: { Double(settings.maxSeconds) },
                                       set: { settings.maxSeconds = Int($0) }),
                        range: 30...1800, step: 30,
                        caption: "\(settings.maxSeconds / 60) мин")
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
                    Text(controller.state == .processingAI ? "Причёсываю…" : "Распознаю…")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    Text("Скажите фразу — текст появится здесь и никуда не вставится")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                if controller.lastLatencyMs > 0 {
                    Text("\(controller.lastLatencyMs) мс")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .help("Задержка последнего распознавания")
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
        case .recording: return "Остановить"
        case .transcribing, .processingAI, .answeringAI: return "Обработка…"
        case .idle: return "Проверить микрофон"
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
                PillButton(title: "Копировать", icon: .copy) {
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
            Text("Пользовательский словарь")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 12) {
                Text("Термины, профессиональный сленг и имена, которые модель может слышать неверно. Добавляйте по одному.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)

                if !dictionaryTerms.isEmpty {
                    FlowTags(items: dictionaryTerms) { term in removeTerm(term) }
                }

                HStack(spacing: 8) {
                    TextField("Например, Kubernetes", text: $newTerm)
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
                    PillButton(title: "Добавить", icon: .plus) { addTerm() }
                    Spacer()
                }

                if dictionaryTerms.isEmpty {
                    Text("Пример: Kubernetes, Postgres, SwiftUI, деплой, коммит, рефакторинг")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    Text("Уходит в модель как подсказка: \(dictionaryTerms.count) термин\(pluralSuffix(dictionaryTerms.count))")
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

    private func pluralSuffix(_ count: Int) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "а" }
        return "ов"
    }

    private var activationSubtitle: String {
        switch settings.activationMode {
        case .modifierHold:  return "Удерживайте \(settings.triggerKey.symbol) во время речи"
        case .hotKeyHold:    return "Удерживайте сочетание во время речи"
        case .hotKeyToggle:  return "Нажмите один раз для старта, второй — для вставки"
        }
    }

    private var availableDeviceUIDs: [String] { [""] + devices.map { $0.id } }

    private func deviceName(for uid: String) -> String {
        if uid.isEmpty { return "Системный по умолчанию" }
        return devices.first(where: { $0.id == uid })?.name ?? "Неизвестный микрофон"
    }
}
