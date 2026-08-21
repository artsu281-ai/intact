import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case chat, history, general, models, ai, language, microphone, system, appearance, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:       return L10n.tabChat
        case .history:    return L10n.tabHistory
        case .general:    return L10n.tabGeneral
        case .models:     return L10n.tabModels
        case .ai:         return L10n.tabAI
        case .language:   return L10n.tabLanguage
        case .microphone: return L10n.tabMicrophone
        case .system:     return L10n.tabSystem
        case .appearance: return L10n.tabAppearance
        case .about:      return L10n.tabAbout
        }
    }

    var icon: String {
        switch self {
        case .chat:       return "bubble.left.and.sparkles"
        case .history:    return "clock.arrow.circlepath"
        case .general:    return "slider.horizontal.3"
        case .models:     return "square.stack.3d.up"
        case .ai:         return "sparkles"
        case .language:   return "character.bubble"
        case .microphone: return "mic"
        case .system:     return "macwindow"
        case .appearance: return "paintpalette"
        case .about:      return "info.circle"
        }
    }

    var category: String {
        switch self {
        case .chat, .history:
            return "WORKSPACE"
        case .general, .models, .ai, .language, .microphone, .system, .appearance:
            return "SETTINGS"
        case .about:
            return "ABOUT"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject private var controller = DictationController.shared
    @ObservedObject var state = MainWindowState.shared
    @State private var searchText = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.hairline).frame(width: 1)
            detail
        }
        .frame(minWidth: 920, minHeight: 680)
        .background(Palette.page)
        .preferredColorScheme(settings.appTheme.colorScheme)
        .id(settings.appTheme)
    }

    // MARK: Боковик

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Поле поиска
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)

                TextField(L10n.isRu ? "Поиск настроек…" : "Search settings…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.dropdownBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 2)
            .padding(.top, 46)
            .padding(.bottom, 6)

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Рабочее пространство: Ассистент и История
                Text(L10n.sectionWorkspace)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                ForEach(SettingsSection.allCases.filter { $0.category == "WORKSPACE" }) { item in
                    SidebarRow(item: item, selected: item == state.section) { state.section = item }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Настройки
                Text(L10n.sectionSettings)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                    .transition(.opacity)

                ForEach(SettingsSection.allCases.filter { $0.category == "SETTINGS" }) { item in
                    SidebarRow(item: item, selected: item == state.section) { state.section = item }
                }
                .transition(.opacity)

                // О программе
                Text(L10n.sectionInfo)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                    .transition(.opacity)

                ForEach(SettingsSection.allCases.filter { $0.category == "ABOUT" }) { item in
                    SidebarRow(item: item, selected: item == state.section) { state.section = item }
                }
                .transition(.opacity)
            } else {
                // Результаты поиска
                searchResultsView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 20)
            footer
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: searchText.isEmpty)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(width: 236)
        .background(Palette.sidebar)
    }

    private var searchResultsView: some View {
        let results = SettingsSearchIndex.shared.search(query: searchText)
        let grouped = Dictionary(grouping: results) { $0.section }
        let orderedSections = SettingsSection.allCases.filter { grouped[$0] != nil }

        return Group {
            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.textTertiary)
                    Text(L10n.isRu ? "Ничего не найдено" : "No results")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(orderedSections) { sec in
                            Text(sec.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.textTertiary)
                                .kerning(0.6)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .padding(.bottom, 2)

                            ForEach(grouped[sec]!, id: \.id) { entry in
                                SearchResultRow(entry: entry, isActive: state.section == sec) {
                                    state.section = entry.section
                                    searchText = ""
                                }
                            }
                        }
                    }
                }
            }
        }
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
            switch state.section {
            case .chat:       ChatTab(settings: settings, onOpenSection: { state.section = $0 })
            case .history:    HistoryTab()
            case .general:    GeneralTab(settings: settings)
            case .models:     ModelsHub(settings: settings)
            case .ai:         AITab(settings: settings, onOpenModels: { state.section = .models })
            case .language:   LanguageTab(settings: settings)
            case .microphone: MicrophoneTab(settings: settings)
            case .system:     SystemTab(settings: settings)
            case .appearance: AppearanceTab(settings: settings)
            case .about:      AboutTab(settings: settings)
            }
        }
    }
}

