import Foundation

/// Держит llama-server живым с загруженной локальной моделью — по образцу WhisperServer.
///
/// Серверов может быть несколько: с тех пор как каждый раздел приложения
/// выбирает модель сам, «одна модель на приложение» означала бы перезагрузку
/// весов на каждое переключение между причёсыванием и чатом — а это десятки
/// секунд и чтение гигабайтов с диска. Поэтому здесь пул: маленькая модель
/// причёсывания и крупная модель чата живут одновременно, пока хватает памяти,
/// и самый давно не используемый сервер выгружается, когда её перестаёт хватать.
final class LocalAIProvider: AIProvider {
    static let shared = LocalAIProvider()

    /// Один запущенный llama-server с конкретным файлом весов.
    private final class ServerInstance {
        let path: String
        let process: Process
        let port: Int
        /// Вес файла в гигабайтах — по нему считается, сколько он занимает памяти.
        let weightsGB: Double
        var lastUsed: Date

        init(path: String, process: Process, port: Int, weightsGB: Double) {
            self.path = path
            self.process = process
            self.port = port
            self.weightsGB = weightsGB
            self.lastUsed = Date()
        }

        /// Веса плюс примерно 30 % под KV-кэш контекста и служебные буферы.
        var footprintGB: Double { weightsGB * 1.3 }
    }

    private let lock = NSLock()
    private var servers: [String: ServerInstance] = [:]
    /// Кто ждёт, пока поднимется сервер по этому пути. Без этого два
    /// одновременных запроса к одной модели запустили бы два процесса.
    private var waiters: [String: [(Bool) -> Void]] = [:]

    /// Сколько гигабайтов оставляем macOS. Без этого запаса машина уходит
    /// в своп и отвечает минутами вместо секунд.
    private static let systemReserveGB: Double = 4

    private var binary: String? {
        ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isAvailable: Bool { binary != nil }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return servers.values.contains { $0.process.isRunning }
    }

    /// Достаточно ли всё готово, чтобы стоило пытаться — сам сервер поднимется лениво.
    var isReady: Bool {
        isAvailable && FileManager.default.fileExists(atPath: AppSettings.shared.aiLocalModelPath)
    }

    /// Какие модели прямо сейчас загружены в память — для показа в интерфейсе.
    var loadedModelPaths: [String] {
        lock.lock(); defer { lock.unlock() }
        return servers.values.filter { $0.process.isRunning }.map(\.path)
    }

    private init() {}

    // MARK: - Жизненный цикл серверов

