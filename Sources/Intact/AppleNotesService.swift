import AppKit
import Foundation

struct NoteItem: Identifiable, Hashable {
    let id: String
    let name: String
    let body: String
    let date: String
}

/// Сервис создания заметок в Apple Notes (Заметки macOS / iOS) по голосовым командам.
enum AppleNotesService {

    /// Регулярные выражения для распознавания команд создания заметки в начале фразы
    private static let commandPatterns: [String] = [
        "^(делаем заметку|сделай заметку|сделать заметку|создай заметку|создать заметку|запиши в заметки|запиши в заметку|записать в заметки|запиши заметку|записать заметку|новая заметка|заметка|заметку)(\\s*(о|про|что|:|-|—|\\.)\\s*|\\s+)",
        "^(take a note|make a note|create a note|new note|quick note|note)(\\s*(that|about|:|-|—|\\.)\\s*|\\s+)"
    ]

    /// Проверяет, является ли продиктованный текст командой создания заметки,
    /// и возвращает очищенное содержимое заметки.
    static func extractNoteText(from rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for pattern in commandPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: trimmed.utf16.count)
                if let match = regex.firstMatch(in: trimmed, options: [], range: range),
                   match.range.location == 0 {
                    // Извлекаем всё, что идет после команды
                    let matchLength = match.range.length
                    let startIndex = trimmed.utf16.index(trimmed.utf16.startIndex, offsetBy: matchLength)
                    let remaining = String(trimmed[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Удаляем лишнее двоеточие/тире/точки в начале оставшейся фразы
                    let cleaned = remaining
                        .trimmingCharacters(in: CharacterSet(charactersIn: ":,.-— \t\n"))
                    
                    guard !cleaned.isEmpty else { return nil }
                    return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
                }
            }
        }
        return nil
    }

    /// Асинхронно создает заметку в Apple Notes
    static func createNote(text: String, folderName: String = "Intact", completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let success = createNoteSync(text: text, folderName: folderName)
            DispatchQueue.main.async {
                completion?(success)
            }
        }
    }

    /// Асинхронно читает последние заметки из Apple Notes
    static func fetchRecentNotes(folderName: String = "Intact", limit: Int = 15, completion: @escaping ([NoteItem]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let notes = fetchRecentNotesSync(folderName: folderName, limit: limit)
            DispatchQueue.main.async {
                completion(notes)
            }
        }
    }

    private static func fetchRecentNotesSync(folderName: String, limit: Int) -> [NoteItem] {
        let folderEscaped = folderName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Notes"
            tell default account
                set targetFolder to missing value
                if "\(folderEscaped)" is not "" then
                    repeat with f in folders
                        if name of f is "\(folderEscaped)" then
                            set targetFolder to f
                            exit repeat
                        end if
                    end repeat
                end if
                if targetFolder is missing value then
                    set targetFolder to default folder
                end if
                set res to ""
                set noteList to (notes of targetFolder)
                set c to count of noteList
                if c > \(limit) then set c to \(limit)
                repeat with i from 1 to c
                    set n to item i of noteList
                    set nName to name of n
                    set nBody to plaintext of n
                    set nDate to ((modification date of n) as string)
                    set res to res & nName & "<NOTE_FIELD>" & nBody & "<NOTE_FIELD>" & nDate & "<NOTE_SEP>"
                end repeat
                return res
            end tell
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else { return [] }
        var error: NSDictionary?
        let output = appleScript.executeAndReturnError(&error)
        if let error {
            Log.write("ошибка чтения заметок из Notes: \(error)")
            return []
        }

        guard let rawStr = output.stringValue, !rawStr.isEmpty else { return [] }
        let rawNotes = rawStr.components(separatedBy: "<NOTE_SEP>").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return rawNotes.compactMap { rawNote in
            let fields = rawNote.components(separatedBy: "<NOTE_FIELD>")
            guard fields.count >= 2 else { return nil }
            let name = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let body = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let date = fields.count > 2 ? fields[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return NoteItem(id: UUID().uuidString, name: name, body: body, date: date)
        }
    }

    private static func createNoteSync(text: String, folderName: String) -> Bool {
        // Формируем заголовок и тело HTML
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let title = lines.first ?? text
        let titleEscaped = escapeHtml(title)
        let bodyEscaped = escapeHtml(text).replacingOccurrences(of: "\n", with: "<br>")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM в HH:mm"
        let dateStr = formatter.string(from: Date())

        let htmlBody = """
        <div><h1>\(titleEscaped)</h1></div><div><span style="color:#888888;font-size:12px;">Создано \(dateStr) через Intact</span></div><br><div>\(bodyEscaped)</div>
        """

        let escapedForAppleScript = htmlBody
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        let folderEscaped = folderName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Notes"
            tell default account
                set targetFolder to missing value
                if "\(folderEscaped)" is not "" then
                    repeat with f in folders
                        if name of f is "\(folderEscaped)" then
                            set targetFolder to f
                            exit repeat
                        end if
                    end repeat
                end if
                
                if targetFolder is missing value then
                    set targetFolder to default folder
                end if
                
                make new note at targetFolder with properties {body:"\(escapedForAppleScript)"}
            end tell
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error {
            Log.write("ошибка создания заметки в Notes: \(error)")
            return false
        }
        Log.write("заметка успешно создана в Apple Notes: «\(title.prefix(30))»")
        return true
    }

    private static func escapeHtml(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
