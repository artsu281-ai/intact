import Foundation

struct WhisperModel: Identifiable, Hashable {
    let filename: String
    let title: String
    let sizeMB: Int
    let note: String
    var id: String { filename }

    var localURL: URL { ModelManager.directory.appendingPathComponent(filename) }
    var isInstalled: Bool { FileManager.default.fileExists(atPath: localURL.path) }

    /// Каталог моделей ggml для whisper.cpp на HuggingFace.
    var remoteURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }

    static let catalog: [WhisperModel] = [
        .init(filename: "ggml-large-v3.bin", title: "large-v3",
              sizeMB: 2950, note: "Максимальное качество. Лучший выбор для смешанной ru/en речи."),
        .init(filename: "ggml-large-v3-turbo.bin", title: "large-v3-turbo",
              sizeMB: 1560, note: "В 3–4 раза быстрее, отличное качество для повседневной речи."),
        .init(filename: "ggml-medium.bin", title: "medium",
              sizeMB: 1530, note: "Компромисс прошлого поколения. Уступает turbo."),
        .init(filename: "ggml-small.bin", title: "small",
              sizeMB: 488, note: "Быстро и нетребовательно, возможны ошибки в сложных терминах."),
        .init(filename: "ggml-base.bin", title: "base",
              sizeMB: 148, note: "Базовая легковесная модель для слабых систем."),
        .init(filename: "ggml-tiny.bin", title: "tiny",
              sizeMB: 75, note: "Сверхлегкая модель для быстрой проверки.")
    ]
}

/// Скачивание, проверка и обновление моделей Whisper с HuggingFace.
///
/// Качает с докачкой, как и каталог LLM: Три гигабайта large-v3 по
/// домашнему каналу — это те же десятки минут и тот же риск моргнувшей сети.
final class ModelManager: NSObject, ObservableObject, URLSessionDataDelegate {
    static let shared = ModelManager()

