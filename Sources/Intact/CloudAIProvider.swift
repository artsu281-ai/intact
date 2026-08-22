import Foundation

/// Клиент Anthropic Messages API. Ключ хранится только в Keychain,
/// никогда в UserDefaults.
///
/// Модель приходит параметром запроса, а не берётся из настроек: именно это
/// позволяет причёсывать диктовку на Haiku, пока чат работает на Opus.
final class CloudAIProvider: AIProvider {
    static let shared = CloudAIProvider()
    static let keychainService = "com.artsu.intact.anthropic-api-key"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"
    /// Бета серверного fallback: при отказе классификатора запрос
    /// автоматически переигрывается на запасной модели внутри того же вызова.
    private static let fallbackBeta = "server-side-fallback-2026-07-01"

    /// Модели, у которых расширенные параметры уже вызвали 400.
    ///
    /// Без этого каждый следующий запрос снова платил бы двумя обращениями:
    /// первое — с полями, которые эта модель не понимает, второе — повтор.
    /// Живёт до перезапуска приложения: набор параметров у модели не меняется
    /// в течение сессии.
    private var extrasRejected = Set<String>()
    private let extrasLock = NSLock()

    private func extrasAllowed(for model: String) -> Bool {
        extrasLock.lock(); defer { extrasLock.unlock() }
        return !extrasRejected.contains(model)
    }

    private func rememberExtrasRejected(_ model: String) {
        extrasLock.lock(); defer { extrasLock.unlock() }
        extrasRejected.insert(model)
    }

    private init() {}

    var isReady: Bool {
        !(KeychainHelper.get(service: Self.keychainService) ?? "").isEmpty
    }

    private var apiKey: String? {
        let key = KeychainHelper.get(service: Self.keychainService) ?? ""
        return key.isEmpty ? nil : key
    }

    // MARK: - Обычный запрос

    @discardableResult
    func complete(_ request: AIRequest, completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        guard let apiKey else {
            completion(.failure(.notConfigured))
            return AITask()
        }

        let token = CancelToken()
        send(request, apiKey: apiKey, streaming: false, allowExtras: extrasAllowed(for: request.model),
             token: token, onDelta: { _ in }, completion: completion)
        return AITask(onCancel: { token.cancel() })
    }

    // MARK: - Потоковая генерация

    /// Крупные модели отвечают минутами, и без потока запрос выглядит как
    /// зависание: ни текста, ни возможности остановиться. Поток решает обе
    /// проблемы разом и снимает потолок на длину ответа.
    @discardableResult
    func stream(_ request: AIRequest,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        guard let apiKey else {
            completion(.failure(.notConfigured))
            return AITask()
        }

        let token = CancelToken()
        send(request, apiKey: apiKey, streaming: true, allowExtras: extrasAllowed(for: request.model),
             token: token, onDelta: onDelta, completion: completion)
        return AITask(onCancel: { token.cancel() })
    }

    // MARK: - Отправка

