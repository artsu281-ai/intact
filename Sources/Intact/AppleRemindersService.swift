import AppKit
import EventKit
import Foundation

struct ParsedReminder {
    let title: String
    let dueDate: Date?
}

/// Сервис создания напоминаний в Apple Reminders (Напоминания macOS / iOS) по голосовым командам.
enum AppleRemindersService {

    private static let eventStore = EKEventStore()

    /// Регулярные выражения для распознавания команд напоминаний в начале фразы
    private static let commandPatterns: [String] = [
        "^(напомни|напомнить|создай напоминание|создать напоминание|поставь напоминание|поставить напоминание|поставь задачу|поставить задачу|напоминание|напоминалка)(\\s*(мне|что|о|про|:|-|—|\\.)\\s*|\\s+)",
        "^(remind me|create reminder|new reminder|set reminder|reminder)(\\s*(to|that|about|:|-|—|\\.)\\s*|\\s+)"
    ]

    /// Проверяет, является ли продиктованный текст командой напоминания,
    /// и возвращает извлеченный заголовок и дату/время срока.
    static func extractReminder(from rawText: String) -> ParsedReminder? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var cleanText = ""
        var matched = false

        for pattern in commandPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: trimmed.utf16.count)
                if let match = regex.firstMatch(in: trimmed, options: [], range: range),
                   match.range.location == 0 {
                    let matchLength = match.range.length
                    let startIndex = trimmed.utf16.index(trimmed.utf16.startIndex, offsetBy: matchLength)
                    cleanText = String(trimmed[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    matched = true
                    break
                }
            }
        }

        guard matched, !cleanText.isEmpty else { return nil }

        var dueDate: Date? = nil
        var finalTitle = cleanText
        let now = Date()
        let cal = Calendar.current

        // 1. Относительное время: «через X минут / часов / дней»
        let relativePattern = "через\\s+(\\d+)\\s+(минут[ыа]?|мин|час[аов]?|дн[ейя]+|день)"
        if let relRegex = try? NSRegularExpression(pattern: relativePattern, options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: cleanText.utf16.count)
            if let match = relRegex.firstMatch(in: cleanText, options: [], range: range) {
                let numRange = match.range(at: 1)
                let unitRange = match.range(at: 2)
                if let numStr = Range(numRange, in: cleanText).map({ String(cleanText[$0]) }),
                   let num = Int(numStr),
                   let unitStr = Range(unitRange, in: cleanText).map({ String(cleanText[$0]).lowercased() }) {
                    if unitStr.hasPrefix("мин") {
                        dueDate = now.addingTimeInterval(Double(num * 60))
                    } else if unitStr.hasPrefix("час") {
                        dueDate = now.addingTimeInterval(Double(num * 3600))
                    } else if unitStr.hasPrefix("дн") || unitStr.hasPrefix("ден") {
                        dueDate = now.addingTimeInterval(Double(num * 86400))
                    }
                    if let fullRange = Range(match.range, in: cleanText) {
                        finalTitle.removeSubrange(fullRange)
                    }
                }
            }
        }

        // 2. Абсолютное время: «завтра в HH(:MM)?» или «сегодня в HH(:MM)?» или «в HH(:MM)?»
        if dueDate == nil {
            let timePattern = "(сегодня|завтра)?\\s*в\\s+(\\d{1,2})([:.](\\d{2}))?"
            if let timeRegex = try? NSRegularExpression(pattern: timePattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: cleanText.utf16.count)
                if let match = timeRegex.firstMatch(in: cleanText, options: [], range: range) {
                    let dayWordRange = match.range(at: 1)
                    let hourRange = match.range(at: 2)
                    let minRange = match.range(at: 4)

                    let isTomorrow = (dayWordRange.location != NSNotFound &&
                                      Range(dayWordRange, in: cleanText).map { String(cleanText[$0]).lowercased() } == "завтра")
                    if let hStr = Range(hourRange, in: cleanText).map({ String(cleanText[$0]) }),
                       let hour = Int(hStr), hour >= 0 && hour <= 23 {
                        let minute = (minRange.location != NSNotFound ? Range(minRange, in: cleanText).flatMap { Int(cleanText[$0]) } : 0) ?? 0
                        
                        var comps = cal.dateComponents([.year, .month, .day], from: now)
                        if isTomorrow {
                            comps.day = (comps.day ?? 0) + 1
                        }
                        comps.hour = hour
                        comps.minute = minute
                        comps.second = 0
                        if let calculated = cal.date(from: comps) {
                            if !isTomorrow && calculated < now {
                                dueDate = cal.date(byAdding: .day, value: 1, to: calculated)
                            } else {
                                dueDate = calculated
                            }
                        }
                        if let fullRange = Range(match.range, in: cleanText) {
                            finalTitle.removeSubrange(fullRange)
                        }
                    }
                }
            }
        }

        // 3. Fallback: NSDataDetector для английских и сложных дат
        if dueDate == nil {
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
                let range = NSRange(location: 0, length: cleanText.utf16.count)
                if let match = detector.firstMatch(in: cleanText, options: [], range: range),
                   let detectedDate = match.date {
                    dueDate = detectedDate
                    if let fullRange = Range(match.range, in: cleanText) {
                        finalTitle.removeSubrange(fullRange)
                    }
                }
            }
        }

        // Очищаем заголовок от остаточных знаков препинания
        let cleanedTitle = finalTitle
            .trimmingCharacters(in: CharacterSet(charactersIn: ":,.-— \t\n"))
        guard !cleanedTitle.isEmpty else { return nil }

        let capitalized = cleanedTitle.prefix(1).uppercased() + cleanedTitle.dropFirst()
        return ParsedReminder(title: capitalized, dueDate: dueDate)
    }

    /// Асинхронно создает напоминание в Apple Reminders
    static func createReminder(title: String, dueDate: Date?, listName: String = "", completion: ((Bool) -> Void)? = nil) {
        requestAccess { granted in
            guard granted else {
                Log.write("нет доступа к Apple Reminders")
                completion?(false)
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let success = createReminderSync(title: title, dueDate: dueDate, listName: listName)
                DispatchQueue.main.async {
                    completion?(success)
                }
            }
        }
    }

    private static func createReminderSync(title: String, dueDate: Date?, listName: String) -> Bool {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = "Создано через Intact"

        // Выбор целевого списка напоминаний
        var targetCalendar: EKCalendar?
        if !listName.trimmingCharacters(in: .whitespaces).isEmpty {
            let calendars = eventStore.calendars(for: .reminder)
            targetCalendar = calendars.first { $0.title.lowercased() == listName.lowercased() }
        }
        reminder.calendar = targetCalendar ?? eventStore.defaultCalendarForNewReminders()

        // Установка дедлайна и будильника
        if let dueDate {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = comps
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        do {
            try eventStore.save(reminder, commit: true)
            Log.write("напоминание успешно создано в Apple Reminders: «\(title)»")
            return true
        } catch {
            Log.write("ошибка сохранения напоминания в EventKit: \(error.localizedDescription)")
            return false
        }
    }

    private static func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }
}
