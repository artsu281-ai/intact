import AppKit
import SwiftUI

// MARK: - Дизайн-система иконок Intact
//
// Правила, на которых держится вся библиотека:
//
//  1. Сетка. Любая иконка авторится на квадрате 24×24. Координаты в формах —
//     это буквальные числа с миллиметровки, а не доли ширины. `IconPen`
//     пересчитывает их в реальный размер.
//
//  2. Живая область 2…22. Крайняя точка контура плюс половина штриха обязана
//     остаться внутри. Иначе иконка обрежется рядом с соседями по строке.
//
//  3. Слои. Иконка — это набор `IconLayer`, а не один Path. Носитель смысла
//     (стрелка, галочка, волна) рисуется ролью `.primary`, контейнер
//     (лист, лоток, рамка) — `.secondary` и приглушается. Это даёт глубину
//     без второго цвета.
//
//  4. Никаких пересечений. Контурная иконка без масок не прощает наложений:
//     линия заднего слоя пройдёт сквозь передний. Перекрывающиеся элементы
//     рисуются как видимый фрагмент, а не как целая фигура сверху.
//
//  5. Толщина штриха НЕ линейна размеру. 16 px и 36 px требуют разной
//     относительной толщины, чтобы выглядеть одинаково плотно, — см. `IconWeight`.

// MARK: - Перо

/// Перо для рисования на авторской сетке 24×24.
///
/// Углы задаются в градусах: 0° — вправо, рост по часовой стрелке
/// (система координат экрана, ось Y смотрит вниз).
struct IconPen {
    /// Сторона авторской сетки.
    static let grid: CGFloat = 24
    /// Живая область: `grid` минус поля сверху/снизу.
    static let safeArea: ClosedRange<CGFloat> = 2...22

    private let u: CGFloat
    private(set) var path = Path()

    init(unit: CGFloat) { self.u = unit }

    private func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }

    /// Точка на окружности по полярным координатам.
    func polar(_ cx: CGFloat, _ cy: CGFloat, radius r: CGFloat, angle deg: CGFloat) -> (CGFloat, CGFloat) {
        let rad = deg * .pi / 180
        return (cx + cos(rad) * r, cy + sin(rad) * r)
    }

    // MARK: Базовые команды

    mutating func move(_ x: CGFloat, _ y: CGFloat) { path.move(to: at(x, y)) }
    mutating func line(_ x: CGFloat, _ y: CGFloat) { path.addLine(to: at(x, y)) }
    mutating func close() { path.closeSubpath() }

    /// Присоединяет уже готовый контур (в тех же единицах) — для деталей,
    /// которые переиспользуются между иконками.
    mutating func append(_ other: Path) { path.addPath(other) }

    /// Ломаная одним вызовом: `pen.polyline([(4, 12), (9, 17), (20, 6)])`.
    mutating func polyline(_ points: [(CGFloat, CGFloat)], closed: Bool = false) {
        guard let first = points.first else { return }
        move(first.0, first.1)
        for p in points.dropFirst() { line(p.0, p.1) }
        if closed { close() }
    }

    /// Квадратичная кривая — для вогнутых лучей звезды и мягких силуэтов.
    mutating func quad(control cx: CGFloat, _ cy: CGFloat, to x: CGFloat, _ y: CGFloat) {
        path.addQuadCurve(to: at(x, y), control: at(cx, cy))
    }

    /// Скруглённый угол: дуга, касательная к отрезку из текущей точки в `via`
    /// и к отрезку из `via` в `to`. Позволяет писать контур как ломаную,
    /// не считая точки касания вручную.
    mutating func corner(via vx: CGFloat, _ vy: CGFloat, to x: CGFloat, _ y: CGFloat, radius: CGFloat) {
        path.addArc(tangent1End: at(vx, vy), tangent2End: at(x, y), radius: radius * u)
    }

    // MARK: Фигуры

    mutating func circle(_ cx: CGFloat, _ cy: CGFloat, radius r: CGFloat) {
        path.addEllipse(in: CGRect(x: (cx - r) * u, y: (cy - r) * u, width: r * 2 * u, height: r * 2 * u))
    }

    mutating func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius r: CGFloat = 0) {
        let frame = CGRect(x: x * u, y: y * u, width: w * u, height: h * u)
        if r > 0 {
            path.addRoundedRect(in: frame, cornerSize: CGSize(width: r * u, height: r * u), style: .continuous)
        } else {
            path.addRect(frame)
        }
    }

    /// Дуга от `from` до `to` (в градусах) с продолжением текущего контура.
    mutating func arc(_ cx: CGFloat, _ cy: CGFloat, radius r: CGFloat,
                      from: CGFloat, to: CGFloat, connected: Bool = false) {
        if !connected {
            let start = polar(cx, cy, radius: r, angle: from)
            move(start.0, start.1)
        }
        path.addArc(center: at(cx, cy), radius: r * u,
                    startAngle: .degrees(Double(from)), endAngle: .degrees(Double(to)),
                    clockwise: false)
    }
}

