import AppKit
import Carbon
import EventKit
import Foundation

// Низкоуровневые исполнители инструментов ассистента (план E.1, B.4, C.4).
//
// Всё здесь синхронное и вызывается с последовательной очереди инструментов,
// никогда с main: каждая операция ограничена по времени (EventKit 5 с,
// AppleScript 10 с, запуск программы 5 с), ошибки — `AssistantToolError` с
// текстом для карточки.
//
// Разрешения TCC внутри операций не запрашиваются никогда. Системный диалог
// посреди действия выскочил бы поверх чужого окна, а шаг ждал бы человека.
// Нет доступа — ошибка с `.permission`, а сам запрос — отдельной функцией,
// которую зовёт кнопка [Разрешить].
//
// В лог уходят только счётчики и виды действий, никогда не текст: заголовки
// напоминаний и заметок — это то, что человек продиктовал.

// MARK: - Общее

/// Состояние разрешения для карточки: [Разрешить] имеет смысл, только пока
/// система ещё может показать диалог, иначе — [Открыть настройки].
enum AssistantAccess: Equatable {
    case granted
    case notDetermined
    /// Календарь «только запись»: создать событие можно, а прочитать его для
    /// правки и отмены — нет (план 0.1 п. 3). Система умеет поднять до полного.
    case writeOnly
    case denied

    var canRequest: Bool { self == .notDetermined || self == .writeOnly }
}

/// Ждёт работу не дольше срока. Саму работу прервать нельзя — ни EventKit, ни
/// Launch Services отмены не знают, — поэтому после тайм-аута она может
/// завершиться позже. Очередь у каждой службы своя и последовательная: зависшая
/// операция задерживает следующие, но не выполняется с ними наперегонки.
///
/// После тайм-аута человеку уже сказано «не ответил». Поэтому работа, которая к
/// сроку не успела начаться (очередь стояла за зависшей предыдущей), не
/// начинается вовсе, а начатая видит `abandoned` и откатывает созданное: иначе
/// элемент появился бы позже без квитанции и без отмены, а повтор дал бы дубль.
private enum Bounded {
    final class Attempt {
        private let lock = NSLock()
        private var gaveUp = false
        var abandoned: Bool { lock.lock(); defer { lock.unlock() }; return gaveUp }
        func abandon() { lock.lock(); gaveUp = true; lock.unlock() }
    }

    static func run<Value>(seconds: TimeInterval, on queue: DispatchQueue, timeout: String,
                           _ work: @escaping (Attempt) throws -> Value) throws -> Value {
        let attempt = Attempt()
        let done = DispatchSemaphore(value: 0)
        var result: Result<Value, Error>?
        queue.async {
            if !attempt.abandoned { result = Result { try work(attempt) } }
            done.signal()
        }
        guard done.wait(timeout: .now() + seconds) == .success, let result else {
            attempt.abandon()
            throw AssistantToolError(message: timeout)
        }
        return try result.get()
    }
}

/// Имя, заголовок, место: одна строка без управляющих символов.
private func singleLine(_ text: String) -> String {
    text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .filter { !($0.unicodeScalars.first.map { $0.properties.generalCategory == .control } ?? false) }
}

// MARK: - Календарь и напоминания

/// EventKit ассистента: события и напоминания через один `EKEventStore`.
///
/// Магазин один на оба вида: он тяжёлый при создании, а идентификаторы,
/// которые он выдаёт, глобальны — напоминание из regex-пути (у
/// `AppleRemindersService` свой магазин) находится и здесь, и его можно отменить.
enum AssistantEvents {
    private static let store = EKEventStore()
    private static let queue = DispatchQueue(label: "intact.assistant.eventkit", qos: .userInitiated)

    /// Поля события, которые сверяются перед правкой и отменой: если человек
    /// успел поменять событие сам, Intact его не трогает. Снимок, а не
    /// `lastModifiedDate`: синхронизация iCloud и CalDAV сдвигает дату изменения.
    struct EventSnapshot: Equatable {
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
    }

    struct ReminderSnapshot: Equatable {
        let title: String
        let due: Date?
        let dueHasTime: Bool
        let completed: Bool
    }

    // MARK: Разрешения

    static var calendarAccess: AssistantAccess { access(for: .event) }
    static var remindersAccess: AssistantAccess { access(for: .reminder) }

    /// Только по кнопке. `completion` — на main.
    static func requestCalendarAccess(completion: @escaping (Bool) -> Void) {
        request(.event, usageKey: "NSCalendarsFullAccessUsageDescription", completion: completion)
    }

    /// Только по кнопке. `completion` — на main.
    static func requestRemindersAccess(completion: @escaping (Bool) -> Void) {
        request(.reminder, usageKey: "NSRemindersFullAccessUsageDescription", completion: completion)
    }

