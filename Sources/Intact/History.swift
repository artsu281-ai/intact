import Foundation

struct HistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let date: Date
    let seconds: Double
    let model: String

    init(text: String, seconds: Double, model: String) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.seconds = seconds
        self.model = model
    }
}

/// Последние распознавания — чтобы вернуть текст, если вставка ушла не туда.
final class History: ObservableObject {
    static let shared = History()
    private let key = "history"
    private let limit = 50

    @Published private(set) var entries: [HistoryEntry] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
