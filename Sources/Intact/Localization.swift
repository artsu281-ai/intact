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
    static var sectionSettings: String { isRu ? "НАСТРОЙКИ" : "SETTINGS" }
    static var sectionInfo: String { isRu ? "ИНФОРМАЦИЯ" : "INFORMATION" }

    static var tabGeneral: String { isRu ? "Основное" : "General" }
    static var tabAppearance: String { isRu ? "Оформление" : "Appearance" }
    static var tabSystem: String { isRu ? "Система" : "System" }
    static var tabModel: String { isRu ? "Модель" : "Model" }
    static var tabLanguage: String { isRu ? "Язык и текст" : "Language & Text" }
    static var tabMicrophone: String { isRu ? "Микрофон" : "Microphone" }
    static var tabHistory: String { isRu ? "История" : "History" }
    static var tabAbout: String { isRu ? "О программе" : "About" }

    // MARK: - Статус
    static var statusReady: String { isRu ? "Готов к диктовке" : "Ready for dictation" }
    static var statusLoading: String { isRu ? "Модель загружается…" : "Loading model…" }

    // MARK: - Оформление (Appearance)
    static var appearanceHeaderTheme: String { isRu ? "Тема интерфейса" : "Interface Theme" }
    static var appearanceThemeDescription: String { isRu ? "Выберите тему приложения и плавающего индикатора записи." : "Choose the application and recording indicator theme." }
    static var appearanceHeaderLanguage: String { isRu ? "Язык программы" : "Interface Language" }
    static var appearanceLanguageSubtitle: String { isRu ? "Язык интерфейса приложения (Русский / English)" : "Application display language (Russian / English)" }
    static var appearanceHeaderDock: String { isRu ? "Иконка в Dock" : "Dock Icon" }
    static var appearanceDockSubtitle: String { isRu ? "В Dock автоматически отображается фирменная светлая или тёмная иконка" : "The Dock icon dynamically updates based on the selected theme" }
    static var appearanceHeaderIndicator: String { isRu ? "Индикатор диктовки" : "Dictation Indicator" }
    static var appearanceShowIndicator: String { isRu ? "Показывать плавающий индикатор во время записи" : "Show floating indicator during recording" }
    static var appearanceIndicatorSubtitle: String { isRu ? "Компактный плавающий статус с живым спектром звука" : "Compact floating pill with live audio spectrum" }
    static var appearanceTimeout: String { isRu ? "Таймаут карточки копирования" : "Copy card dismiss timeout" }
    static var appearanceTimeoutSubtitle: String { isRu ? "Через сколько секунд скрывать окно, если поле ввода не было выбрано" : "Seconds before closing the prompt if no input field is focused" }

    // MARK: - Темы
    static var themeWhite: String { isRu ? "Обычная белая" : "Clean White" }
    static var themeWhiteSub: String { isRu ? "Классический светлый стиль macOS (по умолчанию)" : "Classic macOS light style (default)" }
    static var themeTerracotta: String { isRu ? "Тёплая терракотовая" : "Warm Terracotta" }
    static var themeTerracottaSub: String { isRu ? "Уютный песочно-льняной холст и глина" : "Cozy oatmeal linen and terracotta clay" }
    static var themeDark: String { isRu ? "Тёмная (Оникс / Мокка)" : "Dark (Onyx / Mocha)" }
    static var themeDarkSub: String { isRu ? "Глубокий ночной фон для комфорта глаз" : "Deep nighttime palette for eye comfort" }
    static var themeSystem: String { isRu ? "Как в системе" : "System" }
    static var themeSystemSub: String { isRu ? "Автоматически следовать за темой macOS" : "Automatically follows macOS theme" }

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
    static var historyClearBtn: String { isRu ? "Очистить историю" : "Clear history" }
    static var historyCopyBtn: String { isRu ? "Копировать" : "Copy" }

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
