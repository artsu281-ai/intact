import AppKit
import SwiftUI
import Foundation
import Carbon.HIToolbox

enum AppTheme: String, CaseIterable, Identifiable {
    case white = "white"
    case terracotta = "terracotta"
    case dark = "dark"
    case system = "system"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white:      return "Обычная белая"
        case .terracotta: return "Тёплая терракотовая"
        case .dark:       return "Тёмная (Мокка / Оникс)"
        case .system:     return "Как в системе"
        }
    }

    var subtitle: String {
        switch self {
        case .white:      return "Классический светлый стиль macOS"
        case .terracotta: return "Уютная песочно-льняная палитра"
        case .dark:       return "Глубокая ночная тема для комфорта глаз"
        case .system:     return "Автоматически следовать за темой macOS"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:     return nil
        case .white:      return .light
        case .terracotta: return .light
        case .dark:       return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:     return nil
        case .white:      return NSAppearance(named: .aqua)
        case .terracotta: return NSAppearance(named: .aqua)
        case .dark:       return NSAppearance(named: .darkAqua)
        }
    }
}

enum AppIconStyle: String, CaseIterable, Identifiable {
    case auto = "auto"
    case light = "light"
    case black = "black"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:  return L10n.iconStyleAuto
        case .light: return L10n.iconStyleLight
        case .black: return L10n.iconStyleBlack
        }
    }

    var subtitle: String {
        switch self {
        case .auto:  return L10n.iconStyleAutoSub
        case .light: return L10n.iconStyleLightSub
        case .black: return L10n.iconStyleBlackSub
        }
    }

    var resourceFileName: String {
        switch self {
        case .auto:
            return AppSettings.shared.isDarkMode ? "AppIcon-Black" : "AppIcon-Light"
        case .light:
            return "AppIcon-Light"
        case .black:
            return "AppIcon-Black"
        }
    }
}

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        }
    }
}

enum OutputMode: String, CaseIterable, Identifiable {
    case paste, type, clipboard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .paste:     return "Вставить целиком на отпускании клавиши (⌘V)"
        case .type:      return "Напечатать целиком в конце (посимвольно)"
        case .clipboard: return "Только в буфер обмена (без вставки)"
        }
    }
    var shortTitle: String {
        switch self {
        case .paste:     return "Вставка (⌘V)"
        case .type:      return "Посимвольно"
        case .clipboard: return "В буфер"
        }
    }
    var help: String {
        switch self {
        case .paste:
            return "Пока клавиша зажата, в поле ничего не лезет. Отпустил — весь готовый текст чисто появляется разом через ⌘V. Буфер обмена восстанавливается сразу после вставки."
        case .type:
            return "Как вставка, но прямыми быстрыми нажатиями клавиш в конце — для полей, где ⌘V заблокирован."
        case .clipboard:
            return "Никуда не вставляется, текст просто оказывается в буфере обмена."
        }
    }
    /// Режимы, работающие прямыми событиями клавиатуры, без буфера обмена.
    var usesKeyboard: Bool { self == .type }
}

enum ActivationMode: String, CaseIterable, Identifiable {
    case modifierHold, hotKeyHold, hotKeyToggle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .modifierHold: return "Удержание клавиши-модификатора"
        case .hotKeyHold:   return "Удержание сочетания клавиш"
        case .hotKeyToggle: return "Сочетание как переключатель"
        }
    }
    var help: String {
        switch self {
        case .modifierHold:
            return "Зажал ⌥, говоришь, отпустил — текст на месте. Если во время удержания нажать любую другую клавишу или мышь, запись отменяется: значит это было обычное сочетание."
        case .hotKeyHold:
            return "То же самое, но на сочетании с обычной клавишей."
        case .hotKeyToggle:
            return "Нажал — пишет, нажал ещё раз — вставляет. Удобно для длинных диктовок."
        }
    }
}

enum AIProviderKind: String, CaseIterable, Identifiable {
    case none, local, cloud
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:  return L10n.aiProviderNone
        case .local: return L10n.aiProviderLocal
        case .cloud: return L10n.aiProviderCloud
        }
    }
}

