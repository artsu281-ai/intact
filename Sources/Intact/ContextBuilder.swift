import Foundation

/// Сборка «актуального контекста пользователя» — диктовок, заметок,
/// напоминаний и прикреплённых файлов — в один текстовый блок для модели.
///
/// Вынесено из AIChatService, потому что пользуется этим не только чат:
/// брифы собираются тем же способом, но без диалога вокруг.
enum ContextBuilder {

    static func gather(sources: Set<AIContextSource>,
                       files: [AttachedFile] = [],
                       completion: @escaping (String, [String]) -> Void) {
        var contextBlocks: [String] = []
        var badges: [String] = []
        let group = DispatchGroup()

        // 0. Прикреплённые файлы — не завязаны на toggle-источники, добавляются всегда.
        if !files.isEmpty {
            badges.append("Файлы (\(files.count))")
            var text = "### Прикреплённые файлы:\n"
            for f in files {
                text += "--- \(f.displayName) ---\n\(f.content)\n\n"
            }
            contextBlocks.append(text)
        }

        // 1. Диктовки за сегодня
        if sources.contains(.dictationToday) {
            let todayEntries = History.shared.entries.filter { Calendar.current.isDateInToday($0.date) }
            // Считаем по тому, что реально уходит в промпт: раньше и бейдж,
            // и заголовок блока обещали все записи, а отправлялись первые 25 —
            // модель получала «81 записей» и видела 25.
            let sent = todayEntries.prefix(25)
            if !sent.isEmpty {
                let suffix = todayEntries.count > sent.count ? " из \(todayEntries.count)" : ""
                badges.append("Диктовки сегодня (\(sent.count)\(suffix))")
                var text = "### Диктовки за сегодня (последние \(sent.count) записей):\n"
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                for e in sent {
                    let time = formatter.string(from: e.date)
                    let kind = e.kind == .dictation ? "" : " (\(e.kind.title))"
                    text += "• [\(time)]\(kind): «\(e.text)»\n"
                }
                contextBlocks.append(text)
            }
        }

        // 2. Все последние диктовки (если не только сегодня)
        if sources.contains(.dictationRecent) && !sources.contains(.dictationToday) {
            let entries = History.shared.entries.prefix(30)
            if !entries.isEmpty {
                badges.append("История диктовок (\(entries.count))")
                var text = "### Последние диктовки (\(entries.count) записей):\n"
                let formatter = DateFormatter()
                formatter.dateFormat = "d MMM, HH:mm"
                for e in entries {
                    let time = formatter.string(from: e.date)
                    let kind = e.kind == .dictation ? "" : " (\(e.kind.title))"
                    text += "• [\(time)]\(kind): «\(e.text)»\n"
                }
                contextBlocks.append(text)
            }
        }

        // 3. Apple Notes
        if sources.contains(.appleNotes) {
            group.enter()
            let folder = AppSettings.shared.voiceNotesFolder
            AppleNotesService.fetchRecentNotes(folderName: folder, limit: 12) { notes in
                if !notes.isEmpty {
                    badges.append("Apple Notes (\(notes.count))")
                    var text = "### Заметки из Apple Notes (папка «\(folder)»):\n"
                    for n in notes {
                        let bodySnippet = n.body.prefix(300).replacingOccurrences(of: "\n", with: " ")
                        text += "• Заметка «\(n.name)» (\(n.date)): \(bodySnippet)\n"
                    }
                    contextBlocks.append(text)
                }
                group.leave()
            }
        }

        // 4. Apple Reminders
        if sources.contains(.appleReminders) {
            group.enter()
            AppleRemindersService.fetchPendingReminders { reminders in
                let pending = reminders.filter { !$0.isCompleted }.prefix(15)
                if !pending.isEmpty {
                    badges.append("Напоминания (\(pending.count))")
                    var text = "### Текущие напоминания Apple Reminders:\n"
                    let formatter = DateFormatter()
                    formatter.dateFormat = "d MMM в HH:mm"
                    for r in pending {
                        let due = r.dueDate.map { " (срок: \(formatter.string(from: $0)))" } ?? ""
                        text += "• [ ] \(r.title)\(due)\n"
                    }
                    contextBlocks.append(text)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(contextBlocks.joined(separator: "\n\n"), badges)
        }
    }
}