// MARK: - Поисковый индекс настроек

struct SettingsSearchEntry: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let section: SettingsSection
    let keywords: [String]
}

final class SettingsSearchIndex {
    static let shared = SettingsSearchIndex()

    let entries: [SettingsSearchEntry] = [
        // Чат и ассистент (Chat & Workspace)
        .init(title: "Чат с ИИ", subtitle: "Диалог с персональным ассистентом", section: .chat,
              keywords: ["чат", "chat", "ии", "ai", "ассистент", "assistant", "диалог", "вопрос", "сообщение"]),
        .init(title: "Анализ записей", subtitle: "Сводка голосовых диктовок и заметок", section: .chat,
              keywords: ["анализ", "сводка", "заметки", "задачи", "todo", "выжимка", "история", "диктовки"]),
        // Основное (General)
        .init(title: "Горячая клавиша", subtitle: "Запуск диктовки", section: .general,
              keywords: ["горячая", "клавиша", "hotkey", "hot key", "shortcut", "шорткат", "клавиатура", "keyboard", "модификатор", "modifier", "option", "alt"]),
        .init(title: "Режим активации", subtitle: "Удержание / переключатель", section: .general,
              keywords: ["режим", "активация", "activation", "mode", "удержание", "hold", "toggle", "переключатель"]),
        .init(title: "Микрофон", subtitle: "Источник записи звука", section: .general,
              keywords: ["микрофон", "microphone", "mic", "аудио", "audio", "запись", "recording", "устройство", "device", "вход", "input"]),
        .init(title: "Язык диктовки", subtitle: "Автоопределение русского / английского", section: .general,
              keywords: ["язык", "language", "диктовка", "dictation", "автоопределение", "auto", "русский", "russian", "английский", "english", "распознавание"]),
        .init(title: "Вставка текста", subtitle: "Способ вставки результата", section: .general,
              keywords: ["вставка", "paste", "insertion", "текст", "text", "буфер", "clipboard", "посимвольно", "type", "копирование"]),
        .init(title: "Разрешения", subtitle: "Мониторинг ввода, универсальный доступ", section: .general,
              keywords: ["разрешения", "permissions", "доступ", "accessibility", "мониторинг", "monitoring", "ввод", "input", "права"]),

        // Оформление (Appearance)
        .init(title: "Язык интерфейса", subtitle: "Русский / English", section: .appearance,
              keywords: ["язык", "language", "интерфейс", "interface", "русский", "english", "английский", "локализация", "localization"]),
        .init(title: "Тема", subtitle: "Белая, терракотовая, тёмная", section: .appearance,
              keywords: ["тема", "theme", "цвет", "color", "оформление", "appearance", "белая", "white", "терракотовая", "terracotta", "тёмная", "dark", "ночная", "светлая", "light", "стиль"]),
        .init(title: "Иконка приложения", subtitle: "Светлая, чёрная, авто", section: .appearance,
              keywords: ["иконка", "icon", "dock", "док", "значок", "светлая", "light", "чёрная", "black", "приложение", "app"]),
        .init(title: "Индикатор диктовки", subtitle: "Плавающий индикатор записи", section: .appearance,
              keywords: ["индикатор", "indicator", "запись", "recording", "плавающий", "floating", "hud", "pill", "спектр", "spectrum"]),
        .init(title: "Таймаут копирования", subtitle: "Секунды до скрытия окна", section: .appearance,
              keywords: ["таймаут", "timeout", "копирование", "copy", "dismiss", "скрытие", "окно", "window", "секунды"]),

        // Система (System)
        .init(title: "Запуск при входе", subtitle: "Автозагрузка с macOS", section: .system,
              keywords: ["запуск", "launch", "вход", "login", "автозагрузка", "autostart", "startup", "загрузка", "boot"]),
        .init(title: "Значок в Dock", subtitle: "Отображать / скрывать", section: .system,
              keywords: ["dock", "док", "значок", "icon", "показать", "show", "скрыть", "hide", "панель"]),
        .init(title: "Заглушать звук", subtitle: "Тишина во время диктовки", section: .system,
              keywords: ["заглушать", "mute", "звук", "audio", "sound", "тишина", "silence", "динамики", "speakers", "громкость"]),
        .init(title: "Пауза музыки", subtitle: "Apple Music, Spotify", section: .system,
              keywords: ["пауза", "pause", "музыка", "music", "видео", "video", "spotify", "apple music", "плеер", "player", "медиа"]),
        .init(title: "Звуковые сигналы", subtitle: "Звуки начала и конца записи", section: .system,
              keywords: ["звуковые", "sounds", "сигналы", "effects", "chime", "начало", "start", "конец", "stop", "ошибка"]),
        .init(title: "Убирать точку", subtitle: "Форматирование коротких фраз", section: .system,
              keywords: ["точка", "period", "пунктуация", "punctuation", "форматирование", "formatting", "убирать", "trim"]),
        .init(title: "Пробел после текста", subtitle: "Автоматический пробел", section: .system,
              keywords: ["пробел", "space", "trailing", "автоматический", "automatic"]),
        .init(title: "История записей", subtitle: "Сохранение прошлых диктовок", section: .system,
              keywords: ["история", "history", "записи", "records", "сохранение", "save", "прошлые", "лог", "log"]),
        .init(title: "Голосовые заметки", subtitle: "Apple Notes", section: .system,
              keywords: ["заметки", "notes", "apple notes", "голосовые", "voice", "создать", "create", "заметка", "note"]),
        .init(title: "Голосовые напоминания", subtitle: "Apple Reminders", section: .system,
              keywords: ["напоминания", "reminders", "apple reminders", "голосовые", "voice", "напомнить", "remind", "задача", "task"]),
        .init(title: "Минимальное нажатие", subtitle: "Защита от случайных касаний", section: .system,
              keywords: ["минимальное", "minimum", "нажатие", "press", "случайное", "accidental", "защита", "guard", "мс", "ms"]),
        .init(title: "Максимальная длина записи", subtitle: "Ограничение длительности", section: .system,
              keywords: ["максимальная", "maximum", "длина", "length", "запись", "recording", "duration", "ограничение", "limit"]),

        // Модели (Models)
        .init(title: "Модели Whisper", subtitle: "Установка и выбор модели", section: .models,
              keywords: ["модель", "model", "whisper", "ggml", "скачать", "download", "установить", "install", "large", "turbo", "base", "medium", "small"]),
        .init(title: "Потоковое распознавание", subtitle: "Текст во время речи", section: .models,
              keywords: ["потоковое", "streaming", "реалтайм", "realtime", "live", "черновик", "draft", "во время", "речь"]),
        .init(title: "Потоки CPU", subtitle: "Число ядер для распознавания", section: .models,
              keywords: ["потоки", "threads", "cpu", "ядра", "cores", "производительность", "performance", "скорость", "speed"]),
        .init(title: "Файл модели", subtitle: "Путь к GGML-файлу", section: .models,
              keywords: ["файл", "file", "путь", "path", "ggml", "модель", "model", "папка", "folder", "выбрать"]),
        .init(title: "whisper-server", subtitle: "Состояние движка", section: .models,
              keywords: ["whisper", "server", "сервер", "движок", "engine", "статус", "status", "перезапустить", "restart"]),
        .init(title: "Локальные модели ИИ", subtitle: "Причёсывание текста, GGUF", section: .models,
              keywords: ["llm", "локальная", "модель", "gguf", "причёсывание", "cleanup"]),
        .init(title: "Экспериментальные аудио-модели", subtitle: "Gemma, всё-в-одном", section: .models,
              keywords: ["gemma", "аудио", "audio", "эксперимент", "experiment", "всё-в-одном"]),

        // ИИ (AI)
        .init(title: "Провайдер ИИ", subtitle: "Локально или в облаке", section: .ai,
              keywords: ["ии", "ai", "искусственный интеллект", "провайдер", "provider", "claude", "anthropic", "llm", "локально", "local", "облако", "cloud"]),
        .init(title: "API-ключ Anthropic", subtitle: "Ключ для облачного ИИ", section: .ai,
              keywords: ["api", "ключ", "key", "anthropic", "claude", "keychain", "облако", "cloud"]),
        .init(title: "Локальная модель ИИ", subtitle: "llama-server, GGUF", section: .ai,
              keywords: ["локальная", "local", "модель", "model", "llama", "gguf", "homebrew", "сервер", "server"]),
        .init(title: "Причёсывание текста ИИ", subtitle: "Убирает слова-паразиты", section: .ai,
              keywords: ["причёсывание", "cleanup", "текст", "text", "слова-паразиты", "filler", "форматирование", "formatting"]),

        // Язык и текст (Language)
        .init(title: "Перевод на английский", subtitle: "Автоперевод речи", section: .language,
              keywords: ["перевод", "translate", "translation", "английский", "english", "автоперевод"]),
        .init(title: "Подавление шума", subtitle: "[МУЗЫКА], [АПЛОДИСМЕНТЫ]", section: .language,
              keywords: ["шум", "noise", "подавление", "suppress", "музыка", "music", "аплодисменты", "теги", "tags", "фильтр"]),
        .init(title: "Пользовательский словарь", subtitle: "Термины и имена для Whisper", section: .language,
              keywords: ["словарь", "vocabulary", "dictionary", "термины", "terms", "имена", "names", "подсказки", "prompts", "prompt"]),

        // Микрофон (Microphone)
        .init(title: "Тест микрофона", subtitle: "Проверка записи", section: .microphone,
              keywords: ["тест", "test", "проверка", "check", "микрофон", "microphone", "mic", "запись", "record"]),
        .init(title: "Обновить устройства", subtitle: "Гарнитура / внешний микрофон", section: .microphone,
              keywords: ["обновить", "refresh", "устройства", "devices", "гарнитура", "headset", "внешний", "external", "bluetooth", "usb"]),

        // История (History)
        .init(title: "История", subtitle: "Просмотр и копирование записей", section: .history,
              keywords: ["история", "history", "записи", "records", "копировать", "copy", "очистить", "clear", "прошлые"]),

        // О программе (About)
        .init(title: "Движок распознавания", subtitle: "whisper.cpp + Metal", section: .about,
              keywords: ["движок", "engine", "whisper", "metal", "gpu", "apple silicon", "m1", "m2", "m3", "m4", "распознавание"]),
        .init(title: "Версия", subtitle: "Intact", section: .about,
              keywords: ["версия", "version", "about", "о программе", "информация", "info"]),
        .init(title: "Приватность", subtitle: "100% локальная обработка", section: .about,
              keywords: ["приватность", "privacy", "безопасность", "security", "локальная", "local", "на устройстве", "on-device"]),
        .init(title: "Журнал работы", subtitle: "Логи и отладка", section: .about,
              keywords: ["журнал", "log", "logs", "логи", "отладка", "debug", "файл", "file"]),
    ]

