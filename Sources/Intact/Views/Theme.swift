import AppKit
import SwiftUI

/// Палитра и дизайн-система приложения Intact с поддержкой тем:
/// - Белая (Классика macOS — по умолчанию)
/// - Тёплая терракотовая (Oatmeal & Terracotta)
/// - Тёмная (Оникс / Мокка)
/// - Системная (Следование за macOS)
enum Palette {
    // Основные фоны
    static var page: Color           { dynamic(white: (0.970, 0.972, 0.976), terracotta: (0.980, 0.965, 0.941), dark: (0.086, 0.082, 0.078)) }
    static var sidebar: Color        { dynamic(white: (0.935, 0.940, 0.945), terracotta: (0.949, 0.922, 0.878), dark: (0.118, 0.114, 0.110)) }
    static var card: Color           { dynamic(white: (1.000, 1.000, 1.000), terracotta: (0.996, 0.992, 0.984), dark: (0.145, 0.141, 0.137)) }
    static var cardHighlight: Color  { dynamic(white: (0.945, 0.950, 0.955), terracotta: (0.957, 0.925, 0.882), dark: (0.185, 0.180, 0.175)) }
    static var pill: Color           { dynamic(white: (0.915, 0.922, 0.930), terracotta: (0.929, 0.898, 0.847), dark: (0.205, 0.200, 0.192)) }
    static var pillHover: Color      { dynamic(white: (0.870, 0.880, 0.895), terracotta: (0.894, 0.855, 0.796), dark: (0.260, 0.252, 0.245)) }
    static var dropdownBg: Color     { dynamic(white: (1.000, 1.000, 1.000), terracotta: (0.996, 0.992, 0.984), dark: (0.170, 0.165, 0.160)) }

    // Акценты
    static var accent: Color         { dynamic(white: (0.180, 0.480, 0.920), terracotta: (0.780, 0.435, 0.318), dark: (0.900, 0.580, 0.460)) }
    static var accentHover: Color    { dynamic(white: (0.140, 0.420, 0.840), terracotta: (0.720, 0.375, 0.260), dark: (0.940, 0.640, 0.520)) }

    // Иконки: нейтральные роли
    static var iconIdle: Color       { textSecondary }
    static var iconMuted: Color      { textTertiary }

    // Иконки: статусные роли.
    // Цвет несёт состояние, а не украшает. В терракотовой теме статусы
    // намеренно пригашены и уведены в тёплый — чистый зелёный на кремовом
    // фоне выглядит инородно.
    static var iconSuccess: Color    { dynamic(white: (0.145, 0.620, 0.400), terracotta: (0.345, 0.545, 0.365), dark: (0.400, 0.800, 0.560)) }
    static var iconWarning: Color    { dynamic(white: (0.870, 0.600, 0.130), terracotta: (0.820, 0.580, 0.220), dark: (0.965, 0.755, 0.360)) }
    static var iconDanger: Color     { dynamic(white: (0.840, 0.290, 0.270), terracotta: (0.760, 0.290, 0.240), dark: (0.940, 0.460, 0.420)) }
    static var iconProcess: Color    { dynamic(white: (0.310, 0.400, 0.900), terracotta: (0.490, 0.435, 0.690), dark: (0.620, 0.640, 0.960)) }

    // Типографика
    static var textPrimary: Color    { dynamic(white: (0.100, 0.110, 0.120), terracotta: (0.133, 0.110, 0.094), dark: (0.975, 0.968, 0.952)) }
    static var textSecondary: Color  { dynamic(white: (0.420, 0.450, 0.490), terracotta: (0.459, 0.416, 0.365), dark: (0.680, 0.665, 0.640)) }
    static var textTertiary: Color   { dynamic(white: (0.600, 0.630, 0.670), terracotta: (0.620, 0.576, 0.522), dark: (0.480, 0.465, 0.445)) }

    // Разделители и состояния
    static var hairline: Color       { dynamicAlpha(white: (0, 0, 0, 0.075), terracotta: (0.50, 0.40, 0.30, 0.14), dark: (1, 1, 1, 0.08)) }
    static var selected: Color       { dynamicAlpha(white: (0, 0, 0, 0.065), terracotta: (0.780, 0.435, 0.318, 0.12), dark: (1, 1, 1, 0.10)) }
    static var hover: Color          { dynamicAlpha(white: (0, 0, 0, 0.035), terracotta: (0.50, 0.40, 0.30, 0.06), dark: (1, 1, 1, 0.055)) }

