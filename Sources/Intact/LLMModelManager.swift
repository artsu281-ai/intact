import Foundation

struct LLMModel: Identifiable, Hashable {
    let filename: String
    let title: String
    let sizeMB: Int
    let note: String
    let repo: String
    var id: String { filename }

    var localURL: URL { LLMModelManager.directory.appendingPathComponent(filename) }
    var isInstalled: Bool { FileManager.default.fileExists(atPath: localURL.path) }

    var remoteURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(filename)")!
    }

    // Небольшой каталог: лёгкие instruct-модели в GGUF, которых достаточно
    // для причёсывания текста и коротких брифов. Имена файлов стоит сверить
    // с актуальным листингом на HuggingFace перед публикацией — репозитории
    // с квантованными сборками время от времени переименовывают файлы.
    static let catalog: [LLMModel] = [
        .init(filename: "qwen2.5-3b-instruct-q4_k_m.gguf", title: "Qwen2.5 3B Instruct",
              sizeMB: 2100, note: "Хорошо держит русский и английский, быстрый на Apple Silicon.",
              repo: "Qwen/Qwen2.5-3B-Instruct-GGUF"),
        .init(filename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf", title: "Llama 3.2 3B Instruct",
              sizeMB: 2020, note: "Компактная модель общего назначения от Meta.",
              repo: "bartowski/Llama-3.2-3B-Instruct-GGUF")
    ]
}

/// Скачивание и хранение локальных LLM-моделей — по образцу ModelManager для Whisper.
/// Без проверки обновлений по ETag: каталог маленький, обновлять его вручную не в тягость.
final class LLMModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = LLMModelManager()

    static var directory: URL {
        let dir = URL(fileURLWithPath: NSString(string: "~/Models/llm").expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Published var installed: [LLMModel] = []
    @Published var downloading: String? = nil
    @Published var progress: Double = 0
    @Published var lastError: String? = nil

    private var session: URLSession!
    private var target: LLMModel?

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        refresh()
    }

    func refresh() {
        let found = LLMModel.catalog.filter(\.isInstalled)
        DispatchQueue.main.async { self.installed = found }
    }

    func download(_ model: LLMModel) {
        guard downloading == nil else { return }
        target = model
        DispatchQueue.main.async {
            self.downloading = model.filename
            self.progress = 0
            self.lastError = nil
        }
        session.downloadTask(with: model.remoteURL).resume()
    }

    func delete(_ model: LLMModel) {
        try? FileManager.default.removeItem(at: model.localURL)
        if AppSettings.shared.aiLocalModelPath == model.localURL.path {
            AppSettings.shared.aiLocalModelPath = ""
            LocalAIProvider.shared.stop()
        }
        refresh()
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
        do {
            try? FileManager.default.removeItem(at: model.localURL)
            try FileManager.default.moveItem(at: location, to: model.localURL)
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }

        DispatchQueue.main.async {
            self.downloading = nil
            self.progress = 0
            self.refresh()
            AppSettings.shared.aiLocalModelPath = model.localURL.path
            LocalAIProvider.shared.stop()
        }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
            self.downloading = nil
        }
    }
}
