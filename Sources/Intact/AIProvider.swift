import Foundation

enum AIError: Error {
    case notConfigured
    case network(Error)
    case badResponse
    case timeout
    case providerUnavailable
    /// Модель отказалась отвечать: приходит с кодом 200, без текста.
    case refused(String?)
    /// Сервер ответил ошибкой и объяснил, чем именно недоволен.
    case server(Int, String)

    var localizedDescription: String {
        switch self {
        case .notConfigured:      return T("AI не настроен", "AI is not configured")
        case .network(let error): return T("Сетевая ошибка: \(error.localizedDescription)", "Network error: \(error.localizedDescription)")
        case .badResponse:        return T("Некорректный ответ от AI", "Malformed response from the AI")
        case .timeout:            return T("AI не ответил вовремя", "The AI did not answer in time")
        case .providerUnavailable: return T("AI-провайдер недоступен", "AI provider unavailable")
        case .refused(let explanation):
            return explanation.map { T("Модель отклонила запрос: \($0)", "The model declined the request: \($0)") } ?? T("Модель отклонила запрос", "The model declined the request")
        case .server(let code, let message):
            return T("Ошибка \(code): \(message)", "Error \(code): \(message)")
        }
    }
}

/// Ошибка, приведённая к тому, что можно показать человеку: что случилось
/// и что с этим делать.
///
/// «Некорректный ответ от AI» и «Ошибка 400» — это то, что видел пользователь.
/// Ни одна из этих строк не говорит, что делать дальше, а починить их
/// в настольном приложении негде.
struct AIErrorInfo: Equatable {
    let message: String
    let actionLabel: String?
    let section: SettingsSection?

    init(message: String, actionLabel: String? = nil, section: SettingsSection? = nil) {
        self.message = message
        self.actionLabel = actionLabel
        self.section = section
    }
}

extension AIError {
    var info: AIErrorInfo {
        switch self {
        case .notConfigured:
            return AIErrorInfo(message: T("Для этой задачи не выбрана модель.", "No model is chosen for this task."),
                               actionLabel: T("Выбрать модель", "Choose a model"), section: .settings)

        case .providerUnavailable:
            // Причина может быть любой из двух совсем разных провайдеров:
            // локальная модель не запустилась (нет llama-server или файла модели)
            // либо Gemini.app не установлен/не отвечает — .info не знает, какой
            // именно из них сработал, поэтому формулировка не должна винить
            // конкретно llama-server, когда на деле не готов Gemini (и наоборот).
            return AIErrorInfo(message: T("Выбранный AI-провайдер сейчас недоступен: локальная модель не запустилась, либо не отвечает приложение Gemini.", "The chosen AI provider is unavailable right now: the local model failed to start, or the Gemini app is not responding."),
                               actionLabel: T("Открыть настройки ИИ", "Open AI settings"), section: .settings)

        case .timeout:
            return AIErrorInfo(message: T("Модель не ответила вовремя. Крупная модель на длинном тексте может не уложиться — повторите запрос или выберите модель полегче.", "The model did not answer in time. A large model on long text may not make it — retry, or pick a lighter model."),
                               actionLabel: T("Сменить модель", "Change the model"), section: .settings)

        case .network(let error):
            return AIErrorInfo(message: T("Нет связи с сервером: \(error.localizedDescription)", "No connection to the server: \(error.localizedDescription)"))

        case .badResponse:
            return AIErrorInfo(message: T("Модель вернула пустой ответ. Обычно помогает просто повторить запрос.", "The model returned an empty answer. Retrying usually helps."))

        case .refused(let explanation):
            return AIErrorInfo(message: explanation.map { T("Модель отклонила запрос: \($0)", "The model declined the request: \($0)") }
                               ?? T("Модель отклонила запрос. Попробуйте переформулировать.", "The model declined the request. Try rephrasing it."))

        case .server(let code, let message):
            switch code {
            case 401, 403:
                return AIErrorInfo(message: T("Доступ отклонён (\(code)). Проверьте настройки провайдера.", "Access denied (\(code)). Check the provider settings."),
                                   actionLabel: T("Открыть настройки ИИ", "Open AI settings"), section: .settings)
            case 429:
                return AIErrorInfo(message: T("Слишком много запросов подряд — сервер просит подождать. Повторите через минуту.", "Too many requests in a row — the server is asking you to wait. Retry in a minute."))
            case 402:
                return AIErrorInfo(message: T("Лимит запросов исчерпан.", "The request quota has run out."),
                                   actionLabel: T("Открыть настройки ИИ", "Open AI settings"), section: .settings)
            case 500...599:
                return AIErrorInfo(message: T("Сбой на стороне сервера (\(code)). Обычно проходит за минуту.", "A server-side failure (\(code)). Usually clears within a minute."))
            default:
                return AIErrorInfo(message: T("Запрос отклонён: \(message)", "Request rejected: \(message)"))
            }
        }
    }