    private static func access(for type: EKEntityType) -> AssistantAccess {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return .granted
        case .writeOnly: return .writeOnly
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Без строки описания в Info.plist система не покажет диалог (а на части
    /// версий завершит приложение), поэтому сначала проверяем, что она есть.
    private static func request(_ type: EKEntityType, usageKey: String, completion: @escaping (Bool) -> Void) {
        guard Bundle.main.object(forInfoDictionaryKey: usageKey) != nil else {
            Log.write("ассистент: в Info.plist нет \(usageKey) — доступ не запрашиваю")
            DispatchQueue.main.async { completion(false) }
            return
        }
        let done: EKEventStoreRequestAccessCompletionHandler = { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
        if type == .event {
            store.requestFullAccessToEvents(completion: done)
        } else {
            store.requestFullAccessToReminders(completion: done)
        }
    }

    private static func requireAccess(_ type: EKEntityType) throws {
        let access = access(for: type)
        guard access != .granted else { return }
        let permission: AssistantPermission = type == .event ? .calendars : .reminders
        let message: String
        switch (type, access) {
        case (.event, .writeOnly):
            message = T("Нужен полный доступ к Календарю: без него Intact не сможет поправить или отменить своё событие",
                        "Intact needs full Calendar access to edit or undo its own events")
        case (.event, .notDetermined):
            message = T("Нужен доступ к Календарю — нажмите «Разрешить»", "Intact needs Calendar access — press Allow")
        case (.event, _):
            message = T("Нет доступа к Календарю — включите Intact в Настройках → Конфиденциальность → Календари",
                        "No Calendar access — turn on Intact in Settings → Privacy → Calendars")
        case (_, .notDetermined), (_, .writeOnly):
            message = T("Нужен доступ к Напоминаниям — нажмите «Разрешить»", "Intact needs Reminders access — press Allow")
        default:
            message = T("Нет доступа к Напоминаниям — включите Intact в Настройках → Конфиденциальность → Напоминания",
                        "No Reminders access — turn on Intact in Settings → Privacy → Reminders")
        }
        throw AssistantToolError(message: message, permission: permission)
    }

    private static func bounded<Value>(_ type: EKEntityType,
                                       _ work: @escaping (Bounded.Attempt) throws -> Value) throws -> Value {
        try Bounded.run(seconds: 5, on: queue,
                        timeout: type == .event
                            ? T("Календарь не ответил за 5 с", "Calendar didn't respond in 5 s")
                            : T("Напоминания не ответили за 5 с", "Reminders didn't respond in 5 s"),
                        work)
    }

    /// Ошибку EventKit показываем как есть (в ней нет текста человека), в лог — только код.
    private static func failure(_ what: String, _ error: Error) -> AssistantToolError {
        Log.write("ассистент: EventKit, \(what): код \((error as NSError).code)")
        return AssistantToolError(message: error.localizedDescription)
    }

    private static let marker = T("Создано через Intact", "Created with Intact")

    private static func gregorian(_ timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    // MARK: События

    /// Событие в календаре по умолчанию (B.4). Без конца — час; дата без
    /// времени — событие на весь день. Возвращает `eventIdentifier`.
    static func addEvent(title: String, start: AssistantDate, end: AssistantDate?, place: String?) throws -> String {
        try requireAccess(.event)
        let title = singleLine(title)
        guard !title.isEmpty else { throw AssistantToolError(message: T("Пустое название события", "The event has no title")) }
        let place = place.map(singleLine) ?? ""
        return try bounded(.event) { attempt in
            // Магазин, созданный до выдачи доступа в Настройках, не видит
            // календарей, пока его не сбросить.
            if store.defaultCalendarForNewEvents == nil { store.reset() }
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw AssistantToolError(message: T("Нет календаря по умолчанию — выберите его в Календаре",
                                                    "No default calendar — choose one in Calendar"))
            }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = title
            event.notes = marker
            if !place.isEmpty { event.location = place }
            setTimes(of: event, start: start, end: end, duration: 3600)
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw failure("сохранение события", error)
            }
            if attempt.abandoned {
                try? store.remove(event, span: .thisEvent, commit: true)
                Log.write("ассистент: событие сохранилось уже после тайм-аута — убрано")
                throw AssistantToolError(message: T("Календарь не ответил за 5 с", "Calendar didn't respond in 5 s"))
            }
            guard let id = event.eventIdentifier else {
                throw AssistantToolError(message: T("Календарь не вернул идентификатор события", "Calendar returned no event id"))
            }
            Log.write("ассистент: событие создано (\(event.isAllDay ? "на весь день" : "со временем"))")
            return id
        }
    }

    /// Правка своего события. Перенос начала сохраняет длительность: «перенеси
    /// на три» не должно сжимать двухчасовую встречу до часа, а перенос
    /// события «пт–пн» на весь день — сжимать его до одного дня.
    static func updateEvent(id: String, title: String?, start: AssistantDate?, end: AssistantDate?) throws {
        try requireAccess(.event)
        let title = title.map(singleLine)
        try bounded(.event) { _ in
            let event = try existingEvent(id)
            if let title, !title.isEmpty { event.title = title }
            let span = event.endDate.timeIntervalSince(event.startDate)
            let duration = event.isAllDay ? 3600 : max(60, span)
            let days = event.isAllDay ? max(1, Int((span / 86_400).rounded())) : 1
            if let start {
                setTimes(of: event, start: start, end: end, duration: duration, days: days)
            } else if let end {
                if end.hasTime, !event.isAllDay, end.date <= event.startDate {
                    throw AssistantToolError(message: T("Конец раньше начала события", "The end is before the start"))
                }
                let current = AssistantDate(date: event.startDate, hasTime: !event.isAllDay)
                setTimes(of: event, start: current, end: end, duration: duration)
            }
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw failure("правка события", error)
            }
        }
    }

    static func removeEvent(id: String) throws {
        try requireAccess(.event)
        try bounded(.event) { _ in
            let event = try existingEvent(id)
            do {
                try store.remove(event, span: .thisEvent, commit: true)
            } catch {
                throw failure("удаление события", error)
            }
            Log.write("ассистент: событие удалено")
        }
    }

    /// nil — события больше нет.
    static func snapshotEvent(id: String) throws -> EventSnapshot? {
        try requireAccess(.event)
        return try bounded(.event) { _ in
            guard let event = store.event(withIdentifier: id), event.refresh() else { return nil }
            return EventSnapshot(title: event.title ?? "", start: event.startDate, end: event.endDate, isAllDay: event.isAllDay)
        }
    }

    /// `refresh()` подтягивает правки из самого Календаря: объект из кэша
    /// магазина мог устареть, и снимок сравнивался бы со старыми полями.
    private static func existingEvent(_ id: String) throws -> EKEvent {
        guard let event = store.event(withIdentifier: id), event.refresh() else {
            throw AssistantToolError(message: T("Событие не найдено — возможно, его уже удалили",
                                                "Event not found — it may have been deleted already"))
        }
        return event
    }

    /// Дата без времени — событие на весь день. Конец ставим на последнюю
    /// секунду последнего дня, как EventKit хранит его сам: иначе «с
    /// понедельника по среду» теряло бы среду. Без конца событие на весь день
    /// длится `days` дней.
    private static func setTimes(of event: EKEvent, start: AssistantDate, end: AssistantDate?,
                                 duration: TimeInterval, days: Int = 1) {
        if !start.hasTime {
            let calendar = gregorian()
            let first = calendar.startOfDay(for: start.date)
            let last = end.map { calendar.startOfDay(for: max($0.date, first)) }
                ?? calendar.date(byAdding: .day, value: days - 1, to: first) ?? first
            event.isAllDay = true
            event.startDate = first
            event.endDate = (calendar.date(byAdding: .day, value: 1, to: last) ?? last).addingTimeInterval(-1)
        } else {
            event.isAllDay = false
            event.startDate = start.date
            if let end, end.hasTime, end.date > start.date {
                event.endDate = end.date
            } else {
                event.endDate = start.date.addingTimeInterval(duration)
            }
        }
    }

    // MARK: Напоминания

    /// Напоминание в список `voiceRemindersList` (по имени, без учёта регистра,
    /// как в `AppleRemindersService`), иначе — в список по умолчанию.
    /// Возвращает `calendarItemIdentifier`.
    static func addReminder(title: String, due: AssistantDate?, listName: String? = nil,
                            timeZone: TimeZone = .current) throws -> String {
        try requireAccess(.reminder)
        let title = singleLine(title)
        guard !title.isEmpty else { throw AssistantToolError(message: T("Пустое напоминание", "The reminder has no title")) }
        let wanted = (listName ?? AppSettings.shared.voiceRemindersList).trimmingCharacters(in: .whitespaces)
        return try bounded(.reminder) { attempt in
            guard let list = reminderList(named: wanted) else {
                throw AssistantToolError(message: T("Нет списка напоминаний по умолчанию", "No default reminders list"))
            }
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = title
            reminder.notes = marker
            if let due { setDue(due, of: reminder, timeZone: timeZone) }
            do {
                try store.save(reminder, commit: true)
            } catch {
                throw failure("сохранение напоминания", error)
            }
            if attempt.abandoned {
                try? store.remove(reminder, commit: true)
                Log.write("ассистент: напоминание сохранилось уже после тайм-аута — убрано")
                throw AssistantToolError(message: T("Напоминания не ответили за 5 с", "Reminders didn't respond in 5 s"))
            }
            let kind = due.map { $0.hasTime ? "со временем" : "на дату, без будильника" } ?? "без срока"
            Log.write("ассистент: напоминание создано (\(kind))")
            return reminder.calendarItemIdentifier
        }
    }

    static func updateReminder(id: String, title: String?, due: AssistantDate?, timeZone: TimeZone = .current) throws {
        try requireAccess(.reminder)
        let title = title.map(singleLine)
        try bounded(.reminder) { _ in
            let reminder = try existingReminder(id)
            if let title, !title.isEmpty { reminder.title = title }
            if let due { setDue(due, of: reminder, timeZone: timeZone) }
            do {
                try store.save(reminder, commit: true)
            } catch {
                throw failure("правка напоминания", error)
            }
        }
    }

    static func removeReminder(id: String) throws {
        try requireAccess(.reminder)
        try bounded(.reminder) { _ in
            let reminder = try existingReminder(id)
            do {
                try store.remove(reminder, commit: true)
            } catch {
                throw failure("удаление напоминания", error)
            }
            Log.write("ассистент: напоминание удалено")
        }
    }

    /// nil — напоминания больше нет.
    static func snapshotReminder(id: String) throws -> ReminderSnapshot? {
        try requireAccess(.reminder)
        return try bounded(.reminder) { _ in
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.refresh() else { return nil }
            let components = reminder.dueDateComponents
            let due = components.flatMap { gregorian($0.timeZone ?? .current).date(from: $0) }
            return ReminderSnapshot(title: reminder.title ?? "", due: due,
                                    dueHasTime: components?.hour != nil, completed: reminder.isCompleted)
        }
    }

    private static func existingReminder(_ id: String) throws -> EKReminder {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.refresh() else {
            throw AssistantToolError(message: T("Напоминание не найдено — возможно, его уже удалили",
                                                "Reminder not found — it may have been deleted already"))
        }
        return reminder
    }

    private static func reminderList(named name: String) -> EKCalendar? {
        // Без сброса устаревший магазин не нашёл бы список из настроек, и
        // первое напоминание после выдачи доступа ушло бы в список по умолчанию.
        if store.calendars(for: .reminder).isEmpty { store.reset() }
        if !name.isEmpty {
            let match = store.calendars(for: .reminder).first {
                $0.allowsContentModifications && $0.title.compare(name, options: .caseInsensitive) == .orderedSame
            }
            if let match { return match }
            Log.write("ассистент: списка напоминаний из настроек нет — кладу в список по умолчанию")
        }
        if store.defaultCalendarForNewReminders() == nil { store.reset() }
        return store.defaultCalendarForNewReminders()
    }

    /// Дата без времени — только день и без будильника: иначе напоминание «на
    /// пятницу» зазвонило бы в полночь (план 0.1 п. 19). Часовой пояс у такого
    /// срока убираем — у дня без часа его нет, и в поездке он не должен съехать
    /// на соседний день. Со временем — будильник ровно на срок.
    private static func setDue(_ due: AssistantDate, of reminder: EKReminder, timeZone: TimeZone) {
        var components = due.components(in: timeZone)
        for alarm in reminder.alarms ?? [] { reminder.removeAlarm(alarm) }
        if due.hasTime {
            reminder.addAlarm(EKAlarm(absoluteDate: due.date))
        } else {
            components.timeZone = nil
        }
        reminder.dueDateComponents = components
    }
}

// MARK: - AppleScript

/// Все скрипты ассистента идут по одному: `NSAppleScript` не потокобезопасен.
private enum Script {
    struct Failure: Error { let code: Int }

