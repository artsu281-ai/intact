import AppKit
import Foundation

/// То, что движку нужно от контроллера диктовки. Реализует `DictationController`
/// (расширение в его файле — там доступны приватные члены).
protocol AssistantHost: AnyObject {
    /// Строка в пилюле, пока ассистент думает; nil — обычная подпись.
    func assistantStatus(_ line: String?)
    /// Вернуть диктовку в покой ДО инструментов: пользователь может сразу нажать снова.
    func assistantGoIdle()
    /// Доставить текст в приложение, где нажимали клавишу. `mayActivate: false` — не
    /// выдёргивать его вперёд (ответ пришёл через секунды). Состояние диктовки не трогает:
    /// если уже идёт новая запись, отказывает (`done(false)`), и текст уходит на карточку.
    func assistantDeliverText(_ text: String, target: NSRunningApplication?, mayActivate: Bool, done: @escaping (Bool) -> Void)
    /// [Повторить]: новый прогон через контроллер — с пилюлей, ⎋ и сторожем.
    func assistantRetry(utterance: String, context: AssistantContext)
    /// Показать карточку (nil — убрать). `seconds` — через сколько она закроется сама.
    func assistantPresent(_ card: AssistantCard?, seconds: Int)
    /// Одна запись в истории и «последних ответах».
    func assistantRecord(question: String, answer: String)
}

/// Один прогон ассистента: его можно отменить ⎋.
final class AssistantRun {
    fileprivate let number: Int
    fileprivate var task: AITask?
    fileprivate(set) var cancelled = false
    /// Ждёт ответа Gemini (между отправкой хода и его завершением) — только тогда его
    /// вправе оборвать сторож контроллера.
    fileprivate(set) var awaitingTurn = false
    fileprivate init(number: Int) { self.number = number }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        task?.cancel()
    }
}

/// Ассистент правого ⌘: фраза → один ход Gemini → план → исполнение на этом Mac.
///
/// Все решения — на главном потоке; инструменты — на своей последовательной очереди.
/// Любая асинхронная запись сверяет номер прогона (тот же приём, что `recordingGeneration`
/// в DictationController, AGENTS_SYNC §3): поздний ответ отменённого прогона ничего не трогает.
final class AssistantEngine {
    static let shared = AssistantEngine()

    private let settings = AppSettings.shared
    private let toolQueue = DispatchQueue(label: "intact.assistant.tools", qos: .userInitiated)
    private weak var host: AssistantHost?

    private var runCounter = 0
    private var currentRun: AssistantRun?
    private var memory = AssistantMemory()
    private var journal: [JournalEntry] = []
    private var refCounter = 0
    private var pending: PendingPlan?
    private var clarifyingSince: Date?
    /// Ссылки, выполненные последним прогоном: [Отменить] и «отмени» откатывают их.
    private var lastRunRefs: [String] = []
    /// Прогон, чьи инструменты ещё работают: «отмени» в это время относится к нему.
    private var executingRun: AssistantRun?
    private var undoAfterExecution = false
    /// Текст, который показывает текущая карточка — для [Скопировать] / [Вставить].
    private var cardText: String?
    private var cardQuery: String?
    private var retryRequest: (utterance: String, context: AssistantContext)?
    /// Куда вставлять по кнопке [Вставить] — приложение того запроса, чей ответ на карточке.
    private var lastTarget: NSRunningApplication?

    /// Сколько живут память и журнал.
    private let exchangeTTL: TimeInterval = 180
    private let journalTTL: TimeInterval = 600
    private let pendingTTL: TimeInterval = 30
    private let clarifyTTL: TimeInterval = 60
    /// Ход Gemini: генерация 4–6 с по замерам, запас на длинные ответы.
    private let turnTimeout: TimeInterval = 35

    private init() {}

    // MARK: - Вход