    static var directory: URL {
        let dir = URL(fileURLWithPath: NSString(string: "~/Models/whisper").expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Published var installed: [WhisperModel] = []
    @Published var downloading: String? = nil
    @Published var isUpdating: Bool = false
    @Published var progress: Double = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var resumed = false
    @Published var lastError: String? = nil

    /// Сколько уже лежит в недокачанном файле.
    func partialBytes(_ model: WhisperModel) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.partURL(for: model).path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func partURL(for model: WhisperModel) -> URL {
        directory.appendingPathComponent(model.filename + ".part")
    }

    /// Есть ли хотя бы одна скачанная модель для работы
    var hasAnyModelInstalled: Bool {
        !installed.isEmpty || FileManager.default.fileExists(atPath: AppSettings.shared.modelPath)
    }

    /// Рекомендуемая модель по умолчанию для новых пользователей
    var recommendedModel: WhisperModel {
        WhisperModel.catalog.first(where: { $0.filename == "ggml-large-v3-turbo.bin" }) ?? WhisperModel.catalog[0]
    }

    /// Базовая легковесная модель для мгновенного старта
    var baseModel: WhisperModel {
        WhisperModel.catalog.first(where: { $0.filename == "ggml-base.bin" }) ?? WhisperModel.catalog[4]
    }

    /// Список моделей, для которых обнаружены обновления
    @Published var updatesAvailable: Set<String> = []
    @Published var isCheckingUpdates: Bool = false
    @Published var lastCheckTime: Date? = nil
    @Published var statusMessage: String? = nil

    private var session: URLSession!
    private var target: WhisperModel?
    private var isCurrentDownloadUpdate = false
    private var handle: FileHandle?
    private var receivedBytes: Int64 = 0
    private var expectedTotal: Int64 = 0
    private var currentTask: URLSessionDataTask?
    /// ETag ответа сохраняем при завершении, чтобы проверка обновлений
    /// сравнивала с тем, что реально лежит на диске.
    private var pendingETag: String = ""

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        refresh()
    }

    func refresh() {
        let found = WhisperModel.catalog.filter(\.isInstalled)
        DispatchQueue.main.async {
            self.installed = found
            // Если текущая модель в настройках не существует, но есть другие скачанные — переключаем на первую доступную
            let currentExists = FileManager.default.fileExists(atPath: AppSettings.shared.modelPath)
            if !currentExists, let first = found.first {
                AppSettings.shared.modelPath = first.localURL.path
                DictationController.shared.restartEngine()
            }
        }
    }

    func hasUpdate(_ model: WhisperModel) -> Bool {
        updatesAvailable.contains(model.filename)
    }

    /// Все .bin в каталоге моделей — включая те, что положили руками.
    func allLocalFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: Self.directory,
                                                      includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "bin" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    func download(_ model: WhisperModel, isUpdate: Bool = false) {
        guard downloading == nil else { return }
        target = model
        isCurrentDownloadUpdate = isUpdate

        // Обновление начинаем с нуля: файл на сервере изменился, и дописывать
        // новые байты к старому хвосту — верный способ получить битую модель.
        let partURL = Self.partURL(for: model)
        if isUpdate { try? FileManager.default.removeItem(at: partURL) }

        let already = isUpdate ? 0 : partialBytes(model)
        receivedBytes = already
        expectedTotal = Int64(model.sizeMB) * 1_000_000

        var request = URLRequest(url: model.remoteURL)
        if already > 0 { request.setValue("bytes=\(already)-", forHTTPHeaderField: "Range") }

        DispatchQueue.main.async {
            self.downloading = model.filename
            self.isUpdating = isUpdate
            self.progress = self.expectedTotal > 0 ? Double(already) / Double(self.expectedTotal) : 0
            self.downloadedBytes = already
            self.totalBytes = self.expectedTotal
            self.resumed = already > 0
            self.lastError = nil
        }

        if !FileManager.default.fileExists(atPath: partURL.path) {
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: partURL)
        _ = try? handle?.seekToEnd()

        currentTask = session.dataTask(with: request)
        currentTask?.resume()
    }

    /// Пауза без потери скачанного.
    func pauseDownload() {
        currentTask?.cancel()
        currentTask = nil
        try? handle?.close()
        handle = nil
        DispatchQueue.main.async {
            self.downloading = nil
            self.isUpdating = false
            self.progress = 0
        }
    }

    func discardPartial(_ model: WhisperModel) {
        try? FileManager.default.removeItem(at: Self.partURL(for: model))
        objectWillChange.send()
    }

    func delete(_ model: WhisperModel) {
        try? FileManager.default.removeItem(at: model.localURL)
        try? FileManager.default.removeItem(at: Self.partURL(for: model))
        UserDefaults.standard.removeObject(forKey: "etag_\(model.filename)")
        updatesAvailable.remove(model.filename)
        refresh()
    }

    // MARK: - Проверка обновлений

    /// Проверяет наличие обновлений на Hugging Face для всех установленных моделей.
    func checkForUpdates() {
        guard !isCheckingUpdates else { return }
        let toCheck = WhisperModel.catalog.filter(\.isInstalled)
        guard !toCheck.isEmpty else {
            DispatchQueue.main.async {
                self.statusMessage = "Нет установленных моделей для проверки"
                self.lastCheckTime = Date()
            }
            return
        }

        DispatchQueue.main.async {
            self.isCheckingUpdates = true
            self.lastError = nil
            self.statusMessage = "Проверка обновлений…"
        }

        let group = DispatchGroup()
        var newUpdates = Set<String>()

        for model in toCheck {
            group.enter()
            var request = URLRequest(url: model.remoteURL)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 15

            let task = URLSession.shared.dataTask(with: request) { _, response, error in
                defer { group.leave() }
                guard let http = response as? HTTPURLResponse, error == nil else { return }

                let remoteETag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "etag") ?? ""
                let cleanRemoteETag = remoteETag.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let storedETag = UserDefaults.standard.string(forKey: "etag_\(model.filename)")

                if let storedETag, !storedETag.isEmpty, !cleanRemoteETag.isEmpty {
                    if storedETag != cleanRemoteETag {
                        newUpdates.insert(model.filename)
                    }
                } else if !cleanRemoteETag.isEmpty {
                    // Если ETag ещё не был сохранён, сохраняем текущий как базовый
                    UserDefaults.standard.set(cleanRemoteETag, forKey: "etag_\(model.filename)")
                }
            }
            task.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isCheckingUpdates = false
            self.lastCheckTime = Date()
            self.updatesAvailable = newUpdates

            if newUpdates.isEmpty {
                self.statusMessage = "Все модели актуальны"
            } else {
                self.statusMessage = "Доступно обновление для \(newUpdates.count) мод."
            }
        }
    }

