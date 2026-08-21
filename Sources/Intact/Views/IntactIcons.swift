import SwiftUI

// MARK: - Intact Custom Icon Library
// Все иконки отрисовываются через векторные Path и всегда рендерятся через stroke,
// поэтому никогда не заливаются сплошным цветом и идеально адаптируются к любой теме.

enum IntactIconKind: CaseIterable {
    case chat           // диалог с ИИ
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
    // Разделы UX
    case home           // домашний экран (домик)
    case voice          // диктовка (микрофон)
    case briefs         // брифы и заметки (листы со звёздочкой)
    case models         // каталог моделей (стек 3D слоёв)
    case settingsPage   // единый экран настроек (слайдеры)
    case about          // о программе (круг с i)
    // Утилитарные иконки
    case search         // лупа
    case warning        // предупреждение
    case lock           // замок / приватность
    case user           // пользователь (силуэт)
    case close          // крестик / закрыть
    case chevronDown    // шеврон вниз
    // Опции очистки истории
    case clearHour      // за последний час (часы со стрелкой отката)
    case clearToday     // за сегодня (календарь с цифрой 1)
    case clearWeek      // старше 7 дней (календарь с цифрой 7)
    case clearAll       // всю историю (мусорная корзина)
}

extension IntactIconKind {
    var shape: any Shape {
        switch self {
        case .chat:          return ChatIconShape()
        case .history:       return HistoryIconShape()
        case .send:          return SendIconShape()
        case .clearChat:     return ClearChatIconShape()
        case .copy:          return CopyIconShape()
        case .copied:        return CopiedIconShape()
        case .context:       return ContextIconShape()
        case .aiStar:        return AIStarIconShape()
        case .quickSummary:  return QuickSummaryIconShape()
        case .quickTasks:    return QuickTasksIconShape()
        case .quickNotes:    return QuickNotesIconShape()
        case .settings:      return SettingsIconShape()
        case .statusDot:     return StatusDotShape()
        case .stop:          return StopIconShape()
        case .home:          return HomeIconShape()
        case .voice:         return VoiceIconShape()
        case .briefs:        return BriefsIconShape()
        case .models:        return ModelsIconShape()
        case .settingsPage:  return SettingsPageIconShape()
        case .about:         return AboutIconShape()
        case .search:        return SearchIconShape()
        case .warning:       return WarningIconShape()
        case .lock:          return LockIconShape()
        case .user:          return UserIconShape()
        case .close:         return CloseIconShape()
        case .chevronDown:   return ChevronDownIconShape()
        case .clearHour:     return ClearHourIconShape()
        case .clearToday:    return ClearTodayIconShape()
        case .clearWeek:     return ClearWeekIconShape()
        case .clearAll:      return ClearAllIconShape()
        }
    }
}

/// Универсальный рендерер кастомной векторной иконки Intact.
/// Всегда рендерится через контурный stroke с поддержкой .foregroundStyle().
struct IntactIcon: View {
    let kind: IntactIconKind
    var size: CGFloat = 16
    var strokeWidth: CGFloat? = nil

    private var effectiveStrokeWidth: CGFloat {
        strokeWidth ?? max(1.2, size * 0.08)
    }

