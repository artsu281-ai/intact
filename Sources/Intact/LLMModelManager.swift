import Foundation

/// Характеристики машины, от которых зависит, потянет ли она модель.
enum Hardware {
    /// Объём оперативной памяти в гибибайтах — именно так его маркирует Apple.
    /// Десятичный счёт дал бы «17 ГБ» на машине, которая продаётся как 16 ГБ.
    /// (Размеры файлов, наоборот, считаются десятичными — как в Finder.)
    static var physicalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }
}

/// Весовая категория модели. Разница между 2B и 14B — не «чуть больше»,
/// а разные сценарии и разные требования к железу, поэтому в интерфейсе
/// они разведены по отдельным карточкам.
enum LLMTier {
    /// 2–4B: причёсывание текста и короткие брифы. Работают на любом Mac.
    case light
    /// 8–14B: аналитика, код, длинные рассуждения. Нужно 16 ГБ памяти и больше.
    case large
}

struct LLMModel: Identifiable, Hashable {
    let filename: String
    let title: String
    let sizeMB: Int
    let note: String
    let repo: String
    /// Формат квантования. Для крупных моделей это половина выбора:
    /// один и тот же 14B в Q4 и Q8 отличается вдвое по весу и заметно по качеству.
    let quant: String
    let tier: LLMTier

    var id: String { filename }

    var localURL: URL { LLMModelManager.directory.appendingPathComponent(filename) }
    var isInstalled: Bool { FileManager.default.fileExists(atPath: localURL.path) }

