import AppKit
import ApplicationServices
import Foundation

/// Распознавание речи встроенным микрофоном приложения Gemini.
///
/// Работает целиком через Accessibility, не выводя окно Gemini на передний план:
///   1. нажимаем кнопку «Использовать микрофон (⌘D)» в композере;
///   2. ДОЖИДАЕМСЯ появления кнопки «Остановить» — только после этого можно говорить;
///   3. пока идёт речь, читаем накапливающийся текст из поля ввода (живой черновик);
///   4. по отпусканию клавиши жмём «Остановить» и дослушиваем хвост расшифровки;
///   5. отдаём дельту относительно снимка, сделанного до старта, и чистим поле.
///
/// Замеры на живом приложении (они и задают константы ниже):
///   - кнопка «Остановить» появляется через ~190 мс после нажатия микрофона;
///   - расшифровка догоняет ещё ~700 мс ПОСЛЕ нажатия «Остановить»;
///   - если заговорить, не дождавшись шага 2, начало фразы теряется.
///
/// Важное отличие от удалённого моста ChatGPT: окно Gemini мы не трогаем вообще —
/// не разворачиваем, не активируем, не ставим фокус (см. AGENTS_SYNC.md, раздел 4).
final class GeminiSTTService {
    static let shared = GeminiSTTService()

    /// Чем кончился старт. Причину отказа вызывающий код показывает пользователю:
    /// раньше любой отказ объяснялся разрешением на микрофон, хотя по логу все
    /// 33 отказа были закрытым окном Gemini.
    enum StartOutcome {
        /// Микрофон Gemini пишет — можно говорить.
        case started
        /// Сессию отменили или отпустили клавишу раньше, чем Gemini начал писать.
        /// Вызывающему её исход уже не нужен.
        case abandoned
        case failed(StartFailure)
    }

    enum StartFailure {
        /// Приложения Gemini нет на этом Mac.
        case notInstalled
        /// Gemini не был запущен — поднимаем его скрытым для следующих диктовок.
        case launching
        /// Окно Gemini закрыли крестиком — открываем его без активации для следующих диктовок.
        case windowClosed
        /// Окно есть, но поле ввода недоступно (свёрнуто, на другом рабочем столе).
        /// Окно пользователя не трогаем.
        case composerUnavailable
        /// Gemini начал бы писать слишком поздно — начало фразы он уже не услышит.
        case late
        case micButtonNotFound
        /// Кнопка «Остановить» так и не появилась: чаще всего у самого Gemini нет
        /// разрешения на микрофон (у копии Double Bubble оно своё).
        case notConfirmed

        var logText: String {
            switch self {
            case .notInstalled: return "приложение Gemini не найдено"
            case .launching: return "Gemini не был запущен"
            case .windowClosed: return "окно Gemini закрыто"
            case .composerUnavailable: return "поле ввода Gemini недоступно"
            case .late: return "Gemini опоздал к началу фразы"
            case .micButtonNotFound: return "кнопка микрофона не найдена"
            case .notConfirmed: return "запись не подтвердилась"
            }
        }
    }

    /// Сколько ждать подтверждения, что запись пошла (замер: ~190 мс, берём запас).
    private let startConfirmTimeout: TimeInterval = 3.0
    /// Запас после подтверждения. Появление кнопки «Остановить» — ещё НЕ доказательство,
    /// что микрофон уже пишет: на прогретом микрофоне подтверждение приходит за 20–35 мс
    /// и начало фразы цело, а на холодном — за ~200 мс, и первые слова терялись.
    /// Четверть секунды тишины дешевле потерянного начала фразы.
    private let micWarmup: TimeInterval = 0.25
    /// Сколько может пройти от нажатия клавиши до нажатия микрофона Gemini. Поиск окна
    /// и кнопки занимает 1–14 мс (замер 24.09.2026). Если ушло больше секунды, очередь
    /// занимала прошлая сессия или Gemini будили: человек уже говорит, начала фразы
    /// Gemini не услышит, и честнее отдать эту диктовку локальной записи целиком.
    private let maxDelayBeforeMic: TimeInterval = 1.0
    /// То же для момента «запись пошла». Обычно это 0,3–0,5 с (подтверждение + прогрев).
    private let maxDelayUntilLive: TimeInterval = 1.6
    /// Шаг опроса поля ввода для живого черновика.
    private let pollInterval: TimeInterval = 0.15
    /// Сколько ждать, что текст перестанет расти после «Остановить» (замер: ~700 мс).
    private let tailQuietDuration: TimeInterval = 1.4
    /// Потолок ожидания хвоста, чтобы не подвиснуть навсегда. Догон растёт с длиной
    /// записи, поэтому для длинных диктовок растёт и потолок.
    private let tailMaxDuration: TimeInterval = 8.0
    private let tailPerRecordedSecond: TimeInterval = 0.05
    /// Когда перестать ждать, если текста так и нет. По 248 расшифровкам из лога текст
    /// приходит через 0,57–1,2 с после «Остановить» на записях до 10 с и не позже 3,0 с
    /// на записях за 30 с. Раньше пустой ответ ждали полные 8 с — все 8 таких случаев
    /// в логе были короткими нажатиями, где Gemini ничего не услышал.
    private let emptyGiveUpBase: TimeInterval = 3.0
    private let emptyGiveUpPerRecordedSecond: TimeInterval = 0.06