    var body: some View {
        Canvas { ctx, sz in
            let rect = CGRect(origin: .zero, size: sz)
            let path = kind.shape.path(in: rect)
            ctx.stroke(path,
                       with: .foreground,
                       style: StrokeStyle(lineWidth: effectiveStrokeWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

/// Рендерит кастомную иконку для бокового меню (сайдбара).
struct SidebarIntactIcon: View {
    let kind: IntactIconKind
    let selected: Bool
    var size: CGFloat = 16

    var body: some View {
        IntactIcon(kind: kind, size: size, strokeWidth: selected ? 1.4 : 1.2)
            .foregroundStyle(selected ? Palette.accent : Palette.textSecondary)
    }
}

// MARK: - 1. Chat (два пузыря диалога)
struct ChatIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Большой пузырь слева
        let br: CGFloat = w * 0.16
        let bx = w * 0.06, by = h * 0.08
        let bw = w * 0.64, bh = h * 0.52
        p.addRoundedRect(in: CGRect(x: bx, y: by, width: bw, height: bh),
                         cornerSize: CGSize(width: br, height: br))
        // Хвост большого пузыря
        p.move(to: CGPoint(x: bx + w * 0.10, y: by + bh))
        p.addLine(to: CGPoint(x: bx + w * 0.04, y: by + bh + h * 0.14))
        p.addLine(to: CGPoint(x: bx + w * 0.24, y: by + bh))

        // Маленький пузырь справа-снизу
        let sr: CGFloat = w * 0.14
        let sx = w * 0.48, sy = h * 0.44
        let sw = w * 0.46, sh = h * 0.42
        p.addRoundedRect(in: CGRect(x: sx, y: sy, width: sw, height: sh),
                         cornerSize: CGSize(width: sr, height: sr))
        // Хвост маленького пузыря
        p.move(to: CGPoint(x: sx + sw - w * 0.24, y: sy + sh))
        p.addLine(to: CGPoint(x: sx + sw - w * 0.04, y: sy + sh + h * 0.12))
        p.addLine(to: CGPoint(x: sx + sw - w * 0.10, y: sy + sh))
        return p
    }
}

// MARK: - 2. History (часы со стрелкой отката)
struct HistoryIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w * 0.50, cy = h * 0.50, r = min(w, h) * 0.42
        var p = Path()
        // Циферблат с разрывом сверху
        p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                 startAngle: .degrees(-65), endAngle: .degrees(245), clockwise: false)
        // Стрелка против часовой стрелки на конце разрыва
        let ax = cx + cos(Double(-65) * .pi / 180) * r
        let ay = cy + sin(Double(-65) * .pi / 180) * r
        p.move(to: CGPoint(x: ax - w * 0.14, y: ay - h * 0.02))
        p.addLine(to: CGPoint(x: ax, y: ay))
        p.addLine(to: CGPoint(x: ax - w * 0.02, y: ay + h * 0.14))

        // Стрелки часов (10:10)
        p.move(to: CGPoint(x: cx, y: cy))
        p.addLine(to: CGPoint(x: cx, y: cy - r * 0.60))
        p.move(to: CGPoint(x: cx, y: cy))
        p.addLine(to: CGPoint(x: cx + r * 0.45, y: cy + r * 0.15))
        return p
    }
}

// MARK: - 3. Send (стрелка вверх в круге)
struct SendIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w * 0.50, cy = h * 0.50, r = min(w, h) * 0.44
        var p = Path()
        p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        // Стрелка вверх
        p.move(to: CGPoint(x: cx, y: cy + r * 0.45))
        p.addLine(to: CGPoint(x: cx, y: cy - r * 0.45))
        // Наконечник
        p.move(to: CGPoint(x: cx - w * 0.22, y: cy - r * 0.10))
        p.addLine(to: CGPoint(x: cx, y: cy - r * 0.45))
        p.addLine(to: CGPoint(x: cx + w * 0.22, y: cy - r * 0.10))
        return p
    }
}

// MARK: - 4. ClearChat (метла)
struct ClearChatIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Ручка
        p.move(to: CGPoint(x: w * 0.76, y: h * 0.12))
        p.addLine(to: CGPoint(x: w * 0.38, y: h * 0.52))
        // Перетяжка
        p.move(to: CGPoint(x: w * 0.28, y: h * 0.46))
        p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.58))
        // Ворс
        p.move(to: CGPoint(x: w * 0.30, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.88))
        p.move(to: CGPoint(x: w * 0.38, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.90))
        p.move(to: CGPoint(x: w * 0.46, y: h * 0.56))
        p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.88))
        // Низ ворса
        p.move(to: CGPoint(x: w * 0.08, y: h * 0.88))
        p.addLine(to: CGPoint(x: w * 0.46, y: h * 0.88))
        return p
    }
}