    // Переключатели
    static var toggleOn: Color       { dynamic(white: (0.120, 0.120, 0.130), terracotta: (0.780, 0.435, 0.318), dark: (0.880, 0.550, 0.430)) }
    static var toggleOff: Color      { dynamic(white: (0.850, 0.860, 0.880), terracotta: (0.860, 0.825, 0.780), dark: (0.245, 0.240, 0.230)) }
    static var toggleKnob: Color     { dynamic(white: (1.000, 1.000, 1.000), terracotta: (1.000, 1.000, 1.000), dark: (0.110, 0.105, 0.100)) }

    // HUD Pill (плавающий мини-индикатор записи и тосты)
    static func hudBg(theme: AppTheme) -> Color {
        switch theme {
        case .white:
            return Color.white.opacity(0.96)
        case .terracotta:
            return Color(red: 0.957, green: 0.925, blue: 0.882).opacity(0.96)
        case .dark:
            return Color(red: 0.095, green: 0.090, blue: 0.086).opacity(0.94)
        case .system:
            return AppSettings.shared.isDarkMode ? Color(red: 0.095, green: 0.090, blue: 0.086).opacity(0.94) : Color.white.opacity(0.96)
        }
    }

    static func hudBorder(theme: AppTheme) -> Color {
        switch theme {
        case .white:
            return Color.black.opacity(0.10)
        case .terracotta:
            return Color(red: 0.50, green: 0.40, blue: 0.30).opacity(0.18)
        case .dark:
            return Color.white.opacity(0.14)
        case .system:
            return AppSettings.shared.isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
        }
    }

    static func hudShadow(theme: AppTheme) -> Color {
        switch theme {
        case .white:
            return Color.black.opacity(0.12)
        case .terracotta:
            return Color(red: 0.35, green: 0.25, blue: 0.15).opacity(0.14)
        case .dark:
            return Color.black.opacity(0.40)
        case .system:
            return AppSettings.shared.isDarkMode ? Color.black.opacity(0.40) : Color.black.opacity(0.12)
        }
    }

    static func hudIcon(theme: AppTheme) -> Color {
        switch theme {
        case .white:
            return Color(red: 0.180, green: 0.480, blue: 0.920)
        case .terracotta:
            return Color(red: 0.780, green: 0.435, blue: 0.318)
        case .dark:
            return Color(red: 0.98, green: 0.95, blue: 0.91)
        case .system:
            return AppSettings.shared.isDarkMode ? Color(red: 0.98, green: 0.95, blue: 0.91) : Color(red: 0.180, green: 0.480, blue: 0.920)
        }
    }

    static func hudText(theme: AppTheme) -> Color {
        switch theme {
        case .white:
            return Color(red: 0.100, green: 0.110, blue: 0.120)
        case .terracotta:
            return Color(red: 0.133, green: 0.110, blue: 0.094)
        case .dark:
            return Color(red: 0.98, green: 0.95, blue: 0.91)
        case .system:
            return AppSettings.shared.isDarkMode ? Color(red: 0.98, green: 0.95, blue: 0.91) : Color(red: 0.100, green: 0.110, blue: 0.120)
        }
    }

    static func hudTextMuted(theme: AppTheme) -> Color {
        switch theme {
        case .white:
            return Color(red: 0.420, green: 0.450, blue: 0.490)
        case .terracotta:
            return Color(red: 0.459, green: 0.416, blue: 0.365)
        case .dark:
            return Color(red: 0.80, green: 0.76, blue: 0.72)
        case .system:
            return AppSettings.shared.isDarkMode ? Color(red: 0.80, green: 0.76, blue: 0.72) : Color(red: 0.420, green: 0.450, blue: 0.490)
        }
    }

    static func hudEqTop(theme: AppTheme) -> Color {
        switch theme {
        case .white:
            return Color(red: 0.20, green: 0.45, blue: 0.90)
        case .terracotta:
            return Color(red: 0.780, green: 0.435, blue: 0.318)
        case .dark:
            return Color(red: 0.98, green: 0.94, blue: 0.90)
        case .system:
            return AppSettings.shared.isDarkMode ? Color(red: 0.98, green: 0.94, blue: 0.90) : Color(red: 0.20, green: 0.45, blue: 0.90)
        }
    }

