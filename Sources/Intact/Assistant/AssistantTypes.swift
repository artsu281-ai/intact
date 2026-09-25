import AppKit
import Foundation

// Общий контракт ассистента (правый ⌘): план, который составляет Gemini, контекст
// нажатия, память разговора, квитанции исполнения и карточки. Протокол и замеры —
// AGENTS_SYNC.md, раздел 4.7.

// MARK: - План

/// Дата из плана: со временем или только день («в пятницу» без часа).
struct AssistantDate: Equatable {
    /// Для даты без времени — начало этого дня в часовом поясе нажатия.
    let date: Date
    let hasTime: Bool

    /// Компоненты для EventKit: у даты без времени нет часов и минут —
    /// напоминание без будильника, событие на весь день.
    func components(in timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let units: Set<Calendar.Component> = hasTime
            ? [.year, .month, .day, .hour, .minute]
            : [.year, .month, .day]
        var components = calendar.dateComponents(units, from: date)
        components.timeZone = timeZone
        return components
    }
}

/// Насколько шаг опасен. От этого зависит, выполняется ли он сразу.
enum AssistantRisk: Int, Comparable {
    /// Только показывает (ответ, черновик, вопрос).
    case show = 0
    /// Меняет что-то локально, только своё и отменяемое (напоминание, заметка, таймер).
    case local = 1
    /// Всегда через карточку подтверждения.
    case confirm = 2

    static func < (a: AssistantRisk, b: AssistantRisk) -> Bool { a.rawValue < b.rawValue }
}

/// Один шаг плана. Инструментов, которые отправляют, пересылают, удаляют чужое
/// или платят, в Intact нет вовсе — ни здесь, ни в исполнителе.
enum AssistantStep: Equatable {
    case textInsert(text: String)
    case textReplace(text: String)
    case reminderAdd(title: String, due: AssistantDate?)
    case calendarAdd(title: String, start: AssistantDate, end: AssistantDate?, place: String?)
    case noteAdd(title: String, body: String?)
    case timerSet(seconds: Int, label: String?)
    case appOpen(name: String)
    case urlOpen(URL)
    case volumeSet(level: Int)
    case messageDraft(to: String, text: String)
    case clarify(question: String)
    /// Поправить недавнее действие Intact по его ссылке (A1, A2…).
    case edit(ref: String, title: String?, due: AssistantDate?, start: AssistantDate?, end: AssistantDate?)
    case undo(ref: String)

    var toolName: String {
        switch self {
        case .textInsert: return "text.insert"
        case .textReplace: return "text.replace"
        case .reminderAdd: return "reminder.add"
        case .calendarAdd: return "calendar.add"
        case .noteAdd: return "note.add"
        case .timerSet: return "timer.set"
        case .appOpen: return "app.open"
        case .urlOpen: return "url.open"
        case .volumeSet: return "volume.set"
        case .messageDraft: return "message.draft"
        case .clarify: return "clarify"
        case .edit: return "edit"
        case .undo: return "undo"
        }
    }

    /// Шаг, который пишет текст в чужое поле. Такой шаг в плане один и последний.
    var isTextDelivery: Bool {
        switch self {
        case .textInsert, .textReplace: return true
        default: return false
        }
    }

    /// Базовый риск шага; политика движка может только повысить его.
    var baseRisk: AssistantRisk {
        switch self {
        case .messageDraft, .clarify: return .show
        case .urlOpen: return .confirm   // движок понижает до .local для доверенных хостов
        default: return .local
        }
    }
}

/// Ремонты, которые парсер сделал, чтобы прочитать ответ. Тяжёлые означают, что
/// смысл мог исказиться: план с действиями тогда идёт через подтверждение.
enum AssistantRepair: String, Hashable {
    // Косметические — чинятся молча.
    case smartQuotes, singleQuotes, unquotedKeys, trailingCommas, comments
    case pythonLiterals, rawNewlines, badEscapes, invisibleChars, endAdjusted, aliasedTool, aliasedArgument
    // Тяжёлые.
    case truncated, innerQuote, fuzzyTool, noOffset, multiplePlans, droppedStep, dateSanity

