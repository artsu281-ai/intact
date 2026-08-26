import AppKit
import ApplicationServices
import Foundation

/// AI-провайдер поверх официального десктопного приложения Gemini на macOS.
///
/// Позволяет использовать Gemini (включая модели Pro/Ultra/Flash в приложении)
/// наравне с локальными llama.cpp и облачными Anthropic API:
/// - Для быстрого ответа по хоткею (Правый ⌥ Option / «Спросите ИИ»)
/// - Для диалогов во вкладке «Чат»
/// - Для причёсывания диктовок и генерации сводок
///
/// Работает 100% локально через macOS Accessibility API (AXUIElement),
/// в фоновом режиме без переключения окон и без затирания буфера обмена.
final class GeminiAIProvider: AIProvider {
    static let shared = GeminiAIProvider()

    /// Ссылка на рабочее окно Gemini, полученная когда окно было живым.
    ///
    /// Ключевой факт (проверен на живом приложении): свёрнутое жёлтой кнопкой окно
    /// перестаёт отдавать себя через `kAXWindows`, но ссылка, взятая ДО сворачивания,
    /// продолжает полностью работать — запись в поле ввода доходит и через 15 секунд
    /// после сворачивания. Поэтому держим ссылку между запросами: пока она жива,
    /// окно пользователя не нужно ни разворачивать, ни трогать вообще.
    private var cachedWindow: AXUIElement?
    private let cacheLock = NSLock()

    private var rememberedWindow: AXUIElement? {
        get { cacheLock.lock(); defer { cacheLock.unlock() }; return cachedWindow }
        set { cacheLock.lock(); cachedWindow = newValue; cacheLock.unlock() }
    }

    /// Синхронная проверка: `GeminiBridgeService.isInstalled` обновляется асинхронно и на первом
    /// обращении после запуска ещё пуст, а SwiftUI спрашивает готовность на каждой перерисовке.
    var isReady: Bool { GeminiBridgeService.isAppAvailable }

    @discardableResult
    func complete(_ request: AIRequest, completion: @escaping (Result<String, AIError>) -> Void) -> AITask {
        stream(request, onDelta: { _ in }, completion: completion)
    }

    @discardableResult
    func stream(
        _ request: AIRequest,
        onDelta: @escaping (String) -> Void,
        completion: @escaping (Result<String, AIError>) -> Void
    ) -> AITask {
        guard isReady else {
            completion(.failure(.providerUnavailable))
            return AITask()
        }

        var isCancelled = false
        let task = AITask {
            isCancelled = true
        }

        // Собираем текст запроса для Gemini
        let prompt = formatPrompt(from: request.messages)
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(.badResponse))
            return task
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // completion должен позваться ровно один раз и обязательно. Раньше при отмене
            // поток просто выходил из цикла — вызывающий код ждал ответа вечно, и индикатор
            // диктовки висел на экране до перезапуска приложения.
            var reported = false
            let finish: (Result<String, AIError>) -> Void = { result in
                guard !reported else { return }
                reported = true
                completion(result)
            }

            guard let self else {
                finish(.failure(.providerUnavailable))
                return
            }

            let bundleId = GeminiBridgeService.bundleIdentifier
            let currentActiveApp = NSWorkspace.shared.frontmostApplication
            var geminiApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first