    private static let lock = NSLock()
    private static var compiled: [String: NSAppleScript] = [:]

    /// Постоянный скрипт без параметров (громкость).
    static func run(_ source: String) throws -> NSAppleEventDescriptor {
        lock.lock(); defer { lock.unlock() }
        guard let script = NSAppleScript(source: source) else { throw Failure(code: -2700) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { throw Failure(code: code(error)) }
        return result
    }

    /// Вызов обработчика `handler` постоянного скрипта с параметрами-строками.
    /// Параметры уходят в Apple event как данные и в исходник не попадают.
    static func call(_ source: String, handler: String, _ arguments: [String]) throws -> NSAppleEventDescriptor {
        lock.lock(); defer { lock.unlock() }
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else { throw Failure(code: -2700) }
            var error: NSDictionary?
            guard fresh.compileAndReturnError(&error) else { throw Failure(code: error.map(code) ?? -2700) }
            compiled[source] = fresh
            script = fresh
        }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite),
                                           eventID: AEEventID(kASSubroutineEvent),
                                           targetDescriptor: .currentProcess(),
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        // Имя обработчика в событии — строчными: так его хранит компилятор.
        event.setDescriptor(NSAppleEventDescriptor(string: handler.lowercased()), forKeyword: AEKeyword(keyASSubroutineName))
        let list = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            list.insert(NSAppleEventDescriptor(string: argument), at: index + 1)
        }
        event.setParam(list, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if let error { throw Failure(code: code(error)) }
        return result
    }

    private static func code(_ error: NSDictionary) -> Int {
        (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
    }
}

// MARK: - Заметки

/// Заметки через AppleScript: другого API у Заметок нет.
///
/// Это единственный AppleScript ассистента, куда попадает текст модели, а текст
/// модели недоверенный: выделение с чужой страницы могло уговорить Gemini
/// вписать в заголовок `" & do shell script "…`. Поэтому текст в исходник
/// скрипта не подставляется вовсе: скрипты постоянные, а папка, тело и id
/// уходят параметрами обработчика в Apple event. Нет экранирования — нет и
/// ошибки в нём. Для самих Заметок тело экранируется как HTML, а управляющие
/// символы и переключатели направления письма выбрасываются: первым в заметке
/// они не нужны, вторыми можно перевернуть видимый текст.
enum AssistantNotes {
    static let bundleID = "com.apple.Notes"

    /// Сверка перед отменой. nil — заметки больше нет.
    ///
    /// Не проверено вживую: не трогают ли сами Заметки дату изменения в первые
    /// секунды после создания. Если трогают, движку стоит сверять с допуском.
    static func modificationDate(id: String) throws -> Date? {
        try requireAutomation()
        let result = try call(modifiedSource, handler: "intactNoteModified", [id])
        // `missing value` приходит не как typeNull, а типом 'type' со значением 'msng'.
        guard result.descriptorType == DescType(typeLongDateTime) else { return nil }
        return result.dateValue
    }

    /// Создаёт заметку: `h1` — заголовок, тело без его повтора (план 0.1 п. 18).
    /// Возвращает id и папку, куда заметка попала на самом деле: если папки из
    /// настроек нет, она уходит в папку по умолчанию, и карточка это говорит.
    static func create(title: String, body: String?, folder: String? = nil) throws -> (id: String, folder: String) {
        var title = singleLine(title)
        // По символам, а не `components(separatedBy: .newlines)`: та режет «\r\n»
        // надвое, и каждая строка тела получала бы пустую строку следом.
        var bodyLines = (body ?? "").split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if title.isEmpty, let first = bodyLines.firstIndex(where: { !singleLine($0).isEmpty }) {
            title = singleLine(bodyLines[first])
            bodyLines.removeSubrange(...first)
        }
        guard !title.isEmpty else { throw AssistantToolError(message: T("Пустая заметка", "The note is empty")) }
        try requireAutomation()
        let wanted = (folder ?? AppSettings.shared.voiceNotesFolder).trimmingCharacters(in: .whitespaces)
        let result = try call(createSource, handler: "intactMakeNote", [wanted, html(title: title, body: bodyLines)])
        guard let id = result.atIndex(1)?.stringValue, !id.isEmpty else {
            throw AssistantToolError(message: T("Заметки не вернули id заметки", "Notes returned no note id"))
        }
        let actual = result.atIndex(2)?.stringValue ?? ""
        let fellBack = !wanted.isEmpty && actual.compare(wanted, options: .caseInsensitive) != .orderedSame
        Log.write("ассистент: заметка создана\(fellBack ? " в папке по умолчанию — папки из настроек нет" : "")")
        return (id, actual)
    }

