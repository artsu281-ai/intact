import AppKit

/// Доставка текста в чужое приложение — цепочкой попыток, а не одной.
///
/// # Чем это отличается от прежнего подхода
///
/// Раньше мы **предсказывали** по дереву доступности, примет ли приложение
/// вставку, и при отрицательном ответе не пытались вставлять вовсе — сразу
/// показывали карточку «Скопировать». За это платили 23% отказов на живом
/// логе (43 «вставлять некуда» из 188 доставок), причём заметная часть
/// предсказаний была неверна: `AXGroup` в Electron выглядит как «не поле»,
/// а ⌘V туда проходит.
///
/// Разбор открытого кода тех, у кого вставка работает, показал, что **никто
/// из них не предсказывает**. VoiceInk просто шлёт ⌘V. Hex перебирает три
/// способа подряд (⌘V → пункт меню «Вставить» → Accessibility) и сдаётся
/// только когда провалились все. Espanso выбирает способ настройкой, а не
/// догадкой о поле.
///
/// Поэтому здесь: пробуем по-настоящему, по очереди, и карточку показываем
/// только когда цепочка кончилась. Проверка сохранена, но она теперь
/// **уточняет**, а не запрещает: пока способ не опровергнут измерением, он
/// считается сработавшим.
enum InsertionEngine {

    struct Outcome {
        let landed: Bool
        /// Каким способом дошло — для лога.
        let via: String
        /// Почему не дошло, человеческим языком, если не дошло.
        let reason: String?
    }

    private static let queue = DispatchQueue(label: "intact.insertion", qos: .userInitiated)

    /// Сколько ждём, пока целевое приложение реально станет фронтальным.
    ///
    /// `activate()` асинхронен. Раньше после него спали фиксированные 50–80 мс
    /// и шли дальше — иногда система не успевала, и решение принималось про
    /// одно приложение, а текст уходил в другое. Теперь ждём факт, а не срок.
    private static let activationTimeout: TimeInterval = 0.30

    /// Сколько ждём, пока приложение применит ⌘V, прежде чем мерить результат.
    private static let pasteSettleDelay: TimeInterval = 0.35

    /// Потолок ожидания факта «текст забрали». Опрашиваем с шагом 20 мс и
    /// выходим сразу, как только забрали, — обычно это первые же десятки
    /// миллисекунд. Потолок нужен только для случая, когда не забрали вовсе.
    private static let pasteMaxWait: TimeInterval = 0.6

    // MARK: - Точка входа

    static func deliver(_ text: String,
                        mode: OutputMode,
                        targetApp: NSRunningApplication?,
                        completion: ((Outcome) -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?(Outcome(landed: false, via: "—", reason: T("пустой текст", "empty text")))
            return
        }

        // Вся работа — на фоновой очереди. Раньше ожидания шли на главном
        // потоке, а на его ранлупе висит перехватчик клавиш: пока поток спит,
        // система вправе отключить перехватчик по таймауту, и нажатия,
        // пришедшие в это окно, теряются. Это самая частая клавиша в
        // приложении, терять её нельзя.
        queue.async {
            let outcome = run(text, mode: mode, targetApp: targetApp)
            DispatchQueue.main.async { completion?(outcome) }
        }
    }

