import SwiftUI

// MARK: - Intact Custom Icon Library
// Все иконки реализованы как нативные SwiftUI Shape / View через SVG-пути.
// Использование: IntactIcon(.chat, size: 18).foregroundStyle(Palette.accent)

enum IntactIconKind {
    case chat           // диалог с ИИ (сайдбар, заголовок)
    case history        // история записей
    case send           // отправить сообщение
    case clearChat      // очистить диалог (метла)
    case copy           // скопировать ответ
    case copied         // скопировано (галочка)
    case context        // источники контекста (скрепка)
    case aiStar         // ИИ-ассистент (звезда)
    case quickSummary   // сводка за сегодня (молния)
    case quickTasks     // извлечь задачи (чеклист)
    case quickNotes     // сводка заметок (листок)
    case settings       // настройки (шестерня)
    case statusDot      // индикатор статуса
    case stop           // остановить генерацию
    // Новые разделы UX-редизайна
    case home           // домашний экран (домик)
    case voice          // диктовка (микрофон с волной)
    case briefs         // брифы и заметки (листы со звёздочкой)
    case settingsPage   // единый экран настроек (слайдеры)
}

struct IntactIcon: View {
    let kind: IntactIconKind
    var size: CGFloat = 16

    var body: some View {
        iconShape
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var iconShape: some View {
        switch kind {
        case .chat:          ChatIconShape().aspectRatio(contentMode: .fit)
        case .history:       HistoryIconShape().aspectRatio(contentMode: .fit)
        case .send:          SendIconShape().aspectRatio(contentMode: .fit)
        case .clearChat:     ClearChatIconShape().aspectRatio(contentMode: .fit)
        case .copy:          CopyIconShape().aspectRatio(contentMode: .fit)
        case .copied:        CopiedIconShape().aspectRatio(contentMode: .fit)
        case .context:       ContextIconShape().aspectRatio(contentMode: .fit)
        case .aiStar:        AIStarIconShape().aspectRatio(contentMode: .fit)
        case .quickSummary:  QuickSummaryIconShape().aspectRatio(contentMode: .fit)
        case .quickTasks:    QuickTasksIconShape().aspectRatio(contentMode: .fit)
        case .quickNotes:    QuickNotesIconShape().aspectRatio(contentMode: .fit)
        case .settings:      SettingsIconShape().aspectRatio(contentMode: .fit)
        case .statusDot:     StatusDotShape().aspectRatio(contentMode: .fit)
        case .stop:          StopIconShape().aspectRatio(contentMode: .fit)
        case .home:          HomeIconShape().aspectRatio(contentMode: .fit)
        case .voice:         VoiceIconShape().aspectRatio(contentMode: .fit)
        case .briefs:        BriefsIconShape().aspectRatio(contentMode: .fit)
        case .settingsPage:  SettingsPageIconShape().aspectRatio(contentMode: .fit)
        }
    }
}

// MARK: - Chat (два пузыря + звёздочка внутри)
struct ChatIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Большой пузырь слева
        let br: CGFloat = w * 0.18
        let bx = w * 0.04, by = h * 0.08
        let bw = w * 0.68, bh = h * 0.58
        p.addRoundedRect(in: CGRect(x: bx, y: by, width: bw, height: bh),
                         cornerSize: CGSize(width: br, height: br))
        // Хвост большого пузыря (треугольник вниз-влево)
        let tailBig = Path { t in
            t.move(to: CGPoint(x: bx + w * 0.08, y: by + bh - 1))
            t.addLine(to: CGPoint(x: bx + w * 0.02, y: by + bh + h * 0.14))
            t.addLine(to: CGPoint(x: bx + w * 0.22, y: by + bh - 1))
            t.closeSubpath()
        }
        p.addPath(tailBig)
        // Маленький пузырь справа-снизу
        let sr: CGFloat = w * 0.15
        let sx = w * 0.50, sy = h * 0.42
        let sw = w * 0.46, sh = h * 0.46
        p.addRoundedRect(in: CGRect(x: sx, y: sy, width: sw, height: sh),
                         cornerSize: CGSize(width: sr, height: sr))
        // Хвост маленького пузыря (вниз-вправо)
        let tailSmall = Path { t in
            t.move(to: CGPoint(x: sx + sw - w * 0.22, y: sy + sh - 1))
            t.addLine(to: CGPoint(x: sx + sw - w * 0.02, y: sy + sh + h * 0.12))
            t.addLine(to: CGPoint(x: sx + sw - w * 0.08, y: sy + sh - 1))
            t.closeSubpath()
        }
        p.addPath(tailSmall)
        return p
    }
}

