import AppKit
import SwiftUI
import Foundation
import Carbon.HIToolbox

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системная"
        case .light:  return "Светлая (Sand)"
        case .dark:   return "Тёмная (Onyx)"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

enum OutputMode: String, CaseIterable, Identifiable {
    case live, paste, type, clipboard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .live:      return "Печатать вживую, пока говоришь"
        case .paste:     return "Вставить целиком на отпускании клавиши"
        case .type:      return "Напечатать целиком в конце"
        case .clipboard: return "Только в буфер обмена"
        }
    }
    var help: String {
        switch self {
        case .live:
            return "Слова появляются в поле по мере речи. Буфер обмена не используется вообще: текст идёт прямыми событиями клавиатуры, а уточнённые whisper слова переписываются на месте."
        case .paste:
            return "Пока клавиша зажата, в поле ничего не лезет — распознавание идёт в фоне. Отпустил — весь текст появляется разом. Буфер обмена восстанавливается сразу после вставки."
        case .type:
            return "Как вставка, но прямыми нажатиями клавиш — для полей, где ⌘V заблокирован. Буфер не трогается."
        case .clipboard:
            return "Никуда не вставляется, текст просто оказывается в буфере."
        }
    }
    /// Режимы, работающие прямыми событиями клавиатуры, без буфера обмена.
    var usesKeyboard: Bool { self == .live || self == .type }
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
    /// Сколько последних слов черновика не печатать: их whisper переписывает чаще всего.
    @Published var liveHoldWords: Int { didSet { d.set(liveHoldWords, forKey: "liveHoldWords") } }

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

    func applyTheme() {
        NSApp.appearance = appTheme.nsAppearance
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
        liveHoldWords = d.object(forKey: "liveHoldWords") == nil ? 1 : d.integer(forKey: "liveHoldWords")
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
        appTheme = AppTheme(rawValue: d.string(forKey: "appTheme") ?? "") ?? .system
        maxSeconds = d.object(forKey: "maxSeconds") == nil ? 300 : d.integer(forKey: "maxSeconds")
        keepHistory = d.object(forKey: "keepHistory") == nil ? true : d.bool(forKey: "keepHistory")
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        showDockIcon = d.object(forKey: "showDockIcon") == nil ? true : d.bool(forKey: "showDockIcon")

        applyTheme()
    }
}
