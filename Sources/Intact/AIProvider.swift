import Foundation

enum AIError: Error {
    case notConfigured
    case network(Error)
    case badResponse
    case timeout
    case providerUnavailable
    /// Модель отказалась отвечать: приходит с кодом 200, без текста.
    case refused(String?)

    var localizedDescription: String {
        switch self {
        case .notConfigured:      return "AI не настроен"
        case .network(let error): return "Сетевая ошибка: \(error.localizedDescription)"
        case .badResponse:        return "Некорректный ответ от AI"
        case .timeout:            return "AI не ответил вовремя"
        case .providerUnavailable: return "AI-провайдер недоступен"
        case .refused(let explanation):
            return explanation.map { "Модель отклонила запрос: \($0)" } ?? "Модель отклонила запрос"
        }
    }
}

/// Сообщение в истории диалога для AI-провайдеров.
struct AIMessage {
    enum Role: String {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

/// Единый интерфейс поверх локальной и облачной LLM.
/// Всегда вызывается с фонового потока; completion может прийти на любой очереди.
protocol AIProvider {
    var isReady: Bool { get }
    func complete(messages: [AIMessage], maxTokens: Int, completion: @escaping (Result<String, AIError>) -> Void)

    /// Потоковая генерация: `onDelta` вызывается по мере поступления кусочков
    /// текста, `completion` — с полным ответом.
    ///
    /// Для локальной модели это не украшение, а необходимость: на 9B ответ
    /// в две тысячи токенов идёт полторы минуты, и без потока запрос просто
    /// упирается в таймаут, ничего не показав.
    func stream(messages: [AIMessage],
                maxTokens: Int,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void)
}

extension AIProvider {
    /// Провайдеры без потока отдают ответ целиком одним куском.
    func stream(messages: [AIMessage],
                maxTokens: Int,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void) {
        complete(messages: messages, maxTokens: maxTokens) { result in
            if case .success(let text) = result { onDelta(text) }
            completion(result)
        }
    }
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

    /// Потоковый вариант для чата.
    func stream(messages: [AIMessage],
                maxTokens: Int = 800,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void) {
        switch AppSettings.shared.aiProviderKind {
        case .none:
            completion(.failure(.notConfigured))
        case .local:
            LocalAIProvider.shared.stream(messages: messages, maxTokens: maxTokens,
                                          onDelta: onDelta, completion: completion)
        case .cloud:
            CloudAIProvider.shared.stream(messages: messages, maxTokens: maxTokens,
                                          onDelta: onDelta, completion: completion)
        }
    }

    /// Универсальный метод для многооборотных диалогов (чат и т.д.)
    func complete(messages: [AIMessage], maxTokens: Int = 800, completion: @escaping (Result<String, AIError>) -> Void) {
        switch AppSettings.shared.aiProviderKind {
        case .none:
            completion(.failure(.notConfigured))
        case .local:
            LocalAIProvider.shared.complete(messages: messages, maxTokens: maxTokens, completion: completion)
        case .cloud:
            CloudAIProvider.shared.complete(messages: messages, maxTokens: maxTokens, completion: completion)
        }
    }

    /// Convenience-перегрузка для однооборотных задач (причёсывание текста в диктовке),
    /// чтобы существующий вызывающий код не менялся.
    func complete(system: String, user: String, maxTokens: Int = 800, completion: @escaping (Result<String, AIError>) -> Void) {
        let messages = [
            AIMessage(role: .system, content: system),
            AIMessage(role: .user, content: user)
        ]
        complete(messages: messages, maxTokens: maxTokens, completion: completion)
    }
}