    /// Убирает свою заметку в «Недавно удалённые».
    ///
    /// Заметку, которая уже лежит в «Недавно удалённых», `delete` стёр бы
    /// насовсем, поэтому такую не трогаем. Узнаём её по имени папки, а имя
    /// зависит от языка системы, поэтому `expectedFolder` (папка из `create`)
    /// обязателен: заметку не из своей папки — переложенную или удалённую
    /// человеком при любом языке — не трогаем тоже.
    static func delete(id: String, expectedFolder: String) throws {
        guard !expectedFolder.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AssistantToolError(message: T("Неизвестно, где лежит заметка — не трогаю", "Unknown note folder — leaving it alone"))
        }
        try requireAutomation()
        let verdict = try call(deleteSource, handler: "intactDeleteNote", [id, expectedFolder]).stringValue ?? ""
        switch verdict {
        case "ok":
            Log.write("ассистент: заметка перенесена в «Недавно удалённые»")
        case "missing":
            throw AssistantToolError(message: T("Заметка не найдена — возможно, её уже удалили",
                                                "Note not found — it may have been deleted already"))
        case "trashed":
            throw AssistantToolError(message: T("Заметка уже в «Недавно удалённых»", "The note is already in Recently Deleted"))
        default:
            throw AssistantToolError(message: T("Заметку уже переложили в другую папку — не трогаю",
                                                "The note was moved to another folder — leaving it alone"))
        }
    }

