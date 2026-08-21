import Foundation
import SwiftUI

/// Модуль локализации интерфейса Intact (Русский / English).
enum L10n {
    static var lang: InterfaceLanguage {
        AppSettings.shared.interfaceLanguage
    }

    static var isRu: Bool {
        lang == .russian
    }

    // MARK: - Разделы бокового меню
    static var sectionVoice: String { isRu ? "ГОЛОС" : "VOICE" }
    static var sectionAssistant: String { isRu ? "АССИСТЕНТ" : "ASSISTANT" }
    static var sectionModelsAndSettings: String { isRu ? "МОДЕЛИ И НАСТРОЙКИ" : "MODELS & SETTINGS" }
    static var sectionWorkspace: String { isRu ? "АССИСТЕНТ И ИСТОРИЯ" : "WORKSPACE" }
    static var sectionSettings: String { isRu ? "НАСТРОЙКИ" : "SETTINGS" }
    static var sectionInfo: String { isRu ? "О ПРОГРАММЕ" : "ABOUT" }

    static var tabHome: String { isRu ? "Главная" : "Home" }
    static var tabVoice: String { isRu ? "Диктовка" : "Dictation" }
    static var tabBriefs: String { isRu ? "Брифы и заметки" : "Briefs & Notes" }
    static var tabSettingsUnified: String { isRu ? "Настройки" : "Settings" }

    static var tabGeneral: String { isRu ? "Основное" : "General" }
    static var tabAppearance: String { isRu ? "Оформление" : "Appearance" }
    static var tabSystem: String { isRu ? "Система" : "System" }
    static var tabModel: String { isRu ? "Модель" : "Model" }
    static var tabModels: String { isRu ? "Модели" : "Models" }
    static var tabLanguage: String { isRu ? "Язык и текст" : "Language & Text" }
    static var tabMicrophone: String { isRu ? "Микрофон" : "Microphone" }
    static var tabHistory: String { isRu ? "История" : "History" }
    static var tabAbout: String { isRu ? "О программе" : "About" }
    static var tabAI: String { isRu ? "ИИ" : "AI" }
    static var tabChat: String { isRu ? "Чат с ИИ" : "AI Chat" }
    static var chatMenuTitle: String { isRu ? "Чат с ИИ…" : "AI Chat…" }
    static var chatOpenBtn: String { isRu ? "Открыть чат с ИИ" : "Open AI Chat" }

    // MARK: - Статус
    static var statusReady: String { isRu ? "Готов к диктовке" : "Ready for dictation" }
    static var statusLoading: String { isRu ? "Модель загружается…" : "Loading model…" }
    static var statusNoModel: String { isRu ? "Модель не установлена" : "No model installed" }

    // MARK: - Первоначальная установка (Onboarding)
    static var onboardingTitle: String { isRu ? "Установка языковой модели" : "Install Speech Model" }
    static var onboardingWelcomeTitle: String { isRu ? "Добро пожаловать в Intact!" : "Welcome to Intact!" }
    static var onboardingWelcomeSubtitle: String {
        isRu
        ? "Для работы 100% локальной диктовки без интернета требуется языковая модель Whisper. Установите рекомендуемую модель в один клик:"
        : "Intact performs 100% on-device speech dictation using Whisper. Install a recommended model with one click to get started:"
    }
    static var onboardingQuickInstall: String { isRu ? "Скачать рекомендуемую модель (large-v3-turbo)" : "Download Recommended Model (large-v3-turbo)" }
    static var onboardingQuickInstallSub: String { isRu ? "1.5 ГБ · Высокая скорость и наилучшая точность (ru/en)" : "1.5 GB · Fast speed and best accuracy for mixed ru/en" }
    static var onboardingBaseInstall: String { isRu ? "Быстрый старт: базовая модель (base, 148 МБ)" : "Quick Start: Base model (base, 148 MB)" }
    static var onboardingBaseInstallSub: String { isRu ? "148 МБ · Мгновенное скачивание для быстрой проверки" : "148 MB · Instant download to start right away" }
    static var onboardingDownloading: String { isRu ? "Загрузка модели…" : "Downloading model…" }
    static var onboardingModelReady: String { isRu ? "✅ Модель успешно установлена и готова к работе" : "✅ Model installed and ready to dictate" }
    static var onboardingNoModelBanner: String { isRu ? "⚠︎ Модель Whisper ещё не скачана. Нажмите для быстрой установки." : "⚠︎ Whisper model not installed yet. Click for quick install." }