    func search(query: String) -> [SettingsSearchEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return entries.filter { entry in
            if entry.title.lowercased().contains(q) { return true }
            if entry.subtitle.lowercased().contains(q) { return true }
            if entry.section.title.lowercased().contains(q) { return true }
            return entry.keywords.contains { $0.contains(q) }
        }
    }
}

// MARK: - Результат поиска в сайдбаре

struct SearchResultRow: View {
    let entry: SettingsSearchEntry
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: entry.section.icon)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(entry.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Palette.hover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.accent : Palette.textSecondary)
                    .frame(width: 20)
                    .scaleEffect(selected ? 1.08 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
                Text(item.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Palette.accent.opacity(0.12))
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Palette.accent.opacity(0.18), lineWidth: 1)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Palette.hover)
                    }
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: selected)
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
        SettingsPage(title: L10n.tabGeneral) {
            if !ModelManager.shared.hasAnyModelInstalled || ModelManager.shared.downloading != nil {
                ModelOnboardingBanner()
            }

            Card(header: L10n.genHeaderHotKey) {
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
                    SearchableLanguageDropdown(selection: $settings.language)
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

// MARK: - Оформление (Appearance)

struct AppearanceTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPage(title: L10n.tabAppearance) {
            Card(header: L10n.appearanceHeaderLanguage) {
                Row(title: L10n.appearanceHeaderLanguage,
                    subtitle: L10n.appearanceLanguageSubtitle,
                    first: true) {
                    WisprDropdown(selection: $settings.interfaceLanguage,
                                  options: InterfaceLanguage.allCases) { lang in
                        Text(lang.title)
                    }
                }
            }

            Card(header: L10n.appearanceHeaderTheme) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.appearanceThemeDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ThemeCard(
                            theme: .white,
                            title: L10n.themeWhite,
                            subtitle: L10n.themeWhiteSub,
                            accentColor: Color(red: 0.180, green: 0.480, blue: 0.920),
                            bgSample: Color(red: 0.970, green: 0.972, blue: 0.976),
                            cardSample: Color.white,
                            isSelected: settings.appTheme == .white
                        ) {
                            settings.appTheme = .white
                            settings.applyTheme()
                        }

                        ThemeCard(
                            theme: .terracotta,
                            title: L10n.themeTerracotta,
                            subtitle: L10n.themeTerracottaSub,
                            accentColor: Color(red: 0.780, green: 0.435, blue: 0.318),
                            bgSample: Color(red: 0.980, green: 0.965, blue: 0.941),
                            cardSample: Color(red: 0.996, green: 0.992, blue: 0.984),
                            isSelected: settings.appTheme == .terracotta
                        ) {
                            settings.appTheme = .terracotta
                            settings.applyTheme()
                        }

                        ThemeCard(
                            theme: .dark,
                            title: L10n.themeDark,
                            subtitle: L10n.themeDarkSub,
                            accentColor: Color(red: 0.880, green: 0.650, blue: 0.520),
                            bgSample: Color(red: 0.086, green: 0.082, blue: 0.078),
                            cardSample: Color(red: 0.145, green: 0.141, blue: 0.137),
                            isSelected: settings.appTheme == .dark
                        ) {
                            settings.appTheme = .dark
                            settings.applyTheme()
                        }

                        ThemeCard(
                            theme: .system,
                            title: L10n.themeSystem,
                            subtitle: L10n.themeSystemSub,
                            accentColor: Color(red: 0.50, green: 0.50, blue: 0.50),
                            bgSample: Color(red: 0.935, green: 0.940, blue: 0.945),
                            cardSample: Color.white,
                            isSelected: settings.appTheme == .system
                        ) {
                            settings.appTheme = .system
                            settings.applyTheme()
                        }
                    }
                }
                .padding(20)
            }

            Card(header: L10n.appearanceHeaderDock) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.appearanceDockSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ], spacing: 14) {
                        AppIconChoiceCard(
                            style: .light,
                            title: L10n.iconStyleLight,
                            subtitle: L10n.iconStyleLightSub,
                            imageName: "AppIcon-Light",
                            isSelected: settings.appIconStyle == .light
                        ) {
                            settings.appIconStyle = .light
                        }

                        AppIconChoiceCard(
                            style: .black,
                            title: L10n.iconStyleBlack,
                            subtitle: L10n.iconStyleBlackSub,
                            imageName: "AppIcon-Black",
                            isSelected: settings.appIconStyle == .black
                        ) {
                            settings.appIconStyle = .black
                        }

                        AppIconChoiceCard(
                            style: .auto,
                            title: L10n.iconStyleAuto,
                            subtitle: L10n.iconStyleAutoSub,
                            imageName: settings.isDarkMode ? "AppIcon-Black" : "AppIcon-Light",
                            isSelected: settings.appIconStyle == .auto
                        ) {
                            settings.appIconStyle = .auto
                        }
                    }
                }
                .padding(20)
            }

            Card(header: L10n.appearanceHeaderIndicator) {
                Row(title: L10n.appearanceShowIndicator,
                    subtitle: L10n.appearanceIndicatorSubtitle,
                    first: true) {
                    Toggle("", isOn: $settings.showIndicator)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: L10n.appearanceTimeout,
                    subtitle: L10n.appearanceTimeoutSubtitle) {
                    WisprDropdown(selection: $settings.copyDismissTimeoutSeconds,
                                  options: [3, 5, 10, 15, 30]) { sec in
                        Text("\(sec) \(L10n.isRu ? "сек" : "sec")\(sec == 5 ? (L10n.isRu ? " (по умолч.)" : " (default)") : "")")
                    }
                }
            }
        }
    }
}

