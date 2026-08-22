import Foundation

/// Отдельный диалог с ассистентом.
///
/// До этого чат был один на всё приложение и жил только в памяти: закрыл окно —
/// разговор пропал, начал новую тему — старая затёрлась. Ветка решает обе задачи.
struct ChatThread: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
    /// Чем отвечали в этой ветке в последний раз — видно прямо в списке.
    var modelLabel: String?

    /// Источники контекста этой ветки. Раньше выбор был общий на всё
    /// приложение: включил заметки для одного разговора — они уехали
    /// во все остальные.
    var contextSources: Set<String>
    /// Собранный контекст. Собирается один раз на ветку и переиспользуется:
    /// пересборка на каждую реплику означала бы, что 25 диктовок, 12 заметок
    /// и все прикреплённые файлы заново уходят в промпт с каждым сообщением.
    /// Побочная выгода — префикс запроса перестаёт меняться и становится
    /// пригодным для кэширования на стороне облака.
    var contextSnapshot: String?
    var contextBadges: [String]
    var contextGatheredAt: Date?

    init(title: String = ChatThread.untitled,
         contextSources: Set<AIContextSource> = [.dictationToday, .appleNotes]) {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modelLabel = nil
        self.contextSources = Set(contextSources.map(\.rawValue))
        self.contextSnapshot = nil
        self.contextBadges = []
        self.contextGatheredAt = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, updatedAt, modelLabel
        case contextSources, contextSnapshot, contextBadges, contextGatheredAt
    }

    /// Ветки, сохранённые до появления полей контекста, читаются с умолчаниями.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        messages = try c.decode([ChatMessage].self, forKey: .messages)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        modelLabel = try c.decodeIfPresent(String.self, forKey: .modelLabel)
        contextSources = try c.decodeIfPresent(Set<String>.self, forKey: .contextSources)
            ?? Set([AIContextSource.dictationToday, .appleNotes].map(\.rawValue))
        contextSnapshot = try c.decodeIfPresent(String.self, forKey: .contextSnapshot)
        contextBadges = try c.decodeIfPresent([String].self, forKey: .contextBadges) ?? []
        contextGatheredAt = try c.decodeIfPresent(Date.self, forKey: .contextGatheredAt)
    }

    var sources: Set<AIContextSource> {
        get { Set(contextSources.compactMap(AIContextSource.init(rawValue:))) }
        set { contextSources = Set(newValue.map(\.rawValue)) }
    }

    /// Грубая оценка объёма контекста в токенах. Для кириллицы примерно три
    /// символа на токен — точность здесь не нужна, нужен порядок величины,
    /// чтобы было видно, когда контекст разросся до тысяч токенов на реплику.
    var estimatedContextTokens: Int {
        (contextSnapshot?.count ?? 0) / 3
    }

    static let untitled = "Новый чат"

    var isEmpty: Bool { messages.isEmpty }

    /// Первая строка ответа или запроса — то, по чему ветку узнают в списке.
    var preview: String {
        guard let first = messages.first else { return "Пока пусто" }
        return first.content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? first.content
    }

    /// Заголовок из первой реплики пользователя: до первого знака конца
    /// предложения, но не длиннее 42 символов — иначе список превращается в стену.
    static func autoTitle(from prompt: String) -> String {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return untitled }

        let sentence = cleaned.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? cleaned
        let trimmed = sentence.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 42 { return trimmed }

        let cut = trimmed.prefix(42)
        // Не рвём последнее слово посередине
        if let lastSpace = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: lastSpace) > 20 {
            return String(cut[..<lastSpace]) + "…"
        }
        return String(cut) + "…"
    }
}

/// Хранилище веток на диске.
///
/// Не UserDefaults: переписка растёт неограниченно, а UserDefaults читается
/// целиком при каждом запуске. Обычный JSON-файл в Application Support.
enum ChatThreadStore {

    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Intact", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chats.json")
    }

    static func load() -> [ChatThread] {
        guard let data = try? Data(contentsOf: fileURL),
              let threads = try? JSONDecoder().decode([ChatThread].self, from: data) else {
            return []
        }
        return threads
    }

    static func save(_ threads: [ChatThread]) {
        // Пустые безымянные ветки на диск не попадают: иначе каждое открытие
        // приложения оставляло бы после себя мусорную запись.
        let worthKeeping = threads.filter { !$0.isEmpty }
        guard let data = try? JSONEncoder().encode(worthKeeping) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