            if geminiApp == nil {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                    finish(.failure(.providerUnavailable))
                    return
                }
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                config.hides = true
                let sema = DispatchSemaphore(value: 0)
                NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
                    geminiApp = app
                    sema.signal()
                }
                sema.wait()
                Thread.sleep(forTimeInterval: 0.8)
            }

            guard let app = geminiApp ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
                finish(.failure(.providerUnavailable))
                return
            }

            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)

            var windowsRef: CFTypeRef?
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            var wins = windowsRef as? [AXUIElement] ?? []

            // Сохранённая с прошлого раза ссылка идёт первой: она работает и со
            // свёрнутым окном, так что в обычной жизни мы вообще ничего не трогаем.
            if let remembered = self.rememberedWindow,
               self.findElement(in: remembered, role: "AXTextArea") != nil {
                wins.insert(remembered, at: 0)
            }

            if wins.isEmpty {
                // Окно живёт на другом рабочем столе или свёрнуто: kAXWindows его не
                // отдаёт, но main-окно доступно напрямую. Раньше здесь был AppleScript
                // reopen — он активировал Gemini и вытаскивал его на передний план.
                var mainRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainRef) == .success,
                   let main = mainRef as! AXUIElement? {
                    wins = [main]
                }
            }

            if wins.isEmpty {
                // Окон нет вообще (закрыто на крестик) — только тогда открываем новое,
                // и строго без активации
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    // Стартуем СКРЫТЫМ: без этого флага запуск Gemini выкидывает
                    // его окно на экран — пользователь видит «вызвался полноценный
                    // Gemini». Замерено: скрытый запуск не мешает — поле ввода
                    // доступно, окно на экране не появляется.
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = false
                    config.hides = true
                    NSWorkspace.shared.openApplication(at: url, configuration: config)
                }
                var retries = 10
                while retries > 0 {
                    Thread.sleep(forTimeInterval: 0.2)
                    if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                       let newWins = windowsRef as? [AXUIElement], !newWins.isEmpty {
                        wins = newWins
                        break
                    }
                    retries -= 1
                }
                currentActiveApp?.activate()
            }

            // Предпочитаем неминимизированное окно
            let pickedWindow = wins.first(where: { w in
                var m: CFTypeRef?
                AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &m)
                return (m as? Bool) != true
            }) ?? wins.first

            guard let initialWindow = pickedWindow else {
                finish(.failure(.providerUnavailable))
                return
            }
            // Переменная: после восстановления окна ссылка может смениться, и весь
            // дальнейший код (отправка, чтение ответа) обязан работать с новой.
            var window = initialWindow

            // Свёрнутое окно (и окно на другом рабочем столе) не принимает запись через
            // AX: kAXValue выставляется «успешно», но дерево заморожено, текст в поле не
            // появляется, и потом мы вычитываем как «ответ» остатки прошлой переписки —
            // отсюда обрывки в 1–3 символа.
            //
            // Определять это состояние по атрибутам нельзя, обе попытки провалились на
            // живом приложении: kAXMinimized у свёрнутого окна отвечает false, а список
            // kAXWindows то пуст, то нет. Единственный честный признак — поведение:
            // отдаёт ли дерево поле ввода и доходит ли до него запись.
            // Окно пользователя не разворачиваем и на передний план не тащим.
            // Если дерево всё же заморожено (например, Gemini свернули ещё до того,
            // как мы впервые взяли ссылку), просим систему восстановить окна событием
            // reopen БЕЗ активации: проверено — окно возвращается, но фокус остаётся
            // у пользователя, Gemini не становится активным приложением.
            var foundTextArea = self.findElement(in: window, role: "AXTextArea")
            if foundTextArea == nil {
                Log.write("Gemini: дерево окна заморожено — прошу восстановить окно без активации")
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    let cfg = NSWorkspace.OpenConfiguration()
                    cfg.activates = false
                    cfg.hides = true
                    let sem = DispatchSemaphore(value: 0)
                    NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in sem.signal() }
                    _ = sem.wait(timeout: .now() + 3)
                    Thread.sleep(forTimeInterval: 1.0)
                }
                // Забираем окно заново: после восстановления ссылка могла смениться.
                var freshRef: CFTypeRef?
                AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &freshRef)
                let freshWins = freshRef as? [AXUIElement] ?? []
                if let live = freshWins.first(where: { self.findElement(in: $0, role: "AXTextArea") != nil }) {
                    window = live
                    foundTextArea = self.findElement(in: live, role: "AXTextArea")
                } else {
                    foundTextArea = self.findElement(in: window, role: "AXTextArea")
                }
                // Фокус мог дрогнуть — возвращаем его пользователю.
                currentActiveApp?.activate()
            }
            guard foundTextArea != nil else {
                Log.write("Gemini: поле ввода недоступно даже после восстановления — запрос отменён")
                finish(.failure(.providerUnavailable))
                return
            }
            // Запоминаем рабочее окно: пока эта ссылка жива, сворачивание Gemini
            // жёлтой кнопкой перестаёт мешать — писать в него можно и свёрнутым.
            self.rememberedWindow = window

            // Новый чат НЕ создаём: работаем в том диалоге, который открыт у пользователя.
            // Нажатие «Новый чат» перестраивало страницу целиком, и ссылка на поле
            // ввода, взятая до нажатия, указывала на уже удалённый элемент — запись
            // в него молча не проходила. Именно из-за этого вопрос к ИИ срывался
            // «через раз», а причёсывание маскировало сбой тем, что вставляло
            // распознанный текст как запасной вариант.
            guard let textArea = foundTextArea else {
                finish(.failure(.providerUnavailable))
                return
            }

            // Запоминаем исходные тексты в окне ДО отправки нового запроса
            let initialTexts = Set(self.getStaticTexts(window))

            // Снимок последнего ответа В ДИАЛОГЕ до отправки. Мы больше не создаём
            // новый чат, поэтому в окне уже лежит переписка, и у прошлого ответа
            // тоже есть кнопка «Скопировать ответ» — без этого снимка якорь сразу
            // цеплялся за старое сообщение и выдавал его за свежий ответ.
            let baselineAnswer = self.latestAnswerText(in: window)
            let baselineAnswerCount = self.answerBlockCount(in: window)

            // Устанавливаем промпт в поле ввода и ОБЯЗАТЕЛЬНО проверяем чтением обратно.
            // Код возврата здесь не показатель: замёрзшее дерево (свёрнутое окно, окно
            // на другом столе) отвечает .success, но текст в поле не появляется — и мы
            // потом вычитываем как «ответ» остатки прошлой переписки.
            func writePrompt() -> Bool {
                // Пишем текст как пользовательский ВВОД (выделить всё + заменить
                // выделение), а не подменой kAXValue. Разница принципиальная:
                //  - подмену значения веб-приложение Gemini не регистрирует, поле
                //    визуально заполняется, но «Отправить» ничего не делает;
                //  - установка kAXFocused помогала, но выносила чужое окно вперёд —
                //    это прямо противоречит работе в фоне.
                // Вставка через выделение регистрируется как ввод и фокус не трогает.
                guard Self.insertAsUserInput(prompt, into: textArea) else { return false }
                for _ in 0..<10 {
                    Thread.sleep(forTimeInterval: 0.05)
                    var back: CFTypeRef?
                    AXUIElementCopyAttributeValue(textArea, kAXValueAttribute as CFString, &back)
                    if let text = back as? String, text.contains(prompt.prefix(24)) { return true }
                }
                return false
            }

            guard writePrompt() else {
                Log.write("Gemini: окно не приняло промпт — запрос отменён, чтобы не выдать чужой текст за ответ")
                finish(.failure(.providerUnavailable))
                return
            }

            Thread.sleep(forTimeInterval: 0.2)

            // Отправку проверяем по факту: у отправленного сообщения поле ввода
            // пустеет. Кнопка может быть на месте и «активна», но не сработать —
            // тогда пробуем Enter прямо в процесс.
            func composerIsEmpty() -> Bool {
                var v: CFTypeRef?
                AXUIElementCopyAttributeValue(textArea, kAXValueAttribute as CFString, &v)
                let text = ((v as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty || !text.contains(prompt.prefix(24))
            }
            func waitSent(_ ticks: Int) -> Bool {
                for _ in 0..<ticks {
                    Thread.sleep(forTimeInterval: 0.2)
                    if composerIsEmpty() { return true }
                }
                return false
            }

            var sent = false
            if let sendBtn = self.findElement(in: window, role: "AXButton", descMatch: ["Отправить", "Send", "submit"]) {
                AXUIElementPerformAction(sendBtn, kAXPressAction as CFString)
                sent = waitSent(15)
            }
            if !sent {
                Log.write("Gemini: кнопка отправки не сработала — пробую Enter")
                let src = CGEventSource(stateID: .combinedSessionState)
                let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)
                let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)
                keyDown?.postToPid(pid)
                keyUp?.postToPid(pid)
                sent = waitSent(15)
            }

            currentActiveApp?.activate()

            guard sent else {
                // Оставлять свой промпт в чужом композере нельзя — уберём за собой.
                AXUIElementSetAttributeValue(textArea, kAXValueAttribute as CFString, "" as CFTypeRef)
                Log.write("Gemini: сообщение не отправилось — поле очищено, запрос отменён")
                finish(.failure(.providerUnavailable))
                return
            }

            // Ожидаем ответ и стримим дельту (шаг 150 мс для максимальной отзывчивости).
            // Предел считаем по часам, а не по числу тиков: каждый тик дважды обходит дерево
            // Accessibility, и «25 секунд» из настроек превращались в минуту с лишним.
            var previousFullText = ""
            var unchangedCount = 0
            let pollInterval: TimeInterval = 0.15
            let deadline = Date().addingTimeInterval(request.timeout)

            while Date() < deadline {
                if isCancelled {
                    finish(.failure(.timeout))
                    return
                }
                Thread.sleep(forTimeInterval: pollInterval)

                // Страж фона: если Gemini украл фокус — молча возвращаем его
                // тому приложению, в котором работал пользователь
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                    currentActiveApp?.activate()
                }

                // Текст последнего ответа берём по якорю — кнопке «Скопировать ответ»:
                // она лежит рядом с самим ответом в дереве, тогда как «последний
                // AXStaticText в окне» регулярно оказывается служебным узлом
                // (заголовок процесса размышления, чипы-подсказки, счётчики).
                // Именно из-за этого в поле вместо ответа прилетало «10».
                // Ответ считаем новым, только если в диалоге прибавился блок ответа
                // либо текст последнего блока отличается от снимка до отправки.
                let rawAnchored = self.latestAnswerText(in: window)
                let isNewAnswer = self.answerBlockCount(in: window) > baselineAnswerCount
                    || (rawAnchored != nil && rawAnchored != baselineAnswer)
                let anchored = isNewAnswer ? rawAnchored : nil

                // Пока якоря нет (ответ ещё печатается), старая эвристика годится
                // только для живого предпросмотра — фиксировать по ней результат нельзя.
                let preview: String?
                if anchored == nil {
                    let currentTexts = self.getStaticTexts(window)
                    let candidateTexts = currentTexts.filter { text in
                        text != prompt && !initialTexts.contains(text) && !text.contains(prompt.prefix(40))
                    }
                    preview = candidateTexts.last
                } else {
                    preview = nil
                }

                if let rawCandidate = anchored ?? preview, !rawCandidate.isEmpty {
                    let answerCandidate = self.cleanGeminiAnswer(rawCandidate)
                    if !answerCandidate.isEmpty {
                        if answerCandidate != previousFullText {
                            let delta: String
                            if answerCandidate.hasPrefix(previousFullText) {
                                delta = String(answerCandidate.dropFirst(previousFullText.count))
                            } else {
                                delta = answerCandidate
                            }
                            previousFullText = answerCandidate
                            unchangedCount = 0
                            onDelta(delta)
                        } else {
                            unchangedCount += 1
                        }

                        // Фиксируем результат ТОЛЬКО по якорному тексту: предпросмотр
                        // без якоря — это ещё не ответ, а то, что успело отрисоваться.
                        // Плюс ждём, что текст перестал расти: кнопка «Скопировать»
                        // появляется и у ещё дописываемого ответа.
                        if anchored != nil && unchangedCount >= 3 && !previousFullText.isEmpty {
                            finish(.success(previousFullText))
                            return
                        }
                    }
                }
            }

            if !previousFullText.isEmpty {
                finish(.success(previousFullText))
            } else {
                finish(.failure(.timeout))
            }
        }

        return task
    }

    /// Текст последнего ответа Gemini, найденный по якорю — кнопке «Скопировать ответ».
    ///
    /// Раньше ответом считался просто последний `AXStaticText` в окне, и это регулярно
    /// давало мусор: во время генерации последним узлом оказывается заголовок процесса
    /// размышления («… , expand_more, Ответить сразу»), а в свежем чате — служебные
    /// счётчики интерфейса (именно так в поле однажды прилетело «10» вместо ответа).
    ///
    /// Кнопка «Скопировать ответ» принадлежит блоку конкретного ответа, поэтому от неё
    /// можно подняться к общему предку и взять текст оттуда — проверено на живом окне:
    /// на третьем уровне вверх поддерево содержит ровно текст ответа и ничего лишнего.
    /// Возвращает `nil`, пока такой кнопки нет — значит, ответ ещё не готов.
    private func latestAnswerText(in window: AXUIElement) -> String? {
        var paths: [[AXUIElement]] = []
        collectCopyButtonPaths(window, path: [], into: &paths)
        // Последняя кнопка — самый свежий ответ в диалоге.
        guard let path = paths.last, !path.isEmpty else { return nil }

        for up in 1...min(6, path.count) {
            let ancestor = path[path.count - up]
            let texts = getStaticTexts(ancestor)
            // Ответ — самый объёмный текст в блоке: рядом с ним попадаются
            // короткие служебные подписи вроде «Источники».
            if let best = texts.max(by: { $0.count < $1.count }),
               !best.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return best
            }
        }
        return nil
    }

    /// Вставляет текст в поле как пользовательский ввод: выделяет всё содержимое
    /// и заменяет выделение. Только так веб-приложение Gemini считает текст введённым
    /// и разблокирует отправку — и, в отличие от установки kAXFocused, чужое окно
    /// при этом не выносится на передний план.
    static func insertAsUserInput(_ text: String, into textArea: AXUIElement) -> Bool {
        var existingRef: CFTypeRef?
        AXUIElementCopyAttributeValue(textArea, kAXValueAttribute as CFString, &existingRef)
        let existingLength = ((existingRef as? String) ?? "").utf16.count

        var selection = CFRangeMake(0, existingLength)
        if let rangeValue = AXValueCreate(.cfRange, &selection) {
            AXUIElementSetAttributeValue(textArea, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }
        return AXUIElementSetAttributeValue(textArea, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    /// Сколько ответов уже есть в открытом диалоге — по числу кнопок «Скопировать ответ».
    /// Рост этого числа после отправки и есть признак того, что пришёл новый ответ.
    private func answerBlockCount(in window: AXUIElement) -> Int {
        var paths: [[AXUIElement]] = []
        collectCopyButtonPaths(window, path: [], into: &paths)
        return paths.count
    }

    /// Пути (от окна вниз) до каждой кнопки «Скопировать ответ» — по одной на ответ.
    private func collectCopyButtonPaths(_ el: AXUIElement, path: [AXUIElement], into out: inout [[AXUIElement]], depth: Int = 0) {
        if depth > 45 { return }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        if role == "AXButton" {
            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
            let desc = (descRef as? String ?? "").lowercased()
            if desc.contains("скопировать ответ") || desc.contains("copy response") {
                out.append(path + [el])
            }
            return
        }
        // Боковую панель с историей чатов не обходим: там сотни кнопок и ни одного ответа.
        if role == "AXOutline" { return }

        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef)
        if let children = childrenRef as? [AXUIElement] {
            for child in children {
                collectCopyButtonPaths(child, path: path + [el], into: &out, depth: depth + 1)
            }
        }
    }

    /// Имена лигатур Material-иконок: в дереве Accessibility они приходят как обычный текст.
    private static let iconLigatures: Set<String> = [
        "info", "expand_more", "expand_less", "content_copy", "thumb_up", "thumb_down",
        "more_vert", "refresh", "share", "edit", "mic", "send"
    ]

    /// Очищает текст ответа от системных тегов интерфейса Gemini (процесс размышления, expand_more и служебные заголовки)
    private func cleanGeminiAnswer(_ raw: String) -> String {
        var text = raw

        // 1. Удаляем маркеры выпадающего списка рассуждений (expand_more / expand_less)
        if let range = text.range(of: "expand_more") {
            text = String(text[range.upperBound...])
        }
        if let range = text.range(of: "expand_less") {
            text = String(text[range.upperBound...])
        }

        // 2. Удаляем русские и английские надписи интерфейса размышлений
        let uiLabels = [
            "Показать процесс размышления",
            "Скрыть процесс размышления",
            "Show thought process",
            "Hide thought process",
            "Thought process"
        ]
        for label in uiLabels {
            if let range = text.range(of: label, options: [.caseInsensitive]) {
                text = String(text[range.upperBound...])
            }
        }

        // 3. Убираем служебные строки инициализации рассуждений
        let lines = text.components(separatedBy: "\n")
        var cleanLines: [String] = []
        var skippingThoughts = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Initiating ") || trimmed.hasPrefix("Formulating ") || trimmed.hasPrefix("Begin Assessing ") || trimmed.hasPrefix("Assessing ") || trimmed.hasPrefix("Drafting ") {
                skippingThoughts = true
                continue
            }
            if skippingThoughts {
                if trimmed.isEmpty || trimmed.hasPrefix("I'm ") || trimmed.hasPrefix("Okay, ") || trimmed.hasPrefix("Now, ") {
                    continue
                } else {
                    skippingThoughts = false
                }
            }
            // Удаляем всплывающие системные уведомления Gemini
            if trimmed.localizedCaseInsensitiveContains("расходовать лимит") ||
               trimmed.localizedCaseInsensitiveContains("исчерпали лимит") ||
               trimmed.localizedCaseInsensitiveContains("исчерпан") ||
               trimmed.localizedCaseInsensitiveContains("лимит быстрее") ||
               trimmed.localizedCaseInsensitiveContains("Gemini – это ИИ") ||
               trimmed.localizedCaseInsensitiveContains("Gemini - это ИИ") ||
               Self.iconLigatures.contains(trimmed.lowercased()) {
                continue
            }
            cleanLines.append(line)
        }

        text = cleanLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    /// Форматирует историю сообщений в один текст для Gemini
    private func formatPrompt(from messages: [AIMessage]) -> String {
        if messages.count == 1, let single = messages.first {
            return single.content
        }

        var parts: [String] = []
        for msg in messages {
            switch msg.role {
            case .system:
                parts.append("Инструкция: \(msg.content)")
            case .user:
                parts.append(msg.content)
            case .assistant:
                parts.append("Ответ: \(msg.content)")
            case .tool:
                parts.append("Данные: \(msg.content)")
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// Извлекает список текстовых сообщений из окна Gemini
    private func getStaticTexts(_ el: AXUIElement) -> [String] {
        var results: [String] = []
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        // Игнорируем боковое меню с историей и панели кнопок
        if role == "AXOutline" || role == "AXToolbar" || role == "AXButton" {
            return []
        }

        var valueRef: CFTypeRef?
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef)
        AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
        let val = valueRef as? String ?? ""
        let desc = descRef as? String ?? ""
        let candidate = val.isEmpty ? desc : val

        if role == "AXStaticText" && !candidate.isEmpty {
            let ignoreSubstrings = [
                "Показать процесс",
                "Скрыть процесс",
                "Show thought",
                "Hide thought",
                "Thought process",
                "Gemini – это ИИ",
                "Gemini - это ИИ",
                "Gemini is an AI",
                "исчерпали лимит",
                "исчерпан",
                "исчерпать лимит",
                "расходовать лимит",
                "лимит быстрее",
                "лимит запросов",
                "consume quota",
                "rate limit",
                "usage limit",
                "Initiating the Analysis"
            ]
            // «info», «expand_more» и прочее — это имена лигатур Material-иконок, приходящие
            // отдельными строками. Проверка шла по вхождению подстроки, и любой ответ
            // со словом "information" молча выбрасывался вместе с иконками.
            let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldIgnore = Self.iconLigatures.contains(trimmedCandidate.lowercased())
                || ignoreSubstrings.contains { candidate.localizedCaseInsensitiveContains($0) }
            if !shouldIgnore {
                results.append(candidate)
            }
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                results.append(contentsOf: getStaticTexts(child))
            }
        }
        return results
    }

    /// Рекурсивный поиск UI-элемента
    private func findElement(in el: AXUIElement, role: String, descMatch: [String]? = nil) -> AXUIElement? {
        var roleRef: CFTypeRef?
        var descRef: CFTypeRef?
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)
        let r = roleRef as? String ?? ""
        let d = descRef as? String ?? ""
        let t = titleRef as? String ?? ""
        if r == role {
            if let match = descMatch {
                for target in match {
                    if d.localizedCaseInsensitiveContains(target) || t.localizedCaseInsensitiveContains(target) {
                        return el
                    }
                }
            } else {
                return el
            }
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findElement(in: child, role: role, descMatch: descMatch) {
                    return found
                }
            }
        }
        return nil
    }
}
