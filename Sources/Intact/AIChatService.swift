import Foundation
import Combine

/// Сообщение в окне чата Intact.
struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: AIMessage.Role
    var content: String
    let timestamp: Date
    let contextBadges: [String]
    /// Ответ ещё печатается. Состояние временное — на диск не пишется,
    /// поэтому исключено из ключей кодирования.
    var isStreaming: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, contextBadges
    }

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
}

/// Файл или папка, которые пользователь явно выбрал через диалог macOS
/// и прикрепил к чату. Доступ — по явному выбору в NSOpenPanel, а не
/// фоновым сканированием диска: это единственный способ дать ИИ читать
/// произвольные файлы, не выпрашивая у системы широкие права заранее.
struct AttachedFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let content: String
    var displayName: String { url.lastPathComponent }
}

/// Сервис управления сессией чата с ИИ и контекстным анализом заметок и истории.
final class AIChatService: ObservableObject {
    static let shared = AIChatService()

    /// Все диалоги, свежие сверху.
    @Published private(set) var threads: [ChatThread] = []
    /// Какая ветка открыта прямо сейчас.
    @Published private(set) var activeThreadID: UUID

    @Published var isGenerating: Bool = false
    @Published var errorMessage: String? = nil
    @Published var selectedContextSources: Set<AIContextSource> = [.dictationToday, .appleNotes]
    /// Файлы/папки, прикреплённые пользователем через диалог выбора — живут,
    /// пока открыт чат, на диск не пишутся.
    @Published var attachedFiles: [AttachedFile] = []

    /// Переписка активной ветки.
    ///
    /// Вычисляемое свойство, а не хранимое: весь остальной код обращается
    /// к `chat.messages` ровно как раньше и ничего не знает про ветки.
    var messages: [ChatMessage] {
        get { threads.first(where: { $0.id == activeThreadID })?.messages ?? [] }
        set {
            guard let index = threads.firstIndex(where: { $0.id == activeThreadID }) else { return }
            threads[index].messages = newValue
            threads[index].updatedAt = Date()
            persist()
        }
    }

    var activeThread: ChatThread? {
        threads.first(where: { $0.id == activeThreadID })
    }

    private let baseSystemPrompt = """
    Ты — интеллектуальный персональный ассистент Intact, встроенный в macOS-приложение для голосовой диктовки и работы с заметками.
    Твоя цель: помогать пользователю формулировать мысли, анализировать его голосовые записи (диктовки), структурировать заметки и напоминания, выделять задачи и отвечать на любые вопросы.
    Форматируй ответы разметкой Markdown: заголовки, списки, жирный шрифт.
    Любой код, команду терминала или конфигурацию оборачивай в тройные обратные кавычки     и обязательно указывай язык сразу после открывающих кавычек (```swift, ```bash, ```json).     Приложение показывает такие блоки отдельно, с кнопкой копирования, — без указания языка     заголовок блока будет пустым.
    Отвечай на языке запроса пользователя (по умолчанию на русском).
    """

    private init() {
        let stored = ChatThreadStore.load().sorted { $0.updatedAt > $1.updatedAt }
        if let first = stored.first {
            threads = stored
            activeThreadID = first.id
        } else {
            let fresh = ChatThread()
            threads = [fresh]
            activeThreadID = fresh.id
        }
    }

    // MARK: - Ветки диалога

    /// Открывает новый диалог. Если текущий ещё пуст, переиспользуем его —
    /// иначе список засоряется пустыми «Новый чат» от каждого нажатия.
    func newThread() {
        errorMessage = nil
        if let active = activeThread, active.isEmpty {
            return
        }
        let fresh = ChatThread()
        threads.insert(fresh, at: 0)
        activeThreadID = fresh.id
    }

    func select(_ id: UUID) {
        guard threads.contains(where: { $0.id == id }) else { return }
        errorMessage = nil
        activeThreadID = id
    }

