import AppKit
import Carbon.HIToolbox

/// Клавиша-модификатор, удержание которой запускает диктовку.
public enum TriggerKey: String, Codable, CaseIterable, Identifiable {
    case leftOption, rightOption, anyOption, fn, rightCommand, leftCommand, anyCommand, rightControl
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .leftOption:   return T("Левый ⌥ Option", "Left ⌥ Option")
        case .rightOption:  return T("Правый ⌥ Option", "Right ⌥ Option")
        case .anyOption:    return T("Любой ⌥ Option", "Either ⌥ Option")
        case .fn:           return "Fn (Globe)"
        case .rightCommand: return T("Правый ⌘ Command", "Right ⌘ Command")
        case .leftCommand:  return T("Левый ⌘ Command", "Left ⌘ Command")
        case .anyCommand:   return T("Любой ⌘ Command", "Either ⌘ Command")
        case .rightControl: return T("Правый ⌃ Control", "Right ⌃ Control")
        }
    }

    var symbol: String {
        switch self {
        case .leftOption:   return T("⌥ (левый)", "⌥ (left)")
        case .rightOption:  return T("⌥ (правый)", "⌥ (right)")
        case .anyOption:    return "⌥"
        case .fn:           return "Fn"
        case .rightCommand: return T("⌘ (правый)", "⌘ (right)")
        case .leftCommand:  return T("⌘ (левый)", "⌘ (left)")
        case .anyCommand:   return "⌘"
        case .rightControl: return T("⌃ (правый)", "⌃ (right)")
        }
    }

    /// Коды физических клавиш, которые считаются нажатием этого триггера.
    var keyCodes: Set<Int64> {
        switch self {
        case .leftOption:   return [58]
        case .rightOption:  return [61]
        case .anyOption:    return [58, 61]
        case .fn:           return [63]
        case .rightCommand: return [54]
        case .leftCommand:  return [55]
        case .anyCommand:   return [54, 55]
        case .rightControl: return [62]
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .leftOption, .rightOption, .anyOption: return .maskAlternate
        case .fn:                                   return .maskSecondaryFn
        case .rightCommand, .leftCommand, .anyCommand: return .maskCommand
        case .rightControl:                         return .maskControl
        }
    }
}

/// Слежение за удержанием голой клавиши-модификатора.
///
/// Carbon-хоткеи так не умеют — им нужна обычная клавиша. Поэтому здесь
/// пассивный CGEventTap: события не перехватываются, а только читаются,
/// так что ⌥ продолжает работать во всех сочетаниях как обычно.
final class ModifierKeyMonitor {
    static let shared = ModifierKeyMonitor()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Пользователь нажал другую клавишу, пока держал триггер, — это было
    /// обычное сочетание вроде ⌥←, а не диктовка. Запись надо отменить.
    var onAbort: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var trigger: TriggerKey = .leftOption
    private var held = false

    /// Не приватный: второй независимый хоткей (например, для вопроса к ИИ)
    /// создаёт свой собственный экземпляр — не делит состояние с `.shared`.
    init() {}

    var isActive: Bool { tap != nil }

    func start(trigger: TriggerKey) {
        stop()
        self.trigger = trigger
        held = false

        guard Permissions.inputMonitoring else {
            Log.write("клавиша \(trigger.symbol) не подключена: нет «Мониторинга ввода»")
            return
        }

        // Отслеживаем только смену модификаторов и нажатия других клавиш на клавиатуре.
        // Клики мышкой НЕ сбрасывают запись, чтобы можно было кликнуть в поле во время речи.
        let mask = (1 << CGEventType.flagsChanged.rawValue)
                 | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ModifierKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.write("event tap не создался, хотя «Мониторинг ввода» выдан — неожиданный отказ системы")
            return
        }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.write("клавиша \(trigger.symbol) подключена")
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        }
        tap = nil
        source = nil
        held = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // Система умеет отключать tap при перегрузке — включаем обратно.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        if held, type == .keyDown {
            // Триггер зажат, но нажали обычную клавишу на клавиатуре (например ⌥C, ⌥Tab) — это сочетание, а не диктовка.
            held = false
            DispatchQueue.main.async { self.onAbort?() }
            return
        }

        guard type == .flagsChanged else { return }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard trigger.keyCodes.contains(code) else {
            // Нажали другой модификатор поверх триггера — это тоже сочетание.
            if held, isModifierKeyCode(code), event.flags.contains(flagFor(code)) {
                held = false
                DispatchQueue.main.async { self.onAbort?() }
            }
            return
        }

        let pressed = event.flags.contains(trigger.flag)
        if pressed && !held {
            held = true
            DispatchQueue.main.async { self.onPress?() }
        } else if !pressed && held {
            held = false
            DispatchQueue.main.async { self.onRelease?() }
        }
    }

    private func isModifierKeyCode(_ code: Int64) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code)
    }

    private func flagFor(_ code: Int64) -> CGEventFlags {
        switch code {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 63:     return .maskSecondaryFn
        default:     return []
        }
    }
}