    private static func run(_ text: String, mode: OutputMode, targetApp: NSRunningApplication?) -> Outcome {
        // Приложение могли закрыть, пока шло распознавание. У завершённого
        // `processIdentifier` равен −1, и все дальнейшие вопросы к нему
        // бессмысленны.
        let targetApp = (targetApp?.isTerminated == false) ? targetApp : nil

        if mode == .clipboard {
            Clipboard.write(text, transient: false, session: nil)
            return Outcome(landed: true, via: "буфер", reason: nil)
        }

        let arrived = bringForward(targetApp)

        // Клавишу-триггер могли ещё не отпустить: у нас триггеры — сами
        // модификаторы. ⌘V поверх зажатого ⌥ приходит как ⌥⌘V.
        if let forced = SyntheticKeyboard.settleModifiers() {
            Log.write("Вставка: модификаторы \(forced) пришлось отпустить за пользователя")
        }

        // Приложение вперёд не вышло — значит ⌘V получит не оно. Дальше
        // работаем с тем, кто впереди на самом деле, а не с тем, про кого
        // принималось решение: иначе текст уходит в чужое окно под рапорт
        // об успехе.
        let front = NSWorkspace.shared.frontmostApplication
        let wrongWindow = !arrived && front?.processIdentifier != targetApp?.processIdentifier
        if wrongWindow {
            Log.write("Вставка: «\(targetApp?.bundleIdentifier ?? "—")» не вышел вперёд за \(Int(activationTimeout * 1000)) мс, впереди «\(front?.bundleIdentifier ?? "—")»")
            guard FocusInspector.shouldDeliver(to: front) else {
                return giveUp(text, reason: T("окно получателя не вышло вперёд",
                                              "the target window did not come forward"))
            }
        }

        let element = wrongWindow
            ? AXText.systemWideFocusedElement()
            : (AXText.focusedElement(of: targetApp) ?? AXText.systemWideFocusedElement())

        if let element, AXText.isSecureField(element) {
            Clipboard.write(text, transient: false, session: nil)
            return Outcome(landed: false, via: "—",
                           reason: T("под курсором поле пароля — туда не вставляем",
                                     "the cursor is in a password field — we don't paste there"))
        }

        if mode == .type {
            guard let element, AXText.isTextInput(element) else {
                Clipboard.write(text, transient: false, session: nil)
                return Outcome(landed: false, via: "—",
                               reason: T("под курсором нет поля ввода", "no text field under the cursor"))
            }
            let before = AXText.snapshot(element)
            SyntheticKeyboard.typeOut(text)
            if AXText.verdict(before: before, after: AXText.snapshot(element),
                              inserted: text.utf16.count) != .landed {
                // Печать не подтвердилась. Раньше этот режим рапортовал успех
                // всегда и текст в буфер не клал — сказанное пропадало целиком.
                Clipboard.write(text, transient: false, session: nil)
                return Outcome(landed: false, via: "печать",
                               reason: T("не удалось подтвердить ввод",
                                         "could not confirm the text was typed"))
            }
            return Outcome(landed: true, via: "печать", reason: nil)
        }

        return pasteCascade(text, element: element)
    }

    // MARK: - Цепочка

