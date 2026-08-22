import Foundation

/// Сколько облачных токенов израсходовал каждый раздел приложения.
///
/// Причёсывание срабатывает на каждую диктовку, а диктовок за день бывает
/// полторы сотни. Выбрать в этой роли самую сильную модель — решение,
/// у которого есть цена, и до сих пор её нельзя было увидеть нигде,
/// кроме счёта в конце месяца.
///
/// Локальные модели не учитываются: они ничего не стоят, и смешивать их
/// в одном счётчике с облаком значило бы делать цифру бессмысленной.
struct UsageRecord: Codable, Identifiable, Hashable {
    /// «2026-08-22» — день в локальном календаре пользователя.
    var day: String
    var model: String
    var role: String
    var input: Int
    var output: Int
    var requests: Int

    var id: String { "\(day)|\(model)|\(role)" }

    var tokens: Int { input + output }

    /// Оценка сверху. Настоящий счёт обычно меньше: повторное чтение
    /// закэшированного префикса стоит дешевле обычного входа, а здесь
    /// оно считается по полной цене входа.
    var cost: Double {
        guard let model = AIModelCatalog.cloudModel(id: model) else { return 0 }
        return Double(input) / 1_000_000 * model.priceIn
             + Double(output) / 1_000_000 * model.priceOut
    }
}

final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    private let key = "cloudUsage"
    /// Сколько дней помним. Больше месяца никто не сравнивает, а
    /// UserDefaults читается целиком при запуске.
    private let keepDays = 30

    @Published private(set) var records: [UsageRecord] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UsageRecord].self, from: data) {
            records = decoded
        }
        prune()
    }

    // MARK: - Запись

    /// Вызывается из облачного провайдера после каждого ответа.
    /// Может прийти с любой очереди.
    func record(model: String, role: AIRole?, input: Int, output: Int) {
        guard input > 0 || output > 0 else { return }
        let day = Self.dayKey(Date())
        let roleKey = role?.rawValue ?? "other"

        DispatchQueue.main.async {
            if let index = self.records.firstIndex(where: {
                $0.day == day && $0.model == model && $0.role == roleKey
            }) {
                self.records[index].input += input
                self.records[index].output += output
                self.records[index].requests += 1
            } else {
                self.records.append(UsageRecord(day: day, model: model, role: roleKey,
                                                input: input, output: output, requests: 1))
            }
            self.persist()
        }
    }

    // MARK: - Чтение

    func records(for day: Date) -> [UsageRecord] {
        let key = Self.dayKey(day)
        return records.filter { $0.day == key }.sorted { $0.cost > $1.cost }
    }

    /// Последние `days` дней, включая сегодня.
    func recentRecords(days: Int) -> [UsageRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date()
        let cutoffKey = Self.dayKey(cutoff)
        return records.filter { $0.day >= cutoffKey }
    }

    var todayCost: Double { records(for: Date()).reduce(0) { $0 + $1.cost } }
    var todayTokens: Int { records(for: Date()).reduce(0) { $0 + $1.tokens } }
    var weekCost: Double { recentRecords(days: 7).reduce(0) { $0 + $1.cost } }

    /// Расход по ролям за сегодня — то, ради чего счётчик и заводился:
    /// видно, что именно съедает деньги.
    func todayByRole() -> [(role: AIRole, cost: Double, tokens: Int, requests: Int)] {
        let today = records(for: Date())
        return AIRole.allCases.compactMap { role in
            let mine = today.filter { $0.role == role.rawValue }
            guard !mine.isEmpty else { return nil }
            return (role,
                    mine.reduce(0) { $0 + $1.cost },
                    mine.reduce(0) { $0 + $1.tokens },
                    mine.reduce(0) { $0 + $1.requests })
        }
        .sorted { $0.cost > $1.cost }
    }

    func clear() {
        records.removeAll()
        persist()
    }

    // MARK: - Формат

    /// Ниже цента показываем «<$0,01», а не «$0,00»: ноль читается как
    /// «ничего не потрачено», хотя потрачено.
    static func money(_ value: Double) -> String {
        if value <= 0 { return "$0" }
        if value < 0.01 { return "<$0,01" }
        if value < 10 { return String(format: "$%.2f", value) }
        return String(format: "$%.1f", value)
    }

    static func tokensShort(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }

    // MARK: - Хранение

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) ?? Date()
        let cutoffKey = Self.dayKey(cutoff)
        let kept = records.filter { $0.day >= cutoffKey }
        guard kept.count != records.count else { return }
        records = kept
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