    private let ax = DispatchQueue(label: "com.intact.gemini.stt", qos: .userInitiated)

    // Номера сессий живут под замком, а не на очереди `ax`: отмена и остановка должны
    // действовать сразу, а не вставать в очередь за долгим стартом.
    private let lock = NSLock()
    /// Последняя запрошенная сессия.
    private var requestedSession = 0
    /// Все сессии с номером не больше этого брошены: их старт не должен включать
    /// микрофон, а если уже включил — обязан его выключить.
    private var abandonedThrough = 0
    /// Сессии, отменённые явно (⎋, сочетание клавиш, слишком короткое нажатие), —
    /// в отличие от просто отпущенных. Только им нельзя будить Gemini ради следующих диктовок.
    private var cancelledThrough = 0
    /// Сессия, у которой микрофон Gemini подтверждённо пишет, и с какого момента.
    private var liveSession = 0
    private var liveSince = Date.distantPast

    // Дальше — только с очереди `ax`.
    private var isRecording = false
    private var window: AXUIElement?
    private var textArea: AXUIElement?
    private var baseline = ""
    /// До какого момента в поле может лечь запоздавшая расшифровка выключенного
    /// микрофона: она приходит через 0,6–3 с после «Остановить», смотря по длине записи.
    private var pendingTail: (textArea: AXUIElement, until: Date)?
    /// Когда поле последний раз читалось равным снимку. Изменение, замеченное позже,
    /// могло случиться в любой момент после этого — по нему и судим, чей это хвост.
    private var baselineSeenAt = Date.distantPast
    /// Меняется, когда поле берёт кто-то другой (`waitUntilIdle`): отложенная уборка
    /// после этого чужой текст не трогает.
    private var sweepEpoch = 0

    private init() {}

    var isAvailable: Bool { GeminiBridgeService.isAppAvailable }

    /// Дождаться, пока служба закончит работу с полем ввода Gemini. Нужен тем, кто
    /// пишет в тот же композер (причёсывание, вопрос к ИИ, команда «Джеминай»): иначе
    /// их запрос попадёт под уборку за брошенной диктовкой. Нельзя звать с главного
    /// потока и с очереди самой службы.
    func waitUntilIdle() {
        dispatchPrecondition(condition: .notOnQueue(.main))
        dispatchPrecondition(condition: .notOnQueue(ax))
        // Хвост выключенного микрофона ещё может лечь в поле — дожидаемся его на своём
        // потоке, а не на очереди службы: следующая диктовка не должна стоять за нами.
        // Проверка и уборка — одним блоком: пока мы спали, мог появиться новый хвост.
        while true {
            let wakeAt: Date? = ax.sync {
                if let tail = pendingTail, tail.until > Date() { return tail.until }
                if let tail = pendingTail {
                    if !isRecording { clearComposer(tail.textArea) }
                    pendingTail = nil
                }
                sweepEpoch &+= 1
                return nil
            }
            guard let wakeAt else { return }
            Thread.sleep(until: wakeAt)
        }
    }

    // MARK: - Сессии

    private func isAbandoned(_ session: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return session <= abandonedThrough
    }

