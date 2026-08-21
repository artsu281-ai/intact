import Foundation

enum AIError: Error {
    case notConfigured
    case network(Error)
    case badResponse
    case timeout
    case providerUnavailable

    var localizedDescription: String {
        switch self {
        case .notConfigured:      return "AI не настроен"
        case .network(let error): return "Сетевая ошибка: \(error.localizedDescription)"
        case .badResponse:        return "Некорректный ответ от AI"
        case .timeout:            return "AI не ответил вовремя"
        case .providerUnavailable: return "AI-провайдер недоступен"
        }
    }
}

/// Единый интерфейс поверх локальной и облачной LLM.
/// Всегда вызывается с фонового потока; completion может прийти на любой очереди.
protocol AIProvider {
    var isReady: Bool { get }
    func complete(system: String, user: String, maxTokens: Int, completion: @escaping (Result<String, AIError>) -> Void)
}

/// Выбирает активного AI-провайдера по настройке пользователя и делегирует ему вызовы.
/// DictationController и сервисы Reminders/Notes обращаются только сюда, не зная,
/// работает ли сейчас локальная модель или облачный API.
final class AIRouter {
    static let shared = AIRouter()

    private init() {}

    var isReady: Bool {
        switch AppSettings.shared.aiProviderKind {
        case .none:   return false
        case .local:  return LocalAIProvider.shared.isReady
        case .cloud:  return CloudAIProvider.shared.isReady
        }
    }

    func complete(system: String, user: String, maxTokens: Int = 800, completion: @escaping (Result<String, AIError>) -> Void) {
        switch AppSettings.shared.aiProviderKind {
        case .none:
            completion(.failure(.notConfigured))
        case .local:
            LocalAIProvider.shared.complete(system: system, user: user, maxTokens: maxTokens, completion: completion)
        case .cloud:
            CloudAIProvider.shared.complete(system: system, user: user, maxTokens: maxTokens, completion: completion)
        }
    }
}
