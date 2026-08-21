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
        lock.lock()
        if isRunning && modelPath == bootedWith {
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
        p.arguments = ["-m", modelPath, "--port", String(chosenPort), "--host", "127.0.0.1", "-c", "4096"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice

        do { try p.run() } catch {
            NSLog("Intact: llama-server не запустился — \(error.localizedDescription)")
            completion(false)
            return
        }

        process = p
        port = chosenPort
        bootedWith = modelPath

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

    func complete(system: String, user: String, maxTokens: Int, completion: @escaping (Result<String, AIError>) -> Void) {
        guard isAvailable else { completion(.failure(.providerUnavailable)); return }
        ensureRunning { [weak self] ok in
            guard let self, ok, self.port != 0,
                  let url = URL(string: "http://127.0.0.1:\(self.port)/v1/chat/completions") else {
                completion(.failure(.providerUnavailable))
                return
            }

            let body: [String: Any] = [
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user]
                ],
                "max_tokens": maxTokens,
                "temperature": 0.3
            ]

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 30

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
