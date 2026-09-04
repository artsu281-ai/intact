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
    /// Наведение. Плотнее прежнего в светлых темах и слабее в тёмной:
    /// раньше шаг над плашкой был −2.89 / −2.62 / +5.05 ΔL*, то есть в белой
    /// и терракотовой наведение почти не читалось, а в тёмной было вдвое
    /// громче. Стало −3.97 / −3.95 / +3.69. Пара к `pressed` ниже.
    static var hover: Color          { dynamicAlpha(white: (0, 0, 0, 0.048), terracotta: (0.36, 0.26, 0.16, 0.070), dark: (1, 1, 1, 0.040)) }

    // Переключатели
    static var toggleOn: Color       { dynamic(white: (0.120, 0.120, 0.130), terracotta: (0.780, 0.435, 0.318), dark: (0.880, 0.550, 0.430)) }
    static var toggleOff: Color      { dynamic(white: (0.850, 0.860, 0.880), terracotta: (0.860, 0.825, 0.780), dark: (0.245, 0.240, 0.230)) }
    static var toggleKnob: Color     { dynamic(white: (1.000, 1.000, 1.000), terracotta: (1.000, 1.000, 1.000), dark: (0.110, 0.105, 0.100)) }

    // MARK: - Состояния контролов
    //
    // Наведение и нажатие — одна лестница на всё приложение: сначала `hover`,
    // затем вдвое плотнее `pressed`. До этого нажатия не существовало вовсе:
    // `isPressed` не встречался в проекте ни разу, все 63 кнопки стояли на
    // `.buttonStyle(.plain)`.
    //
    // Числа подобраны так, чтобы шаг читался в каждой из трёх тем. Величина
    // шага зависит от того, на чём лежит вуаль, и одинаковой на всех
    // поверхностях она не бывает: над `pill` (плашка кнопки) новый `hover`
    // даёт ΔL* −3.97 / −3.95 / +3.69, `pressed` — −6.47 / −6.50 / +6.22.
    // Над `sidebar` те же вуали дают −4.03 / −4.08 / +4.40 и
    // −6.57 / −6.72 / +7.39. Прежний `hover` давал над `pill` всего
    // −2.89 / −2.62 / +5.05 — в светлых темах наведение было почти незаметным.

    /// Нажатие. Плотнее `hover` примерно вдвое: разница между «курсор здесь»
    /// и «палец нажал» должна читаться, не сливаясь с наведением.
    static var pressed: Color        { dynamicAlpha(white: (0, 0, 0, 0.078), terracotta: (0.36, 0.26, 0.16, 0.115), dark: (1, 1, 1, 0.068)) }

    /// Карточка под курсором.
    ///
    /// Отдельный сплошной токен, а не `hover` поверх карточки. `hover` — это
    /// плёнка, и если ею ЗАЛИТЬ карточку (как сделано в `SettingsView`
    /// на строках 578 и 669), она смешается не с карточкой, а с тем, что под
    /// ней, то есть со страницей. Белая карточка при наведении становилась
    /// темнее страницы и проваливалась сквозь полотно. Здесь результат
    /// посчитан заранее: шаг к `card` — 1.08 / 1.08 / 1.14, во всех темах
    /// в одну сторону.
    static var cardHover: Color      { dynamic(white: (0.965, 0.965, 0.965), terracotta: (0.966, 0.956, 0.943), dark: (0.184, 0.180, 0.176)) }

    // MARK: - Кнопки: заливки и краски
    //
    // `accent` и `accentHover` выше НЕ меняются — они остаются идентичностью
    // темы и продолжают красить иконки, чекмарки и ссылки. Токены ниже нужны
    // потому, что под сплошную заливку тот же цвет не годится: белым по
    // `Palette.accent` контраст 4.11 / 3.61 / 2.38 — провал AA во всех трёх
    // темах, а в тёмной подпись просто не читается.

    /// Заливка акцентной кнопки — тон на ступень глубже акцента.
    /// В тёмной теме сдвига нет: там подпись тёмная, и контраста хватает.
    static var accentFill: Color        { dynamic(white: (0.145, 0.425, 0.845), terracotta: (0.700, 0.350, 0.240), dark: (0.900, 0.580, 0.460)) }
    static var accentFillHover: Color   { dynamic(white: (0.110, 0.365, 0.760), terracotta: (0.640, 0.300, 0.196), dark: (0.940, 0.640, 0.520)) }
    static var accentFillPressed: Color { dynamic(white: (0.085, 0.310, 0.665), terracotta: (0.575, 0.255, 0.160), dark: (0.972, 0.700, 0.585)) }

    /// Подпись и иконка поверх акцентной заливки. Вычисляется темой, а не
    /// берётся белой: в тёмной теме акцент светлый, и белым по нему — 2.38:1.
    /// Худшее из девяти сочетаний с тремя заливками выше — 4.66:1, AA везде.
    static var onAccent: Color          { dynamic(white: (0.992, 0.995, 1.000), terracotta: (1.000, 0.988, 0.976), dark: (0.115, 0.072, 0.052)) }

    /// Подпись опасной кнопки. Отдельно от `iconDanger`: тот на плашке даёт
    /// 3.57 / 3.87 / 4.48 — годится как графика (порог 3:1), но не как текст
    /// 13.5 pt. Здесь худшее из всех состояний — 4.50:1.
    static var textDanger: Color        { dynamic(white: (0.700, 0.145, 0.125), terracotta: (0.628, 0.182, 0.140), dark: (0.985, 0.640, 0.598)) }

    /// Вуаль опасной кнопки. Сплошной красной заливки нет намеренно:
    /// в терракотовой теме `iconDanger` и `accent` — соседи по семейству,
    /// и залитая красным кнопка читалась бы как акцентная, то есть как
    /// приглашение, а не предупреждение. В покое плашка обычная, теплеет она
    /// ровно тогда, когда курсор уже на ней.
    static var dangerVeilHover: Color   { dynamicAlpha(white: (0.840, 0.290, 0.270, 0.090), terracotta: (0.760, 0.290, 0.240, 0.090), dark: (0.940, 0.460, 0.420, 0.115)) }
    static var dangerVeilPressed: Color { dynamicAlpha(white: (0.840, 0.290, 0.270, 0.150), terracotta: (0.760, 0.290, 0.240, 0.150), dark: (0.940, 0.460, 0.420, 0.190)) }

    /// Выключенная кнопка теряет рельеф, а не выцветает целиком: плашка почти
    /// сливается с фоном страницы. Так выключенную акцентную кнопку не
    /// спутать с включённой обычной — а именно это и происходило, пока
    /// выключение делалось через `.opacity(0.4…0.45)` на весь узел.
    static var disabledFill: Color      { dynamic(white: (0.950, 0.953, 0.960), terracotta: (0.963, 0.945, 0.915), dark: (0.132, 0.128, 0.122)) }
    /// Подпись выключенной кнопки: 3.17 / 3.55 / 4.40 на плашке выше.
    /// Не `textTertiary` — тот дал бы 2.36 / 2.68 / 3.61, то есть надпись,
    /// которую нельзя прочитать, чтобы понять, чего ты лишён.
    static var disabledLabel: Color     { dynamic(white: (0.512, 0.538, 0.575), terracotta: (0.540, 0.492, 0.435), dark: (0.535, 0.522, 0.502)) }

    // MARK: - Переключатель
    //
    // Прежний `toggleOn` в белой теме был почти чёрным, а в двух других —
    // акцентным: включённый тумблер означал разное в разных темах. Теперь
    // включённый трек — всегда акцент своей темы.

    static var switchTrackOn: Color          { accent }
    static var switchTrackOnHover: Color     { accentHover }
    /// Выключенный трек. Прежний (0.850, 0.860, 0.880) давал белой кнопке
    /// контраст 1.30:1 — граница кнопки на треке была не видна.
    static var switchTrackOff: Color         { dynamic(white: (0.545, 0.558, 0.578), terracotta: (0.596, 0.548, 0.482), dark: (0.442, 0.432, 0.416)) }
    static var switchTrackOffHover: Color    { dynamic(white: (0.478, 0.492, 0.514), terracotta: (0.528, 0.478, 0.410), dark: (0.512, 0.500, 0.482)) }
    static var switchTrackOnDisabled: Color  { dynamic(white: (0.631, 0.766, 0.964), terracotta: (0.899, 0.741, 0.684), dark: (0.485, 0.339, 0.282)) }
    static var switchTrackOffDisabled: Color { dynamic(white: (0.750, 0.757, 0.768), terracotta: (0.776, 0.748, 0.708), dark: (0.308, 0.301, 0.290)) }
    static var switchKnob: Color             { dynamic(white: (1.000, 1.000, 1.000), terracotta: (1.000, 1.000, 1.000), dark: (0.110, 0.105, 0.100)) }
    static var switchKnobDisabled: Color     { dynamic(white: (0.480, 0.490, 0.510), terracotta: (0.500, 0.460, 0.400), dark: (0.110, 0.105, 0.100)) }
    static var switchKnobShadow: Color       { dynamicAlpha(white: (0, 0, 0, 0.14), terracotta: (0.35, 0.25, 0.15, 0.16), dark: (0, 0, 0, 0.28)) }

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