    @discardableResult
    func handle(utterance: String, context: AssistantContext, host: AssistantHost) -> AssistantRun {
        self.host = host
        expireMemory()
        runCounter += 1
        let run = AssistantRun(number: runCounter)
        currentRun = run
        let started = Date()

        // Локальные фразы — без Gemini: подтверждение, отказ, «отмени».
        if let local = localPhrase(utterance) {
            Log.write("Ассистент[\(run.number)]: локальная фраза «\(local)»")
            switch local {
            case "yes":
                if let plan = pending {
                    pending = nil
                    // «Да» сказано в другом окне — но текст идёт туда, где был запрос.
                    retryRequest = (plan.utterance, plan.context)
                    execute(plan.plan, context: plan.context, utterance: plan.utterance, run: run)
                }
            case "no":
                pending = nil
                host.assistantGoIdle()
                present(.summary(lines: [AssistantCardLine(ok: true, text: T("Отменено", "Cancelled"))], canUndo: false), seconds: 2)
            case "dismissClarify":
                memory.clarifying = nil
                clarifyingSince = nil
                host.assistantGoIdle()
                closeCard()
            default:
                undoLastRun(run: run, fromVoice: true)
            }
            return run
        }
        retryRequest = (utterance, context)

        // Любая другая фраза при ожидающем подтверждении — поправка к нему: строка
        // «ждёт подтверждения» идёт в промпт только от живого плана и один раз.
        var pendingLine: String?
        if let plan = pending {
            if Date().timeIntervalSince(plan.at) < pendingTTL { pendingLine = describe(plan.plan) }
            pending = nil
        }
        if let since = clarifyingSince, Date().timeIntervalSince(since) > clarifyTTL {
            memory.clarifying = nil
            clarifyingSince = nil
        }

        let id = AssistantPrompt.newId()
        var promptMemory = memory
        promptMemory.pendingConfirmation = pendingLine
        promptMemory.recentActions = journal.filter { Date().timeIntervalSince($0.at) < journalTTL }
            .map { AssistantRecentAction(ref: $0.ref, summary: $0.summary, at: $0.at) }
        let prompt = AssistantPrompt.build(id: id, utterance: utterance, context: context, memory: promptMemory,
                                           windowContext: settings.assistantSendWindowContext)
        memory.clarifying = nil
        clarifyingSince = nil

        let parseContext = AssistantParseContext(
            id: id, now: context.now, timeZone: context.timeZone, utterance: utterance,
            // Замена выделения валидна, только если промпт её предложил: выделение, которое
            // Gemini видел лишь частично, заменять нельзя.
            hasSelection: AssistantPrompt.offersReplace(in: prompt),
            knownRefs: Set(promptMemory.recentActions.map(\.ref)))

        host.assistantStatus(statusLine(utterance, suffix: T("думаю…", "thinking…"), context: context))
        Log.write("Ассистент[\(run.number)]: запрос \(utterance.count) симв., промпт \(prompt.count) симв."
                  + (context.selection != nil ? ", с выделением \(context.selection!.count)" : "")
                  + (context.selectionDropReason.map { ", выделение отброшено: \($0)" } ?? ""))

        run.awaitingTurn = true
        run.task = GeminiAIProvider.shared.runTurn(
            prompt: prompt, id: id, timeout: turnTimeout,
            isComplete: { text in
                // Досрочно — только чистый план без ссылок на длинный текст: блок ```text
                // ещё может дописываться.
                guard !text.contains("\"@") else { return false }
                if case .plan(let plan) = AssistantParser.extract(answer: text, context: parseContext) {
                    return !plan.hasHeavyRepairs
                }
                return false
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    run.awaitingTurn = false
                    guard let self, self.currentRun === run, !run.cancelled else { return }
                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    switch result {
                    case .failure(let error):
                        Log.write("Ассистент[\(run.number)]: Gemini не ответил (\(error.localizedDescription)) за \(ms) мс")
                        host.assistantGoIdle()
                        let message: String
                        switch error {
                        case .timeout: message = T("Gemini не ответил вовремя.", "Gemini didn't answer in time.")
                        default: message = T("Gemini недоступен: окно закрыто или занято другим ответом.",
                                             "Gemini is unavailable: its window is closed or busy with another answer.")
                        }
                        self.present(.error(message: message, query: utterance, permission: nil), seconds: 12, query: utterance)
                        if self.settings.playSounds { NSSound(named: "Basso")?.play() }
                    case .success(let answer):
                        let verdict = AssistantParser.extract(answer: answer, context: parseContext)
                        Log.write("Ассистент[\(run.number)]: вердикт \(Self.describe(verdict)) за \(ms) мс")
                        self.decide(verdict, context: context, utterance: utterance, run: run)
                    }
                }
            })
        return run
    }

    /// ⎋ во время ожидания Gemini (или сторож контроллера, `timedOut: true`).
    func cancelCurrent(timedOut: Bool = false) {
        guard let run = currentRun, !run.cancelled else { return }
        run.cancel()
        Log.write("Ассистент[\(run.number)]: \(timedOut ? "сторож: ход завис" : "отменён")")
        host?.assistantGoIdle()
        if timedOut {
            present(.error(message: T("Gemini не ответил вовремя.", "Gemini didn't answer in time."), query: retryRequest?.utterance, permission: nil),
                    seconds: 12, query: retryRequest?.utterance)
        } else {
            present(.summary(lines: [AssistantCardLine(ok: true, text: T("Отменено", "Cancelled"))], canUndo: false), seconds: 1)
        }
    }

    /// Сторож контроллера: обрывает только СВОЙ прогон и только пока тот ждёт Gemini —
    /// по состоянию `.answeringAI` судить нельзя, его ставят и другие пайплайны.
    func timeOut(_ run: AssistantRun) {
        guard currentRun === run, run.awaitingTurn, !run.cancelled else { return }
        cancelCurrent(timedOut: true)
    }

    /// Ассистент не может начать (нет Gemini, нет копии) — карточка через движок, чтобы
    /// её кнопки и таймер работали, даже если прогонов ещё не было.
    func showProblem(_ message: String, utterance: String, context: AssistantContext, host: AssistantHost) {
        self.host = host
        retryRequest = (utterance, context)
        present(.error(message: message, query: utterance, permission: nil), seconds: 12, query: utterance)
        playSound("Basso")
    }

    /// Есть план, который ждёт «да».
    var hasPendingConfirmation: Bool {
        guard let plan = pending else { return false }
        return Date().timeIntervalSince(plan.at) < pendingTTL
    }

    /// ⎋, пока показана карточка: закрыть; для подтверждения это «нет».
    func dismissCard() {
        pending = nil
        AssistantTimers.shared.silence()
        closeCard()
    }

    /// Карточка закрылась по таймеру.
    func cardExpired() {
        if pending != nil {
            Log.write("Ассистент: подтверждение не пришло — план отменён")
            pending = nil
        }
        closeCard()
    }

    /// Нажата клавиша другого пайплайна — ожидающее подтверждение отменяется (по умолчанию «нет»).
    func dropPending() {
        guard pending != nil else { return }
        Log.write("Ассистент: подтверждение отменено нажатием другой клавиши")
        pending = nil
    }

    // MARK: - Решение

    private func decide(_ verdict: AssistantVerdict, context: AssistantContext, utterance: String, run: AssistantRun) {
        guard let host else { return }
        switch verdict {
        case .noPlan(let prose):
            host.assistantGoIdle()
            showAnswer(prose, query: utterance, context: context)

        case .stale:
            host.assistantGoIdle()
            present(.error(message: T("Gemini ответил не на этот запрос — повторите.", "Gemini answered a different request — please retry."),
                           query: utterance, permission: nil), seconds: 12, query: utterance)
            playSound("Basso")

        case .invalid(_, let reason):
            host.assistantGoIdle()
            Log.write("Ассистент[\(run.number)]: план невалиден — \(reason)")
            // Фразу Gemini не показываем: она обычно про действие, которое не выполнено
            // («Перевёл…», «Удалю…»), и ввела бы в заблуждение.
            present(.error(message: T("Не понял ответ Gemini — скажите иначе.", "Couldn't read Gemini's answer — try saying it differently."),
                           query: utterance, permission: nil), seconds: 12, query: utterance)
            playSound("Basso")

        case .plan(let plan):
            if plan.steps.isEmpty {
                host.assistantGoIdle()
                showAnswer(plan.say.isEmpty ? T("Готово.", "Done.") : plan.say, query: utterance, context: context)
                return
            }
            if let question = plan.steps.compactMap({ step -> String? in
                if case .clarify(let q) = step { return q } else { return nil }
            }).first {
                host.assistantGoIdle()
                memory.clarifying = utterance
                clarifyingSince = Date()
                present(.clarify(question: question), seconds: Int(clarifyTTL))
                playSound("Purr")
                return
            }
            if needsConfirmation(plan, context: context) {
                host.assistantGoIdle()
                pending = PendingPlan(plan: plan, context: context, utterance: utterance, at: Date())
                let reason: String? = plan.hasHeavyRepairs
                    ? T("Ответ Gemini пришлось чинить — проверьте.", "Gemini's answer needed repair — please check.")
                    : (settings.assistantConfirmAll ? nil : T("Это действие требует подтверждения.", "This action needs confirmation."))
                present(.confirm(lines: plan.steps.map(preview), reason: reason), seconds: 20)
                playSound("Purr")
                return
            }
            execute(plan, context: context, utterance: utterance, run: run)
        }
    }

    private func needsConfirmation(_ plan: AssistantPlan, context: AssistantContext) -> Bool {
        if settings.assistantConfirmAll && plan.hasActions { return true }
        if plan.hasHeavyRepairs && plan.hasActions { return true }
        for step in plan.steps {
            if case .urlOpen(let url) = step, !AssistantURLPolicy.isTrusted(url) { return true }
            if step.isTextDelivery, context.isTerminal { return true }
        }
        return false
    }

    private func showAnswer(_ text: String, query: String, context: AssistantContext) {
        lastTarget = context.targetApp
        memory.lastExchange = AssistantExchange(question: query, answer: text, at: Date())
        host?.assistantRecord(question: query, answer: text)
        let seconds = min(60, 20 + text.count / 25)
        present(.answer(query: query, text: text, canInsert: context.hasTextField), seconds: seconds, text: text, query: query)
        playSound("Purr")
    }

    // MARK: - Исполнение

    private func execute(_ plan: AssistantPlan, context: AssistantContext, utterance: String, run: AssistantRun) {
        guard let host else { return }
        host.assistantGoIdle()
        // «Отмени», сказанное пока работают инструменты, — про ЭТОТ прогон, а не прошлый.
        executingRun = run
        lastRunRefs = []
        let actionSteps = plan.steps.filter { !$0.isTextDelivery }
        let textStep = plan.steps.last(where: { $0.isTextDelivery })
        // Журнал — состояние главного потока; инструменты получают его копию.
        let journalSnapshot = journal

        toolQueue.async { [weak self] in
            guard let self else { return }
            var receipts: [AssistantReceipt] = []
            for step in actionSteps {
                if run.cancelled { break }
                let receipt = self.perform(step, context: context, journal: journalSnapshot)
                receipts.append(receipt)
                if !receipt.ok { break }   // остановка на первой ошибке
            }
            // Текстовый шаг — последним и только если всё до него удалось.
            let canDeliverText = receipts.allSatisfy(\.ok) && !run.cancelled
            var replaceStillValid = true
            if canDeliverText, let textStep {
                // Окно должно быть тем же, где был запрос (другая вкладка или чат в том же
                // приложении — это уже не то поле), а для замены — и выделение тем же.
                let isReplace: Bool = { if case .textReplace = textStep { return true } else { return false } }()
                let now = AssistantContext.capture(target: context.targetApp ?? NSWorkspace.shared.frontmostApplication,
                                                   sendSelection: isReplace)
                let sameWindow = context.windowTitle == nil || now.windowTitle == context.windowTitle
                let sameSelection = !isReplace || (now.selectionFingerprint != nil && now.selectionFingerprint == context.selectionFingerprint)
                replaceStillValid = sameWindow && sameSelection
            }
            DispatchQueue.main.async {
                self.finishExecution(plan: plan, receipts: receipts, textStep: canDeliverText ? textStep : nil,
                                     replaceStillValid: replaceStillValid, utterance: utterance, context: context, run: run)
            }
        }
    }

    private func finishExecution(plan: AssistantPlan, receipts: [AssistantReceipt], textStep: AssistantStep?,
                                 replaceStillValid: Bool, utterance: String, context: AssistantContext, run: AssistantRun) {
        // Журнал: у каждого удавшегося шага с обратной операцией — своя ссылка.
        var refs: [String] = []
        var journaled: [AssistantReceipt] = []
        for receipt in receipts where receipt.ok {
            if case .undo(let ref) = receipt.step { journal.removeAll { $0.ref == ref } }
        }
        for var receipt in receipts {
            if receipt.ok, let undo = receipt.undo {
                refCounter += 1
                let ref = "A\(refCounter)"
                receipt.ref = ref
                journal.append(JournalEntry(ref: ref, summary: receipt.memorySummary ?? receipt.line, at: Date(),
                                            step: receipt.step, undo: undo, itemID: receipt.itemID,
                                            guardBox: receipt.guardBox))
                refs.append(ref)
            }
            journaled.append(receipt)
        }
        // «Отмени» — про последний выполненный запрос, даже если отменять в нём нечего.
        lastRunRefs = refs
        if executingRun === run { executingRun = nil }
        if undoAfterExecution {
            undoAfterExecution = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.runCounter += 1
                self.undoLastRun(run: AssistantRun(number: self.runCounter), fromVoice: true)
            }
        }

        var lines = journaled.map { AssistantCardLine(ok: $0.ok, text: $0.ok ? $0.line : ($0.error?.message ?? $0.line)) }
        let failedPermission = journaled.first(where: { !$0.ok })?.error?.permission
        let drafts = plan.steps.compactMap { step -> (String, String)? in
            if case .messageDraft(let to, let text) = step { return (to, text) } else { return nil }
        }

        let complete: (Bool?) -> Void = { [weak self] textLanded in
            guard let self else { return }
            if let landed = textLanded {
                lines.append(AssistantCardLine(ok: landed, text: landed
                    ? (textStep.map { if case .textReplace = $0 { return T("Выделение заменено · ⌘Z — вернуть", "Selection replaced · ⌘Z to undo") } else { return T("Текст вставлен", "Text inserted") } } ?? "")
                    : T("Вставить не удалось — текст на карточке", "Couldn't insert — the text is on the card")))
            }
            let anyFailed = lines.contains { !$0.ok }
            let anySucceeded = journaled.contains { $0.ok }
            if let (to, text) = drafts.first, lines.isEmpty || !anyFailed {
                self.present(.draft(to: to, text: text), seconds: 30, text: text)
                self.playSound("Purr")
            } else if !lines.isEmpty {
                if let permission = failedPermission, !anySucceeded {
                    // Ничего не выполнено — карточка ошибки с [Разрешить].
                    let message = journaled.first(where: { !$0.ok })?.error?.message ?? ""
                    self.present(.error(message: message, query: utterance, permission: permission), seconds: 15, query: utterance)
                } else {
                    // Часть выполнена — итог со всеми строками и [Отменить]; повтор всего плана
                    // создал бы уже сделанное второй раз.
                    self.present(.summary(lines: lines, canUndo: !refs.isEmpty), seconds: refs.isEmpty ? 4 : (anyFailed ? 10 : 6))
                }
                self.playSound(anyFailed ? "Basso" : "Glass")
            }
            let summary = lines.filter(\.ok).map(\.text).joined(separator: "; ")
            // Вставленный текст — то, что потом ищут в истории, если поле оказалось не тем.
            let delivered: String? = {
                guard textLanded == true, let textStep else { return nil }
                switch textStep {
                case .textInsert(let t), .textReplace(let t): return t
                default: return nil
                }
            }()
            let answer = delivered ?? (plan.say.isEmpty ? summary : plan.say)
            self.memory.lastExchange = AssistantExchange(question: utterance, answer: answer, at: Date())
            self.host?.assistantRecord(question: utterance, answer: answer)
            Log.write("Ассистент[\(run.number)]: выполнено \(journaled.filter(\.ok).count) из \(plan.steps.count) шаг(ов)"
                      + (textLanded.map { $0 ? ", текст доставлен" : ", текст не доставлен" } ?? ""))
        }

        guard let textStep else { complete(nil); return }
        let text: String
        switch textStep {
        case .textInsert(let t), .textReplace(let t): text = t
        default: complete(nil); return
        }
        if !replaceStillValid {
            Log.write("Ассистент[\(run.number)]: окно или выделение сменились — текст на карточке")
            textFallback(text, lines: &lines, reason: T("Окно сменилось", "The window changed"), utterance: utterance, refs: refs, plan: plan)
            return
        }
        host?.assistantDeliverText(text, target: context.targetApp, mayActivate: false) { [weak self] landed in
            guard let self else { return }
            if landed {
                complete(true)
            } else {
                // Некуда вставить (ушли в другое приложение, поле пропало, идёт новая
                // диктовка) — текст не теряем.
                self.textFallback(text, lines: &lines, reason: T("Вставить не удалось", "Couldn't insert"), utterance: utterance, refs: refs, plan: plan)
            }
        }
    }

    /// Текст не вставился. Если в этом запросе уже выполнены действия, они не должны
    /// пропасть с карточки вместе с [Отменить]: итог со строками, а текст — в буфер.
    /// Если действий не было — карточка с текстом и [Скопировать].
    private func textFallback(_ text: String, lines: inout [AssistantCardLine], reason: String,
                              utterance: String, refs: [String], plan: AssistantPlan) {
        host?.assistantRecord(question: utterance, answer: text)
        memory.lastExchange = AssistantExchange(question: utterance, answer: text, at: Date())
        if lines.contains(where: \.ok) {
            Clipboard.write(text, transient: false, session: nil)
            lines.append(AssistantCardLine(ok: false, text: T("\(reason) — текст скопирован в буфер", "\(reason) — the text is on the clipboard")))
            present(.summary(lines: lines, canUndo: !refs.isEmpty), seconds: 10)
        } else {
            present(.answer(query: utterance, text: text, canInsert: false), seconds: 40, text: text, query: utterance)
        }
        playSound("Basso")
    }

    /// Выполнение одного шага на очереди инструментов.
    private func perform(_ step: AssistantStep, context: AssistantContext, journal: [JournalEntry]) -> AssistantReceipt {
        let tz = context.timeZone
        func fail(_ error: Error) -> AssistantReceipt {
            let toolError = error as? AssistantToolError ?? AssistantToolError(message: error.localizedDescription)
            Log.write("Ассистент: шаг \(step.toolName) не удался — \(toolError.message)")
            return AssistantReceipt(step: step, ok: false, line: toolError.message, error: toolError)
        }
        do {
            switch step {
            case .reminderAdd(let title, let due):
                let id = try AssistantEvents.addReminder(title: title, due: due, listName: settings.voiceRemindersList, timeZone: tz)
                let box = ItemGuard(); box.reminder = try? AssistantEvents.snapshotReminder(id: id)
                let when = due.map { Self.format($0, tz: tz) } ?? T("без срока", "no due date")
                return AssistantReceipt(step: step, ok: true,
                                        line: T("Напоминание · \(title) · \(when)", "Reminder · \(title) · \(when)"),
                                        memorySummary: "напоминание «\(title)»" + (due.map { " на \(Self.iso($0, tz: tz))" } ?? ""),
                                        undo: { try Self.undoReminder(id: id, box: box) }, itemID: id, guardBox: box)

            case .calendarAdd(let title, let start, let end, let place):
                let id = try AssistantEvents.addEvent(title: title, start: start, end: end, place: place)
                let box = ItemGuard(); box.event = try? AssistantEvents.snapshotEvent(id: id)
                return AssistantReceipt(step: step, ok: true,
                                        line: T("Событие · \(title) · \(Self.format(start, tz: tz))", "Event · \(title) · \(Self.format(start, tz: tz))"),
                                        memorySummary: "событие «\(title)» на \(Self.iso(start, tz: tz))",
                                        undo: { try Self.undoEvent(id: id, box: box) }, itemID: id, guardBox: box)

            case .noteAdd(let title, let body):
                let created = try AssistantNotes.create(title: title, body: body, folder: settings.voiceNotesFolder)
                let box = ItemGuard(); box.noteModified = try? AssistantNotes.modificationDate(id: created.id)
                let folderNote = created.folder == settings.voiceNotesFolder ? "" : T(" (в папке «\(created.folder)»)", " (in “\(created.folder)”)")
                return AssistantReceipt(step: step, ok: true,
                                        line: T("Заметка · \(title)", "Note · \(title)") + folderNote,
                                        memorySummary: "заметка «\(title)»",
                                        undo: {
                                            // Заметку, которую успели поправить, не удаляем.
                                            guard let current = try AssistantNotes.modificationDate(id: created.id) else { return }
                                            if let expected = box.noteModified, abs(current.timeIntervalSince(expected)) > 5 {
                                                throw AssistantToolError(message: T("Заметку уже меняли — не трогаю", "The note was edited — leaving it alone"))
                                            }
                                            try AssistantNotes.delete(id: created.id, expectedFolder: created.folder)
                                        },
                                        itemID: created.id, guardBox: box)

            case .timerSet(let seconds, let label):
                let name = label ?? T("таймер", "timer")
                if seconds > AssistantTimers.maxSeconds {
                    // Внутренний таймер не переживёт перезапуск Intact — длинный ставим напоминанием.
                    let due = AssistantDate(date: Date().addingTimeInterval(TimeInterval(seconds)), hasTime: true)
                    let id = try AssistantEvents.addReminder(title: name, due: due, listName: settings.voiceRemindersList, timeZone: tz)
                    let box = ItemGuard(); box.reminder = try? AssistantEvents.snapshotReminder(id: id)
                    return AssistantReceipt(step: step, ok: true,
                                            line: T("Напоминание-таймер · \(name) · \(Self.format(due, tz: tz))", "Timer reminder · \(name) · \(Self.format(due, tz: tz))"),
                                            memorySummary: "таймер-напоминание «\(name)» на \(Self.iso(due, tz: tz))",
                                            undo: { try Self.undoReminder(id: id, box: box) }, itemID: id, guardBox: box)
                }
                let id = try AssistantTimers.shared.start(seconds: seconds, label: label) { [weak self] item in
                    self?.timerFired(label: item.label ?? name)
                }
                return AssistantReceipt(step: step, ok: true,
                                        line: T("Таймер · \(name) · \(Self.duration(seconds)) (пока Intact запущен)", "Timer · \(name) · \(Self.duration(seconds)) (while Intact runs)"),
                                        memorySummary: "таймер «\(name)» на \(Self.duration(seconds))",
                                        undo: { _ = AssistantTimers.shared.cancel(id: id) }, itemID: id)

            case .appOpen(let name):
                switch AppIndex.resolve(name) {
                case .found(let url, let displayName):
                    guard AppIndex.open(url: url) else {
                        return fail(AssistantToolError(message: T("Не удалось открыть «\(displayName)»", "Couldn't open “\(displayName)”")))
                    }
                    return AssistantReceipt(step: step, ok: true, line: T("Открыто · \(displayName)", "Opened · \(displayName)"))
                case .ambiguous(let names):
                    return fail(AssistantToolError(message: T("Какую программу открыть: \(names.prefix(4).joined(separator: ", "))?",
                                                              "Which app: \(names.prefix(4).joined(separator: ", "))?")))
                case .notFound:
                    return fail(AssistantToolError(message: T("Не нашёл программу «\(name)»", "Couldn't find an app called “\(name)”")))
                }

            case .urlOpen(let url):
                let opened = DispatchQueue.main.sync { NSWorkspace.shared.open(url) }
                guard opened else { return fail(AssistantToolError(message: T("Не удалось открыть ссылку", "Couldn't open the link"))) }
                return AssistantReceipt(step: step, ok: true, line: T("Открыта ссылка · \(AssistantURLPolicy.displayHost(url))", "Opened · \(AssistantURLPolicy.displayHost(url))"))

            case .volumeSet(let level):
                let previous = SystemVolume.get()
                try SystemVolume.set(level)
                return AssistantReceipt(step: step, ok: true,
                                        line: level == 0 ? T("Звук выключен", "Sound off") : T("Громкость · \(level)%", "Volume · \(level)%"),
                                        memorySummary: "громкость \(level)%",
                                        undo: previous.map { prev in { try SystemVolume.set(prev) } })

            case .edit(let ref, let title, let due, let start, let end):
                guard let entry = journal.first(where: { $0.ref == ref }) else {
                    return fail(AssistantToolError(message: T("Не нашёл, что поправить", "Nothing to change")))
                }
                guard let itemID = entry.itemID else {
                    return fail(AssistantToolError(message: T("Не нашёл, что поправить", "Nothing to change")))
                }
                // Правим только своё и только нетронутое — как и при отмене.
                func editReminder() throws -> AssistantReceipt? {
                    if let expected = entry.guardBox?.reminder, let current = try AssistantEvents.snapshotReminder(id: itemID), current != expected {
                        return fail(AssistantToolError(message: T("Напоминание уже меняли — не трогаю", "The reminder was edited — leaving it alone")))
                    }
                    try AssistantEvents.updateReminder(id: itemID, title: title, due: due ?? start, timeZone: tz)
                    entry.guardBox?.reminder = try? AssistantEvents.snapshotReminder(id: itemID)
                    return nil
                }
                switch entry.step {
                case .reminderAdd:
                    if let refused = try editReminder() { return refused }
                case .timerSet where entry.guardBox?.reminder != nil:
                    // Длинный таймер стал напоминанием — правится как напоминание.
                    if let refused = try editReminder() { return refused }
                case .calendarAdd:
                    if let expected = entry.guardBox?.event, let current = try AssistantEvents.snapshotEvent(id: itemID), current != expected {
                        return fail(AssistantToolError(message: T("Событие уже меняли — не трогаю", "The event was edited — leaving it alone")))
                    }
                    try AssistantEvents.updateEvent(id: itemID, title: title, start: start ?? due, end: end)
                    entry.guardBox?.event = try? AssistantEvents.snapshotEvent(id: itemID)
                default:
                    return fail(AssistantToolError(message: T("Это действие не поправить — отмените и скажите заново", "This can't be changed — undo and say it again")))
                }
                let when = (due ?? start).map { " · " + Self.format($0, tz: tz) } ?? ""
                return AssistantReceipt(step: step, ok: true, line: T("Изменено\(when)", "Changed\(when)"))

            case .undo(let ref):
                guard let index = journal.firstIndex(where: { $0.ref == ref }) else {
                    return fail(AssistantToolError(message: T("Отменять нечего", "Nothing to undo")))
                }
                try journal[index].undo()
                return AssistantReceipt(step: step, ok: true, line: T("Отменено · \(journal[index].summary)", "Undone · \(journal[index].summary)"))

            case .messageDraft, .clarify, .textInsert, .textReplace:
                return AssistantReceipt(step: step, ok: true, line: "")
            }
        } catch {
            return fail(error)
        }
    }

    // MARK: - Отмена

    private func undoLastRun(run: AssistantRun, fromVoice: Bool) {
        host?.assistantGoIdle()
        if executingRun != nil {
            // Инструменты прошлого запроса ещё работают — отменим его, как только закончат.
            undoAfterExecution = true
            Log.write("Ассистент: «отмени» во время выполнения — отменю после")
            return
        }
        let fresh = journal.filter { lastRunRefs.contains($0.ref) && Date().timeIntervalSince($0.at) < journalTTL }
        guard !fresh.isEmpty else {
            present(.summary(lines: [AssistantCardLine(ok: false, text: T("Отменять нечего", "Nothing to undo"))], canUndo: false), seconds: 3)
            return
        }
        let refs = Set(fresh.map(\.ref))
        toolQueue.async { [weak self] in
            guard let self else { return }
            var lines: [AssistantCardLine] = []
            for entry in fresh.reversed() {
                do {
                    try entry.undo()
                    lines.append(AssistantCardLine(ok: true, text: T("Отменено · \(entry.summary)", "Undone · \(entry.summary)")))
                } catch {
                    lines.append(AssistantCardLine(ok: false, text: (error as? AssistantToolError)?.message ?? error.localizedDescription))
                }
            }
            DispatchQueue.main.async {
                self.journal.removeAll { refs.contains($0.ref) }
                self.lastRunRefs.removeAll { refs.contains($0) }
                Log.write("Ассистент[\(run.number)]: отменено \(lines.filter(\.ok).count) действий" + (fromVoice ? " голосом" : " кнопкой"))
                self.present(.summary(lines: lines, canUndo: false), seconds: 4)
                self.playSound("Pop")
            }
        }
    }

    // MARK: - Кнопки карточек

    func handleButton(_ button: AssistantCardButton) {
        switch button {
        case .undo:
            runCounter += 1
            undoLastRun(run: AssistantRun(number: runCounter), fromVoice: false)
        case .insert:
            guard let text = cardText else { return }
            let query = cardQuery ?? ""
            closeCard()
            // Клик — явное согласие: здесь приложение можно вывести вперёд.
            host?.assistantDeliverText(text, target: lastTarget, mayActivate: true) { [weak self] landed in
                guard !landed else { return }
                self?.present(.answer(query: query, text: text, canInsert: false), seconds: 40, text: text, query: query)
                self?.playSound("Basso")
            }
        case .copy:
            if let text = cardText ?? cardQuery { Clipboard.write(text, transient: false, session: nil) }
            closeCard()
        case .confirm:
            guard let plan = pending else { closeCard(); return }
            pending = nil
            memory.pendingConfirmation = nil
            closeCard()
            runCounter += 1
            let run = AssistantRun(number: runCounter)
            currentRun = run
            execute(plan.plan, context: plan.context, utterance: plan.utterance, run: run)
        case .reject:
            dismissCard()
        case .retry:
            guard let request = retryRequest, let host else { closeCard(); return }
            closeCard()
            host.assistantRetry(utterance: request.utterance, context: request.context.withTime(Date()))
        case .dismiss, .stopTimer:
            AssistantTimers.shared.silence()
            closeCard()
        case .openSettings(let permission):
            if let url = permission.settingsURL { NSWorkspace.shared.open(url) }
            closeCard()
        case .grant(let permission):
            closeCard()
            // Запрос разрешения — только по клику, и именно тот, которого не хватило:
            // без запроса Intact даже не появится в списке Настроек.
            let (name, request): (String, (@escaping (Bool) -> Void) -> Void) = {
                switch permission {
                case .calendars: return (T("Календарю", "Calendar"), AssistantEvents.requestCalendarAccess)
                case .reminders: return (T("Напоминаниям", "Reminders"), AssistantEvents.requestRemindersAccess)
                case .automationNotes: return (T("Заметкам", "Notes"), AssistantNotes.requestAccess)
                case .notifications: return ("", { done in done(false) })
                }
            }()
            guard !name.isEmpty else {
                if let url = permission.settingsURL { NSWorkspace.shared.open(url) }
                return
            }
            request { [weak self] granted in
                DispatchQueue.main.async {
                    if !granted, let url = permission.settingsURL { NSWorkspace.shared.open(url) }
                    self?.present(.summary(lines: [AssistantCardLine(ok: granted, text: granted
                        ? T("Доступ к \(name) выдан — повторите запрос", "\(name) access granted — say it again")
                        : T("Доступ к \(name) не выдан — включите его в Настройках", "\(name) access was not granted — enable it in Settings"))], canUndo: false), seconds: 5)
                }
            }
        }
    }

    // MARK: - Таймеры

    /// Звонит сам таймер (Intact, поэтому слышно и при «Не беспокоить»); здесь — только карточка.
    private func timerFired(label: String) {
        present(.timer(label: label), seconds: 60)
    }

    // MARK: - Карточки

    private func present(_ card: AssistantCard, seconds: Int, text: String? = nil, query: String? = nil) {
        cardText = text
        cardQuery = query
        host?.assistantPresent(card, seconds: seconds)
    }

    private func closeCard() {
        cardText = nil
        cardQuery = nil
        host?.assistantPresent(nil, seconds: 0)
    }

    private func playSound(_ name: String) {
        if settings.playSounds { NSSound(named: name)?.play() }
    }

    // MARK: - Вспомогательное

    /// «да / нет / отмени» — только целой фразой, без Gemini.
    private func localPhrase(_ utterance: String) -> String? {
        let normalized = utterance.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let cancelWords: Set<String> = ["нет", "не надо", "отмена", "стоп", "не нужно", "отмени", "отмени это", "отменить", "no", "cancel"]
        // Ждёт подтверждения — любое «отмени» значит «не выполняй», а не «удали прошлое».
        if let plan = pending, Date().timeIntervalSince(plan.at) < pendingTTL {
            if ["да", "давай", "выполняй", "ок", "окей", "делай", "да давай", "подтверждаю", "yes", "ok", "okay"].contains(normalized) { return "yes" }
            if cancelWords.contains(normalized) { return "no" }
            return nil
        }
        // Открыт уточняющий вопрос — явная отмена закрывает его; «нет» — это ответ, он идёт в Gemini.
        if let since = clarifyingSince, Date().timeIntervalSince(since) < clarifyTTL,
           ["отмена", "отмени", "отмени это", "отменить", "стоп", "cancel"].contains(normalized) {
            return "dismissClarify"
        }
        if ["отмени", "отмени это", "верни как было"].contains(normalized),
           executingRun != nil || journal.contains(where: { lastRunRefs.contains($0.ref) && Date().timeIntervalSince($0.at) < journalTTL }) {
            return "undo"
        }
        return nil
    }

    private func expireMemory() {
        let now = Date()
        if let exchange = memory.lastExchange, now.timeIntervalSince(exchange.at) > exchangeTTL { memory.lastExchange = nil }
        journal.removeAll { now.timeIntervalSince($0.at) > journalTTL }
        if let plan = pending, now.timeIntervalSince(plan.at) > pendingTTL { pending = nil; memory.pendingConfirmation = nil }
    }

    private func statusLine(_ utterance: String, suffix: String, context: AssistantContext) -> String {
        let quote = utterance.count > 28 ? String(utterance.prefix(27)) + "…" : utterance
        let selection = context.selection != nil ? T(" · с выделением", " · with selection") : ""
        return "«\(quote)»\(selection) · \(suffix)"
    }

    private func preview(_ step: AssistantStep) -> String {
        let tz = TimeZone.current
        func excerpt(_ text: String) -> String {
            // Подтверждение существует, чтобы проверить текст, — показываем его, а не длину.
            let visible = text.replacingOccurrences(of: "\r", with: "⏎").replacingOccurrences(of: "\n", with: "⏎ ")
            return visible.count > 300 ? String(visible.prefix(300)) + "…" : visible
        }
        func item(_ ref: String) -> String { journal.first(where: { $0.ref == ref })?.summary ?? ref }
        switch step {
        case .textInsert(let t): return T("Вставить: «\(excerpt(t))»", "Insert: “\(excerpt(t))”")
        case .textReplace(let t): return T("Заменить выделение на: «\(excerpt(t))»", "Replace the selection with: “\(excerpt(t))”")
        case .reminderAdd(let title, let due): return T("Напоминание «\(title)»", "Reminder “\(title)”") + (due.map { " · " + Self.format($0, tz: tz) } ?? "")
        case .calendarAdd(let title, let start, _, _): return T("Событие «\(title)» · \(Self.format(start, tz: tz))", "Event “\(title)” · \(Self.format(start, tz: tz))")
        case .noteAdd(let title, _): return T("Заметка «\(title)»", "Note “\(title)”")
        case .timerSet(let s, let label): return T("Таймер \(Self.duration(s))", "Timer \(Self.duration(s))") + (label.map { " · \($0)" } ?? "")
        case .appOpen(let name): return T("Открыть «\(name)»", "Open “\(name)”")
        case .urlOpen(let url): return T("Открыть ссылку \(AssistantURLPolicy.displayHost(url))", "Open link \(AssistantURLPolicy.displayHost(url))")
        case .volumeSet(let level): return T("Громкость \(level)%", "Volume \(level)%")
        case .messageDraft(let to, _): return T("Черновик для \(to)", "Draft for \(to)")
        case .clarify(let q): return q
        case .edit(let ref, let title, let due, let start, _):
            let when = (due ?? start).map { " → " + Self.format($0, tz: tz) } ?? ""
            let rename = title.map { T(" → «\($0)»", " → “\($0)”") } ?? ""
            return T("Поправить \(item(ref))\(rename)\(when)", "Change \(item(ref))\(rename)\(when)")
        case .undo(let ref): return T("Отменить \(item(ref))", "Undo \(item(ref))")
        }
    }

    private func describe(_ plan: AssistantPlan) -> String {
        plan.steps.map(preview).joined(separator: "; ")
    }

    private static func describe(_ verdict: AssistantVerdict) -> String {
        switch verdict {
        case .plan(let p): return "план из \(p.steps.count) шаг(ов)" + (p.repairs.isEmpty ? "" : ", ремонты: \(p.repairs.map(\.rawValue).sorted().joined(separator: ","))")
        case .noPlan: return "ответ без плана"
        case .invalid(_, let reason): return "невалиден (\(reason))"
        case .stale: return "чужой id"
        }
    }

    /// «сегодня 11:43», «завтра 9:00», «чт 01.10 15:00», «пт 02.10».
    static func format(_ date: AssistantDate, tz: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let formatter = DateFormatter()
        formatter.timeZone = tz
        formatter.locale = Locale(identifier: L10n.isRu ? "ru_RU" : "en_US")
        let day: String
        if calendar.isDateInToday(date.date) { day = T("сегодня", "today") }
        else if calendar.isDateInTomorrow(date.date) { day = T("завтра", "tomorrow") }
        else { formatter.dateFormat = "EE dd.MM"; day = formatter.string(from: date.date) }
        guard date.hasTime else { return day }
        formatter.dateFormat = "H:mm"
        return "\(day) \(formatter.string(from: date.date))"
    }

    static func iso(_ date: AssistantDate, tz: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = tz
        formatter.formatOptions = date.hasTime ? [.withFullDate, .withTime, .withColonSeparatorInTime, .withTimeZone, .withDashSeparatorInDate] : [.withFullDate, .withDashSeparatorInDate]
        return formatter.string(from: date.date)
    }

    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return T("\(seconds) с", "\(seconds) s") }
        if seconds < 3600 { return T("\(seconds / 60) мин", "\(seconds / 60) min") + (seconds % 60 == 0 ? "" : T(" \(seconds % 60) с", " \(seconds % 60) s")) }
        return T("\(seconds / 3600) ч \(seconds % 3600 / 60) мин", "\(seconds / 3600) h \(seconds % 3600 / 60) min")
    }
}