    /// Поднимает сервер для конкретного файла модели, если он ещё не поднят.
    func ensureRunning(modelPath: String, completion: @escaping (Bool) -> Void) {
        guard let bin = binary, FileManager.default.fileExists(atPath: modelPath) else {
            completion(false)
            return
        }

        lock.lock()

        if let existing = servers[modelPath] {
            if existing.process.isRunning {
                existing.lastUsed = Date()
                lock.unlock()
                completion(true)
                return
            }
            servers.removeValue(forKey: modelPath)
        }

        if waiters[modelPath] != nil {
            waiters[modelPath]?.append(completion)
            lock.unlock()
            return
        }
        waiters[modelPath] = [completion]

        let weightsGB = Self.weightsGB(of: modelPath)
        evictUntilRoom(for: weightsGB * 1.3, excluding: modelPath)

        let port = Self.freePort()
        let contextSize = contextSizeLocked(weightsGB: weightsGB)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["-m", modelPath, "--port", String(port), "--host", "127.0.0.1",
                             "-c", String(contextSize)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            let pending = waiters.removeValue(forKey: modelPath) ?? []
            lock.unlock()
            Log.write("llama-server не запустился — \(error.localizedDescription)")
            pending.forEach { $0(false) }
            return
        }

        servers[modelPath] = ServerInstance(path: modelPath, process: process,
                                            port: port, weightsGB: weightsGB)
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(120)
            var ok = false
            while Date() < deadline {
                if !process.isRunning { break }
                if Self.ping(port: port) { ok = true; break }
                Thread.sleep(forTimeInterval: 0.25)
            }

            self.lock.lock()
            if !ok { self.servers.removeValue(forKey: modelPath) }
            let pending = self.waiters.removeValue(forKey: modelPath) ?? []
            self.lock.unlock()

            if !ok { process.terminate() }
            pending.forEach { $0(ok) }
        }
    }

    /// Совместимость с прежним вызовом: поднимает модель по умолчанию.
    func ensureRunning(completion: @escaping (Bool) -> Void) {
        ensureRunning(modelPath: AppSettings.shared.aiLocalModelPath, completion: completion)
    }

    /// Останавливает все серверы — при выходе и при смене набора моделей.
    func stop() {
        lock.lock()
        let running = Array(servers.values)
        servers.removeAll()
        lock.unlock()
        running.forEach { $0.process.terminate() }
    }

    func stop(modelPath: String) {
        lock.lock()
        let instance = servers.removeValue(forKey: modelPath)
        lock.unlock()
        instance?.process.terminate()
    }

    /// Выгружает давно не использованные серверы, пока не освободится место.
    /// Вызывается с уже захваченным `lock`.
    private func evictUntilRoom(for neededGB: Double, excluding path: String) {
        let budget = Hardware.physicalMemoryGB - Self.systemReserveGB
        var alive = servers.values.filter { $0.process.isRunning && $0.path != path }
        var used = alive.reduce(0) { $0 + $1.footprintGB }

        while used + neededGB > budget, !alive.isEmpty {
            guard let victim = alive.min(by: { $0.lastUsed < $1.lastUsed }) else { break }
            Log.write("выгружаю локальную модель \(URL(fileURLWithPath: victim.path).lastPathComponent) — не хватает памяти")
            victim.process.terminate()
            servers.removeValue(forKey: victim.path)
            alive.removeAll { $0.path == victim.path }
            used -= victim.footprintGB
        }
    }

    /// Убивает осиротевшие llama-server из прошлых запусков приложения — если предыдущий
    /// процесс Intact был закрыт не штатно (kill -9, пересборка), дочерний сервер продолжает
    /// висеть в памяти с загруженной моделью.
    static func killAllOrphanedServers() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-9", "-f", "llama-server"]
        try? task.run()
        task.waitUntilExit()
    }

    private static func weightsGB(of path: String) -> Double {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return Double((attributes?[.size] as? NSNumber)?.int64Value ?? 0) / 1_000_000_000
    }

    /// Сколько токенов контекста поднимать.
    ///
    /// KV-кэш живёт в той же памяти, что и веса модели, поэтому окно считаем
    /// от запаса, который остаётся после весов — и после уже поднятых соседей.
    /// Вызывается с уже захваченным `lock`.
    private func contextSizeLocked(weightsGB: Double) -> Int {
        let others = servers.values
            .filter { $0.process.isRunning }
            .reduce(0) { $0 + $1.footprintGB }
        let headroom = Hardware.physicalMemoryGB - weightsGB - others - Self.systemReserveGB

        // Потолок 32k осознанный: приложению нужно около 8–12 тысяч токенов
        // (системный промпт, диктовки, заметки, история диалога и ответ),
        // а крупные модели тянут длинные брифы с прикреплёнными файлами.
        switch headroom {
        case ..<2:  return 4096
        case ..<5:  return 8192
        case ..<12: return 16384
        default:    return 32768
        }
    }

    private static func ping(port: Int) -> Bool {
        guard port != 0, let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { _, response, _ in
            ok = (response as? HTTPURLResponse) != nil
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.5)
        return ok
    }

    private func port(for path: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard let server = servers[path], server.process.isRunning else { return nil }
        server.lastUsed = Date()
        return server.port
    }

    /// Путь к весам: из запроса, а если он пуст — модель по умолчанию.
    private func resolvePath(_ request: AIRequest) -> String {
        request.model.isEmpty ? AppSettings.shared.aiLocalModelPath : request.model
    }

    // MARK: - Запрос

    @discardableResult
    func complete(_ request: AIRequest, completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        let cancelToken = CancelToken()
        guard isAvailable else { completion(.failure(.providerUnavailable)); return AITask() }
        let path = resolvePath(request)

        ensureRunning(modelPath: path) { [weak self] ok in
            guard !cancelToken.isCancelled else { return }
            guard let self, ok, let port = self.port(for: path),
                  let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
                completion(.failure(.providerUnavailable))
                return
            }

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject:
                Self.requestBody(messages: request.messages, maxTokens: request.maxTokens))
            // Щедро: локальная модель на длинном ответе идёт минутами,
            // а сам вызывающий код держит собственный, более короткий таймер.
            req.timeoutInterval = 600

            let task = URLSession.shared.dataTask(with: req) { data, response, error in
                if let error {
                    if (error as NSError).code == NSURLErrorCancelled { return }
                    completion(.failure((error as NSError).code == NSURLErrorTimedOut ? .timeout : .network(error)))
                    return
                }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let text = message["content"] as? String else {
                    completion(.failure(.badResponse))
                    return
                }
                completion(.success(text))
            }
            cancelToken.task = task
            task.resume()
        }
        return AITask(onCancel: { cancelToken.cancel() })
    }

    struct ToolCompletionResult {
        let content: String?
        let toolCalls: [AIToolCall]
    }

    /// Как `complete`, но с полем `tools` — модель может либо ответить текстом,
    /// либо попросить вызвать один из инструментов (веб-поиск, чтение страницы).
    /// Только для локального провайдера: облачные модели ищут сами, серверным
    /// инструментом, и клиентский цикл им не нужен.
    @discardableResult
    func completeWithTools(_ request: AIRequest, tools: [[String: Any]],
                           completion: @escaping (Result<ToolCompletionResult, AIError>) -> Void) -> AITask {
        let cancelToken = CancelToken()
        guard isAvailable else { completion(.failure(.providerUnavailable)); return AITask() }
        let path = resolvePath(request)

        ensureRunning(modelPath: path) { [weak self] ok in
            guard !cancelToken.isCancelled else { return }
            guard let self, ok, let port = self.port(for: path),
                  let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
                completion(.failure(.providerUnavailable))
                return
            }

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject:
                Self.requestBody(messages: request.messages, maxTokens: request.maxTokens, tools: tools))
            req.timeoutInterval = 300

            let task = URLSession.shared.dataTask(with: req) { data, response, error in
                if let error {
                    if (error as NSError).code == NSURLErrorCancelled { return }
                    completion(.failure((error as NSError).code == NSURLErrorTimedOut ? .timeout : .network(error)))
                    return
                }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any] else {
                    completion(.failure(.badResponse))
                    return
                }

                let content = message["content"] as? String
                var toolCalls: [AIToolCall] = []
                if let rawCalls = message["tool_calls"] as? [[String: Any]] {
                    for call in rawCalls {
                        guard let id = call["id"] as? String,
                              let function = call["function"] as? [String: Any],
                              let name = function["name"] as? String,
                              let arguments = function["arguments"] as? String else { continue }
                        toolCalls.append(AIToolCall(id: id, name: name, arguments: arguments))
                    }
                }
                guard content != nil || !toolCalls.isEmpty else {
                    completion(.failure(.badResponse))
                    return
                }
                completion(.success(ToolCompletionResult(content: content, toolCalls: toolCalls)))
            }
            cancelToken.task = task
            task.resume()
        }
        return AITask(onCancel: { cancelToken.cancel() })
    }

    private static func messageJSON(_ m: AIMessage) -> [String: Any] {
        var dict: [String: Any] = ["role": m.role.rawValue, "content": m.content]
        if let calls = m.toolCalls, !calls.isEmpty {
            dict["tool_calls"] = calls.map { call in
                ["id": call.id, "type": "function",
                 "function": ["name": call.name, "arguments": call.arguments]]
            }
        }
        if let toolCallId = m.toolCallId {
            dict["tool_call_id"] = toolCallId
        }
        return dict
    }

    private static func requestBody(messages: [AIMessage], maxTokens: Int, tools: [[String: Any]]? = nil) -> [String: Any] {
        var body: [String: Any] = [
            "messages": messages.map { messageJSON($0) },
            "max_tokens": maxTokens,
            "temperature": 0.3,
            // Некоторые модели (Qwen3.5 и т.п.) по умолчанию «думают» перед ответом и уходят
            // в reasoning_content, оставляя content пустым — весь лимит токенов сгорает
            // на рассуждения. Явно отключаем thinking-режим, если модель его поддерживает;
            // модели без такого шаблона это поле просто игнорируют.
            "chat_template_kwargs": ["enable_thinking": false]
        ]
        if let tools, !tools.isEmpty { body["tools"] = tools }
        return body
    }

    // MARK: - Потоковая генерация

    /// Ответ приходит по кусочкам, как их выдаёт модель.
    ///
    /// Это не косметика: на 9B скорость около 24 токенов в секунду, то есть
    /// развёрнутый ответ идёт полторы минуты. Одним куском такой запрос
    /// упирался в таймаут и пропадал целиком, ничего не показав.
    @discardableResult
    func stream(_ request: AIRequest,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        guard isAvailable else { completion(.failure(.providerUnavailable)); return AITask() }

        let cancelToken = CancelToken()
        var collectorBox: SSECollector?
        let path = resolvePath(request)

        ensureRunning(modelPath: path) { [weak self] ok in
            guard !cancelToken.isCancelled else { return }
            guard let self, ok, let port = self.port(for: path),
                  let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
                completion(.failure(.providerUnavailable))
                return
            }

            var body = Self.requestBody(messages: request.messages, maxTokens: request.maxTokens)
            body["stream"] = true

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)

            let collector = SSECollector(onDelta: onDelta, completion: completion)
            collectorBox = collector
            let config = URLSessionConfiguration.ephemeral
            // Таймер простоя, а не общий срок: пока идут токены, он сбрасывается.
            // Запас в две минуты нужен на обработку длинного промпта до первого токена.
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 1800
            let session = URLSession(configuration: config, delegate: collector, delegateQueue: nil)
            collector.session = session
            session.dataTask(with: req).resume()
        }

        return AITask(onCancel: {
            cancelToken.cancel()
            collectorBox?.cancel()
        })
    }

    // MARK: - Установка сервера через Homebrew

    var isHomebrewAvailable: Bool { brewBinary != nil }

    private var brewBinary: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Ставит llama.cpp (а вместе с ним и llama-server) через Homebrew.
    /// `output` вызывается построчно с логом установки, на главном потоке.
    func installViaHomebrew(output: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        guard let brew = brewBinary else {
            completion(false)
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: brew)
        p.arguments = ["install", "llama.cpp"]

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { output(line) }
        }

        p.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { completion(proc.terminationStatus == 0) }
        }

        do { try p.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            completion(false)
        }
    }

    private static func freePort() -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return 8478 }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) {
            _ = $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &len)
            }
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

