import Foundation

/// Характеристики машины, от которых зависит, потянет ли она модель.
enum Hardware {
    /// Объём оперативной памяти в гибибайтах — именно так его маркирует Apple.
    /// Десятичный счёт дал бы «17 ГБ» на машине, которая продаётся как 16 ГБ.
    /// (Размеры файлов, наоборот, считаются десятичными — как в Finder.)
    static var physicalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    /// Сколько гигабайтов оставляем macOS и остальным приложениям.
    /// Одно число на весь проект: и прогноз в каталоге, и решение выгрузить
    /// сервер в LocalAIProvider должны считать одинаково, иначе интерфейс
    /// обещает «влезет», а модель на старте выталкивает соседа.
    static let systemReserveGB: Double = 4
}

/// Весовая категория модели. Разница между 2B и 14B — не «чуть больше»,
/// а разные сценарии и разные требования к железу, поэтому в интерфейсе
/// они разведены по отдельным карточкам.
enum LLMTier: CaseIterable {
    /// 2–4B: причёсывание текста и короткие брифы. Работают на любом Mac.
    case light
    /// 8–14B: аналитика, код, длинные рассуждения. Нужно 16 ГБ памяти и больше.
    case large
    /// 24–35B: настольный предел. Здесь локальная модель впервые начинает
    /// спорить с облаком по качеству разбора — ценой 16–25 ГБ памяти.
    case xlarge

    /// Сколько всего памяти нужно машине, чтобы ярус имел смысл.
    var recommendedRAMGB: Double {
        switch self {
        case .light:  return 8
        case .large:  return 16
        case .xlarge: return 32
        }
    }
}

/// Умеет ли модель рассуждать перед ответом.
///
/// Это не украшение: у DeepSeek-R1 рассуждение — единственное, ради чего
/// её берут, а раньше приложение выключало его всем подряд одной строкой
/// в теле запроса, и модель отвечала вполсилы.
enum LLMThinking {
    /// Не умеет — поле в запросе просто игнорируется.
    case none
    /// Понимает `enable_thinking` в шаблоне: можно включить и выключить.
    case toggleable
    /// Рассуждает всегда, отключить нельзя (дистилляты R1).
    case always
}

/// Один конкретный файл конкретного кванта — то, что реально скачивается.
struct LLMQuantOption: Identifiable, Hashable {
    let quant: String
    let filename: String
    let sizeMB: Int
    var id: String { filename }
}

/// Семейство: одна модель, несколько вариантов квантования одного и того же файла.
/// Разница между Q3_K_M и Q8_0 — это не другая модель, а компромисс размер/качество,
/// поэтому выбор кванта — часть интерфейса модели, а не отдельная строка каталога.
struct LLMModel: Identifiable, Hashable {
    let title: String
    let note: String
    let repo: String
    let tier: LLMTier
    var thinking: LLMThinking = .none
    /// От меньшего к большему — так их и показываем в выпадающем списке.
    let quantOptions: [LLMQuantOption]

    /// Стоит ли ждать эту модель дольше обычного.
    var reasons: Bool { thinking != .none }

    var id: String { title }

    /// Что предложить, если пользователь ещё ничего не выбирал.
    ///
    /// Q4_K_M — общепринятый компромисс, но на крупных моделях он может
    /// не влезть в память конкретной машины. Предлагать заведомо своп —
    /// худший вариант умолчания, поэтому сначала ищем самый качественный
    /// из тех, что помещаются, и только потом откатываемся к Q4.
    var defaultQuant: LLMQuantOption {
        let preferred = quantOptions.first { $0.quant == "Q4_K_M" }
            ?? quantOptions.first { $0.quant == "UD-Q4_K_M" }
        if let preferred, fitsInMemory(preferred) { return preferred }
        if let biggestThatFits = quantOptions.last(where: { fitsInMemory($0) }) { return biggestThatFits }
        return preferred ?? quantOptions[quantOptions.count / 2]
    }

    /// Уже скачанный вариант, если такой есть — чтобы при повторном открытии
    /// хаба выпадающий список сразу показывал то, что реально лежит на диске.
    var installedQuant: LLMQuantOption? {
        quantOptions.first(where: { isInstalled($0) })
    }

