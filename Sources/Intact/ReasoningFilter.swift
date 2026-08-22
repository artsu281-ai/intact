import Foundation

/// Отделяет рассуждение модели от самого ответа.
///
/// Рассуждающие модели выдают ход мысли двумя разными способами. Хорошо
/// настроенный шаблон кладёт его в отдельное поле `reasoning_content` —
/// такое нам и разбирать не надо. Но многие GGUF-сборки пишут рассуждение
/// прямо в `content`, обёрнутым в `<think>…</think>`, и без фильтра оно
/// попадало бы в чат, в бриф и в текст, который вставляется под курсор.
///
/// Работает по кусочкам потока: теги свободно разрезаются между пакетами,
/// поэтому хвост, который может оказаться началом тега, придерживается
/// до следующего куска.
struct ReasoningFilter {
    private static let openTag = "<think>"
    private static let closeTag = "</think>"

    private var buffer = ""
    private var inside = false
    /// Модель действительно рассуждала — по этому признаку интерфейс может
    /// сказать «думает», а не «печатает».
    private(set) var sawReasoning = false

    /// Скармливает очередной кусок, возвращает ту его часть, которую можно показать.
    mutating func feed(_ chunk: String) -> String {
        buffer += chunk
        var visible = ""

        while true {
            if inside {
                guard let range = buffer.range(of: Self.closeTag) else {
                    // Всё, что накопилось, — рассуждение. Оставляем только хвост,
                    // который может оказаться началом закрывающего тега.
                    buffer = String(buffer.suffix(Self.partialTailLength(buffer, tag: Self.closeTag)))
                    return visible
                }
                buffer = String(buffer[range.upperBound...])
                inside = false
            } else {
                guard let range = buffer.range(of: Self.openTag) else {
                    let keep = Self.partialTailLength(buffer, tag: Self.openTag)
                    visible += String(buffer.dropLast(keep))
                    buffer = String(buffer.suffix(keep))
                    return visible
                }
                visible += String(buffer[..<range.lowerBound])
                buffer = String(buffer[range.upperBound...])
                inside = true
                sawReasoning = true
            }
        }
    }

    /// Остаток после конца потока: незакрытый `<think>` означает, что модель
    /// не успела дойти до ответа — показывать её мысли всё равно не нужно.
    mutating func flush() -> String {
        guard !inside else { buffer = ""; return "" }
        let rest = buffer
        buffer = ""
        return rest
    }

    /// Разовая очистка целого текста — для непотоковых ответов.
    static func strip(_ text: String) -> String {
        var filter = ReasoningFilter()
        let visible = filter.feed(text) + filter.flush()
        return visible.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Длина самого длинного суффикса строки, который является префиксом тега.
    /// «…ответ, а вот и <thi» — три последних символа придерживаем.
    private static func partialTailLength(_ text: String, tag: String) -> Int {
        let maxLength = min(text.count, tag.count - 1)
        guard maxLength > 0 else { return 0 }
        for length in stride(from: maxLength, through: 1, by: -1) {
            if text.hasSuffix(String(tag.prefix(length))) { return length }
        }
        return 0
    }
}