    var isHeavy: Bool {
        switch self {
        case .truncated, .innerQuote, .fuzzyTool, .noOffset, .multiplePlans, .droppedStep, .dateSanity:
            return true
        default:
            return false
        }
    }
}

struct AssistantPlan: Equatable {
    let id: String
    let steps: [AssistantStep]
    /// Короткий ответ человеку на языке запроса. Может быть пустым.
    let say: String
    let repairs: Set<AssistantRepair>
    /// JSON прочитан из блока ```json, а не выковырян из прозы.
    let fromCodeBlock: Bool

    var hasActions: Bool { steps.contains { $0.baseRisk >= .local } }
    var hasHeavyRepairs: Bool { repairs.contains { $0.isHeavy } }
}

/// Итог разбора ответа Gemini.
enum AssistantVerdict: Equatable {
    case plan(AssistantPlan)
    /// Gemini ответил без нашего JSON — показать как ответ; действий из прозы не выводим.
    case noPlan(prose: String)
    /// JSON наш, но в нём нечего исполнить (неизвестные инструменты, неверные аргументы).
    case invalid(say: String?, reason: String)
    /// JSON есть, но с чужим id — ответ не на этот запрос.
    case stale
}

/// Что парсеру нужно знать о нажатии, чтобы проверить план.
struct AssistantParseContext {
    let id: String
    let now: Date
    let timeZone: TimeZone
    /// Исходная фраза — для локальной сверки дат («через час», «в пятницу»).
    let utterance: String
    /// Выделение было снято целиком — без этого `text.replace` невалиден.
    let hasSelection: Bool
    /// Ссылки недавних действий, на которые можно ссылаться в `edit`/`undo`.
    let knownRefs: Set<String>
}

// MARK: - Контекст нажатия

/// Снимок того, что было у пользователя перед глазами в момент отпускания клавиши.
/// Собирается вне главного потока (AX), в промпт уходит только разрешённое.
struct AssistantContext {
    let now: Date
    let timeZone: TimeZone
    let appName: String?
    let bundleID: String?
    /// Заголовок окна — локально для проверки перед вставкой; в промпт только
    /// по указательным словам («это», «ответь ему»).
    let windowTitle: String?
    /// Под курсором есть поле, куда можно вставить текст.
    let hasTextField: Bool
    /// Выделенный текст, уже прошедший фильтры (пароли, ключи, мост Gemini). nil — нет или отброшен.
    let selection: String?
    let selectionTruncated: Bool
    /// Отпечаток полного выделения на момент снимка: `text.replace` проверяет, что оно не сменилось.
    let selectionFingerprint: Int?
    let isTerminal: Bool
    /// Почему выделение не взяли — только для лога, без содержимого.
    let selectionDropReason: String?
    /// Приложение, в котором была нажата клавиша: текст ассистента идёт только туда.
    /// Заполняет `AssistantContextBox`, а не снимок AX.
    var targetApp: NSRunningApplication? = nil

    static func empty(now: Date = Date()) -> AssistantContext {
        AssistantContext(now: now, timeZone: .current, appName: nil, bundleID: nil, windowTitle: nil,
                         hasTextField: false, selection: nil, selectionTruncated: false,
                         selectionFingerprint: nil, isTerminal: false, selectionDropReason: nil)
    }
}

// MARK: - Память разговора

struct AssistantExchange: Equatable {
    let question: String
    let answer: String
    let at: Date
}

/// Недавнее действие Intact, на которое можно сослаться: «нет, через два часа», «отмени».
struct AssistantRecentAction: Equatable {
    /// A1, A2… — стабильная ссылка для Gemini.
    let ref: String
    /// Одна строка для промпта: «напоминание «Позвонить Ване» на 2026-09-25T11:43+06:00».
    let summary: String
    let at: Date
}

