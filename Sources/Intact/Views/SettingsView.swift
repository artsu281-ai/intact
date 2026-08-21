import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case home, voice, history, chat, askAI, briefs, models, settings, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:       return L10n.tabHome
        case .voice:      return L10n.tabVoice
        case .history:    return L10n.tabHistory
        case .chat:       return L10n.tabChat
        case .askAI:      return L10n.tabAskAI
        case .briefs:     return L10n.tabBriefs
        case .models:     return L10n.tabModels
        case .settings:   return L10n.tabSettingsUnified
        case .about:      return L10n.tabAbout
        }
    }

    /// SF Symbol — используется везде, кроме сайдбара для разделов с кастомной иконкой.
    var icon: String {
        switch self {
        case .home:       return "house"
        case .voice:      return "mic"
        case .history:    return "clock.arrow.circlepath"
        case .chat:       return "bubble.left.and.bubble.right"
        case .askAI:      return "questionmark.bubble"
        case .briefs:     return "note.text"
        case .models:     return "square.stack.3d.up"
        case .settings:   return "gearshape"
        case .about:      return "info.circle"
        }
    }

    /// Кастомная иконка из IntactIcons для каждого раздела.
    var customIcon: IntactIconKind {
        switch self {
        case .home:     return .home
        case .voice:    return .voice
        case .history:  return .history
        case .chat:     return .chat
        case .askAI:    return .aiStar
        case .briefs:   return .briefs
        case .models:   return .models
        case .settings: return .settingsPage
        case .about:    return .about
        }
    }

    var category: String {
        switch self {
        case .home:
            return "HOME"
        case .voice, .history:
            return "VOICE"
        case .chat, .askAI, .briefs:
            return "ASSISTANT"
        case .models, .settings:
            return "MODELS_SETTINGS"
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
        .frame(minWidth: 1040, minHeight: 680)
        .background(Palette.page)
        .preferredColorScheme(settings.appTheme.colorScheme)
        .id(settings.appTheme)
    }

    // MARK: Боковик

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Поле поиска
            HStack(spacing: 8) {
                IntactIcon(kind: .search, size: 13)
                    .foregroundStyle(Palette.textTertiary)

                TextField(L10n.isRu ? "Поиск настроек…" : "Search settings…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.textPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        IntactIcon(kind: .close, size: 10)
                            .foregroundStyle(Palette.textTertiary)
                            .padding(2)
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
                // Главная
                ForEach(SettingsSection.allCases.filter { $0.category == "HOME" }) { item in
                    SidebarRow(item: item, selected: item == state.section) { state.section = item }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Голос (Диктовка, История)
                Text(L10n.sectionVoice)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                    .transition(.opacity)

                ForEach(SettingsSection.allCases.filter { $0.category == "VOICE" }) { item in
                    SidebarRow(item: item, selected: item == state.section) { state.section = item }
                }
                .transition(.opacity)

                // Ассистент (Чат с ИИ, Брифы и заметки)
                Text(L10n.sectionAssistant)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                    .transition(.opacity)

                ForEach(SettingsSection.allCases.filter { $0.category == "ASSISTANT" }) { item in
                    SidebarRow(item: item, selected: item == state.section) { state.section = item }
                }
                .transition(.opacity)

                // Модели и настройки
                Text(L10n.sectionModelsAndSettings)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                    .transition(.opacity)

                ForEach(SettingsSection.allCases.filter { $0.category == "MODELS_SETTINGS" }) { item in
                    SidebarRow(item: item, selected: item == state.section) { state.section = item }
                }
                .transition(.opacity)

                // О программе
                Text(L10n.sectionInfo)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
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
        .frame(width: 244)
        .background(Palette.sidebar)
    }

    private var searchResultsView: some View {
        let results = SettingsSearchIndex.shared.search(query: searchText)
        let grouped = Dictionary(grouping: results) { $0.section }
        let orderedSections = SettingsSection.allCases.filter { grouped[$0] != nil }

        return Group {
            if results.isEmpty {
                VStack(spacing: 8) {
                    IntactIcon(kind: .search, size: 24)
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
            Text("Intact v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private var statusColor: Color {
        if Permissions.missingDescription != nil { return Palette.iconDanger }
        return controller.engineReady ? Palette.iconSuccess : Palette.iconWarning
    }

    private var statusText: String {
        if let missing = Permissions.missingDescription { return missing }
        return controller.engineReady ? "Готов к диктовке" : "Модель загружается…"
    }

    private var detail: some View {
        Group {
            switch state.section {
            case .home:       HomeTab(settings: settings, onOpenSection: { state.section = $0 })
            case .voice:      VoiceTab(settings: settings)
            case .history:    HistoryTab(settings: settings)
            case .chat:       ChatTab(settings: settings, onOpenSection: { state.section = $0 })
            case .askAI:      AskAITab(settings: settings, onOpenSection: { state.section = $0 })
            case .briefs:     BriefsTab(settings: settings, onOpenSection: { state.section = $0 })
            case .models:     ModelsHub(settings: settings)
            case .settings:   SettingsTab(settings: settings, onOpenModels: { state.section = .models })
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
        // Главная (Home)
        .init(title: "Главная", subtitle: "Обзор и быстрый доступ", section: .home,
              keywords: ["главная", "home", "дашборд", "dashboard", "старт", "обзор"]),

        // Чат и ассистент (Chat & Briefs)
        .init(title: "Чат с ИИ", subtitle: "Диалог с персональным ассистентом", section: .chat,
              keywords: ["чат", "chat", "ии", "ai", "ассистент", "assistant", "диалог", "вопрос", "сообщение"]),
        .init(title: "Брифы и заметки", subtitle: "Сводка голосовых диктовок и заметок", section: .briefs,
              keywords: ["брифы", "briefs", "анализ", "сводка", "заметки", "задачи", "todo", "выжимка", "история", "диктовки", "apple notes", "reminders"]),
        .init(title: "Спросите ИИ", subtitle: "Хоткей: вопрос голосом — ответ сразу вставляется", section: .askAI,
              keywords: ["спросите", "ask", "вопрос", "хоткей", "hotkey", "правый", "option", "ии", "ai", "ответ", "мгновенный"]),

        // Диктовка (Voice)
        .init(title: "Горячая клавиша", subtitle: "Запуск диктовки", section: .voice,
              keywords: ["горячая", "клавиша", "hotkey", "hot key", "shortcut", "шорткат", "клавиатура", "keyboard", "модификатор", "modifier", "option", "alt"]),
        .init(title: "Режим активации", subtitle: "Удержание / переключатель", section: .voice,
              keywords: ["режим", "активация", "activation", "mode", "удержание", "hold", "toggle", "переключатель"]),
        .init(title: "Микрофон", subtitle: "Источник записи звука", section: .voice,
              keywords: ["микрофон", "microphone", "mic", "аудио", "audio", "запись", "recording", "устройство", "device", "вход", "input"]),
        .init(title: "Язык диктовки", subtitle: "Автоопределение русского / английского", section: .voice,
              keywords: ["язык", "language", "диктовка", "dictation", "автоопределение", "auto", "русский", "russian", "английский", "english", "распознавание"]),
        .init(title: "Вставка текста", subtitle: "Способ вставки результата", section: .voice,
              keywords: ["вставка", "paste", "insertion", "текст", "text", "буфер", "clipboard", "посимвольно", "type", "копирование"]),
        .init(title: "Разрешения", subtitle: "Мониторинг ввода, универсальный доступ", section: .voice,
              keywords: ["разрешения", "permissions", "доступ", "accessibility", "мониторинг", "monitoring", "ввод", "input", "права"]),
        .init(title: "Перевод на английский", subtitle: "Автоперевод речи", section: .voice,
              keywords: ["перевод", "translate", "translation", "английский", "english", "автоперевод"]),
        .init(title: "Подавление шума", subtitle: "[МУЗЫКА], [АПЛОДИСМЕНТЫ]", section: .voice,
              keywords: ["шум", "noise", "подавление", "suppress", "музыка", "music", "аплодисменты", "теги", "tags", "фильтр"]),
        .init(title: "Пользовательский словарь", subtitle: "Термины и имена для Whisper", section: .voice,
              keywords: ["словарь", "vocabulary", "dictionary", "термины", "terms", "имена", "names", "подсказки", "prompts", "prompt"]),
        .init(title: "Тест микрофона", subtitle: "Проверка записи", section: .voice,
              keywords: ["тест", "test", "проверка", "check", "микрофон", "microphone", "mic", "запись", "record"]),

        // Настройки (Settings)
        .init(title: "Язык интерфейса", subtitle: "Русский / English", section: .settings,
              keywords: ["язык", "language", "интерфейс", "interface", "русский", "english", "английский", "локализация", "localization"]),
        .init(title: "Тема", subtitle: "Белая, терракотовая, тёмная", section: .settings,
              keywords: ["тема", "theme", "цвет", "color", "оформление", "appearance", "белая", "white", "терракотовая", "terracotta", "тёмная", "dark", "ночная", "светлая", "light", "стиль"]),
        .init(title: "Иконка приложения", subtitle: "Светлая, чёрная, авто", section: .settings,
              keywords: ["иконка", "icon", "dock", "док", "значок", "светлая", "light", "чёрная", "black", "приложение", "app"]),
        .init(title: "Индикатор диктовки", subtitle: "Плавающий индикатор записи", section: .settings,
              keywords: ["индикатор", "indicator", "запись", "recording", "плавающий", "floating", "hud", "pill", "спектр", "spectrum"]),
        .init(title: "Таймаут копирования", subtitle: "Секунды до скрытия окна", section: .settings,
              keywords: ["таймаут", "timeout", "копирование", "copy", "dismiss", "скрытие", "окно", "window", "секунды"]),
        .init(title: "Запуск при входе", subtitle: "Автозагрузка с macOS", section: .settings,
              keywords: ["запуск", "launch", "вход", "login", "автозагрузка", "autostart", "startup", "загрузка", "boot"]),
        .init(title: "Значок в Dock", subtitle: "Отображать / скрывать", section: .settings,
              keywords: ["dock", "док", "значок", "icon", "показать", "show", "скрыть", "hide", "панель"]),
        .init(title: "Заглушать звук", subtitle: "Тишина во время диктовки", section: .settings,
              keywords: ["заглушать", "mute", "звук", "audio", "sound", "тишина", "silence", "динамики", "speakers", "громкость"]),
        .init(title: "Пауза музыки", subtitle: "Apple Music, Spotify", section: .settings,
              keywords: ["пауза", "pause", "музыка", "music", "видео", "video", "spotify", "apple music", "плеер", "player", "медиа"]),
        .init(title: "Звуковые сигналы", subtitle: "Звуки начала и конца записи", section: .settings,
              keywords: ["звуковые", "sounds", "сигналы", "effects", "chime", "начало", "start", "конец", "stop", "ошибка"]),
        .init(title: "Провайдер ИИ", subtitle: "Локально или в облаке", section: .settings,
              keywords: ["ии", "ai", "искусственный интеллект", "провайдер", "provider", "claude", "anthropic", "llm", "локально", "local", "облако", "cloud"]),
        .init(title: "API-ключ Anthropic", subtitle: "Ключ для облачного ИИ", section: .settings,
              keywords: ["api", "ключ", "key", "anthropic", "claude", "keychain", "облако", "cloud"]),
        .init(title: "Причёсывание текста ИИ", subtitle: "Убирает слова-паразиты", section: .settings,
              keywords: ["причёсывание", "cleanup", "текст", "text", "слова-паразиты", "filler", "форматирование", "formatting"]),

        // История (History)
        .init(title: "История записей", subtitle: "Поиск и просмотр диктовок", section: .history,
              keywords: ["история", "history", "записи", "records", "диктовки", "поиск", "копировать"]),
        .init(title: "Автоочистка истории", subtitle: "Лимит строк и очистка по таймеру", section: .history,
              keywords: ["автоочистка", "очистка", "лимит", "таймер", "ежедневно", "еженедельно", "ежемесячно", "строк", "записей", "хранение", "clear", "limit", "schedule"]),

        // Модели (Models)
        .init(title: "Модели Whisper", subtitle: "Установка и выбор модели", section: .models,
              keywords: ["модель", "model", "whisper", "ggml", "скачать", "download", "установить", "install", "large", "turbo", "base", "medium", "small"]),
        .init(title: "Потоковое распознавание", subtitle: "Текст во время речи", section: .models,
              keywords: ["потоковое", "streaming", "реалтайм", "realtime", "live", "черновик", "draft", "во время", "речь"]),
        .init(title: "Потоки CPU", subtitle: "Число ядер для распознавания", section: .models,
              keywords: ["потоки", "threads", "cpu", "ядра", "cores", "производительность", "performance", "скорость", "speed"]),
        .init(title: "Локальные модели ИИ", subtitle: "Причёсывание текста, GGUF", section: .models,
              keywords: ["llm", "локальная", "модель", "gguf", "причёсывание", "cleanup"]),

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
                SidebarIntactIcon(kind: entry.section.customIcon, selected: isActive, size: 15)
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
                SidebarIntactIcon(kind: item.customIcon, selected: selected, size: 18)
                    .frame(width: 20)
                    .scaleEffect(selected ? 1.06 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
                Text(item.title)
                    .font(.system(size: 14, weight: selected ? .semibold : .medium))
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
                    IntactIcon(kind: .success, size: 15)
                        .foregroundStyle(Palette.iconSuccess)
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
                    IntactIcon(kind: .chevronRight, size: 12, weight: .medium)
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
                    .foregroundStyle(Palette.iconDanger)
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
            IconTile(kind: .aiStar, tone: .active, side: 40)

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
                IntactIcon(kind: .download, size: 15)
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
                    IntactIcon(kind: .download, size: 16, weight: .medium)
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
                    IntactIcon(kind: .quickSummary, size: 14)
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
                    PillButton(title: "Обновить", icon: .refresh) {
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
                if let err = controller.lastError {
                    Row(title: "Ошибка") {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.iconDanger)
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
    @ObservedObject var settings: AppSettings
    @ObservedObject private var history = History.shared
    @State private var query = ""
    @State private var showClearPopover = false
    @State private var exportError: String? = nil

    /// Выгружает то, что сейчас видно: с активным поиском — только найденное.
    private func exportHistory() {
        let entries = filteredEntries
        let text = Exporter.historyMarkdown(entries)
        switch Exporter.save(text: text, suggestedName: "Intact-история-\(Exporter.fileStamp())") {
        case .saved(let url):  Exporter.reveal(url)
        case .cancelled:       break
        case .failed(let msg): exportError = msg
        }
    }

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

            // ── Автоочистка и лимиты ────────────────────────────────────
            Card(header: L10n.historyAutoClearHeader) {
                Row(title: L10n.historyLimitTitle,
                    subtitle: L10n.historyLimitSub,
                    first: true) {
                    WisprDropdown(selection: $settings.historyLimitOption,
                                  options: HistoryLimitOption.allCases) { opt in
                        Text(opt.title)
                    }
                }

                Row(title: L10n.historyScheduleTitle,
                    subtitle: L10n.historyScheduleSub) {
                    WisprDropdown(selection: $settings.historyAutoClearSchedule,
                                  options: HistoryAutoClearSchedule.allCases) { sch in
                        Text(sch.title)
                    }
                }
            }

            // ── Список записей ──────────────────────────────────────────
            if history.entries.isEmpty {
                VStack(spacing: 14) {
                    IconTile(kind: .history, tone: .muted, side: 56)
                    Text(L10n.historyEmptyTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                    Text(L10n.historyEmptySubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                // Поле поиска по истории и кнопка вызова поповера очистки
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        IntactIcon(kind: .search, size: 13)
                            .foregroundStyle(Palette.textTertiary)

                        TextField(L10n.historySearchPlaceholder, text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textPrimary)

                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                IntactIcon(kind: .close, size: 10)
                                    .foregroundStyle(Palette.textTertiary)
                                    .padding(2)
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

                    // Выгрузка истории в Markdown-файл
                    Button {
                        exportHistory()
                    } label: {
                        HStack(spacing: 6) {
                            IntactIcon(kind: .export, size: 13)
                            Text("Выгрузить")
                                .font(.system(size: 13, weight: .medium))
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
                    .help("Сохранить историю диктовок в файл Markdown")
                    .onHover { if $0 { exportError = nil } }

                    // Кнопка открытия поповера очистки
                    Button {
                        showClearPopover = true
                    } label: {
                        HStack(spacing: 6) {
                            IntactIcon(kind: .clearChat, size: 12)
                            Text(L10n.historyClearBtn)
                                .font(.system(size: 13, weight: .medium))
                            IntactIcon(kind: .chevronDown, size: 8)
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

                if let err = exportError {
                    HStack(spacing: 8) {
                        IntactIcon(kind: .error, size: 15)
                            .foregroundStyle(Palette.iconDanger)
                        Text(err)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.iconDanger)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.iconDanger.opacity(0.08))
                    )
                    .padding(.bottom, 8)
                }

                if filteredEntries.isEmpty {
                    VStack(spacing: 10) {
                        IntactIcon(kind: .search, size: 32)
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

// MARK: - Поповер очистки истории с кастомными векторными иконками

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
                iconKind: .clearHour,
                title: L10n.historyClearLastHour,
                subtitle: L10n.historyClearLastHourSub,
                isDestructive: false
            ) {
                onSelect(.lastHour)
            }

            HistoryClearOptionRow(
                iconKind: .clearToday,
                title: L10n.historyClearToday,
                subtitle: L10n.historyClearTodaySub,
                isDestructive: false
            ) {
                onSelect(.today)
            }

            HistoryClearOptionRow(
                iconKind: .clearWeek,
                title: L10n.historyClearOlder7Days,
                subtitle: L10n.historyClearOlder7DaysSub,
                isDestructive: false
            ) {
                onSelect(.olderThan7Days)
            }

            HistoryClearOptionRow(
                iconKind: .clearAll,
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
    let iconKind: IntactIconKind
    let title: String
    let subtitle: String
    let isDestructive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(kind: iconKind, tone: isDestructive ? .danger : .active, side: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isDestructive ? Palette.iconDanger.opacity(0.95) : Palette.textPrimary)
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
                    .fill(hovering ? (isDestructive ? Palette.iconDanger.opacity(0.10) : Palette.hover) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    var first: Bool
    var onDelete: () -> Void
    @State private var hovering = false
    @State private var copied = false
    @State private var expanded = false

    /// Три строки — предел, после которого запись обрезается и появляется
    /// кнопка «показать целиком».
    private var isTruncatable: Bool { entry.text.count > 180 }

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 22)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.text)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(expanded ? nil : 3)
                        .lineSpacing(2.5)
                        .fixedSize(horizontal: false, vertical: true)

                    if isTruncatable {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                        } label: {
                            HStack(spacing: 5) {
                                IntactIcon(kind: .eye, size: 12)
                                Text(expanded ? "Свернуть" : "Показать целиком")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(String(format: "%.1f", entry.seconds)) с · \(entry.model)")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Button(action: onDelete) {
                        IntactIcon(kind: .clearAll, size: 13)
                            .foregroundStyle(hovering ? Palette.iconDanger : Palette.iconMuted)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Palette.pill)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(L10n.historyDeleteTooltip)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            IntactIcon(kind: copied ? .copied : .copy, size: 12)
                                .foregroundStyle(copied ? Palette.accent : Palette.textSecondary)
                            Text(copied ? (L10n.isRu ? "Скопировано!" : "Copied!") : L10n.historyCopyBtn)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(copied ? Palette.accent : Palette.textPrimary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(copied ? Palette.accent.opacity(0.10) : Palette.pill)
                        )
                    }
                    .buttonStyle(.plain)
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
                    PillButton(title: "Показать файл", icon: .folder) {
                        NSWorkspace.shared.selectFile(Log.path, inFileViewerRootedAtPath: "")
                    }
                }
            }

            Card(header: "Приватность и безопасность") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        IntactIcon(kind: .lock, size: 15)
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

