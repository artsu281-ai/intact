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
final class ModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
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
    @Published var lastError: String? = nil

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

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
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
        DispatchQueue.main.async {
            self.downloading = model.filename
            self.isUpdating = isUpdate
            self.progress = 0
            self.lastError = nil
        }
        session.downloadTask(with: model.remoteURL).resume()
    }

    func delete(_ model: WhisperModel) {
        try? FileManager.default.removeItem(at: model.localURL)
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

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite total: Int64) {
        guard total > 0 else { return }
        let p = Double(totalBytesWritten) / Double(total)
        DispatchQueue.main.async { self.progress = p }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let model = target else { return }
        let isUpdate = isCurrentDownloadUpdate

        // Сохраняем ETag из ответа
        if let http = downloadTask.response as? HTTPURLResponse {
            let etag = (http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "etag") ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !etag.isEmpty {
                UserDefaults.standard.set(etag, forKey: "etag_\(model.filename)")
            }
        }

        do {
            try? FileManager.default.removeItem(at: model.localURL)
            try FileManager.default.moveItem(at: location, to: model.localURL)
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }

        DispatchQueue.main.async {
            self.downloading = nil
            self.isUpdating = false
            self.progress = 0
            self.updatesAvailable.remove(model.filename)
            self.refresh()

            let currentExists = FileManager.default.fileExists(atPath: AppSettings.shared.modelPath)
            if !currentExists || isUpdate || AppSettings.shared.modelPath == model.localURL.path || self.installed.count <= 1 {
                AppSettings.shared.modelPath = model.localURL.path
                DictationController.shared.restartEngine()
            }
        }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
            self.downloading = nil
            self.isUpdating = false
        }
    }
}