struct AssistantMemory: Equatable {
    var lastExchange: AssistantExchange?
    var recentActions: [AssistantRecentAction] = []
    /// Описание плана, который ждёт подтверждения.
    var pendingConfirmation: String?
    /// Предыдущий запрос, к которому Gemini задал уточняющий вопрос.
    var clarifying: String?
}

// MARK: - Исполнение

enum AssistantPermission: Equatable {
    case calendars, reminders, automationNotes, notifications

    var settingsURL: URL? {
        switch self {
        case .calendars: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .reminders: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        case .automationNotes: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .notifications: return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        }
    }
}

/// Ошибка инструмента — всегда с человеческим текстом для карточки.
struct AssistantToolError: LocalizedError, Equatable {
    let message: String
    /// Не хватает разрешения: карточка покажет [Разрешить] / [Открыть настройки].
    var permission: AssistantPermission? = nil

    var errorDescription: String? { message }
}

/// Квитанция о выполненном шаге: из неё собирается карточка (а не из `say`),
/// и в ней же лежит обратная операция для «отмени».
struct AssistantReceipt {
    let step: AssistantStep
    let ok: Bool
    /// Одна строка для карточки: «Напоминание · Позвонить Ване · сегодня 11:43».
    let line: String
    /// Ссылка A1… для недавних действий; nil, если отменять нечего.
    var ref: String? = nil
    /// Строка для памяти («напоминание «…» на …»); nil — в память не кладём.
    var memorySummary: String? = nil
    /// Обратная операция. Вызывается вне главного потока.
    var undo: (() throws -> Void)? = nil
    /// Идентификатор созданного элемента (EventKit, Заметки, таймер) — для `edit`.
    var itemID: String? = nil
    /// Каким элемент был сразу после создания: отмена и правка трогают только нетронутое.
    var guardBox: ItemGuard? = nil
    var error: AssistantToolError? = nil
}

// MARK: - Карточки

struct AssistantCardLine: Equatable, Identifiable {
    let id = UUID()
    let ok: Bool
    let text: String

    static func == (a: AssistantCardLine, b: AssistantCardLine) -> Bool { a.ok == b.ok && a.text == b.text }
}

/// Кнопки карточек. Любой клик — явное согласие пользователя.
enum AssistantCardButton: Equatable {
    case undo, insert, copy, confirm, reject, retry, dismiss, stopTimer
    case openSettings(AssistantPermission)
    case grant(AssistantPermission)
}

/// Что показывает карточка ассистента. Панель не активирует Intact и не берёт клавиатуру.
enum AssistantCard: Equatable {
    /// Итог выполненных действий: строка на шаг и, если есть что, [Отменить].
    case summary(lines: [AssistantCardLine], canUndo: Bool)
    /// Ответ на вопрос. [Вставить] — только если при нажатии было поле ввода.
    case answer(query: String, text: String, canInsert: Bool)
    /// План ждёт подтверждения: [Выполнить] [Отмена], голосом «да» / «нет».
    case confirm(lines: [String], reason: String?)
    /// Gemini задал уточняющий вопрос — ответ правым ⌘ в течение минуты.
    case clarify(question: String)
    /// Черновик сообщения: только [Скопировать], Intact ничего не отправляет.
    case draft(to: String, text: String)
    case error(message: String, query: String?, permission: AssistantPermission?)
    /// Сработал таймер.
    case timer(label: String)

    var title: String {
        switch self {
        case .summary: return T("Готово", "Done")
        case .answer: return T("Ответ", "Answer")
        case .confirm: return T("Понял так:", "Here's the plan:")
        case .clarify: return T("Уточните", "One question")
        case .draft(let to, _): return T("Черновик для \(to)", "Draft for \(to)")
        case .error: return T("Не получилось", "Couldn't do it")
        case .timer: return T("Таймер", "Timer")
        }
    }
}
