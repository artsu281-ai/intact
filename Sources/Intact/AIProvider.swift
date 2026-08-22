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
        case .notConfigured:      return "AI не настроен"
        case .network(let error): return "Сетевая ошибка: \(error.localizedDescription)"
        case .badResponse:        return "Некорректный ответ от AI"
        case .timeout:            return "AI не ответил вовремя"
        case .providerUnavailable: return "AI-провайдер недоступен"
        case .refused(let explanation):
            return explanation.map { "Модель отклонила запрос: \($0)" } ?? "Модель отклонила запрос"
        case .server(let code, let message):
            return "Ошибка \(code): \(message)"
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
            return AIErrorInfo(message: "Для этой задачи не выбрана модель.",
                               actionLabel: "Выбрать модель", section: .settings)

        case .providerUnavailable:
            return AIErrorInfo(message: "Локальная модель не запустилась. Проверьте, что установлен llama-server и выбранный файл модели на месте.",
                               actionLabel: "Открыть модели", section: .models)

        case .timeout:
            return AIErrorInfo(message: "Модель не ответила вовремя. Крупная модель на длинном тексте может не уложиться — повторите запрос или выберите модель полегче.",
                               actionLabel: "Сменить модель", section: .settings)

        case .network(let error):
            return AIErrorInfo(message: "Нет связи с сервером: \(error.localizedDescription)")

        case .badResponse:
            return AIErrorInfo(message: "Модель вернула пустой ответ. Обычно помогает просто повторить запрос.")

        case .refused(let explanation):
            return AIErrorInfo(message: explanation.map { "Модель отклонила запрос: \($0)" }
                               ?? "Модель отклонила запрос. Попробуйте переформулировать.")

        case .server(let code, let message):
            switch code {
            case 401, 403:
                return AIErrorInfo(message: "Ключ Anthropic не принят. Проверьте, что он скопирован целиком и не отозван.",
                                   actionLabel: "Проверить ключ", section: .settings)
            case 429:
                return AIErrorInfo(message: "Слишком много запросов подряд — API просит подождать. Повторите через минуту.")
            case 402:
                return AIErrorInfo(message: "На счету Anthropic закончились средства.",
                                   actionLabel: "Открыть настройки ИИ", section: .settings)
            case 500...599:
                return AIErrorInfo(message: "Сбой на стороне Anthropic. Обычно проходит за минуту.")
            default:
                return AIErrorInfo(message: "Запрос отклонён: \(message)")
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
        case .local(let filename):
            guard let match = LLMModel.matching(path: filename) else { return false }
            return LocalAIProvider.shared.isAvailable && match.model.isInstalled(match.quant)
        case .cloud:
            return CloudAIProvider.shared.isReady
        }
    }

    /// Разбирает выбор роли в конкретные параметры запроса.
    /// `nil` — ИИ для этой роли выключен или недонастроен.
    func routing(for role: AIRole, webSearch: Bool = false) -> AIRouting? {
        let choice = AIModelCatalog.resolved(for: role)
        switch choice {
        case .disabled:
            return nil

        case .cloud(let id):
            guard let model = AIModelCatalog.cloudModel(id: id) else { return nil }
            return AIRouting(
                choice: choice,
                role: role,
                isCloud: true,
                thinks: model.isThinkingModel,
                model: id,
                maxTokens: role.maxTokens(cloud: true, thinking: model.isThinkingModel),
                effort: model.supportsEffort ? role.cloudEffort : nil,
                timeout: role.timeout(cloud: true, thinking: model.isThinkingModel),
                webSearchTool: webSearch ? model.webSearchTool : nil)

        case .local(let filename):
            guard let path = AIModelCatalog.localPath(for: choice),
                  FileManager.default.fileExists(atPath: path) else { return nil }

            // Рассуждение включаем только там, где время не критично, и только
            // если модель это умеет. Дистиллятам R1 его не выключить в принципе —
            // значит, ждать их надо дольше в любой роли.
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
        return routing.isCloud
            ? CloudAIProvider.shared.stream(req, onDelta: onDelta, completion: completion)
            : LocalAIProvider.shared.stream(req, onDelta: onDelta, completion: completion)
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
        return routing.isCloud
            ? CloudAIProvider.shared.complete(req, completion: completion)
            : LocalAIProvider.shared.complete(req, completion: completion)
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