struct Language: Identifiable, Hashable {
    let code: String
    let name: String            // Родное название (напр. "English", "Русский", "Deutsch")
    let russianName: String     // Русское название (напр. "Английский", "Русский", "Немецкий")
    let englishName: String     // Английское название (напр. "English", "Russian", "German")
    let aliases: [String]       // Синонимы и сокращения для поиска

    var id: String { code }

    var displayName: String {
        if code == "auto" {
            return "Автоопределение"
        }
        if name.lowercased() == russianName.lowercased() {
            return "\(name) (\(englishName))"
        }
        return "\(name) · \(russianName)"
    }

    func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        if code.lowercased() == q { return true }
        if name.lowercased().contains(q) { return true }
        if russianName.lowercased().contains(q) { return true }
        if englishName.lowercased().contains(q) { return true }
        for a in aliases {
            if a.lowercased().contains(q) { return true }
        }
        return false
    }

    static func find(code: String) -> Language {
        all.first(where: { $0.code == code }) ?? .init(code: code, name: code.uppercased(), russianName: code, englishName: code, aliases: [code])
    }

    static let popular: [Language] = [
        .init(code: "auto", name: "Автоопределение", russianName: "Авто", englishName: "Auto Detect", aliases: ["auto", "авто", "автоопределение", "detect", "automatic"]),
        .init(code: "ru",   name: "Русский",        russianName: "Русский", englishName: "Russian",     aliases: ["ru", "rus", "russian", "рус", "русский", "рос", "раша"]),
        .init(code: "en",   name: "English",        russianName: "Английский", englishName: "English",   aliases: ["en", "eng", "english", "англ", "английский", "инглиш"])
    ]

    static let all: [Language] = [
        .init(code: "auto", name: "Автоопределение", russianName: "Авто", englishName: "Auto Detect", aliases: ["auto", "авто", "автоопределение", "detect", "automatic"]),
        .init(code: "ru",   name: "Русский",        russianName: "Русский", englishName: "Russian",     aliases: ["ru", "rus", "russian", "рус", "русский", "рос", "россия"]),
        .init(code: "en",   name: "English",        russianName: "Английский", englishName: "English",   aliases: ["en", "eng", "english", "англ", "английский", "инглиш"]),
        .init(code: "az",   name: "Azərbaycan",     russianName: "Азербайджанский", englishName: "Azerbaijani", aliases: ["az", "aze", "azerbaijani", "азербайджанский", "азер"]),
        .init(code: "sq",   name: "Shqip",          russianName: "Албанский", englishName: "Albanian", aliases: ["sq", "alb", "albanian", "албанский"]),
        .init(code: "ar",   name: "العربية",        russianName: "Арабский", englishName: "Arabic",     aliases: ["ar", "ara", "arabic", "арабский", "араб"]),
        .init(code: "hy",   name: "Հայերեն",        russianName: "Армянский", englishName: "Armenian",   aliases: ["hy", "arm", "hye", "armenian", "армянский", "арм"]),
        .init(code: "be",   name: "Беларуская",     russianName: "Белорусский", englishName: "Belarusian", aliases: ["be", "bel", "belarusian", "белорусский", "бел", "беларусь"]),
        .init(code: "bg",   name: "Български",      russianName: "Болгарский", englishName: "Bulgarian",  aliases: ["bg", "bul", "bulgarian", "болгарский", "болг"]),
        .init(code: "bs",   name: "Bosanski",       russianName: "Боснийский", englishName: "Bosnian",    aliases: ["bs", "bos", "bosnian", "боснийский"]),
        .init(code: "hu",   name: "Magyar",         russianName: "Венгерский", englishName: "Hungarian",  aliases: ["hu", "hun", "hungarian", "magyar", "венгерский", "венгр"]),
        .init(code: "vi",   name: "Tiếng Việt",     russianName: "Вьетнамский", englishName: "Vietnamese", aliases: ["vi", "vie", "vietnamese", "вьетнамский", "вьетнам"]),
        .init(code: "nl",   name: "Nederlands",     russianName: "Нидерландский", englishName: "Dutch",   aliases: ["nl", "nld", "dut", "dutch", "nederlands", "нидерландский", "голландский"]),
        .init(code: "el",   name: "Ελληνικά",       russianName: "Греческий", englishName: "Greek",       aliases: ["el", "ell", "gre", "greek", "ellinika", "греческий", "греч"]),
        .init(code: "ka",   name: "ქართული",        russianName: "Грузинский", englishName: "Georgian",   aliases: ["ka", "kat", "geo", "georgian", "грузинский", "груз"]),
        .init(code: "da",   name: "Dansk",          russianName: "Датский", englishName: "Danish",       aliases: ["da", "dan", "danish", "dansk", "датский"]),
        .init(code: "he",   name: "עברית",          russianName: "Иврит", englishName: "Hebrew",         aliases: ["he", "heb", "hebrew", "иврит"]),
        .init(code: "id",   name: "Bahasa Indonesia", russianName: "Индонезийский", englishName: "Indonesian", aliases: ["id", "ind", "indonesian", "индонезийский"]),
        .init(code: "es",   name: "Español",        russianName: "Испанский", englishName: "Spanish",    aliases: ["es", "spa", "spanish", "espanol", "español", "испанский", "исп"]),
        .init(code: "it",   name: "Italiano",       russianName: "Итальянский", englishName: "Italian",  aliases: ["it", "ita", "italian", "italiano", "итальянский", "итал"]),
        .init(code: "kk",   name: "Қазақша",        russianName: "Казахский", englishName: "Kazakh",     aliases: ["kk", "kaz", "kazakh", "казахский", "каз", "қазақ", "казахстан"]),
        .init(code: "ca",   name: "Català",         russianName: "Каталанский", englishName: "Catalan",  aliases: ["ca", "cat", "catalan", "каталанский"]),
        .init(code: "zh",   name: "中文",           russianName: "Китайский", englishName: "Chinese",    aliases: ["zh", "chi", "zho", "chinese", "китайский", "кит", "китай", "mandarin"]),
        .init(code: "ko",   name: "한국어",          russianName: "Корейский", englishName: "Korean",     aliases: ["ko", "kor", "korean", "корейский", "кор", "корея"]),
        .init(code: "lv",   name: "Latviešu",       russianName: "Латышский", englishName: "Latvian",    aliases: ["lv", "lav", "latvian", "latviesu", "латвийский", "латышский", "латвия"]),
        .init(code: "lt",   name: "Lietuvių",       russianName: "Литовский", englishName: "Lithuanian", aliases: ["lt", "lit", "lithuanian", "lietuviu", "литовский", "литва"]),
        .init(code: "mk",   name: "Македонски",     russianName: "Македонский", englishName: "Macedonian", aliases: ["mk", "mkd", "macedonian", "македонский"]),
        .init(code: "ms",   name: "Bahasa Melayu",  russianName: "Малайский", englishName: "Malay",      aliases: ["ms", "msa", "may", "malay", "малайский"]),
        .init(code: "de",   name: "Deutsch",        russianName: "Немецкий", englishName: "German",      aliases: ["de", "deu", "ger", "german", "deutsch", "немецкий", "нем", "германия"]),
        .init(code: "no",   name: "Norsk",          russianName: "Норвежский", englishName: "Norwegian",  aliases: ["no", "nor", "norwegian", "norsk", "норвежский", "норв"]),
        .init(code: "fa",   name: "فارسی",          russianName: "Персидский (Фарси)", englishName: "Persian", aliases: ["fa", "per", "fas", "persian", "farsi", "персидский", "фарси"]),
        .init(code: "pl",   name: "Polski",         russianName: "Польский", englishName: "Polish",      aliases: ["pl", "pol", "polish", "polski", "польский", "пол", "польша"]),
        .init(code: "pt",   name: "Português",      russianName: "Португальский", englishName: "Portuguese", aliases: ["pt", "por", "portuguese", "portugues", "португальский", "порт"]),
        .init(code: "ro",   name: "Română",         russianName: "Румынский", englishName: "Romanian",   aliases: ["ro", "ron", "rum", "romanian", "romana", "румынский", "рум"]),
        .init(code: "sr",   name: "Српски",         russianName: "Сербский", englishName: "Serbian",     aliases: ["sr", "srp", "serbian", "сербский", "серб"]),
        .init(code: "sk",   name: "Slovenčina",     russianName: "Словацкий", englishName: "Slovak",     aliases: ["sk", "slk", "slo", "slovak", "slovencina", "словацкий", "слов"]),
        .init(code: "sl",   name: "Slovenščina",    russianName: "Словенский", englishName: "Slovenian",  aliases: ["sl", "slv", "slovenian", "slovenscina", "словенский"]),
        .init(code: "th",   name: "ไทย",            russianName: "Тайский", englishName: "Thai",         aliases: ["th", "tha", "thai", "тайский", "таиланд"]),
        .init(code: "tr",   name: "Türkçe",         russianName: "Турецкий", englishName: "Turkish",     aliases: ["tr", "tur", "turkish", "turkce", "турецкий", "тур", "турция"]),
        .init(code: "uz",   name: "Oʻzbekcha",      russianName: "Узбекский", englishName: "Uzbek",       aliases: ["uz", "uzb", "uzbek", "узбекский", "узб", "узбекистан"]),
        .init(code: "uk",   name: "Українська",     russianName: "Украинский", englishName: "Ukrainian",  aliases: ["uk", "ukr", "ukrainian", "украинский", "укр", "україна"]),
        .init(code: "fi",   name: "Suomi",          russianName: "Финский", englishName: "Finnish",       aliases: ["fi", "fin", "finnish", "suomi", "финский", "финляндия"]),
        .init(code: "fr",   name: "Français",       russianName: "Французский", englishName: "French",   aliases: ["fr", "fra", "fre", "french", "francais", "французский", "франц", "франция"]),
        .init(code: "hi",   name: "हिन्दी",          russianName: "Хинди", englishName: "Hindi",           aliases: ["hi", "hin", "hindi", "хинди", "индия"]),
        .init(code: "hr",   name: "Hrvatski",       russianName: "Хорватский", englishName: "Croatian",   aliases: ["hr", "hrv", "croatian", "hrvatski", "хорватский", "хорв"]),
        .init(code: "cs",   name: "Čeština",        russianName: "Чешский", englishName: "Czech",         aliases: ["cs", "ces", "cze", "czech", "cestina", "чешский", "чехия"]),
        .init(code: "sv",   name: "Svenska",        russianName: "Шведский", englishName: "Swedish",     aliases: ["sv", "swe", "swedish", "svenska", "шведский", "швеция"]),
        .init(code: "et",   name: "Eesti",          russianName: "Эстонский", englishName: "Estonian",   aliases: ["et", "est", "estonian", "eesti", "эстонский", "эстония"]),
        .init(code: "ja",   name: "日本語",          russianName: "Японский", englishName: "Japanese",   aliases: ["ja", "jpn", "japanese", "японский", "яп", "япония"])
    ]
}