// MARK: - Кнопки

/// Роль кнопки — что она делает, а не как выглядит. Цвета выводятся из роли,
/// поэтому в местах вызова не остаётся ни одной строки про заливку и подпись.
enum IntactButtonRole {
    /// Обычное действие: «Копировать», «Обновить», «Показать файл».
    case neutral
    /// Главное действие блока. На один блок — одна такая кнопка.
    case accent
    /// Удаление, сброс, необратимое.
    case danger
    /// Третичное: в покое одна подпись, плашка появляется под курсором.
    case quiet
}

/// Состояние кнопки. Отдельным типом, чтобы таблица цветов читалась как
/// таблица, а не как гнездо тернарников.
enum IntactButtonState {
    case rest, hovered, pressed, disabled
}

/// Метрики кнопки. Именно метрики: кегль и начертание задаёт содержимое,
/// стиль в типографику не лезет.
enum IntactButtonSize {
    /// Плашка в строке настроек. Размеры прежнего `PillButton`, до пикселя.
    case regular
    /// Плотный ряд, где кнопок несколько подряд.
    case compact

    var horizontalPadding: CGFloat { self == .regular ? 18 : 12 }
    var verticalPadding: CGFloat   { self == .regular ? 8 : 6 }
    var cornerRadius: CGFloat      { self == .regular ? 9 : 8 }
}