// MARK: - History (часы с закруглённой стрелкой)
struct HistoryIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2, cy = h / 2, r = min(w, h) * 0.44
        var p = Path()
        // Циферблат (кольцо)
        p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        // Вырезаем внутренность — рисуем через stroke
        // Минутная стрелка (12 часов → 3 часа)
        p.move(to: CGPoint(x: cx, y: cy))
        p.addLine(to: CGPoint(x: cx, y: cy - r * 0.62))
        // Часовая стрелка (→ 2 часа)
        p.move(to: CGPoint(x: cx, y: cy))
        p.addLine(to: CGPoint(x: cx + r * 0.46, y: cy - r * 0.26))
        // Дуга-стрелка «возврат» снаружи справа-сверху
        p.move(to: CGPoint(x: cx + r * 0.9, y: cy - r * 0.38))
        p.addArc(center: CGPoint(x: cx, y: cy),
                 radius: r * 1.0,
                 startAngle: .degrees(-25),
                 endAngle: .degrees(-110),
                 clockwise: true)
        return p
    }
}

// MARK: - Send (стрелка вверх в круге)
struct SendIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2, cy = h / 2, r = min(w, h) * 0.46
        var p = Path()
        // Круг
        p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        // Стрелка вверх (тело)
        let aw = w * 0.12, ah = h * 0.44
        let ax = cx - aw / 2, ay = cy - ah * 0.38 + h * 0.04
        p.addRect(CGRect(x: ax, y: ay, width: aw, height: ah * 0.56))
        // Наконечник стрелки (треугольник)
        let tip = Path { t in
            t.move(to: CGPoint(x: cx, y: cy - r * 0.52))
            t.addLine(to: CGPoint(x: cx - w * 0.20, y: cy - r * 0.10))
            t.addLine(to: CGPoint(x: cx + w * 0.20, y: cy - r * 0.10))
            t.closeSubpath()
        }
        p.addPath(tip)
        return p
    }
}

// MARK: - Clear Chat (метла)
struct ClearChatIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Ручка метлы — диагональная линия
        p.move(to: CGPoint(x: w * 0.72, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.62))
        // Ворс метлы — веер из 5 линий
        let fBase = CGPoint(x: w * 0.28, y: h * 0.62)
        let angles: [Double] = [-30, -15, 0, 15, 30]
        for deg in angles {
            let rad = (deg + 110) * .pi / 180
            let ex = fBase.x + cos(rad) * w * 0.26
            let ey = fBase.y + sin(rad) * h * 0.30
            p.move(to: fBase)
            p.addLine(to: CGPoint(x: ex, y: ey))
        }
        // Горизонтальная черта у основания ворса
        p.move(to: CGPoint(x: w * 0.08, y: h * 0.84))
        p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.84))
        // Маленький квадратик ластика на конце ручки
        let er: CGFloat = w * 0.10
        p.addRoundedRect(in: CGRect(x: w * 0.68, y: h * 0.02, width: er, height: er),
                         cornerSize: CGSize(width: 2, height: 2))
        return p
    }
}

// MARK: - Copy (два листа)
struct CopyIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let r: CGFloat = w * 0.12
        // Задний лист (сдвинут вправо-вниз)
        p.addRoundedRect(in: CGRect(x: w * 0.26, y: h * 0.26, width: w * 0.60, height: h * 0.66),
                         cornerSize: CGSize(width: r, height: r))
        // Передний лист (перекрывает)
        p.addRoundedRect(in: CGRect(x: w * 0.14, y: h * 0.08, width: w * 0.60, height: h * 0.66),
                         cornerSize: CGSize(width: r, height: r))
        // Линии текста на переднем листе
        for i in 0..<3 {
            let ly = h * (0.26 + CGFloat(i) * 0.16)
            p.move(to: CGPoint(x: w * 0.24, y: ly))
            p.addLine(to: CGPoint(x: w * 0.64, y: ly))
        }
        return p
    }
}

// MARK: - Copied (галочка)
struct CopiedIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.12, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.80))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.22))
        return p
    }
}

// MARK: - Context / Paperclip (скрепка)
struct ContextIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2
        var p = Path()
        // Внешняя дуга скрепки
        p.addArc(center: CGPoint(x: cx, y: h * 0.36),
                 radius: w * 0.30,
                 startAngle: .degrees(180),
                 endAngle: .degrees(0),
                 clockwise: false)
        p.addLine(to: CGPoint(x: cx + w * 0.30, y: h * 0.76))
        p.addArc(center: CGPoint(x: cx, y: h * 0.76),
                 radius: w * 0.30,
                 startAngle: .degrees(0),
                 endAngle: .degrees(180),
                 clockwise: false)
        p.addLine(to: CGPoint(x: cx - w * 0.30, y: h * 0.36))
        // Внутренняя дуга
        let ir = w * 0.16
        p.move(to: CGPoint(x: cx + ir, y: h * 0.36))
        p.addArc(center: CGPoint(x: cx, y: h * 0.36),
                 radius: ir,
                 startAngle: .degrees(0),
                 endAngle: .degrees(180),
                 clockwise: false)
        p.addLine(to: CGPoint(x: cx - ir, y: h * 0.72))
        p.addArc(center: CGPoint(x: cx, y: h * 0.72),
                 radius: ir,
                 startAngle: .degrees(180),
                 endAngle: .degrees(0),
                 clockwise: false)
        return p
    }
}