    /// Явный запрос разрешения «Автоматизация → Заметки», только по кнопке.
    /// Блокирует до ответа человека, поэтому работает вне main; `completion` — на main.
    static func requestAccess(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = (try? launchHiddenIfNeeded()) != nil && automationStatus(ask: true) == OSStatus(noErr)
            DispatchQueue.main.async { completion(granted) }
        }
    }

    // MARK: Разрешение

    /// Тихая проверка вместо диалога посреди действия. Она отвечает только
    /// про запущенные Заметки, поэтому их сначала поднимаем скрыто — создать
    /// заметку, не запуская Заметки, всё равно нельзя.
    private static func requireAutomation() throws {
        try launchHiddenIfNeeded()
        switch Int(automationStatus(ask: false)) {
        case Int(noErr):
            return
        case errAEEventWouldRequireUserConsent:
            throw AssistantToolError(message: T("Разрешите Intact управлять Заметками — нажмите «Разрешить»",
                                                "Allow Intact to control Notes — press Allow"),
                                     permission: .automationNotes)
        case errAEEventNotPermitted:
            throw AssistantToolError(message: T("Intact не разрешено управлять Заметками — включите в Настройках → Конфиденциальность → Автоматизация",
                                                "Intact isn't allowed to control Notes — turn it on in Settings → Privacy → Automation"),
                                     permission: .automationNotes)
        case procNotFound:
            throw AssistantToolError(message: T("Заметки не запустились", "Notes didn't start"))
        default:
            return   // незнакомый ответ — пусть скрипт скажет сам
        }
    }

    private static func automationStatus(ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        return withExtendedLifetime(target) {
            guard let desc = target.aeDesc else { return OSStatus(procNotFound) }
            return AEDeterminePermissionToAutomateTarget(desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        }
    }

    private static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Скрыто и без активации: окно Заметок не должно выйти поверх работы.
    private static func launchHiddenIfNeeded() throws {
        guard !isRunning else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw AssistantToolError(message: T("Заметки не найдены на этом Mac", "Notes isn't installed on this Mac"))
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        let launched = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in launched.signal() }
        guard launched.wait(timeout: .now() + 5) == .success, isRunning else {
            throw AssistantToolError(message: T("Заметки не запустились за 5 с", "Notes didn't start in 5 s"))
        }
    }

    // MARK: Скрипты

    private static func call(_ source: String, handler: String, _ arguments: [String]) throws -> NSAppleEventDescriptor {
        do {
            return try Script.call(source, handler: handler, arguments)
        } catch let failure as Script.Failure {
            Log.write("ассистент: AppleScript Заметок, ошибка \(failure.code)")
            switch failure.code {
            case errAEEventNotPermitted, errAEEventWouldRequireUserConsent:
                throw AssistantToolError(message: T("Нет разрешения управлять Заметками", "No permission to control Notes"),
                                         permission: .automationNotes)
            case errAETimeout:
                throw AssistantToolError(message: T("Заметки не ответили за 10 с", "Notes didn't respond in 10 s"))
            case procNotFound, connectionInvalid:
                throw AssistantToolError(message: T("Заметки закрылись посреди действия", "Notes quit in the middle of the action"))
            default:
                throw AssistantToolError(message: T("Заметки вернули ошибку \(failure.code)", "Notes returned error \(failure.code)"))
            }
        }
    }

    // Папка ищется по имени, как в AppleNotesService; не нашлась — папка по
    // умолчанию, и её имя возвращается, чтобы карточка сказала правду.
    private static let createSource = """
    on intactMakeNote(wantedFolder, htmlBody)
        with timeout of 10 seconds
            tell application "Notes"
                set acc to default account
                set targetFolder to missing value
                if wantedFolder is not "" then
                    set found to (folders of acc whose name is wantedFolder)
                    if (count of found) > 0 then set targetFolder to item 1 of found
                end if
                if targetFolder is missing value then set targetFolder to default folder of acc
                set n to make new note at targetFolder with properties {body:htmlBody}
                return {id of n, name of targetFolder}
            end tell
        end timeout
    end intactMakeNote
    """

    private static let modifiedSource = """
    on intactNoteModified(noteID)
        with timeout of 10 seconds
            tell application "Notes"
                if not (exists note id noteID) then return missing value
                return modification date of note id noteID
            end tell
        end timeout
    end intactNoteModified
    """

    // Имена «Недавно удалённых» — на языках интерфейса Intact.
    private static let deleteSource = """
    on intactDeleteNote(noteID, expectedFolder)
        with timeout of 10 seconds
            tell application "Notes"
                if not (exists note id noteID) then return "missing"
                set n to note id noteID
                set place to name of container of n
                if place is in {"Recently Deleted", "Недавно удаленные", "Недавно удалённые"} then return "trashed"
                if expectedFolder is not "" and place is not expectedFolder then return "moved"
                delete n
                return "ok"
            end tell
        end timeout
    end intactDeleteNote
    """

    // MARK: HTML

    private static func html(title: String, body lines: [String]) -> String {
        var lines = lines
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        // Модель часто повторяет заголовок первой строкой тела — в заметке он уже есть.
        if let first = lines.first, comparable(first) == comparable(title) { lines.removeFirst() }
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isRu ? "ru_RU" : "en_US")
        formatter.dateFormat = L10n.isRu ? "d MMMM в HH:mm" : "MMMM d 'at' HH:mm"
        let now = formatter.string(from: Date())
        let stamp = T("Создано \(now) через Intact", "Created \(now) with Intact")

        var html = "<div><h1>\(escape(title))</h1></div>"
        html += "<div><span style=\"color:#888888;font-size:12px;\">\(escape(stamp))</span></div>"
        if !lines.isEmpty {
            html += "<div><br></div>"
            html += lines.map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? "<div><br></div>" : "<div>\(escape($0))</div>" }.joined()
        }
        return html
    }

    private static func comparable(_ line: String) -> String {
        line.trimmingCharacters(in: CharacterSet(charactersIn: "#*_ \t.:").union(.whitespaces)).lowercased()
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\t": out += " "
            // Переключатели направления письма: с ними «gpj.exe» читается как «exe.jpg».
            case "\u{202A}"..."\u{202E}", "\u{2066}"..."\u{2069}":
                continue
            default:
                if scalar.properties.generalCategory == .control { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

// MARK: - Таймеры

/// Таймеры внутри Intact (план E.1, TimerCenter).
///
/// Звонит сам Intact — звуком приложения, а не уведомлением, поэтому таймер
/// слышен и при Фокусе, и при «Не беспокоить» и не зависит от разрешений TCC.
/// Цена — таймер живёт, пока запущен Intact, и карточка честно это говорит.
/// Поэтому больше часа здесь не принимается: движок превращает такие таймеры в
/// напоминание с будильником, которое переживёт перезапуск.
final class AssistantTimers {
    static let shared = AssistantTimers()
    static let maxSeconds = 3600

    struct Item: Equatable {
        let id: String
        let label: String?
        let seconds: Int
        let fireDate: Date

        var remaining: TimeInterval { max(0, fireDate.timeIntervalSinceNow) }
    }

    private let lock = NSLock()
    private var items: [String: Item] = [:]
    private var sources: [String: DispatchSourceTimer] = [:]
    private var ringing: Set<String> = []

    /// Идущие таймеры, ближайший первым.
    var active: [Item] {
        lock.lock(); defer { lock.unlock() }
        return items.values.sorted { $0.fireDate < $1.fireDate }
    }

    /// `onFire` — на main, после первого звонка.
    func start(seconds: Int, label: String?, onFire: @escaping (Item) -> Void) throws -> String {
        guard seconds >= 1 else { throw AssistantToolError(message: T("Слишком короткий таймер", "The timer is too short")) }
        guard seconds <= Self.maxSeconds else {
            throw AssistantToolError(message: T("Таймер больше часа ставится напоминанием", "Timers over an hour become reminders"))
        }
        let label = label.map(singleLine).flatMap { $0.isEmpty ? nil : $0 }
        let item = Item(id: UUID().uuidString, label: label, seconds: seconds, fireDate: Date().addingTimeInterval(TimeInterval(seconds)))
        let source = DispatchSource.makeTimerSource(queue: .main)
        // Настенное время, а не время работы: после сна Mac таймер сработает
        // сразу при пробуждении, а не на время сна позже.
        source.schedule(wallDeadline: .now() + .seconds(seconds))
        source.setEventHandler { [weak self] in self?.fire(item, onFire) }
        lock.lock()
        items[item.id] = item
        sources[item.id] = source
        lock.unlock()
        source.resume()
        Log.write("ассистент: таймер на \(seconds) с запущен, всего \(active.count)")
        return item.id
    }

    /// Снимает идущий таймер или глушит звонящий. false — такого нет.
    @discardableResult
    func cancel(id: String) -> Bool {
        lock.lock()
        let source = sources.removeValue(forKey: id)
        let wasPending = items.removeValue(forKey: id) != nil
        let wasRinging = ringing.remove(id) != nil
        lock.unlock()
        source?.cancel()
        return wasPending || wasRinging
    }

    /// Глушит все звонящие таймеры (⎋, закрытие карточки).
    func silence() {
        lock.lock()
        ringing.removeAll()
        lock.unlock()
    }

    private func fire(_ item: Item, _ onFire: @escaping (Item) -> Void) {
        lock.lock()
        let source = sources.removeValue(forKey: item.id)
        let wasPending = items.removeValue(forKey: item.id) != nil
        if wasPending { ringing.insert(item.id) }
        lock.unlock()
        source?.cancel()
        guard wasPending else { return }
        Log.write("ассистент: таймер сработал")
        ring(item.id, times: 5)
        onFire(item)
    }

    /// Один «дзынь» легко пропустить, поэтому звоним несколько раз, пока не заглушат.
    private func ring(_ id: String, times: Int) {
        lock.lock()
        let stillRinging = ringing.contains(id)
        if times <= 0 { ringing.remove(id) }
        lock.unlock()
        guard stillRinging, times > 0 else { return }
        NSSound(named: "Glass")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.ring(id, times: times - 1) }
    }
}

// MARK: - Программы

/// Находит установленную программу по произнесённому имени: «Телеграм», «хром»,
/// «почту», «системные настройки», «VS Code», «клод».
///
/// Никогда не отдаёт мост Gemini и сам Intact (F.1): «открой Gemini» не должно
/// вывести вперёд окно, через которое идут промпты.
enum AppIndex {
    enum Resolution: Equatable {
        case found(url: URL, name: String)
        /// Несколько одинаково подходящих программ — движок спросит, какую.
        case ambiguous([String])
        case notFound
    }

    /// Разрешает имя в программу. Индекс кэшируется на 60 с.
    static func resolve(_ spoken: String) -> Resolution {
        let entries = index().filter { !isExcluded($0.url, bundleID: $0.bundleID) }
        let full = words(spoken)
        let trimmed = full.filter { !fillers.contains($0) }
        let queries = unique([full, trimmed].filter { !$0.isEmpty }.map { $0.joined() })
        guard !queries.isEmpty else { return .notFound }

        // 1. Точное имя: сначала имя файла и имя в Finder, затем имена из Info.plist.
        for strong in [true, false] {
            let hits = entries.filter { entry in queries.contains { (strong ? entry.primary : entry.secondary).contains($0) } }
            if let result = verdict(hits) { return result }
        }

        // 2. Встроенные прозвища популярных программ.
        let aliasHits = aliases.filter { alias in queries.contains { alias.keys.contains($0) } }
        if !aliasHits.isEmpty {
            let hits = installed(aliasHits, in: entries)
            // Прозвище узнали, а программы нет: «VS Code» не должен открыть Xcode
            // через приблизительное совпадение.
            return verdict(hits) ?? .notFound
        }

        // 3. Падежи: «почту» → «почта», «телеграме» → «телеграм».
        let queryForms = forms(of: full).union(forms(of: trimmed))
        let formHits = entries.filter { !$0.forms.isDisjoint(with: queryForms) }
            + installed(aliases.filter { !$0.forms.isDisjoint(with: queryForms) }, in: entries)
        if let result = verdict(formHits) { return result }

        // 4. Латиницей: «сафари» → «safari», «джемини» → «jemini».
        let latin = Set(queryForms.map(transliterate))
        let latinHits = entries.filter { !$0.forms.isDisjoint(with: latin) }
            + installed(aliases.filter { !$0.forms.isDisjoint(with: latin) }, in: entries)
        if let result = verdict(latinHits) { return result }

        // 5. Опечатки распознавания: не дальше 2 правок и единственный лучший.
        let probes = queryForms.union(latin)
        if let result = nearest(probes, among: entries.map { ($0, $0.forms) } + aliasCandidates(in: entries)) {
            return result
        }

        // 6. Одно слово из длинного имени: «фотошоп» → «Adobe Photoshop 2026».
        if (trimmed.isEmpty ? full : trimmed).count == 1 {
            let wordHits = entries.filter { !$0.words.isDisjoint(with: probes) }
            if let result = verdict(wordHits) { return result }
            if let result = nearest(probes, among: entries.map { ($0, $0.words) }) { return result }
        }
        return .notFound
    }

    /// Запускает программу и выводит её вперёд; ждёт не дольше 5 с.
    /// true — программа запущена; вперёд она выводится по возможности
    /// (кооперативная активация macOS 14+ может отказать фоновому Intact).
    static func open(url: URL) -> Bool {
        let bundleID = Bundle(url: url)?.bundleIdentifier
        guard !isExcluded(url, bundleID: bundleID) else {
            Log.write("ассистент: отказ открыть мост Gemini или сам Intact")
            return false
        }
        let deadline = Date().addingTimeInterval(5)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let done = DispatchSemaphore(value: 0)
        var launched: NSRunningApplication?
        var failure: Error?
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            launched = app
            failure = error
            done.signal()
        }
        let answered = done.wait(timeout: .now() + 5) == .success
        if answered, let failure {
            Log.write("ассистент: программа не открылась, код \((failure as NSError).code)")
            return false
        }
        let app = (answered ? launched : nil)
            ?? bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        guard let app else {
            Log.write("ассистент: программа не запустилась за 5 с")
            return false
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            DispatchQueue.main.async { app.activate() }
            while Date() < deadline, NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
                usleep(20_000)
            }
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            Log.write("ассистент: программа запущена, но вперёд не вышла")
        }
        return true
    }

    /// Сбросить кэш, например после установки программы.
    static func invalidate() {
        lock.lock(); cache = nil; lock.unlock()
    }

    // MARK: Индекс

    private struct Entry {
        let url: URL
        let bundleID: String?
        /// Для карточки: по-русски, если интерфейс русский и перевод есть.
        let name: String
        /// Имя файла и имя в Finder — точнее, чем имена из Info.plist.
        let primary: Set<String>
        let secondary: Set<String>
        /// Все ключи с падежными формами.
        let forms: Set<String>
        /// Значимые слова длинных имён.
        let words: Set<String>
    }

    private struct Alias {
        let keys: Set<String>
        let forms: Set<String>
        let bundleIDs: [String]
    }

    private static let lock = NSLock()
    private static var cache: (built: Date, entries: [Entry])?

    private static func index() -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        if let cache, Date().timeIntervalSince(cache.built) < 60 { return cache.entries }
        let entries = scan()
        cache = (Date(), entries)
        return entries
    }

    private static func scan() -> [Entry] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications",
                     "/System/Applications/Utilities", home + "/Applications"]
        // Не `.skipsHiddenFiles`: ссылка /Applications/Safari.app на криптекс
        // помечена флагом hidden, и Safari пропал бы из индекса.
        func contents(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { !$0.lastPathComponent.hasPrefix(".") }
        }
        var bundles: [URL] = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
        for root in roots {
            for item in contents(URL(fileURLWithPath: root)) {
                if item.pathExtension == "app" {
                    bundles.append(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // Один уровень вложенности: «Adobe Photoshop 2026/…», «Chrome Apps».
                    bundles += contents(item).filter { $0.pathExtension == "app" }
                }
            }
        }
        // Дубли — по настоящему пути (Utilities лежит и корнем, и внутри
        // /Applications), а открываем по тому адресу, что видит человек.
        var seen = Set<String>()
        return bundles.compactMap { url in
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard seen.insert(path).inserted, fm.fileExists(atPath: path) else { return nil }
            return entry(for: url.standardizedFileURL)
        }
    }

    private static func entry(for url: URL) -> Entry {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let fileName = url.deletingPathExtension().lastPathComponent
        let finderName = FileManager.default.displayName(atPath: url.path)
        let localized = localizedNames(of: url)
        var plistNames = [info["CFBundleName"], info["CFBundleDisplayName"]].compactMap { $0 as? String }
        plistNames += localized

        let primary = Set([fileName, finderName].map { words($0).joined() }.filter { !$0.isEmpty })
        let secondary = Set(plistNames.map { words($0).joined() }.filter { !$0.isEmpty })
        let all = [fileName, finderName] + plistNames
        let allForms = Set(all.flatMap { forms(of: words($0)) })
        let significant = Set(all.flatMap { name -> [String] in
            let parts = words(name)
            guard parts.count > 1 else { return [] }
            return parts.filter { $0.count >= 4 && !genericWords.contains($0) && !$0.allSatisfy(\.isNumber) }
        })
        // Имя для карточки — на языке интерфейса: у Intact нет ru.lproj, и
        // Finder отдаёт ему английские имена («Calendar»). Уже русское имя
        // файла не заменяем: в Info.plist «Яндекс Музыки» «М» латинская.
        let finder = finderName.hasSuffix(".app") ? String(finderName.dropLast(4)) : finderName
        let isCyrillic = finder.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
        let name = visible((L10n.isRu && !isCyrillic ? localized.first : nil) ?? finder)
        return Entry(url: url, bundleID: bundle?.bundleIdentifier, name: name, primary: primary,
                     secondary: secondary, forms: allForms, words: significant)
    }

    /// Русские и английские имена из самой программы. Системные программы
    /// хранят переводы в `InfoPlist.loctable`, остальные — в `ru.lproj`.
    /// Русские нужны всегда: говорят по-русски и при английской системе.
    private static func localizedNames(of url: URL) -> [String] {
        let resources = url.appendingPathComponent("Contents/Resources")
        let languages = unique(["ru"] + Locale.preferredLanguages.map { String($0.prefix(2)) } + ["en"])
        let keys = ["CFBundleDisplayName", "CFBundleName"]
        var names: [String] = []
        let table = NSDictionary(contentsOf: resources.appendingPathComponent("InfoPlist.loctable")) as? [String: Any]
        for language in languages {
            if let strings = table?[language] as? [String: Any] {
                names += keys.compactMap { strings[$0] as? String }
            }
            for folder in [language, language == "ru" ? "Russian" : "English"] {
                let file = resources.appendingPathComponent("\(folder).lproj/InfoPlist.strings")
                if let strings = NSDictionary(contentsOf: file) as? [String: Any] {
                    names += keys.compactMap { strings[$0] as? String }
                }
            }
        }
        return unique(names.map { $0.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    /// У отладочного запуска из `.build` нет идентификатора бандла, поэтому
    /// установленный Intact исключаем и по его постоянному id.
    private static func isExcluded(_ url: URL, bundleID: String?) -> Bool {
        if url.standardizedFileURL.path == Bundle.main.bundleURL.standardizedFileURL.path { return true }
        guard let bundleID else { return false }
        if bundleID == Bundle.main.bundleIdentifier || bundleID == "com.artsu.intact" { return true }
        let bridge = GeminiBridgeService.bundleIdentifier
        return bridge != GeminiBridgeService.mainBundleIdentifier && bundleID == bridge
    }

    // MARK: Сопоставление

    private static func verdict(_ hits: [Entry]) -> Resolution? {
        var seen = Set<String>()
        let distinct = hits.filter { seen.insert($0.url.path).inserted }
        switch distinct.count {
        case 0: return nil
        case 1: return .found(url: distinct[0].url, name: distinct[0].name)
        default: return .ambiguous(unique(distinct.map(\.name)).prefix(5).map { $0 })
        }
    }

    private static func installed(_ matched: [Alias], in entries: [Entry]) -> [Entry] {
        matched.compactMap { alias in
            // Первый установленный из списка: у Telegram и ChatGPT по нескольку сборок.
            alias.bundleIDs.lazy.compactMap { id in entries.first { $0.bundleID == id } }.first
        }
    }

    private static func aliasCandidates(in entries: [Entry]) -> [(Entry, Set<String>)] {
        aliases.compactMap { alias in installed([alias], in: entries).first.map { ($0, alias.forms) } }
    }

    /// Ближайшее по правкам. Порог растёт с длиной: в коротком имени две
    /// правки — это уже другое слово.
    private static func nearest(_ probes: Set<String>, among candidates: [(Entry, Set<String>)]) -> Resolution? {
        var best: [String: (entry: Entry, distance: Int)] = [:]
        for (entry, keys) in candidates {
            for probe in probes {
                let limit = probe.count >= 8 ? 2 : (probe.count >= 4 ? 1 : 0)
                guard limit > 0 else { continue }
                for key in keys where key.count >= 3 && abs(key.count - probe.count) <= limit {
                    let distance = levenshtein(probe, key)
                    if distance <= limit, distance < (best[entry.url.path]?.distance ?? .max) {
                        best[entry.url.path] = (entry, distance)
                    }
                }
            }
        }
        guard let minimum = best.values.map(\.distance).min() else { return nil }
        return verdict(best.values.filter { $0.distance == minimum }.map(\.entry).sorted { $0.name < $1.name })
    }

    // MARK: Нормализация

    /// Без невидимых символов: у WhatsApp имя начинается с U+200E.
    private static func visible(_ name: String) -> String {
        String(String.UnicodeScalarView(name.unicodeScalars.filter { $0.properties.generalCategory != .format }))
            .trimmingCharacters(in: .whitespaces)
    }

    /// «Системные настройки.app» → ["системные", "настройки"]: регистр, «ё»,
    /// знаки и невидимые символы (у WhatsApp в имени стоит U+200E) не важны.
    private static func words(_ text: String) -> [String] {
        var text = text.precomposedStringWithCanonicalMapping.lowercased().replacingOccurrences(of: "ё", with: "е")
        if text.hasSuffix(".app") { text.removeLast(4) }
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? $0 : " "
        }))
        return cleaned.split(separator: " ").map(String.init)
    }

    /// Слово и оно же без каждого подходящего падежного окончания. Не один
    /// «правильный» корень, а набор: «телеграм» сам оканчивается на «-ам», и
    /// жёсткий стеммер разошёлся бы с «телеграме». Совпадение любой формы —
    /// совпадение.
    private static func wordForms(_ word: String) -> Set<String> {
        var result: Set<String> = [word]
        guard word.count >= 4, word.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) else { return result }
        for ending in endings where word.hasSuffix(ending) && word.count - ending.count >= 3 {
            result.insert(String(word.dropLast(ending.count)))
        }
        return result
    }

    private static func forms(of words: [String]) -> Set<String> {
        guard !words.isEmpty else { return [] }
        guard words.count <= 3 else { return [words.joined()] }
        return words.reduce([""]) { partial, word in
            Set(partial.flatMap { prefix in wordForms(word).map { prefix + $0 } })
        }
    }

    private static let endings = [
        "ами", "ями", "ого", "его", "ому", "ему", "ыми", "ими",
        "ах", "ях", "ов", "ев", "ей", "ой", "ый", "ий", "ые", "ие", "ая", "яя", "ое", "ее",
        "ую", "юю", "ом", "ем", "ам", "ям", "ых", "их",
        "а", "я", "у", "ю", "е", "ы", "и", "о", "ь", "й"
    ]

    /// Слова, которые говорят вокруг имени: «открой приложение телеграм».
    private static let fillers: Set<String> = [
        "приложение", "приложения", "приложении", "программа", "программу", "программы", "программе", "прогу",
        "открой", "открыть", "запусти", "запустить", "пожалуйста", "мне",
        "app", "application", "the", "open", "launch", "please"
    ]

    /// Слова длинных имён, по которым программу не угадать.
    private static let genericWords: Set<String> = [
        "apple", "google", "microsoft", "adobe", "yandex", "яндекс", "desktop", "studio", "creator",
        "lite", "work", "apps", "app", "for", "the", "and", "with", "macos", "utility", "assistant"
    ]

    /// Латиница, как её слышат в названиях программ: «дж» → j («джемини» →
    /// «jemini»), «х» → h («хэнгар» → «hengar»).
    private static func transliterate(_ text: String) -> String {
        let table: [Character: String] = [
            "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ж": "zh", "з": "z", "и": "i",
            "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s",
            "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "",
            "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"
        ]
        return text.replacingOccurrences(of: "дж", with: "j").map { table[$0] ?? String($0) }.joined()
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    /// Популярные программы, которые называют не так, как они подписаны.
    /// Сначала ищем по идентификатору: имя файла у сборок бывает любым.
    private static let aliasTable: [(spoken: [String], ids: [String])] = [
        (["хром", "гугл хром", "chrome", "google chrome"], ["com.google.Chrome"]),
        (["сафари", "safari"], ["com.apple.Safari"]),
        (["телеграм", "телеграмм", "телега", "тг", "telegram"], ["ru.keepcoder.Telegram", "org.telegram.desktop", "com.tdesktop.Telegram"]),
        (["ватсап", "вотсап", "вацап", "ватсапп", "вотсапп", "whatsapp"], ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]),
        (["слак", "слэк", "slack"], ["com.tinyspeck.slackmacgap"]),
        (["зум", "zoom"], ["us.zoom.xos"]),
        (["ноушн", "ноушен", "ношн", "notion"], ["notion.id"]),
        (["спотифай", "spotify"], ["com.spotify.client"]),
        (["музыка", "эпл мьюзик", "эппл мьюзик", "apple music", "music", "айтюнс", "itunes"], ["com.apple.Music"]),
        (["почта", "мейл", "мэйл", "эпл мейл", "mail", "apple mail"], ["com.apple.mail"]),
        (["календарь", "calendar", "ical"], ["com.apple.iCal"]),
        (["заметки", "notes"], ["com.apple.Notes"]),
        (["напоминания", "reminders"], ["com.apple.reminders"]),
        (["системные настройки", "настройки", "настройки системы", "параметры системы",
          "system settings", "system preferences", "settings"], ["com.apple.systempreferences"]),
        (["терминал", "terminal"], ["com.apple.Terminal"]),
        (["файндер", "finder", "проводник"], ["com.apple.finder"]),
        (["превью", "просмотр", "preview"], ["com.apple.Preview"]),
        (["фейстайм", "фейс тайм", "facetime"], ["com.apple.FaceTime"]),
        (["апп стор", "эп стор", "эпп стор", "аппстор", "эпстор", "app store"], ["com.apple.AppStore"]),
        (["vs code", "vscode", "вс код", "вскод", "вэ эс код", "visual studio code", "визуал студио код",
          "вижуал студио код"], ["com.microsoft.VSCode"]),
        (["xcode", "икскод", "экскод", "иксюд"], ["com.apple.dt.Xcode"]),
        (["gemini", "джемини", "джеминай", "гемини", "джеминаи"], ["com.google.GeminiMacOS"]),
        (["claude", "клод", "клауд", "клоуд"], ["com.anthropic.claudefordesktop"]),
        (["chatgpt", "chat gpt", "чат гпт", "чатгпт", "чат джипити", "чат джи пи ти"], ["com.openai.chat", "com.openai.codex"]),
        (["фигма", "figma"], ["com.figma.Desktop"]),
        (["яндекс", "яндекс браузер", "yandex", "yandex browser"], ["ru.yandex.desktop.yandex-browser"]),
        (["арк", "arc", "arc browser"], ["company.thebrowser.Browser"])
    ]

    private static let aliases: [Alias] = aliasTable.map { row in
        let split = row.spoken.map { words($0) }
        return Alias(keys: Set(split.map { $0.joined() }), forms: Set(split.flatMap { forms(of: $0) }), bundleIDs: row.ids)
    }
}