    private func currentRequestedSession() -> Int {
        lock.lock(); defer { lock.unlock() }
        return requestedSession
    }

    /// Переход «микрофон пишет» под тем же замком, что и остановка: исход ровно один —
    /// либо stop() увидит живую запись, либо старт увидит, что его бросили.
    private func goLive(_ session: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard session > abandonedThrough, session == requestedSession else { return false }
        liveSession = session
        liveSince = Date()
        return true
    }

    /// Отпускает текущую сессию. Если микрофон Gemini ещё не пишет (или `abandonLive`),
    /// сессия бросается — её старт увидит это и уберёт за собой сам.
    private func release(abandonLive: Bool) -> (session: Int, wasLive: Bool, liveFor: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        let session = requestedSession
        let wasLive = session != 0 && liveSession == session
        if !wasLive || abandonLive { abandonedThrough = max(abandonedThrough, session) }
        let liveFor = wasLive ? Date().timeIntervalSince(liveSince) : 0
        liveSession = 0
        return (session, wasLive, liveFor)
    }

    // MARK: - Старт

    /// Включает микрофон Gemini. `.started` приходит только когда запись ПОДТВЕРЖДЕНА —
    /// до этого момента говорить нельзя, начало фразы потеряется.
    func start(onDraft: @escaping (String) -> Void, completion: @escaping (StartOutcome) -> Void) {
        lock.lock()
        // Новая сессия закрывает все прежние: если какую-то забыли отпустить, её
        // черновик и её микрофон не должны пережить следующую диктовку.
        abandonedThrough = max(abandonedThrough, requestedSession)
        liveSession = 0
        requestedSession &+= 1
        let session = requestedSession
        lock.unlock()
        let requestedAt = Date()
        // Будить Gemini ради следующих диктовок — только если нажатие продержалось заметно
        // дольше порога короткого нажатия (и не меньше 0,5 с): сочетания клавиш и короткие
        // нажатия отменяются раньше, с запасом на остановку своей записи.
        let minHold = max(0.5, Double(AppSettings.shared.minHoldMs) / 1000 + 0.25)

        ax.async { [weak self] in
            guard let self else { return }
            let report: (StartOutcome) -> Void = { outcome in
                let final: StartOutcome = self.isAbandoned(session) ? .abandoned : outcome
                DispatchQueue.main.async { completion(final) }
            }
            let waited = { Int(Date().timeIntervalSince(requestedAt) * 1000) }

            // Прошлую сессию так и не отпустили, а её микрофон пишет — гасим его первым делом.
            if self.isRecording, let window = self.window {
                self.isRecording = false
                Log.write("Gemini STT: прошлая запись осталась без хозяина — выключаю микрофон")
                self.shutMic(window: window, textArea: self.textArea, heardFor: 1)
            }

            guard !self.isAbandoned(session) else { report(.abandoned); return }

            let ctx: (window: AXUIElement, textArea: AXUIElement)
            switch self.resolveComposer() {
            case .ready(let window, let textArea):
                ctx = (window, textArea)
            case .notInstalled:
                report(.failed(.notInstalled))
                return
            case .notRunning:
                // Эту диктовку ведёт локальная запись, а Gemini поднимаем для следующих.
                // Раньше запуск ждали прямо здесь (до 17 с), и Gemini слышал только
                // хвост фразы — а раз текст не пустой, он и вставлялся.
                report(.failed(.launching))
                self.wakeGeminiIfStillWanted(session, after: requestedAt.addingTimeInterval(minHold))
                return
            case .windowClosed:
                report(.failed(.windowClosed))
                self.wakeGeminiIfStillWanted(session, after: requestedAt.addingTimeInterval(minHold))
                return
            case .composerUnavailable:
                Log.write("Gemini STT: окно Gemini есть, но поле ввода недоступно (свёрнуто или на другом столе)")
                report(.failed(.composerUnavailable))
                return
            }

            guard Date().timeIntervalSince(requestedAt) <= self.maxDelayBeforeMic else {
                Log.write("Gemini STT: до микрофона дошли только через \(waited()) мс — начало фразы Gemini уже не услышит")
                report(.failed(.late))
                return
            }
            // Бросили, пока искали окно — композер пользователя ещё не тронут.
            guard !self.isAbandoned(session) else { report(.abandoned); return }

            self.window = ctx.window
            self.textArea = ctx.textArea

            // Композер мог остаться непустым (свой же прошлый хвост, черновик пользователя).
            // Чистим и берём снимок: всё, что появится дальше, — это наша речь.
            self.clearComposer(ctx.textArea)
            self.baseline = self.readComposer(ctx.textArea)
            self.baselineSeenAt = Date()

            guard let mic = self.findButton(in: ctx.window, anyOf: ["использовать микрофон", "microphone"]) else {
                Log.write("Gemini STT: кнопка микрофона не найдена")
                report(.failed(.micButtonNotFound))
                return
            }
            guard !self.isAbandoned(session) else { report(.abandoned); return }
            AXUIElementPerformAction(mic, kAXPressAction as CFString)
            let micPressedAt = Date()

            // Ждём подтверждения записи — появления кнопки «Остановить». Ждём даже у
            // брошенной сессии: выключить микрофон можно только этой кнопкой.
            let deadline = Date().addingTimeInterval(self.startConfirmTimeout)
            var confirmed = false
            while Date() < deadline {
                if self.findStopButton(in: ctx.window) != nil { confirmed = true; break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard confirmed else {
                Log.write("Gemini STT: запись не подтвердилась — микрофон не включился")
                report(.failed(.notConfirmed))
                return
            }

            // Даём микрофону догреться, прежде чем сказать пользователю «говорите».
            // Прогрев прерывается отменой: сочетание вроде ⌥+← приходит через десятки
            // миллисекунд, и микрофон надо гасить сразу, а не после прогрева.
            let warmEnd = Date().addingTimeInterval(self.micWarmup)
            while Date() < warmEnd, !self.isAbandoned(session) {
                Thread.sleep(forTimeInterval: 0.02)
            }

            let late = Date().timeIntervalSince(requestedAt) > self.maxDelayUntilLive
            guard !late, self.goLive(session) else {
                // Микрофон уже нажат, но запись этой сессии не нужна: гасим его.
                if late {
                    Log.write("Gemini STT: запись пошла бы только через \(waited()) мс — начало фразы Gemini уже не услышал")
                }
                self.shutMic(window: ctx.window, textArea: ctx.textArea,
                             heardFor: Date().timeIntervalSince(micPressedAt))
                Log.write("Gemini STT: микрофон выключен, запись не понадобилась")
                report(late ? .failed(.late) : .abandoned)
                return
            }

            self.isRecording = true
            // Пока микрофон грелся, поле никто не читал — хвост прошлой записи мог лечь тогда.
            _ = self.absorbLateTail(self.readComposer(ctx.textArea))
            Log.write("Gemini STT: запись пошла через \(waited()) мс после нажатия")
            report(.started)
            self.pollDraft(session: session, onDraft: onDraft)
        }
    }

    /// Живой черновик: поле ввода Gemini наполняется по мере распознавания.
    private func pollDraft(session: Int, onDraft: @escaping (String) -> Void) {
        ax.asyncAfter(deadline: .now() + pollInterval) { [weak self] in
            guard let self, self.isRecording, !self.isAbandoned(session),
                  let ta = self.textArea else { return }
            let current = self.readComposer(ta)
            if self.absorbLateTail(current) {
                // Хвост прошлой записи — не наша речь, черновиком его не показываем.
            } else {
                let delta = Self.delta(full: current, base: self.baseline)
                if !delta.isEmpty {
                    DispatchQueue.main.async { onDraft(delta) }
                }
            }
            self.pollDraft(session: session, onDraft: onDraft)
        }
    }

    // MARK: - Остановка

    /// Останавливает запись и отдаёт расшифровку. Пустая строка означает, что Gemini
    /// ничего не вернул — вызывающий код должен подстраховаться локальным Whisper.
    /// `recordedSeconds` — длина своей записи: от неё зависит, сколько ждать хвост.
    func stop(recordedSeconds: TimeInterval, completion: @escaping (String) -> Void) {
        guard release(abandonLive: false).wasLive else {
            // Клавишу отпустили раньше, чем микрофон Gemini начал писать: всё сказанное
            // он пропустил. Старт, если он ещё идёт, увидит это и уберёт за собой сам.
            Log.write("Gemini STT: клавишу отпустили раньше, чем Gemini начал писать — беру свою запись")
            DispatchQueue.main.async { completion("") }
            return
        }
        ax.async { [weak self] in
            guard let self, self.isRecording,
                  let window = self.window, let ta = self.textArea else {
                DispatchQueue.main.async { completion("") }
                return
            }
            self.isRecording = false
            // Хвост прошлой записи мог лечь уже после последнего опроса черновика. А если
            // его окно ещё открыто, дожидаемся его конца ДО «Остановить»: пока микрофон
            // пишет, Gemini в поле ничего не выводит, значит всё, что появится сейчас, —
            // чужое. После «Остановить» свой текст от чужого уже не отличить. Это бывает
            // только сразу после отмены длинной записи и длится не больше ~2,5 с.
            _ = self.absorbLateTail(self.readComposer(ta))
            if let tail = self.pendingTail, tail.until > Date() {
                Log.write("Gemini STT: дожидаюсь хвоста прошлой записи перед остановкой")
                while Date() < tail.until {
                    Thread.sleep(forTimeInterval: 0.1)
                    _ = self.absorbLateTail(self.readComposer(ta))
                }
            }
            self.pendingTail = nil

            // Кнопки нет — значит, Gemini уже сам закончил запись. Нажимать здесь
            // «Использовать микрофон» нельзя: это включило бы его заново, и выключить
            // его потом было бы уже некому.
            if let stop = self.findStopButton(in: window) {
                AXUIElementPerformAction(stop, kAXPressAction as CFString)
            } else {
                Log.write("Gemini STT: кнопки «Остановить» нет — Gemini уже закончил запись сам")
            }

            // Хвост: расшифровка догоняет уже после нажатия «Остановить».
            let started = Date()
            let tailMax = max(self.tailMaxDuration, 3 + self.tailPerRecordedSecond * recordedSeconds)
            let emptyGiveUp = min(tailMax, max(self.emptyGiveUpBase,
                                               2 + self.emptyGiveUpPerRecordedSecond * recordedSeconds))
            var lastText = self.readComposer(ta)
            var lastChange = Date()
            var ending = "потолок"
            while Date().timeIntervalSince(started) < tailMax {
                Thread.sleep(forTimeInterval: 0.1)
                let now = self.readComposer(ta)
                if now != lastText {
                    lastText = now
                    lastChange = Date()
                }
                let hasText = !Self.delta(full: lastText, base: self.baseline).isEmpty
                if hasText && Date().timeIntervalSince(lastChange) >= self.tailQuietDuration {
                    ending = ""
                    break
                }
                if !hasText && Date().timeIntervalSince(started) >= emptyGiveUp {
                    ending = "текста нет"
                    break
                }
            }

            let result = Self.delta(full: lastText, base: self.baseline)
            // Убираем за собой: наш текст не должен остаться в чужом композере.
            self.clearComposer(ta)
            self.pendingTail = nil

            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            Log.write("Gemini STT: расшифровка \(result.count) симв. за \(elapsed) мс"
                      + (ending.isEmpty ? "" : " (\(ending), запись \(Int(recordedSeconds.rounded())) с)"))
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Диктовку прервали — глушим микрофон Gemini и чистим поле, результат не нужен.
    /// Без этого микрофон остался бы включённым и продолжал писать в композер.
    /// Если микрофон ещё не успел заработать, старт увидит отмену и уберёт за собой сам.
    func cancel() {
        let released = release(abandonLive: true)
        lock.lock()
        cancelledThrough = max(cancelledThrough, released.session)
        lock.unlock()
        guard released.wasLive else { return }
        ax.async { [weak self] in
            guard let self, self.isRecording, let window = self.window else { return }
            self.isRecording = false
            self.shutMic(window: window, textArea: self.textArea, heardFor: released.liveFor)
            Log.write("Gemini STT: запись отменена, микрофон выключен")
        }
    }

    /// Пока микрофон пишет, Gemini в поле ничего не выводит — текст приходит целиком
    /// после «Остановить» (раздел 5). Значит, изменение поля в окне хвоста — это
    /// запоздавшая расшифровка прошлой, выключенной записи: она становится частью
    /// снимка, а не нашей речью. Вне окна хвоста ничего не трогаем — на случай,
    /// если Gemini когда-нибудь начнёт показывать живой текст.
    private func absorbLateTail(_ current: String) -> Bool {
        guard current != baseline else {
            baselineSeenAt = Date()
            return false
        }
        guard let tail = pendingTail, baselineSeenAt < tail.until else { return false }
        baseline = current
        baselineSeenAt = Date()
        Log.write("Gemini STT: в поле легла расшифровка прошлой записи — не считаю её своей речью")
        return true
    }

    /// Выключает микрофон Gemini и убирает то, что он успел расшифровать. Только кнопкой
    /// «Остановить»: кнопка микрофона при её отсутствии включила бы запись заново.
    ///
    /// Расшифровка приходит ~0,7 с после «Остановить», поэтому просто подождать 0,4 с
    /// и почистить мало — текст ляжет в поле уже после уборки. Ждём его тем дольше, чем
    /// дольше микрофон слушал (`heardFor`): после сочетания клавиш он не слышал ничего,
    /// и следующая диктовка не должна стоять в очереди лишнюю секунду.
    private func shutMic(window: AXUIElement, textArea: AXUIElement?, heardFor: TimeInterval) {
        guard let stop = findStopButton(in: window) else {
            if let textArea { clearComposer(textArea) }
            return
        }
        AXUIElementPerformAction(stop, kAXPressAction as CFString)
        guard let textArea else { return }

        let heard = max(0, heardFor)
        let wait = min(1.2, 0.4 + heard)
        let pressed = Date()
        // Окно хвоста прошлой записи ещё открыто — изменение поля может быть её текстом,
        // а не нашим, поэтому своё окно открываем в любом случае.
        let olderTailOpen = pendingTail.map { $0.until > pressed } ?? false
        let before = readComposer(textArea)
        var arrivedAt: Date?
        while Date().timeIntervalSince(pressed) < wait {
            Thread.sleep(forTimeInterval: 0.1)
            if arrivedAt == nil, readComposer(textArea) != before { arrivedAt = Date() }
            if let arrivedAt, Date().timeIntervalSince(arrivedAt) >= 0.2 { break }
        }
        clearComposer(textArea)
        if arrivedAt != nil && !olderTailOpen { return }

        // Текст ещё не пришёл. Дольше очередь не держим — за ней может ждать следующая
        // диктовка, — а запоминаем, до какого момента он может лечь: по логу это до 1,2 с
        // на записях до 10 с и до ~3,2 с на минутных. Его учтут следующая сессия
        // (absorbLateTail), чужие запросы (waitUntilIdle) и отложенная уборка ниже.
        let own = pressed.addingTimeInterval(min(4.0, 1.3 + 0.04 * heard))
        let until = max(own, pendingTail?.until ?? own)
        pendingTail = (textArea, until)
        let requestedAtShutdown = currentRequestedSession()
        let epoch = sweepEpoch
        ax.asyncAfter(deadline: .now() + until.timeIntervalSinceNow + 0.3) { [weak self] in
            // Поле трогаем, только если его с тех пор никто не взял: ни новая диктовка,
            // ни запрос к Gemini через waitUntilIdle.
            guard let self, !self.isRecording, self.sweepEpoch == epoch,
                  self.currentRequestedSession() == requestedAtShutdown else { return }
            self.clearComposer(textArea)
            // Окно могли продлить более поздним выключением — тогда оно уже не наше.
            if self.pendingTail?.until == until { self.pendingTail = nil }
        }
    }

    // MARK: - Доступ к окну и полю

    private enum Composer {
        case ready(window: AXUIElement, textArea: AXUIElement)
        case notInstalled
        case notRunning
        /// Gemini запущен, но окна у него нет: в `kAXWindows` только пустая `AXGroup`,
        /// `kAXMainWindow` не отдаётся. Так выглядит приложение, у которого окно закрыли
        /// крестиком, а оно осталось жить в строке меню.
        case windowClosed(NSRunningApplication)
        /// Окно есть, но поля ввода в нём не видно.
        case composerUnavailable
    }

    private func runningGemini() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: GeminiBridgeService.bundleIdentifier).first
    }

    private func resolveComposer() -> Composer {
        guard let app = runningGemini() else {
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: GeminiBridgeService.bundleIdentifier) != nil
            return installed ? .notRunning : .notInstalled
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)

        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        let listed = windowsRef as? [AXUIElement] ?? []
        var candidates = listed
        // Свёрнутое окно не отдаётся через kAXWindows, но main-окно доступно,
        // а взятая ранее ссылка продолжает работать (см. AGENTS_SYNC.md, раздел 4.3).
        if let remembered = window { candidates.insert(remembered, at: 0) }
        for candidate in candidates {
            if let ta = findTextArea(in: candidate) { return .ready(window: candidate, textArea: ta) }
        }
        // Main-окно пробуем не только при пустом списке: у закрытого окна в списке
        // остаётся пустая AXGroup, а свёрнутое окно в список может не попасть вовсе.
        var mainRef: CFTypeRef?
        let mainResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainRef)
        if mainResult == .success, let main = mainRef as! AXUIElement? {
            if let ta = findTextArea(in: main) { return .ready(window: main, textArea: ta) }
            return .composerUnavailable
        }
        // «Закрыто» — только при точной сигнатуре: список окон прочитан и в нём нет ни одного
        // AXWindow, а main-окна нет (−25212). Любая другая ошибка AX — не повод открывать окно.
        let hasRealWindow = listed.contains { role(of: $0) == kAXWindowRole as String }
        let closed = windowsResult == .success && !hasRealWindow && mainResult == .noValue
        return closed ? .windowClosed(app) : .composerUnavailable
    }