// MARK: - 5. Copy (два наложенных листа)
struct CopyIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let cr: CGFloat = w * 0.10
        // Задний лист
        p.addRoundedRect(in: CGRect(x: w * 0.30, y: h * 0.10, width: w * 0.58, height: h * 0.65),
                         cornerSize: CGSize(width: cr, height: cr))
        // Передний лист
        p.addRoundedRect(in: CGRect(x: w * 0.12, y: h * 0.25, width: w * 0.58, height: h * 0.65),
                         cornerSize: CGSize(width: cr, height: cr))
        return p
    }
}

// MARK: - 6. Copied (галочка подтверждения)
struct CopiedIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.15, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.78))
        p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.24))
        return p
    }
}

// MARK: - 7. Context (скрепка)
struct ContextIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.42, y: h * 0.70))
        p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.35))
        p.addArc(center: CGPoint(x: w * 0.55, y: h * 0.35), radius: w * 0.13,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.65))
        p.addArc(center: CGPoint(x: w * 0.50, y: h * 0.65), radius: w * 0.18,
                 startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.28))
        p.addArc(center: CGPoint(x: w * 0.54, y: h * 0.28), radius: w * 0.22,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.60))
        return p
    }
}

// MARK: - 8. AI Star (четырёхлучевая звезда ассистента)
struct AIStarIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w * 0.50, cy = h * 0.50
        var p = Path()
        let points = 8
        let rOuter = min(w, h) * 0.48
        let rInner = rOuter * 0.32
        for i in 0..<points {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let r = i % 2 == 0 ? rOuter : rInner
            let pt = CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
            if i == 0 { p.move(to: pt) }
            else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - 9. Quick Summary (молния)
struct QuickSummaryIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.56, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.92))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.44))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.44))
        p.closeSubpath()
        return p
    }
}

// MARK: - 10. Quick Tasks (чеклист с галочками)
struct QuickTasksIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Рамка блокнота
        p.addRoundedRect(in: CGRect(x: w * 0.12, y: h * 0.10, width: w * 0.76, height: h * 0.80),
                         cornerSize: CGSize(width: w * 0.10, height: w * 0.10))
        // 3 строки чеклиста
        for i in 0..<3 {
            let y = h * (0.30 + CGFloat(i) * 0.20)
            // Чекбокс
            p.move(to: CGPoint(x: w * 0.24, y: y))
            p.addLine(to: CGPoint(x: w * 0.32, y: y + h * 0.06))
            p.addLine(to: CGPoint(x: w * 0.40, y: y - h * 0.04))
            // Линия задачи
            p.move(to: CGPoint(x: w * 0.48, y: y))
            p.addLine(to: CGPoint(x: w * 0.76, y: y))
        }
        return p
    }
}

// MARK: - 11. Quick Notes (листок с загнутым уголком)
struct QuickNotesIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let fold = w * 0.22
        // Контур листа
        p.move(to: CGPoint(x: w * 0.15, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.85 - fold, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.08 + fold))
        p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.92))
        p.addLine(to: CGPoint(x: w * 0.15, y: h * 0.92))
        p.closeSubpath()
        // Сгиб
        p.move(to: CGPoint(x: w * 0.85 - fold, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.85 - fold, y: h * 0.08 + fold))
        p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.08 + fold))
        // Строки текста
        for i in 0..<3 {
            let y = h * (0.38 + CGFloat(i) * 0.16)
            p.move(to: CGPoint(x: w * 0.28, y: y))
            p.addLine(to: CGPoint(x: w * 0.72, y: y))
        }
        return p
    }
}

