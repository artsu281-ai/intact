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

/// Вызов инструмента (web-поиск и т.п.), который запросила модель.
struct AIToolCall: Hashable {
    let id: String
    let name: String
    /// JSON-строка с аргументами — так, как её вернула модель, без парсинга здесь.
    let arguments: String
}

/// Сообщение в истории диалога для AI-провайдеров.
struct AIMessage {
    enum Role: String {
        case system
        case user
        case assistant
        /// Результат вызова инструмента — привязан к конкретному tool call по id.
        case tool
    }

    let role: Role
    let content: String
    var toolCalls: [AIToolCall]? = nil
    var toolCallId: String? = nil

    init(role: Role, content: String, toolCalls: [AIToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

/// Хэндл на уже запущенный запрос к ИИ — единственное, что вызывающий код
/// может с ним сделать извне, это отменить. Кнопка «Стоп» в чате держит
/// именно такой хэндл, а не пытается дотянуться до внутренностей провайдера.
final class AITask {
    private let onCancel: () -> Void
    private var isCancelled = false

    init(onCancel: @escaping () -> Void = {}) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
}

/// Общий хелпер для провайдеров: запрос к серверу поднимается асинхронно
/// (`ensureRunning`), и отмена может прийти до того, как появится реальная
/// `URLSessionTask` — токен ловит оба случая.
final class CancelToken {
    private(set) var isCancelled = false
    var task: URLSessionTask?

    func cancel() {
        isCancelled = true
        task?.cancel()
    }
}

/// Единый интерфейс поверх локальной и облачной LLM.
/// Всегда вызывается с фонового потока; completion может прийти на любой очереди.
protocol AIProvider {
    var isReady: Bool { get }
    @discardableResult
    func complete(messages: [AIMessage], maxTokens: Int, completion: @escaping (Result<String, AIError>) -> Void) -> AITask

    /// Потоковая генерация: `onDelta` вызывается по мере поступления кусочков
    /// текста, `completion` — с полным ответом.
    ///
    /// Для локальной модели это не украшение, а необходимость: на 9B ответ
    /// в две тысячи токенов идёт полторы минуты, и без потока запрос просто
    /// упирается в таймаут, ничего не показав.
    @discardableResult
    func stream(messages: [AIMessage],
                maxTokens: Int,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void) -> AITask
}

extension AIProvider {
    /// Провайдеры без потока отдают ответ целиком одним куском.
    @discardableResult
    func stream(messages: [AIMessage],
                maxTokens: Int,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
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
    @discardableResult
    func stream(messages: [AIMessage],
                maxTokens: Int = 800,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        switch AppSettings.shared.aiProviderKind {
        case .none:
            completion(.failure(.notConfigured))
            return AITask()
        case .local:
            return LocalAIProvider.shared.stream(messages: messages, maxTokens: maxTokens,
                                          onDelta: onDelta, completion: completion)
        case .cloud:
            return CloudAIProvider.shared.stream(messages: messages, maxTokens: maxTokens,
                                          onDelta: onDelta, completion: completion)
        }
    }

    /// Универсальный метод для многооборотных диалогов (чат и т.д.)
    @discardableResult
    func complete(messages: [AIMessage], maxTokens: Int = 800, completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        switch AppSettings.shared.aiProviderKind {
        case .none:
            completion(.failure(.notConfigured))
            return AITask()
        case .local:
            return LocalAIProvider.shared.complete(messages: messages, maxTokens: maxTokens, completion: completion)
        case .cloud:
            return CloudAIProvider.shared.complete(messages: messages, maxTokens: maxTokens, completion: completion)
        }
    }

    /// Convenience-перегрузка для однооборотных задач (причёсывание текста в диктовке),
    /// чтобы существующий вызывающий код не менялся.
    @discardableResult
    func complete(system: String, user: String, maxTokens: Int = 800, completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        let messages = [
            AIMessage(role: .system, content: system),
            AIMessage(role: .user, content: user)
        ]
        return complete(messages: messages, maxTokens: maxTokens, completion: completion)
    }
}