// MARK: - AI Star (четырёхлучевая звезда)
struct AIStarIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2, cy = h / 2
        let outer = min(w, h) * 0.46
        let inner = outer * 0.38
        var p = Path()
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let r = i % 2 == 0 ? outer : inner
            let x = cx + cos(angle) * r
            let y = cy + sin(angle) * r
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Quick Summary / Lightning (молния)
struct QuickSummaryIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.60, y: h * 0.04))
        p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.54))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.54))
        p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.46))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.46))
        p.closeSubpath()
        return p
    }
}

// MARK: - Quick Tasks / Checklist (три строки с галочкой)
struct QuickTasksIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let rows: [(CGFloat, Bool)] = [(0.20, true), (0.50, true), (0.78, false)]
        for (yf, checked) in rows {
            let cy = h * yf
            let r = w * 0.10
            // Квадратик чекбокса
            p.addRoundedRect(in: CGRect(x: w * 0.06, y: cy - r, width: r * 2, height: r * 2),
                             cornerSize: CGSize(width: 2, height: 2))
            if checked {
                // Галочка внутри
                p.move(to: CGPoint(x: w * 0.09, y: cy + r * 0.1))
                p.addLine(to: CGPoint(x: w * 0.13, y: cy + r * 0.60))
                p.addLine(to: CGPoint(x: w * 0.23, y: cy - r * 0.44))
            }
            // Строка текста рядом
            p.move(to: CGPoint(x: w * 0.32, y: cy))
            p.addLine(to: CGPoint(x: w * 0.92, y: cy))
        }
        return p
    }
}

// MARK: - Quick Notes / Paper (листок с уголком)
struct QuickNotesIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let fold = w * 0.28
        var p = Path()
        // Контур листа
        p.move(to: CGPoint(x: w * 0.12, y: h * 0.06))
        p.addLine(to: CGPoint(x: w * 0.88 - fold, y: h * 0.06))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.06 + fold))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.94))
        p.addLine(to: CGPoint(x: w * 0.12, y: h * 0.94))
        p.closeSubpath()
        // Загнутый уголок
        p.move(to: CGPoint(x: w * 0.88 - fold, y: h * 0.06))
        p.addLine(to: CGPoint(x: w * 0.88 - fold, y: h * 0.06 + fold))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.06 + fold))
        // Строки текста
        let lines: [CGFloat] = [0.36, 0.52, 0.68]
        for yf in lines {
            p.move(to: CGPoint(x: w * 0.24, y: h * yf))
            p.addLine(to: CGPoint(x: w * 0.76, y: h * yf))
        }
        return p
    }
}

// MARK: - Settings (шестерня с отверстием)
struct SettingsIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2, cy = h / 2
        let outer = min(w, h) * 0.46
        let inner = outer * 0.54
        let toothH = outer * 0.22
        let teeth = 8
        var p = Path()
        for i in 0..<teeth {
            let a0 = Double(i) * .pi * 2 / Double(teeth) - .pi / 2
            let a1 = a0 + .pi / Double(teeth) * 0.5
            let a2 = a0 + .pi / Double(teeth) * 1.5
            let a3 = a0 + .pi * 2 / Double(teeth)
            let pts: [(CGFloat, CGFloat)] = [
                (cx + cos(a0) * outer, cy + sin(a0) * outer),
                (cx + cos(a1) * (outer + toothH), cy + sin(a1) * (outer + toothH)),
                (cx + cos(a2) * (outer + toothH), cy + sin(a2) * (outer + toothH)),
                (cx + cos(a3) * outer, cy + sin(a3) * outer)
            ]
            if i == 0 { p.move(to: CGPoint(x: pts[0].0, y: pts[0].1)) }
            else { p.addLine(to: CGPoint(x: pts[0].0, y: pts[0].1)) }
            for pt in pts.dropFirst() {
                p.addLine(to: CGPoint(x: pt.0, y: pt.1))
            }
        }
        p.closeSubpath()
        // Отверстие в центре (вычтем через EvenOdd)
        p.addEllipse(in: CGRect(x: cx - inner, y: cy - inner, width: inner * 2, height: inner * 2))
        return p
    }
}

// MARK: - Status Dot (заполненный круг)
struct StatusDotShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08))
    }
}

// MARK: - Stop (квадрат)
struct StopIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22),
             cornerRadius: rect.width * 0.08)
    }
}