    // MARK: - Оформление (Appearance)
    static var appearanceHeaderTheme: String { isRu ? "Тема интерфейса" : "Interface Theme" }
    static var appearanceThemeDescription: String { isRu ? "Выберите тему приложения и плавающего индикатора записи." : "Choose the application and recording indicator theme." }
    static var appearanceHeaderLanguage: String { isRu ? "Язык программы" : "Interface Language" }
    static var appearanceLanguageSubtitle: String { isRu ? "Язык интерфейса приложения (Русский / English)" : "Application display language (Russian / English)" }
    static var appearanceHeaderDock: String { isRu ? "Иконка приложения" : "Application Icon" }
    static var appearanceDockSubtitle: String { isRu ? "Выберите вариант иконки для Dock и системы (Светлая, Чёрная или Авто)" : "Choose application icon for Dock and macOS (Light, Black or Auto)" }
    static var appearanceHeaderIndicator: String { isRu ? "Индикатор диктовки" : "Dictation Indicator" }
    static var appearanceShowIndicator: String { isRu ? "Показывать плавающий индикатор во время записи" : "Show floating indicator during recording" }
    static var appearanceIndicatorSubtitle: String { isRu ? "Компактный плавающий статус с живым спектром звука" : "Compact floating pill with live audio spectrum" }
    static var appearanceTimeout: String { isRu ? "Таймаут карточки копирования" : "Copy card dismiss timeout" }
    static var appearanceTimeoutSubtitle: String { isRu ? "Через сколько секунд скрывать окно, если поле ввода не было выбрано" : "Seconds before closing the prompt if no input field is focused" }

    // MARK: - Варианты иконок
    static var iconStyleAuto: String { isRu ? "Автоматически" : "Automatic" }
    static var iconStyleAutoSub: String { isRu ? "Светлая днём, чёрная ночью" : "Light by day, black by night" }
    static var iconStyleLight: String { isRu ? "Светлая" : "Light" }
    static var iconStyleLightSub: String { isRu ? "Молочный опал" : "Frosted opal glass" }
    static var iconStyleBlack: String { isRu ? "Чёрная" : "Black" }
    static var iconStyleBlackSub: String { isRu ? "Jet Black Minimal" : "Jet black minimal" }

    // MARK: - Темы
    static var themeWhite: String { isRu ? "Обычная белая" : "Clean White" }
    static var themeWhiteSub: String { isRu ? "Классический светлый стиль macOS (по умолчанию)" : "Classic macOS light style (default)" }
    static var themeTerracotta: String { isRu ? "Тёплая терракотовая" : "Warm Terracotta" }
    static var themeTerracottaSub: String { isRu ? "Уютный песочно-льняной холст и глина" : "Cozy oatmeal linen and terracotta clay" }
    static var themeDark: String { isRu ? "Тёмная (Оникс / Мокка)" : "Dark (Onyx / Mocha)" }
    static var themeDarkSub: String { isRu ? "Глубокий ночной фон для комфорта глаз" : "Deep nighttime palette for eye comfort" }
    static var themeSystem: String { isRu ? "Как в системе" : "System" }
    static var themeSystemSub: String { isRu ? "Автоматически следовать за темой macOS" : "Automatically follows macOS theme" }

