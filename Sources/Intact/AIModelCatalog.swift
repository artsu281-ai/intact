import Foundation

/// Одна «версия ИИ», которую можно выбрать в разделе приложения.
///
/// Раньше выбор был размазан по трём настройкам (`aiProviderKind`,
/// `aiCloudModel`, `aiLocalModelPath`) и жил только в разделе настроек.
/// Здесь они сведены в один тип, который можно показать списком и применить
/// одним действием.
enum AIModelChoice: Hashable, Identifiable {
    case disabled
    /// Идентификатор модели Anthropic.
    case cloud(String)
    /// Имя файла установленной GGUF-модели.
    case local(String)

    var id: String {
        switch self {
        case .disabled:          return "disabled"
        case .cloud(let model):  return "cloud:\(model)"
        case .local(let file):   return "local:\(file)"
        }
    }

    /// Разбор `id` обратно в выбор — так переопределение роли хранится
    /// в UserDefaults одной строкой, без отдельного Codable-слоя.
    init?(id: String) {
        if id == "disabled" { self = .disabled; return }
        if id.hasPrefix("cloud:") { self = .cloud(String(id.dropFirst("cloud:".count))); return }
        if id.hasPrefix("local:") { self = .local(String(id.dropFirst("local:".count))); return }
        return nil
    }
}

/// Как модель принимает параметры рассуждения. Разные поколения отвечают
/// на одни и те же поля по-разному, и ошибка здесь — не деградация качества,
/// а HTTP 400 на каждый запрос.
enum CloudThinkingSupport {
    /// Рассуждение всегда включено, поле `thinking` слать нельзя (Claude Fable 5).
    case always
    /// Принимает `{"type": "adaptive"}` и `output_config.effort` (5-е поколение).
    case adaptive
    /// Прошлое поколение: и `adaptive`, и `effort` отвечают ошибкой.
    case legacy
}

/// Облачная модель Anthropic в каталоге выбора.
struct CloudModel: Identifiable, Hashable {
    let id: String
    let title: String
    let note: String
    /// Контекстное окно в токенах — сколько заметок и диктовок влезет за раз.
    let contextTokens: Int
    /// Цена за миллион токенов, доллары: вход / выход.
    let priceIn: Double
    let priceOut: Double
    let thinking: CloudThinkingSupport
    /// Тип серверного инструмента веб-поиска, который понимает эта модель.
    let webSearchTool: String
    /// Модель умеет серверный fallback при отказе классификатора
    /// (`stop_reason: "refusal"` приходит с кодом 200 и без текста).
    let supportsRefusalFallback: Bool

    static func == (a: CloudModel, b: CloudModel) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var supportsEffort: Bool {
        switch thinking {
        case .always, .adaptive: return true
        case .legacy:            return false
        }
    }

    /// Отвечает ли модель через рассуждение — от этого зависит, сколько её ждать.
    var isThinkingModel: Bool {
        switch thinking {
        case .always, .adaptive: return true
        case .legacy:            return false
        }
    }

    /// «$5 / $25 за 1M токенов» — цена вслух, чтобы выбор самой крупной модели
    /// был осознанным, а не сюрпризом в счёте.
    var priceText: String {
        String(format: T("$%.0f / $%.0f за 1M токенов", "$%.0f / $%.0f per 1M tokens"), priceIn, priceOut)
    }

    var contextText: String {
        contextTokens >= 1_000_000
            ? T("1M контекста", "1M context")
            : T("\(contextTokens / 1000)K контекста", "\(contextTokens / 1000)K context")
    }
}

enum AIModelCatalog {

    /// Актуальная линейка Anthropic, от самой способной к самой быстрой.
    ///
    /// Идентификаторы указываются ровно так, без суффикса с датой: дописанная
    /// дата — не «более точная» версия, а несуществующая модель.
    static let cloud: [CloudModel] = [
        .init(id: "claude-fable-5",
              title: "Claude Fable 5",
              note: T("Предел возможного: самая сильная модель Anthropic. Для разбора недельных заметок и длинных рассуждений — и самая дорогая.", "The upper limit: Anthropic's strongest model. For working through a week of notes and long reasoning — and the most expensive."),
              contextTokens: 1_000_000, priceIn: 10, priceOut: 50,
              thinking: .always, webSearchTool: "web_search_20260209",
              supportsRefusalFallback: true),
        .init(id: "claude-opus-5",
              title: "Claude Opus 5",
              note: T("Глубокий анализ диктовок и длинные брифы. Рассуждает по умолчанию, вдвое дешевле Fable — разумный максимум на каждый день.", "Deep analysis of dictations and long briefs. Reasons by default, half the price of Fable — a sensible everyday maximum."),
              contextTokens: 1_000_000, priceIn: 5, priceOut: 25,
              thinking: .adaptive, webSearchTool: "web_search_20260209",
              supportsRefusalFallback: true),
        .init(id: "claude-sonnet-5",
              title: "Claude Sonnet 5",
              note: T("Баланс качества и скорости — хороший выбор по умолчанию для чата.", "A balance of quality and speed — a good default for chat."),
              contextTokens: 1_000_000, priceIn: 3, priceOut: 15,
              thinking: .adaptive, webSearchTool: "web_search_20260209",
              supportsRefusalFallback: false),
        .init(id: "claude-haiku-4-5",
              title: "Claude Haiku 4.5",
              note: T("Самая быстрая и дешёвая. Отвечает без рассуждения — то, что нужно причёсыванию диктовки.", "The fastest and cheapest. Answers without reasoning — exactly what dictation cleanup needs."),
              contextTokens: 200_000, priceIn: 1, priceOut: 5,
              thinking: .legacy, webSearchTool: "web_search_20250305",
              supportsRefusalFallback: false)
    ]

