import AppKit

/// Доставка распознанного текста в активное приложение.
///
/// Сама механика живёт в `InsertionEngine` (цепочка попыток),
/// `SyntheticKeyboard` (синтетические нажатия) и `AXText` (дерево
/// доступности). Здесь остался только фасад: проверка прав, лог и прежняя
/// подпись для вызывающих.
enum TextInserter {

    static var hasAccessibility: Bool { Permissions.accessibility }

    static func requestAccessibility() { Permissions.requestAccessibility() }

    /// - Parameter completion: `true` — текст доставлен, `false` — все способы
    ///   провалились (текст при этом остаётся в буфере обмена, и вызывающая
    ///   сторона показывает карточку «Скопировать»).
    ///
    ///   Звук успеха и прочую обратную связь вешать только на `true`. Раньше
    ///   звук играл сразу после отправки ⌘V, за ~370 мс до того, как выяснится,
    ///   дошёл ли он, — и при неудаче получалось «звук вставки, потом карточка
    ///   „скопировать“», хотя вставлять было некуда.
    static func deliver(_ text: String, mode: OutputMode, targetApp: NSRunningApplication? = nil,
                        completion: ((Bool) -> Void)? = nil) {
        guard mode == .clipboard || Permissions.accessibility else {
            Clipboard.write(text, transient: false, session: nil)
            Log.write("текст в буфере, но вставить нельзя: нет «Универсального доступа»")
            completion?(false)
            return
        }

        InsertionEngine.deliver(text, mode: mode, targetApp: targetApp) { outcome in
            if outcome.landed {
                Log.write("Вставлено через \(outcome.via)")
            } else {
                Log.write("Вставить не удалось: \(outcome.reason ?? "причина неизвестна") — текст оставлен в буфере")
            }
            completion?(outcome.landed)
        }
    }
}
