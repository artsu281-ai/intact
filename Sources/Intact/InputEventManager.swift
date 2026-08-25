import AppKit
import Carbon.HIToolbox

/// Единый менеджер глобального ввода: клавиатурные модификаторы и кнопки мыши
public final class InputEventManager {
    public static let shared = InputEventManager()

    public var onPipelineStart: ((VoicePipeline) -> Void)?
    public var onPipelineStop: ((VoicePipeline) -> Void)?
    public var onPipelineAbort: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var activePipeline: VoicePipeline?
    private var isTriggerHeld = false

    private init() {}

    public var isActive: Bool { tap != nil }

    public func restart() {
        stop()
        start()
    }

    public func start() {
        guard tap == nil else { return }

        guard Permissions.inputMonitoring else {
            Log.write("InputEventManager: нет разрешения на «Мониторинг ввода»")
            return
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
                 | (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.otherMouseDown.rawValue)
                 | (1 << CGEventType.otherMouseUp.rawValue)

        guard let tapPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<InputEventManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            Log.write("InputEventManager: не удалось создать CGEventTap")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tapPort, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tapPort, enable: true)

        self.tap = tapPort
        self.source = runLoopSource
        Log.write("InputEventManager: глобальный перехватчик ввода успешно запущен")
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = nil
        }
        activePipeline = nil
        isTriggerHeld = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let pipelines = PipelineManager.shared.pipelines.filter { $0.enabled }

        switch type {
        case .flagsChanged:
            handleModifierEvent(event: event, pipelines: pipelines)

        case .otherMouseDown:
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            handleMouseButtonDown(buttonNumber: Int(buttonNumber), pipelines: pipelines)

        case .otherMouseUp:
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            handleMouseButtonUp(buttonNumber: Int(buttonNumber))

        case .keyDown:
            if isTriggerHeld {
                // Нажата обычная клавиша во время удержания триггера — это системное
                // сочетание, а не диктовка.
                isTriggerHeld = false
                activePipeline = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onPipelineAbort?()
                }
            }

        default:
            break
        }
    }

    private func handleModifierEvent(event: CGEvent, pipelines: [VoicePipeline]) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Отпускание разбираем по активному пайплайну, а не по списку включённых:
        // выключенный прямо во время удержания пайплайн было уже некому остановить,
        // и запись висела до перезапуска приложения.
        if isTriggerHeld, let active = activePipeline,
           case .modifierKey(let key) = active.trigger, key.keyCodes.contains(code) {
            guard !flags.contains(key.flag) else { return }
            isTriggerHeld = false
            activePipeline = nil
            DispatchQueue.main.async { [weak self] in self?.onPipelineStop?(active) }
            return
        }

        guard !isTriggerHeld else {
            // Поверх удерживаемого триггера нажали ещё один модификатор — это сочетание
            // клавиш вроде ⌘⇧S, а не диктовка.
            if Self.isModifierKeyCode(code), flags.contains(Self.flag(for: code)) {
                Self.traceTrigger(code: code, "поверх удерживаемого триггера — считаю это сочетанием клавиш, отменяю запись")
                isTriggerHeld = false
                activePipeline = nil
                DispatchQueue.main.async { [weak self] in self?.onPipelineAbort?() }
            }
            return
        }

        for pipeline in pipelines {
            guard case .modifierKey(let key) = pipeline.trigger,
                  key.keyCodes.contains(code) else { continue }
            // Клавиша пайплайна опознана — дальше расходятся нажатие и отпускание.
            guard flags.contains(key.flag) else { return }
            isTriggerHeld = true
            activePipeline = pipeline
            DispatchQueue.main.async { [weak self] in self?.onPipelineStart?(pipeline) }
            return
        }

        // Клавиша не подошла ни одному включённому пайплайну. Молчать здесь нельзя:
        // именно так «клавиша вообще ничего не делает» выглядела в логе как пустота,
        // и отличить «событие не дошло» от «пайплайн выключен» было невозможно.
        if Self.isModifierKeyCode(code), flags.contains(Self.flag(for: code)) {
            let known = pipelines.compactMap { p -> String? in
                guard case .modifierKey(let k) = p.trigger else { return nil }
                return "\(p.name):\(k.keyCodes.map(String.init).joined(separator: "/"))"
            }.joined(separator: ", ")
            Self.traceTrigger(code: code, "ни один включённый пайплайн не слушает эту клавишу; слушают: [\(known)]")
        }
    }

    /// Диагностика триггеров: пишет в лог не чаще раза в 2 секунды на код клавиши,
    /// чтобы обычная работа с ⌘C/⌘V не залила лог.
    private static var lastTrace: [Int64: Date] = [:]
    private static let traceLock = NSLock()

    private static func traceTrigger(code: Int64, _ reason: String) {
        traceLock.lock()
        let now = Date()
        let recent = lastTrace[code].map { now.timeIntervalSince($0) < 2.0 } ?? false
        if !recent { lastTrace[code] = now }
        traceLock.unlock()
        guard !recent else { return }
        Log.write("Триггер: клавиша \(keyName(code)) (код \(code)) — \(reason)")
    }

    private static func keyName(_ code: Int64) -> String {
        switch code {
        case 54: return "правый ⌘"
        case 55: return "левый ⌘"
        case 56: return "левый ⇧"
        case 60: return "правый ⇧"
        case 58: return "левый ⌥"
        case 61: return "правый ⌥"
        case 59: return "левый ⌃"
        case 62: return "правый ⌃"
        case 63: return "Fn"
        default: return "?"
        }
    }

    private static func isModifierKeyCode(_ code: Int64) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code)
    }

    private static func flag(for code: Int64) -> CGEventFlags {
        switch code {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 63:     return .maskSecondaryFn
        default:     return []
        }
    }

    private func handleMouseButtonDown(buttonNumber: Int, pipelines: [VoicePipeline]) {
        guard !isTriggerHeld else { return }

        for pipeline in pipelines {
            guard case .mouseButton(let btn) = pipeline.trigger else { continue }
            if btn.buttonNumber == buttonNumber {
                isTriggerHeld = true
                activePipeline = pipeline
                DispatchQueue.main.async { [weak self] in
                    self?.onPipelineStart?(pipeline)
                }
                return
            }
        }
    }

    private func handleMouseButtonUp(buttonNumber: Int) {
        guard isTriggerHeld, let active = activePipeline else { return }
        if case .mouseButton(let btn) = active.trigger, btn.buttonNumber == buttonNumber {
            isTriggerHeld = false
            activePipeline = nil
            DispatchQueue.main.async { [weak self] in
                self?.onPipelineStop?(active)
            }
        }
    }
}
