import SwiftUI

/// Выбор модели прямо в том разделе, где с ней работают.
///
/// Раньше выбор был один на всё приложение и жил в настройках. Здесь он
/// привязан к роли: у чата может быть Opus, у причёсывания диктовки —
/// локальная 2B, и переключаются они независимо, не уходя со страницы.
/// Без `role` компонент показывает общий выбор по умолчанию.
struct AIModelPicker: View {
    /// Роль, для которой выбирается модель. `nil` — общая настройка.
    var role: AIRole? = nil
    /// Компактный вид: только название, без пилюли «Облако/Локально».
    var compact: Bool = false
    var onOpenSettings: () -> Void
    var onOpenModels: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var llmModels = LLMModelManager.shared
    @State private var isOpen = false
    @State private var hovering = false
    /// Выбор, ждущий подтверждения «да, я понимаю, что текст уйдёт наружу».
    @State private var pendingCloudChoice: AIModelChoice? = nil

    private var current: AIModelChoice {
        role.map { AIModelCatalog.resolved(for: $0) } ?? AIModelCatalog.current
    }

    /// Роль работает на общей настройке, а не на собственной.
    private var inherits: Bool {
        guard let role else { return false }
        return !AIModelCatalog.hasOverride(role)
    }

    private var cloudReady: Bool { CloudAIProvider.shared.isReady }

    private var statusColor: Color {
        switch current {
        case .disabled:
            return Palette.iconMuted
        case .local:
            return LocalAIProvider.shared.isAvailable ? Palette.iconSuccess : Palette.iconWarning
        case .cloud:
            return cloudReady ? Palette.iconSuccess : Palette.iconWarning
        }
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(AIModelCatalog.title(for: current))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)

