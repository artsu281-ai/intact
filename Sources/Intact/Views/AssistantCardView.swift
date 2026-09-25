import AppKit
import EventKit
import SwiftUI

// Карточки ассистента правого ⌘ (план B.2): итог действий, ответ, подтверждение,
// уточнение, черновик, ошибка, таймер.
//
// Показываются в той же плавающей `IndicatorPanel`, что и «Текст готов», и собраны
// из тех же деталей — фон, `SoftButton`, `DismissCountdownButton`, — чтобы не
// выглядеть чужими. Панель не активирует Intact и не берёт клавиатуру, поэтому
// у карточек нет горячих клавиш: ⏎ и ⌘C ушли бы в приложение пользователя.

struct AssistantCardView: View {
    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

    let card: AssistantCard
    /// Секунды до автозакрытия; nil — карточка висит, пока её не закроют.
    let remaining: Int?
    let onButton: (AssistantCardButton) -> Void

    init(card: AssistantCard, remaining: Int?, onButton: @escaping (AssistantCardButton) -> Void) {
        self.card = card
        self.remaining = remaining
        self.onButton = onButton
    }

    /// Размер панели под карточку. Считается тем же разбором (`spec`), что и
    /// отрисовка, поэтому окно и содержимое не могут разойтись.
    static func size(for card: AssistantCard) -> CGSize {
        layout(for: spec(for: card)).size
    }

    var body: some View {
        let spec = Self.spec(for: card)
        let layout = Self.layout(for: spec)

        VStack(alignment: .leading, spacing: 0) {
            header(spec)
                .frame(height: M.header)

            Spacer().frame(height: M.headerGap)

            if !spec.lead.isEmpty {
                blocks(spec.lead)
                    .frame(height: layout.leadHeight, alignment: .top)
                Spacer().frame(height: M.blockGap)
            }

            ScrollView(.vertical, showsIndicators: layout.scrolls) {
                blocks(spec.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: layout.bodyHeight)

            if let footer = layout.footer {
                Spacer().frame(height: M.footerGap)
                footerView(spec, footer)
            }
        }
        .padding(M.pad)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
                .shadow(color: Palette.hudShadow(theme: themeStamp.theme), radius: 16, y: 6)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.title)
    }

    // MARK: - Шапка

