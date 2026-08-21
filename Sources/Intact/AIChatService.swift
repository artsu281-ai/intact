import Foundation
import Combine

/// Сообщение в окне чата Intact.
struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: AIMessage.Role
    let content: String
    let timestamp: Date
    let contextBadges: [String]

    init(role: AIMessage.Role, content: String, contextBadges: [String] = []) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.contextBadges = contextBadges
    }
}

// Conformance for Codable AIMessage.Role
extension AIMessage.Role: Codable {}

/// Источник контекста для анализа
enum AIContextSource: String, CaseIterable, Identifiable {
    case dictationToday = "Диктовки за сегодня"
    case dictationRecent = "Все диктовки"
    case appleNotes = "Заметки Apple Notes"
    case appleReminders = "Напоминания"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dictationToday, .dictationRecent: return "waveform"
        case .appleNotes: return "note.text"
        case .appleReminders: return "checklist"
        }
    }
}

/// Сервис управления сессией чата с ИИ и контекстным анализом заметок и истории.
final class AIChatService: ObservableObject {
    static let shared = AIChatService()

    @Published var messages: [ChatMessage] = []
    @Published var isGenerating: Bool = false
    @Published var errorMessage: String? = nil
    @Published var selectedContextSources: Set<AIContextSource> = [.dictationToday, .appleNotes]

    private let baseSystemPrompt = """
    Ты — интеллектуальный персональный ассистент Intact, встроенный в macOS-приложение для голосовой диктовки и работы с заметками.
    Твоя цель: помогать пользователю формулировать мысли, анализировать его голосовые записи (диктовки), структурировать заметки и напоминания, выделять задачи и отвечать на любые вопросы.
    Форматируй ответы красиво и чётко с использованием Markdown (списки, жирный шрифт, заголовки, блоки кода при необходимости).
    Отвечай на языке запроса пользователя (по умолчанию на русском).
    """

    private init() {}

    /// Очистить историю диалога
    func clearHistory() {
        messages.removeAll()
        errorMessage = nil
    }

    /// Отправить сообщение пользователя
    func send(prompt: String, forceContext: Set<AIContextSource>? = nil) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        errorMessage = nil
        let contextToUse = forceContext ?? selectedContextSources

        // Асинхронно собираем контекст
        gatherContext(sources: contextToUse) { [weak self] contextText, badges in
            guard let self else { return }

            let userMsg = ChatMessage(role: .user, content: trimmed, contextBadges: badges)
            self.messages.append(userMsg)
            self.isGenerating = true

            // Собираем историю сообщений для AIRouter
            var aiMessages: [AIMessage] = []

            // System prompt + прикрепленный контекст
            var systemContent = self.baseSystemPrompt
            if !contextText.isEmpty {
                systemContent += "\n\n=== АКТУАЛЬНЫЙ КОНТЕКСТ ПОЛЬЗОВАТЕЛЯ ===\n\(contextText)\n=== КОНЕЦ КОНТЕКСТА ==="
            }
            aiMessages.append(AIMessage(role: .system, content: systemContent))

            // Добавляем историю текущего диалога
            for m in self.messages {
                aiMessages.append(AIMessage(role: m.role, content: m.content))
            }

            AIRouter.shared.complete(messages: aiMessages, maxTokens: 2048) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isGenerating = false
                    switch result {
                    case .success(let answer):
                        let assistantMsg = ChatMessage(role: .assistant, content: answer.trimmingCharacters(in: .whitespacesAndNewlines))
                        self.messages.append(assistantMsg)
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - Быстрые действия

    /// Анализ диктовок за сегодня
    func analyzeTodayDictations() {
        send(prompt: "Сделай краткую структурированную сводку моих голосовых диктовок за сегодня. Выдели ключевые темы, мысли и важные решения.", forceContext: [.dictationToday])
    }

    /// Извлечение задач и TODO
    func extractTasksFromHistoryAndNotes() {
        send(prompt: "Проанализируй мои последние диктовки и заметки. Найди все прямые и неявные задачи, поручения, идеи и договоренности. Сформируй удобный список TODO с приоритетами.", forceContext: [.dictationToday, .appleNotes, .appleReminders])
    }

    /// Обзор заметок Apple Notes
    func summarizeNotes() {
        send(prompt: "Проанализируй мои заметки из Apple Notes. Сделай краткую выжимку по главным темам и проектам.", forceContext: [.appleNotes])
    }

    // MARK: - Сборщик контекста

    private func gatherContext(sources: Set<AIContextSource>, completion: @escaping (String, [String]) -> Void) {
        var contextBlocks: [String] = []
        var badges: [String] = []
        let group = DispatchGroup()

        // 1. Диктовки за сегодня
        if sources.contains(.dictationToday) {
            let todayEntries = History.shared.entries.filter { Calendar.current.isDateInToday($0.date) }
            if !todayEntries.isEmpty {
                badges.append("Диктовки сегодня (\(todayEntries.count))")
                var text = "### Диктовки за сегодня (\(todayEntries.count) записей):\n"
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                for e in todayEntries.prefix(25) {
                    let time = formatter.string(from: e.date)
                    text += "• [\(time)]: «\(e.text)»\n"
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
                    text += "• [\(time)]: «\(e.text)»\n"
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