    /// Короткая версия для мест, где кнопке действия негде поместиться —
    /// плавающий индикатор, лог.
    var shortMessage: String { info.message }
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

/// Один запрос к модели со всем, что зависит от выбора пользователя.
///
/// До этого провайдеры сами лезли в `AppSettings` за именем модели, поэтому
/// «модель» была ровно одна на всё приложение. Здесь она — параметр запроса,
/// и именно это позволяет разным разделам работать с разными моделями.
struct AIRequest {
    var messages: [AIMessage]
    var maxTokens: Int
    /// Идентификатор облачной модели либо путь к локальному GGUF-файлу.
    var model: String
    /// Чья это задача — нужно счётчику расхода, чтобы показать, какой
    /// раздел приложения сколько тратит.
    var role: AIRole? = nil
    /// Глубина рассуждения (`output_config.effort`), только для облака.
    var effort: String? = nil
    /// Разрешить модели искать в интернете.
    var webSearch: Bool = false
    /// Разрешить локальной модели рассуждать перед ответом.
    var allowThinking: Bool = false
    /// Потолок ожидания на уровне HTTP.
    var timeout: TimeInterval = 120
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
    func complete(_ request: AIRequest, completion: @escaping (Result<String, AIError>) -> Void) -> AITask

    /// Потоковая генерация: `onDelta` вызывается по мере поступления кусочков
    /// текста, `completion` — с полным ответом.
    ///
    /// Для локальной модели это не украшение, а необходимость: на 9B ответ
    /// в две тысячи токенов идёт полторы минуты, и без потока запрос просто
    /// упирается в таймаут, ничего не показав. Для облака то же самое верно
    /// для крупных рассуждающих моделей.
    @discardableResult
    func stream(_ request: AIRequest,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void) -> AITask
}

extension AIProvider {
    /// Провайдеры без потока отдают ответ целиком одним куском.
    @discardableResult
    func stream(_ request: AIRequest,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        complete(request) { result in
            if case .success(let text) = result { onDelta(text) }
            completion(result)
        }
    }
}

/// Куда и с какими параметрами уходит запрос конкретной роли.
struct AIRouting {
    let choice: AIModelChoice
    let role: AIRole
    let isCloud: Bool
    /// Модель будет рассуждать перед ответом — значит, ждать её дольше.
    var thinks: Bool = false
    var allowThinking: Bool = false
    /// Идентификатор облачной модели либо путь к локальному файлу.
    let model: String
    let maxTokens: Int
    let effort: String?
    let timeout: TimeInterval
    let webSearchTool: String?
}

/// Выбирает провайдера и модель под конкретную роль и делегирует ей вызовы.
/// DictationController, чат и сервисы Reminders/Notes обращаются только сюда
/// и не знают, работает ли сейчас локальная модель или облачный API.
final class AIRouter {
    static let shared = AIRouter()

    private init() {}

    /// Готовность общего выбора по умолчанию.
    var isReady: Bool { isReady(for: .chat) }