// MARK: - Интерактивная карточка выбора иконки приложения

struct AppIconChoiceCard: View {
    let style: AppIconStyle
    let title: String
    let subtitle: String
    let imageName: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var iconImage: NSImage {
        if let url = Bundle.main.url(forResource: imageName, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let resourcePath = Bundle.main.resourcePath {
            let p = (resourcePath as NSString).appendingPathComponent("\(imageName).png")
            if let img = NSImage(contentsOfFile: p) { return img }
        }
        if let img = NSImage(contentsOfFile: "/Users/artsu/work_tree/voice/Resources/\(imageName).png") {
            return img
        }
        return NSImage(named: "AppIcon") ?? NSImage()
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(nsImage: iconImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .shadow(color: Color.black.opacity(0.14), radius: 4, y: 2)
                    .padding(.top, 4)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(Palette.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Palette.accent : Palette.textTertiary, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    if isSelected {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Palette.cardHighlight : (hovering ? Palette.hover : Palette.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? Palette.accent : Palette.hairline, lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ThemeCard: View {
    let theme: AppTheme
    let title: String
    let subtitle: String
    let accentColor: Color
    let bgSample: Color
    let cardSample: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(bgSample)
                        .frame(height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accentColor.opacity(0.85))
                                .frame(width: 38, height: 5)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.35))
                                .frame(width: 60, height: 3.5)
                        }
                        Spacer()
                        Capsule()
                            .fill(accentColor)
                            .frame(width: 20, height: 10)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(cardSample)
                            .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                    )
                    .padding(.horizontal, 8)
                }

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(Palette.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? Palette.accent : Palette.textTertiary, lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                        if isSelected {
                            Circle()
                                .fill(Palette.accent)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Palette.cardHighlight : (hovering ? Palette.hover : Palette.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? Palette.accent : Palette.hairline, lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Система (System)

struct SystemTab: View {
    @ObservedObject var settings: AppSettings
    @State private var advanced = false

    var body: some View {
        SettingsPage(title: "Система") {
            Card(header: "Настройки приложения") {
                Row(title: "Запускать при входе в систему",
                    subtitle: "Автоматический запуск Intact вместе с macOS",
                    first: true) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(WisprToggleStyle())
                        .onChange(of: settings.launchAtLogin) { _, new in LoginItem.set(enabled: new) }
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

            Card(header: "Голосовые напоминания (Apple Reminders)") {
                Row(title: "Создавать напоминания по командам",
                    subtitle: "Команды «Напомни завтра в 15:00…», «Напоминание…», «Поставь задачу…» создают напоминание в Apple Reminders",
                    first: true) {
                    Toggle("", isOn: $settings.enableVoiceReminders)
                        .toggleStyle(WisprToggleStyle())
                }

                if settings.enableVoiceReminders {
                    Row(title: "Список напоминаний",
                        subtitle: "Список в приложении Напоминания (оставьте пустым для списка по умолчанию)") {
                        TextField("По умолчанию", text: $settings.voiceRemindersList)
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
                            .frame(width: 140)
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

// MARK: - Баннер первоначальной установки модели (Onboarding)

struct ModelOnboardingBanner: View {
    @ObservedObject var models = ModelManager.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerView

            if let downloading = models.downloading {
                downloadProgress(filename: downloading)
            } else {
                installButtons
            }

            if let err = models.lastError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.cardHighlight)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.accent.opacity(0.35), lineWidth: 1.5)
                )
        )
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.accent.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.onboardingWelcomeTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)

                Text(L10n.onboardingWelcomeSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func downloadProgress(filename: String) -> some View {
        let percentText = "\(Int(models.progress * 100))%"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Palette.accent)
                Text("\(L10n.onboardingDownloading) (\(filename))")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(percentText)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
            }

            ProgressView(value: models.progress)
                .progressViewStyle(.linear)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.dropdownBg)
        )
    }

    private var installButtons: some View {
        HStack(spacing: 12) {
            Button {
                models.download(models.recommendedModel)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.onboardingQuickInstall)
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(L10n.onboardingQuickInstallSub)
                            .font(.system(size: 10.5))
                            .opacity(0.85)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.accent)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                models.download(models.baseModel)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.onboardingBaseInstall)
                            .font(.system(size: 12, weight: .medium))
                        Text(L10n.onboardingBaseInstallSub)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.pill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 1)
                        )
                )
                .foregroundStyle(Palette.textPrimary)
            }
            .buttonStyle(.plain)
        }
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
                        if controller.state == .transcribing || controller.state == .processingAI {
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
    @State private var query = ""
    @State private var showClearPopover = false

    private var filteredEntries: [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return history.entries }
        return history.entries.filter { entry in
            entry.text.lowercased().contains(trimmed) ||
            entry.model.lowercased().contains(trimmed) ||
            entry.date.formatted(date: .abbreviated, time: .shortened).lowercased().contains(trimmed)
        }
    }