    private static func pasteCascade(_ text: String, element: AXUIElement?) -> Outcome {
        let secureInput = SyntheticKeyboard.isSecureInputEnabled
        let inserted = text.utf16.count

        // Буфер пользователя снимаем один раз на всю цепочку и возвращаем один
        // раз в конце. Если снимать его внутри каждого звена, второе звено
        // снимет наш собственный текст, оставленный первым.
        let session = UUID().uuidString
        let saved = Clipboard.userSnapshot()

        func finish(_ outcome: Outcome, restoreClipboard: Bool) -> Outcome {
            if restoreClipboard {
                Clipboard.restore(saved, session: session, fallback: text)
            }
            return outcome
        }

        // 1. ⌘V — основной способ. Приложения понимают его лучше всего:
        //    работает отмена, работает форматирование, работает вставка поверх
        //    выделения. Пропускаем, только когда он заведомо мёртв.
        if !secureInput {
            let before = AXText.snapshot(element)
            guard let probe = Clipboard.writeWatched(text, session: session) else {
                return giveUp(text, reason: T("буфер обмена недоступен", "the clipboard is unavailable"))
            }
            Clipboard.waitForCommit()
            // Пауза между записью в буфер и ⌘V. У VoiceInk здесь 100 мс: без неё
            // приложение успевает прочитать буфер до того, как система его
            // опубликовала, и вставляет прежнее содержимое.
            usleep(100_000)

            probe.arm()
            SyntheticKeyboard.postPaste()

            // Ждём факт, а не срок. Раньше здесь стояла глухая пауза 0.35 с и
            // одно чтение после неё: быстрые приложения заставляли ждать зря,
            // медленные не успевали — и вставка объявлялась несостоявшейся,
            // хотя проходила.
            let startedWait = Date()
            let deadline = startedWait.addingTimeInterval(pasteMaxWait)
            var reading = probe.reading
            while reading == .never, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
                reading = probe.reading
            }

            // Главный сигнал — у нас забрали текст. Это факт: приложение,
            // обрабатывая ⌘V, читает буфер обмена.
            if reading == .afterPaste {
                Log.write("⌘V дошёл: текст забрали из буфера за \(Int(Date().timeIntervalSince(startedWait) * 1000)) мс")
                return finish(Outcome(landed: true, via: "⌘V", reason: nil), restoreClipboard: true)
            }

            // Измерение поля — второй сигнал: отвечает далеко не всегда (в
            // логе — `фокуса нет (код 0)`: запрос успешен, элемента нет).
            let measured = AXText.verdict(before: before, after: AXText.snapshot(element), inserted: inserted)
            if measured == .landed {
                Log.write("⌘V дошёл (по измерению поля)")
                return finish(Outcome(landed: true, via: "⌘V", reason: nil), restoreClipboard: true)
            }

            if reading == .beforePaste {
                // Обещание потратил чужой читатель ДО нашего ⌘V — сигнала
                // больше нет. Продолжать каскад вслепую нельзя: следующее
                // звено пишет в поле само и на живой вставке продублирует
                // текст. Если поле ничего не показало, честнее закончить
                // карточкой.
                if measured == .unmeasurable {
                    Log.write("⌘V: обещание из буфера забрали до вставки, поле молчит — сигнала нет")
                    return giveUp(text, reason: T("не удалось подтвердить вставку",
                                                  "could not confirm the text was pasted"))
                }
                Log.write("⌘V: обещание из буфера забрали до вставки — сужу по полю")
            }
            if measured == .failed {
                Log.write("⌘V не дошёл: текст из буфера не забрали, поле не изменилось — пробую дальше")
            } else {
                Log.write("⌘V не дошёл: текст из буфера никто не забрал")
            }
        } else {
            Log.write("Вставка: включён защищённый ввод — ⌘V пропускаем" +
                      (SyntheticKeyboard.secureInputHolder().map { ", держит «\($0)»" } ?? ""))
        }

        // 2. Прямая запись через Accessibility. Не трогает буфер, не зависит
        //    от раскладки, проходит при защищённом вводе.
        //
        //    Сюда попадаем, только когда текст из буфера **никто не забрал** —
        //    то есть ⌘V достоверно не сработал. Раньше на этом месте стоял
        //    запрет идти дальше при неизмеримом поле: без ловышки чтения
        //    отличить «вставилось, но не измерить» от «не вставилось» было
        //    нечем, и второй способ мог продублировать текст. Теперь отличить
        //    есть чем, и задвоения не будет.
        if let element {
            let before = AXText.snapshot(element)
            if AXText.insert(text, into: element) {
                let measured = AXText.verdict(before: before, after: AXText.snapshot(element), inserted: inserted)

                if measured == .landed {
                    return finish(Outcome(landed: true, via: "Accessibility", reason: nil), restoreClipboard: true)
                }

                // Код ответа приложения здесь — НЕ подтверждение.
                //
                // Раньше успехом считалось `verdict != .failed`, то есть
                // `.unmeasurable` шёл в зачёт: рассуждали так, что
                // `AXUIElementSetAttributeValue` возвращает ответ самого
                // приложения, а измерение лишь отсекает «ответил success и не
                // сделал ничего». Собственный журнал проекта говорит обратное
                // прямым текстом (§4.2): «код возврата
                // `AXUIElementSetAttributeValue` за доказательство не считать —
                // замёрзшее дерево отвечает `.success`».
                //
                // Отдельно про веб-композер. Единственная форма записи,
                // измеренная на нём как работающая, — ПАРА
                // `kAXSelectedTextRange` + `kAXSelectedText` (§4.1,
                // `GeminiAIProvider.insertAsUserInput`). `AXText.insert` пишет
                // только вторую половину, без установки диапазона; сработает
                // ли такая запись, на этом композере не мерил никто. Тем
                // важнее не выдавать её за успех без подтверждения.
                //
                // Складывалось это в худший исход во всём приложении: диктуют в
                // ПУСТОЕ поле, `before` = (0,0) неизмерим, запись ничего не
                // сделала, `after` тоже (0,0) — «Вставлено через Accessibility»,
                // звук успеха, а через 0.5 с `Clipboard.restore` кладёт поверх
                // прежний буфер. Сказанное исчезает целиком, и лог при этом
                // выглядит починкой.
                //
                // Обратной ошибки здесь нет: удавшаяся запись делает поле
                // измеримым (длина N, каретка N) и даёт `.landed`. Так что
                // `.unmeasurable` на этом шаге означает ровно «подтвердить
                // нечем», и выдавать его за успех нельзя.
                if measured == .unmeasurable {
                    // Дальше по каскаду не идём: печать на неизмеримом поле
                    // может задвоить текст, если запись всё же прошла. Карточка
                    // с текстом в буфере — исход, при котором ничего не теряется
                    // и ничего не дублируется.
                    Log.write("Accessibility: приложение приняло запись, но поле её не подтвердило — печатать вслепую не буду")
                    return giveUp(text, reason: T("не удалось подтвердить вставку",
                                                  "could not confirm the text was pasted"))
                }

                Log.write("Accessibility: запись поле не изменила — пробую печать")
            }
        }