extension AssistantEngine {
    /// Отмена напоминания: только если его с тех пор не меняли (синхронизация iCloud
    /// двигает дату изменения, поэтому сверяем поля, а не `lastModifiedDate`).
    fileprivate static func undoReminder(id: String, box: ItemGuard) throws {
        guard let current = try AssistantEvents.snapshotReminder(id: id) else { return }   // уже удалено
        if let expected = box.reminder, current != expected {
            throw AssistantToolError(message: T("Напоминание уже меняли — не трогаю", "The reminder was edited — leaving it alone"))
        }
        try AssistantEvents.removeReminder(id: id)
    }

    fileprivate static func undoEvent(id: String, box: ItemGuard) throws {
        guard let current = try AssistantEvents.snapshotEvent(id: id) else { return }
        if let expected = box.event, current != expected {
            throw AssistantToolError(message: T("Событие уже меняли — не трогаю", "The event was edited — leaving it alone"))
        }
        try AssistantEvents.removeEvent(id: id)
    }
}

/// Каким элемент был сразу после создания (или последней своей правки) — «отмени» и
/// «поправь» трогают только нетронутое.
final class ItemGuard {
    var reminder: AssistantEvents.ReminderSnapshot?
    var event: AssistantEvents.EventSnapshot?
    var noteModified: Date?
}