// MARK: - Громкость

/// Громкость системы через Standard Additions: ни разрешений TCC, ни чужой
/// программы. В скрипт подставляется только число. Прежний уровень здесь не
/// хранится — его держит движок для отмены.
enum SystemVolume {
    /// 0…100; при выключенном звуке — 0. nil — у устройства вывода нет
    /// регулятора (часть HDMI- и USB-выходов): AppleScript отдаёт missing value.
    static func get() -> Int? {
        let source = """
        set s to get volume settings
        if output muted of s is true then return 0
        return output volume of s
        """
        // `missing value` — не typeNull, а 'type'/'msng': `int32Value` дал бы 0.
        guard let result = try? Script.run(source), result.descriptorType == DescType(typeSInt32) else { return nil }
        return Int(result.int32Value)
    }

    /// 0 выключает звук, не трогая сам уровень: клавиша звука потом вернёт прежнюю громкость.
    /// У выхода без регулятора `set volume` молча ничего не делает, поэтому
    /// сначала проверяем, что громкость вообще читается: карточка не должна
    /// сказать «Громкость · 50%», когда ничего не поменялось.
    static func set(_ level: Int) throws {
        guard get() != nil else {
            Log.write("ассистент: у выхода звука нет регулятора громкости")
            throw AssistantToolError(message: T("У этого выхода звука нет регулятора громкости",
                                                "This audio output has no volume control"))
        }
        let level = min(100, max(0, level))
        let source = level == 0
            ? "set volume with output muted"
            : "set volume output volume \(level) without output muted"
        do {
            _ = try Script.run(source)
        } catch {
            Log.write("ассистент: громкость не изменилась, код \((error as? Script.Failure)?.code ?? 0)")
            throw AssistantToolError(message: T("Не удалось поменять громкость", "Couldn't change the volume"))
        }
    }
}