/// Разбирает поток server-sent events от llama-server.
///
/// Строки собираются в двоичном буфере и декодируются только целиком:
/// кириллический символ легко разрезается между пакетами, и посимвольное
/// декодирование ломало бы текст.
private final class SSECollector: NSObject, URLSessionDataDelegate {
    private let onDelta: (String) -> Void
    private let completion: (Result<String, AIError>) -> Void
    private var buffer = Data()
    private var text = ""
    private var finished = false
    var session: URLSession?

    init(onDelta: @escaping (String) -> Void,
         completion: @escaping (Result<String, AIError>) -> Void) {
        self.onDelta = onDelta
        self.completion = completion
    }

    /// Обрывает соединение по нажатию «Стоп». `didCompleteWithError` сам
    /// разберётся, что делать с уже накопленным текстом.
    func cancel() {
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
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
        guard payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let piece = delta["content"] as? String,
              !piece.isEmpty else { return }

        text += piece
        onDelta(piece)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        finished = true
        defer { self.session?.finishTasksAndInvalidate() }

        if let error {
            // Успели набрать текст до обрыва — отдаём его, это лучше пустоты.
            if !text.isEmpty {
                completion(.success(text))
            } else if (error as NSError).code == NSURLErrorCancelled {
                // Нажали «Стоп» до первого токена — тихо закрываем, без баннера ошибки.
                completion(.success(""))
            } else {
                completion(.failure((error as NSError).code == NSURLErrorTimedOut ? .timeout : .network(error)))
            }
        } else if text.isEmpty {
            completion(.failure(.badResponse))
        } else {
            completion(.success(text))
        }
    }
}
