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

    init(title: String = ChatThread.untitled) {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modelLabel = nil
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
