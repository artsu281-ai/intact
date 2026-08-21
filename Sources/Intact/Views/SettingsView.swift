import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, system, model, language, microphone, history, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return "Основное"
        case .system:     return "Система"
        case .model:      return "Модель"
        case .language:   return "Язык и текст"
        case .microphone: return "Микрофон"
        case .history:    return "История"
        case .about:      return "О программе"
        }
    }

    var icon: String {
        switch self {
        case .general:    return "slider.horizontal.3"
        case .system:     return "macwindow"
        case .model:      return "waveform"
        case .language:   return "character.bubble"
        case .microphone: return "mic"
        case .history:    return "clock.arrow.circlepath"
        case .about:      return "info.circle"
        }
    }

    var category: String {
        switch self {
        case .general, .system, .model, .language, .microphone, .history:
            return "НАСТРОЙКИ"
        case .about:
            return "О ПРИЛОЖЕНИИ"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject private var controller = DictationController.shared
    @State private var section: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.hairline).frame(width: 1)
            detail
        }
        .frame(minWidth: 920, minHeight: 680)
        .background(Palette.page)
        .preferredColorScheme(settings.appTheme.colorScheme)
    }

    // MARK: Боковик

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Раздел: НАСТРОЙКИ
            Text("НАСТРОЙКИ")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.8)
                .padding(.horizontal, 14)
                .padding(.top, 48)
                .padding(.bottom, 8)

            ForEach(SettingsSection.allCases.filter { $0.category == "НАСТРОЙКИ" }) { item in
                SidebarRow(item: item, selected: item == section) { section = item }
            }

            // Раздел: О ПРИЛОЖЕНИИ
            Text("ИНФОРМАЦИЯ")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.8)
                .padding(.horizontal, 14)
                .padding(.top, 22)
                .padding(.bottom, 8)

            ForEach(SettingsSection.allCases.filter { $0.category == "О ПРИЛОЖЕНИИ" }) { item in
                SidebarRow(item: item, selected: item == section) { section = item }
            }

            Spacer(minLength: 20)
            footer
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(width: 236)
        .background(Palette.sidebar)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
            HStack(spacing: 7) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Intact v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private var statusColor: Color {
        if Permissions.missingDescription != nil { return .red }
        return controller.engineReady ? .green : .orange
    }

    private var statusText: String {
        if let missing = Permissions.missingDescription { return missing }
        return controller.engineReady ? "Готов к диктовке" : "Модель загружается…"
    }

    private var detail: some View {
        Group {
            switch section {
            case .general:    GeneralTab(settings: settings)
            case .system:     SystemTab(settings: settings)
            case .model:      ModelTab(settings: settings)
            case .language:   LanguageTab(settings: settings)
            case .microphone: MicrophoneTab(settings: settings)
            case .history:    HistoryTab()
            case .about:      AboutTab(settings: settings)
            }
        }
    }
}

