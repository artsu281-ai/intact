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
    func assistantDeliverText(_ text: String, target: NSRunningApplication?, mayActivate: Bool, done: @escaping (AssistantDelivery) -> Void)
    /// [Повторить]: новый прогон через контроллер — с пилюлей, ⎋ и сторожем.
    func assistantRetry(utterance: String, context: AssistantContext)
    /// Показать карточку (nil — убрать). `seconds` — через сколько она закроется сама.
    func assistantPresent(_ card: AssistantCard?, seconds: Int)
    /// Одна запись в истории и «последних ответах».
    func assistantRecord(question: String, answer: String)
}

/// Чем кончилась доставка текста — по факту, а не по «вызов не упал».
enum AssistantDelivery {
    /// Вставлено в поле и подтверждено (InsertionEngine сверил поле или ⌘V забрали).
    case inserted
    /// Режим вывода «только в буфер»: текст в буфере, в поле его нет.
    case copied
    case failed
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
            if Self.claimsUnexecutedAction(utterance: utterance, answer: prose) {
                claimedButNotDone(utterance: utterance, run: run)
                return
            }
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
                if plan.say.isEmpty || Self.claimsUnexecutedAction(utterance: utterance, answer: plan.say) {
                    claimedButNotDone(utterance: utterance, run: run)
                    return
                }
                showAnswer(plan.say, query: utterance, context: context)
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

    /// Просили действие, а Gemini ответил словами «готово / поставила / открыла» без плана.
    /// На Mac ничего не произошло — сказать это прямо, а не показывать его слова как итог.
    private func claimedButNotDone(utterance: String, run: AssistantRun) {
        Log.write("Ассистент[\(run.number)]: Gemini сообщил о выполнении, но плана не прислал")
        present(.error(message: T("Gemini ответил, что сделал, но плана действий не прислал — на Mac ничего не выполнено.",
                                  "Gemini said it was done but sent no plan — nothing was done on the Mac."),
                       query: utterance, permission: nil), seconds: 12, query: utterance)
        playSound("Basso")
    }