// MARK: - 12. Settings (шестерня)
struct SettingsIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w * 0.50, cy = h * 0.50
        var p = Path()
        let teeth = 6
        let rOut = min(w, h) * 0.44
        let rIn = rOut * 0.65
        for i in 0..<(teeth * 2) {
            let a = Double(i) * .pi / Double(teeth) - .pi / 2
            let r = i % 2 == 0 ? rOut : rIn
            let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
            if i == 0 { p.move(to: pt) }
            else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        // Внутренний круг
        p.addEllipse(in: CGRect(x: cx - rIn * 0.40, y: cy - rIn * 0.40, width: rIn * 0.80, height: rIn * 0.80))
        return p
    }
}

// MARK: - 13. StatusDot
struct StatusDotShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect)
    }
}

// MARK: - 14. Stop (квадрат остановки)
struct StopIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22),
             cornerRadius: rect.width * 0.08)
    }
}

// MARK: - 15. Home (домик)
struct HomeIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Крыша
        p.move(to: CGPoint(x: w * 0.10, y: h * 0.48))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.12))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.48))
        // Стены
        p.move(to: CGPoint(x: w * 0.18, y: h * 0.48))
        p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.90))
        p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.90))
        p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.48))
        // Дверь
        p.move(to: CGPoint(x: w * 0.38, y: h * 0.90))
        p.addLine(to: CGPoint(x: w * 0.38, y: h * 0.60))
        p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.60))
        p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.90))
        return p
    }
}

// MARK: - 16. Voice (микрофон)
struct VoiceIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w * 0.50
        var p = Path()
        // Капсула
        let mw = w * 0.28, mh = h * 0.46
        p.addRoundedRect(in: CGRect(x: cx - mw / 2, y: h * 0.08, width: mw, height: mh),
                         cornerSize: CGSize(width: mw / 2, height: mw / 2))
        // Дуга подвеса
        p.addArc(center: CGPoint(x: cx, y: h * 0.50), radius: w * 0.30,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        // Ножка
        p.move(to: CGPoint(x: cx, y: h * 0.80))
        p.addLine(to: CGPoint(x: cx, y: h * 0.92))
        // Подставка
        p.move(to: CGPoint(x: cx - w * 0.22, y: h * 0.92))
        p.addLine(to: CGPoint(x: cx + w * 0.22, y: h * 0.92))
        return p
    }
}

// MARK: - 17. Briefs (лист с мини-звездой)
struct BriefsIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let fold = w * 0.22
        // Лист
        p.move(to: CGPoint(x: w * 0.14, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.86 - fold, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.08 + fold))
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.92))
        p.addLine(to: CGPoint(x: w * 0.14, y: h * 0.92))
        p.closeSubpath()
        // Уголок
        p.move(to: CGPoint(x: w * 0.86 - fold, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.86 - fold, y: h * 0.08 + fold))
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.08 + fold))
        // Мини-звезда
        let sx = w * 0.50, sy = h * 0.56, r = w * 0.16
        p.move(to: CGPoint(x: sx, y: sy - r))
        p.addLine(to: CGPoint(x: sx, y: sy + r))
        p.move(to: CGPoint(x: sx - r, y: sy))
        p.addLine(to: CGPoint(x: sx + r, y: sy))
        return p
    }
}

// MARK: - 18. Models (изометрический стек 3D-слоёв)
struct ModelsIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let cx = w * 0.50
        // Верхний ромб
        p.move(to: CGPoint(x: cx, y: h * 0.10))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.28))
        p.addLine(to: CGPoint(x: cx, y: h * 0.46))
        p.addLine(to: CGPoint(x: w * 0.12, y: h * 0.28))
        p.closeSubpath()
        // Средний слой
        p.move(to: CGPoint(x: w * 0.12, y: h * 0.48))
        p.addLine(to: CGPoint(x: cx, y: h * 0.66))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.48))
        // Нижний слой
        p.move(to: CGPoint(x: w * 0.12, y: h * 0.68))
        p.addLine(to: CGPoint(x: cx, y: h * 0.86))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.68))
        return p
    }
}