    /// `allowExtras` выключается на повторной попытке.
    ///
    /// Рассуждение, глубина, веб-поиск и fallback — параметры, набор которых
    /// у разных поколений моделей разный, и лишний из них отвечает не мягкой
    /// деградацией, а HTTP 400 на весь запрос. Пользователю настольного
    /// приложения такую ошибку чинить негде, поэтому один раз пробуем ещё раз
    /// без всего необязательного: лучше ответ попроще, чем красный баннер.
    private func send(_ request: AIRequest,
                      apiKey: String,
                      streaming: Bool,
                      allowExtras: Bool,
                      token: CancelToken,
                      onDelta: @escaping (String) -> Void,
                      completion: @escaping (Result<String, AIError>) -> Void) {
        guard !token.isCancelled else { return }

        let model = AIModelCatalog.cloudModel(id: request.model)
        let body = Self.requestBody(request, model: model, streaming: streaming, extras: allowExtras)
        let useFallback = allowExtras && (model?.supportsRefusalFallback ?? false)

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if useFallback {
            req.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Повтор без необязательных параметров — единственный способ пережить
        // модель, которая не понимает какое-то из полей.
        let retryPlain: (Int, String) -> Bool = { [weak self] status, message in
            guard allowExtras, status == 400, let self else { return false }
            // Повторяем только если сервер ругается именно на необязательное
            // поле: 400 из-за кривой истории сообщений повтор не починит,
            // а тихо отключит рассуждение до конца сессии.
            let optionalFields = ["thinking", "effort", "output_config", "fallback", "beta", "tool", "web_search"]
            let lower = message.lowercased()
            guard optionalFields.contains(where: { lower.contains($0) }) else { return false }

            Log.write("Anthropic отклонил расширенные параметры (\(message)) — повтор без них")
            self.rememberExtrasRejected(request.model)
            self.send(request, apiKey: apiKey, streaming: streaming, allowExtras: false,
                      token: token, onDelta: onDelta, completion: completion)
            return true
        }

        if streaming {
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            let collector = AnthropicSSECollector(onDelta: onDelta,
                                                  onRetryableFailure: retryPlain,
                                                  completion: completion)
            let config = URLSessionConfiguration.ephemeral
            // Таймер простоя, а не общий срок: пока идут токены, он сбрасывается.
            // Три минуты — запас на обработку длинного промпта до первого
            // токена у рассуждающей модели; растягивать его до общего лимита
            // роли нельзя, иначе оборванное соединение висит четверть часа.
            config.timeoutIntervalForRequest = 180
            config.timeoutIntervalForResource = max(request.timeout, 900)
            let session = URLSession(configuration: config, delegate: collector, delegateQueue: nil)
            collector.session = session
            let task = session.dataTask(with: req)
            token.task = task
            task.resume()
            return
        }

        req.timeoutInterval = request.timeout
        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                if (error as NSError).code == NSURLErrorCancelled { return }
                completion(.failure((error as NSError).code == NSURLErrorTimedOut ? .timeout : .network(error)))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(.badResponse))
                return
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            guard (200..<300).contains(http.statusCode) else {
                let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "нет описания"
                if retryPlain(http.statusCode, message) { return }
                completion(.failure(.server(http.statusCode, message)))
                return
            }
            guard let json else {
                completion(.failure(.badResponse))
                return
            }

            // Отказ приходит обычным 200 и без текстового блока. Без этой
            // ветки он выглядел бы как «некорректный ответ от AI».
            if json["stop_reason"] as? String == "refusal" {
                let explanation = (json["stop_details"] as? [String: Any])?["explanation"] as? String
                completion(.failure(.refused(explanation)))
                return
            }

            // Блоки рассуждения и результаты веб-поиска идут вперемешку
            // с ответом — склеиваем именно текстовые.
            guard let content = json["content"] as? [[String: Any]] else {
                completion(.failure(.badResponse))
                return
            }
            let text = content
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
            guard !text.isEmpty else {
                completion(.failure(.badResponse))
                return
            }
            completion(.success(text))
        }
        token.task = task
        task.resume()
    }

    // MARK: - Тело запроса

    private static func requestBody(_ request: AIRequest,
                                    model: CloudModel?,
                                    streaming: Bool,
                                    extras: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "messages": conversation(request.messages)
        ]

        let system = request.messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")
        if !system.isEmpty {
            // Контекст ветки теперь собирается один раз, поэтому системный блок
            // от реплики к реплике байт-в-байт одинаков — как раз то, что можно
            // кэшировать на стороне API. Минимальный кэшируемый префикс — около
            // 1024 токенов; для кириллицы это примерно 3000 символов, и на
            // коротких промптах пометка всё равно не сработала бы.
            if system.count > 4000 {
                body["system"] = [["type": "text", "text": system,
                                   "cache_control": ["type": "ephemeral"]]]
            } else {
                body["system"] = system
            }
        }
        if streaming { body["stream"] = true }

        guard extras, let model else { return body }

        switch model.thinking {
        case .always:
            // Рассуждение включено всегда, и любое явное значение — ошибка.
            break
        case .adaptive:
            body["thinking"] = ["type": "adaptive"]
        case .legacy:
            break
        }

        if model.supportsEffort, let effort = request.effort {
            body["output_config"] = ["effort": effort]
        }

        if request.webSearch {
            body["tools"] = [["type": model.webSearchTool, "name": "web_search"]]
        }

        if model.supportsRefusalFallback {
            body["fallbacks"] = "default"
        }

        return body
    }

    /// Приводит историю к тому, что принимает Messages API: только `user`
    /// и `assistant`, строго по очереди, начиная с пользователя.
    ///
    /// Результаты инструментов сюда попадают только от локального цикла
    /// вызовов — облако ищет само, на своей стороне. Их место в разговоре
    /// всё равно нужно сохранить, иначе модель отвечает без того, что нашла.
    private static func conversation(_ messages: [AIMessage]) -> [[String: Any]] {
        var result: [(role: String, content: String)] = []

        for message in messages {
            let role: String
            let text: String
            switch message.role {
            case .system:
                continue
            case .user:
                role = "user"; text = message.content
            case .assistant:
                role = "assistant"; text = message.content
            case .tool:
                role = "user"; text = "Результат инструмента:\n\(message.content)"
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Подряд идущие реплики одной роли API не принимает — склеиваем.
            if let last = result.last, last.role == role {
                result[result.count - 1].content += "\n\n" + trimmed
            } else {
                result.append((role, trimmed))
            }
        }

        // Разговор обязан начинаться с пользователя.
        while let first = result.first, first.role != "user" {
            result.removeFirst()
        }

        return result.map { ["role": $0.role, "content": $0.content] }
    }
}