        // 3. Печать. Последний способ, который вообще может сработать: он ни о
        //    чём не спрашивает приложение. При защищённом вводе бесполезен —
        //    синтетические нажатия туда не доходят по определению.
        if secureInput {
            return giveUp(text, reason: T("защищённый ввод блокирует вставку — снимите его в приложении, которое держит",
                                          "secure input is blocking insertion — clear it in the app holding it"))
        }
        // Печатать вслепую нельзя: если под курсором страница, а не поле, буквы
        // уедут в неё как горячие клавиши. Ответ «19:56» в Safari — это ⌘-меньше
        // нажатий «1», «9», «:», «5», «6» по странице.
        if let element, AXText.isTextInput(element) {
            let before = AXText.snapshot(element)
            SyntheticKeyboard.typeOut(text)
            if AXText.verdict(before: before, after: AXText.snapshot(element), inserted: inserted) == .landed {
                return finish(Outcome(landed: true, via: "печать", reason: nil), restoreClipboard: true)
            }
        }

        return giveUp(text, reason: T("под курсором нет поля ввода", "no text field under the cursor"))
    }

    /// Сдаёмся — но текст кладём в буфер **готовым значением**.
    ///
    /// Во время попытки он лежал там обещанием, а обещание выполняем мы: если
    /// Intact закроется, по ⌘V не появится ничего. Поэтому на выходе из
    /// цепочки обещание обязательно заменяется настоящей строкой.
    private static func giveUp(_ text: String, reason: String) -> Outcome {
        Clipboard.write(text, transient: false, session: nil)
        return Outcome(landed: false, via: "—", reason: reason)
    }

    // MARK: - Фокус

    /// Выводит целевое приложение вперёд и ждёт, пока это правда случится.
    ///
    /// - Returns: вышло ли приложение вперёд на самом деле. Раньше функция
    ///   ничего не возвращала, и цикл ожидания выходил по двум разным
    ///   причинам — «стало фронтальным» и «истекли 0.30 с» — одинаково молча.
    ///   Каскад шёл дальше при любом исходе, и на промахе ⌘V улетал в чужое
    ///   окно, а ловушка честно фиксировала «текст забрали» — забрал чужой.
    ///   Случай штатный: `targetApp` снимается в начале записи, а ответ Gemini
    ///   сам перетягивает фокус.
    @discardableResult
    private static func bringForward(_ app: NSRunningApplication?) -> Bool {
        guard let app,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !app.isActive else { return true }

        DispatchQueue.main.async { app.activate() }

        var arrived = false
        let deadline = Date().addingTimeInterval(activationTimeout)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                arrived = true
                break
            }
            usleep(10_000)
        }
        guard arrived else { return false }
        // Веб-движок восстанавливает фокус внутри страницы асинхронно, уже
        // после того, как окно стало фронтальным.
        usleep(60_000)
        return true
    }
}

// MARK: - Буфер обмена