                if !compact, let placement = AIModelCatalog.placement(for: current) {
                    Text(placement)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Palette.pill))
                }

                IntactIcon(kind: isOpen ? .chevronUp : .chevronDown, size: 8)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering || isOpen ? Palette.pillHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(role.map { T("Модель для раздела «\($0.title)»", "Model for “\($0.title)”") } ?? T("Сменить версию ИИ", "Change AI model"))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { picker }
        .alert(T("Текст будет уходить в облако", "Text will be sent to the cloud"),
               isPresented: Binding(get: { pendingCloudChoice != nil },
                                    set: { if !$0 { pendingCloudChoice = nil } })) {
            Button(T("Отмена", "Cancel"), role: .cancel) { pendingCloudChoice = nil }
            Button(T("Понимаю, включить", "I understand, enable")) {
                if let choice = pendingCloudChoice {
                    settings.cloudConsentGiven = true
                    commit(choice)
                }
                pendingCloudChoice = nil
            }
        } message: {
            Text(T("С локальной моделью звук и текст не покидают этот Mac. ", "With a local model, audio and text never leave this Mac. ")
                 + T("Облачная модель работает иначе: распознанный текст, а в чате — ещё ", "A cloud model works differently: the recognised text — and in chat also ")
                 + T("и заметки, напоминания и содержимое прикреплённых файлов ", "your notes, reminders and the contents of attached files — ")
                 + T("отправляются на серверы Anthropic.\n\n", "are sent to Anthropic's servers.\n\n")
                 + T("Спрашиваем один раз. Вернуться к локальной модели можно в любой момент.", "Asked once. You can switch back to a local model at any time."))
        }
    }

    /// Применяет выбор — к роли или к общей настройке.
    private func commit(_ choice: AIModelChoice) {
        if let role {
            AIModelCatalog.apply(choice, to: role)
        } else {
            AIModelCatalog.apply(choice)
        }
    }

    // MARK: - Список

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let role {
                    sectionHeader(T("Модель для: \(role.title)", "Model for: \(role.title)"))
                    inheritRow(role)
                    Divider().overlay(Palette.hairline).padding(.vertical, 3)
                }

                localSection
                cloudSection

                Divider().overlay(Palette.hairline).padding(.vertical, 3)

                row(choice: .disabled, title: T("Выключить ИИ", "Turn AI off"),
                    subtitle: T("Диктовка продолжит работать", "Dictation keeps working"), enabled: true)
            }
            .padding(7)
        }
        .frame(width: 372)
        .frame(maxHeight: 460)
        .background(Palette.card)
    }

    @ViewBuilder
    private var localSection: some View {
        let installed = llmModels.installedPairs

        sectionHeader(T("Локально · не покидает Mac", "Local · never leaves this Mac"))
        if installed.isEmpty {
            hint(T("Ни одна локальная модель не установлена", "No local model installed")) { onOpenModels() }
        } else {
            ForEach(installed, id: \.quant.filename) { pair in
                row(choice: .local(pair.quant.filename),
                    title: pair.model.title,
                    subtitle: "\(pair.quant.quant) · \(sizeText(pair.quant.sizeMB)) · \(tierText(pair.model.tier))"
                        + (pair.model.reasons ? T(" · рассуждает", " · reasons") : ""),
                    enabled: LocalAIProvider.shared.isAvailable)
            }
            if !LocalAIProvider.shared.isAvailable {
                hint(T("Нужен llama-server: brew install llama.cpp", "Needs llama-server: brew install llama.cpp")) { onOpenSettings() }
            }
        }
    }

    @ViewBuilder
    private var cloudSection: some View {
        sectionHeader(T("Облако Anthropic", "Anthropic cloud"))
        ForEach(AIModelCatalog.cloud) { model in
            row(choice: .cloud(model.id),
                title: model.title,
                subtitle: model.note,
                footnote: "\(model.contextText) · \(model.priceText)",
                enabled: cloudReady)
        }
        if !cloudReady {
            hint(T("Нужен ключ Anthropic API", "Needs an Anthropic API key")) { onOpenSettings() }
        }
    }

    /// Строка «как в основных настройках»: без неё роль, однажды переключённая
    /// вручную, уже никогда не вернулась бы к общему выбору.
    private func inheritRow(_ role: AIRole) -> some View {
        WisprDropdownItemRow(
            isSelected: inherits,
            action: {
                AIModelCatalog.apply(nil, to: role)
                isOpen = false
            }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(T("Как в основных настройках", "Same as main settings"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text(T("Сейчас это \(AIModelCatalog.title(for: AIModelCatalog.current))", "Currently \(AIModelCatalog.title(for: AIModelCatalog.current))"))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func row(choice: AIModelChoice, title: String, subtitle: String,
                     footnote: String? = nil, enabled: Bool) -> some View {
        WisprDropdownItemRow(
            isSelected: current == choice && !inherits,
            action: {
                guard enabled else { return }
                isOpen = false
                // Переход на облако — это изменение того, что происходит
                // с текстом пользователя. Один раз об этом стоит спросить.
                if case .cloud = choice, !settings.cloudConsentGiven {
                    pendingCloudChoice = choice
                    return
                }
                commit(choice)
            }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(enabled ? Palette.textPrimary : Palette.iconMuted)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let footnote {
                    Text(footnote)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary.opacity(0.85))
                }
            }
        }
        .opacity(enabled ? 1 : 0.5)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.textTertiary)
            .kerning(0.6)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func hint(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                IntactIcon(kind: .warning, size: 13)
                Text(text)
                    .font(.system(size: 11.5))
                Spacer(minLength: 0)
                IntactIcon(kind: .chevronRight, size: 9)
            }
            .foregroundStyle(Palette.iconWarning)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sizeText(_ mb: Int) -> String {
        mb >= 1000 ? String(format: T("%.1f ГБ", "%.1f GB"), Double(mb) / 1000.0) : T("\(mb) МБ", "\(mb) MB")
    }

    private func tierText(_ tier: LLMTier) -> String {
        switch tier {
        case .light:  return T("лёгкая", "light")
        case .large:  return T("крупная", "large")
        case .xlarge: return T("очень крупная", "very large")
        }
    }
}

/// Строка настроек «какая модель отвечает за эту задачу» — с выбором прямо тут.
/// Используется в разделах «Диктовка», «Спросите ИИ» и в общих настройках.
struct AIRoleRow: View {
    let role: AIRole
    var first: Bool = false
    var onOpenSettings: () -> Void
    var onOpenModels: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    private var choice: AIModelChoice { AIModelCatalog.resolved(for: role) }

    /// Честное предупреждение вместо молчания: роль настроена, но работать
    /// не будет — ключа нет, сервер не установлен или модель выключена.
    private var problem: String? {
        switch choice {
        case .disabled:
            return T("ИИ выключен — задача выполняться не будет", "AI is off — this task will not run")
        case .cloud:
            return CloudAIProvider.shared.isReady ? nil : T("Нужен ключ Anthropic API в настройках", "Needs an Anthropic API key in Settings")
        case .local:
            return LocalAIProvider.shared.isAvailable ? nil : T("Не найден llama-server: brew install llama.cpp", "llama-server not found: brew install llama.cpp")
        }
    }

    /// Куда уходит текст этой задачи. Слова «Облако» в маленькой пилюле
    /// недостаточно: приложение обещает приватность, и место, где это
    /// обещание перестаёт действовать, должно называться прямо.
    private var privacy: (text: String, cloud: Bool)? {
        switch choice {
        case .disabled: return nil
        case .local:    return (T("Не покидает этот Mac", "Never leaves this Mac"), false)
        case .cloud:    return (T("Текст этой задачи отправляется в облако Anthropic", "Text from this task is sent to the Anthropic cloud"), true)
        }
    }

    var body: some View {
        Row(title: role.title,
            subtitle: problem ?? role.subtitle,
            first: first) {
            VStack(alignment: .trailing, spacing: 6) {
                AIModelPicker(role: role,
                              onOpenSettings: onOpenSettings,
                              onOpenModels: onOpenModels)
                if let privacy {
                    HStack(spacing: 5) {
                        IntactIcon(kind: .lock, size: 11)
                        Text(privacy.text)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(privacy.cloud ? Palette.iconWarning : Palette.textTertiary)
                }
            }
        }
    }
}