    func localURL(for quant: LLMQuantOption) -> URL {
        LLMModelManager.directory.appendingPathComponent(quant.filename)
    }

    func isInstalled(_ quant: LLMQuantOption) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: quant).path)
    }

    func remoteURL(for quant: LLMQuantOption) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(quant.filename)")!
    }

    /// Оценка потребности в оперативной памяти: вес модели плюс примерно 30 %
    /// под KV-кэш контекста и служебные буферы llama-server.
    func estimatedRAMGB(for quant: LLMQuantOption) -> Double { Double(quant.sizeMB) / 1000.0 * 1.3 }

    /// Останется ли системе чем дышать. Без запаса под macOS машина уходит
    /// в своп вместо генерации.
    func fitsInMemory(_ quant: LLMQuantOption) -> Bool {
        estimatedRAMGB(for: quant) + Hardware.systemReserveGB <= Hardware.physicalMemoryGB
    }

    static func catalog(_ tier: LLMTier) -> [LLMModel] {
        catalog.filter { $0.tier == tier }
    }

    /// Модель и конкретный квант каталога по пути к файлу на диске.
    static func matching(path: String) -> (model: LLMModel, quant: LLMQuantOption)? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        for model in catalog {
            if let quant = model.quantOptions.first(where: { $0.filename == name }) {
                return (model, quant)
            }
        }
        return nil
    }

    /// Как модель называется в интерфейсе: «Qwen3.5 4B · Q4_K_M».
    static func displayName(model: LLMModel, quant: LLMQuantOption) -> String {
        "\(model.title) · \(quant.quant)"
    }

    // Небольшой каталог: свежие instruct-модели в GGUF. У каждой — пять уровней
    // квантования (Q3_K_M/Q4_K_M/Q5_K_M/Q6_K/Q8_0), имена файлов и размеры сверены
    // напрямую с HuggingFace API (HTTP 200 + Content-Length на момент добавления).
    // Официальные репозитории Qwen/Google/Meta отдают 401 без токена, поэтому
    // используются открытые зеркала (unsloth, owao) — актуальность стоит
    // перепроверять время от времени.
    static let catalog: [LLMModel] = [
        // ── Лёгкие: причёсывание текста и короткие брифы ──────────────────
        .init(title: "Qwen3.5 2B",
              note: T("Самая быстрая и лёгкая. Для причёсывания текста хватает с запасом — рекомендуемый выбор по умолчанию.", "The fastest and lightest. More than enough for text cleanup — the recommended default."),
              repo: "unsloth/Qwen3.5-2B-GGUF", tier: .light, thinking: .toggleable, quantOptions: [
                .init(quant: "Q3_K_M", filename: "Qwen3.5-2B-Q3_K_M.gguf", sizeMB: 1107),
                .init(quant: "Q4_K_M", filename: "Qwen3.5-2B-Q4_K_M.gguf", sizeMB: 1281),
                .init(quant: "Q5_K_M", filename: "Qwen3.5-2B-Q5_K_M.gguf", sizeMB: 1435),
                .init(quant: "Q6_K",   filename: "Qwen3.5-2B-Q6_K.gguf",   sizeMB: 1575),
                .init(quant: "Q8_0",   filename: "Qwen3.5-2B-Q8_0.gguf",   sizeMB: 2012)
              ]),
        .init(title: "Gemma 4 E2B Instruct",
              note: T("Альтернатива от Google: сильный мультиязык, архитектура изначально заточена под работу с голосом.", "Google's alternative: strong multilingual support, an architecture built for voice from the start."),
              repo: "unsloth/gemma-4-E2B-it-GGUF", tier: .light, quantOptions: [
                .init(quant: "Q3_K_M", filename: "gemma-4-E2B-it-Q3_K_M.gguf", sizeMB: 2537),
                .init(quant: "Q4_K_M", filename: "gemma-4-E2B-it-Q4_K_M.gguf", sizeMB: 3107),
                .init(quant: "Q5_K_M", filename: "gemma-4-E2B-it-Q5_K_M.gguf", sizeMB: 3356),
                .init(quant: "Q6_K",   filename: "gemma-4-E2B-it-Q6_K.gguf",   sizeMB: 4502),
                .init(quant: "Q8_0",   filename: "gemma-4-E2B-it-Q8_0.gguf",   sizeMB: 5048)
              ]),
        .init(title: "Nanbeige4.2 3B",
              note: T("Заточена под логику, извлечение задач и вызов функций — задел на будущее, если понадобится больше, чем просто причёсывание.", "Built for logic, task extraction and function calling — groundwork for when cleanup alone is no longer enough."),
              repo: "owao/Nanbeige4.2-3B-GGUF", tier: .light, quantOptions: [
                .init(quant: "Q3_K_M", filename: "Nanbeige4.2-3B-Q3_K_M.gguf", sizeMB: 2165),
                .init(quant: "Q4_K_M", filename: "Nanbeige4.2-3B-Q4_K_M.gguf", sizeMB: 2575),
                .init(quant: "Q5_K_M", filename: "Nanbeige4.2-3B-Q5_K_M.gguf", sizeMB: 2987),
                .init(quant: "Q6_K",   filename: "Nanbeige4.2-3B-Q6_K.gguf",   sizeMB: 3425),
                .init(quant: "Q8_0",   filename: "Nanbeige4.2-3B-Q8_0.gguf",   sizeMB: 4435)
              ]),
        .init(title: "Qwen3.5 4B",
              note: T("Крупнее и заметно умнее 2B на сложных смешанных фразах — но и медленнее, и тяжелее в памяти.", "Larger and noticeably smarter than 2B on complex mixed phrases — but slower and heavier in memory."),
              repo: "unsloth/Qwen3.5-4B-GGUF", tier: .light, thinking: .toggleable, quantOptions: [
                .init(quant: "Q3_K_M", filename: "Qwen3.5-4B-Q3_K_M.gguf", sizeMB: 2293),
                .init(quant: "Q4_K_M", filename: "Qwen3.5-4B-Q4_K_M.gguf", sizeMB: 2741),
                .init(quant: "Q5_K_M", filename: "Qwen3.5-4B-Q5_K_M.gguf", sizeMB: 3144),
                .init(quant: "Q6_K",   filename: "Qwen3.5-4B-Q6_K.gguf",   sizeMB: 3526),
                .init(quant: "Q8_0",   filename: "Qwen3.5-4B-Q8_0.gguf",   sizeMB: 4482)
              ]),
        .init(title: "Gemma 4 E4B Instruct",
              note: T("Крупный вариант от Google с поддержкой аудио — на будущее, если одна модель должна закрыть и голос, и текст.", "Google's larger variant with audio support — for when a single model should cover both voice and text."),
              repo: "unsloth/gemma-4-E4B-it-GGUF", tier: .light, quantOptions: [
                .init(quant: "Q3_K_M", filename: "gemma-4-E4B-it-Q3_K_M.gguf", sizeMB: 4058),
                .init(quant: "Q4_K_M", filename: "gemma-4-E4B-it-Q4_K_M.gguf", sizeMB: 4977),
                .init(quant: "Q5_K_M", filename: "gemma-4-E4B-it-Q5_K_M.gguf", sizeMB: 5482),
                .init(quant: "Q6_K",   filename: "gemma-4-E4B-it-Q6_K.gguf",   sizeMB: 7075),
                .init(quant: "Q8_0",   filename: "gemma-4-E4B-it-Q8_0.gguf",   sizeMB: 8193)
              ]),
        .init(title: "Ministral 3 3B",
              note: T("Универсальная модель от Mistral — золотая середина между скоростью и качеством, если не хочется выбирать между крайностями.", "Mistral's all-rounder — the middle ground between speed and quality, when you would rather not choose an extreme."),
              repo: "unsloth/Ministral-3-3B-Instruct-2512-GGUF", tier: .light, quantOptions: [
                .init(quant: "Q3_K_M", filename: "Ministral-3-3B-Instruct-2512-Q3_K_M.gguf", sizeMB: 1796),
                .init(quant: "Q4_K_M", filename: "Ministral-3-3B-Instruct-2512-Q4_K_M.gguf", sizeMB: 2146),
                .init(quant: "Q5_K_M", filename: "Ministral-3-3B-Instruct-2512-Q5_K_M.gguf", sizeMB: 2474),
                .init(quant: "Q6_K",   filename: "Ministral-3-3B-Instruct-2512-Q6_K.gguf",   sizeMB: 2821),
                .init(quant: "Q8_0",   filename: "Ministral-3-3B-Instruct-2512-Q8_0.gguf",   sizeMB: 3652)
              ]),

        // ── Крупные: аналитика, код, длинные рассуждения ───────────────────
        .init(title: "Qwen3 14B",
              note: T("Топ-универсал: сложная аналитика, живой русский язык, ролевые диалоги. При 16 ГБ памяти остаётся запас примерно на 32k токенов контекста.", "The top all-rounder: complex analysis, natural Russian, role-play. With 16 GB of memory there is room for roughly 32k tokens of context."),
              repo: "unsloth/Qwen3-14B-GGUF", tier: .large, thinking: .toggleable, quantOptions: [
                .init(quant: "Q3_K_M", filename: "Qwen3-14B-Q3_K_M.gguf", sizeMB: 7321),
                .init(quant: "Q4_K_M", filename: "Qwen3-14B-Q4_K_M.gguf", sizeMB: 9002),
                .init(quant: "Q5_K_M", filename: "Qwen3-14B-Q5_K_M.gguf", sizeMB: 10515),
                .init(quant: "Q6_K",   filename: "Qwen3-14B-Q6_K.gguf",   sizeMB: 12122),
                .init(quant: "Q8_0",   filename: "Qwen3-14B-Q8_0.gguf",   sizeMB: 15699)
              ]),
        .init(title: "Qwen2.5 Coder 14B",
              note: T("Лучшая в каталоге для кода: рефакторинг, поиск багов, генерация скриптов на любых языках.", "The best in the catalogue for code: refactoring, bug hunting, generating scripts in any language."),
              repo: "unsloth/Qwen2.5-Coder-14B-Instruct-GGUF", tier: .large, quantOptions: [
                .init(quant: "Q3_K_M", filename: "Qwen2.5-Coder-14B-Instruct-Q3_K_M.gguf", sizeMB: 7339),
                .init(quant: "Q4_K_M", filename: "Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf", sizeMB: 8988),
                .init(quant: "Q5_K_M", filename: "Qwen2.5-Coder-14B-Instruct-Q5_K_M.gguf", sizeMB: 10509),
                .init(quant: "Q6_K",   filename: "Qwen2.5-Coder-14B-Instruct-Q6_K.gguf",   sizeMB: 12125),
                .init(quant: "Q8_0",   filename: "Qwen2.5-Coder-14B-Instruct-Q8_0.gguf",   sizeMB: 15702)
              ]),
        .init(title: "Qwen3.5 9B",
              note: T("Максимальная скорость без потерь от сжатия: Q8_0 почти неотличим от оригинала, а контекст тянет до 64k токенов и больше.", "Maximum speed with no compression loss: Q8_0 is near-indistinguishable from the original, and context stretches to 64k tokens and beyond."),
              repo: "unsloth/Qwen3.5-9B-GGUF", tier: .large, thinking: .toggleable, quantOptions: [
                .init(quant: "Q3_K_M", filename: "Qwen3.5-9B-Q3_K_M.gguf", sizeMB: 4674),
                .init(quant: "Q4_K_M", filename: "Qwen3.5-9B-Q4_K_M.gguf", sizeMB: 5681),
                .init(quant: "Q5_K_M", filename: "Qwen3.5-9B-Q5_K_M.gguf", sizeMB: 6578),
                .init(quant: "Q6_K",   filename: "Qwen3.5-9B-Q6_K.gguf",   sizeMB: 7458),
                .init(quant: "Q8_0",   filename: "Qwen3.5-9B-Q8_0.gguf",   sizeMB: 9528)
              ]),
        .init(title: "DeepSeek-R1 Distill 14B",
              note: T("Сложная логика и алгоритмы: расписывает ход рассуждения по шагам и меньше выдумывает. Лёгкое квантование оставляет память под длинные размышления.", "Complex logic and algorithms: it writes out its reasoning step by step and invents less. Lighter quantisation leaves memory for long deliberation."),
              repo: "unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF", tier: .large, thinking: .always, quantOptions: [
                .init(quant: "Q3_K_M", filename: "DeepSeek-R1-Distill-Qwen-14B-Q3_K_M.gguf", sizeMB: 7339),
                .init(quant: "Q4_K_M", filename: "DeepSeek-R1-Distill-Qwen-14B-Q4_K_M.gguf", sizeMB: 8988),
                .init(quant: "Q5_K_M", filename: "DeepSeek-R1-Distill-Qwen-14B-Q5_K_M.gguf", sizeMB: 10509),
                .init(quant: "Q6_K",   filename: "DeepSeek-R1-Distill-Qwen-14B-Q6_K.gguf",   sizeMB: 12125),
                .init(quant: "Q8_0",   filename: "DeepSeek-R1-Distill-Qwen-14B-Q8_0.gguf",   sizeMB: 15702)
              ]),
        .init(title: "Phi-4 14B",
              note: T("Точные науки и математика, выжимка плотных технических текстов.", "Exact sciences and mathematics, condensing dense technical texts."),
              repo: "unsloth/phi-4-GGUF", tier: .large, quantOptions: [
                .init(quant: "Q3_K_M", filename: "phi-4-Q3_K_M.gguf", sizeMB: 7191),
                .init(quant: "Q4_K_M", filename: "phi-4-Q4_K_M.gguf", sizeMB: 8890),
                .init(quant: "Q5_K_M", filename: "phi-4-Q5_K_M.gguf", sizeMB: 10413),
                .init(quant: "Q6_K",   filename: "phi-4-Q6_K.gguf",   sizeMB: 12030),
                .init(quant: "Q8_0",   filename: "phi-4-Q8_0.gguf",   sizeMB: 15581)
              ]),
        .init(title: "Gemma 3 12B Instruct",
              note: T("Мультимодальность и быстрая генерация, устойчива к очень длинным промптам. Самая нетребовательная в этой группе.", "Multimodal and fast, holds up on very long prompts. The least demanding in this group."),
              repo: "unsloth/gemma-3-12b-it-GGUF", tier: .large, quantOptions: [
                .init(quant: "Q3_K_M", filename: "gemma-3-12b-it-Q3_K_M.gguf", sizeMB: 6009),
                .init(quant: "Q4_K_M", filename: "gemma-3-12b-it-Q4_K_M.gguf", sizeMB: 7301),
                .init(quant: "Q5_K_M", filename: "gemma-3-12b-it-Q5_K_M.gguf", sizeMB: 8445),
                .init(quant: "Q6_K",   filename: "gemma-3-12b-it-Q6_K.gguf",   sizeMB: 9661),
                .init(quant: "Q8_0",   filename: "gemma-3-12b-it-Q8_0.gguf",   sizeMB: 12510)
              ]),

        // ── Очень крупные: настольный предел, 16–25 ГБ памяти ──────────────
        // Здесь локальная модель впервые всерьёз спорит с облаком по качеству
        // разбора. Имена файлов у этих репозиториев не следуют схеме Q3/Q4/Q5:
        // unsloth публикует «динамические» кванты (UD-*), где разные слои сжаты
        // по-разному — при том же размере они заметно точнее обычных.
        .init(title: "Qwen3.8 27B",
              note: T("Флагман плотной архитектуры: лучшая в каталоге на разборе смыслов, живом русском и длинных документах.", "The flagship dense architecture: the best in the catalogue at working through meaning, natural Russian and long documents."),
              repo: "unsloth/Qwen3.8-27B-GGUF", tier: .xlarge, thinking: .toggleable, quantOptions: [
                .init(quant: "UD-Q3_K_XL", filename: "Qwen3.8-27B-UD-Q3_K_XL.gguf", sizeMB: 13146),
                .init(quant: "UD-Q4_K_M",  filename: "Qwen3.8-27B-UD-Q4_K_M.gguf",  sizeMB: 16464),
                .init(quant: "UD-Q5_K_M",  filename: "Qwen3.8-27B-UD-Q5_K_M.gguf",  sizeMB: 19772),
                .init(quant: "UD-Q6_K",    filename: "Qwen3.8-27B-UD-Q6_K.gguf",    sizeMB: 21984),
                .init(quant: "Q8_0",       filename: "Qwen3.8-27B-Q8_0.gguf",       sizeMB: 29047)
              ]),
        .init(title: "Qwen3.6 35B-A3B",
              note: T("Смесь экспертов: 35B знаний при 3B активных параметров. Отвечает почти как 4B-модель, а рассуждает как крупная — лучший компромисс скорости и ума на Mac.", "A mixture of experts: 35B of knowledge with 3B active parameters. Answers almost like a 4B model and reasons like a large one — the best speed-to-intelligence trade-off on a Mac."),
              repo: "unsloth/Qwen3.6-35B-A3B-GGUF", tier: .xlarge, thinking: .toggleable, quantOptions: [
                .init(quant: "UD-Q3_K_M", filename: "Qwen3.6-35B-A3B-UD-Q3_K_M.gguf", sizeMB: 16601),
                .init(quant: "UD-Q4_K_M", filename: "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf", sizeMB: 22135),
                .init(quant: "UD-Q5_K_M", filename: "Qwen3.6-35B-A3B-UD-Q5_K_M.gguf", sizeMB: 26456),
                .init(quant: "UD-Q6_K",   filename: "Qwen3.6-35B-A3B-UD-Q6_K.gguf",   sizeMB: 29308),
                .init(quant: "Q8_0",      filename: "Qwen3.6-35B-A3B-Q8_0.gguf",      sizeMB: 36903)
              ]),
        .init(title: "Qwen3.5 27B",
              note: T("Старший брат лёгких моделей из этого же каталога: та же манера речи и те же промпты, только заметно умнее.", "The big sibling of the light models in this same catalogue: the same manner of speech and the same prompts, only noticeably smarter."),
              repo: "unsloth/Qwen3.5-27B-GGUF", tier: .xlarge, thinking: .toggleable, quantOptions: [
                .init(quant: "Q3_K_M", filename: "Qwen3.5-27B-Q3_K_M.gguf", sizeMB: 13505),
                .init(quant: "Q4_K_M", filename: "Qwen3.5-27B-Q4_K_M.gguf", sizeMB: 16741),
                .init(quant: "Q5_K_M", filename: "Qwen3.5-27B-Q5_K_M.gguf", sizeMB: 19609),
                .init(quant: "Q6_K",   filename: "Qwen3.5-27B-Q6_K.gguf",   sizeMB: 22454),
                .init(quant: "Q8_0",   filename: "Qwen3.5-27B-Q8_0.gguf",   sizeMB: 28596)
              ]),
        .init(title: "Gemma 4 31B Instruct",
              note: T("Самая сильная мультиязычная в каталоге: русский, кыргызский и смеси языков даются ей лучше остальных.", "The strongest multilingual model in the catalogue: Russian, Kyrgyz and language mixes come easier to it than to the rest."),
              repo: "unsloth/gemma-4-31B-it-GGUF", tier: .xlarge, quantOptions: [
                .init(quant: "Q3_K_M", filename: "gemma-4-31B-it-Q3_K_M.gguf", sizeMB: 14737),
                .init(quant: "Q4_K_M", filename: "gemma-4-31B-it-Q4_K_M.gguf", sizeMB: 18324),
                .init(quant: "Q5_K_M", filename: "gemma-4-31B-it-Q5_K_M.gguf", sizeMB: 21658),
                .init(quant: "Q6_K",   filename: "gemma-4-31B-it-Q6_K.gguf",   sizeMB: 25201),
                .init(quant: "Q8_0",   filename: "gemma-4-31B-it-Q8_0.gguf",   sizeMB: 32636)
              ]),
        .init(title: "Qwen3 Coder 30B-A3B",
              note: T("Код и скрипты: смесь экспертов, поэтому быстрая. Рефакторинг, разбор стектрейсов, генерация на любом языке.", "Code and scripts: a mixture of experts, so it is fast. Refactoring, reading stack traces, generating in any language."),
              repo: "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF", tier: .xlarge, quantOptions: [
                .init(quant: "Q3_K_M", filename: "Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf", sizeMB: 14712),
                .init(quant: "Q4_K_M", filename: "Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf", sizeMB: 18557),
                .init(quant: "Q5_K_M", filename: "Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf", sizeMB: 21726),
                .init(quant: "Q6_K",   filename: "Qwen3-Coder-30B-A3B-Instruct-Q6_K.gguf",   sizeMB: 25093),
                .init(quant: "Q8_0",   filename: "Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf",   sizeMB: 32484)
              ])
    ]
}