    var remoteURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(filename)")!
    }

    /// Оценка потребности в оперативной памяти: вес модели плюс примерно 30 %
    /// под KV-кэш контекста и служебные буферы llama-server.
    var estimatedRAMGB: Double { Double(sizeMB) / 1000.0 * 1.3 }

    /// Останется ли системе чем дышать. ~3 ГБ macOS забирает под себя,
    /// и без этого запаса машина уходит в своп вместо генерации.
    var fitsInMemory: Bool { estimatedRAMGB + 3.0 <= Hardware.physicalMemoryGB }

    static func catalog(_ tier: LLMTier) -> [LLMModel] {
        catalog.filter { $0.tier == tier }
    }

    /// Модель каталога по пути к файлу на диске.
    static func matching(path: String) -> LLMModel? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return catalog.first { $0.filename == name }
    }

    /// Как модель называется в интерфейсе: «Qwen3.5 4B · Q4_K_M».
    var displayName: String { "\(title) · \(quant)" }

    // Небольшой каталог: свежие лёгкие instruct-модели в GGUF, которых достаточно
    // для причёсывания текста и коротких брифов. Прямые ссылки на конкретные файлы
    // проверены вручную (HTTP 200) на момент добавления — официальные репозитории
    // Qwen/Google на HuggingFace отдают 401 без токена, поэтому используются открытые
    // зеркала (unsloth), актуальность стоит перепроверять время от времени.
    static let catalog: [LLMModel] = [
        // ── Лёгкие: причёсывание текста и короткие брифы ──────────────────
        .init(filename: "Qwen3.5-2B-Q4_K_M.gguf", title: "Qwen3.5 2B",
              sizeMB: 1222, note: "Самая быстрая и лёгкая. Для причёсывания текста хватает с запасом — рекомендуемый выбор по умолчанию.",
              repo: "unsloth/Qwen3.5-2B-GGUF", quant: "Q4_K_M", tier: .light),
        .init(filename: "gemma-4-E2B-it-Q4_K_M.gguf", title: "Gemma 4 E2B Instruct",
              sizeMB: 2963, note: "Альтернатива от Google: сильный мультиязык, архитектура изначально заточена под работу с голосом.",
              repo: "unsloth/gemma-4-E2B-it-GGUF", quant: "Q4_K_M", tier: .light),
        .init(filename: "Nanbeige4.2-3B-Q4_K_M.gguf", title: "Nanbeige4.2 3B",
              sizeMB: 2455, note: "Заточена под логику, извлечение задач и вызов функций — задел на будущее, если понадобится больше, чем просто причёсывание.",
              repo: "owao/Nanbeige4.2-3B-GGUF", quant: "Q4_K_M", tier: .light),
        .init(filename: "Qwen3.5-4B-Q4_K_M.gguf", title: "Qwen3.5 4B",
              sizeMB: 2614, note: "Крупнее и заметно умнее 2B на сложных смешанных фразах — но и медленнее, и тяжелее в памяти.",
              repo: "unsloth/Qwen3.5-4B-GGUF", quant: "Q4_K_M", tier: .light),
        .init(filename: "gemma-4-E4B-it-Q4_K_M.gguf", title: "Gemma 4 E4B Instruct",
              sizeMB: 4747, note: "Крупный вариант от Google с поддержкой аудио — на будущее, если одна модель должна закрыть и голос, и текст.",
              repo: "unsloth/gemma-4-E4B-it-GGUF", quant: "Q4_K_M", tier: .light),
        .init(filename: "Ministral-3-3B-Instruct-2512-Q4_K_M.gguf", title: "Ministral 3 3B",
              sizeMB: 2047, note: "Универсальная модель от Mistral — золотая середина между скоростью и качеством, если не хочется выбирать между крайностями.",
              repo: "unsloth/Ministral-3-3B-Instruct-2512-GGUF", quant: "Q4_K_M", tier: .light),

        // ── Крупные: аналитика, код, длинные рассуждения ───────────────────
        // Размеры взяты из HuggingFace API, имена файлов проверены (HTTP 200).
        // Официальные репозитории Qwen/Meta отдают 401 без токена — как и для
        // лёгких моделей, используются открытые зеркала unsloth и bartowski.
        .init(filename: "Qwen3-14B-Q5_K_M.gguf", title: "Qwen3 14B",
              sizeMB: 10515, note: "Топ-универсал: сложная аналитика, живой русский язык, ролевые диалоги. При 16 ГБ памяти остаётся запас примерно на 32k токенов контекста.",
              repo: "unsloth/Qwen3-14B-GGUF", quant: "Q5_K_M", tier: .large),
        .init(filename: "Qwen2.5-Coder-14B-Instruct-Q5_K_M.gguf", title: "Qwen2.5 Coder 14B",
              sizeMB: 10509, note: "Лучшая в каталоге для кода: рефакторинг, поиск багов, генерация скриптов на любых языках.",
              repo: "unsloth/Qwen2.5-Coder-14B-Instruct-GGUF", quant: "Q5_K_M", tier: .large),
        .init(filename: "Qwen3.5-9B-Q8_0.gguf", title: "Qwen3.5 9B",
              sizeMB: 9528, note: "Максимальная скорость без потерь от сжатия: Q8_0 почти неотличим от оригинала, а контекст тянет до 64k токенов и больше.",
              repo: "unsloth/Qwen3.5-9B-GGUF", quant: "Q8_0", tier: .large),
        .init(filename: "DeepSeek-R1-Distill-Qwen-14B-Q4_K_M.gguf", title: "DeepSeek-R1 Distill 14B",
              sizeMB: 8988, note: "Сложная логика и алгоритмы: расписывает ход рассуждения по шагам и меньше выдумывает. Лёгкое квантование оставляет память под длинные размышления.",
              repo: "unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF", quant: "Q4_K_M", tier: .large),
        .init(filename: "phi-4-Q4_K_M.gguf", title: "Phi-4 14B",
              sizeMB: 8890, note: "Точные науки и математика, выжимка плотных технических текстов.",
              repo: "unsloth/phi-4-GGUF", quant: "Q4_K_M", tier: .large),
        .init(filename: "gemma-3-12b-it-Q4_K_M.gguf", title: "Gemma 3 12B Instruct",
              sizeMB: 7301, note: "Мультимодальность и быстрая генерация, устойчива к очень длинным промптам. Самая нетребовательная в этой группе.",
              repo: "unsloth/gemma-3-12b-it-GGUF", quant: "Q4_K_M", tier: .large)
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
