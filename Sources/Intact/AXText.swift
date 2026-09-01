import AppKit
import ApplicationServices

/// Работа с текстовым полем через дерево доступности.
///
/// Здесь два разных дела, которые раньше были размазаны по `TextInserter` и
/// `FocusInspector`: найти сфокусированное поле у *нужного* приложения и
/// написать в него напрямую, без буфера обмена и без клавиатуры.
enum AXText {

    /// Сколько ждём ответа от чужого приложения.
    ///
    /// По умолчанию Accessibility ждёт ответа **6 секунд**. Если целевое
    /// приложение задумалось (а Electron задумывается регулярно), любой наш
    /// запрос об этом узнает первым — и повесит поток, с которого спрашивали.
    /// У нас спрашивают в том числе с главного потока, а на его ранлупе висит
    /// перехватчик клавиш: пока поток спит, система вправе отключить
    /// перехватчик по таймауту, и нажатия теряются.
    private static let messagingTimeout: Float = 0.25

    private static func timedElement(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    // MARK: - Поиск поля

    /// Сфокусированный элемент у конкретного приложения.
    ///
    /// Спрашиваем именно у него, а не у «того, кто сейчас впереди». Раньше и
    /// проверка, и постфактум-снимок читали `frontmostApplication`, а вставка
    /// шла в `targetApp` — в логе живьём попадалось решение, принятое про
    /// Telegram, и текст, ушедший в Antigravity.
    /// Код последней неудачи поиска — для лога. Отличать −25212 (дерево спит)
    /// от −25202 (элемент приложения вообще невалиден) важно: это разные
    /// болезни с разным лечением, а в строке лога они выглядели одинаково.
    /// Пишется с очереди вставки, читается с главного — поэтому под замком.
    /// Падения незащищённое поле не давало (`AXError` — выровненный 32-битный
    /// enum), но врало ровно в том сценарии, ради которого заведено: при двух
    /// наложившихся доставках строка лога показывала код от чужого запроса.
    private static let errorLock = NSLock()
    private static var _lastLookupError: AXError = .success
    static var lastLookupError: AXError {
        get { errorLock.lock(); defer { errorLock.unlock() }; return _lastLookupError }
    }
    private static func noteLookupError(_ err: AXError) {
        errorLock.lock(); _lastLookupError = err; errorLock.unlock()
    }

    static func focusedElement(of app: NSRunningApplication?) -> AXUIElement? {
        guard let app, app.processIdentifier > 0 else { return systemWideFocusedElement() }
        let appElement = timedElement(AXUIElementCreateApplication(app.processIdentifier))
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &ref)
        noteLookupError(err)
        guard err == .success, let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return timedElement(unsafeBitCast(ref, to: AXUIElement.self))
    }

    /// То же самое, но через системный элемент — им пользуется Hex.
    /// Отвечает только про фронтальное приложение, поэтому это запасной путь.
    static func systemWideFocusedElement() -> AXUIElement? {
        let system = timedElement(AXUIElementCreateSystemWide())
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return timedElement(unsafeBitCast(ref, to: AXUIElement.self))
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    static func role(_ element: AXUIElement) -> String { string(element, kAXRoleAttribute as String) ?? "" }
    static func subrole(_ element: AXUIElement) -> String { string(element, kAXSubroleAttribute as String) ?? "" }

    /// Поле пароля. Туда не вставляем никогда — ни распознанную речь, ни
    /// тем более ответ модели: текст ушёл бы в чужое хранилище паролей, а
    /// человек бы этого не увидел.
    static func isSecureField(_ element: AXUIElement) -> Bool {
        subrole(element) == (kAXSecureTextFieldSubrole as String) || role(element) == "AXSecureTextField"
    }

    // MARK: - Прямая вставка

    /// Пишет текст в точку вставки, заменяя выделение.
    ///
    /// Это тот самый путь, которого у нас не было вовсе. Он не трогает буфер
    /// обмена, не зависит от раскладки и работает даже при включённом
    /// защищённом вводе, где синтетические нажатия не проходят. У Hex это
    /// последнее звено цепочки (`PasteStrategy.accessibility`), и здесь тоже:
    /// в редакторах и терминалах ⌘V ведёт себя предсказуемее, а `AXSelectedText`
    /// умеют не все.
    static func insert(_ text: String, into element: AXUIElement) -> Bool {
        guard isTextInput(element) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    /// Роли, которые полем ввода не бывают никогда.
    ///
    /// Замерено на живом Chrome и Electron: у `AXWebArea` (в странице ничего не
    /// выбрано), у `AXWindow` (кликнули по пустому месту окна) и у `AXCheckBox`
    /// не настраивается ни `AXValue`, ни `AXSelectedText`, ни `AXSelectedTextRange`.
    private static let neverInput: Set<String> = [
        "AXWebArea", "AXWindow", "AXButton", "AXImage", "AXStaticText",
        "AXCheckBox", "AXRadioButton", "AXLink", "AXMenuItem", "AXMenuBarItem",
        "AXSlider", "AXScrollBar", "AXHeading", "AXToolbar", "AXTabGroup",
        "AXList", "AXOutline", "AXTable", "AXRow", "AXCell", "AXPopUpButton",
        "AXMenu", "AXMenuButton", "AXSplitter", "AXDisclosureTriangle",
        "AXColorWell", "AXStepper", "AXProgressIndicator",
    ]

    /// Есть ли смысл писать в этот элемент напрямую.
    ///
    /// **Это не «примет ли приложение вставку».** Такой вопрос мы больше не
    /// задаём — на него честно отвечает только сама попытка, и ради этого
    /// ⌘V шлётся куда угодно без предварительных условий.
    ///
    /// Здесь вопрос другой и законный: **есть ли вообще куда писать**. Прямая
    /// запись `AXSelectedText` в `AXWebArea` возвращает `.success` и не делает
    /// ничего — на этом движок один раз соврал вслух: ответ ИИ «вставился» в
    /// тело страницы Safari, карточка не появилась, текст пропал.
    ///
    /// Признак `AXInsertionPointLineNumber` для этого не годится и не
    /// используется: он стоит и у галочки, и у пустой страницы.
    static func isTextInput(_ element: AXUIElement) -> Bool {
        guard !isSecureField(element) else { return false }

        let role = role(element)
        if ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(role) { return true }
        if neverInput.contains(role) { return false }

        var valSettable: DarwinBoolean = false
        var selSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valSettable)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selSettable)
        return valSettable.boolValue || selSettable.boolValue
    }