// MARK: - 19. SettingsPage (горизонтальные слайдеры)
struct SettingsPageIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let rows: [(CGFloat, CGFloat)] = [(0.24, 0.60), (0.50, 0.35), (0.76, 0.70)]
        for (yf, knobX) in rows {
            let cy = h * yf
            p.move(to: CGPoint(x: w * 0.10, y: cy))
            p.addLine(to: CGPoint(x: w * 0.90, y: cy))
            let kx = w * knobX
            p.addEllipse(in: CGRect(x: kx - w * 0.08, y: cy - h * 0.10, width: w * 0.16, height: h * 0.20))
        }
        return p
    }
}

// MARK: - 20. About (круг с буквой i)
struct AboutIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w * 0.50, cy = h * 0.50, r = min(w, h) * 0.44
        var p = Path()
        p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        // Точка
        p.addEllipse(in: CGRect(x: cx - w * 0.04, y: cy - h * 0.24, width: w * 0.08, height: h * 0.08))
        // Палочка
        p.move(to: CGPoint(x: cx, y: cy - h * 0.06))
        p.addLine(to: CGPoint(x: cx, y: cy + h * 0.22))
        return p
    }
}

// MARK: - 21. Search (лупа)
struct SearchIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let r = w * 0.28
        let cx = w * 0.40, cy = h * 0.40
        p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        let rad = 45.0 * .pi / 180.0
        let sx = cx + cos(rad) * r
        let sy = cy + sin(rad) * r
        p.move(to: CGPoint(x: sx, y: sy))
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.86))
        return p
    }
}

// MARK: - 22. Warning (треугольник с «!»)
struct WarningIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.50, y: h * 0.10))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.88))
        p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.88))
        p.closeSubpath()
        // Восклицательный знак
        p.move(to: CGPoint(x: w * 0.50, y: h * 0.36))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.60))
        p.addEllipse(in: CGRect(x: w * 0.46, y: h * 0.70, width: w * 0.08, height: h * 0.08))
        return p
    }
}

// MARK: - 23. Lock (замок)
struct LockIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w * 0.50
        var p = Path()
        // Дужка
        p.addArc(center: CGPoint(x: cx, y: h * 0.38), radius: w * 0.20,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: cx + w * 0.20, y: h * 0.48))
        // Корпус
        p.addRoundedRect(in: CGRect(x: w * 0.18, y: h * 0.48, width: w * 0.64, height: h * 0.44),
                         cornerSize: CGSize(width: w * 0.08, height: w * 0.08))
        // Скважина
        p.move(to: CGPoint(x: cx, y: h * 0.62))
        p.addLine(to: CGPoint(x: cx, y: h * 0.74))
        return p
    }
}

// MARK: - 24. User (силуэт)
struct UserIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w * 0.50
        var p = Path()
        let hr = w * 0.20
        p.addEllipse(in: CGRect(x: cx - hr, y: h * 0.08, width: hr * 2, height: hr * 2))
        p.addArc(center: CGPoint(x: cx, y: h * 0.90), radius: w * 0.35,
                 startAngle: .degrees(190), endAngle: .degrees(350), clockwise: false)
        return p
    }
}

// MARK: - 25. Close (крестик)
struct CloseIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.22, y: h * 0.22))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.78))
        p.move(to: CGPoint(x: w * 0.78, y: h * 0.22))
        p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.78))
        return p
    }
}

// MARK: - 26. ChevronDown
struct ChevronDownIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.15, y: h * 0.35))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.70))
        p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.35))
        return p
    }
}