    // MARK: - ИИ (AI)
    static var aiHeaderProvider: String { isRu ? "Провайдер ИИ" : "AI Provider" }
    static var aiProviderSubtitle: String { isRu ? "Кто причёсывает текст после распознавания" : "Who cleans up text after transcription" }
    static var aiProviderNone: String { isRu ? "Выключено" : "Off" }
    static var aiProviderLocal: String { isRu ? "Локально" : "Local" }
    static var aiProviderCloud: String { isRu ? "Облако (Claude)" : "Cloud (Claude)" }
    static var aiHeaderCloud: String { isRu ? "Облачный провайдер" : "Cloud Provider" }
    static var aiApiKeyLabel: String { isRu ? "API-ключ Anthropic" : "Anthropic API Key" }
    static var aiApiKeyPlaceholder: String { isRu ? "sk-ant-…" : "sk-ant-…" }
    static var aiApiKeySave: String { isRu ? "Сохранить" : "Save" }
    static var aiApiKeySavedSub: String { isRu ? "Ключ хранится в Keychain, не в настройках приложения" : "Key is stored in Keychain, not in app settings" }
    static var aiCloudModelLabel: String { isRu ? "Модель" : "Model" }
    static var aiHeaderLocal: String { isRu ? "Локальная модель" : "Local Model" }
    static var aiLocalServerMissing: String { isRu ? "Локальный AI-сервер не найден" : "Local AI server not found" }
    static var aiLocalServerMissingSub: String { isRu ? "Нужен llama-server из llama.cpp — можно поставить прямо отсюда" : "Requires llama-server from llama.cpp — install it right here" }
    static var aiInstallHomebrewBtn: String { isRu ? "Установить через Homebrew" : "Install via Homebrew" }
    static var aiInstalling: String { isRu ? "Установка…" : "Installing…" }
    static var aiHomebrewMissing: String { isRu ? "Homebrew не найден. Установите его с brew.sh, затем вернитесь сюда." : "Homebrew not found. Install it from brew.sh, then come back here." }
    static var aiLocalModelsTitle: String { isRu ? "Модели" : "Models" }
    static var aiLocalServerStatus: String { isRu ? "Состояние локального сервера" : "Local server status" }
    static var aiLocalServerRunning: String { isRu ? "Запущен и готов" : "Running and ready" }
    static var aiLocalServerStopped: String { isRu ? "Остановлен" : "Stopped" }
    static var aiRestartBtn: String { isRu ? "Перезапустить" : "Restart" }
    static var aiHeaderFeatures: String { isRu ? "Возможности" : "Features" }
    static var aiCleanupToggle: String { isRu ? "Причёсывать текст ИИ" : "Clean up text with AI" }
    static var aiCleanupToggleSub: String { isRu ? "Убирает слова-паразиты и поправляет пунктуацию перед вставкой" : "Removes filler words and fixes punctuation before inserting" }
    static var hudProcessingAI: String { isRu ? "Улучшаю…" : "Refining…" }
    // Длина сознательно на уровне hudTranscribing («Распознаю…») — капсула HUD
    // фиксированной ширины (112pt), «Спрашиваю ИИ…» в неё не помещалось и вылезало за края.
    static var hudAnsweringAI: String { isRu ? "Спрашиваю…" : "Asking…" }
    static var aiExperimentHeader: String { isRu ? "Эксперимент: всё-в-одном через Gemma" : "Experiment: all-in-one via Gemma" }
    static var aiExperimentSubtitle: String {
        isRu
        ? "Отдельная песочница для сравнения — не участвует в основной диктовке. Gemma сама распознаёт голос и сразу причёсывает текст, без Whisper."
        : "A separate sandbox for comparison — not part of normal dictation. Gemma transcribes speech and cleans it up in one pass, without Whisper."
    }
    static var aiExperimentModelRow: String { isRu ? "Gemma 4 E2B с поддержкой аудио" : "Gemma 4 E2B with audio support" }
    static var aiExperimentDownloadBtn: String { isRu ? "Скачать" : "Download" }
    static var aiExperimentNotInstalled: String { isRu ? "Сначала скачай модель (~3.2 ГБ, два файла)" : "Download the model first (~3.2 GB, two files)" }
    static var aiExperimentRecordBtn: String { isRu ? "Записать" : "Record" }
    static var aiExperimentStopBtn: String { isRu ? "Остановить" : "Stop" }
    static var aiExperimentProcessing: String { isRu ? "Gemma распознаёт и причёсывает…" : "Gemma is transcribing and cleaning up…" }
    static var aiExperimentResultTitle: String { isRu ? "Результат" : "Result" }