    /// Команда («открой», «поставь», «напомни»…) и ответ, который начинается с отчёта о
    /// сделанном. Только по первому слову с обеих сторон: «Эйнштейн создал…» — не отчёт.
    static func claimsUnexecutedAction(utterance: String, answer: String) -> Bool {
        func words(_ text: String) -> [String] {
            text.lowercased().replacingOccurrences(of: "ё", with: "е")
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty }
        }
        // Вопрос («Напомни, когда день рождения Пушкина?») — это просьба ответить, а не сделать.
        if utterance.contains("?") { return false }
        let fillers: Set<String> = ["пожалуйста", "слушай", "можешь", "можно", "давай", "ну", "а", "и", "please", "can", "could", "you"]
        let command = words(utterance).drop(while: { fillers.contains($0) })
        let commandStems = ["открой", "запусти", "поставь", "напомни", "создай", "запиши", "добавь", "включи", "выключи",
                            "удали", "убери", "отмени", "перенеси", "установи", "заведи", "разбуди", "open", "set",
                            "remind", "create", "add", "turn", "delete", "remove", "launch"]
        guard let first = command.first, commandStems.contains(where: { first.hasPrefix($0) }) else { return false }
        let questionWords: Set<String> = ["когда", "как", "что", "где", "кто", "сколько", "какой", "какая", "какое", "какие",
                                          "почему", "зачем", "куда", "откуда", "what", "when", "where", "who", "how", "which", "why"]
        if command.dropFirst().first.map(questionWords.contains) == true { return false }
        // Ответ: пропускаем «хорошо, конечно» и названия инструментов, смотрим следующие слова.
        let acknowledgements: Set<String> = ["хорошо", "конечно", "окей", "ок", "да", "так", "sure", "okay", "ok", "yes",
                                             "таймер", "напоминание", "заметка", "событие", "встреча", "timer", "reminder", "note", "event"]
        let report = words(answer).drop(while: { acknowledgements.contains($0) }).prefix(2)
        // Только прошедшее и причастия: «напомню», «ставлю» начинают и обычные ответы.
        let reportWords: Set<String> = ["готово", "сделано", "открыл", "открыла", "открыт", "открыто", "запустил", "запустила",
                                        "поставил", "поставила", "поставлен", "поставлено", "создал", "создала", "создано", "создана",
                                        "записал", "записала", "записано", "добавил", "добавила", "добавлено", "включил", "включила",
                                        "выключил", "выключила", "удалил", "удалила", "удалено", "отменил", "отменила", "перенес",
                                        "перенесла", "перенесено", "установил", "установила", "done", "opened", "created", "added",
                                        "deleted", "removed"]
        return report.contains(where: reportWords.contains)
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
            var skipped: [AssistantStep] = []
            for (index, step) in actionSteps.enumerated() {
                if run.cancelled { skipped = Array(actionSteps[index...]); break }
                let receipt = self.perform(step, context: context, journal: journalSnapshot)
                receipts.append(receipt)
                if !receipt.ok {   // остановка на первой ошибке; оставшееся — «не выполнено»
                    skipped = Array(actionSteps[(index + 1)...])
                    break
                }
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
                self.finishExecution(plan: plan, receipts: receipts, skipped: skipped, textStep: textStep,
                                     canDeliverText: canDeliverText, replaceStillValid: replaceStillValid,
                                     utterance: utterance, context: context, run: run)
            }
        }
    }

    private func finishExecution(plan: AssistantPlan, receipts: [AssistantReceipt], skipped: [AssistantStep],
                                 textStep: AssistantStep?, canDeliverText: Bool, replaceStillValid: Bool,
                                 utterance: String, context: AssistantContext, run: AssistantRun) {
        // Журнал: у каждого шага, после которого в мире что-то осталось (даже если проверка
        // результата не сошлась), — своя ссылка, чтобы «отмени» могло это убрать.
        var refs: [String] = []
        for receipt in receipts where receipt.ok {
            if case .undo(let ref) = receipt.step { journal.removeAll { $0.ref == ref } }
            if case .edit(let ref, _, _, _, _) = receipt.step, let summary = receipt.memorySummary,
               let index = journal.firstIndex(where: { $0.ref == ref }) {
                journal[index].summary = summary
            }
        }
        for var receipt in receipts {
            if let undo = receipt.undo {
                refCounter += 1
                let ref = "A\(refCounter)"
                receipt.ref = ref
                journal.append(JournalEntry(ref: ref, summary: receipt.memorySummary ?? receipt.line, at: Date(),
                                            step: receipt.step, undo: undo, itemID: receipt.itemID,
                                            guardBox: receipt.guardBox))
                refs.append(ref)
            }
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

        // Строки карточки — из квитанций. Черновик и вопрос ничего не делают на Mac: это
        // не «успех», в строках и в подсчёте их нет.
        let meaningful = receipts.filter { !($0.ok && $0.line.isEmpty) }
        var lines = meaningful.map { AssistantCardLine(ok: $0.ok, text: $0.ok ? $0.line : ($0.error?.message ?? $0.line)) }
        lines += skipped.filter { $0.baseRisk >= .local }.map { AssistantCardLine(ok: false, text: T("Не выполнено: ", "Not done: ") + preview($0)) }
        let failedPermission = meaningful.first(where: { !$0.ok })?.error?.permission
        let anySucceeded = meaningful.contains { $0.ok }
        let drafts = plan.steps.compactMap { step -> (String, String)? in
            if case .messageDraft(let to, let text) = step { return (to, text) } else { return nil }
        }
        let text: String? = textStep.flatMap { step in
            switch step {
            case .textInsert(let t), .textReplace(let t): return t
            default: return nil
            }
        }

        let complete: (AssistantDelivery?) -> Void = { [weak self] delivery in
            guard let self else { return }
            if let delivery, let textStep {
                let isReplace: Bool = { if case .textReplace = textStep { return true } else { return false } }()
                switch delivery {
                case .inserted:
                    lines.append(AssistantCardLine(ok: true, text: isReplace ? T("Выделение заменено · ⌘Z — вернуть", "Selection replaced · ⌘Z to undo")
                                                                   : T("Текст вставлен", "Text inserted")))
                case .copied:
                    lines.append(AssistantCardLine(ok: true, text: T("Текст в буфере — вставьте ⌘V (режим «только в буфер»)", "The text is on the clipboard — paste with ⌘V (clipboard-only mode)")))
                case .failed:
                    break   // до сюда не доходит: неудача идёт через textFallback
                }
            }
            // Текстовый шаг не дошёл до очереди — раньше что-то не удалось. Текст не теряем,
            // и про буфер говорим на той карточке, которую покажем.
            var clipboardNote: String?
            if delivery == nil, let text, !canDeliverText {
                Clipboard.write(text, transient: false, session: nil)
                if NSPasteboard.general.string(forType: .string) == text {
                    clipboardNote = T("Текст не вставлен — он в буфере", "The text wasn't inserted — it's on the clipboard")
                    lines.append(AssistantCardLine(ok: false, text: clipboardNote!))
                }
            }
            let anyFailed = lines.contains { !$0.ok }
            if let (to, draftText) = drafts.first, !anyFailed, lines.isEmpty {
                self.present(.draft(to: to, text: draftText), seconds: 30, text: draftText)
                self.playSound("Purr")
            } else if !lines.isEmpty {
                if let (to, draftText) = drafts.first, !anyFailed, delivery != .copied {
                    // Черновик рядом с выполненными действиями: итог с [Отменить], а текст
                    // черновика — в буфер, чтобы он не пропал.
                    Clipboard.write(draftText, transient: false, session: nil)
                    lines.append(AssistantCardLine(ok: true, text: T("Черновик для \(to) — в буфере", "Draft for \(to) — on the clipboard")))
                }
                if let permission = failedPermission, !anySucceeded {
                    // Ничего не выполнено — карточка ошибки с [Разрешить].
                    var message = meaningful.first(where: { !$0.ok })?.error?.message ?? ""
                    if let clipboardNote { message += "\n" + clipboardNote }
                    self.present(.error(message: message, query: utterance, permission: permission), seconds: 15, query: utterance)
                } else {
                    // Итог со всеми строками и [Отменить]; повтор всего плана создал бы
                    // уже сделанное второй раз.
                    self.present(.summary(lines: lines, canUndo: !refs.isEmpty), seconds: refs.isEmpty ? (anyFailed ? 10 : 4) : (anyFailed ? 10 : 6))
                }
                self.playSound(anyFailed ? "Basso" : "Glass")
            }
            // В историю и память — что сделано на самом деле. «say» Gemini написан ДО
            // выполнения («Открываю Telegram») и верен, только если всё удалось.
            let delivered: String? = (delivery == .inserted || delivery == .copied) ? text : nil
            let outcome = lines.map { ($0.ok ? "✓ " : "✗ ") + $0.text }.joined(separator: "; ")
            let answer = delivered ?? ((!anyFailed && !plan.say.isEmpty) ? plan.say : outcome)
            self.memory.lastExchange = AssistantExchange(question: utterance, answer: answer, at: Date())
            self.host?.assistantRecord(question: utterance, answer: answer)
            Log.write("Ассистент[\(run.number)]: выполнено \(meaningful.filter(\.ok).count) из \(plan.steps.count) шаг(ов)"
                      + (skipped.isEmpty ? "" : ", пропущено \(skipped.count)")
                      + (delivery.map { ", текст: \($0)" } ?? ""))
        }

        guard let textStep, let text, canDeliverText else { complete(nil); return }
        if !replaceStillValid {
            Log.write("Ассистент[\(run.number)]: окно или выделение сменились — текст на карточке")
            textFallback(text, lines: &lines, reason: T("Окно сменилось", "The window changed"), utterance: utterance, refs: refs, plan: plan)
            return
        }
        _ = textStep
        host?.assistantDeliverText(text, target: context.targetApp, mayActivate: false) { [weak self] delivery in
            guard let self else { return }
            if delivery == .failed {
                // Некуда вставить (ушли в другое приложение, поле пропало, идёт новая
                // диктовка) — текст не теряем.
                self.textFallback(text, lines: &lines, reason: T("Вставить не удалось", "Couldn't insert"), utterance: utterance, refs: refs, plan: plan)
            } else {
                complete(delivery)
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
            let onClipboard = NSPasteboard.general.string(forType: .string) == text
            lines.append(AssistantCardLine(ok: false, text: onClipboard
                ? T("\(reason) — текст скопирован в буфер", "\(reason) — the text is on the clipboard")
                : T("\(reason), и в буфер положить не удалось", "\(reason), and it couldn't be put on the clipboard")))
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
                let box = ItemGuard()
                let check = Verify.reminder(id: id, due: due)
                box.reminder = check.observed
                let when = due.map { Self.format($0, tz: tz) } ?? T("без срока", "no due date")
                return Verify.receipt(check, step: step,
                                      line: T("Напоминание · \(title) · \(when)", "Reminder · \(title) · \(when)"),
                                      memorySummary: "напоминание «\(title)»" + (due.map { " на \(Self.iso($0, tz: tz))" } ?? ""),
                                      undo: { try Self.undoReminder(id: id, box: box) }, itemID: id, guardBox: box)

            case .calendarAdd(let title, let start, let end, let place):
                let id = try AssistantEvents.addEvent(title: title, start: start, end: end, place: place)
                let box = ItemGuard()
                let check = Verify.event(id: id, start: start)
                box.event = check.observed
                return Verify.receipt(check, step: step,
                                      line: T("Событие · \(title) · \(Self.format(start, tz: tz))", "Event · \(title) · \(Self.format(start, tz: tz))"),
                                      memorySummary: "событие «\(title)» на \(Self.iso(start, tz: tz))",
                                      undo: { try Self.undoEvent(id: id, box: box) }, itemID: id, guardBox: box)

            case .noteAdd(let title, let body):
                let created = try AssistantNotes.create(title: title, body: body, folder: settings.voiceNotesFolder)
                let box = ItemGuard()
                let check = Verify.note(id: created.id)
                box.noteModified = check.observed
                let folderNote = created.folder == settings.voiceNotesFolder ? "" : T(" (в папке «\(created.folder)»)", " (in “\(created.folder)”)")
                return Verify.receipt(check, step: step,
                                      line: T("Заметка · \(title)", "Note · \(title)") + folderNote,
                                      memorySummary: "заметка «\(title)»",
                                      undo: {
                                          // Заметку, которую успели поправить, не удаляем.
                                          guard let current = try AssistantNotes.modificationDate(id: created.id) else {
                                              throw AssistantToolError(message: T("Не нашёл заметку — проверьте в «Заметках»", "Couldn't find the note — check Notes"))
                                          }
                                          if let expected = box.noteModified, abs(current.timeIntervalSince(expected)) > 5 {
                                              throw AssistantToolError(message: T("Заметку уже меняли — не трогаю", "The note was edited — leaving it alone"))
                                          }
                                          // Удалённая заметка лежит в «Недавно удалённых» и по id находится —
                                          // итог удаления сообщает сам `delete` (он сверяет папку).
                                          try AssistantNotes.delete(id: created.id, expectedFolder: created.folder)
                                      },
                                      itemID: created.id, guardBox: box)

            case .timerSet(let seconds, let label):
                let name = label ?? T("таймер", "timer")
                if seconds > AssistantTimers.maxSeconds {
                    // Внутренний таймер не переживёт перезапуск Intact — длинный ставим напоминанием.
                    let due = AssistantDate(date: Date().addingTimeInterval(TimeInterval(seconds)), hasTime: true)
                    let id = try AssistantEvents.addReminder(title: name, due: due, listName: settings.voiceRemindersList, timeZone: tz)
                    let box = ItemGuard()
                    let check = Verify.reminder(id: id, due: due)
                    box.reminder = check.observed
                    return Verify.receipt(check, step: step,
                                          line: T("Напоминание-таймер · \(name) · \(Self.format(due, tz: tz))", "Timer reminder · \(name) · \(Self.format(due, tz: tz))"),
                                          memorySummary: "таймер-напоминание «\(name)» на \(Self.iso(due, tz: tz))",
                                          undo: { try Self.undoReminder(id: id, box: box) }, itemID: id, guardBox: box)
                }
                let id = try AssistantTimers.shared.start(seconds: seconds, label: label) { [weak self] item in
                    self?.timerFired(label: item.label ?? name)
                }
                guard AssistantTimers.shared.active.contains(where: { $0.id == id }) else {
                    return fail(AssistantToolError(message: T("Таймер не запустился", "The timer didn't start")))
                }
                return AssistantReceipt(step: step, ok: true,
                                        line: T("Таймер · \(name) · \(Self.duration(seconds)) (пока Intact запущен)", "Timer · \(name) · \(Self.duration(seconds)) (while Intact runs)"),
                                        memorySummary: "таймер «\(name)» на \(Self.duration(seconds))",
                                        undo: {
                                            guard AssistantTimers.shared.cancel(id: id) else {
                                                throw AssistantToolError(message: T("Таймер уже сработал — отменять нечего", "The timer already went off"))
                                            }
                                        }, itemID: id)

            case .appOpen(let name):
                switch AppIndex.resolve(name) {
                case .found(let url, let displayName):
                    // Строка карточки — по тому, что видно на экране, а не по «запустилось».
                    switch AppIndex.open(url: url) {
                    case .visible:
                        return AssistantReceipt(step: step, ok: true, line: T("Открыто · \(displayName)", "Opened · \(displayName)"))
                    case .launched:
                        return AssistantReceipt(step: step, ok: true, line: T("Запущено · \(displayName)", "Launched · \(displayName)"))
                    case .otherSpace:
                        return fail(AssistantToolError(message: WindowVisibility.switchesSpaceOnActivate
                            ? T("«\(displayName)» активна, но её окно на другом рабочем столе", "“\(displayName)” is active, but its window is on another desktop")
                            : T("«\(displayName)» активна, но окно на другом рабочем столе, а переход туда выключен (Рабочий стол и Dock → «переходить на стол с окнами приложения»)",
                                "“\(displayName)” is active, but its window is on another desktop and switching there is off (Desktop & Dock → “switch to a Space with open windows”)")))
                    case .noWindow:
                        return fail(AssistantToolError(message: T("«\(displayName)» запущена, но окно не показала", "“\(displayName)” is running but didn't show a window")))
                    case .notFrontmost:
                        return fail(AssistantToolError(message: T("«\(displayName)» запущена, но macOS не дала вывести её вперёд", "“\(displayName)” is running, but macOS didn't let it come forward")))
                    case .failed:
                        return fail(AssistantToolError(message: T("Не удалось открыть «\(displayName)»", "Couldn't open “\(displayName)”")))
                    }
                case .ambiguous(let names):
                    return fail(AssistantToolError(message: T("Какую программу открыть: \(names.prefix(4).joined(separator: ", "))?",
                                                              "Which app: \(names.prefix(4).joined(separator: ", "))?")))
                case .notFound:
                    return fail(AssistantToolError(message: T("Не нашёл программу «\(name)»", "Couldn't find an app called “\(name)”")))
                }

            case .urlOpen(let url):
                let host = AssistantURLPolicy.displayHost(url)
                // «Открыто» — только если окно, куда легла ссылка, на этом столе впереди:
                // иначе вкладка открылась там, куда человек не смотрит.
                switch Verify.openLink(url) {
                case .confirmed:
                    return AssistantReceipt(step: step, ok: true, line: T("Открыта ссылка · \(host)", "Opened · \(host)"))
                case .unverified(let note):
                    return AssistantReceipt(step: step, ok: true, line: T("Открыта ссылка · \(host)", "Opened · \(host)") + " · " + note)
                case .contradicted(let message, _):
                    return fail(AssistantToolError(message: message))
                }

            case .volumeSet(let level):
                let previous = SystemVolume.get()
                try SystemVolume.set(level)
                // У HDMI и части внешних устройств громкость системой не управляется: команда
                // проходит молча, а звук не меняется. Читаем обратно.
                if level > 0, let now = SystemVolume.get(), abs(now - level) > 3 {
                    return fail(AssistantToolError(message: T("Громкость не изменилась: у этого устройства вывода её регулирует само устройство",
                                                              "The volume didn't change: this output device controls its own volume")))
                }
                if level == 0, SystemVolume.isMuted() == false {
                    return fail(AssistantToolError(message: T("Звук не выключился: у этого устройства вывода его регулирует само устройство",
                                                              "Sound didn't turn off: this output device controls its own volume")))
                }
                return AssistantReceipt(step: step, ok: true,
                                        line: level == 0 ? T("Звук выключен", "Sound off") : T("Громкость · \(level)%", "Volume · \(level)%"),
                                        memorySummary: "громкость \(level)%",
                                        undo: previous.map { prev in {
                                            try SystemVolume.set(prev)
                                            if let now = SystemVolume.get(), abs(now - prev) > 3 {
                                                throw AssistantToolError(message: T("Громкость не вернулась", "The volume wasn't restored"))
                                            }
                                        } })

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
                    do {
                        entry.guardBox?.reminder = try AssistantEvents.snapshotReminder(id: itemID)
                    } catch {
                        entry.guardBox?.reminder = nil
                        return AssistantReceipt(step: step, ok: true, line: T("Изменено · не перепроверено", "Changed · not re-checked"))
                    }
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
                    do {
                        entry.guardBox?.event = try AssistantEvents.snapshotEvent(id: itemID)
                    } catch {
                        entry.guardBox?.event = nil
                        return AssistantReceipt(step: step, ok: true, line: T("Изменено · не перепроверено", "Changed · not re-checked"))
                    }
                default:
                    return fail(AssistantToolError(message: T("Это действие не поправить — отмените и скажите заново", "This can't be changed — undo and say it again")))
                }
                // Карточка и журнал — по тому, что сохранилось, а не по тому, что просили.
                let stored: (title: String, date: Date?, hasTime: Bool)? = {
                    if let r = entry.guardBox?.reminder { return (r.title, r.due, r.dueHasTime) }
                    if let e = entry.guardBox?.event { return (e.title, e.start, !e.isAllDay) }
                    return nil
                }()
                guard let stored else {
                    return AssistantReceipt(step: step, ok: true, line: T("Изменено · не перепроверено", "Changed · not re-checked"))
                }
                if let requested = (start ?? due), requested.hasTime, let saved = stored.date, abs(saved.timeIntervalSince(requested.date)) > 60 {
                    return fail(AssistantToolError(message: T("Изменение сохранилось не так, как просили — проверьте", "The change wasn't saved as asked — please check")))
                }
                let when = stored.date.map { " · " + Self.format(AssistantDate(date: $0, hasTime: stored.hasTime), tz: tz) } ?? ""
                let kind: String = { if case .calendarAdd = entry.step { return "событие" } else { return "напоминание" } }()
                return AssistantReceipt(step: step, ok: true, line: T("Изменено · \(stored.title)\(when)", "Changed · \(stored.title)\(when)"),
                                        memorySummary: "\(kind) «\(stored.title)»" + (stored.date.map { " на \(Self.iso(AssistantDate(date: $0, hasTime: stored.hasTime), tz: tz))" } ?? ""))

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
                Log.write("Ассистент[\(run.number)]: отменено \(lines.filter(\.ok).count) из \(lines.count)" + (fromVoice ? " голосом" : " кнопкой"))
                self.present(.summary(lines: lines, canUndo: false), seconds: lines.allSatisfy(\.ok) ? 4 : 8)
                self.playSound(lines.allSatisfy(\.ok) ? "Pop" : "Basso")
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
            host?.assistantDeliverText(text, target: lastTarget, mayActivate: true) { [weak self] delivery in
                switch delivery {
                case .inserted: break
                case .copied:
                    self?.present(.summary(lines: [AssistantCardLine(ok: true, text: T("Текст в буфере — вставьте ⌘V", "The text is on the clipboard — paste with ⌘V"))], canUndo: false), seconds: 4)
                case .failed:
                    self?.present(.answer(query: query, text: text, canInsert: false), seconds: 40, text: text, query: query)
                    self?.playSound("Basso")
                }
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
        // Не нашлось — это не «отменено»: id мог смениться после синхронизации, а
        // напоминание осталось. Честно говорим, что не нашли.
        guard let current = try AssistantEvents.snapshotReminder(id: id) else {
            throw AssistantToolError(message: T("Не нашёл напоминание — проверьте в «Напоминаниях»", "Couldn't find the reminder — check Reminders"))
        }
        if let expected = box.reminder, current != expected {
            throw AssistantToolError(message: T("Напоминание уже меняли — не трогаю", "The reminder was edited — leaving it alone"))
        }
        try AssistantEvents.removeReminder(id: id)
        if try AssistantEvents.snapshotReminder(id: id) != nil {
            throw AssistantToolError(message: T("Напоминание не удалилось", "The reminder wasn't removed"))
        }
    }

    fileprivate static func undoEvent(id: String, box: ItemGuard) throws {
        guard let current = try AssistantEvents.snapshotEvent(id: id) else {
            throw AssistantToolError(message: T("Не нашёл событие — проверьте в «Календаре»", "Couldn't find the event — check Calendar"))
        }
        if let expected = box.event, current != expected {
            throw AssistantToolError(message: T("Событие уже меняли — не трогаю", "The event was edited — leaving it alone"))
        }
        try AssistantEvents.removeEvent(id: id)
        if try AssistantEvents.snapshotEvent(id: id) != nil {
            throw AssistantToolError(message: T("Событие не удалилось", "The event wasn't removed"))
        }
    }
}

/// Проверка результата после действия: «готово» на карточке — только если результат
/// виден в мире (перечитан из EventKit, найден в Заметках, окно на экране), а не потому,
/// что вызов не бросил ошибку. Тот же принцип, что у вставки (AGENTS_SYNC 7.1.2).
enum Verify {
    enum Check<Value> {
        /// Результат наблюдён и совпал с просьбой.
        case confirmed(Value)
        /// Наблюдение противоречит просьбе (не нашлось, время другое, окно не там).
        case contradicted(String, Value?)
        /// Посмотреть не удалось (чтение не ответило) — действие, скорее всего, сделано.
        case unverified(String)

        /// Что увидели — и при совпадении, и при расхождении: по этому снимку отмена потом
        /// проверяет, что элемент с тех пор не трогали руками.
        var observed: Value? {
            switch self {
            case .confirmed(let value): return value
            case .contradicted(_, let value): return value
            case .unverified: return nil
            }
        }
    }

    private static var notRechecked: String { T("не перепроверено", "not re-checked") }

    static func reminder(id: String, due: AssistantDate?) -> Check<AssistantEvents.ReminderSnapshot> {
        let snapshot: AssistantEvents.ReminderSnapshot?
        do { snapshot = try AssistantEvents.snapshotReminder(id: id) } catch { return .unverified(notRechecked) }
        guard let snapshot else {
            return .contradicted(T("Напоминание не нашлось после сохранения", "The reminder wasn't found after saving"), nil)
        }
        if let due, due.hasTime, let saved = snapshot.due, abs(saved.timeIntervalSince(due.date)) > 60 {
            return .contradicted(T("Напоминание сохранилось с другим временем — проверьте в «Напоминаниях»",
                                   "The reminder was saved with a different time — check Reminders"), snapshot)
        }
        return .confirmed(snapshot)
    }

    static func event(id: String, start: AssistantDate) -> Check<AssistantEvents.EventSnapshot> {
        let snapshot: AssistantEvents.EventSnapshot?
        do { snapshot = try AssistantEvents.snapshotEvent(id: id) } catch { return .unverified(notRechecked) }
        guard let snapshot else {
            return .contradicted(T("Событие не нашлось после сохранения", "The event wasn't found after saving"), nil)
        }
        if start.hasTime, abs(snapshot.start.timeIntervalSince(start.date)) > 60 {
            return .contradicted(T("Событие сохранилось с другим временем — проверьте в «Календаре»",
                                   "The event was saved with a different time — check Calendar"), snapshot)
        }
        return .confirmed(snapshot)
    }

    static func note(id: String) -> Check<Date> {
        let modified: Date?
        do { modified = try AssistantNotes.modificationDate(id: id) } catch { return .unverified(notRechecked) }
        guard let modified else {
            return .contradicted(T("Заметка не нашлась после сохранения", "The note wasn't found after saving"), nil)
        }
        return .confirmed(modified)
    }

    /// Квитанция по проверке. Если элемент в мире остался (подтверждён, не перепроверен
    /// или сохранён «не так»), квитанция несёт отмену — «отмени» должно его достать.
    static func receipt<Value>(_ check: Check<Value>, step: AssistantStep, line: String, memorySummary: String,
                               undo: @escaping () throws -> Void, itemID: String, guardBox: ItemGuard) -> AssistantReceipt {
        switch check {
        case .confirmed:
            return AssistantReceipt(step: step, ok: true, line: line, memorySummary: memorySummary,
                                    undo: undo, itemID: itemID, guardBox: guardBox)
        case .unverified(let note):
            return AssistantReceipt(step: step, ok: true, line: line + " · " + note, memorySummary: memorySummary,
                                    undo: undo, itemID: itemID, guardBox: guardBox)
        case .contradicted(let message, let value):
            let error = AssistantToolError(message: message)
            return AssistantReceipt(step: step, ok: false, line: message, memorySummary: memorySummary,
                                    undo: value == nil ? nil : undo, itemID: itemID, guardBox: guardBox, error: error)
        }
    }

    /// Открыть ссылку и убедиться, что её окно на этом столе впереди. Приложение, которое
    /// её приняло, берём из ответа системы (универсальные ссылки открываются не браузером).
    static func openLink(_ url: URL) -> Check<Void> {
        let expected = NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
        let before = expected.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        let titleBefore = before.flatMap { focusedWindowTitle(pid: $0.processIdentifier) }
        let countBefore = before.map { WindowVisibility.visibleWindows(of: $0.processIdentifier) } ?? 0

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let done = DispatchSemaphore(value: 0)
        var handler: NSRunningApplication?
        var failure: Error?
        NSWorkspace.shared.open(url, configuration: configuration) { app, error in
            handler = app
            failure = error
            done.signal()
        }
        guard done.wait(timeout: .now() + 5) == .success else { return .unverified(T("не перепроверено", "not re-checked")) }
        if failure != nil { return .contradicted(T("Не удалось открыть ссылку", "Couldn't open the link"), nil) }
        guard let app = handler ?? expected.flatMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }) else {
            return .unverified(T("не перепроверено", "not re-checked"))
        }
        let pid = app.processIdentifier
        let name = app.localizedName ?? "браузер"
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
               WindowVisibility.visibleWindows(of: pid) > 0 {
                // Окно впереди — но то ли, куда легла ссылка? Новое окно или новая вкладка
                // меняют заголовок окна в фокусе (или добавляют окно).
                let changed = before?.processIdentifier != pid
                    || focusedWindowTitle(pid: pid) != titleBefore
                    || WindowVisibility.visibleWindows(of: pid) > countBefore
                if changed { return .confirmed(()) }
            }
            usleep(100_000)
        }
        Log.write("ассистент: ссылка открыта, но её окна на этом столе не видно")
        return .contradicted(T("Ссылка открыта в «\(name)», но его окна с ней нет на этом рабочем столе",
                               "The link opened in “\(name)”, but that window isn't on this desktop"), nil)
    }

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
        return title as? String
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
    var summary: String
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