    static func hudEqBottom(theme: AppTheme) -> Color {
        switch theme {
        case .white:
            return Color(red: 0.45, green: 0.65, blue: 0.95)
        case .terracotta:
            return Color(red: 0.900, green: 0.580, blue: 0.460)
        case .dark:
            return Color(red: 0.86, green: 0.62, blue: 0.49)
        case .system:
            return AppSettings.shared.isDarkMode ? Color(red: 0.86, green: 0.62, blue: 0.49) : Color(red: 0.45, green: 0.65, blue: 0.95)
        }
    }

    private static func dynamic(
        white: (CGFloat, CGFloat, CGFloat),
        terracotta: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        dynamicAlpha(
            white: (white.0, white.1, white.2, 1),
            terracotta: (terracotta.0, terracotta.1, terracotta.2, 1),
            dark: (dark.0, dark.1, dark.2, 1)
        )
    }

    private static func dynamicAlpha(
        white: (CGFloat, CGFloat, CGFloat, CGFloat),
        terracotta: (CGFloat, CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> Color {
        let theme = AppSettings.shared.appTheme
        let chosen: (CGFloat, CGFloat, CGFloat, CGFloat)
        switch theme {
        case .dark:
            chosen = dark
        case .terracotta:
            chosen = terracotta
        case .white:
            chosen = white
        case .system:
            chosen = AppSettings.shared.isDarkMode ? dark : white
        }
        return Color(red: Double(chosen.0), green: Double(chosen.1), blue: Double(chosen.2)).opacity(Double(chosen.3))
    }
}

/// Кастомный минималистичный переключатель в стиле Wispr Flow.
struct WisprToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    configuration.isOn.toggle()
                }
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(configuration.isOn ? Palette.toggleOn : Palette.toggleOff)
                        .frame(width: 44, height: 26)

                    Circle()
                        .fill(Palette.toggleKnob)
                        .frame(width: 20, height: 20)
                        .padding(3)
                        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// Страница раздела: крупный заголовок с засечками и прокручиваемое содержимое.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ContentColumn {
                Text(title)
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.top, 46)
            .padding(.bottom, 24)

            ScrollView {
                ContentColumn {
                    VStack(alignment: .leading, spacing: 28) {
                        content
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.page)
    }
}

/// Карточка с заголовком: мягкий фон, скругленные углы, разделители-волоски.
struct Card<Content: View>: View {
    var header: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header {
                Text(header.uppercased())
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.35, green: 0.25, blue: 0.15).opacity(0.035), radius: 6, y: 2)
            )
        }
    }
}

/// Строка карточки: название, пояснение под ним, управляющий элемент справа.
struct Row<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var first: Bool = false
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .padding(.leading, 22)
            }
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 16)
                control
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
    }
}

/// Кнопка-таблетка в правой части строки.
///
/// Иконка принимается только как `IntactIconKind` — строковых имён SF Symbols
/// тут больше нет, поэтому стоковую иконку в интерфейс не пронести незаметно.
struct PillButton: View {
    let title: String
    var icon: IntactIconKind? = nil
    /// Семантика действия: `.danger` для удаления, `.success` для подтверждения.
    var tone: IconTone? = nil
    var action: () -> Void
    @State private var hovering = false

    private var labelColor: Color { tone?.color ?? Palette.textPrimary }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    IntactIcon(kind: icon, size: 13, tone: tone)
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Palette.pillHover : Palette.pill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Бейдж горячей клавиши (например, ⌥ Opt, ⌘V).
struct KeyCapBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.pill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
            )
    }
}

/// Элегантный кастомный выпадающий список в стиле современной дизайн-системы Intact:
/// - Кнопка-триггер с текущим значением и векторным шевроном.
/// - Плавающий поповер со списком элементов, увеличенными отступами,
///   выделением выбранного элемента галочкой слева, плавным ховером и отличной читаемостью.
struct WisprDropdown<T: Hashable, Label: View>: View {
    @Binding var selection: T
    let options: [T]
    @ViewBuilder let label: (T) -> Label
    @State private var isOpen = false
    @State private var hovering = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                label(selection)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)

                IntactIcon(kind: isOpen ? .chevronUp : .chevronDown, size: 8)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7.5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Palette.pillHover : Palette.dropdownBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(options, id: \.self) { item in
                    let isSelected = item == selection
                    WisprDropdownItemRow(
                        isSelected: isSelected,
                        action: {
                            selection = item
                            isOpen = false
                        }
                    ) {
                        label(item)
                    }
                }
            }
            .padding(6)
            .frame(minWidth: 200)
            .background(Palette.card)
        }
    }
}