private struct PendingPlan {
    let plan: AssistantPlan
    let context: AssistantContext
    let utterance: String
    let at: Date
}

private struct JournalEntry {
    let ref: String
    let summary: String
    let at: Date
    let step: AssistantStep
    let undo: () throws -> Void
    let itemID: String?
    let guardBox: ItemGuard?
}

/// Контекст ассистента, снятый в фоне в момент отпускания клавиши. К тому времени, когда
/// Gemini дорасшифрует речь (секунды), снимок давно готов; `take` ждёт его не дольше `timeout`.
final class AssistantContextBox {
    private let lock = NSLock()
    private var value: AssistantContext?
    private var group: DispatchGroup?
    private let queue = DispatchQueue(label: "intact.assistant.ctx", qos: .userInitiated)

    func capture(target: NSRunningApplication?, sendSelection: Bool) {
        let group = DispatchGroup()
        group.enter()
        lock.lock()
        value = nil
        self.group = group
        lock.unlock()
        queue.async { [weak self] in
            var context = AssistantContext.capture(target: target, sendSelection: sendSelection)
            context.targetApp = target
            self?.lock.lock()
            if self?.group === group { self?.value = context }
            self?.lock.unlock()
            group.leave()
        }
    }

    func take(timeout: TimeInterval) -> AssistantContext? {
        lock.lock()
        let group = self.group
        lock.unlock()
        guard let group else { return nil }
        _ = group.wait(timeout: .now() + timeout)
        lock.lock()
        defer { value = nil; self.group = nil; lock.unlock() }
        return value
    }
}

extension AssistantContext {
    /// Тот же контекст на новый момент: [Повторить] пересчитывает «через 5 минут» от сейчас,
    /// а приложение, окно и выделение остаются от исходного нажатия.
    func withTime(_ now: Date) -> AssistantContext {
        var copy = AssistantContext(now: now, timeZone: .current, appName: appName, bundleID: bundleID,
                                    windowTitle: windowTitle, hasTextField: hasTextField, selection: selection,
                                    selectionTruncated: selectionTruncated, selectionFingerprint: selectionFingerprint,
                                    isTerminal: isTerminal, selectionDropReason: selectionDropReason)
        copy.targetApp = targetApp
        return copy
    }
}
