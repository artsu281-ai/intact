import AppKit
import IOKit.hid

/// macOS делит нужные нам права надвое, и путать их нельзя:
///
/// - **Мониторинг ввода** — чтобы *читать* нажатия (удержание ⌥ через CGEventTap).
/// - **Универсальный доступ** — чтобы *отправлять* события (⌘V и печать текста).
///
/// Без первого клавиша молча не работает, без второго текст молча остаётся в буфере.
enum Permissions {

    // MARK: - Мониторинг ввода (чтение)

    static var inputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    // MARK: - Универсальный доступ (отправка)

    static var accessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    // MARK: - Общее

    static var allGranted: Bool { inputMonitoring && accessibility }

    /// Чего не хватает — человеческим языком, для меню и настроек.
    static var missingDescription: String? {
        switch (inputMonitoring, accessibility) {
        case (true, true):   return nil
        case (false, true):  return T("Нет «Мониторинга ввода» — клавиша ⌥ не читается",
                                       "No “Input Monitoring” — the ⌥ key isn't read")
        case (true, false):  return T("Нет «Универсального доступа» — текст не вставляется",
                                       "No “Accessibility” access — text isn't inserted")
        case (false, false): return T("Нет доступа к клавиатуре — ни ⌥, ни вставка не работают",
                                       "No keyboard access — neither ⌥ nor pasting works")
        }
    }

    private static func open(_ url: String) {
        NSWorkspace.shared.open(URL(string: url)!)
    }
}

/// Лог в файл: системный лог для приложения без подписи разработчика
/// пустой, а разбираться, почему клавиша молчит, как-то надо.
enum Log {
    private static let url = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Intact.log")

    /// Запись сериализована.
    ///
    /// Каждый вызов открывает свой `FileHandle`, делает `seekToEnd()` и
    /// `write` — три операции без единой блокировки. Пока весь код жил на
    /// главном потоке, это сходило с рук. После переезда вставки на очередь
    /// `intact.insertion` в лог пишут два потока сразу, и строки могут
    /// наложиться друг на друга или потеряться. Очередь последовательная и
    /// асинхронная: ни главный поток, ни очередь вставки на ней не ждут.
    private static let queue = DispatchQueue(label: "intact.log", qos: .utility)

    static func write(_ message: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard))  \(message)\n"
        NSLog("Intact: \(message)")
        guard let data = line.data(using: .utf8) else { return }
        queue.async { append(data) }
    }

    private static func append(_ data: Data) {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    static var path: String { url.path }
}