    // MARK: - Снимок для проверки

    /// Дешёвый снимок поля — чтобы после вставки понять, дошла ли она.
    ///
    /// Читаются отдельные атрибуты, а не `AXValue` целиком: в редакторе это
    /// мегабайты на каждую диктовку.
    struct Snapshot: Equatable {
        var length: Int?
        var caret: Int?
        /// Сколько символов было выделено — вставка их заменит.
        var selection: Int = 0

        /// Есть ли чем проверять.
        ///
        /// Ноль в обоих полях — это НЕ измерение. Так отвечает `AXGroup` в
        /// Electron: атрибуты формально есть, значения всегда нулевые. Раньше
        /// такой снимок считался измеримым, «не изменился» — и удачная вставка
        /// объявлялась провалом. В логе это три подряд
        /// «⌘V не дошёл: символов 0→0, каретка 0→0».
        var isMeasurable: Bool {
            if length == nil && caret == nil { return false }
            if (length ?? 0) == 0 && (caret ?? 0) == 0 { return false }
            return true
        }
    }

    static func snapshot(_ element: AXUIElement?) -> Snapshot {
        guard let element else { return Snapshot() }
        var snapshot = Snapshot()

        var countRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &countRef) == .success {
            snapshot.length = countRef as? Int
        }
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let value = rangeRef, CFGetTypeID(value) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range) {
                snapshot.caret = range.location
                snapshot.selection = range.length
            }
        }
        return snapshot
    }

    /// Чем кончилась вставка, судя по полю.
    enum Verdict { case landed, failed, unmeasurable }

    /// Сверяет снимки направленно: мы знаем, СКОЛЬКО вставляли, — значит можно
    /// проверять не «что-то изменилось», а «изменилось ровно на это».
    ///
    /// Почему не хватало «изменилось»: сравнивались два `Optional`, и переход
    /// `caret: nil → 3` (атрибут просто проснулся) засчитывался как успешная
    /// вставка. Обратная ошибка тоже была: длина не изменилась, потому что
    /// вставляли поверх выделения ровно такой же длины.
    ///
    /// Точные равенства выводятся так. Пусть выделение начиналось на позиции
    /// `L` длиной `S`, вставляем `N` символов. Тогда после вставки каретка
    /// стоит на `L + N`, а длина поля равна `было − S + N`.
    ///
    /// Совпадение хотя бы по одному из двух — это успех. Если ни одно не
    /// сошлось, но состояние всё же изменилось, считаем успехом тоже: текст
    /// мог приехать не дословно (умные кавычки, нормализация переводов
    /// строк), и придираться к точной длине здесь опаснее, чем поверить.
    /// Провал — только когда не изменилось ничего.
    static func verdict(before: Snapshot, after: Snapshot, inserted: Int) -> Verdict {
        guard before.isMeasurable || after.isMeasurable else { return .unmeasurable }

        if let was = before.caret, let now = after.caret, now == was + inserted { return .landed }
        if let was = before.length, let now = after.length,
           now == was - before.selection + inserted { return .landed }

        // Сравниваем только то, что известно С ОБЕИХ сторон.
        //
        // Здесь стояло прямое сравнение `Optional`, и оно давало «изменилось»
        // на ровном месте — в обе стороны:
        //
        // — поле умерло или приложение не ответило за `messagingTimeout`
        //   (0.25 с): в `after` оба атрибута остаются nil, `Optional(12) != nil`
        //   истинно, и провал засчитывался как `.landed`. Дальше вставка
        //   рапортовала успех, играла звук и через 0.5 с возвращала прежний
        //   буфер поверх нашего текста — сказанное пропадало целиком;
        // — обратный случай, описанный абзацем выше: `caret: nil → 3`, атрибут
        //   просто проснулся. Точные равенства его закрыли, а этот запасной
        //   путь — нет.
        //
        // Проверять `after.isMeasurable` нельзя: пустое поле по этому признаку
        // тоже «неизмеримо» (`length == 0 && caret == 0`), а диктуют чаще всего
        // именно в пустое.
        var changed = before.selection != after.selection
        if let was = before.length, let now = after.length, was != now { changed = true }
        if let was = before.caret,  let now = after.caret,  was != now { changed = true }
        return changed ? .landed : .failed
    }
}