extension IntactButtonRole {
    /// Сплошная заливка плашки. Опасная и тихая роль сплошной заливки не
    /// имеют — им кладётся вуаль (см. `veil`).
    func fill(_ state: IntactButtonState) -> Color {
        switch (self, state) {
        case (.quiet, _):          return .clear
        case (_, .disabled):       return Palette.disabledFill
        case (.neutral, _):        return Palette.pill
        // У опасной кнопки покой намеренно нейтральный: краснеет подпись,
        // а не плашка. Предупреждение приходит ровно тогда, когда до него
        // есть дело, — когда курсор уже на кнопке.
        case (.danger, _):         return Palette.pill
        case (.accent, .rest):     return Palette.accentFill
        case (.accent, .hovered):  return Palette.accentFillHover
        case (.accent, .pressed):  return Palette.accentFillPressed
        }
    }

    /// Вуаль состояния поверх заливки. У акцентной кнопки её нет — там
    /// состояние несёт собственная лестница заливок.
    func veil(_ state: IntactButtonState) -> Color {
        guard state != .disabled, self != .accent else { return .clear }
        switch (self, state) {
        case (.danger, .hovered):  return Palette.dangerVeilHover
        case (.danger, .pressed):  return Palette.dangerVeilPressed
        case (_, .hovered):        return Palette.hover
        case (_, .pressed):        return Palette.pressed
        default:                   return .clear
        }
    }

    /// Цвет подписи и иконки.
    func label(_ state: IntactButtonState) -> Color {
        switch (self, state) {
        case (_, .disabled):  return Palette.disabledLabel
        case (.accent, _):    return Palette.onAccent
        case (.danger, _):    return Palette.textDanger
        case (.neutral, _):   return Palette.textPrimary
        // Тихая кнопка в покое приглушена, под курсором дотягивается до
        // основного текста — иначе непонятно, что это вообще кнопка.
        case (.quiet, .rest): return Palette.textSecondary
        case (.quiet, _):     return Palette.textPrimary
        }
    }
}