struct WisprDropdownItemRow<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                // Чекмарк слева
                ZStack {
                    if isSelected {
                        IntactIcon(kind: .copied, size: 12)
                            .foregroundStyle(Palette.accent)
                    }
                }
                .frame(width: 14, height: 14)

                content()
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Palette.hover : (isSelected ? Palette.accent.opacity(0.08) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Ползунок в правой части строки — с аккуратной подписью значения.
struct SliderControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let caption: String

    var body: some View {
        HStack(spacing: 12) {
            Slider(value: $value, in: range, step: step)
                .frame(width: 170)
                .tint(Palette.toggleOn)
            Text(caption)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 58, alignment: .trailing)
        }
    }
}

/// Выпадающий список выбора языка с быстрым многоязычным поиском (без флагов)
struct SearchableLanguageDropdown: View {
    @Binding var selection: String
    @State private var isOpen = false
    @State private var search = ""
    @State private var hovering = false
    @FocusState private var isSearchFocused: Bool

    private var currentLanguage: Language {
        Language.find(code: selection)
    }

    private var filteredLanguages: [Language] {
        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Language.all
        }
        return Language.all.filter { $0.matches(query: search) }
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(currentLanguage.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)

                Text(currentLanguage.code.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Palette.pill)
                    )

                IntactIcon(kind: isOpen ? .chevronUp : .chevronDown, size: 8)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7.5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Palette.pillHover : Palette.dropdownBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                // Поле поиска с иконкой
                HStack(spacing: 8) {
                    IntactIcon(kind: .search, size: 13)
                        .foregroundStyle(Palette.textSecondary)

                    TextField("Поиск: русский, english, de, fr...", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isSearchFocused)

                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            IntactIcon(kind: .close, size: 10)
                                .foregroundStyle(Palette.textTertiary)
                                .padding(2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.pill)

                Divider()
                    .overlay(Palette.hairline)

                // Список языков
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if filteredLanguages.isEmpty {
                            Text("Язык не найден")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            if search.isEmpty {
                                Text("Часто используемые")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.textTertiary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)

                                ForEach(Language.popular) { lang in
                                    languageRow(lang)
                                }

                                Text("Все языки (\(Language.all.count))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.textTertiary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                            }

                            ForEach(filteredLanguages) { lang in
                                languageRow(lang)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(width: 320, height: 260)
            }
            .background(Palette.card)
            .onAppear {
                isSearchFocused = true
            }
        }
    }

    private func languageRow(_ lang: Language) -> some View {
        let isSelected = lang.code == selection
        return Button {
            selection = lang.code
            isOpen = false
            search = ""
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    if isSelected {
                        IntactIcon(kind: .copied, size: 12)
                            .foregroundStyle(Palette.accent)
                    }
                }
                .frame(width: 14, height: 14)

                Text(lang.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Palette.textPrimary)

                Spacer()

                Text(lang.code.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(Palette.pill)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7.5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Palette.accent.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}

/// Ряд удаляемых меток, переносящийся по строкам.
///
/// Нужен там, где список короткий и растёт по одному элементу — например,
/// словарь терминов диктовки. `LazyVGrid` тут не подходит: ширина меток
/// разная, а фиксированная сетка оставляет дыры.
struct FlowTags: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        TagFlowLayout(spacing: 7) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    Text(item)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textPrimary)
                    Button { onRemove(item) } label: {
                        IntactIcon(kind: .close, size: 9)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Убрать «\(item)» из словаря")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Palette.pill))
            }
        }
    }
}

/// Простая раскладка «в строку с переносом».
///
/// Имя с префиксом Tag — в проекте уже есть свой `enum Layout` с ширинами
/// колонок, и `struct X: Layout` разрешался бы в него, а не в протокол SwiftUI.
struct TagFlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