/// Ловушка «наш текст кто-то забрал».
///
/// Главный сигнал успеха вставки. Логика простая: приложение, обрабатывая ⌘V,
/// **читает буфер обмена**. Если положить текст не готовым значением, а обещанием
/// (`NSPasteboardItemDataProvider`), то система позовёт нас в тот момент, когда
/// его действительно запросят, — и мы узнаем факт, а не догадаемся о нём.
///
/// Зачем это понадобилось: измерение поля через дерево доступности отвечает
/// далеко не всегда. В логе живьём — `фокуса нет (код 0)`: запрос успешен,
/// элемента нет, мерить нечего. При этом ⌘V туда проходит. Строить на таком
/// сигнале решение «показывать ли карточку» нельзя, он там просто отсутствует.
///
/// Ложное срабатывание возможно от менеджеров буфера обмена, которые опрашивают
/// его по таймеру. От них защищают метки `org.nspasteboard.TransientType` и
/// `AutoGeneratedType` — соглашение, которое они понимают, — и то, что чтения
/// считаются только после отправки ⌘V.
private final class PasteProbe: NSObject, NSPasteboardItemDataProvider {
    /// Кто и когда забрал текст.
    ///
    /// Исходов три, а не два, и это принципиально: обещание **одноразовое**.
    /// Система зовёт поставщика ровно раз, дальше значение лежит в элементе
    /// готовым. Между публикацией и нашим ⌘V проходит 100–250 мс, и если в это
    /// окно в буфер заглянул менеджер (Maccy, Paste, Raycast) или Spotlight,
    /// обещание тратится на него. Прежняя версия писала `read` только при
    /// взведённой ловушке — то есть такое чтение просто терялось, и дальше
    /// «текст не забрали» означало и настоящий провал ⌘V, и уничтоженный
    /// сигнал. Теперь время чтения пишется безусловно, а решает сравнение.
    enum Reading {
        /// Никто не читал: ⌘V не сработал.
        case never
        /// Забрали после нашего ⌘V — вставка прошла.
        case afterPaste
        /// Обещание потратил кто-то до ⌘V. Сигнала больше нет, судить нечем.
        case beforePaste
    }

    private let text: String
    private let lock = NSLock()
    private var armedAt: Date?
    private var readAt: Date?

    init(text: String) { self.text = text }

    /// С этого момента чужое чтение означает вставку. До него — чей-то опрос.
    func arm() { lock.lock(); armedAt = Date(); lock.unlock() }

    var reading: Reading {
        lock.lock(); defer { lock.unlock() }
        guard let readAt else { return .never }
        guard let armedAt else { return .beforePaste }
        return readAt > armedAt ? .afterPaste : .beforePaste
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString(text, forType: type)
        lock.lock()
        if readAt == nil { readAt = Date() }
        lock.unlock()
    }
}

/// Аккуратная работа с буфером: сохранить всё, подменить, вернуть.
///
/// Прежняя версия сохраняла только `.string` и возвращала его безусловно
/// через 0.85 с. Из-за этого терялось всё остальное — картинки, файлы,
/// форматированный текст, — а быстрые диктовки подряд затирали буфер друг
/// друга. Снимок «все элементы, все типы» и охранный токен взяты у VoiceInk
/// и Hex, там это ровно та же задача.
enum Clipboard {

    private static let sessionType = NSPasteboard.PasteboardType("com.artsu.intact.PasteSession")
    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let autoGeneratedType = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")

    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    /// Поставщик текущего обещания. Держим ссылку: система зовёт его позже, и
    /// освобождать его до этого нельзя. Под замком — к нему обращаются и с
    /// очереди доставки, и с главного потока (карточка, возврат буфера).
    private static var _probe: PasteProbe?
    private static let probeLock = NSLock()
    private static var probe: PasteProbe? {
        get { probeLock.lock(); defer { probeLock.unlock() }; return _probe }
        set { probeLock.lock(); _probe = newValue; probeLock.unlock() }
    }