// MARK: - 27. ClearHour (Часы со стрелкой назад — 1 час)
struct ClearHourIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w * 0.50, cy = h * 0.52, r = min(w, h) * 0.40
        var p = Path()
        // Циферблат со срезом сверху-справа
        p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                 startAngle: .degrees(-70), endAngle: .degrees(230), clockwise: false)
        // Стрелка отката против часовой стрелки
        let ax = cx + cos(Double(-70) * .pi / 180) * r
        let ay = cy + sin(Double(-70) * .pi / 180) * r
        p.move(to: CGPoint(x: ax - w * 0.14, y: ay - h * 0.02))
        p.addLine(to: CGPoint(x: ax, y: ay))
        p.addLine(to: CGPoint(x: ax - w * 0.02, y: ay + h * 0.14))
        // Стрелки на циферблате: часовая на 1 час (30°), минутная на 12 (0°)
        p.move(to: CGPoint(x: cx, y: cy))
        p.addLine(to: CGPoint(x: cx, y: cy - r * 0.62))
        p.move(to: CGPoint(x: cx, y: cy))
        p.addLine(to: CGPoint(x: cx + r * 0.40, y: cy - r * 0.28))
        return p
    }
}

// MARK: - 28. ClearToday (Календарь с цифрой 1 — сегодня)
struct ClearTodayIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Лист календаря
        p.addRoundedRect(in: CGRect(x: w * 0.12, y: h * 0.14, width: w * 0.76, height: h * 0.76),
                         cornerSize: CGSize(width: w * 0.12, height: w * 0.12))
        // Разделитель шапки
        p.move(to: CGPoint(x: w * 0.12, y: h * 0.38))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.38))
        // Люверсы / кольца сверху
        p.move(to: CGPoint(x: w * 0.32, y: h * 0.06))
        p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.20))
        p.move(to: CGPoint(x: w * 0.68, y: h * 0.06))
        p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.20))
        // Чёткая цифра «1»
        p.move(to: CGPoint(x: w * 0.42, y: h * 0.56))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.48))
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.78))
        p.move(to: CGPoint(x: w * 0.38, y: h * 0.78))
        p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.78))
        return p
    }
}

// MARK: - 29. ClearWeek (Календарь с цифрой 7 — за неделю)
struct ClearWeekIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Лист календаря
        p.addRoundedRect(in: CGRect(x: w * 0.12, y: h * 0.14, width: w * 0.76, height: h * 0.76),
                         cornerSize: CGSize(width: w * 0.12, height: w * 0.12))
        // Разделитель шапки
        p.move(to: CGPoint(x: w * 0.12, y: h * 0.38))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.38))
        // Люверсы / кольца сверху
        p.move(to: CGPoint(x: w * 0.32, y: h * 0.06))
        p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.20))
        p.move(to: CGPoint(x: w * 0.68, y: h * 0.06))
        p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.20))
        // Чёткая цифра «7»
        p.move(to: CGPoint(x: w * 0.36, y: h * 0.48))
        p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.48))
        p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.78))
        // Поперечная черточка семёрки
        p.move(to: CGPoint(x: w * 0.45, y: h * 0.63))
        p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.63))
        return p
    }
}

// MARK: - 30. ClearAll (Мусорная корзина / полный сброс)
struct ClearAllIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Ручка крышки
        p.move(to: CGPoint(x: w * 0.38, y: h * 0.20))
        p.addLine(to: CGPoint(x: w * 0.38, y: h * 0.10))
        p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.10))
        p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.20))
        // Крышка
        p.move(to: CGPoint(x: w * 0.14, y: h * 0.20))
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.20))
        // Корпус бака
        p.move(to: CGPoint(x: w * 0.22, y: h * 0.20))
        p.addLine(to: CGPoint(x: w * 0.27, y: h * 0.88))
        p.addLine(to: CGPoint(x: w * 0.73, y: h * 0.88))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.20))
        // Продольные линии
        p.move(to: CGPoint(x: w * 0.40, y: h * 0.34))
        p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.74))
        p.move(to: CGPoint(x: w * 0.60, y: h * 0.34))
        p.addLine(to: CGPoint(x: w * 0.60, y: h * 0.74))
        return p
    }
}