    private func header(_ spec: Spec) -> some View {
        HStack(spacing: 8) {
            IntactIcon(kind: spec.icon, size: 15, tone: spec.iconTone)
                .foregroundStyle(Palette.textPrimary)

            Text(card.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            DismissCountdownButton(seconds: remaining ?? 0) { onButton(spec.close) }
                .accessibilityLabel(spec.close == .reject ? T("Отменить план", "Cancel the plan")
                                                          : T("Закрыть", "Close"))
                .accessibilityValue(remaining.flatMap { $0 > 0 ? T("закроется через \($0) с", "closes in \($0) s") : nil } ?? "")
        }
    }

    // MARK: - Содержимое

    private func blocks(_ list: [Block]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { index, block in
                if index > 0 {
                    Color.clear.frame(height: Self.gap(list[index - 1], block))
                }
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .text(let text, let markdown):
            Text(markdown ? Self.inlineMarkdown(text) : AttributedString(text))
                .font(.system(size: M.bodySize))
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(M.bodySpacing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .muted(let text):
            Text(text)
                .font(.system(size: M.mutedSize))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(M.mutedSpacing)
                .lineLimit(M.mutedLines)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .mark(let ok, let text):
            markedRow(text) {
                IntactIcon(kind: ok ? .success : .error, size: M.markSize, tone: ok ? .success : .danger)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel((ok ? T("Выполнено: ", "Done: ") : T("Не выполнено: ", "Failed: ")) + text)

        case .bullet(let text):
            markedRow(text) {
                Circle()
                    .fill(Palette.textSecondary)
                    .frame(width: 5, height: 5)
                    .frame(width: M.markSize, height: M.markSize)
            }

        case .large(let text):
            Text(text)
                .font(.system(size: M.largeSize, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(M.mutedSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Строка с отметкой слева. Выравнивание по верху, а не по базовой линии:
    /// у иконки базовой линии нет, и SwiftUI ставит её низом на строку — значок
    /// висел бы выше букв. Отступ центрирует его на первой строке текста.
    private func markedRow<Mark: View>(_ text: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(alignment: .top, spacing: M.markGap) {
            mark()
                .padding(.top, Self.markTopInset)
            Text(text)
                .font(.system(size: M.bodySize))
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(M.bodySpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Низ карточки

    private func footerView(_ spec: Spec, _ footer: FooterLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(footer.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Color.clear.frame(height: M.rowGap) }
                // Внешний ряд без собственного зазора: иначе HStack вставит
                // 8 pt и после пустой распорки, ряд выйдет шире замера и
                // уедет за правый край карточки.
                HStack(spacing: 0) {
                    if index == 0, footer.hintInline, let hint = spec.hint {
                        hintView(hint)
                        Spacer(minLength: M.buttonGap)
                    } else {
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: M.buttonGap) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, button in
                            buttonView(button)
                        }
                    }
                }
                .frame(height: M.buttonHeight)
            }
            if !footer.hintInline, let hint = spec.hint {
                if !footer.rows.isEmpty { Color.clear.frame(height: M.hintGap) }
                hintView(hint)
                    .frame(height: M.hintHeight)
            }
        }
    }

    private func hintView(_ hint: Hint) -> some View {
        HStack(spacing: M.hintIconGap) {
            if let icon = hint.icon {
                IntactIcon(kind: icon, size: M.hintIconSize, weight: .medium)
            }
            Text(hint.text)
                .font(.system(size: M.hintSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(Palette.textSecondary)
    }

    /// Кнопки — те же, что у карточки «Текст готов»: они уже работают в этой
    /// панели. Главная кнопка берёт акцентную заливку общего стиля, а поля
    /// добирает до метрик `SoftButton`, чтобы пара стояла ровно.
    @ViewBuilder
    private func buttonView(_ button: CardButton) -> some View {
        Group {
            if button.prominent {
                Button { onButton(button.action) } label: {
                    HStack(spacing: 6) {
                        // Одноцветная: зелёная галочка на синей заливке спорит с ней.
                        IntactIcon(kind: button.icon, size: 13, weight: .medium, monochrome: true)
                        Text(button.title).font(.system(size: M.buttonSize, weight: .semibold))
                    }
                    .padding(.horizontal, M.buttonPad - IntactButtonSize.compact.horizontalPadding)
                }
                .buttonStyle(.intact(.accent, size: .compact))
            } else {
                SoftButton(title: button.title, icon: button.icon) { onButton(button.action) }
            }
        }
        .fixedSize()
        .accessibilityLabel(button.label)
        .accessibilityHint(button.hint ?? "")
    }
}

// MARK: - Разбор карточки

extension AssistantCardView {
    /// Кусок содержимого. Один и тот же список и рисуется, и меряется.
    fileprivate enum Block {
        /// Основной текст: ответ, черновик, вопрос, причина ошибки. Выделяется мышью.
        case text(String, markdown: Bool)
        /// Приглушённая строка: запрос, причина подтверждения. Не длиннее двух строк.
        case muted(String)
        /// Строка итога с ✓ или ✗.
        case mark(ok: Bool, String)
        /// Шаг плана на карточке подтверждения.
        case bullet(String)
        /// Подпись сработавшего таймера.
        case large(String)
    }

    fileprivate struct Hint {
        var icon: IntactIconKind? = nil
        let text: String
    }

    fileprivate struct CardButton {
        var title: String
        let icon: IntactIconKind
        let action: AssistantCardButton
        var prominent = false
        /// Подсказка VoiceOver: что именно произойдёт по клику.
        var hint: String? = nil
        /// Подпись для VoiceOver — полная, даже если на кнопке сокращённая.
        let label: String

        init(title: String, icon: IntactIconKind, action: AssistantCardButton,
             prominent: Bool = false, hint: String? = nil) {
            self.title = title
            self.icon = icon
            self.action = action
            self.prominent = prominent
            self.hint = hint
            self.label = title
        }
    }

    fileprivate struct Spec {
        var icon: IntactIconKind
        var iconTone: IconTone? = nil
        /// Не прокручивается: запрос над длинным ответом должен оставаться на виду.
        var lead: [Block] = []
        var body: [Block]
        var hint: Hint? = nil
        var buttons: [CardButton] = []
        /// Крестик в шапке. На подтверждении закрыть — значит сказать «нет»:
        /// иначе план остался бы ждать и выполнился бы от случайного «да».
        var close: AssistantCardButton = .dismiss
    }

    fileprivate static func spec(for card: AssistantCard) -> Spec {
        switch card {
        case .summary(let lines, let canUndo):
            let allOK = lines.allSatisfy(\.ok)
            return Spec(
                icon: allOK ? .success : .warning,
                iconTone: allOK ? .success : .warning,
                body: lines.map { .mark(ok: $0.ok, $0.text) },
                buttons: canUndo ? [CardButton(title: T("Отменить", "Undo"), icon: .refresh, action: .undo,
                                               hint: T("Отменить то, что сейчас сделано", "Undo what was just done"))] : []
            )

        case .answer(let query, let text, let canInsert):
            var buttons = [CardButton(title: T("Скопировать", "Copy"), icon: .copy, action: .copy,
                                      hint: T("Скопировать ответ в буфер обмена", "Copy the answer to the clipboard"))]
            if canInsert {
                buttons.append(CardButton(title: T("Вставить", "Insert"), icon: .clipboardReady, action: .insert,
                                          hint: T("Вставить ответ в поле, где стоял курсор", "Insert the answer where the cursor was")))
            }
            return Spec(icon: .aiStar,
                        lead: shownQuery(query).map { [.muted(quoted($0))] } ?? [],
                        body: [.text(text, markdown: true)],
                        buttons: buttons)

        case .confirm(let lines, let reason):
            var body: [Block] = lines.map { .bullet($0) }
            if let reason, !reason.isEmpty { body.append(.muted(reason)) }
            return Spec(
                icon: .aiStar,
                body: body,
                hint: Hint(text: T("или скажите «да» / «нет» правым ⌘", "or say “yes” / “no” with right ⌘")),
                buttons: [
                    CardButton(title: T("Отмена", "Cancel"), icon: .close, action: .reject,
                               hint: T("Ничего не выполнять", "Do nothing")),
                    CardButton(title: T("Выполнить", "Run"), icon: .success, action: .confirm, prominent: true,
                               hint: T("Выполнить план", "Run the plan")),
                ],
                close: .reject
            )

        case .clarify(let question):
            return Spec(icon: .chat,
                        body: [.text(question, markdown: false)],
                        hint: Hint(icon: .voice, text: T("Зажмите правый ⌘ и ответьте", "Hold right ⌘ and answer")))

        case .draft(_, let text):
            return Spec(icon: .chat,
                        body: [.text(text, markdown: false)],
                        hint: Hint(icon: .lock, text: T("Intact не отправляет сообщения", "Intact never sends messages")),
                        buttons: [CardButton(title: T("Скопировать", "Copy"), icon: .copy, action: .copy,
                                             hint: T("Скопировать черновик в буфер обмена", "Copy the draft to the clipboard"))])

        case .error(let message, let query, let permission):
            let query = shownQuery(query)
            var body: [Block] = [.text(message, markdown: false)]
            if let query { body.append(.muted(quoted(query))) }

            var buttons: [CardButton] = []
            if query != nil {
                buttons.append(CardButton(title: T("Скопировать запрос", "Copy request"), icon: .copy, action: .copy,
                                          hint: T("Скопировать распознанный запрос", "Copy the recognized request")))
            }
            buttons.append(CardButton(title: T("Повторить", "Retry"), icon: .refresh, action: .retry,
                                      hint: T("Отправить запрос ещё раз", "Send the request again")))
            if let permission {
                let action = permissionButton(for: permission)
                if case .grant = action {
                    buttons.append(CardButton(title: T("Разрешить", "Allow"), icon: .lock, action: action, prominent: true,
                                              hint: T("macOS спросит разрешение", "macOS will ask for permission")))
                } else {
                    var settings = CardButton(title: T("Открыть настройки", "Open Settings"), icon: .settings, action: action,
                                              prominent: true,
                                              hint: T("Открыть нужный раздел Системных настроек", "Open the right pane of System Settings"))
                    // С запросом и «Повторить» полная подпись не влезает в ряд, а
                    // второй ряд ради одной кнопки выглядит поломкой. Шестерёнка
                    // договаривает «открыть»; VoiceOver читает полную подпись.
                    if rowWidth(buttons + [settings]) > M.contentWidth {
                        settings.title = T("Настройки", "Settings")
                    }
                    buttons.append(settings)
                }
            }
            return Spec(icon: .error, iconTone: .danger, body: body, buttons: buttons)

        case .timer(let label):
            let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
            return Spec(icon: .reminder,
                        body: [.large(text.isEmpty ? T("Время вышло", "Time's up") : text)],
                        buttons: [CardButton(title: T("Остановить", "Stop"), icon: .stop, action: .stopTimer,
                                             hint: T("Выключить сигнал таймера", "Silence the timer"))])
        }
    }

    /// [Разрешить] или [Открыть настройки].
    ///
    /// Спросить macOS можно, только пока человек ещё не отвечал: после «нет»
    /// системное окно больше не появится, и честная кнопка — настройки.
    /// Календарю при доступе «только запись» тоже нужно спросить: Intact
    /// должен читать свои события, чтобы отменять и править их (0.1 п. 3).
    /// Статус EventKit — синхронный вопрос без окна. У Заметок ошибка приходит
    /// уже после ответа человека на системный вопрос, то есть после «нет».
    /// Статус уведомлений синхронно не узнать — по [Разрешить] движок сам
    /// откроет настройки, если система ответит отказом без окна.
    static func permissionButton(for permission: AssistantPermission) -> AssistantCardButton {
        switch permission {
        case .calendars:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined, .writeOnly: return .grant(permission)
            default: return .openSettings(permission)
            }
        case .reminders:
            return EKEventStore.authorizationStatus(for: .reminder) == .notDetermined
                ? .grant(permission) : .openSettings(permission)
        case .automationNotes:
            // Пока Intact не спрашивал, в списке «Автоматизации» его нет — кнопка должна
            // спросить; если система уже отказала, движок сам откроет Настройки.
            return .grant(permission)
        case .notifications:
            return .grant(permission)
        }
    }

    /// Запрос для показа: пустой и из одних пробелов — всё равно что нет,
    /// иначе на карточке остались бы пустые кавычки и [Скопировать запрос].
    private static func shownQuery(_ query: String?) -> String? {
        guard let text = query?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func quoted(_ text: String) -> String {
        T("«\(text)»", "“\(text)”")
    }

    /// Строчная разметка ответа: жирный, курсив, ссылки.
    ///
    /// Gemini отвечает markdown'ом, и звёздочки вокруг слов на карточке
    /// выглядели бы мусором. Блочную разметку не разбираем: заголовки и
    /// строки ``` просто убираем, а высоту меряем по тем буквам, что остались
    /// на экране. Код между ``` показываем как есть: разобранный как проза,
    /// он терял `__` и `*` (`__init__` превращался в жирное «init»).
    fileprivate static func inlineMarkdown(_ raw: String) -> AttributedString {
        var segments: [(code: Bool, lines: [Substring])] = []
        var inFence = false
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if segments.last?.code != inFence { segments.append((inFence, [])) }
            segments[segments.count - 1].lines.append(inFence ? line : withoutHeading(line))
        }

        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            let text = segment.lines.joined(separator: "\n")
            result.append(segment.code ? AttributedString(text) : prose(text))
        }
        let characters = result.characters
        guard let start = characters.firstIndex(where: { !$0.isWhitespace }),
              let end = characters.lastIndex(where: { !$0.isWhitespace }) else { return AttributedString() }
        return AttributedString(result[start...end])
    }

    private static func withoutHeading(_ line: Substring) -> Substring {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") else { return line }
        return line.dropFirst(hashes + 1)
    }

    private static func prose(_ text: String) -> AttributedString {
        guard let parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return AttributedString(text)
        }
        // `код` — обычным шрифтом: моноширинный шире, и замер разошёлся бы с отрисовкой.
        let plain = parsed.transformingAttributes(\.inlinePresentationIntent) { $0.value?.remove(.code) }

        // Ссылки пишет модель, а в ответ попадает и чужой текст из её поиска.
        // `[сайт банка](https://bank.example.evil)` или `[настройки](shortcuts://…)`
        // открыли бы по клику не то, что написано, в обход политики `url.open`
        // (план F.3). Поэтому кликаются только http(s), и хост всегда на виду.
        var result = AttributedString()
        for (url, range) in plain.runs[\.link] {
            var piece = AttributedString(plain[range])
            if let url {
                if let host = webHost(url) {
                    if !String(piece.characters).lowercased().contains(host) {
                        piece.append(AttributedString(" (\(host))"))
                    }
                } else {
                    piece.link = nil
                }
            }
            result.append(piece)
        }
        return result
    }

    /// Хост ссылки, по которой можно кликнуть; nil — схема не http(s).
    /// Хост в ASCII-виде: кириллический двойник «аррӏе.com» так не спрячется.
    private static func webHost(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        return host
    }
}

// MARK: - Замер

extension AssistantCardView {
    /// Метрики карточки. Поля, шапка и кнопки — как у карточки «Текст готов»
    /// (`IndicatorView.copySize`), чтобы две карточки не прыгали при смене.
    fileprivate enum M {
        static let width: CGFloat = IndicatorView.width
        static let pad: CGFloat = 16
        static let header: CGFloat = 24
        static let headerGap: CGFloat = 10
        static let footerGap: CGFloat = 14
        static let buttonHeight: CGFloat = 30
        static let rowGap: CGFloat = 8
        static let buttonGap: CGFloat = 8
        static let blockGap: CGFloat = 8
        static let lineGap: CGFloat = 6
        static let hintGap: CGFloat = 6
        static let hintHeight: CGFloat = 16
        /// Потолок панели: длинный ответ прокручивается внутри, а не растит окно
        /// на пол-экрана.
        static let maxHeight: CGFloat = 420

        static let bodySize: CGFloat = 13.5
        static let bodySpacing: CGFloat = 3.5
        static let mutedSize: CGFloat = 12
        static let mutedSpacing: CGFloat = 2
        static let mutedLines = 2
        static let largeSize: CGFloat = 17
        static let markSize: CGFloat = 13
        static let markGap: CGFloat = 8

        static let hintSize: CGFloat = 11.5
        static let hintIconSize: CGFloat = 12
        static let hintIconGap: CGFloat = 5

        static let buttonSize: CGFloat = 12.5
        /// Поля `SoftButton`: 14 по бокам, иконка 13 и зазор 6.
        static let buttonPad: CGFloat = 14
        static let buttonChrome: CGFloat = buttonPad * 2 + 13 + 6

        static var contentWidth: CGFloat { width - pad * 2 }
        static var bodyFont: NSFont { .systemFont(ofSize: bodySize) }
        static var mutedFont: NSFont { .systemFont(ofSize: mutedSize) }
        static var largeFont: NSFont { .systemFont(ofSize: largeSize, weight: .semibold) }
    }

    fileprivate struct FooterLayout {
        /// Ряды кнопок сверху вниз. Второй ряд появляется, только если кнопки
        /// не влезли в ширину (ошибка с разрешением: три длинные подписи).
        var rows: [[CardButton]]
        /// Подсказка стоит слева от кнопок; не влезла — уходит строкой ниже.
        var hintInline: Bool
        var height: CGFloat
    }

    fileprivate struct CardLayout {
        var size: CGSize
        var leadHeight: CGFloat
        var bodyHeight: CGFloat
        var scrolls: Bool
        var footer: FooterLayout?
    }

    fileprivate static func layout(for spec: Spec) -> CardLayout {
        let width = M.contentWidth
        let footer = footerLayout(spec, width: width)
        let leadHeight = stackHeight(spec.lead, width: width)

        var chrome = M.pad * 2 + M.header + M.headerGap
        if !spec.lead.isEmpty { chrome += leadHeight + M.blockGap }
        if let footer { chrome += M.footerGap + footer.height }

        let fullBody = stackHeight(spec.body, width: width)
        let room = max(M.maxHeight - chrome, 40)
        let bodyHeight = min(fullBody, room)
        return CardLayout(size: CGSize(width: M.width, height: chrome + bodyHeight),
                      leadHeight: leadHeight,
                      bodyHeight: bodyHeight,
                      scrolls: fullBody > room,
                      footer: footer)
    }

    private static func footerLayout(_ spec: Spec, width: CGFloat) -> FooterLayout? {
        guard spec.hint != nil || !spec.buttons.isEmpty else { return nil }

        // Кнопки прижаты вправо; не влезли — хвост остаётся внизу справа
        // (там главная кнопка), а начало ряда поднимается выше.
        var rows: [[CardButton]] = []
        if !spec.buttons.isEmpty {
            var split = 0
            while split < spec.buttons.count - 1, rowWidth(spec.buttons[split...]) > width { split += 1 }
            if split > 0 { rows.append(Array(spec.buttons[..<split])) }
            rows.append(Array(spec.buttons[split...]))
        }

        var hintInline = false
        if let hint = spec.hint {
            let hintWidth = (hint.icon == nil ? 0 : M.hintIconSize + M.hintIconGap)
                + textWidth(hint.text, font: .systemFont(ofSize: M.hintSize, weight: .medium))
            // Без кнопок подсказка — сама по себе строка низа (уточнение).
            if let first = rows.first {
                hintInline = hintWidth + M.buttonGap + rowWidth(first) <= width
            }
        }

        var height = CGFloat(rows.count) * M.buttonHeight + CGFloat(max(rows.count - 1, 0)) * M.rowGap
        if spec.hint != nil, !hintInline {
            height += (rows.isEmpty ? 0 : M.hintGap) + M.hintHeight
        }
        return FooterLayout(rows: rows, hintInline: hintInline, height: height)
    }

    private static func rowWidth<Row: Collection>(_ row: Row) -> CGFloat where Row.Element == CardButton {
        row.reduce(0) { $0 + buttonWidth($1) } + CGFloat(max(row.count - 1, 0)) * M.buttonGap
    }

    private static func buttonWidth(_ button: CardButton) -> CGFloat {
        M.buttonChrome + textWidth(button.title, font: .systemFont(ofSize: M.buttonSize, weight: .semibold))
    }

    private static func stackHeight(_ blocks: [Block], width: CGFloat) -> CGFloat {
        var total: CGFloat = 0
        for (index, block) in blocks.enumerated() {
            if index > 0 { total += gap(blocks[index - 1], block) }
            total += blockHeight(block, width: width)
        }
        return total
    }

    fileprivate static func gap(_ a: Block, _ b: Block) -> CGFloat {
        switch (a, b) {
        case (.mark, .mark), (.bullet, .bullet): return M.lineGap
        default: return M.blockGap
        }
    }

    private static func blockHeight(_ block: Block, width: CGFloat) -> CGFloat {
        switch block {
        case .text(let text, let markdown):
            let shown = markdown ? measured(inlineMarkdown(text))
                                 : NSAttributedString(string: text, attributes: [.font: M.bodyFont])
            return textHeight(shown, spacing: M.bodySpacing, width: width)
        case .muted(let text):
            let cap = textHeight(Array(repeating: "Ag", count: M.mutedLines).joined(separator: "\n"),
                                 font: M.mutedFont, spacing: M.mutedSpacing, width: width)
            return min(textHeight(text, font: M.mutedFont, spacing: M.mutedSpacing, width: width), cap)
        case .mark(_, let text), .bullet(let text):
            let textWidth = width - M.markSize - M.markGap
            return max(textHeight(text, font: M.bodyFont, spacing: M.bodySpacing, width: textWidth),
                       M.markSize + markTopInset)
        case .large(let text):
            return textHeight(text, font: M.largeFont, spacing: M.mutedSpacing, width: width)
        }
    }

    /// Высота текста с тем же межстрочным интервалом, что у `Text.lineSpacing`.
    /// Замер без интервала (как было в `IndicatorView.textHeight`) занижает
    /// высоту на интервал с каждой строки, и низ длинного текста подрезался.
    private static func textHeight(_ text: String, font: NSFont, spacing: CGFloat, width: CGFloat) -> CGFloat {
        textHeight(NSAttributedString(string: text, attributes: [.font: font]), spacing: spacing, width: width)
    }

    private static func textHeight(_ text: NSAttributedString, spacing: CGFloat, width: CGFloat) -> CGFloat {
        guard text.length > 0 else { return 0 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = spacing
        paragraph.lineBreakMode = .byWordWrapping
        let styled = NSMutableAttributedString(attributedString: text)
        styled.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: styled.length))
        let box = styled.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(box.height)
    }

    /// Ответ для замера — теми же начертаниями, что на экране. Жирный шире
    /// обычного, курсив уже: замер по голым буквам терял строку внизу
    /// жирного ответа (её было не видно без прокрутки) или добавлял пустую.
    private static func measured(_ text: AttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (intent, range) in text.runs[\.inlinePresentationIntent] {
            var font = intent?.contains(.stronglyEmphasized) == true
                ? NSFont.systemFont(ofSize: M.bodySize, weight: .bold) : M.bodyFont
            if intent?.contains(.emphasized) == true {
                font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: M.bodySize) ?? font
            }
            result.append(NSAttributedString(string: String(text[range].characters), attributes: [.font: font]))
        }
        return result
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Отступ отметки сверху: центр значка на центре первой строки.
    fileprivate static var markTopInset: CGFloat {
        let font = M.bodyFont
        let line = font.ascender - font.descender + font.leading
        return max(0, ((line - M.markSize) / 2).rounded())
    }
}