    private func role(of element: AXUIElement) -> String {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        return roleRef as? String ?? ""
    }

    /// Будить Gemini (запуск, открытие окна) ради следующих диктовок стоит, только если
    /// нажатие оказалось настоящей диктовкой. Сочетание вроде ⌘+C на клавише-триггере
    /// отменяется через десятки миллисекунд — поэтому ждём до `moment` и смотрим, не
    /// отменили ли. Просто отпущенная сессия (без отмены) — настоящая диктовка.
    /// Состояние перепроверяется: за это время Gemini могли разбудить другим путём.
    private func wakeGeminiIfStillWanted(_ session: Int, after moment: Date) {
        ax.asyncAfter(deadline: .now() + max(0, moment.timeIntervalSinceNow)) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let cancelled = session <= self.cancelledThrough
            self.lock.unlock()
            guard !cancelled else { return }
            switch self.resolveComposer() {
            case .notRunning: self.launchHidden()
            case .windowClosed(let app): self.reopenClosedWindow(app)
            default: break
            }
        }
    }

    /// Gemini выключен — поднимаем его СКРЫТЫМ, чтобы следующая диктовка его застала.
    /// Обычный запуск (без hides) выбрасывал окно Gemini на экран, что пользователь
    /// и видел как «вызвался полноценный Gemini». Замерено: скрытый старт полностью рабочий.
    private func launchHidden() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: GeminiBridgeService.bundleIdentifier) else {
            return
        }
        Log.write("Gemini STT: приложение не запущено — поднимаю скрытым для следующих диктовок")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        let sema = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in sema.signal() }
        _ = sema.wait(timeout: .now() + 12)
        // Композер появляется не мгновенно — ждём, пока веб-часть отрисуется.
        let ready = waitForComposer(attempts: 25)
        Log.write(ready ? "Gemini STT: Gemini поднят, поле ввода на месте"
                        : "Gemini STT: Gemini поднят, но поле ввода так и не появилось")
    }

    /// Окно Gemini закрыли крестиком, приложение осталось в строке меню. Просим его открыть
    /// окно событием reopen без активации — крайняя мера из раздела 4.1, которой в том же
    /// состоянии уже пользуется GeminiAIProvider: окно возвращается, фокус остаётся у
    /// пользователя. Спрятанный при запуске Gemini остаётся спрятанным; видимый — получает
    /// окно позади текущего приложения (замер 24.09.2026, раздел 5.1). Свёрнутое окно сюда
    /// не попадает: у него другая сигнатура, и его не трогаем.
    private func reopenClosedWindow(_ app: NSRunningApplication) {
        guard let url = app.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: GeminiBridgeService.bundleIdentifier) else { return }
        Log.write("Gemini STT: окно Gemini закрыто — открываю его без активации для следующих диктовок")
        let previous = NSWorkspace.shared.frontmostApplication
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        let sema = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in sema.signal() }
        _ = sema.wait(timeout: .now() + 3)
        // Если фокус всё-таки ушёл к Gemini — возвращаем. Проверяем сразу: позже
        // пользователь мог переключиться на Gemini сам.
        if let previous, previous.processIdentifier != app.processIdentifier,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            previous.activate()
        }
        let ready = waitForComposer(attempts: 15)
        Log.write(ready ? "Gemini STT: окно Gemini открыто, поле ввода на месте"
                        : "Gemini STT: окно Gemini открыть не удалось")
    }

    private func waitForComposer(attempts: Int) -> Bool {
        for _ in 0..<attempts {
            Thread.sleep(forTimeInterval: 0.2)
            if case .ready = resolveComposer() { return true }
        }
        return false
    }

    private func readComposer(_ textArea: AXUIElement) -> String {
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(textArea, kAXValueAttribute as CFString, &valueRef)
        let text = ((valueRef as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Подсказка-заглушка полем не является.
        for placeholder in ["Спросить Gemini", "Ask Gemini"] where text == placeholder { return "" }
        return text
    }

    /// Чистим поле заменой выделения: подмену kAXValue веб-приложение не регистрирует
    /// (см. AGENTS_SYNC.md, раздел 4.1).
    private func clearComposer(_ textArea: AXUIElement) {
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(textArea, kAXValueAttribute as CFString, &valueRef)
        let length = ((valueRef as? String) ?? "").utf16.count
        guard length > 0 else { return }
        var range = CFRangeMake(0, length)
        if let rangeValue = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(textArea, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }
        AXUIElementSetAttributeValue(textArea, kAXSelectedTextAttribute as CFString, "" as CFTypeRef)
        Thread.sleep(forTimeInterval: 0.15)
    }

    // MARK: - Поиск элементов

    private func findTextArea(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 40 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        if role == "AXTextArea" { return element }
        if role == "AXOutline" { return nil }
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        for child in (childrenRef as? [AXUIElement]) ?? [] {
            if let found = findTextArea(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Кнопку ищем по вхождению подстроки в описание, но НЕ заходя в боковую панель:
    /// там сотни кнопок, а сообщения пользователя рендерятся кнопками с полным текстом
    /// внутри — по ним легко промахнуться (см. AGENTS_SYNC.md, раздел 4.6).
    private func findButton(in element: AXUIElement, anyOf needles: [String],
                            excluding stopWords: [String] = [], depth: Int = 0) -> AXUIElement? {
        if depth > 40 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        if role == "AXOutline" { return nil }
        if role == "AXButton" {
            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
            let desc = (descRef as? String ?? "").lowercased()
            // Длинные описания — это сообщения диалога, а не органы управления.
            if desc.count < 45, needles.contains(where: { desc.contains($0) }),
               !stopWords.contains(where: { desc.contains($0) }) { return element }
            return nil
        }
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        for child in (childrenRef as? [AXUIElement]) ?? [] {
            if let found = findButton(in: child, anyOf: needles, excluding: stopWords, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Кнопка остановки ЗАПИСИ. Под «останов»/«stop» подходят и чужие кнопки Gemini:
    /// «Остановить генерацию ответа» (пока Gemini отвечает) давала ложное «запись
    /// пошла», а её нажатие обрывало ответ; «Приостановить» — пауза озвучки.
    private func findStopButton(in window: AXUIElement) -> AXUIElement? {
        findButton(in: window, anyOf: ["останов", "stop"],
                   excluding: ["генерац", "ответ", "response", "приостанов", "pause"])
    }

    // MARK: - Дельта

    /// Новая речь = текущее содержимое поля минус то, что было до старта.
    /// Снимок обычно пуст (поле чистится перед стартом), но пользователь мог что-то
    /// печатать в Gemini сам — его текст возвращать нельзя.
    static func delta(full: String, base: String) -> String {
        let current = full.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previous.isEmpty else { return current }
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Поле переписали целиком — старого текста в нём уже нет, значит всё новое.
        return current == previous ? "" : current
    }
}