// MARK: - Sidebar icon helper (stroke rendered per shape)
/// Рендерит кастомную иконку с правильным stroke для сайдбара.
struct SidebarIntactIcon: View {
    let kind: IntactIconKind
    let selected: Bool
    var size: CGFloat = 16

    private var strokeColor: Color { selected ? Palette.accent : Palette.textSecondary }
    private var strokeWidth: CGFloat { selected ? 1.4 : 1.2 }

    var body: some View {
        Canvas { ctx, sz in
            let rect = CGRect(origin: .zero, size: sz)
            let shape: any Shape
            switch kind {
            case .chat:         shape = ChatIconShape()
            case .history:      shape = HistoryIconShape()
            case .send:         shape = SendIconShape()
            case .clearChat:    shape = ClearChatIconShape()
            case .copy:         shape = CopyIconShape()
            case .copied:       shape = CopiedIconShape()
            case .context:      shape = ContextIconShape()
            case .aiStar:       shape = AIStarIconShape()
            case .quickSummary: shape = QuickSummaryIconShape()
            case .quickTasks:   shape = QuickTasksIconShape()
            case .quickNotes:   shape = QuickNotesIconShape()
            case .settings:     shape = SettingsIconShape()
            case .statusDot:    shape = StatusDotShape()
            case .stop:         shape = StopIconShape()
            case .home:         shape = HomeIconShape()
            case .voice:        shape = VoiceIconShape()
            case .briefs:       shape = BriefsIconShape()
            case .settingsPage: shape = SettingsPageIconShape()
            }
            let path = shape.path(in: rect)
            ctx.stroke(path,
                       with: .color(strokeColor),
                       style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Home (домик с крышей и окошком)
struct HomeIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Крыша — треугольник
        p.move(to: CGPoint(x: w * 0.10, y: h * 0.50))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.10))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.50))
        // Стены и дверь
        p.move(to: CGPoint(x: w * 0.18, y: h * 0.50))
        p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.92))
        p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.92))
        p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.50))
        // Дверь
        let dr = w * 0.06
        p.addRoundedRect(in: CGRect(x: w * 0.40, y: h * 0.62, width: w * 0.20, height: h * 0.30),
                         cornerSize: CGSize(width: dr, height: dr))
        return p
    }
}

// MARK: - Voice (микрофон с волнами активности)
struct VoiceIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2
        var p = Path()
        // Капсула микрофона
        let mw = w * 0.28, mh = h * 0.46
        let mx = cx - mw / 2, my = h * 0.06
        p.addRoundedRect(in: CGRect(x: mx, y: my, width: mw, height: mh),
                         cornerSize: CGSize(width: mw / 2, height: mw / 2))
        // Дуга стойки
        p.addArc(center: CGPoint(x: cx, y: h * 0.52),
                 radius: w * 0.30,
                 startAngle: .degrees(180),
                 endAngle: .degrees(0),
                 clockwise: true)
        // Ножка
        p.move(to: CGPoint(x: cx, y: h * 0.82))
        p.addLine(to: CGPoint(x: cx, y: h * 0.94))
        // Подставка
        p.move(to: CGPoint(x: cx - w * 0.24, y: h * 0.94))
        p.addLine(to: CGPoint(x: cx + w * 0.24, y: h * 0.94))
        return p
    }
}

// MARK: - Briefs (листок со звёздочкой — заметки + ИИ)
struct BriefsIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Лист бумаги
        let fold = w * 0.24
        p.move(to: CGPoint(x: w * 0.10, y: h * 0.06))
        p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.06))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.06 + fold))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.94))
        p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.94))
        p.closeSubpath()
        // Загнутый уголок
        p.move(to: CGPoint(x: w * 0.76, y: h * 0.06))
        p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.06 + fold))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.06 + fold))
        // Мини-звезда (4 луча) в центре листа
        let sx = w * 0.50, sy = h * 0.54, sr = w * 0.14, si = sr * 0.40
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 - .pi / 2
            let r = i % 2 == 0 ? sr : si
            let x = sx + cos(a) * r
            let y = sy + sin(a) * r
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - SettingsPage (три горизонтальных слайдера)
struct SettingsPageIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let rows: [(CGFloat, CGFloat)] = [(0.22, 0.55), (0.50, 0.30), (0.76, 0.70)]
        for (yf, knobX) in rows {
            let cy = h * yf
            // Дорожка слайдера
            p.move(to: CGPoint(x: w * 0.08, y: cy))
            p.addLine(to: CGPoint(x: w * 0.92, y: cy))
            // Кружок-ручка
            let kx = w * knobX
            p.addEllipse(in: CGRect(x: kx - w * 0.08, y: cy - h * 0.10,
                                    width: w * 0.16, height: h * 0.20))
        }
        return p
    }
}