struct SidebarRow: View {
    let item: SettingsSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: item.icon)
                    .font(.system(size: 13.5, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                    .frame(width: 20)
                Text(item.title)
                    .font(.system(size: 13.5, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Palette.selected : (hovering ? Palette.hover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Основное (General)

struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    @State private var permInput = Permissions.inputMonitoring
    @State private var permAX = Permissions.accessibility
    @State private var devices: [InputDevice] = []
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPage(title: "General") {
            Card(header: "Запуск диктовки") {
                Row(title: "Горячая клавиша",
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
            }

            Card(header: "Устройства и язык") {
                Row(title: "Микрофон",
                    subtitle: "Источник записи звука для распознавания",
                    first: true) {
                    WisprDropdown(selection: $settings.inputDeviceUID,
                                  options: availableDeviceUIDs) { uid in
                        Text(deviceName(for: uid))
                    }
                }

                Row(title: "Язык диктовки",
                    subtitle: "Автоопределение поддерживает смесь русского и английского") {
                    WisprDropdown(selection: $settings.language,
                                  options: Language.all.map { $0.code }) { code in
                        Text(Language.all.first(where: { $0.code == code })?.name ?? code)
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

            Card(header: "Разрешения системы") {
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
        .onAppear { devices = AudioRecorder.availableInputDevices() }
        .onReceive(poll) { _ in
            permInput = Permissions.inputMonitoring
            permAX = Permissions.accessibility
            devices = AudioRecorder.availableInputDevices()
        }
    }

    private var activationSubtitle: String {
        switch settings.activationMode {
        case .modifierHold:
            return "Удерживайте \(settings.triggerKey.symbol) во время речи"
        case .hotKeyHold:
            return "Удерживайте сочетание во время речи"
        case .hotKeyToggle:
            return "Нажмите сочетание один раз для старта, второй — для вставки"
        }
    }

    private var availableDeviceUIDs: [String] {
        [""] + devices.map { $0.id }
    }

    private func deviceName(for uid: String) -> String {
        if uid.isEmpty { return "Системный по умолчанию" }
        return devices.first(where: { $0.id == uid })?.name ?? "Неизвестный микрофон"
    }
}

struct PermissionRow: View {
    let title: String
    let subtitle: String
    let granted: Bool
    var first: Bool = false
    let request: () -> Void

    var body: some View {
        Row(title: title, subtitle: subtitle, first: first) {
            if granted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                    Text("выдано")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                PillButton(title: "Разрешить", action: request)
            }
        }
    }
}

// MARK: - Система (System)

struct SystemTab: View {
    @ObservedObject var settings: AppSettings
    @State private var advanced = false

    var body: some View {
        SettingsPage(title: "System") {
            Card(header: "Настройки приложения") {
                Row(title: "Тема оформления",
                    subtitle: "Светлая (Sand), тёмная (Onyx) или системная",
                    first: true) {
                    WisprDropdown(selection: $settings.appTheme,
                                  options: AppTheme.allCases) { theme in
                        Text(theme.title)
                    }
                }

                Row(title: "Запускать при входе в систему",
                    subtitle: "Автоматический запуск Intact вместе с macOS") {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(WisprToggleStyle())
                        .onChange(of: settings.launchAtLogin) { _, new in LoginItem.set(enabled: new) }
                }

                Row(title: "Показывать индикатор во время записи",
                    subtitle: "Компактный плавающий статус с живым мини-эквалайзером") {
                    Toggle("", isOn: $settings.showIndicator)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: "Значок в Dock",
                    subtitle: "Отображать приложение в панели Dock") {
                    Toggle("", isOn: $settings.showDockIcon)
                        .toggleStyle(WisprToggleStyle())
                }
            }

            Card(header: "Звук и медиа") {
                Row(title: "Заглушать системный звук во время речи",
                    subtitle: "Временно отключает вывод динамиков и наушников, чтобы фоновые звуки не лезли в микрофон",
                    first: true) {
                    Toggle("", isOn: $settings.muteAudioWhileDictating)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: "Приостанавливать музыку и видео",
                    subtitle: "Ставит на паузу Apple Music, Spotify и другие плееры на время диктовки, а затем возобновляет") {
                    Toggle("", isOn: $settings.pauseMediaWhileDictating)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: "Звуковые сигналы диктовки",
                    subtitle: "Короткие звуки при начале, окончании и ошибке записи") {
                    Toggle("", isOn: $settings.playSounds)
                        .toggleStyle(WisprToggleStyle())
                }
            }

            Card(header: "Форматирование текста") {
                Row(title: "Убирать точку в конце",
                    subtitle: "Удалять завершающую точку, если вы диктуете короткие фразы",
                    first: true) {
                    Toggle("", isOn: $settings.trimTrailingPeriod)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: "Добавлять пробел после текста",
                    subtitle: "Автоматически ставить пробел после вставленного фрагмента") {
                    Toggle("", isOn: $settings.appendSpace)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: "Сохранять историю распознаваний",
                    subtitle: "Возможность скопировать продиктованный текст из истории") {
                    Toggle("", isOn: $settings.keepHistory)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: "Таймаут карточки копирования",
                    subtitle: "Через сколько секунд скрывать окно, если поле ввода не было выбрано") {
                    WisprDropdown(selection: $settings.copyDismissTimeoutSeconds,
                                  options: [3, 5, 10, 15, 30]) { sec in
                        Text("\(sec) сек\(sec == 5 ? " (по умолч.)" : "")")
                    }
                }
            }

            Card(header: "Голосовые заметки (Apple Notes)") {
                Row(title: "Создавать заметки по командам",
                    subtitle: "Фразы «Делаем заметку…», «Заметка…», «Создай заметку…» сохраняют текст в Apple Notes без вставки в поле",
                    first: true) {
                    Toggle("", isOn: $settings.enableVoiceNotes)
                        .toggleStyle(WisprToggleStyle())
                }

                if settings.enableVoiceNotes {
                    Row(title: "Папка в Заметках",
                        subtitle: "Папка в приложении Заметки (по умолчанию «Intact»)") {
                        TextField("Intact", text: $settings.voiceNotesFolder)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Palette.dropdownBg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Palette.hairline, lineWidth: 1)
                                    )
                            )
                            .frame(width: 130)
                    }
                }
            }

            AdvancedBlock(expanded: $advanced) {
                if settings.activationMode == .modifierHold {
                    Row(title: "Игнорировать нажатия короче",
                        subtitle: "Защита от случайного касания клавиши-модификатора", first: true) {
                        SliderControl(value: Binding(get: { Double(settings.minHoldMs) },
                                                     set: { settings.minHoldMs = Int($0) }),
                                      range: 100...800, step: 50,
                                      caption: "\(settings.minHoldMs) мс")
                    }
                }
                Row(title: "Максимальная длина записи",
                    first: settings.activationMode != .modifierHold) {
                    SliderControl(value: Binding(get: { Double(settings.maxSeconds) },
                                                 set: { settings.maxSeconds = Int($0) }),
                                  range: 30...1800, step: 30,
                                  caption: "\(settings.maxSeconds / 60) мин")
                }
                if settings.outputMode == .live {
                    Row(title: "Придерживать последних слов",
                        subtitle: "Хвост черновика самый неустойчивый: эти слова допечатаются на отпускании") {
                        SliderControl(value: Binding(get: { Double(settings.liveHoldWords) },
                                                     set: { settings.liveHoldWords = Int($0) }),
                                      range: 0...3, step: 1,
                                      caption: "\(settings.liveHoldWords)")
                    }
                }
            }
        }
    }
}

/// Раскрывающийся блок для технических настроек.
struct AdvancedBlock<Content: View>: View {
    @Binding var expanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Text("Дополнительно")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(Palette.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 0) { content }
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
            }
        }
    }
}

// MARK: - Модель (Model)

struct ModelTab: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var models = ModelManager.shared
    @ObservedObject private var controller = DictationController.shared
    @State private var advanced = false

    var body: some View {
        SettingsPage(title: "Model") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Модели Whisper")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .padding(.leading, 2)
                        if let msg = models.statusMessage {
                            Text(msg)
                                .font(.system(size: 12))
                                .foregroundStyle(models.updatesAvailable.isEmpty ? Palette.textTertiary : Color.orange)
                                .padding(.leading, 2)
                        }
                    }
                    Spacer()
                    PillButton(title: models.isCheckingUpdates ? "Проверка…" : "Проверить обновления",
                               symbol: "arrow.triangle.2.circlepath") {
                        models.checkForUpdates()
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(WhisperModel.catalog.enumerated()), id: \.element.id) { index, model in
                        ModelRow(model: model, settings: settings, models: models, first: index == 0)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
            }

            if let err = models.lastError {
                Text(err).font(.system(size: 12)).foregroundStyle(.red)
            }

            Card(header: "Скорость и фоновый движок") {
                Row(title: "Распознавать во время речи",
                    subtitle: "Модель держится загруженной, и текст считается, пока вы говорите. К отпусканию клавиши он обычно уже готов.",
                    first: true) {
                    Toggle("", isOn: $settings.streaming)
                        .toggleStyle(WisprToggleStyle())
                        .onChange(of: settings.streaming) { _, _ in controller.restartEngine() }
                }
                Row(title: "Состояние whisper-server", subtitle: engineStatus) {
                    PillButton(title: "Перезапустить", symbol: "arrow.clockwise") {
                        controller.restartEngine()
                    }
                }
            }

            AdvancedBlock(expanded: $advanced) {
                Row(title: "Задержка последней вставки", first: true) {
                    Text(controller.lastLatencyMs == 0 ? "мгновенно" : "\(controller.lastLatencyMs) мс")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(controller.lastLatencyMs == 0 ? Color.green : Palette.textSecondary)
                }
                Row(title: "Черновик каждые") {
                    SliderControl(value: Binding(get: { Double(settings.draftIntervalMs) },
                                                 set: { settings.draftIntervalMs = Int($0) }),
                                  range: 200...1500, step: 50,
                                  caption: "\(settings.draftIntervalMs) мс")
                }
                Row(title: "Аудиоконтекст энкодера",
                    subtitle: "Урезанный считается быстрее, но обрезает окно распознавания") {
                    WisprDropdown(selection: $settings.draftAudioContext,
                                  options: [0, 768, 512]) { ctx in
                        switch ctx {
                        case 768: Text("768 — окно 15 с")
                        case 512: Text("512 — окно 10 с")
                        default:  Text("Полный контекст")
                        }
                    }
                    .onChange(of: settings.draftAudioContext) { _, _ in controller.restartEngine() }
                }
                Row(title: "Потоков CPU") {
                    SliderControl(value: Binding(get: { Double(settings.threads) },
                                                 set: { settings.threads = Int($0) }),
                                  range: 1...Double(ProcessInfo.processInfo.activeProcessorCount), step: 1,
                                  caption: "\(settings.threads)")
                }
                Row(title: "Файл модели",
                    subtitle: URL(fileURLWithPath: settings.modelPath).lastPathComponent) {
                    HStack(spacing: 8) {
                        PillButton(title: "Выбрать…") { pickModel() }
                        PillButton(title: "Папка") { NSWorkspace.shared.open(ModelManager.directory) }
                    }
                }
            }
        }
        .onAppear {
            if models.lastCheckTime == nil {
                models.checkForUpdates()
            }
        }
    }

    private var engineStatus: String {
        if !WhisperServer.shared.isAvailable { return "whisper-server не найден — работает запасной режим CLI" }
        if !settings.streaming { return "Выключено: текст считается после отпускания клавиши" }
        return controller.engineReady ? "Модель загружена в память и готова" : "Модель загружается…"
    }

    private func pickModel() {
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.directoryURL = ModelManager.directory
        if panel.runModal() == .OK, let url = panel.url {
            settings.modelPath = url.path
        }
    }
}

