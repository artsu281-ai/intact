import Foundation

/// Экспериментальный режим «всё-в-одном»: Gemma 4 E2B умеет нативно понимать аудио
/// и сразу отдавать причёсанный текст, без отдельного Whisper. НЕ используется в основном
/// пайплайне диктовки — Whisper остаётся точным специализированным ASR по умолчанию.
/// Это отдельная песочница для сравнения, доступная только из вкладки настроек ИИ.
struct GemmaAudioModel {
    let title: String
    let mainFilename: String
    let mmprojFilename: String
    let repo: String
    let mainSizeMB: Int
    let mmprojSizeMB: Int

    var mainURL: URL { GemmaAudioModelManager.directory.appendingPathComponent(mainFilename) }
    var mmprojURL: URL { GemmaAudioModelManager.directory.appendingPathComponent(mmprojFilename) }
    var mainRemoteURL: URL { URL(string: "https://huggingface.co/\(repo)/resolve/main/\(mainFilename)")! }
    var mmprojRemoteURL: URL { URL(string: "https://huggingface.co/\(repo)/resolve/main/\(mmprojFilename)")! }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: mainURL.path) && FileManager.default.fileExists(atPath: mmprojURL.path)
    }

    // Проверено вручную (HTTP 200) на момент добавления. Официальный репозиторий ggml-org
    // не публикует Q4_K_M для этой модели — берём Q4_0 (основная) + Q8_0 (mmproj-проектор,
    // его почти не квантуют мельче, он и так небольшой).
    static let gemma4E2B = GemmaAudioModel(
        title: "Gemma 4 E2B (аудио)",
        mainFilename: "gemma-4-E2B-it-Q4_0.gguf",
        mmprojFilename: "mmproj-gemma-4-E2B-it-Q8_0.gguf",
        repo: "ggml-org/gemma-4-E2B-it-GGUF",
        mainSizeMB: 2710, mmprojSizeMB: 532)
}

/// Скачивает пару файлов (модель + mmproj) последовательно, с общим прогрессом на оба.
final class GemmaAudioModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = GemmaAudioModelManager()
    let model = GemmaAudioModel.gemma4E2B

    static var directory: URL {
        let dir = URL(fileURLWithPath: NSString(string: "~/Models/llm-audio").expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Published var isInstalled = false
    @Published var downloading = false
    @Published var progress: Double = 0
    @Published var lastError: String?

    private var session: URLSession!
    private var mmprojStage = false

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        isInstalled = model.isInstalled
    }

    func download() {
        guard !downloading else { return }
        downloading = true
        progress = 0
        lastError = nil
        mmprojStage = false
        session.downloadTask(with: model.mainRemoteURL).resume()
    }

    func delete() {
        try? FileManager.default.removeItem(at: model.mainURL)
        try? FileManager.default.removeItem(at: model.mmprojURL)
        isInstalled = false
        GemmaAudioProvider.shared.stop()
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite total: Int64) {
        guard total > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(total)
        DispatchQueue.main.async { self.progress = (self.mmprojStage ? 0.5 : 0) + fraction * 0.5 }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let target = mmprojStage ? model.mmprojURL : model.mainURL
        do {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: location, to: target)
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription; self.downloading = false }
            return
        }

        if !mmprojStage {
            mmprojStage = true
            session.downloadTask(with: model.mmprojRemoteURL).resume()
        } else {
            DispatchQueue.main.async {
                self.downloading = false
                self.progress = 0
                self.isInstalled = self.model.isInstalled
            }
        }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
            self.downloading = false
        }
    }
}

/// Отдельный llama-server с загруженным mmproj — на своём порту, независимо от
/// LocalAIProvider (текстовой модели для причёсывания), чтобы оба могли жить рядом
/// и не мешать друг другу процессами с одинаковым именем.
final class GemmaAudioProvider {
    static let shared = GemmaAudioProvider()

    private var process: Process?
    private(set) var port: Int = 0

    private var binary: String? {
        ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isRunning: Bool { process?.isRunning == true && port != 0 }
    var isReady: Bool { binary != nil && GemmaAudioModelManager.shared.model.isInstalled }

    private init() {}

    func ensureRunning(completion: @escaping (Bool) -> Void) {
        if isRunning { completion(true); return }

        let model = GemmaAudioModelManager.shared.model
        guard let bin = binary, model.isInstalled else {
            completion(false)
            return
        }

        let chosenPort = Self.freePort()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["-m", model.mainURL.path, "--mmproj", model.mmprojURL.path,
                       "--port", String(chosenPort), "--host", "127.0.0.1", "-c", "4096"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice

        do { try p.run() } catch {
            NSLog("Intact: gemma audio server не запустился — \(error.localizedDescription)")
            completion(false)
            return
        }

        process = p
        port = chosenPort

        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(90)
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

    // MARK: - Запрос: аудио прямо в модель, без Whisper

    static let systemPrompt = """
    Расшифруй голосовую запись на русском или кыргызском (возможна смесь языков) и сразу \
    верни причёсанный текст: убери слова-паразиты, поправь пунктуацию и порядок слов, \
    сохрани исходный смысл и язык. Верни только готовый текст, без пояснений и кавычек.
    """

    func transcribeAndRefine(wav: URL, completion: @escaping (Result<String, AIError>) -> Void) {
        guard isReady else { completion(.failure(.providerUnavailable)); return }
        ensureRunning { [weak self] ok in
            guard let self, ok, self.port != 0,
                  let url = URL(string: "http://127.0.0.1:\(self.port)/v1/chat/completions"),
                  let audioData = try? Data(contentsOf: wav) else {
                completion(.failure(.providerUnavailable))
                return
            }

            let base64 = audioData.base64EncodedString()
            let body: [String: Any] = [
                "messages": [
                    ["role": "system", "content": Self.systemPrompt],
                    ["role": "user", "content": [
                        ["type": "input_audio", "input_audio": ["data": base64, "format": "wav"]]
                    ]]
                ],
                "max_tokens": 600,
                "temperature": 0.3
            ]

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 60

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
        guard bound == 0 else { return 8479 }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) {
            _ = $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &len)
            }
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}