    func rename(_ id: UUID, to title: String) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        threads[index].title = trimmed.isEmpty ? ChatThread.untitled : trimmed
        persist()
    }

    func delete(_ id: UUID) {
        threads.removeAll { $0.id == id }
        if threads.isEmpty {
            let fresh = ChatThread()
            threads = [fresh]
            activeThreadID = fresh.id
        } else if activeThreadID == id {
            activeThreadID = threads[0].id
        }
        persist()
    }

    /// Очистить переписку текущей ветки, не удаляя саму ветку.
    func clearHistory() {
        messages.removeAll()
        if let index = threads.firstIndex(where: { $0.id == activeThreadID }) {
            threads[index].title = ChatThread.untitled
            threads[index].modelLabel = nil
        }
        errorMessage = nil
        persist()
    }

    /// Запись на диск уходит с главного потока: переписка растёт, а `persist()`
    /// вызывается на каждое сообщение — синхронный файловый ввод-вывод здесь
    /// подтормаживал бы набор текста.
    /// Дописывает очередной кусочек ответа. Первый кусок создаёт сообщение,
    /// остальные наращивают его текст.
    ///
    /// На диск здесь не пишем: сохранение на каждый токен — это сотни записей
    /// в секунду. Итог сохраняется один раз в `finishStreaming`.
    private func appendDelta(_ piece: String, to threadID: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }

        if let last = threads[index].messages.last, last.role == .assistant, last.isStreaming {
            threads[index].messages[threads[index].messages.count - 1].content += piece
        } else {
            var message = ChatMessage(role: .assistant, content: piece)
            message.isStreaming = true
            threads[index].messages.append(message)
        }
        threads[index].updatedAt = Date()
    }

    /// Снимает пометку «печатается» и сохраняет результат.
    /// Пустой ответ (обрыв до первого токена) не оставляем висеть в переписке.
    private func finishStreaming(in threadID: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }),
              let last = threads[index].messages.last,
              last.role == .assistant, last.isStreaming else { return }

        let trimmed = last.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            threads[index].messages.removeLast()
        } else {
            threads[index].messages[threads[index].messages.count - 1].content = trimmed
            threads[index].messages[threads[index].messages.count - 1].isStreaming = false
        }
        persist()
    }

    private func persist() {
        let snapshot = threads
        Self.persistQueue.async { ChatThreadStore.save(snapshot) }
    }

    private static let persistQueue = DispatchQueue(label: "com.artsu.intact.chat-threads", qos: .utility)

    /// Поднимает ветку наверх списка и подписывает её по первой реплике.
    private func touchActiveThread(firstPrompt: String?) {
        guard let index = threads.firstIndex(where: { $0.id == activeThreadID }) else { return }
        if let firstPrompt, threads[index].title == ChatThread.untitled {
            threads[index].title = ChatThread.autoTitle(from: firstPrompt)
        }
        threads[index].updatedAt = Date()
        threads[index].modelLabel = AIModelCatalog.title(for: AIModelCatalog.current)

        let thread = threads.remove(at: index)
        threads.insert(thread, at: 0)
        persist()
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

            let isFirstInThread = self.messages.isEmpty
            let userMsg = ChatMessage(role: .user, content: trimmed, contextBadges: badges)
            self.messages.append(userMsg)
            self.touchActiveThread(firstPrompt: isFirstInThread ? trimmed : nil)
            self.isGenerating = true

            // Ветка, в которой задан вопрос: ответ вернётся именно сюда,
            // даже если пользователь тем временем откроет другой диалог.
            let targetThreadID = self.activeThreadID

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

            // Лимит подняли с 2048: на этом пороге модель обрывала ответ
            // посреди HTML-страницы с причиной остановки «length».
            AIRouter.shared.stream(
                messages: aiMessages,
                maxTokens: 4096,
                onDelta: { [weak self] piece in
                    DispatchQueue.main.async {
                        self?.appendDelta(piece, to: targetThreadID)
                    }
                },
                completion: { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.isGenerating = false
                        self.finishStreaming(in: targetThreadID)
                        if case .failure(let error) = result {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                }
            )
        }
    }

    // MARK: - Быстрые действия

    /// Анализ диктовок за сегодня.
    /// Каждый быстрый анализ открывает свою ветку: иначе сводка падала бы
    /// в середину постороннего разговора.
    func analyzeTodayDictations() {
        newThread()
        send(prompt: "Сделай краткую структурированную сводку моих голосовых диктовок за сегодня. Выдели ключевые темы, мысли и важные решения.", forceContext: [.dictationToday])
    }

    /// Извлечение задач и TODO
    func extractTasksFromHistoryAndNotes() {
        newThread()
        send(prompt: "Проанализируй мои последние диктовки и заметки. Найди все прямые и неявные задачи, поручения, идеи и договоренности. Сформируй удобный список TODO с приоритетами.", forceContext: [.dictationToday, .appleNotes, .appleReminders])
    }

    /// Обзор заметок Apple Notes
    func summarizeNotes() {
        newThread()
        send(prompt: "Проанализируй мои заметки из Apple Notes. Сделай краткую выжимку по главным темам и проектам.", forceContext: [.appleNotes])
    }

    // MARK: - Прикреплённые файлы

    private static let maxFileBytes = 200_000
    private static let maxTotalAttachedBytes = 600_000
    private static let maxFilesPerFolder = 40
    private static let readableExtensions: Set<String> = [
        "txt", "md", "markdown", "swift", "py", "js", "ts", "json", "yaml", "yml",
        "csv", "log", "html", "css", "xml", "sh", "c", "cpp", "h", "m", "java", "go", "rs"
    ]
    private static let skippedPathComponents: Set<String> = [
        "node_modules", ".git", ".build", "Pods", "DerivedData", ".venv"
    ]

    /// Читает файл(ы) или папки, выбранные в NSOpenPanel, и добавляет как контекст чата.
    /// Папки разбираются не рекурсивно-бесконечно, а с потолком на число файлов и общий
    /// объём — иначе один клик по домашней папке мог бы утащить в промпт гигабайты текста.
    func attachFiles(urls: [URL]) {
        var totalBytes = attachedFiles.reduce(0) { $0 + $1.content.utf8.count }
        for base in urls {
            for fileURL in Self.collectReadableFiles(from: base) {
                guard totalBytes < Self.maxTotalAttachedBytes else { return }
                guard !attachedFiles.contains(where: { $0.url == fileURL }) else { continue }
                guard let text = Self.readTextFile(fileURL) else { continue }
                attachedFiles.append(AttachedFile(url: fileURL, content: text))
                totalBytes += text.utf8.count
            }
        }
    }

    func removeAttachedFile(_ id: UUID) {
        attachedFiles.removeAll { $0.id == id }
    }

    func clearAttachedFiles() {
        attachedFiles.removeAll()
    }

    private static func collectReadableFiles(from url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else { return [url] }

        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for case let item as URL in enumerator {
            if results.count >= maxFilesPerFolder { break }
            if item.pathComponents.contains(where: { skippedPathComponents.contains($0) }) { continue }
            guard readableExtensions.contains(item.pathExtension.lowercased()) else { continue }
            results.append(item)
        }
        return results
    }

    private static func readTextFile(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.intValue, size > 0, size <= maxFileBytes * 4 else { return nil }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
        return String(text.prefix(maxFileBytes))
    }

    // MARK: - Сборщик контекста

    private func gatherContext(sources: Set<AIContextSource>, completion: @escaping (String, [String]) -> Void) {
        var contextBlocks: [String] = []
        var badges: [String] = []
        let group = DispatchGroup()

        // 0. Прикреплённые файлы — не завязаны на toggle-источники, добавляются всегда.
        if !attachedFiles.isEmpty {
            badges.append("Файлы (\(attachedFiles.count))")
            var text = "### Прикреплённые файлы:\n"
            for f in attachedFiles {
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
