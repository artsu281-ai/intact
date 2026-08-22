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

    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPage(title: "Диктовка") {

            // Баннер установки модели, если нужна
            if !models.hasAnyModelInstalled || models.downloading != nil {
                ModelOnboardingBanner()
            }

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
                Row(title: "Проверить микрофон",
                    subtitle: "Тестовая запись без вставки текста") {
                    HStack(spacing: 12) {
                        if controller.state == .recording {
                            CompactEqualizer(level: controller.level)
                                .frame(width: 36, height: 18)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.85)))
                        }
                        if controller.state == .transcribing || controller.state == .processingAI {
                            ProgressView().controlSize(.small)
                        }
                        PillButton(title: controller.state == .recording ? "Остановить" : "Записать",
                                   icon: controller.state == .recording ? .stop : .voice) {
                            controller.toggle()
                        }
                    }
                }
                if !controller.lastResult.isEmpty {
                    Row(title: "Распознанный текст") {
                        Text(controller.lastResult)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: 360, alignment: .trailing)
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Пользовательский словарь")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.leading, 2)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Термины, профессиональный сленг и имена, которые модель может слышать неверно:")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                    TextEditor(text: $settings.initialPrompt)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(height: 80)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Palette.dropdownBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Palette.hairline, lineWidth: 1)
                                )
                        )
                    Text("Пример: Kubernetes, Postgres, SwiftUI, деплой, коммит, рефакторинг")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
            }

            // ── Разрешения ───────────────────────────────────────────────
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