    func isReady(for role: AIRole) -> Bool {
        switch AIModelCatalog.resolved(for: role) {
        case .disabled: return false
        case .gemini:
            return GeminiAIProvider.shared.isReady
        case .local(let filename):
            guard let match = LLMModel.matching(path: filename) else { return false }
            return LocalAIProvider.shared.isAvailable && match.model.isInstalled(match.quant)
        }
    }

    /// Разбирает выбор роли в конкретные параметры запроса.
    /// `nil` — ИИ для этой роли выключен или недонастроен.
    func routing(for role: AIRole, webSearch: Bool = false) -> AIRouting? {
        let choice = AIModelCatalog.resolved(for: role)
        switch choice {
        case .disabled:
            return nil

        case .gemini:
            guard GeminiAIProvider.shared.isReady else { return nil }
            return AIRouting(
                choice: choice,
                role: role,
                // Само приложение Gemini локально, но обработка идёт на серверах
                // Google — те же данные, что попадают в облачную плашку в чате.
                isCloud: true,
                thinks: true,
                allowThinking: false,
                model: "gemini:app",
                maxTokens: 4096,
                effort: nil,
                timeout: role == .cleanup ? 20 : 60,
                webSearchTool: nil)

        case .local(let filename):
            guard let path = AIModelCatalog.localPath(for: choice),
                  FileManager.default.fileExists(atPath: path) else { return nil }

            let thinking = LLMModel.matching(path: filename)?.model.thinking ?? LLMThinking.none
            let allowThinking = role == .chat
                && AppSettings.shared.localThinkingInChat
                && thinking != .none
            let thinks = thinking == .always || allowThinking

            return AIRouting(
                choice: choice,
                role: role,
                isCloud: false,
                thinks: thinks,
                allowThinking: allowThinking,
                model: path,
                maxTokens: role.maxTokens(cloud: false, thinking: thinks),
                effort: nil,
                timeout: role.timeout(cloud: false, thinking: thinks),
                webSearchTool: nil)
        }
    }

    private func request(_ routing: AIRouting, messages: [AIMessage]) -> AIRequest {
        AIRequest(messages: messages,
                  maxTokens: routing.maxTokens,
                  model: routing.model,
                  role: routing.role,
                  effort: routing.effort,
                  webSearch: routing.webSearchTool != nil,
                  allowThinking: routing.allowThinking,
                  timeout: routing.timeout)
    }

    // MARK: - Потоковая генерация

    @discardableResult
    func stream(role: AIRole,
                messages: [AIMessage],
                webSearch: Bool = false,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        guard let routing = routing(for: role, webSearch: webSearch) else {
            completion(.failure(.notConfigured))
            return AITask()
        }
        let req = request(routing, messages: messages)
        switch routing.choice {
        case .gemini:
            return GeminiAIProvider.shared.stream(req, onDelta: onDelta, completion: completion)
        case .local:
            return LocalAIProvider.shared.stream(req, onDelta: onDelta, completion: completion)
        case .disabled:
            completion(.failure(.notConfigured))
            return AITask()
        }
    }

    // MARK: - Обычный запрос

    @discardableResult
    func complete(role: AIRole,
                  messages: [AIMessage],
                  completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        guard let routing = routing(for: role) else {
            completion(.failure(.notConfigured))
            return AITask()
        }
        let req = request(routing, messages: messages)
        switch routing.choice {
        case .gemini:
            return GeminiAIProvider.shared.complete(req, completion: completion)
        case .local:
            return LocalAIProvider.shared.complete(req, completion: completion)
        case .disabled:
            completion(.failure(.notConfigured))
            return AITask()
        }
    }

    /// Convenience для однооборотных задач — причёсывания и быстрого ответа.
    @discardableResult
    func complete(role: AIRole,
                  system: String,
                  user: String,
                  completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        complete(role: role,
                 messages: [AIMessage(role: .system, content: system),
                            AIMessage(role: .user, content: user)],
                 completion: completion)
    }
}