    // MARK: - Индикатор диктовки (HUD)
    static var hudTranscribing: String { isRu ? "Распознаю…" : "Transcribing…" }
    static var hudNoteSaved: String { isRu ? "Заметка сохранена" : "Note saved" }
    static var hudReminderSaved: String { isRu ? "Напоминание:" : "Reminder:" }
    static var hudTextReady: String { isRu ? "Текст готов к копированию" : "Text ready to copy" }
    static var hudCopyBtn: String { isRu ? "Скопировать" : "Copy" }
    static var hudCopyShortcut: String { isRu ? "C или Enter" : "C or Enter" }

    // MARK: - Основное (General)
    static var genHeaderHotKey: String { isRu ? "Запуск диктовки" : "Dictation Trigger" }
    static var genHotKey: String { isRu ? "Горячая клавиша" : "Hot Key" }
    static var genActivationMode: String { isRu ? "Режим активации" : "Activation Mode" }
    static var genHeaderDevices: String { isRu ? "Устройства и язык" : "Devices & Language" }
    static var genMic: String { isRu ? "Микрофон" : "Microphone" }
    static var genMicSubtitle: String { isRu ? "Источник записи звука для распознавания" : "Audio input source for recognition" }
    static var genDictationLang: String { isRu ? "Язык диктовки" : "Dictation Language" }
    static var genDictationLangSubtitle: String { isRu ? "Автоопределение поддерживает смесь русского и английского" : "Auto-detect supports mixing Russian and English" }
    static var genOutputMode: String { isRu ? "Вставка текста" : "Text Insertion" }
    static var genHeaderPermissions: String { isRu ? "Разрешения системы" : "System Permissions" }
    static var genPermInput: String { isRu ? "Мониторинг ввода" : "Input Monitoring" }
    static var genPermInputSub: String { isRu ? "Чтобы читать удержание клавиши ⌥" : "To detect holding modifier keys like ⌥" }
    static var genPermAX: String { isRu ? "Универсальный доступ" : "Accessibility" }
    static var genPermAXSub: String { isRu ? "Чтобы автоматически вставлять распознанный текст" : "To automatically insert recognized text" }
    static var genGranted: String { isRu ? "выдано" : "granted" }
    static var genGrantBtn: String { isRu ? "Разрешить" : "Grant" }