struct ModelRow: View {
    let model: WhisperModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var models: ModelManager
    var first: Bool = false
    @State private var hovering = false

    private var isActive: Bool { settings.modelPath == model.localURL.path }
    private var isDownloading: Bool { models.downloading == model.filename }
    private var hasUpdate: Bool { models.hasUpdate(model) }

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 22)
            }
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? Palette.textPrimary : Palette.textTertiary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                        Text("\(model.sizeMB) МБ")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)

                        if hasUpdate {
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                                Text("Доступно обновление")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.orange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.orange.opacity(0.12))
                            )
                        }
                    }
                    Text(model.note)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isDownloading {
                        ProgressView(value: models.progress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 280)
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: 12)

                if isDownloading {
                    Text("\(models.isUpdating ? "Обновление" : "Загрузка"): \(Int(models.progress * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                } else if !model.isInstalled {
                    PillButton(title: "Скачать", symbol: "arrow.down.circle") {
                        models.download(model)
                    }
                } else if hasUpdate {
                    PillButton(title: "Обновить", symbol: "arrow.triangle.2.circlepath") {
                        models.download(model, isUpdate: true)
                    }
                } else if hovering {
                    HStack(spacing: 8) {
                        PillButton(title: "Обновить", symbol: "arrow.clockwise") {
                            models.download(model, isUpdate: true)
                        }
                        if !isActive {
                            PillButton(title: "Удалить", symbol: "trash") {
                                models.delete(model)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isInstalled {
                settings.modelPath = model.localURL.path
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Язык и текст (Language)

struct LanguageTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPage(title: "Язык и текст") {
            Card(header: "Дополнительные опции") {
                Row(title: "Переводить речь на английский",
                    subtitle: "Whisper автоматически переведёт сказанное на любой язык в английский текст",
                    first: true) {
                    Toggle("", isOn: $settings.translateToEnglish)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: "Подавлять пометки о шуме и музыке",
                    subtitle: "Игнорировать теги вроде [МУЗЫКА], [АПЛОДИСМЕНТЫ] и фоновые звуки") {
                    Toggle("", isOn: $settings.suppressNonSpeech)
                        .toggleStyle(WisprToggleStyle())
                }
            }

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
                        .frame(height: 96)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Palette.dropdownBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Palette.hairline, lineWidth: 1)
                                )
                        )

                    Text("Пример: Kubernetes, Postgres, whisper.cpp, SwiftUI, деплой, коммит, рефакторинг")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
            }
        }
    }
}

