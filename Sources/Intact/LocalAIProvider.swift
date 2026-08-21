import Foundation

/// Держит llama-server живым с загруженной локальной моделью — по образцу WhisperServer.
/// В отличие от WhisperServer, вызовы неблокирующие: задержка LLM менее предсказуема,
/// и в будущем сюда добавится диалоговый режим, которому блокирующий вызов не подходит.
final class LocalAIProvider: AIProvider {
    static let shared = LocalAIProvider()

    private var process: Process?
    private(set) var port: Int = 0
    private var bootedWith: String = ""
    private let lock = NSLock()

    private var binary: String? {
        ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isAvailable: Bool { binary != nil }
    var isRunning: Bool { process?.isRunning == true && port != 0 }

    /// Достаточно ли всё готово, чтобы стоило пытаться — сам сервер поднимется лениво в complete().
    var isReady: Bool {
        isAvailable && FileManager.default.fileExists(atPath: AppSettings.shared.aiLocalModelPath)
    }

    private init() {}

    /// Поднимает сервер, если он ещё не поднят или сменилась модель.
    func ensureRunning(completion: @escaping (Bool) -> Void) {
        let modelPath = AppSettings.shared.aiLocalModelPath
        let bootKey = "\(modelPath)#\(Self.contextSize(forModelAt: modelPath))"
        lock.lock()
        if isRunning && bootKey == bootedWith {
            lock.unlock()
            completion(true)
            return
        }
        lock.unlock()

        stop()
        Self.killAllOrphanedServers()

        guard let bin = binary, FileManager.default.fileExists(atPath: modelPath) else {
            completion(false)
            return
        }

        let chosenPort = Self.freePort()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        let contextSize = Self.contextSize(forModelAt: modelPath)
        p.arguments = ["-m", modelPath, "--port", String(chosenPort), "--host", "127.0.0.1",
                       "-c", String(contextSize)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice

        do { try p.run() } catch {
            NSLog("Intact: llama-server не запустился — \(error.localizedDescription)")
            completion(false)
            return
        }

        process = p
        port = chosenPort
        bootedWith = bootKey

        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline {
                if !p.isRunning { break }
                if self.ping() { completion(true); return }
                Thread.sleep(forTimeInterval: 0.25)
            }
            completion(false)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        port = 0
        bootedWith = ""
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

    /// Сколько токенов контекста поднимать.
    ///
    /// KV-кэш живёт в той же памяти, что и веса модели, поэтому окно считаем
    /// от запаса, который остаётся после весов. Фиксированные 4096 не вмещали
    /// ни контекст из диктовок, ни развёрнутый ответ.
    private static func contextSize(forModelAt path: String) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let weightsGB = Double((attributes?[.size] as? NSNumber)?.int64Value ?? 0) / 1_000_000_000
        let headroom = Hardware.physicalMemoryGB - weightsGB - 4  // 4 ГБ оставляем системе

        // Потолок 16k осознанный: приложению нужно около 8–12 тысяч токенов
        // (системный промпт, диктовки, заметки, история диалога и 4096 на ответ).
        // Больше — только лишний KV-кэш в памяти.
        switch headroom {
        case ..<2:  return 4096
        case ..<5:  return 8192
        default:    return 16384
        }
    }

    private func ping() -> Bool {
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

    // MARK: - Запрос

    func complete(messages: [AIMessage], maxTokens: Int, completion: @escaping (Result<String, AIError>) -> Void) {
        guard isAvailable else { completion(.failure(.providerUnavailable)); return }
        ensureRunning { [weak self] ok in
            guard let self, ok, self.port != 0,
                  let url = URL(string: "http://127.0.0.1:\(self.port)/v1/chat/completions") else {
                completion(.failure(.providerUnavailable))
                return
            }

            let body = Self.requestBody(messages: messages, maxTokens: maxTokens)

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            // 30 секунд хватало примерно на 700 токенов — всё длиннее обрывалось.
            req.timeoutInterval = 300

            URLSession.shared.dataTask(with: req) { data, response, error in
                if let error {
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
            }.resume()
        }
    }

    private static func requestBody(messages: [AIMessage], maxTokens: Int) -> [String: Any] {
        [
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "max_tokens": maxTokens,
            "temperature": 0.3,
            // Некоторые модели (Qwen3.5 и т.п.) по умолчанию «думают» перед ответом и уходят
            // в reasoning_content, оставляя content пустым — весь лимит токенов сгорает
            // на рассуждения. Явно отключаем thinking-режим, если модель его поддерживает;
            // модели без такого шаблона это поле просто игнорируют.
            "chat_template_kwargs": ["enable_thinking": false]
        ]
    }

    // MARK: - Потоковая генерация

    /// Ответ приходит по кусочкам, как их выдаёт модель.
    ///
    /// Это не косметика: на 9B скорость около 24 токенов в секунду, то есть
    /// развёрнутый ответ идёт полторы минуты. Одним куском такой запрос
    /// упирался в таймаут и пропадал целиком, ничего не показав.
    func stream(messages: [AIMessage],
                maxTokens: Int,
                onDelta: @escaping (String) -> Void,
                completion: @escaping (Result<String, AIError>) -> Void) {
        guard isAvailable else { completion(.failure(.providerUnavailable)); return }

        ensureRunning { [weak self] ok in
            guard let self, ok, self.port != 0,
                  let url = URL(string: "http://127.0.0.1:\(self.port)/v1/chat/completions") else {
                completion(.failure(.providerUnavailable))
                return
            }

            var body = Self.requestBody(messages: messages, maxTokens: maxTokens)
            body["stream"] = true

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)

            let collector = SSECollector(onDelta: onDelta, completion: completion)
            let config = URLSessionConfiguration.ephemeral
            // Таймер простоя, а не общий срок: пока идут токены, он сбрасывается.
            // Запас в две минуты нужен на обработку длинного промпта до первого токена.
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 1800
            let session = URLSession(configuration: config, delegate: collector, delegateQueue: nil)
            collector.session = session
            session.dataTask(with: req).resume()
        }
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