    // MARK: - Система (System)
    static var sysHeaderApp: String { isRu ? "Настройки приложения" : "Application Settings" }
    static var sysLaunchAtLogin: String { isRu ? "Запускать при входе в систему" : "Launch at Login" }
    static var sysLaunchAtLoginSub: String { isRu ? "Автоматический запуск Intact вместе с macOS" : "Automatically start Intact on macOS login" }
    static var sysDockIcon: String { isRu ? "Значок в Dock" : "Dock Icon" }
    static var sysDockIconSub: String { isRu ? "Отображать приложение в панели Dock" : "Show application in the macOS Dock" }
    static var sysHeaderSound: String { isRu ? "Звук и медиа" : "Audio & Media" }
    static var sysMuteAudio: String { isRu ? "Заглушать системный звук во время речи" : "Mute system audio while dictating" }
    static var sysMuteAudioSub: String { isRu ? "Временно отключает динамики, чтобы фоновые звуки не лезли в микрофон" : "Temporarily mutes output so speakers don't bleed into mic" }
    static var sysPauseMedia: String { isRu ? "Приостанавливать музыку и видео" : "Pause music and video" }
    static var sysPauseMediaSub: String { isRu ? "Ставит на паузу Apple Music, Spotify и другие плееры на время диктовки" : "Pauses Apple Music, Spotify and media players during speech" }
    static var sysSounds: String { isRu ? "Звуковые сигналы диктовки" : "Dictation sound effects" }
    static var sysSoundsSub: String { isRu ? "Короткие звуки при начале, окончании и ошибке записи" : "Short chimes on start, stop, and errors" }
    static var sysHeaderText: String { isRu ? "Форматирование текста" : "Text Formatting" }
    static var sysTrimPeriod: String { isRu ? "Убирать точку в конце" : "Trim trailing period" }
    static var sysTrimPeriodSub: String { isRu ? "Удалять завершающую точку при коротких фразах" : "Remove trailing punctuation from short phrases" }
    static var sysAppendSpace: String { isRu ? "Добавлять пробел после текста" : "Append trailing space" }
    static var sysAppendSpaceSub: String { isRu ? "Автоматически ставить пробел после вставленного фрагмента" : "Insert a trailing space after inserted text" }
    static var sysKeepHistory: String { isRu ? "Сохранять историю распознаваний" : "Save transcription history" }
    static var sysKeepHistorySub: String { isRu ? "Возможность просмотреть и скопировать прошлые записи" : "Access and copy previously dictated notes" }
    static var sysHeaderNotes: String { isRu ? "Голосовые заметки (Apple Notes)" : "Voice Notes (Apple Notes)" }
    static var sysNotesEnable: String { isRu ? "Создавать заметки по командам" : "Create notes via voice commands" }
    static var sysNotesEnableSub: String { isRu ? "Команды «Заметка…», «Создай заметку…» сохраняют текст в Apple Notes" : "Phrases like 'Note...', 'Take a note...' save text directly to Apple Notes" }
    static var sysNotesFolder: String { isRu ? "Папка в Заметках" : "Notes Folder" }
    static var sysNotesFolderSub: String { isRu ? "Папка в Заметках (по умолчанию «Intact»)" : "Folder name in Apple Notes (default 'Intact')" }
    static var sysHeaderReminders: String { isRu ? "Голосовые напоминания (Apple Reminders)" : "Voice Reminders (Apple Reminders)" }
    static var sysRemindersEnable: String { isRu ? "Создавать напоминания по командам" : "Create reminders via voice commands" }
    static var sysRemindersEnableSub: String { isRu ? "Команды «Напомни завтра…», «Поставь задачу…» создают напоминание" : "Commands like 'Remind me tomorrow...', 'Set task...' create reminders" }
    static var sysRemindersList: String { isRu ? "Список напоминаний" : "Reminders List" }
    static var sysRemindersListSub: String { isRu ? "Список в Напоминаниях (оставьте пустым для списка по умолчанию)" : "List in Reminders (leave blank for default)" }
    static var sysAdvanced: String { isRu ? "Дополнительно" : "Advanced" }
    static var sysIgnoreShortMs: String { isRu ? "Игнорировать нажатия короче" : "Ignore key presses shorter than" }
    static var sysIgnoreShortMsSub: String { isRu ? "Защита от случайного касания клавиши-модификатора" : "Guard against accidental taps of modifier keys" }
    static var sysMaxRecordLength: String { isRu ? "Максимальная длина записи" : "Maximum recording duration" }

