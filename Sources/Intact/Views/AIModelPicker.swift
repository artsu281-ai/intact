import SwiftUI

/// Компактная выпадайка смены модели ИИ для шапки карточки или раздела.
struct AIModelPicker: View {
    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

    var role: AIRole? = nil
    var compact: Bool = false
    /// Скруглённый прямоугольник с обводкой, как у соседних плашек шапки чата.
    var outlined: Bool = false
    var onOpenSettings: () -> Void = {}
    var onOpenModels: () -> Void = {}

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var llmModels = LLMModelManager.shared
    @State private var isOpen = false
    @State private var hovering = false

    private var current: AIModelChoice {
        role.map { AIModelCatalog.resolved(for: $0) } ?? AIModelCatalog.current
    }

    /// Роль работает на общей настройке, а не на собственной.
    private var inherits: Bool {
        guard let role else { return false }
        return !AIModelCatalog.hasOverride(role)
    }

    private var statusColor: Color {
        switch current {
        case .disabled:
            return Palette.iconMuted
        case .gemini:
            return GeminiBridgeService.shared.isInstalled ? Palette.iconSuccess : Palette.iconWarning
        case .local:
            return LocalAIProvider.shared.isAvailable ? Palette.iconSuccess : Palette.iconWarning
        }
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                // Единственный элемент шапки, которому позволено сжиматься:
                // название модели усекается многоточием, всё остальное рядом
                // стоит на `fixedSize`. Кто-то сжиматься обязан — суммарная
                // ширина шапки больше, чем окно даёт в узком состоянии.
                Text(AIModelCatalog.title(for: current))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !compact, let placement = AIModelCatalog.placement(for: current) {
                    // Без `lineLimit` этот бейдж разрывался ПОСРЕДИ СЛОВА:
                    // «Приложение» складывалось в капсуле в четыре строки по
                    // слогам — «При / ило / же / ние». У названия модели строкой
                    // выше ограничение стояло, у бейджа его забыли.
                    Text(placement)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
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
                Group {
                    if outlined {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(hovering || isOpen ? Palette.pillHover : Palette.pill)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(hovering || isOpen ? Palette.pillHover : Color.clear)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(role.map { T("Модель для раздела «\($0.title)»", "Model for “\($0.title)”") } ?? T("Сменить версию ИИ", "Change AI model"))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { picker }
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

                appsSection
                localSection

                Divider().overlay(Palette.hairline).padding(.vertical, 3)

                row(choice: .disabled, title: T("Выключить ИИ", "Turn AI off"),
                    subtitle: T("Диктовка продолжит работать", "Dictation keeps working"), enabled: true)
            }
            .padding(7)
        }
        .frame(width: 372)
        .frame(maxHeight: 450)
        .background(Palette.card)
    }

    @ViewBuilder
    private var appsSection: some View {
        sectionHeader(T("Десктопное приложение", "Desktop Application"))
        row(
            choice: .gemini,
            title: "Gemini.app (macOS)",
            subtitle: GeminiBridgeService.shared.isInstalled
                ? T("Официальное приложение Gemini на вашем Mac (работает в фоне)", "Official Gemini app on your Mac (runs in background)")
                : T("Приложение Gemini не найдено в /Applications", "Gemini app not found in /Applications"),
            footnote: T("100% бесплатно · без API ключей · через Accessibility API", "100% free · no API keys · via Accessibility API"),
            enabled: GeminiBridgeService.shared.isInstalled
        )
        if !GeminiBridgeService.shared.isInstalled {
            hint(T("Установите приложение Gemini в /Applications", "Install the Gemini app in /Applications")) { onOpenSettings() }
        }
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

    private func row(choice: AIModelChoice,
                     title: String,
                     subtitle: String? = nil,
                     footnote: String? = nil,
                     enabled: Bool = true) -> some View {
        let isSelected = !inherits && current == choice
        return WisprDropdownItemRow(
            isSelected: isSelected,
            action: {
                guard enabled else { return }
                commit(choice)
                isOpen = false
            }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(enabled ? Palette.textPrimary : Palette.textTertiary)

                    if let placement = AIModelCatalog.placement(for: choice) {
                        Text(placement)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Palette.pill))
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }

                if let footnote {
                    Text(footnote)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .opacity(enabled ? 1.0 : 0.55)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.textTertiary)
            .kerning(0.5)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func hint(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            isOpen = false
            action()
        }) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.accent)
                Spacer()
                Text("→")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func sizeText(_ mb: Int) -> String {
        mb >= 1000
            ? String(format: "%.1f ГБ", Double(mb) / 1024.0)
            : "\(mb) МБ"
    }

    private func tierText(_ tier: LLMTier) -> String {
        switch tier {
        case .xlarge: return T("флагман", "flagship")
        case .large:  return T("баланс", "balanced")
        case .light:  return T("лёгкая", "compact")
        }
    }
}

/// Строка настроек «какая модель отвечает за эту задачу» — с выбором прямо тут.
/// Используется в разделах «Диктовка», «Спросите ИИ» и в общих настройках.
struct AIRoleRow: View {
    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

    let role: AIRole
    var first: Bool = false
    var onOpenSettings: () -> Void
    var onOpenModels: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    private var choice: AIModelChoice { AIModelCatalog.resolved(for: role) }

    /// Честное предупреждение вместо молчания: роль настроена, но работать
    /// не будет — приложение не запущено или модель не установлена.
    private var problem: String? {
        switch choice {
        case .disabled:
            return T("ИИ выключен — задача выполняться не будет", "AI is off — this task will not run")
        case .gemini:
            return GeminiBridgeService.shared.isInstalled ? nil : T("Приложение Gemini не найдено в /Applications", "Gemini app not found in /Applications")
        case .local:
            return LocalAIProvider.shared.isAvailable ? nil : T("Не найден llama-server: brew install llama.cpp", "llama-server not found: brew install llama.cpp")
        }
    }

    private var privacy: String? {
        switch choice {
        case .disabled: return nil
        case .gemini:   return T("Передаётся в приложение Gemini на вашем Mac", "Forwarded to Gemini app on your Mac")
        case .local:    return T("Не покидает этот Mac (0 токенов, офлайн)", "Never leaves this Mac (0 tokens, offline)")
        }
    }

    var body: some View {
        Row(title: role.title,
            subtitle: problem ?? role.subtitle,
            first: first) {
            VStack(alignment: .trailing, spacing: 6) {
                AIModelPicker(role: role,
                              outlined: true,
                              onOpenSettings: onOpenSettings,
                              onOpenModels: onOpenModels)
                if let privacy {
                    HStack(spacing: 5) {
                        IntactIcon(kind: .lock, size: 11)
                        Text(privacy)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }
}
