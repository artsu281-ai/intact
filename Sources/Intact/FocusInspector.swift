import AppKit
import ApplicationServices

/// Что мы знаем о том, куда сейчас поедет текст.
///
/// # Важное изменение подхода
///
/// Раньше этот файл **решал**, вставлять или нет, по дереву доступности: нет
/// подходящего элемента — текст не вставляем вовсе, показываем карточку
/// «Скопировать». На живом логе это давало 23% отказов, и заметная часть из
/// них была ошибкой предсказания, а не отсутствием поля.
///
/// Никто из тех, у кого вставка работает, так не делает: VoiceInk шлёт ⌘V
/// без вопросов, Hex перебирает три способа подряд. Решение о вставке
/// переехало в `InsertionEngine`, который **пробует**, а не гадает.
///
/// Здесь осталось три вещи, которые по-прежнему нужны:
/// 1. Узкая политика «сюда не вставляем никогда» — свои же окна и
///    приложения-посредники (`shouldDeliver(to:)`).
/// 2. Пробуждение дерева доступности у Chromium (`ensureAccessibilityTree`).
/// 3. Описание текущего фокуса для лога (`focusDescription`).
enum FocusInspector {

    /// Куда не вставляем ни при каких обстоятельствах.
    ///
    /// Это политика, а не догадка о поле: сюда попадают наши собственные окна
    /// и посредники, через которых мы сами и спрашиваем модель. Если ответ
    /// придёт в момент, когда фронтом оказалось окно Gemini, «вставить»
    /// означало бы вписать ответ в его же поле ввода — а человек при этом не
    /// увидит вообще ничего.
    private static let excludedBundles: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine"
    ]

    /// Приложение-посредник, через которое мы сами и спрашиваем модель.
    ///
    /// Сравнение **точное**, и это принципиально. Экземпляр Gemini бывает не
    /// один: в настройках выбирают копию (Double Bubble) с идентификатором вида
    /// `com.google.GeminiMacOS.doublebubble.<хеш>`, и раньше здесь стояло
    /// `hasPrefix(mainBundleIdentifier)` — чтобы копия тоже попадала под запрет.
    /// Но `hasPrefix` истинен и для строки, **равной** префиксу, поэтому под
    /// запрет попадало и само основное приложение.
    ///
    /// У того, кто выбрал мостом копию, это отсекало ровно то окно, ради
    /// свободы которого копию и заводят (§4.5): на живом логе 26 доставок в
    /// `com.google.GeminiMacOS` и ни одной вставки, причём строкой выше лог
    /// писал `фокус: AXTextArea` — поле было живым, каскад просто не звали.
    ///
    /// Мост в любой момент ровно один — тот, что вернёт
    /// `GeminiBridgeService.bundleIdentifier`; через него же резолвят
    /// посредника и провайдер, и STT, и прямая отправка. Всё остальное
    /// семейство — обычные приложения пользователя, куда диктовка обязана
    /// доезжать.
    private static func isGeminiBridge(_ bundleId: String) -> Bool {
        bundleId == GeminiBridgeService.bundleIdentifier
    }

    /// Можно ли вообще доставлять текст в это приложение.
    ///
    /// Единственная оставшаяся проверка «до» вставки. Она про приложение
    /// целиком, а не про элемент под курсором: про элемент честно ответит
    /// только сама попытка.
    static func shouldDeliver(to app: NSRunningApplication?) -> Bool {
        refusalReason(for: app) == nil
    }

    /// Та же лестница условий, но названная словами — для лога.
    ///
    /// `nil` значит «доставлять можно». Отдельная функция, а не второй список
    /// условий рядом: расхождение между тем, что мы делаем, и тем, что пишем в
    /// лог, — худший вид лога. Здесь один источник истины, `shouldDeliver`
    /// сведён к нему.
    ///
    /// Зачем понадобилось. Из трёх мест доставки причину отказа писали два, а
    /// третье — пайплайновое, то самое, через которое идёт вся работа, — не
    /// писало ничего: в логе оставалась безличная строка «вставить некуда»,
    /// одинаковая и для «политика запретила», и для «каскад провалился».
    /// Отличить их можно было только чтением исходников.
    static func refusalReason(for app: NSRunningApplication?) -> String? {
        let bundleId = (app ?? NSWorkspace.shared.frontmostApplication)?.bundleIdentifier ?? ""
        if bundleId.isEmpty {
            return T("у приложения-получателя нет идентификатора",
                     "the receiving app has no bundle identifier")
        }
        if bundleId == Bundle.main.bundleIdentifier {
            return T("это собственное окно Intact", "this is Intact's own window")
        }
        if isGeminiBridge(bundleId) {
            return T("«\(bundleId)» — посредник, через который мы сами спрашиваем модель",
                     "«\(bundleId)» is the bridge we ask the model through")
        }
        if excludedBundles.contains(bundleId) {
            return T("«\(bundleId)» — системное окно", "«\(bundleId)» is a system window")
        }
        return nil
    }

    /// Короткое описание того, что видно прямо сейчас — для лога.
    /// Без него разбор «почему текст ушёл в никуда» требует отдельного скрипта.
    static func focusDescription(for app: NSRunningApplication? = nil) -> String {
        let target = app ?? NSWorkspace.shared.frontmostApplication
        guard let target else { return "нет активного приложения" }
        let bundleId = target.bundleIdentifier ?? "—"
        guard let element = AXText.focusedElement(of: target) else {
            return "\(bundleId), фокуса нет (код \(AXText.lastLookupError.rawValue))"
        }
        let role = AXText.role(element)
        let subrole = AXText.subrole(element)
        return "\(bundleId), фокус: \(role)\(subrole.isEmpty ? "" : "/\(subrole)")"
    }

    // MARK: - Пробуждение дерева доступности у Chromium

    /// Когда приложению в последний раз ставили `AXManualAccessibility`.
    private static var armedAt: [pid_t: Date] = [:]
    private static let armLock = NSLock()

    /// Chromium **сам выключает** дерево доступности, когда им какое-то время
    /// никто не пользуется. Поэтому одного включения на запуск приложения не
    /// хватает — атрибут надо переставлять. Держим паузу, чтобы не дёргать
    /// его на каждое нажатие.
    private static let rearmInterval: TimeInterval = 120

    /// Включает у приложения дерево доступности.
    ///
    /// Chromium (Chrome, Electron: Claude Desktop, Antigravity, Slack, VS Code)
    /// по умолчанию не публикует дерево веб-содержимого — оно включается только
    /// когда его запросит вспомогательная технология. Пока оно выключено, окно
    /// выглядит так:
    ///
    ///     AXWindow «Claude»
    ///       AXGroup → AXGroup → AXGroup → AXGroup   (и ничего больше)
    ///       AXButton (закрыть / развернуть / свернуть)
    ///
    /// Ни `AXWebArea`, ни полей, ни `AXFocusedUIElement` — отсюда и вечное
    /// −25212, и карточка «Скопировать» вместо вставки.
    ///
    /// **Просыпается не мгновенно.** В коде Chromium и Electron это
    /// `enableScreenReaderCompleteModeAfterDelay` с константой
    /// `kTwoSecondDelay = 2.0` — то есть две секунды после запроса, плюс
    /// время на построение дерева. Поэтому звать это надо в начале записи,
    /// пока человек говорит, а не в момент вставки.
    ///
    /// Тем, кто атрибута не понимает, вызов безвреден: возвращается −25205
    /// или −25208, и ничего не происходит.
    ///
    /// **`AXEnhancedUserInterface` мы больше не ставим.** Electron его и не
    /// принимает (в логе `enhanced=-25208`, `kAXErrorNotImplemented`), а вот
    /// нативные Cocoa-приложения принимают — и это известный способ сломать
    /// им изменение размеров окон, на чём обжигались авторы оконных
    /// менеджеров. Пользы ноль, риск настоящий.
    static func ensureAccessibilityTree(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid > 0,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              Permissions.accessibility else { return }

        armLock.lock()
        let last = armedAt[pid]
        let due = last.map { Date().timeIntervalSince($0) > rearmInterval } ?? true
        // Отметку ставим только когда правда собрались включать. Раньше pid
        // вносился в список ДО проверки прав — один ранний вызов без
        // «Универсального доступа», и приложение помечено «уже сделано»
        // навсегда, а дерево у него так и не проснулось.
        if due { armedAt[pid] = Date() }
        armLock.unlock()
        guard due else { return }

        // Сам AX-запрос — с фоновой очереди.
        //
        // Это синхронный поход в чужой процесс, и хотя таймаут ограничен
        // четвертью секунды, зовут эту функцию из наблюдателя за
        // переключением приложений, то есть на КАЖДЫЙ переход между окнами и
        // всегда на главном потоке. А на главном ранлупе висит перехватчик
        // клавиш (`InputEventManager.swift`, `CFRunLoopAddSource(CFRunLoopGetMain(), …)`):
        // пока поток занят, события к нему не идут, и система вправе отключить
        // перехватчик по таймауту. Он переподключается сам, но нажатия,
        // пришедшие в это окно, теряются — а это самая частая клавиша
        // приложения. Ответ нам не нужен ни для чего, кроме строки лога,
        // так что ждать его на главном потоке незачем.
        //
        // Учёт `armedAt` остаётся выше и под замком, поэтому переносить его
        // сюда не требуется.
        let bundleId = app.bundleIdentifier ?? "—"
        DispatchQueue.global(qos: .utility).async {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.25)
            let result = AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            if result == .success, last == nil {
                Log.write("Дерево доступности запрошено у «\(bundleId)»")
            }
        }
    }

    /// Проснулось ли дерево. Chromium и Electron отдают этот атрибут на
    /// чтение (`accessibilityAttributeValue:@"AXManualAccessibility"` →
    /// «режим доступности полный»), так что гадать не нужно.
    static func accessibilityTreeIsAwake(for app: NSRunningApplication) -> Bool? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXManualAccessibility" as CFString, &ref) == .success,
              let number = ref as? NSNumber else { return nil }
        return number.boolValue
    }
}