    // MARK: - Модели (Models)
    static var modelCatalogTitle: String { isRu ? "Модели Whisper" : "Whisper Models" }
    static var modelCheckUpdates: String { isRu ? "Проверить обновления" : "Check for Updates" }
    static var modelChecking: String { isRu ? "Проверка…" : "Checking…" }
    static var modelHeaderSpeed: String { isRu ? "Скорость и фоновый движок" : "Speed & Engine" }
    static var modelStreaming: String { isRu ? "Распознавать во время речи" : "Real-time stream transcription" }
    static var modelStreamingSub: String { isRu ? "Текст распознаётся в фоне прямо во время речи" : "Processes audio live while you speak for zero-wait delivery" }
    static var modelServerStatus: String { isRu ? "Состояние whisper-server" : "whisper-server status" }
    static var modelRestartBtn: String { isRu ? "Перезапустить" : "Restart" }
    static var modelLatency: String { isRu ? "Задержка последней вставки" : "Last insertion latency" }
    static var modelLatencyInstant: String { isRu ? "мгновенно" : "instant" }
    static var modelDraftInterval: String { isRu ? "Черновик каждые" : "Draft interval" }
    static var modelAudioContext: String { isRu ? "Аудиоконтекст энкодера" : "Encoder audio context" }
    static var modelAudioContextSub: String { isRu ? "Урезанный считается быстрее, но обрезает окно распознавания" : "Shorter windows run faster on lighter CPUs" }
    static var modelCpuThreads: String { isRu ? "Потоков CPU" : "CPU Threads" }
    static var modelFilePath: String { isRu ? "Файл модели" : "Model File" }
    static var modelChooseBtn: String { isRu ? "Выбрать…" : "Choose…" }
    static var modelFolderBtn: String { isRu ? "Папка" : "Folder" }

    // MARK: - Язык и текст (Language & Text)
    static var langHeaderOptions: String { isRu ? "Дополнительные опции" : "Options" }
    static var langTranslateEn: String { isRu ? "Переводить речь на английский" : "Translate speech to English" }
    static var langTranslateEnSub: String { isRu ? "Whisper автоматически переведёт сказанное на английский текст" : "Whisper will translate spoken language into English text" }
    static var langSuppressTags: String { isRu ? "Подавлять пометки о шуме и музыке" : "Suppress non-speech sound tags" }
    static var langSuppressTagsSub: String { isRu ? "Игнорировать теги вроде [МУЗЫКА], [АПЛОДИСМЕНТЫ]" : "Ignore tags like [MUSIC], [APPLAUSE] and background sounds" }
    static var langHeaderVocab: String { isRu ? "Пользовательский словарь" : "Custom Vocabulary" }
    static var langVocabSub: String { isRu ? "Подсказки для Whisper: профессиональные термины, аббревиатуры и имена" : "Prompts for Whisper: technical terms, acronyms, and names" }

    // MARK: - Микрофон (Microphone)
    static var micHeaderTest: String { isRu ? "Тестирование записи" : "Microphone Test" }
    static var micTestRow: String { isRu ? "Проверить микрофон" : "Test microphone" }
    static var micTestSub: String { isRu ? "Тестовая запись без вставки в сторонние приложения" : "Test audio capture without pasting into external apps" }
    static var micRecordBtn: String { isRu ? "Записать" : "Record" }
    static var micStopBtn: String { isRu ? "Остановить" : "Stop" }
    static var micRecognizedText: String { isRu ? "Распознанный текст" : "Recognized text" }
    static var micError: String { isRu ? "Ошибка" : "Error" }
    static var micRefreshDevices: String { isRu ? "Обновить список устройств" : "Refresh devices list" }
    static var micRefreshDevicesSub: String { isRu ? "Если вы подключили гарнитуру или внешний микрофон" : "If you connected a new headset or external microphone" }
    static var micRefreshBtn: String { isRu ? "Обновить" : "Refresh" }