/// Собирает один контур: `draw { p in p.move(4, 12); p.line(20, 12) }`.
func iconPath(unit: CGFloat, _ body: (inout IconPen) -> Void) -> Path {
    var pen = IconPen(unit: unit)
    body(&pen)
    return pen.path
}

// MARK: - Слои

/// Как рисуется отдельный контур иконки.
enum IconRole {
    /// Носитель смысла. Полная непрозрачность, обводка.
    case primary
    /// Контейнер и поддержка. Обводка, приглушённая по прозрачности.
    case secondary
    /// Плотная заливка: точка статуса, квадрат «стоп», ядро радиокнопки.
    case solid
    /// Заливка приглушённым тоном.
    case solidSecondary
    /// Обводка семантическим цветом независимо от `foregroundStyle`.
    case tinted(IconTone)
    /// Заливка семантическим цветом (бейджи, индикаторы).
    case tintedSolid(IconTone)
}

struct IconLayer {
    let path: Path
    let role: IconRole

    static func primary(_ p: Path) -> IconLayer { .init(path: p, role: .primary) }
    static func secondary(_ p: Path) -> IconLayer { .init(path: p, role: .secondary) }
    static func solid(_ p: Path) -> IconLayer { .init(path: p, role: .solid) }
    static func solidSecondary(_ p: Path) -> IconLayer { .init(path: p, role: .solidSecondary) }
    static func tinted(_ tone: IconTone, _ p: Path) -> IconLayer { .init(path: p, role: .tinted(tone)) }
    static func tintedSolid(_ tone: IconTone, _ p: Path) -> IconLayer { .init(path: p, role: .tintedSolid(tone)) }
}

// MARK: - Цветовые роли

/// Семантическая роль цвета. Цвет несёт состояние, а не украшает:
/// нейтральный контур по умолчанию, окраска — только когда иконка что-то сообщает.
enum IconTone {
    case idle       // контур по умолчанию
    case muted      // выключено, декоративное
    case active     // выбранный раздел, активное действие
    case onAccent   // иконка внутри залитой акцентом кнопки
    case success    // сохранено, выполнено, доступ выдан
    case warning    // доступно обновление, напоминание
    case danger     // удаление, очистка, ошибка
    case process    // генерация, загрузка, транскрипция
    case voice      // запись, микрофон, эквалайзер

    var color: Color {
        switch self {
        case .idle:     return Palette.iconIdle
        case .muted:    return Palette.iconMuted
        case .active:   return Palette.accent
        case .onAccent: return .white
        case .success:  return Palette.iconSuccess
        case .warning:  return Palette.iconWarning
        case .danger:   return Palette.iconDanger
        case .process:  return Palette.iconProcess
        case .voice:    return Palette.accent
        }
    }
}

// MARK: - Толщина

/// Оптическая плотность контура. Толщина подобрана бэндами, а не пропорцией:
/// линейное масштабирование делает мелкие иконки жирными, а крупные — ватными.
enum IconWeight: Hashable {
    case light, regular, medium

    var multiplier: CGFloat {
        switch self {
        case .light:   return 0.85
        case .regular: return 1.0
        case .medium:  return 1.18
        }
    }