// MARK: - Микрофон (Microphone)

struct MicrophoneTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var controller = DictationController.shared
    @State private var devices: [InputDevice] = []

    var body: some View {
        SettingsPage(title: "Микрофон") {
            Card(header: "Устройство записи") {
                Row(title: "Источник звука",
                    subtitle: "Выберите микрофон, с которого будет производиться запись",
                    first: true) {
                    WisprDropdown(selection: $settings.inputDeviceUID,
                                  options: availableDeviceUIDs) { uid in
                        Text(deviceName(for: uid))
                    }
                }
                Row(title: "Обновить список устройств",
                    subtitle: "Если вы подключили гарнитуру или внешний микрофон") {
                    PillButton(title: "Обновить", symbol: "arrow.clockwise") {
                        devices = AudioRecorder.availableInputDevices()
                    }
                }
            }

            Card(header: "Тестирование записи") {
                Row(title: "Проверить микрофон",
                    subtitle: "Тестовая запись без вставки в сторонние приложения",
                    first: true) {
                    HStack(spacing: 12) {
                        if controller.state == .recording {
                            CompactEqualizer(level: controller.level)
                                .frame(width: 36, height: 18)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.85)))
                        }
                        if controller.state == .transcribing {
                            ProgressView().controlSize(.small)
                        }
                        PillButton(title: controller.state == .recording ? "Остановить" : "Записать",
                                   symbol: controller.state == .recording ? "stop.fill" : "mic.fill") {
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
                if let err = controller.lastError {
                    Row(title: "Ошибка") {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .frame(maxWidth: 360, alignment: .trailing)
                    }
                }
            }
        }
        .onAppear { devices = AudioRecorder.availableInputDevices() }
    }

    private var availableDeviceUIDs: [String] {
        [""] + devices.map { $0.id }
    }

    private func deviceName(for uid: String) -> String {
        if uid.isEmpty { return "Системный по умолчанию" }
        return devices.first(where: { $0.id == uid })?.name ?? "Неизвестный микрофон"
    }
}

