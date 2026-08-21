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

enum HistoryClearRange: String, CaseIterable, Identifiable {
    case lastHour
    case today
    case olderThan7Days
    case olderThan30Days
    case all

    var id: String { rawValue }
}

/// Последние распознавания — чтобы вернуть текст, если вставка ушла не туда.
final class History: ObservableObject {
    static let shared = History()
    private let key = "history"
    private let limit = 500

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

    func delete(id: UUID) {
        entries.removeAll(where: { $0.id == id })
        persist()
    }

    func clear(range: HistoryClearRange = .all) {
        let now = Date()
        let calendar = Calendar.current

        switch range {
        case .lastHour:
            let oneHourAgo = now.addingTimeInterval(-3600)
            entries.removeAll(where: { $0.date >= oneHourAgo })

        case .today:
            let startOfToday = calendar.startOfDay(for: now)
            entries.removeAll(where: { $0.date >= startOfToday })

        case .olderThan7Days:
            if let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) {
                entries.removeAll(where: { $0.date < sevenDaysAgo })
            }

        case .olderThan30Days:
            if let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) {
                entries.removeAll(where: { $0.date < thirtyDaysAgo })
            }

        case .all:
            entries.removeAll()
        }

        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
