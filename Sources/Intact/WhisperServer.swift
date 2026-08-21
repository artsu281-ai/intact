import Foundation

/// Держит whisper-server живым с загруженной моделью.
/// Загрузка модели стоит ~0.7 с, и платить её на каждую диктовку нельзя —
/// поэтому процесс поднимается один раз и живёт, пока не сменятся модель или язык.
final class WhisperServer {
    static let shared = WhisperServer()

    private var process: Process?
    private(set) var port: Int = 0
    private var bootedWith: String = ""
    private let lock = NSLock()

    private var binary: String? {
        ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isAvailable: Bool { binary != nil }
    var isRunning: Bool { process?.isRunning == true && port != 0 }

    private init() {}

    /// Ключ конфигурации: если он не изменился, сервер перезапускать не нужно.
    private func configKey(_ s: AppSettings) -> String {
        "\(s.modelPath)|\(s.language)|\(s.threads)|\(s.translateToEnglish)|\(s.suppressNonSpeech)|\(s.draftAudioContext)"
    }

    /// Поднимает сервер, если он ещё не поднят или изменилась конфигурация.
    func ensureRunning(settings s: AppSettings, completion: ((Bool) -> Void)? = nil) {
        lock.lock()
        let key = configKey(s)
        if isRunning && key == bootedWith {
            lock.unlock()
            completion?(true)
            return
        }
        lock.unlock()

        stop()
        guard let bin = binary, FileManager.default.fileExists(atPath: s.modelPath) else {
            completion?(false)
            return
        }

        let chosenPort = Self.freePort()
        var args = [
            "-m", s.modelPath,
            "--port", String(chosenPort),
            "--host", "127.0.0.1",
            "-t", String(s.threads),
            "-l", s.language,
            "-nt"
        ]
        if s.suppressNonSpeech { args.append("-sns") }
        if s.translateToEnglish { args.append("-tr") }
        if s.draftAudioContext > 0 { args += ["-ac", String(s.draftAudioContext)] }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice

        do { try p.run() } catch {
            NSLog("Intact: whisper-server не запустился — \(error.localizedDescription)")
            completion?(false)
            return
        }

        process = p
        port = chosenPort
        bootedWith = key

        // Ждём, пока модель поднимется в память.
        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(90)
            while Date() < deadline {
                if !p.isRunning { break }
                if self.ping() { completion?(true); return }
                Thread.sleep(forTimeInterval: 0.25)
            }
            completion?(false)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        port = 0
        bootedWith = ""
    }

    private func ping() -> Bool {
        guard port != 0, let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
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

    // MARK: - Распознавание

    /// Отправляет WAV на тёплый сервер. Синхронно, вызывать с фонового потока.
    func transcribe(wav: URL, settings s: AppSettings) throws -> String {
        guard isRunning, let url = URL(string: "http://127.0.0.1:\(port)/inference") else {
            throw TranscribeError.binaryMissing
        }
        let boundary = "----voiceinput-\(UUID().uuidString)"
        var body = Data()

        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        let audio = try Data(contentsOf: wav)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)

        field("response_format", "text")
        field("language", s.language)
        let prompt = s.initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty { field("prompt", prompt) }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 60

        var result = ""
        var failure: Error?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error { failure = error }
            else if let data { result = String(data: data, encoding: .utf8) ?? "" }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 60)

        if let failure { throw failure }
        return Transcriber.clean(result)
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
        guard bound == 0 else { return 8477 }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) {
            _ = $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &len)
            }
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}