    static func cloudModel(id: String) -> CloudModel? {
        cloud.first { $0.id == id }
    }

    // MARK: - Текущий выбор

    /// Выбор «по умолчанию» — то, чем пользуются все разделы, у которых нет
    /// собственного переопределения.
    static var current: AIModelChoice {
        let settings = AppSettings.shared
        switch settings.aiProviderKind {
        case .none:
            return .disabled
        case .cloud:
            return .cloud(settings.aiCloudModel)
        case .local:
            let file = URL(fileURLWithPath: settings.aiLocalModelPath).lastPathComponent
            return file.isEmpty ? .disabled : .local(file)
        }
    }

    /// Что реально выполнит задачу этой роли.
    ///
    /// Переопределение, указывающее на удалённую модель, молча игнорируется:
    /// иначе удаление файла в хабе моделей ломало бы раздел, который на него
    /// когда-то сослались, и починить это было бы негде.
    static func resolved(for role: AIRole) -> AIModelChoice {
        guard let raw = AppSettings.shared.aiRoleOverrides[role.rawValue],
              let choice = AIModelChoice(id: raw),
              isAvailable(choice) else { return current }
        return choice
    }

    /// Есть ли у роли собственный выбор, отличный от «по умолчанию».
    static func hasOverride(_ role: AIRole) -> Bool {
        guard let raw = AppSettings.shared.aiRoleOverrides[role.rawValue],
              let choice = AIModelChoice(id: raw) else { return false }
        return isAvailable(choice)
    }

    /// Существует ли выбранное физически: файл на диске для локальной модели,
    /// известный идентификатор для облачной.
    static func isAvailable(_ choice: AIModelChoice) -> Bool {
        switch choice {
        case .disabled:
            return true
        case .cloud(let id):
            return cloudModel(id: id) != nil
        case .local(let filename):
            guard let match = LLMModel.matching(path: filename) else { return false }
            return match.model.isInstalled(match.quant)
        }
    }

    /// Путь к файлу локальной модели для выбора `.local`.
    static func localPath(for choice: AIModelChoice) -> String? {
        guard case .local(let filename) = choice,
              let match = LLMModel.matching(path: filename) else { return nil }
        return match.model.localURL(for: match.quant).path
    }

    // MARK: - Применение

    /// Применяет выбор как общий по умолчанию. Перезапуск локального сервера
    /// и всё остальное происходит через уже существующие наблюдатели `AppSettings`.
    @MainActor
    static func apply(_ choice: AIModelChoice) {
        let settings = AppSettings.shared
        switch choice {
        case .disabled:
            settings.aiProviderKind = .none
        case .cloud(let model):
            settings.aiCloudModel = model
            settings.aiProviderKind = .cloud
        case .local(let filename):
            guard let match = LLMModel.matching(path: filename) else { return }
            settings.aiLocalModelPath = match.model.localURL(for: match.quant).path
            settings.aiProviderKind = .local
        }
    }

    /// Применяет выбор к одной роли. `nil` возвращает роль к общему умолчанию.
    @MainActor
    static func apply(_ choice: AIModelChoice?, to role: AIRole) {
        var overrides = AppSettings.shared.aiRoleOverrides
        if let choice {
            overrides[role.rawValue] = choice.id
        } else {
            overrides.removeValue(forKey: role.rawValue)
        }
        AppSettings.shared.aiRoleOverrides = overrides
    }

    // MARK: - Подписи

    /// Короткое имя для шапки раздела.
    static func title(for choice: AIModelChoice) -> String {
        switch choice {
        case .disabled:
            return T("ИИ выключен", "AI is off")
        case .cloud(let id):
            return cloudModel(id: id)?.title ?? id
        case .local(let filename):
            guard let match = LLMModel.matching(path: filename) else {
                return URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            }
            return LLMModel.displayName(model: match.model, quant: match.quant)
        }
    }

    /// Где именно выполняется модель — это важнее её названия: локальная
    /// не отправляет ничего наружу, облачная отправляет.
    static func placement(for choice: AIModelChoice) -> String? {
        switch choice {
        case .disabled: return nil
        case .cloud:    return T("Облако", "Cloud")
        case .local:    return T("Локально", "Local")
        }
    }
}