// MARK: - История (History)

struct HistoryTab: View {
    @ObservedObject private var history = History.shared

    var body: some View {
        SettingsPage(title: "История") {
            if history.entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Palette.textTertiary)
                    Text("История записей пуста")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                    Text("Здесь будут сохраняться продиктованные вами фразы.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 100)
            } else {
                Card {
                    ForEach(Array(history.entries.enumerated()), id: \.element.id) { index, entry in
                        HistoryRow(entry: entry, first: index == 0)
                    }
                }
                HStack {
                    Spacer()
                    PillButton(title: "Очистить историю", symbol: "trash") {
                        history.clear()
                    }
                }
            }
        }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    var first: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 22)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.text)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(String(format: "%.1f", entry.seconds)) с · \(entry.model)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 12)
                PillButton(title: "Копировать", symbol: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                }
                .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 15)
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - О программе (About)

struct AboutTab: View {
    @ObservedObject var settings: AppSettings

    private var whisperStatus: String {
        Transcriber.binaryPath ?? "не найден — brew install whisper-cpp"
    }

    var body: some View {
        SettingsPage(title: "О программе") {
            Card {
                Row(title: "Движок распознавания",
                    subtitle: "whisper.cpp с аппаратным ускорением Apple Silicon (Metal)",
                    first: true) {
                    Text(URL(fileURLWithPath: settings.modelPath).lastPathComponent)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                }
                Row(title: "Утилита whisper-cli") {
                    Text(whisperStatus)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Transcriber.binaryPath == nil ? .red : Palette.textSecondary)
                }
                Row(title: "Ядер процессора") {
                    Text("\(ProcessInfo.processInfo.activeProcessorCount)")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                }
                Row(title: "Версия") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                }
                Row(title: "Журнал работы",
                    subtitle: "Логирование нажатий клавиш, прав доступа и ошибок") {
                    PillButton(title: "Показать файл", symbol: "folder") {
                        NSWorkspace.shared.selectFile(Log.path, inFileViewerRootedAtPath: "")
                    }
                }
            }

            Card(header: "Приватность и безопасность") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.textPrimary)
                        Text("100% локальная обработка на устройстве")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }

                    Text("Весь процесс записи и распознавания речи выполняется исключительно на вашем Mac. Аудиофайлы никогда не отправляются на сторонние серверы и удаляются из памяти сразу после завершения диктовки.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
            }
        }
    }
}