    func strokeWidth(for size: CGFloat) -> CGFloat {
        let base: CGFloat
        switch size {
        case ..<11:  base = 1.25
        case ..<16:  base = 1.40
        case ..<20:  base = 1.50
        case ..<28:  base = 1.60
        case ..<40:  base = 1.75
        default:     base = size * 0.045
        }
        return base * multiplier
    }
}

// MARK: - Рендерер

/// Универсальный рендерер векторной иконки Intact.
///
/// По умолчанию иконка наследует цвет из `.foregroundStyle()` вызывающего кода —
/// поэтому её можно ставить в любую кнопку и не думать о теме. Явный `tone`
/// перебивает наследование и красит иконку семантически.
struct IntactIcon: View {
    let kind: IntactIconKind
    var size: CGFloat = 16
    var tone: IconTone? = nil
    var weight: IconWeight = .regular
    /// Гасит семантические слои (бейджи, цветные акценты) — для сайдбара и
    /// меню-бара, где иконка обязана быть строго одноцветной.
    var monochrome: Bool = false

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: weight.strokeWidth(for: size), lineCap: .round, lineJoin: .round)
    }

    /// В тёмной теме тонкий контур на 45 % физически исчезает — поднимаем порог.
    private var secondaryOpacity: Double {
        AppSettings.shared.isDarkMode ? 0.55 : 0.45
    }

    var body: some View {
        // Цвет НЕ навязывается: без явного `tone` иконка наследует
        // `foregroundStyle` места вызова — так одна и та же иконка работает
        // и в акцентной кнопке, и в приглушённой строке.
        canvas
            .frame(width: size, height: size)
            .modifier(OptionalForeground(color: tone?.color))
            .accessibilityHidden(true)
    }

    private var canvas: some View {
        Canvas { ctx, canvasSize in
            let unit = min(canvasSize.width, canvasSize.height) / IconPen.grid
            for layer in kind.layers(unit: unit) {
                draw(layer, in: &ctx)
            }
        }
    }

    private func draw(_ layer: IconLayer, in ctx: inout GraphicsContext) {
        switch layer.role {
        case .primary:
            ctx.stroke(layer.path, with: .foreground, style: stroke)
        case .secondary:
            withOpacity(secondaryOpacity, &ctx) { c in c.stroke(layer.path, with: .foreground, style: stroke) }
        case .solid:
            ctx.fill(layer.path, with: .foreground)
        case .solidSecondary:
            withOpacity(secondaryOpacity, &ctx) { c in c.fill(layer.path, with: .foreground) }
        case .tinted(let t):
            let shading: GraphicsContext.Shading = monochrome ? .foreground : .color(t.color)
            ctx.stroke(layer.path, with: shading, style: stroke)
        case .tintedSolid(let t):
            let shading: GraphicsContext.Shading = monochrome ? .foreground : .color(t.color)
            ctx.fill(layer.path, with: shading)
        }
    }

    private func withOpacity(_ value: Double, _ ctx: inout GraphicsContext,
                             _ body: (inout GraphicsContext) -> Void) {
        let previous = ctx.opacity
        ctx.opacity = value
        body(&ctx)
        ctx.opacity = previous
    }
}

/// Красит содержимое только если цвет задан. Безусловный `foregroundStyle`
/// внутри компонента молча перебивал бы цвет, выставленный на месте вызова.
private struct OptionalForeground: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.foregroundStyle(color)
        } else {
            content
        }
    }
}

// MARK: - Иконка, следующая за размером шрифта

/// Иконка, которая растёт вместе с системным масштабом текста (100 %…200 %).
/// Верхняя граница обязательна: иначе на 200 % иконка разорвёт строку карточки.
struct ScaledIntactIcon: View {
    let kind: IntactIconKind
    var tone: IconTone? = nil
    var weight: IconWeight = .regular
    var maxSize: CGFloat = 28

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 16

    var body: some View {
        IntactIcon(kind: kind, size: min(side, maxSize), tone: tone, weight: weight)
    }
}

// MARK: - Иконка бокового меню

/// Иконка раздела в сайдбаре. Выбранный раздел получает акцент и чуть большую
/// плотность контура — вес важнее цвета, он читается и в монохромной теме.
struct SidebarIntactIcon: View {
    let kind: IntactIconKind
    let selected: Bool
    var size: CGFloat = 16

