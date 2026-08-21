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

    var flag: String {
        switch self {
        case .russian: return "🇷🇺"
        case .english: return "🇺🇸"
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

struct Language: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }

    static let all: [Language] = [
        .init(code: "auto", name: "Автоопределение"),
        .init(code: "ru",   name: "Русский"),
        .init(code: "en",   name: "English"),
        .init(code: "uk",   name: "Українська"),
        .init(code: "de",   name: "Deutsch"),
        .init(code: "fr",   name: "Français"),
        .init(code: "es",   name: "Español"),
        .init(code: "it",   name: "Italiano"),
        .init(code: "pt",   name: "Português"),
        .init(code: "pl",   name: "Polski"),
        .init(code: "tr",   name: "Türkçe"),
        .init(code: "zh",   name: "中文"),
        .init(code: "ja",   name: "日本語"),
        .init(code: "ko",   name: "한국어")
    ]
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
    @Published var maxSeconds: Int { didSet { d.set(maxSeconds, forKey: "maxSeconds") } }
    @Published var keepHistory: Bool { didSet { d.set(keepHistory, forKey: "keepHistory") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin") } }
    @Published var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: "showDockIcon"); onDockIconChange?() } }

    /// Вызывается, когда меняется способ активации — чтобы перепривязать клавиши.
    var onHotKeyChange: (() -> Void)?
    /// Вызывается, когда меняются параметры движка — чтобы перезапустить whisper-server.
    var onEngineChange: (() -> Void)?
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
        maxSeconds = d.object(forKey: "maxSeconds") == nil ? 300 : d.integer(forKey: "maxSeconds")
        keepHistory = d.object(forKey: "keepHistory") == nil ? true : d.bool(forKey: "keepHistory")
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