    private static func snapshot() -> Snapshot {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    /// Снимок буфера пользователя — не наш собственный.
    ///
    /// Две быстрые диктовки подряд ловили такую ловушку: вторая снимала буфер
    /// в тот момент, когда там лежал текст первой, и «восстанавливала» его
    /// потом как «прежнее содержимое». Настоящий буфер человека — ссылка,
    /// картинка, что угодно — пропадал навсегда, а взамен появлялся текст
    /// предыдущей диктовки.
    ///
    /// Поэтому: если в буфере наша же метка сессии, берём то, что мы отложили
    /// в прошлый раз, а не то, что лежит сейчас.
    private static var carried: Snapshot = []
    private static let carryLock = NSLock()

    /// Сколько ждём снимок, прежде чем признать его несостоявшимся.
    private static let snapshotTimeout: TimeInterval = 0.3

    /// `nil` — снимок не удался, прежнее содержимое буфера нам неизвестно.
    ///
    /// Отличать `nil` от пустого массива обязательно: пустой значит «буфер и
    /// был пуст», и тогда восстанавливать нечего, а `nil` значит «мы не знаем,
    /// что там было» — стереть буфер в этом случае значит отнять у человека
    /// его копию.
    ///
    /// Почему с потолком. `item.data(forType:)` для «обещанного» типа — это
    /// синхронный поход в главный поток чужого приложения без всякого
    /// таймаута, и ждём мы ровно столько, сколько тот думает. Так кладут в
    /// буфер Finder, Excel, Numbers, Photoshop, Figma, Chrome — десяток
    /// «плоских» вариантов на одно ⌘C. А очередь вставки последовательная:
    /// одна такая диктовка вешала не только себя, но и все следующие, причём
    /// молча — индикатор к тому моменту уже погашен, а completion не позовут
    /// никогда. Ни звука, ни карточки, ни текста в буфере: блокировка
    /// наступала раньше записи.
    static func userSnapshot() -> Snapshot? {
        carryLock.lock()
        let isOurs = NSPasteboard.general.string(forType: sessionType) != nil
        if isOurs {
            defer { carryLock.unlock() }
            return carried
        }
        carryLock.unlock()

        final class Box {
            let lock = NSLock()
            var value: Snapshot?
            var abandoned = false
        }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let snap = snapshot()
            box.lock.lock()
            let abandoned = box.abandoned
            if !abandoned { box.value = snap }
            box.lock.unlock()
            // Опоздавшего работника к `carried` не пускаем: он перезапишет
            // отложенное содержимое устаревшим снимком.
            if !abandoned {
                carryLock.lock(); carried = snap; carryLock.unlock()
            }
            done.signal()
        }

        if done.wait(timeout: .now() + snapshotTimeout) == .timedOut {
            box.lock.lock(); box.abandoned = true; box.lock.unlock()
            Log.write("Буфер: снимок не успел за \(Int(snapshotTimeout * 1000)) мс — прежнее содержимое неизвестно")
            return nil
        }
        box.lock.lock(); defer { box.lock.unlock() }
        return box.value
    }

    /// Кладёт текст готовым значением. Для режима «только в буфер» и для
    /// запасного пути, где ловушка не нужна.
    @discardableResult
    static func write(_ text: String, transient: Bool, session: String?) -> Bool {
        let pb = NSPasteboard.general
        // Порядок важен: сначала снять обещание с буфера, потом отпускать
        // поставщика. При обратном порядке между двумя строками остаётся окно,
        // в котором обещание на буфере есть, а объекта, который его выполнит,
        // уже нет — и запрос от менеджера буфера (Maccy, Paste, Raycast)
        // попадает в освобождённый объект.
        pb.clearContents()
        probe = nil
        guard pb.setString(text, forType: .string) else { return false }
        decorate(pb, transient: transient, session: session)
        return true
    }

    /// Кладёт текст обещанием и возвращает ловушку, по которой потом видно,
    /// забрал ли его кто-нибудь.
    /// Возвращает саму ловушку, а не «получилось/нет».
    ///
    /// Раньше каскад спрашивал её через статику `Clipboard.probe`, а ту
    /// обнуляет отложенный возврат буфера с ГЛАВНОГО потока. Две диктовки
    /// подряд — и вторая читала сигнал по ловушке, которую первая уже
    /// затёрла. Держать ловушку надо там, где идёт каскад: локально.
    /// Статика остаётся ровно для одного — не дать объекту умереть, пока
    /// обещание висит на буфере.
    fileprivate static func writeWatched(_ text: String, session: String) -> PasteProbe? {
        let pb = NSPasteboard.general
        commitBaseline = pb.changeCount
        let probe = PasteProbe(text: text)
        let item = NSPasteboardItem()
        // Текст — обещанием: система позовёт поставщика, когда его запросят.
        guard item.setDataProvider(probe, forTypes: [.string]) else { return nil }
        pb.clearContents()
        guard pb.writeObjects([item]) else { return nil }
        decorate(pb, transient: true, session: session)
        Self.probe = probe
        return probe
    }