// MARK: - Ссылки

/// Какие ссылки открываются без карточки подтверждения (план E.1, F.3).
///
/// Правило отбора сайтов: под доменом нет чужого содержимого, которое
/// выдаётся за сам сайт, и нет открытых редиректов в обход проверки. Поэтому
/// здесь нет t.me и других мессенджеров (диплинк пишет человеку), github.io,
/// sites.google.com, досок объявлений. Всё, что не прошло, — не запрет, а
/// карточка с хостом в punycode.
enum AssistantURLPolicy {
    private static let trustedDomains: [String] = {
        let google = ["com", "ru", "kg", "kz", "by", "uz", "de", "co.uk"].map { "google." + $0 }
        let yandex = ["ru", "com", "kz", "by", "uz"].map { "yandex." + $0 }
        return google + yandex + [
            "youtube.com", "youtu.be", "ya.ru",
            "wikipedia.org", "wiktionary.org",
            "github.com", "apple.com", "stackoverflow.com",
            "habr.com", "vc.ru", "kinopoisk.ru",
            "2gis.ru", "2gis.kg", "openstreetmap.org", "gismeteo.ru",
            "python.org", "swift.org", "mozilla.org", "microsoft.com",
            "duckduckgo.com", "bing.com", "imdb.com",
            "spotify.com", "netflix.com", "anthropic.com", "openai.com"
        ]
    }()