    // MARK: - История (History)
    static var historyEmptyTitle: String { isRu ? "История записей пуста" : "History is empty" }
    static var historyEmptySubtitle: String { isRu ? "Здесь будут сохраняться продиктованные вами фразы." : "Your transcribed phrases will appear here." }
    static var historySearchPlaceholder: String { isRu ? "Поиск по истории записей…" : "Search history…" }
    static var historyNoSearchResults: String { isRu ? "По запросу ничего не найдено" : "No entries found for query" }
    static var historyClearBtn: String { isRu ? "Очистить…" : "Clear…" }
    static var historyClearPopoverTitle: String { isRu ? "Очистка истории" : "Clear History" }
    static var historyClearPopoverSubtitle: String { isRu ? "Выберите период для удаления записей:" : "Select time range to delete:" }
    static var historyClearLastHour: String { isRu ? "За последний час" : "Last hour" }
    static var historyClearLastHourSub: String { isRu ? "Удалит записи за последние 60 минут" : "Deletes entries recorded in the last 60 minutes" }
    static var historyClearToday: String { isRu ? "За сегодня" : "Today" }
    static var historyClearTodaySub: String { isRu ? "Очистит историю за текущий день" : "Clears records from today" }
    static var historyClearOlder7Days: String { isRu ? "Старше 7 дней" : "Older than 7 days" }
    static var historyClearOlder7DaysSub: String { isRu ? "Оставит только свежие записи за неделю" : "Keeps only the past 7 days of records" }
    static var historyClearOlder30Days: String { isRu ? "Старше 30 дней" : "Older than 30 days" }
    static var historyClearOlder30DaysSub: String { isRu ? "Оставит только записи за последний месяц" : "Keeps only the last 30 days of records" }
    static var historyClearAll: String { isRu ? "Всю историю" : "All history" }
    static var historyClearAllSub: String { isRu ? "Полное удаление всех записей" : "Permanently deletes all history" }
    static var historyDeleteTooltip: String { isRu ? "Удалить запись" : "Delete record" }
    static var historyCopyBtn: String { isRu ? "Копировать" : "Copy" }
    static var historyAutoClearHeader: String { isRu ? "АВТООЧИСТКА И ЛИМИТЫ ХРАНЕНИЯ" : "AUTO-CLEANUP & STORAGE LIMITS" }
    static var historyLimitTitle: String { isRu ? "Лимит количества строк" : "History lines limit" }
    static var historyLimitSub: String { isRu ? "При превышении лимита старые записи удаляются автоматически" : "Automatically trims oldest records when line limit is reached" }
    static var historyScheduleTitle: String { isRu ? "Очистка по таймеру" : "Scheduled auto-cleanup" }
    static var historyScheduleSub: String { isRu ? "Автоматическое удаление устаревших записей по расписанию" : "Automatically purge older entries based on timer schedule" }

    // MARK: - О программе (About)
    static var aboutEngineRow: String { isRu ? "Движок распознавания" : "Recognition Engine" }
    static var aboutEngineSub: String { isRu ? "whisper.cpp с аппаратным ускорением Apple Silicon (Metal)" : "whisper.cpp with Apple Silicon Metal GPU acceleration" }
    static var aboutCliRow: String { isRu ? "Утилита whisper-cli" : "whisper-cli Utility" }
    static var aboutCpuCores: String { isRu ? "Ядер процессора" : "CPU Cores" }
    static var aboutVersion: String { isRu ? "Версия" : "Version" }
    static var aboutLogsRow: String { isRu ? "Журнал работы" : "Application Logs" }
    static var aboutLogsSub: String { isRu ? "Логирование нажатий клавиш, прав доступа и ошибок" : "Debug logs for hotkeys, permissions, and engine events" }
    static var aboutShowFileBtn: String { isRu ? "Показать файл" : "Show File" }
    static var aboutHeaderPrivacy: String { isRu ? "Приватность и безопасность" : "Privacy & Security" }
    static var aboutPrivacyTitle: String { isRu ? "100% локальная обработка на устройстве" : "100% On-Device & Private" }
    static var aboutPrivacyBody: String {
        isRu
        ? "Весь процесс записи и распознавания речи выполняется исключительно на вашем Mac. Аудиофайлы никогда не отправляются на сторонние серверы и удаляются из памяти сразу после завершения диктовки."
        : "All audio recording and transcription happens 100% locally on your Mac. No voice recordings or text ever leave your computer or get sent to remote servers."
    }
}