/// Разбирает поток server-sent events Anthropic.
///
/// Строки собираются в двоичном буфере и декодируются только целиком:
/// кириллический символ легко разрезается между пакетами, и посимвольное
/// декодирование ломало бы текст.
private final class AnthropicSSECollector: NSObject, URLSessionDataDelegate {
    private let onDelta: (String) -> Void
    /// Возвращает true, если ошибку взяли на повтор и завершать поток не надо.
    private let onRetryableFailure: (Int, String) -> Bool
    private let completion: (Result<String, AIError>) -> Void

    private var buffer = Data()
    private var text = ""
    private var finished = false
    private var statusCode = 200
    private var errorPayload = Data()
    private var refusal: String?
    private var sawRefusal = false
    var session: URLSession?

    init(onDelta: @escaping (String) -> Void,
         onRetryableFailure: @escaping (Int, String) -> Bool,
         completion: @escaping (Result<String, AIError>) -> Void) {
        self.onDelta = onDelta
        self.onRetryableFailure = onRetryableFailure
        self.completion = completion
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Ошибку сервер отдаёт обычным JSON, а не потоком событий.
        guard (200..<300).contains(statusCode) else {
            errorPayload.append(data)
            return
        }

        buffer.append(data)
        let newline = Data([0x0A])
        while let range = buffer.range(of: newline) {
            let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            handle(line: String(decoding: line, as: UTF8.self))
        }
    }

    private func handle(line raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("data:") else { return }

        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "content_block_delta":
            // Блоки рассуждения и аргументы серверных инструментов приходят
            // своими типами дельт — в ответ идёт только текст.
            guard let delta = json["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let piece = delta["text"] as? String,
                  !piece.isEmpty else { return }
            text += piece
            onDelta(piece)

        case "message_delta":
            guard let delta = json["delta"] as? [String: Any] else { return }
            if delta["stop_reason"] as? String == "refusal" {
                sawRefusal = true
                refusal = (delta["stop_details"] as? [String: Any])?["explanation"] as? String
            }

        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "поток прерван"
            finish(.failure(.server(statusCode, message)))

        default:
            break
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }

        if !(200..<300).contains(statusCode) {
            let json = (try? JSONSerialization.jsonObject(with: errorPayload)) as? [String: Any]
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "нет описания"
            if onRetryableFailure(statusCode, message) {
                finished = true
                self.session?.finishTasksAndInvalidate()
                return
            }
            finish(.failure(.server(statusCode, message)))
            return
        }

        if let error {
            // Успели набрать текст до обрыва — отдаём его, это лучше пустоты.
            if !text.isEmpty {
                finish(.success(text))
            } else if (error as NSError).code == NSURLErrorCancelled {
                // Нажали «Стоп» до первого токена — тихо закрываем, без баннера ошибки.
                finish(.success(""))
            } else {
                finish(.failure((error as NSError).code == NSURLErrorTimedOut ? .timeout : .network(error)))
            }
            return
        }

        if text.isEmpty && sawRefusal {
            finish(.failure(.refused(refusal)))
        } else if text.isEmpty {
            finish(.failure(.badResponse))
        } else {
            finish(.success(text))
        }
    }

    private func finish(_ result: Result<String, AIError>) {
        guard !finished else { return }
        finished = true
        completion(result)
        session?.finishTasksAndInvalidate()
    }
}
