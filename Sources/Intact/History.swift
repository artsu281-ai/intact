import Foundation

/// Чем закончилась диктовка: вставкой текста, заметкой, напоминанием,
/// ответом ИИ или сообщением в чат.
///
/// Раньше это писалось эмодзи в начало самого текста («📝 …»). Из-за этого
/// значок уезжал в экспорт, в поиск и в промпт, который читает модель,
/// а отфильтровать историю по типу было нечем. Теперь это поле записи.
enum HistoryKind: String, Codable, CaseIterable, Identifiable {
    case dictation
    case note
    case reminder
    case aiAnswer
    case chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation: return "Диктовка"
        case .note:      return "Заметка"
        case .reminder:  return "Напоминание"
        case .aiAnswer:  return "Ответ ИИ"
        case .chat:      return "В чат"
        }
    }

    var icon: IntactIconKind {
        switch self {
        case .dictation: return .voice
        case .note:      return .briefs
        case .reminder:  return .reminder
        case .aiAnswer:  return .aiStar
        case .chat:      return .chat
        }
    }

    /// Значок для выгрузки в Markdown — там тип нужен именно текстом.
    var marker: String {
        switch self {
        case .dictation: return "🎙"
        case .note:      return "📝"
        case .reminder:  return "⏰"
        case .aiAnswer:  return "✨"
        case .chat:      return "💬"
        }
    }

    /// Старые записи хранили тип префиксом в тексте. Разбираем его один раз
    /// при чтении с диска и дальше живём с нормальным полем.
    static func migrate(from raw: String) -> (kind: HistoryKind, text: String) {
        let prefixes: [(String, HistoryKind)] = [
            ("📝 ", .note), ("⏰ ", .reminder), ("✨ ", .aiAnswer), ("💬 ", .chat)
        ]
        for (prefix, kind) in prefixes where raw.hasPrefix(prefix) {
            return (kind, String(raw.dropFirst(prefix.count)))
        }
        return (.dictation, raw)
    }
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let date: Date
    let seconds: Double
    let model: String
    let kind: HistoryKind

    init(text: String, kind: HistoryKind = .dictation, seconds: Double, model: String) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.seconds = seconds
        self.model = model
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, date, seconds, model, kind
    }

    /// Записи, сделанные до появления поля `kind`, читаются по префиксу текста
    /// и тут же теряют его — миграция происходит на первом же сохранении.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        seconds = try container.decode(Double.self, forKey: .seconds)
        model = try container.decode(String.self, forKey: .model)

        let raw = try container.decode(String.self, forKey: .text)
        if let stored = try container.decodeIfPresent(HistoryKind.self, forKey: .kind) {
            kind = stored
            text = raw
        } else {
            let migrated = HistoryKind.migrate(from: raw)
            kind = migrated.kind
            text = migrated.text
        }
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
        // performAutoCleanup всегда заканчивается записью на диск — этим же
        // проходом на диск ложится и результат миграции типов.
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

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        entries.removeAll(where: { ids.contains($0.id) })
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