    var body: some View {
        IntactIcon(kind: kind,
                   size: size,
                   tone: selected ? .active : .idle,
                   weight: selected ? .medium : .regular,
                   monochrome: true)
    }
}

// MARK: - Стеклянная плитка

/// Контейнер под иконку: мягкое стекло в цвете роли.
///
/// Стекло живёт здесь, а не на контуре: эффект на штрихе толщиной 1.4 pt
/// превращается в грязь. Одна плитка на смысловой блок, не на каждую строку списка.
struct IconTile: View {
    let kind: IntactIconKind
    var tone: IconTone = .active
    var side: CGFloat = 36
    /// Включать поверх фотоподложки и HUD, где за плиткой есть что размывать.
    var material: Bool = false

    private var iconSize: CGFloat { (side * 0.48).rounded() }
    private var radius: CGFloat { side * 0.34 }
    private var isDark: Bool { AppSettings.shared.isDarkMode }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tone.color.opacity(isDark ? 0.16 : 0.10))
                .background {
                    if material {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(tone.color.opacity(isDark ? 0.22 : 0.18), lineWidth: 1)
                }

            IntactIcon(kind: kind, size: iconSize, tone: tone)
        }
        .frame(width: side, height: side)
    }
}

// MARK: - Живая иконка голоса

/// Микрофон с дыханием. Анимация включается только на активном состоянии
/// и полностью отключается при «Уменьшении движения»: индикатор висит поверх
/// всех окон, и вечный таймер там стоит батареи.
struct PulsingVoiceIcon: View {
    var active: Bool
    var size: CGFloat = 16
    /// `nil` — наследовать цвет от вызывающего кода (нужно в HUD со своей палитрой).
    var tone: IconTone? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { active && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let breath = animates ? 1 + 0.06 * sin(phase * 3.4) : 1

            IntactIcon(kind: active ? .voicePulse : .voice, size: size, tone: tone)
                .scaleEffect(breath)
        }
    }
}

/// Три точки «ассистент печатает».
///
/// Заменяет системный `ProgressView` там, где идёт генерация текста:
/// крутящийся индикатор означает «жди неизвестно сколько», а бегущие точки
/// читаются как «идёт речь» — это разные обещания пользователю.
struct ThinkingDots: View {
    var size: CGFloat = 16
    var tone: IconTone? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dot: CGFloat { size * 0.21 }
    private var gap: CGFloat { size * 0.19 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 2.4
            HStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .frame(width: dot, height: dot)
                        .opacity(reduceMotion ? 0.55 : opacity(phase: phase, index: index))
                }
            }
            .modifier(OptionalForeground(color: tone?.color))
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }

    /// Волна по трём точкам: каждая отстаёт от предыдущей на треть периода.
    private func opacity(phase: Double, index: Int) -> Double {
        let offset = Double(index) * 2 * .pi / 3
        return 0.35 + 0.55 * (0.5 + 0.5 * sin(phase - offset))
    }
}

// MARK: - Мост в AppKit

extension IntactIconKind {
    /// Растеризует иконку для мест, где AppKit требует `NSImage`:
    /// строка меню и пункты `NSMenu`.
    ///
    /// `isTemplate` обязателен для меню-бара — иначе иконка останется чёрной
    /// на тёмной панели и белой на светлой.
    ///
    /// Результат кэшируется: меню перерисовывается на каждое движение мыши,
    /// а `ImageRenderer` — операция не бесплатная.
    @MainActor
    func nsImage(size: CGFloat, weight: IconWeight = .medium, template: Bool = true) -> NSImage {
        let key = IconRasterCache.Key(kind: self, size: size, weight: weight, template: template)
        if let cached = IconRasterCache.storage[key] { return cached }

        let renderer = ImageRenderer(
            content: IntactIcon(kind: self, size: size, tone: .idle, weight: weight, monochrome: true)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage else { return NSImage() }
        image.isTemplate = template
        IconRasterCache.storage[key] = image
        return image
    }
}

@MainActor
private enum IconRasterCache {
    struct Key: Hashable {
        let kind: IntactIconKind
        let size: CGFloat
        let weight: IconWeight
        let template: Bool
    }
    static var storage: [Key: NSImage] = [:]
}
