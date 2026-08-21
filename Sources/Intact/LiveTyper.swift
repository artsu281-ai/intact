import AppKit
import Carbon.HIToolbox

/// Печать текста прямо в поле по мере распознавания — без буфера обмена.
///
/// Черновик whisper — это каждый раз заново распознанная целиком фраза, а не
/// дописанный хвост. Он свободно меняет уже произнесённое: дописывает запятую,
/// переставляет заглавную букву. Стирать из-за этого всё напечатанное и
/// набирать заново нельзя — текст в документе прыгал бы на каждом черновике.
///
/// Поэтому правило простое: **напечатанное не переписывается никогда.**
/// Слово уходит в поле, только когда оно совпало в двух черновиках подряд,
/// и дальше считается окончательным. Цена — редкое слово в начале фразы
/// останется в той версии, в какой было признано устойчивым.
final class LiveTyper {
    static let shared = LiveTyper()

    /// Слова, которые уже физически напечатаны в чужом окне.
    private var committed: [String] = []
    /// Предыдущий черновик — с ним сверяем, что успело устояться.
    private var previous: [String] = []
    /// Сколько символов мы набрали: столько же придётся стереть при отмене.
    private var typedChars = 0

    private let queue = DispatchQueue(label: "intact.livetyper")

    private init() {}

    func reset() {
        queue.async {
            self.committed = []
            self.previous = []
            self.typedChars = 0
        }
    }

    /// Очередной черновик. `holdBack` — сколько последних слов придержать:
    /// хвост черновика самый неустойчивый.
    func update(draft: String, holdBack: Int) {
        queue.async {
            let words = Self.words(of: draft)

            // Устоявшийся префикс: слова, не изменившиеся с прошлого черновика.
            var stable = 0
            while stable < words.count, stable < self.previous.count,
                  words[stable] == self.previous[stable] { stable += 1 }
            self.previous = words

            let limit = min(stable, max(0, words.count - holdBack))
            guard limit > self.committed.count else { return }

            let fresh = Array(words[self.committed.count..<limit])

            // Если новый хвост дословно повторяет уже напечатанный конец —
            // это whisper зациклился, и печатать это второй раз нельзя.
            if fresh.count >= 3, Array(self.committed.suffix(fresh.count)) == fresh {
                Log.write("пропущен повтор хвоста: \(fresh.count) сл.")
                self.committed = Array(words[0..<limit])
                return
            }

            self.emit(fresh)
            self.committed = Array(words[0..<limit])
        }
    }

    /// Финальный текст: дописываем то, что осталось за уже напечатанным.
    func finish(with text: String, appendSpace: Bool) {
        queue.async {
            let words = Self.words(of: text)
            if words.count > self.committed.count {
                self.emit(Array(words[self.committed.count...]), trailingSpace: appendSpace)
            }
            self.committed = []
            self.previous = []
            self.typedChars = 0
        }
    }

    /// Диктовку отменили — убираем за собой всё, что успели напечатать.
    func eraseAll() {
        queue.async {
            self.backspace(self.typedChars)
            self.committed = []
            self.previous = []
            self.typedChars = 0
        }
    }

    // MARK: - Ввод

    private func emit(_ words: [String], trailingSpace: Bool = true) {
        guard !words.isEmpty else { return }
        guard Permissions.accessibility else {
            Log.write("живая печать невозможна: нет «Универсального доступа»")
            return
        }
        var chunk = words.joined(separator: " ")
        if trailingSpace { chunk += " " }
        Log.write("печать: +\(words.count) сл. (\(chunk.count) симв.)")
        type(chunk)
        typedChars += chunk.count
    }

    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    }

    /// Печатаем, пока пользователь физически держит ⌥. Если не гасить флаги,
    /// каждый символ уйдёт как ⌥+клавиша, а забой станет «удалить слово целиком».
    private func post(_ event: CGEvent?) {
        guard let event else { return }
        event.flags = []
        event.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func backspace(_ count: Int) {
        guard count > 0, let src = CGEventSource(stateID: .privateState) else { return }
        for _ in 0..<count {
            post(CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Delete), keyDown: true))
            post(CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Delete), keyDown: false))
            usleep(1200)
        }
    }

    private func type(_ text: String) {
        guard !text.isEmpty, let src = CGEventSource(stateID: .privateState) else { return }
        // Пара нажатие+отпускание на символ: событий без отпускания
        // многие поля ввода не принимают.
        for ch in text {
            var down = Array(String(ch).utf16)
            let d = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            d?.keyboardSetUnicodeString(stringLength: down.count, unicodeString: &down)
            post(d)

            var up = Array(String(ch).utf16)
            let u = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            u?.keyboardSetUnicodeString(stringLength: up.count, unicodeString: &up)
            post(u)
            usleep(1400)
        }
    }
}