    // MARK: - URLSession Delegate

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }

        pendingETag = (http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "etag") ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        switch http.statusCode {
        case 206:
            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let totalPart = range.split(separator: "/").last,
               let total = Int64(totalPart) {
                expectedTotal = total
            }
        case 200:
            // Диапазон не поддержан или файл изменился — начинаем заново.
            if receivedBytes > 0, let model = target {
                try? handle?.close()
                let partURL = Self.partURL(for: model)
                try? FileManager.default.removeItem(at: partURL)
                FileManager.default.createFile(atPath: partURL.path, contents: nil)
                handle = try? FileHandle(forWritingTo: partURL)
                receivedBytes = 0
            }
            if http.expectedContentLength > 0 { expectedTotal = http.expectedContentLength }
        default:
            fail("Сервер ответил \(http.statusCode). Попробуйте позже.")
            completionHandler(.cancel)
            return
        }

        let total = expectedTotal
        let received = receivedBytes
        DispatchQueue.main.async {
            self.totalBytes = total
            self.downloadedBytes = received
            self.resumed = received > 0
        }
        completionHandler(.allow)
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handle?.write(data)
        receivedBytes += Int64(data.count)
        let received = receivedBytes
        let total = expectedTotal
        guard total > 0 else { return }
        let p = min(1, Double(received) / Double(total))
        DispatchQueue.main.async {
            self.progress = p
            self.downloadedBytes = received
        }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        currentTask = nil

        if let error {
            // Отмена — это пауза: `.part` остаётся, следующий запуск продолжит.
            if (error as NSError).code == NSURLErrorCancelled { return }
            fail(error.localizedDescription)
            return
        }
        guard let model = target else { return }
        let isUpdate = isCurrentDownloadUpdate
        let partURL = Self.partURL(for: model)

        let onDisk = (try? FileManager.default.attributesOfItem(atPath: partURL.path))
            .flatMap { ($0[.size] as? NSNumber)?.int64Value } ?? 0

        // Оборванная загрузка внешне неотличима от полной, а whisper-server
        // на обрезанном файле падает уже потом, при первой же диктовке.
        if expectedTotal > 0, onDisk < expectedTotal {
            fail("Файл докачан не полностью (\(onDisk / 1_000_000) из \(expectedTotal / 1_000_000) МБ). Нажмите «Продолжить».")
            return
        }

        if !pendingETag.isEmpty {
            UserDefaults.standard.set(pendingETag, forKey: "etag_\(model.filename)")
        }

        do {
            try? FileManager.default.removeItem(at: model.localURL)
            try FileManager.default.moveItem(at: partURL, to: model.localURL)
        } catch {
            fail(error.localizedDescription)
            return
        }

        DispatchQueue.main.async {
            self.downloading = nil
            self.isUpdating = false
            self.progress = 0
            self.downloadedBytes = 0
            self.totalBytes = 0
            self.resumed = false
            self.updatesAvailable.remove(model.filename)
            self.refresh()

            let currentExists = FileManager.default.fileExists(atPath: AppSettings.shared.modelPath)
            if !currentExists || isUpdate || AppSettings.shared.modelPath == model.localURL.path || self.installed.count <= 1 {
                AppSettings.shared.modelPath = model.localURL.path
                DictationController.shared.restartEngine()
            }
        }
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async {
            self.lastError = message
            self.downloading = nil
            self.isUpdating = false
            self.progress = 0
        }
    }
}
