import AppKit
import Foundation

public enum MouseButtonType: String, Codable, CaseIterable, Identifiable {
    case middle = "middle"       // Кнопка 3 (Колёсико)
    case button4 = "button4"     // Кнопка 4 (Боковая назад)
    case button5 = "button5"     // Кнопка 5 (Боковая вперед)

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .middle: return T("Колёсико мыши (Кнопка 3)", "Mouse wheel (Button 3)")
        case .button4: return T("Боковая кнопка мыши (Назад/4)", "Mouse side button (Back/4)")
        case .button5: return T("Боковая кнопка мыши (Вперед/5)", "Mouse side button (Forward/5)")
        }
    }

    public var buttonNumber: Int {
        switch self {
        case .middle: return 2
        case .button4: return 3
        case .button5: return 4
        }
    }
}

public enum TriggerSource: Codable, Hashable {
    case modifierKey(TriggerKey)
    case mouseButton(MouseButtonType)

    private enum CodingKeys: String, CodingKey {
        case type, key, button
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "mouseButton" {
            let btn = try container.decode(MouseButtonType.self, forKey: .button)
            self = .mouseButton(btn)
        } else {
            let key = try container.decode(TriggerKey.self, forKey: .key)
            self = .modifierKey(key)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .modifierKey(let key):
            try container.encode("modifierKey", forKey: .type)
            try container.encode(key, forKey: .key)
        case .mouseButton(let btn):
            try container.encode("mouseButton", forKey: .type)
            try container.encode(btn, forKey: .button)
        }
    }

    public var title: String {
        switch self {
        case .modifierKey(let key): return key.title
        case .mouseButton(let btn): return btn.title
        }
    }
}

public enum STTEngineType: String, Codable, CaseIterable, Identifiable {
    case whisperLocal = "whisper_local"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .whisperLocal: return T("Локальный Whisper (0 токенов, офлайн)", "Local Whisper (0 tokens, offline)")
        }
    }

    /// Миграция старых конфигов: удалённый движок ChatGPT превращается в Whisper.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = STTEngineType(rawValue: raw) ?? .whisperLocal
    }
}

public enum PostProcessingMode: String, Codable, CaseIterable, Identifiable {
    case none = "none"
    case cleanup = "cleanup"
    case promptAnswer = "prompt_answer"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return T("Без обработки (прямая вставка)", "No processing (insert as-is)")
        case .cleanup: return T("Причёсывание текста (удаление паразитов и пунктуация)", "Text cleanup (fillers and punctuation)")
        case .promptAnswer: return T("Вопрос к ИИ (генерация ответа)", "Ask AI (generate an answer)")
        }
    }
}

public struct VoicePipeline: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var trigger: TriggerSource
    public var sttEngine: STTEngineType
    public var postProcessing: PostProcessingMode
    public var customPrompt: String?
    public var uiBadge: String
    public var soundStart: String
    public var soundFinish: String

    public init(
        id: String,
        name: String,
        enabled: Bool = true,
        trigger: TriggerSource,
        sttEngine: STTEngineType,
        postProcessing: PostProcessingMode,
        customPrompt: String? = nil,
        uiBadge: String,
        soundStart: String = "Tink",
        soundFinish: String = "Pop"
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.trigger = trigger
        self.sttEngine = sttEngine
        self.postProcessing = postProcessing
        self.customPrompt = customPrompt
        self.uiBadge = uiBadge
        self.soundStart = soundStart
        self.soundFinish = soundFinish
    }
}

/// Менеджер конфигурации голосовых пайплайнов
public final class PipelineManager: ObservableObject {
    public static let shared = PipelineManager()

    @Published public var pipelines: [VoicePipeline] = []

    /// Состав или триггеры пайплайнов изменились — по этому сигналу перепривязываются
    /// глобальные клавиши, иначе новый триггер начинал работать только после перезапуска.
    public var onChange: (() -> Void)?

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Intact", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pipelines.json")
    }

    private init() {
        load()
    }

    public func load() {
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([VoicePipeline].self, from: data),
           !list.isEmpty {
            // Наследие моста ChatGPT: его пайплайны переезжают на локальный Whisper
            var all = list
            all.removeAll { $0.id == "chatgpt_voice" }
            for i in all.indices where all[i].name.contains("ChatGPT") || all[i].uiBadge.contains("ChatGPT") {
                all[i].name = all[i].name.replacingOccurrences(of: "ChatGPT", with: "Whisper")
                all[i].uiBadge = all[i].uiBadge.replacingOccurrences(of: "ChatGPT", with: "Whisper")
            }
            self.pipelines = all
            save()
            return
        }

        // Значения по умолчанию
        self.pipelines = [
            VoicePipeline(
                id: "raw_whisper",
                name: "Whisper Voice",
                enabled: true,
                trigger: .modifierKey(.leftOption), // Левый Option — чистая диктовка (как есть)
                sttEngine: .whisperLocal,
                postProcessing: .none,
                uiBadge: "Whisper Voice"
            ),
            VoicePipeline(
                id: "ai_cleanup",
                name: "Whisper Cleanup",
                enabled: true,
                trigger: .modifierKey(.rightOption), // Правый Option — обработка / причёсывание
                sttEngine: .whisperLocal,
                postProcessing: .cleanup,
                customPrompt: """
                Инструкция: Ты — модуль форматирования текста. Причеши текст голосовой диктовки:
                1) Удали слова-паразиты («ну», «короче», «типа», «э-э», «в общем» и т.д.);
                2) Убери повторы и заикания;
                3) Расставь правильную пунктуацию и регистр;
                4) Не меняй смысл и не добавляй ответов от себя. Выведи только исправленный текст.
                """,
                uiBadge: "Whisper Cleanup"
            ),
            VoicePipeline(
                id: "ai_task",
                name: "Whisper Answer",
                enabled: true,
                trigger: .modifierKey(.rightCommand), // Правый Command — вопрос / задача к ИИ
                sttEngine: .whisperLocal,
                postProcessing: .promptAnswer,
                customPrompt: "Отвечай сразу по существу, максимально кратко и точно, без вступлений («Конечно», «Вот ответ:») и без заключений. Только чистый текст ответа.",
                uiBadge: "Whisper Answer"
            )
        ]
        save()
    }

    public func save() {
        if let data = try? JSONEncoder().encode(pipelines) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public func updatePipeline(_ pipeline: VoicePipeline) {
        guard let idx = pipelines.firstIndex(where: { $0.id == pipeline.id }) else { return }
        guard pipelines[idx] != pipeline else { return }
        pipelines[idx] = pipeline
        save()
        onChange?()
    }

    /// Другие включённые пайплайны, которые спорят с этим за ту же клавишу или кнопку мыши.
    /// «Любой ⌥» пересекается и с левым, и с правым — поэтому сравниваем наборы кодов, а не сами клавиши.
    public func conflicts(with pipeline: VoicePipeline) -> [VoicePipeline] {
        guard pipeline.enabled else { return [] }
        return pipelines.filter { other in
            guard other.enabled, other.id != pipeline.id else { return false }
            switch (pipeline.trigger, other.trigger) {
            case (.modifierKey(let a), .modifierKey(let b)):
                return !a.keyCodes.isDisjoint(with: b.keyCodes)
            case (.mouseButton(let a), .mouseButton(let b)):
                return a == b
            default:
                return false
            }
        }
    }
}
