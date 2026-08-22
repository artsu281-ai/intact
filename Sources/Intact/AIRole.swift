import Foundation

/// Задача, под которую выбирается модель.
///
/// Раньше «версия ИИ» была одна на всё приложение: та же модель, что пишет
/// развёрнутый разбор в чате, причёсывала каждую диктовку. Это несовместимые
/// требования. Причёсывание обязано уложиться в несколько секунд, иначе оно
/// тормозит вставку текста и отваливается по таймауту; разбор недельных
/// заметок, наоборот, имеет право думать минуту. Одна общая настройка
/// заставляла выбирать между «умно, но диктовка тормозит» и «быстро, но
/// в чате слабая модель». Поэтому модель выбирается на роль, а не на приложение.
enum AIRole: String, CaseIterable, Identifiable {
    /// Причёсывание диктовки перед вставкой в поле ввода.
    case cleanup
    /// Хоткей «Спросите ИИ»: ответ вставляется вместо надиктованного вопроса.
    case quickAnswer
    /// Чат, быстрый анализ и брифы.
    case chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleanup:     return T("Причёсывание диктовки", "Dictation cleanup")
        case .quickAnswer: return T("Спросите ИИ", "Ask AI")
        case .chat:        return T("Чат, анализ и брифы", "Chat, analysis and briefs")
        }
    }

    var subtitle: String {
        switch self {
        case .cleanup:
            return T("Убирает слова-паразиты и расставляет знаки. Должно успевать за диктовкой — здесь важнее скорость, чем ум.", "Removes filler words and adds punctuation. Has to keep up with dictation — speed matters more than depth here.")
        case .quickAnswer:
            return T("Отвечает на голосовой вопрос и вставляет ответ под курсор. Нужен короткий точный ответ за несколько секунд.", "Answers a spoken question and inserts the answer at the cursor. Needs a short, exact answer within seconds.")
        case .chat:
            return T("Разбирает диктовки, заметки и файлы. Здесь имеет смысл самая сильная модель — время ответа не критично.", "Works through dictations, notes and files. The strongest model makes sense here — response time is not critical.")
        }
    }

    var icon: IntactIconKind {
        switch self {
        case .cleanup:     return .voice
        case .quickAnswer: return .aiStar
        case .chat:        return .chat
        }
    }

    /// Раздел приложения, где эта роль настраивается — для ссылок «настроить».
    var section: SettingsSection {
        switch self {
        case .cleanup:     return .voice
        case .quickAnswer: return .askAI
        case .chat:        return .chat
        }
    }

    /// Потолок ответа.
    ///
    /// У облака и локальной модели он разный не из-за качества, а из-за скорости:
    /// 16k токенов облако отдаёт за полминуты, локальная 27B — за десять минут.
    func maxTokens(cloud: Bool, thinking: Bool = false) -> Int {
        let base: Int
        switch self {
        case .cleanup:     base = 2_000
        case .quickAnswer: base = cloud ? 4_000 : 1_500
        case .chat:        base = cloud ? 16_000 : 4_096
        }
        // Рассуждение тратит лимит до того, как начнётся ответ: на прежнем
        // потолке модель успевала подумать и обрывалась на первой фразе.
        return thinking ? base * 2 : base
    }

    /// Сколько ждать ответа, прежде чем сдаться.
    ///
    /// Для причёсывания это не «сколько не жалко», а «сколько человек готов
    /// смотреть на пустое поле»: по истечении вставляется исходный текст.
    /// Крупные и рассуждающие модели честно получают больше времени —
    /// иначе выбор Opus в этой роли означал бы, что причёсывание не работает
    /// никогда и молча.
    func timeout(cloud: Bool, thinking: Bool) -> TimeInterval {
        switch self {
        case .cleanup:
            if thinking { return 25 }
            return cloud ? 15 : 8
        case .quickAnswer:
            if thinking { return 60 }
            return cloud ? 40 : 25
        case .chat:
            // Чат стримит и показывает текст по мере генерации — здесь потолок
            // нужен только чтобы не висеть вечно на мёртвом соединении.
            return 900
        }
    }

    /// `output_config.effort` для облачных моделей, которые его понимают.
    ///
    /// Глубина рассуждения — главный рычаг «быстро/умно» у моделей 5-го
    /// поколения, и он же самый недооценённый: Opus на `low` отвечает
    /// в разы быстрее, оставаясь заметно сильнее Haiku.
    var cloudEffort: String {
        switch self {
        case .cleanup:     return "low"
        case .quickAnswer: return "low"
        case .chat:        return "high"
        }
    }
}