/// Скачивание и хранение локальных LLM-моделей — по образцу ModelManager для Whisper.
/// Оперирует конкретными файлами кванта (LLMQuantOption), а не семьями моделей:
/// одна и та же модель в разных квантах — это разные файлы на диске одновременно.
/// Скачивание и хранение локальных LLM-моделей — по образцу ModelManager для Whisper.
/// Оперирует конкретными файлами кванта (LLMQuantOption), а не семьями моделей:
/// одна и та же модель в разных квантах — это разные файлы на диске одновременно.
///
/// Качает с докачкой. Двадцать гигабайт по домашнему интернету — это десятки
/// минут, за которые сеть успевает моргнуть; раньше любой обрыв означал
/// «начинай сначала», потому что незавершённый файл просто выбрасывался.
/// Теперь загрузка идёт в файл `.part`, а повторный запуск дописывает его
/// с того места, где остановился, через заголовок `Range`.
final class LLMModelManager: NSObject, ObservableObject, URLSessionDataDelegate {
    static let shared = LLMModelManager()

    static var directory: URL {
        let dir = URL(fileURLWithPath: NSString(string: "~/Models/llm").expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Published var downloading: String? = nil
    /// Заголовок для показа снаружи каталога — в строке меню, например.
    @Published var downloadingTitle: String? = nil
    @Published var progress: Double = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var lastError: String? = nil
    /// Загрузка продолжена с уже скачанного места, а не начата заново.
    @Published var resumed = false

    /// Все установленные пары (модель, квант) по всему каталогу — считается заново
    /// из состояния диска на каждое обращение, отдельно не кэшируется.
    var installedPairs: [(model: LLMModel, quant: LLMQuantOption)] {
        LLMModel.catalog.flatMap { model in
            model.quantOptions.filter { model.isInstalled($0) }.map { (model, $0) }
        }
    }

    /// Сколько уже лежит в недокачанном файле — чтобы предложить «продолжить»
    /// вместо «скачать» и назвать оставшийся объём.
    func partialBytes(_ model: LLMModel, _ quant: LLMQuantOption) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.partURL(for: quant).path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func partURL(for quant: LLMQuantOption) -> URL {
        directory.appendingPathComponent(quant.filename + ".part")
    }

    private var session: URLSession!
    private var targetModel: LLMModel?
    private var targetQuant: LLMQuantOption?
    private var handle: FileHandle?
    private var receivedBytes: Int64 = 0
    private var expectedTotal: Int64 = 0
    private var currentTask: URLSessionDataTask?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        // Двадцать гигабайт по медленному каналу — это часы; общий срок
        // ресурса не должен обрывать такую загрузку.
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func download(_ model: LLMModel, _ quant: LLMQuantOption) {
        guard downloading == nil else { return }
        targetModel = model
        targetQuant = quant

        let partURL = Self.partURL(for: quant)
        let already = partialBytes(model, quant)
        receivedBytes = already
        expectedTotal = Int64(quant.sizeMB) * 1_000_000

        var request = URLRequest(url: model.remoteURL(for: quant))
        if already > 0 {
            request.setValue("bytes=\(already)-", forHTTPHeaderField: "Range")
        }

        DispatchQueue.main.async {
            self.downloading = quant.filename
            self.downloadingTitle = LLMModel.displayName(model: model, quant: quant)
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

    /// Останавливает загрузку, не удаляя уже скачанное: следующий запуск
    /// продолжит с этого места.
    func pauseDownload() {
        currentTask?.cancel()
        currentTask = nil
        try? handle?.close()
        handle = nil
        DispatchQueue.main.async {
            self.downloading = nil
            self.downloadingTitle = nil
            self.progress = 0
        }
    }

    /// Выбрасывает недокачанный кусок — когда файл на сервере изменился
    /// и докачка бессмысленна.
    func discardPartial(_ quant: LLMQuantOption) {
        try? FileManager.default.removeItem(at: Self.partURL(for: quant))
        objectWillChange.send()
    }

    func delete(_ model: LLMModel, _ quant: LLMQuantOption) {
        let url = model.localURL(for: quant)
        let path = url.path
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: Self.partURL(for: quant))
        // Останавливаем только этот сервер: остальные модели остаются
        // загруженными и продолжают обслуживать свои разделы.
        LocalAIProvider.shared.stop(modelPath: path)

        if AppSettings.shared.aiLocalModelPath == path {
            AppSettings.shared.aiLocalModelPath = ""
        }
        // Роли, которые ссылались на удалённый файл, возвращаем к общему
        // умолчанию: иначе раздел остался бы указывать в пустоту.
        let deletedID = AIModelChoice.local(quant.filename).id
        var overrides = AppSettings.shared.aiRoleOverrides
        let cleaned = overrides.filter { $0.value != deletedID }
        if cleaned.count != overrides.count {
            overrides = cleaned
            AppSettings.shared.aiRoleOverrides = overrides
        }
        objectWillChange.send()
    }

    // MARK: - URLSession Delegate

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }

        switch http.statusCode {
        case 206:
            // Сервер согласился продолжить — дописываем.
            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let totalPart = range.split(separator: "/").last,
               let total = Int64(totalPart) {
                expectedTotal = total
            }
        case 200:
            // Докачка не поддержана или файл изменился — начинаем заново.
            if receivedBytes > 0, let quant = targetQuant {
                try? handle?.close()
                try? FileManager.default.removeItem(at: Self.partURL(for: quant))
                FileManager.default.createFile(atPath: Self.partURL(for: quant).path, contents: nil)
                handle = try? FileHandle(forWritingTo: Self.partURL(for: quant))
                receivedBytes = 0
            }
            if http.expectedContentLength > 0 { expectedTotal = http.expectedContentLength }
        default:
            fail(T("Сервер ответил \(http.statusCode). Попробуйте позже.", "The server replied \(http.statusCode). Try again later."))
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
            // Отмена — это пауза, а не сбой: `.part` остаётся на диске.
            if (error as NSError).code == NSURLErrorCancelled { return }
            fail(error.localizedDescription)
            return
        }
        guard let model = targetModel, let quant = targetQuant else { return }

        let partURL = Self.partURL(for: quant)
        let onDisk = (try? FileManager.default.attributesOfItem(atPath: partURL.path))
            .flatMap { ($0[.size] as? NSNumber)?.int64Value } ?? 0

        // Проверка размера: оборванная на середине загрузка внешне выглядит
        // как успешная, а llama-server на битом файле падает с невнятной
        // ошибкой уже сильно позже, при первой попытке что-то спросить.
        if expectedTotal > 0, onDisk < expectedTotal {
            fail(T("Файл докачан не полностью (\(onDisk / 1_000_000) из \(expectedTotal / 1_000_000) МБ). Нажмите «Продолжить».", "The file is not fully downloaded (\(onDisk / 1_000_000) of \(expectedTotal / 1_000_000) MB). Press “Resume”."))
            return
        }

        do {
            try? FileManager.default.removeItem(at: model.localURL(for: quant))
            try FileManager.default.moveItem(at: partURL, to: model.localURL(for: quant))
        } catch {
            fail(error.localizedDescription)
            return
        }

        DispatchQueue.main.async {
            self.downloading = nil
            self.downloadingTitle = nil
            self.progress = 0
            self.downloadedBytes = 0
            self.totalBytes = 0
            self.resumed = false
            self.objectWillChange.send()
            AppSettings.shared.aiLocalModelPath = model.localURL(for: quant).path
        }
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async {
            self.lastError = message
            self.downloading = nil
            self.downloadingTitle = nil
            self.progress = 0
        }
    }
}
