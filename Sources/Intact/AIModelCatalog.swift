import Foundation

/// Одна «версия ИИ», которую можно выбрать в чате.
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
}

/// Облачная модель Anthropic в каталоге выбора.
struct CloudModel: Identifiable, Hashable {
    let id: String
    let title: String
    let note: String
}

enum AIModelCatalog {

    /// Актуальная линейка Anthropic.
    ///
    /// Идентификаторы указываются ровно так, без суффикса с датой: дописанная
    /// дата — не «более точная» версия, а несуществующая модель.
    static let cloud: [CloudModel] = [
        .init(id: "claude-opus-5",
              title: "Claude Opus 5",
              note: "Самая способная: глубокий анализ диктовок, длинные брифы"),
        .init(id: "claude-sonnet-5",
              title: "Claude Sonnet 5",
              note: "Баланс качества и скорости — хороший выбор по умолчанию"),
        .init(id: "claude-haiku-4-5",
              title: "Claude Haiku 4.5",
              note: "Самая быстрая и дешёвая: короткие сводки и причёсывание текста")
    ]

    static func cloudModel(id: String) -> CloudModel? {
        cloud.first { $0.id == id }
    }

    // MARK: - Текущий выбор

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

    /// Применяет выбор к настройкам. Перезапуск локального сервера и всё
    /// остальное происходит через уже существующие наблюдатели `AppSettings`.
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

    // MARK: - Подписи

    /// Короткое имя для шапки чата.
    static func title(for choice: AIModelChoice) -> String {
        switch choice {
        case .disabled:
            return "ИИ выключен"
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
        case .cloud:    return "Облако"
        case .local:    return "Локально"
        }
    }
}