enum HistoryAutoClearSchedule: String, CaseIterable, Identifiable {
    case disabled = "disabled"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: return L10n.isRu ? "Вручную (отключено)" : "Manual (Disabled)"
        case .daily:    return L10n.isRu ? "Ежедневно" : "Daily"
        case .weekly:   return L10n.isRu ? "Еженедельно" : "Weekly"
        case .monthly:  return L10n.isRu ? "Ежемесячно" : "Monthly"
        }
    }
}

enum HistoryLimitOption: Int, CaseIterable, Identifiable {
    case unlimited = 0
    case limit50 = 50
    case limit100 = 100
    case limit250 = 250
    case limit500 = 500
    case limit1000 = 1000

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .unlimited: return L10n.isRu ? "Без лимита" : "Unlimited"
        case .limit50:   return L10n.isRu ? "50 записей" : "50 entries"
        case .limit100:  return L10n.isRu ? "100 записей" : "100 entries"
        case .limit250:  return L10n.isRu ? "250 записей" : "250 entries"
        case .limit500:  return L10n.isRu ? "500 записей (стандарт)" : "500 entries (Default)"
        case .limit1000: return L10n.isRu ? "1000 записей" : "1000 entries"
        }
    }
}


/// Единый источник правды для настроек. Пишется в UserDefaults, читается везде.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    private func str(_ k: String, _ fallback: String) -> String { d.string(forKey: k) ?? fallback }
    private func int(_ k: String, _ fallback: Int) -> Int { d.object(forKey: k) == nil ? fallback : d.integer(forKey: k) }
    private func bool(_ k: String, _ fallback: Bool) -> Bool { d.object(forKey: k) == nil ? fallback : d.bool(forKey: k) }

    @Published var modelPath: String { didSet { d.set(modelPath, forKey: "modelPath"); onEngineChange?() } }
    @Published var language: String { didSet { d.set(language, forKey: "language"); onEngineChange?() } }
    @Published var threads: Int { didSet { d.set(threads, forKey: "threads"); onEngineChange?() } }
    @Published var translateToEnglish: Bool { didSet { d.set(translateToEnglish, forKey: "translateToEnglish"); onEngineChange?() } }
    @Published var initialPrompt: String { didSet { d.set(initialPrompt, forKey: "initialPrompt") } }
    @Published var suppressNonSpeech: Bool { didSet { d.set(suppressNonSpeech, forKey: "suppressNonSpeech"); onEngineChange?() } }

    @Published var outputMode: OutputMode { didSet { d.set(outputMode.rawValue, forKey: "outputMode") } }
    @Published var trimTrailingPeriod: Bool { didSet { d.set(trimTrailingPeriod, forKey: "trimTrailingPeriod") } }
    @Published var appendSpace: Bool { didSet { d.set(appendSpace, forKey: "appendSpace") } }

    @Published var hotKeyCode: Int { didSet { d.set(hotKeyCode, forKey: "hotKeyCode"); onHotKeyChange?() } }
    @Published var hotKeyModifiers: Int { didSet { d.set(hotKeyModifiers, forKey: "hotKeyModifiers"); onHotKeyChange?() } }
    @Published var activationMode: ActivationMode { didSet { d.set(activationMode.rawValue, forKey: "activationMode"); onHotKeyChange?() } }
    @Published var triggerKey: TriggerKey { didSet { d.set(triggerKey.rawValue, forKey: "triggerKey"); onHotKeyChange?() } }
    @Published var minHoldMs: Int { didSet { d.set(minHoldMs, forKey: "minHoldMs") } }

    // Потоковое распознавание: черновики считаются прямо во время речи,
    // чтобы на отпускании клавиши вставлять уже готовый текст.
    @Published var streaming: Bool { didSet { d.set(streaming, forKey: "streaming"); onEngineChange?() } }
    @Published var draftIntervalMs: Int { didSet { d.set(draftIntervalMs, forKey: "draftIntervalMs") } }
    @Published var draftAudioContext: Int { didSet { d.set(draftAudioContext, forKey: "draftAudioContext"); onEngineChange?() } }
    @Published var showLiveText: Bool { didSet { d.set(showLiveText, forKey: "showLiveText") } }

    @Published var inputDeviceUID: String { didSet { d.set(inputDeviceUID, forKey: "inputDeviceUID") } }
    @Published var showIndicator: Bool { didSet { d.set(showIndicator, forKey: "showIndicator") } }
    @Published var playSounds: Bool { didSet { d.set(playSounds, forKey: "playSounds") } }
    @Published var muteAudioWhileDictating: Bool { didSet { d.set(muteAudioWhileDictating, forKey: "muteAudioWhileDictating") } }
    @Published var pauseMediaWhileDictating: Bool { didSet { d.set(pauseMediaWhileDictating, forKey: "pauseMediaWhileDictating") } }
    @Published var appTheme: AppTheme { didSet { d.set(appTheme.rawValue, forKey: "appTheme"); applyTheme() } }
    @Published var appIconStyle: AppIconStyle { didSet { d.set(appIconStyle.rawValue, forKey: "appIconStyle"); applyTheme() } }
    @Published var interfaceLanguage: InterfaceLanguage { didSet { d.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage"); objectWillChange.send() } }
    @Published var copyDismissTimeoutSeconds: Int { didSet { d.set(copyDismissTimeoutSeconds, forKey: "copyDismissTimeoutSeconds") } }
    @Published var enableVoiceNotes: Bool { didSet { d.set(enableVoiceNotes, forKey: "enableVoiceNotes") } }
    @Published var voiceNotesFolder: String { didSet { d.set(voiceNotesFolder, forKey: "voiceNotesFolder") } }
    @Published var enableVoiceReminders: Bool { didSet { d.set(enableVoiceReminders, forKey: "enableVoiceReminders") } }
    @Published var voiceRemindersList: String { didSet { d.set(voiceRemindersList, forKey: "voiceRemindersList") } }
    @Published var aiProviderKind: AIProviderKind { didSet { d.set(aiProviderKind.rawValue, forKey: "aiProviderKind"); onAIProviderChange?() } }
    @Published var aiCloudModel: String { didSet { d.set(aiCloudModel, forKey: "aiCloudModel") } }
    @Published var aiLocalModelPath: String { didSet { d.set(aiLocalModelPath, forKey: "aiLocalModelPath"); onAIProviderChange?() } }
    @Published var enableAICleanup: Bool { didSet { d.set(enableAICleanup, forKey: "enableAICleanup") } }
    /// Выбор модели по разделам: роль → идентификатор `AIModelChoice`.
    /// Пусто для роли — значит «как в основных настройках».
    @Published var aiRoleOverrides: [String: String] { didSet { d.set(aiRoleOverrides, forKey: "aiRoleOverrides"); onAIProviderChange?() } }
    /// Пользователь подтвердил, что понимает: с облачной моделью текст
    /// покидает устройство. Спрашивается один раз, перед первым включением.
    @Published var cloudConsentGiven: Bool { didSet { d.set(cloudConsentGiven, forKey: "cloudConsentGiven") } }
    /// Разрешить локальной модели рассуждать перед ответом в чате и брифах.
    /// В причёсывании и быстром ответе рассуждение выключено всегда — там
    /// важнее секунды, чем глубина.
    @Published var localThinkingInChat: Bool { didSet { d.set(localThinkingInChat, forKey: "localThinkingInChat") } }

    /// Автоматический бриф: что собирать, во сколько и когда собирали в последний раз.
    @Published var briefScheduleEnabled: Bool { didSet { d.set(briefScheduleEnabled, forKey: "briefScheduleEnabled") } }
    @Published var briefScheduleHour: Int { didSet { d.set(briefScheduleHour, forKey: "briefScheduleHour") } }
    @Published var briefScheduleMinute: Int { didSet { d.set(briefScheduleMinute, forKey: "briefScheduleMinute") } }
    @Published var briefScheduleKind: BriefKind { didSet { d.set(briefScheduleKind.rawValue, forKey: "briefScheduleKind") } }
    @Published var lastBriefRunTimestamp: Double { didSet { d.set(lastBriefRunTimestamp, forKey: "lastBriefRunTimestamp") } }
    @Published var gemmaAudioModelFilename: String { didSet { d.set(gemmaAudioModelFilename, forKey: "gemmaAudioModelFilename") } }
    /// Доступ в интернет для локальной модели через собственный SearXNG (см. WebTools).
    @Published var enableLocalWebSearch: Bool { didSet { d.set(enableLocalWebSearch, forKey: "enableLocalWebSearch") } }

    /// Второй, независимый от основной диктовки хоткей: вместо вставки текста
    /// как есть отправляет распознанное в ИИ и вставляет ответ.
    @Published var enableAIHotkey: Bool { didSet { d.set(enableAIHotkey, forKey: "enableAIHotkey"); onHotKeyChange?() } }
    @Published var aiTriggerKey: TriggerKey { didSet { d.set(aiTriggerKey.rawValue, forKey: "aiTriggerKey"); onHotKeyChange?() } }
    @Published var maxSeconds: Int { didSet { d.set(maxSeconds, forKey: "maxSeconds") } }
    @Published var keepHistory: Bool { didSet { d.set(keepHistory, forKey: "keepHistory") } }
    @Published var historyLimitOption: HistoryLimitOption { didSet { d.set(historyLimitOption.rawValue, forKey: "historyLimitOption"); History.shared.performAutoCleanup() } }
    @Published var historyAutoClearSchedule: HistoryAutoClearSchedule { didSet { d.set(historyAutoClearSchedule.rawValue, forKey: "historyAutoClearSchedule"); History.shared.performAutoCleanup() } }
    @Published var lastHistoryAutoClearTimestamp: Double { didSet { d.set(lastHistoryAutoClearTimestamp, forKey: "lastHistoryAutoClearTimestamp") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin") } }
    @Published var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: "showDockIcon"); onDockIconChange?() } }

    /// Вызывается, когда меняется способ активации — чтобы перепривязать клавиши.
    var onHotKeyChange: (() -> Void)?
    /// Вызывается, когда меняются параметры движка — чтобы перезапустить whisper-server.
    var onEngineChange: (() -> Void)?
    /// Вызывается при смене AI-провайдера или локальной модели — чтобы прогреть llama-server заранее.
    var onAIProviderChange: (() -> Void)?
    /// Вызывается при переключении значка в Dock.
    var onDockIconChange: (() -> Void)?

    var isDarkMode: Bool {
        switch appTheme {
        case .dark: return true
        case .white, .terracotta: return false
        case .system:
            if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle"), style.lowercased().contains("dark") {
                return true
            }
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    func applyTheme() {
        DispatchQueue.main.async {
            NSApp.appearance = self.appTheme.nsAppearance
            let targetAppearance = self.isDarkMode ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
            for window in NSApp.windows {
                window.appearance = targetAppearance
            }

            // Динамическая смена иконки в Dock (Светлая / Тёмная / Чёрная / Авто)
            let iconName = self.appIconStyle.resourceFileName
            if let iconUrl = Bundle.main.url(forResource: iconName, withExtension: "png"),
               let image = NSImage(contentsOf: iconUrl) {
                NSApp.applicationIconImage = image
            } else if let resourcePath = Bundle.main.resourcePath {
                let directPath = (resourcePath as NSString).appendingPathComponent("\(iconName).png")
                if let image = NSImage(contentsOfFile: directPath) {
                    NSApp.applicationIconImage = image
                }
            } else if let image = NSImage(contentsOfFile: "/Users/artsu/work_tree/voice/Resources/\(iconName).png") {
                NSApp.applicationIconImage = image
            }
        }
    }

    private init() {
        let defaultModel = NSString(string: "~/Models/whisper/ggml-large-v3.bin").expandingTildeInPath
        modelPath = d.string(forKey: "modelPath") ?? defaultModel
        language = d.string(forKey: "language") ?? "auto"
        threads = d.object(forKey: "threads") == nil ? 8 : d.integer(forKey: "threads")
        translateToEnglish = d.bool(forKey: "translateToEnglish")
        initialPrompt = d.string(forKey: "initialPrompt") ?? ""
        suppressNonSpeech = d.object(forKey: "suppressNonSpeech") == nil ? true : d.bool(forKey: "suppressNonSpeech")

        outputMode = OutputMode(rawValue: d.string(forKey: "outputMode") ?? "") ?? .paste
        trimTrailingPeriod = d.bool(forKey: "trimTrailingPeriod")
        appendSpace = d.object(forKey: "appendSpace") == nil ? true : d.bool(forKey: "appendSpace")

        hotKeyCode = d.object(forKey: "hotKeyCode") == nil ? kVK_Space : d.integer(forKey: "hotKeyCode")
        hotKeyModifiers = d.object(forKey: "hotKeyModifiers") == nil ? Int(optionKey) : d.integer(forKey: "hotKeyModifiers")
        activationMode = ActivationMode(rawValue: d.string(forKey: "activationMode") ?? "") ?? .modifierHold
        triggerKey = TriggerKey(rawValue: d.string(forKey: "triggerKey") ?? "") ?? .anyOption
        minHoldMs = d.object(forKey: "minHoldMs") == nil ? 250 : d.integer(forKey: "minHoldMs")

        streaming = d.object(forKey: "streaming") == nil ? true : d.bool(forKey: "streaming")
        draftIntervalMs = d.object(forKey: "draftIntervalMs") == nil ? 400 : d.integer(forKey: "draftIntervalMs")
        draftAudioContext = d.object(forKey: "draftAudioContext") == nil ? 0 : d.integer(forKey: "draftAudioContext")
        showLiveText = d.object(forKey: "showLiveText") == nil ? true : d.bool(forKey: "showLiveText")

        inputDeviceUID = d.string(forKey: "inputDeviceUID") ?? ""
        showIndicator = d.object(forKey: "showIndicator") == nil ? true : d.bool(forKey: "showIndicator")
        playSounds = d.object(forKey: "playSounds") == nil ? true : d.bool(forKey: "playSounds")
        muteAudioWhileDictating = d.object(forKey: "muteAudioWhileDictating") == nil ? true : d.bool(forKey: "muteAudioWhileDictating")
        pauseMediaWhileDictating = d.object(forKey: "pauseMediaWhileDictating") == nil ? true : d.bool(forKey: "pauseMediaWhileDictating")
        appTheme = AppTheme(rawValue: d.string(forKey: "appTheme") ?? "") ?? .white
        appIconStyle = AppIconStyle(rawValue: d.string(forKey: "appIconStyle") ?? "") ?? .auto
        interfaceLanguage = InterfaceLanguage(rawValue: d.string(forKey: "interfaceLanguage") ?? "") ?? .russian
        copyDismissTimeoutSeconds = d.object(forKey: "copyDismissTimeoutSeconds") == nil ? 5 : d.integer(forKey: "copyDismissTimeoutSeconds")
        enableVoiceNotes = d.object(forKey: "enableVoiceNotes") == nil ? true : d.bool(forKey: "enableVoiceNotes")
        voiceNotesFolder = d.string(forKey: "voiceNotesFolder") ?? "Intact"
        enableVoiceReminders = d.object(forKey: "enableVoiceReminders") == nil ? true : d.bool(forKey: "enableVoiceReminders")
        voiceRemindersList = d.string(forKey: "voiceRemindersList") ?? ""
        aiProviderKind = AIProviderKind(rawValue: d.string(forKey: "aiProviderKind") ?? "") ?? .none
        let storedCloudModel = d.string(forKey: "aiCloudModel") ?? ""
        aiCloudModel = AIModelCatalog.cloud.contains { $0.id == storedCloudModel }
            ? storedCloudModel
            : "claude-haiku-4-5"
        aiLocalModelPath = d.string(forKey: "aiLocalModelPath") ?? ""
        enableAICleanup = d.object(forKey: "enableAICleanup") == nil ? false : d.bool(forKey: "enableAICleanup")
        aiRoleOverrides = (d.dictionary(forKey: "aiRoleOverrides") as? [String: String]) ?? [:]
        cloudConsentGiven = d.bool(forKey: "cloudConsentGiven")
        localThinkingInChat = d.object(forKey: "localThinkingInChat") == nil ? true : d.bool(forKey: "localThinkingInChat")
        briefScheduleEnabled = d.bool(forKey: "briefScheduleEnabled")
        briefScheduleHour = d.object(forKey: "briefScheduleHour") == nil ? 21 : d.integer(forKey: "briefScheduleHour")
        briefScheduleMinute = d.object(forKey: "briefScheduleMinute") == nil ? 0 : d.integer(forKey: "briefScheduleMinute")
        briefScheduleKind = BriefKind(rawValue: d.string(forKey: "briefScheduleKind") ?? "") ?? .day
        lastBriefRunTimestamp = d.double(forKey: "lastBriefRunTimestamp")
        gemmaAudioModelFilename = d.string(forKey: "gemmaAudioModelFilename") ?? ""
        enableLocalWebSearch = d.object(forKey: "enableLocalWebSearch") == nil ? false : d.bool(forKey: "enableLocalWebSearch")
        enableAIHotkey = d.object(forKey: "enableAIHotkey") == nil ? false : d.bool(forKey: "enableAIHotkey")
        aiTriggerKey = TriggerKey(rawValue: d.string(forKey: "aiTriggerKey") ?? "") ?? .rightOption
        maxSeconds = d.object(forKey: "maxSeconds") == nil ? 300 : d.integer(forKey: "maxSeconds")
        keepHistory = d.object(forKey: "keepHistory") == nil ? true : d.bool(forKey: "keepHistory")
        historyLimitOption = HistoryLimitOption(rawValue: d.object(forKey: "historyLimitOption") == nil ? 500 : d.integer(forKey: "historyLimitOption")) ?? .limit500
        historyAutoClearSchedule = HistoryAutoClearSchedule(rawValue: d.string(forKey: "historyAutoClearSchedule") ?? "") ?? .disabled
        lastHistoryAutoClearTimestamp = d.double(forKey: "lastHistoryAutoClearTimestamp")
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        showDockIcon = d.object(forKey: "showDockIcon") == nil ? true : d.bool(forKey: "showDockIcon")
        applyTheme()

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.appTheme == .system {
                self.objectWillChange.send()
                self.applyTheme()
            }
        }
    }
}
