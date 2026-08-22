import AppKit
import Foundation

/// Выгрузка содержимого Intact в файл на диске.
///
/// Единая точка: и история диктовок, и отчёт ассистента уходят через один
/// диалог сохранения с одинаковыми правилами именования и одинаковой
/// обработкой отказа пользователя.
enum Exporter {

    enum Result {
        case saved(URL)
        case cancelled
        case failed(String)
    }

    /// Показывает диалог сохранения и пишет текст в выбранный файл.
    @MainActor
    static func save(text: String, suggestedName: String, fileExtension: String = "md") -> Result {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed("Нечего выгружать")
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).\(fileExtension)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Выгрузка Intact"
        panel.prompt = "Сохранить"

        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return .saved(url)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Открывает Finder на сохранённом файле — иначе пользователь не понимает,
    /// куда именно ушла выгрузка.
    @MainActor
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Форматы

    /// История диктовок в Markdown: заголовок, затем по записи на блок.
    static func historyMarkdown(_ entries: [HistoryEntry]) -> String {
        var out = "# История диктовок Intact\n\n"
        out += "Записей: \(entries.count) · выгружено \(stamp(Date()))\n\n"

        let byDay = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
        for day in byDay.keys.sorted(by: >) {
            out += "\n## \(day.formatted(date: .long, time: .omitted))\n\n"
            for entry in (byDay[day] ?? []).sorted(by: { $0.date > $1.date }) {
                let meta = "\(entry.kind.marker) \(entry.kind.title)"
                    + " · \(entry.date.formatted(date: .omitted, time: .shortened))"
                    + " · \(String(format: "%.1f", entry.seconds)) с · \(entry.model)"
                out += "- **\(meta)**\n  \n  \(entry.text)\n\n"
            }
        }
        return out
    }

    /// Отчёт по диалогу с ассистентом: только содержательная часть переписки.
    static func reportMarkdown(_ messages: [ChatMessage]) -> String {
        var out = "# Отчёт Intact\n\n"
        out += "Сформировано \(stamp(Date()))\n"

        for message in messages {
            let isUser = message.role == .user
            out += "\n## \(isUser ? "Запрос" : "Ответ ассистента")"
            out += " · \(message.timestamp.formatted(date: .omitted, time: .shortened))\n\n"
            if !message.contextBadges.isEmpty {
                out += "_Контекст: \(message.contextBadges.joined(separator: ", "))_\n\n"
            }
            out += message.content + "\n"
        }
        return out
    }

    /// Имя файла без пробелов и двоеточий — иначе оно неудобно в терминале.
    static func fileStamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }

    private static func stamp(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }
}