/// Единственный способ выразить наведение, нажатие и выключенность кнопки.
///
/// До него нажатия в приложении не существовало: все 63 кнопки стояли на
/// `.buttonStyle(.plain)`, а `isPressed` не встречался ни разу.
struct IntactButtonStyle: ButtonStyle {
    var role: IntactButtonRole = .neutral
    var size: IntactButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, role: role, size: size)
    }

    /// Почему тело стиля — отдельная `View`, а не `configuration.label`
    /// с модификаторами прямо в `makeBody`.
    ///
    /// `ButtonStyle` — не `View`, а фабрика: SwiftUI негде хранить её
    /// состояние, поэтому `@State` внутри стиля не переживает перерисовку,
    /// а `@Environment` не читается. В `Configuration` есть только
    /// `isPressed` — ни про курсор, ни про `.disabled(...)` там ничего нет.
    /// Всё это появляется, как только `makeBody` возвращает настоящую `View`.
    ///
    /// Имя `Surface` выбрано не случайно: назвать вложенный тип `Body`
    /// нельзя — он столкнётся с `associatedtype Body` протокола, и стиль
    /// перестанет ему соответствовать.
    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let role: IntactButtonRole
        let size: IntactButtonSize

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        private var state: IntactButtonState {
            // Порядок важен: выключенность старше нажатия, нажатие старше
            // наведения. Иначе кнопка, погасшая под курсором, продолжает
            // светиться.
            if !isEnabled { return .disabled }
            if configuration.isPressed { return .pressed }
            return hovering ? .hovered : .rest
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
        }

        var body: some View {
            configuration.label
                // Однострочность — инвариант компонента, а не забота места
                // вызова: подпись кнопки, разорванная посреди слова, всегда
                // дефект. Сознательно без `fixedSize` — он делает кнопку
                // несжимаемой, и кластер из четырёх пилюль уезжает за карточку.
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(role.label(state))
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, size.verticalPadding)
                // Заливка и вуаль — ОДНИМ фоном, слоями внутри `ZStack`.
                // Двумя `.background` подряд не работает: второй кладётся
                // ПОД первый, и вуаль состояния уходит под непрозрачную
                // плашку. Проверено рендером — наведение и нажатие пропадали
                // у всех кнопок с ролями `.neutral` и `.danger`, то есть у всех
                // существующих.
                .background(
                    ZStack {
                        shape.fill(role.fill(state))
                        shape.fill(role.veil(state))
                    }
                )
                // Нажимается вся плашка вместе с полями — и у тихой роли,
                // где фон прозрачный и ловить курсору нечего.
                .contentShape(shape)
                .scaleEffect(pressScale)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { inside in
                    // Выключенная кнопка не подсвечивается: наведение —
                    // обещание, которое она не может выполнить.
                    hovering = isEnabled && inside
                }
                .onChange(of: isEnabled) { _, enabled in
                    // Кнопка гаснет прямо под курсором: нажал «Собрать» —
                    // и она тут же выключилась. Без сброса подсветка залипнет
                    // до следующего движения мыши.
                    if !enabled { hovering = false }
                }
        }

        /// Единственный сигнал нажатия, не зависящий от цвета. При включённом
        /// «Уменьшении движения» — не проседает.
        private var pressScale: CGFloat {
            guard isEnabled, configuration.isPressed, !reduceMotion else { return 1 }
            return 0.975
        }
    }
}

extension ButtonStyle where Self == IntactButtonStyle {
    static var intact: IntactButtonStyle { IntactButtonStyle() }

    static func intact(_ role: IntactButtonRole,
                       size: IntactButtonSize = .regular) -> IntactButtonStyle {
        IntactButtonStyle(role: role, size: size)
    }
}

/// Кастомный минималистичный переключатель в стиле Wispr Flow.
///
/// Стиль возвращает только сам переключатель фиксированного размера 44×26.
/// Подпись `configuration.label` намеренно не рисуется: все 23 вызова
/// в проекте — `Toggle("", isOn:)`, роль подписи играет заголовок `Row`.
/// Прежний `HStack { label; Spacer() }` растягивал контрол на всю доступную
/// ширину и отбирал место у того самого заголовка — при том что `Row` уже
/// ставит `Spacer(minLength: 16)` перед контролом сам.
struct WisprToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        WisprSwitch(isOn: configuration.$isOn)
    }
}

/// Отдельная `View`, а не тело стиля: `ToggleStyle.makeBody` — не `View`,
/// и `@Environment`/`@State` внутри самого стиля не обновлялись бы. Именно
/// здесь читается `isEnabled`, приходящий от `.disabled(...)` на месте вызова.
private struct WisprSwitch: View {
    @Binding var isOn: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    // Геометрия прежняя — размер менять не просили.
    private static let trackWidth: CGFloat = 44
    private static let trackHeight: CGFloat = 26
    private static let knobSize: CGFloat = 20
    private static let knobInset: CGFloat = 3

    /// Переброс. Та же пружина, что стояла в прежнем стиле.
    private static let flip = Animation.spring(response: 0.22, dampingFraction: 0.72)
    /// Наведение и нажатие — микродвижения. Пружина им не нужна.
    private static let touch = Animation.easeOut(duration: 0.10)

