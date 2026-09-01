import AppKit
import Carbon.HIToolbox

/// Синтетическая клавиатура: всё, что мы «нажимаем» за пользователя.
///
/// Отдельный файл, потому что у синтетического ввода на macOS ровно четыре
/// способа промахнуться, и каждый из них — отдельная строчка кода, которую
/// легко потерять при следующей правке. Разбор открытого кода тех, у кого
/// вставка работает (VoiceInk, Hex, Maccy, espanso), сходится на одном и том
/// же наборе приёмов — они собраны здесь и подписаны источником.
enum SyntheticKeyboard {

    /// Метка «это событие послали мы».
    ///
    /// У нас на главном ранлупе висит собственный перехватчик
    /// (`InputEventManager`), и наши же ⌘V и печать приходят в него как
    /// обычные нажатия. Без метки перехватчик считает их «пользователь нажал
    /// клавишу во время удержания триггера» и отменяет пайплайн.
    /// Приём взят у espanso, там для этого метили координату события
    /// (`ESPANSO_POINT_MARKER`); поле `eventSourceUserData` для этого честнее.
    static let marker: Int64 = 0x1_4AC7

    static func mark(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: marker)
    }

    static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    // MARK: - Защищённый ввод

    /// Включён ли системный «защищённый ввод».
    ///
    /// Пока он включён, синтетические нажатия до приложения не доходят —
    /// молча, без единой ошибки. Включают его поля паролей, «Secure Keyboard
    /// Entry» в Терминале и менеджеры паролей; иногда он залипает и после
    /// того, как окно закрыли. Справка Wispr Flow описывает ровно этот случай
    /// как отдельную статью: «другое приложение держит Secure Event Input»,
    /// и перезапуск самой диктовки его не снимает.
    ///
    /// Проверять обязательно: без проверки мы шлём ⌘V в пустоту и объявляем
    /// провал вставки, не сказав человеку, почему.
    static var isSecureInputEnabled: Bool { IsSecureEventInputEnabled() }

    /// Кто держит защищённый ввод — для сообщения человеку.
    /// Читается из IORegistry (`kCGSSessionSecureInputPID`).
    static func secureInputHolder() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        task.arguments = ["-a", "-l", "-w", "0", "-d", "1", "-k", "kCGSSessionSecureInputPID"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        // <key>kCGSSessionSecureInputPID</key><integer>1234</integer>
        guard let range = xml.range(of: "kCGSSessionSecureInputPID") else { return nil }
        let tail = xml[range.upperBound...]
        guard let open = tail.range(of: "<integer>"),
              let close = tail.range(of: "</integer>", range: open.upperBound..<tail.endIndex),
              let pid = pid_t(tail[open.upperBound..<close.lowerBound]) else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
            ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    // MARK: - Залипшие модификаторы

    private static let modifierKeys: [(CGKeyCode, CGEventFlags, String)] = [
        (CGKeyCode(kVK_Shift),        .maskShift,     "⇧"),
        (CGKeyCode(kVK_RightShift),   .maskShift,     "⇧"),
        (CGKeyCode(kVK_Control),      .maskControl,   "⌃"),
        (CGKeyCode(kVK_RightControl), .maskControl,   "⌃"),
        (CGKeyCode(kVK_Option),       .maskAlternate, "⌥"),
        (CGKeyCode(kVK_RightOption),  .maskAlternate, "⌥"),
        (CGKeyCode(kVK_Command),      .maskCommand,   "⌘"),
        (CGKeyCode(kVK_RightCommand), .maskCommand,   "⌘"),
    ]

    /// Какие модификаторы физически зажаты прямо сейчас.
    static var heldModifiers: CGEventFlags {
        CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
    }

    /// Ждёт, пока человек отпустит модификаторы, и отпускает их за него, если
    /// не дождались.
    ///
    /// Зачем: триггеры записи у нас — сами клавиши-модификаторы (левый ⌥,
    /// правый ⌥, правый ⌘), и они удерживаются, пока человек говорит. Если
    /// текст готов раньше, чем клавишу отпустили (а при стриминге черновика
    /// так и бывает), то ⌘V уходит поверх зажатого ⌥ — и приложение получает
    /// ⌥⌘V, то есть «вставить и сохранить стиль» или вообще ничего.
    ///
    /// Приём с принудительным отпусканием взят у espanso (issue #279): они
    /// точно так же проверяют `CGEventSourceKeyState` и шлют key-up за
    /// пользователя.
    ///
    /// - Returns: описание того, что пришлось отпустить силой, или `nil`.
    @discardableResult
    static func settleModifiers(timeout: TimeInterval = 0.25) -> String? {
        guard !heldModifiers.isEmpty else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if heldModifiers.isEmpty { return nil }
            usleep(10_000)
        }

        var forced: [String] = []
        let source = CGEventSource(stateID: .privateState)
        for (key, _, label) in modifierKeys
        where CGEventSource.keyState(.combinedSessionState, key: key) {
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
            mark(up)
            up?.post(tap: .cghidEventTap)
            forced.append(label)
            usleep(5_000)
        }
        return forced.isEmpty ? nil : forced.joined(separator: "")
    }

    // MARK: - Раскладка

    /// Код клавиши, которая в текущей раскладке даёт «v».
    ///
    /// `kVK_ANSI_V` — код *позиции* на клавиатуре, а не буквы: приложение
    /// переводит его через текущую раскладку. На Dvorak в этой позиции стоит
    /// точка, и вместо ⌘V уходит ⌘. — «отмена». Именно из-за этого у Wispr
    /// Flow есть отдельная статья про non-QWERTY раскладки, а Maccy и Hex
    /// берут код клавиши из библиотеки Sauce.
    ///
    /// На нелатинских раскладках (русская, иврит) «v» не набирается вовсе —
    /// там система сама подставляет латиницу для сочетаний с ⌘, и правильный
    /// ответ снова `kVK_ANSI_V`.
    /// **Считается заранее на главном потоке и кешируется.**
    ///
    /// Text Input Sources (`TISCopyCurrentKeyboardInputSource`,
    /// `TISGetInputSourceProperty`, `TISCopyCurrentKeyboardLayoutInputSource`) —
    /// API главного потока: внутри стоит `dispatch_assert_queue(main)`. Вызов с
    /// чужой очереди не возвращает ошибку и не деградирует — он роняет процесс
    /// по SIGTRAP. Ровно так приложение и упало 30 августа: всю вставку унесли
    /// на очередь `intact.insertion`, а раскладку она продолжала спрашивать
    /// оттуда же.
    ///
    /// Возвращать вставку на главный поток нельзя — её унесли, чтобы не
    /// блокировать ранлуп с перехватчиком клавиш. Поэтому раскладку считаем
    /// на главном потоке заранее, а очередь вставки читает готовое число.
    static var pasteKeyCode: CGKeyCode {
        layoutLock.lock()
        let cached = cachedPasteKeyCode
        layoutLock.unlock()
        if let cached { return cached }

        // Кеша ещё нет — просим посчитать и отвечаем безопасным значением.
        // `kVK_ANSI_V` верен и для QWERTY, и для нелатинских раскладок, то есть
        // для подавляющего большинства случаев; неверен он только на Dvorak и
        // подобных, и там уже со второй вставки подхватится посчитанное.
        refreshKeyboardLayout()
        return CGKeyCode(kVK_ANSI_V)
    }

    private static let layoutLock = NSLock()
    private static var cachedPasteKeyCode: CGKeyCode?

    /// Пересчитывает раскладку. Сама уходит на главный поток, если её позвали
    /// с чужого, — трогать TIS откуда попало нельзя.
    static func refreshKeyboardLayout() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { refreshKeyboardLayout() }
            return
        }
        let code = commandSwitchesToQWERTY
            ? CGKeyCode(kVK_ANSI_V)
            : (keyCode(for: "v") ?? CGKeyCode(kVK_ANSI_V))
        layoutLock.lock()
        let changed = cachedPasteKeyCode != code
        cachedPasteKeyCode = code
        layoutLock.unlock()
        if changed { Log.write("Раскладка: код клавиши вставки \(code)") }
    }

    /// Считает раскладку сейчас и следит за её сменой.
    ///
    /// Без подписки кеш устареет после первого же переключения языка, и на
    /// Dvorak вместо ⌘V уйдёт ⌘. — «отмена». Звать один раз при запуске.
    static func watchKeyboardLayout() {
        refreshKeyboardLayout()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleSelectedInputSourcesChangedNotification"),
            object: nil, queue: .main
        ) { _ in refreshKeyboardLayout() }
    }

    /// Раскладки вида «Dvorak — QWERTY ⌘» при зажатом ⌘ переключаются на
    /// QWERTY, поэтому искать позицию «v» в них не нужно и вредно.
    /// Признак взят у VoiceInk: имя раскладки оканчивается на «⌘».
    private static var commandSwitchesToQWERTY: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return false }
        let name = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        return name.hasSuffix("⌘")
    }

    /// Перебирает позиции клавиш и ищет ту, что печатает нужный символ.
    private static func keyCode(for character: String) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data

        return data.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let modifiers = UInt32(0)
            let kbdType = UInt32(LMGetKbdType())

            for code in 0..<CGKeyCode(128) {
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers, kbdType,
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeys, chars.count, &length, &chars)
                guard status == noErr, length > 0 else { continue }
                if String(utf16CodeUnits: chars, count: length) == character { return code }
            }
            return nil
        }
    }

    // MARK: - Вставка ⌘V

    /// Левый ⌘ в «зависимых от устройства» флагах (`NX_DEVICELCMDKEYMASK`).
    ///
    /// Без этого бита часть приложений сочетание просто не узнаёт: они
    /// смотрят, какая именно клавиша нажата, а не обобщённый `maskCommand`.
    /// Приём известен по Flycut (PR #18) и с тех пор живёт в Maccy.
    private static let deviceLeftCommand: UInt64 = 0x000008

    /// Посылает ⌘V так, как это делают приложения, у которых вставка работает.
    ///
    /// Отличия от наивной версии, каждое из которых лечит свой отказ:
    /// - источник `.privateState`, а не `.combinedSessionState`: у второго
    ///   физически зажатые пользователем модификаторы подмешиваются во флаги
    ///   события (VoiceInk);
    /// - подавление настоящей клавиатуры на время вставки (Maccy);
    /// - полная последовательность ⌘↓ V↓ V↑ ⌘↑, а не одно V с флагом: часть
    ///   приложений следит за `flagsChanged` и без «нажатия» ⌘ вставку не
    ///   узнаёт (VoiceInk, Hex);
    /// - паузы между событиями: без них быстрые приложения успевают склеить
    ///   их в одно (VoiceInk: 10 мс);
    /// - код клавиши по текущей раскладке, а не жёсткий `kVK_ANSI_V`.
    static func postPaste() {
        let source = CGEventSource(stateID: .privateState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)

        let vKey = pasteKeyCode
        let cmdKey = CGKeyCode(kVK_Command)
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | deviceLeftCommand)

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        let vDown   = CGEvent(keyboardEventSource: source, virtualKey: vKey,   keyDown: true)
        let vUp     = CGEvent(keyboardEventSource: source, virtualKey: vKey,   keyDown: false)
        let cmdUp   = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)

        cmdDown?.flags = flags
        vDown?.flags = flags
        vUp?.flags = flags
        cmdUp?.flags = []

        for event in [cmdDown, vDown, vUp, cmdUp] { mark(event) }

        cmdDown?.post(tap: .cghidEventTap)
        usleep(10_000)
        vDown?.post(tap: .cghidEventTap)
        usleep(10_000)
        vUp?.post(tap: .cghidEventTap)
        usleep(10_000)
        cmdUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Печать текста

    /// Предел `CGEventKeyboardSetUnicodeString` — 20 UTF-16 единиц на событие.
    /// Недокументированный, но воспроизводимый; espanso режет строку ровно так.
    private static let unicodeChunk = 20

    /// Печатает текст пачками по 20 символов.
    ///
    /// Раньше здесь был один символ на событие с паузой 1.4 мс — то есть на
    /// абзац в 400 знаков уходило больше полсекунды непрерывного долбления
    /// системы событиями. Пачками — двадцать событий вместо четырёхсот.
    ///
    /// Клавиша-носитель — пробел (`kVK_Space`): сам код клавиши приложению
    /// неважен, потому что строка задана явно, но явный key-up нужен —
    /// без него часть приложений ввод не применяет (espanso, issue #159).
    static func typeOut(_ text: String, chunkDelay: useconds_t = 8_000) {
        let source = CGEventSource(stateID: .privateState)
        let units = Array(text.utf16)
        var index = 0

        while index < units.count {
            let end = min(index + unicodeChunk, units.count)
            var chunk = Array(units[index..<end])

            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Space), keyDown: true)
            down?.flags = []
            down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            mark(down)
            down?.post(tap: .cghidEventTap)

            usleep(chunkDelay)

            // Юникод-строка вешается ТОЛЬКО на нажатие. Chromium, Java/Swing и Qt
            // применяют её и на отпускании тоже, если она там есть, — получается
            // «ппррииввеетт». У espanso key-up отправляется пустым по той же причине.
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Space), keyDown: false)
            up?.flags = []
            mark(up)
            up?.post(tap: .cghidEventTap)

            usleep(chunkDelay)
            index = end
        }
    }
}