    var body: some View {
        SettingsPage(title: L10n.tabHistory) {
            if history.entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Palette.textTertiary)
                    Text(L10n.historyEmptyTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                    Text(L10n.historyEmptySubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 100)
            } else {
                // Поле поиска по истории и кнопка вызова поповера очистки
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)

                        TextField(L10n.historySearchPlaceholder, text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textPrimary)

                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.dropdownBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Palette.hairline, lineWidth: 1)
                            )
                    )

                    if !query.isEmpty {
                        Text("\(filteredEntries.count) / \(history.entries.count)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 6)
                    }

                    Spacer()

                    // Кнопка открытия поповера очистки
                    Button {
                        showClearPopover = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                            Text(L10n.historyClearBtn)
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7.5)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Palette.pill)
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showClearPopover, arrowEdge: .bottom) {
                        HistoryClearPopoverView { range in
                            history.clear(range: range)
                            showClearPopover = false
                        }
                    }
                }
                .padding(.bottom, 4)

                if filteredEntries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Palette.textTertiary)
                        Text(L10n.historyNoSearchResults)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                        Text("«\(query)»")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    Card {
                        ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                            HistoryRow(entry: entry, first: index == 0) {
                                history.delete(id: entry.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Поповер очистки истории с растровыми иконками

struct HistoryClearPopoverView: View {
    let onSelect: (HistoryClearRange) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.historyClearPopoverTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(L10n.historyClearPopoverSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle().fill(Palette.hairline).frame(height: 1)
                .padding(.bottom, 4)

            HistoryClearOptionRow(
                iconName: "history_clear_1h",
                title: L10n.historyClearLastHour,
                subtitle: L10n.historyClearLastHourSub,
                isDestructive: false
            ) {
                onSelect(.lastHour)
            }

            HistoryClearOptionRow(
                iconName: "history_clear_today",
                title: L10n.historyClearToday,
                subtitle: L10n.historyClearTodaySub,
                isDestructive: false
            ) {
                onSelect(.today)
            }

            HistoryClearOptionRow(
                iconName: "history_clear_7d",
                title: L10n.historyClearOlder7Days,
                subtitle: L10n.historyClearOlder7DaysSub,
                isDestructive: false
            ) {
                onSelect(.olderThan7Days)
            }

            HistoryClearOptionRow(
                iconName: "history_clear_all",
                title: L10n.historyClearAll,
                subtitle: L10n.historyClearAllSub,
                isDestructive: true
            ) {
                onSelect(.all)
            }
        }
        .padding(8)
        .frame(width: 320)
        .background(Palette.card)
    }
}

struct HistoryClearOptionRow: View {
    let iconName: String
    let title: String
    let subtitle: String
    let isDestructive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let img = loadLocalHistoryIcon(iconName) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isDestructive ? Color.red.opacity(0.95) : Palette.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? (isDestructive ? Color.red.opacity(0.12) : Palette.hover) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func loadLocalHistoryIcon(_ name: String) -> NSImage? {
        if let bundleURL = Bundle.main.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: bundleURL) {
            return img
        }
        let localPath = "/Users/artsu/work_tree/voice/Resources/\(name).png"
        return NSImage(contentsOfFile: localPath)
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    var first: Bool
    var onDelete: () -> Void
    @State private var hovering = false
    @State private var copied = false

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
                HStack(spacing: 8) {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Palette.pill)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(L10n.historyDeleteTooltip)

                    PillButton(title: copied ? (L10n.isRu ? "Скопировано!" : "Copied!") : L10n.historyCopyBtn,
                               symbol: copied ? "checkmark" : "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    }
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