    /// - Parameter transient: пометить содержимое как временное, чтобы
    ///   менеджеры буфера обмена (Maccy, Paste, Raycast) не тащили каждую
    ///   диктовку к себе в историю. Соглашение `org.nspasteboard.*` они
    ///   понимают все.
    private static func decorate(_ pb: NSPasteboard, transient: Bool, session: String?) {
        if let bundle = Bundle.main.bundleIdentifier { pb.setString(bundle, forType: sourceType) }
        if transient {
            pb.setData(Data(), forType: transientType)
            pb.setData(Data(), forType: autoGeneratedType)
        }
        if let session { pb.setString(session, forType: sessionType) }
    }

    /// Ждёт, пока система опубликует запись.
    ///
    /// `setString` возвращается раньше, чем содержимое становится видно
    /// другим процессам. Раньше здесь стояла фиксированная пауза 20 мс —
    /// иногда её не хватало, и приложение вставляло прежний буфер. Ждём
    /// факт публикации по `changeCount`, как это делает Hex.
    /// Счётчик буфера, снятый ДО записи. Без него ждать нечего.
    private static var commitBaseline = -1

    static func waitForCommit(timeout: TimeInterval = 0.15) {
        // Раньше счётчик снимался прямо здесь — то есть уже после того, как
        // запись прошла, — и условие `changeCount >= target` выполнялось на
        // первой же итерации. Функция возвращалась мгновенно и не ждала
        // ничего. Практических последствий это почти не имело: сразу за ней
        // идёт фиксированная пауза 100 мс, она и делала работу. Но выглядело
        // как ожидание, которого не было.
        let baseline = commitBaseline
        guard baseline >= 0 else { return }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSPasteboard.general.changeCount > baseline { return }
            usleep(5_000)
        }
        Log.write("Буфер: система не подтвердила публикацию за \(Int(timeout * 1000)) мс")
    }

    /// Возвращает прежнее содержимое — но только если буфер всё ещё наш.
    ///
    /// Охрана по токену, а не по тексту: во-первых, пользователь мог за это
    /// время скопировать ровно ту же строку сам, и тогда возврат отнял бы у
    /// него его же копию; во-вторых, читать `.string` нам теперь нельзя — это
    /// дёрнуло бы собственную ловушку и подделало сигнал.
    static func restore(_ saved: Snapshot?, session: String, fallback text: String,
                        after delay: TimeInterval = 0.5) {
        // Раннего выхода по пустому снимку здесь быть не должно.
        //
        // Пустой снимок значит «до диктовки буфер был пуст», а не «делать
        // нечего»: наш текст лежит в буфере ОБЕЩАНИЕМ, и снять его всё равно
        // обязаны мы. Иначе обещание остаётся висеть, а когда Intact закроют
        // или он упадёт, выполнять его станет некому — и ⌘V у человека начнёт
        // давать пустоту. Поэтому решение про пустой снимок принимается уже
        // внутри блока, под охраной токена сессии.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let pb = NSPasteboard.general
            guard pb.string(forType: sessionType) == session else { return }
            // Сначала снимаем обещание с буфера, потом отпускаем поставщика —
            // см. комментарий в `write`.
            pb.clearContents()
            probe = nil
            guard let saved else {
                // Снимок не удался — что лежало в буфере до диктовки, мы не
                // знаем. Стирать его начисто нельзя, а вернуть нечего;
                // оставляем продиктованный текст готовой строкой, как это
                // делает `giveUp`. Человек хотя бы вставит его руками.
                pb.setString(text, forType: .string)
                return
            }
            guard !saved.isEmpty else { return }
            pb.writeObjects(saved.map { dict in
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                return item
            })
        }
    }
}