    /// Поддомены доверенных сайтов с пользовательскими страницами, скриптами и
    /// формами: чужая форма под google.com — классическая ловушка для пароля.
    private static let untrustedHosts = ["sites.google.com", "script.google.com", "gist.github.com",
                                         "forms.yandex.ru", "forms.yandex.com"]

    /// Google Формы: и «/forms/…», и «/a/<домен>/forms/…».
    private static func isGoogleForm(host: String, url: URL) -> Bool {
        host == "docs.google.com" && url.path.lowercased().split(separator: "/").contains("forms")
    }

    /// Пути-редиректы и прокси: «google.com/url?q=…», «yandex.ru/clck/…»,
    /// «youtube.com/redirect?…», «bing.com/ck/a?…u=a1<base64>», переводчик страниц.
    private static let redirectPaths = ["/url", "/aclk", "/amp", "/imgres", "/redirect", "/clck", "/redir",
                                        "/turbo", "/away", "/leave", "/out", "/go", "/translate", "/proxy", "/ck"]

    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = host(of: url),
              host.allSatisfy(\.isASCII),
              trustedDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              !untrustedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              !isGoogleForm(host: host, url: url),
              !hidesAnotherURL(url) else { return false }
        return true
    }

    /// Хост для карточки подтверждения — в punycode: «gооgle.com» с
    /// кириллическими «о» выглядит как настоящий, а «xn--ggle-55da.com» — нет.
    static func displayHost(_ url: URL) -> String {
        guard let host = host(of: url) else { return url.absoluteString }
        return host.split(separator: ".", omittingEmptySubsequences: false).map { label -> String in
            let label = String(label)
            return label.allSatisfy(\.isASCII) ? label : "xn--" + punycode(label)
        }.joined(separator: ".")
    }

    private static func host(of url: URL) -> String? {
        guard var host = url.host(percentEncoded: false)?.precomposedStringWithCanonicalMapping.lowercased(),
              !host.isEmpty else { return nil }
        while host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }

    /// Ссылка, в которой спрятан другой адрес, ведёт туда, куда захочет автор
    /// ссылки, а не доверенный сайт. Проверяем путь и хвост, раскрыв
    /// процент-кодирование (в том числе двойное). Страница согласия OAuth —
    /// тоже чужая: доступ к почте на ней выдаётся приложению автора ссылки.
    private static func hidesAnotherURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if redirectPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") || path.hasPrefix($0 + ".") }) {
            return true
        }
        if ((url.host ?? "") + path).lowercased().contains("oauth") { return true }
        var tail = ((url.query ?? "") + "#" + (url.fragment ?? "")).lowercased()
        for _ in 0..<3 {
            guard let decoded = tail.removingPercentEncoding, decoded != tail else { break }
            tail = decoded.lowercased()
        }
        return tail.contains("http:") || tail.contains("https:") || tail.contains("//")
    }

    /// Punycode (RFC 3492) для одной метки. Свежий Foundation сам переводит
    /// IDN-хост в punycode, а на macOS 14 хост может прийти юникодом.
    private static func punycode(_ label: String) -> String {
        let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700
        let input = label.unicodeScalars.map { Int($0.value) }
        var output = input.filter { $0 < 0x80 }.map { Character(UnicodeScalar(UInt8($0))) }
        let basic = output.count
        var handled = basic
        if basic > 0 { output.append("-") }
        var n = 128, delta = 0, bias = 72

        func digit(_ d: Int) -> Character { Character(UnicodeScalar(UInt8(d < 26 ? d + 97 : d + 22))) }
        func adapt(_ delta: Int, _ points: Int, _ first: Bool) -> Int {
            var delta = first ? delta / damp : delta / 2
            delta += delta / points
            var k = 0
            while delta > ((base - tMin) * tMax) / 2 {
                delta /= base - tMin
                k += base
            }
            return k + (base - tMin + 1) * delta / (delta + skew)
        }

        while handled < input.count {
            guard let m = input.filter({ $0 >= n }).min() else { break }
            delta += (m - n) * (handled + 1)
            n = m
            for c in input {
                if c < n { delta += 1 }
                guard c == n else { continue }
                var q = delta
                var k = base
                while true {
                    let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                    if q < t { break }
                    output.append(digit(t + (q - t) % (base - t)))
                    q = (q - t) / (base - t)
                    k += base
                }
                output.append(digit(q))
                bias = adapt(delta, handled + 1, handled == basic)
                delta = 0
                handled += 1
            }
            delta += 1
            n += 1
        }
        return String(output)
    }
}