    var body: some View {
        // Именно `Button`, а не жесты на голом `ZStack`. Кнопка сама
        // попадает в цепочку фокуса и срабатывает на пробел; на жестах
        // переключатель стал бы доступен только мыши.
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(trackColor)

                Circle()
                    .fill(isEnabled ? Palette.switchKnob : Palette.switchKnobDisabled)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    // У недоступного переключателя тени нет: плоскость сама
                    // читается как «сейчас не трогается», и это не `.opacity`
                    // на всю вьюху, которая размазала бы и цвета.
                    .shadow(color: isEnabled ? Palette.switchKnobShadow : Color.clear,
                            radius: isEnabled ? 2 : 0,
                            x: 0,
                            y: isEnabled ? 1 : 0)
                    .padding(Self.knobInset)
            }
            .frame(width: Self.trackWidth, height: Self.trackHeight)
            // Кликается вся таблетка, включая 3 pt отступа вокруг кнобы.
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(SwitchPressStyle(reduceMotion: reduceMotion))
        .animation(Self.flip, value: isOn)
        .animation(Self.touch, value: hovering)
        .animation(Self.touch, value: isEnabled)
        // Наведение приходит и на недоступный контрол — гасим его здесь.
        .onHover { hovering = isEnabled && $0 }
        // Подписи у контрола нет (её роль играет `Row.title`), поэтому
        // озвучиваем хотя бы значение — иначе VoiceOver прочитает «кнопка».
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
        .accessibilityValue(isOn ? T("Включено", "On") : T("Выключено", "Off"))
    }

    private var trackColor: Color {
        guard isEnabled else {
            return isOn ? Palette.switchTrackOnDisabled : Palette.switchTrackOffDisabled
        }
        if isOn {
            return hovering ? Palette.switchTrackOnHover : Palette.switchTrackOn
        }
        return hovering ? Palette.switchTrackOffHover : Palette.switchTrackOff
    }
}

/// Нажатие переключателя — ТОЛЬКО масштаб, без цветной вуали поверх.
///
/// Вуаль здесь легла бы разом и на трек, и на кнобу и уронила бы их взаимный
/// контраст во всех шести сочетаниях: выключенный трек 3.28 → 3.19,
/// включённый 4.11 → 3.96, а в терракотовой теме до 3.05:1 — впритык к порогу
/// 3:1 для графики. Граница кнобы на треке важнее подсветки нажатия, тем
/// более что нажатие тут же и переключает состояние, которое видно само.
private struct SwitchPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
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
///
/// Внешне это теперь тонкая обёртка: весь вид и все состояния держит
/// `IntactButtonStyle`, а компонент отвечает только за состав содержимого
/// и за то, какую роль вывести из `tone`. Подпись вызова прежняя — её
/// используют 39 мест, ломать их незачем.
struct PillButton: View {
    let title: String
    var icon: IntactIconKind? = nil
    /// Семантика действия: `.danger` для удаления, `.success` для подтверждения.
    var tone: IconTone? = nil
    var action: () -> Void

    /// Роль выводится из тона, а не задаётся отдельно: на местах вызова уже
    /// написано `tone: .danger`, и заставлять их дублировать это ещё и ролью
    /// значит завести два источника правды об одной кнопке.
    private var role: IntactButtonRole {
        if case .danger = tone { return .danger }
        return .neutral
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    // Цвет иконки больше не задаётся здесь: он приходит из
                    // роли через `foregroundStyle` стиля и потому совпадает
                    // с подписью во всех четырёх состояниях, включая
                    // выключенное. Прежде иконка красилась `tone`, а подпись —
                    // отдельно, и у выключенной кнопки они расходились.
                    IntactIcon(kind: icon, size: 13, monochrome: true)
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
            }
        }
        .buttonStyle(.intact(role))
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

                    TextField(T("Поиск: русский, english, de, fr...", "Search: english, русский, de, fr..."), text: $search)
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
                            Text(T("Язык не найден", "Language not found"))
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            if search.isEmpty {
                                Text(T("Часто используемые", "Frequently used"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.textTertiary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)

                                ForEach(Language.popular) { lang in
                                    languageRow(lang)
                                }

                                Text(T("Все языки (\(Language.all.count))", "All languages (\(Language.all.count))"))
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
                    .help(T("Убрать «\(item)» из словаря", "Remove “\(item)” from the dictionary"))
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
