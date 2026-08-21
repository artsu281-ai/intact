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
    private var timer: Timer?

    @Published private(set) var entries: [HistoryEntry] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
        performAutoCleanup()
        setupPeriodicTimer()
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        applyLimit()
        persist()
    }

    func delete(id: UUID) {
        entries.removeAll(where: { $0.id == id })
        persist()
    }

    func applyLimit() {
        let limit = AppSettings.shared.historyLimitOption.rawValue
        if limit > 0 && entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
    }

    func performAutoCleanup() {
        applyLimit()

        let schedule = AppSettings.shared.historyAutoClearSchedule
        guard schedule != .disabled else {
            persist()
            return
        }

        let now = Date()
        let lastTimestamp = AppSettings.shared.lastHistoryAutoClearTimestamp
        let lastDate = Date(timeIntervalSince1970: lastTimestamp)
        let calendar = Calendar.current

        var shouldClear = false
        var rangeToClear: HistoryClearRange = .olderThan30Days

        switch schedule {
        case .disabled:
            return
        case .daily:
            if lastTimestamp == 0 || !calendar.isDateInToday(lastDate) {
                shouldClear = true
                rangeToClear = .olderThan7Days
            }
        case .weekly:
            if lastTimestamp == 0 || now.timeIntervalSince(lastDate) >= (7 * 86400) {
                shouldClear = true
                rangeToClear = .olderThan7Days
            }
        case .monthly:
            if lastTimestamp == 0 || now.timeIntervalSince(lastDate) >= (30 * 86400) {
                shouldClear = true
                rangeToClear = .olderThan30Days
            }
        }

        if shouldClear {
            clear(range: rangeToClear)
            AppSettings.shared.lastHistoryAutoClearTimestamp = now.timeIntervalSince1970
        } else {
            persist()
        }
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

    private func setupPeriodicTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.performAutoCleanup()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
