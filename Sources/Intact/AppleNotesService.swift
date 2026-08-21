import AppKit
import Foundation

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
