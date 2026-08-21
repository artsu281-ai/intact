import SwiftUI

// MARK: - Библиотека иконок Intact
//
// Каждая иконка живёт в `IconArt` отдельной функцией и читается как чертёж:
// координаты — буквальные числа на сетке 24×24, роли слоёв заданы явно.
// Правила сетки и ролей — в `IconSystem.swift`.
//
// Чтобы добавить иконку: заведите case в `IntactIconKind`, напишите функцию
// в `IconArt` и свяжите их в `layers(unit:)`. Компилятор поймает пропуск.

enum IntactIconKind: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    // Разделы приложения
    case home           // домашний экран
    case voice          // диктовка (микрофон)
    case briefs         // брифы и заметки
    case models         // каталог моделей
    case settingsPage   // экран настроек
    case about          // о программе

    // Чат с ИИ
    case chat           // диалог
    case send           // отправить
    case stop           // остановить генерацию
    case aiStar         // ответ ассистента
    case user           // реплика пользователя
    case context        // источники контекста
    case clearChat      // очистить диалог
    case plus           // новый диалог

    // Брифы
    case quickSummary   // сводка за сегодня
    case quickTasks     // извлечь задачи
    case quickNotes     // сводка заметок
    case export         // выгрузка
    case report         // отчёт

    // История
    case history        // журнал записей
    case eye            // просмотр записи
    case copy           // скопировать
    case copied         // скопировано
    case clearHour      // за последний час
    case clearToday     // за сегодня
    case clearWeek      // старше 7 дней
    case clearAll       // всю историю

    // Модели и хранилище
    case download       // скачать
    case refresh        // проверить обновления
    case update         // обновить
    case disk           // занято на диске
    case folder         // папка на диске
    case radioOn        // активная модель
    case radioOff       // неактивная модель

    // Состояния
    case success        // выполнено
    case error          // ошибка
    case warning        // предупреждение
    case reminder       // напоминание создано
    case clipboardReady // текст готов к вставке
    case lock           // приватность

    // Голос и HUD
    case voicePulse     // идёт запись
    case waveform       // идёт распознавание

    // Управление
    case settings       // параметры (шестерня)
    case search         // поиск
    case close          // закрыть
    case chevronUp
    case chevronDown
    case chevronLeft   // пара к chevronRight: направленный набор держим полным
    case chevronRight
    case keyboard       // горячая клавиша
    case textScale      // масштаб текста: ждёт масштабируемой типографики
}

extension IntactIconKind {
    /// Контуры иконки на сетке 24×24, пересчитанные в `unit` за клетку.
    func layers(unit u: CGFloat) -> [IconLayer] {
        switch self {
        case .home:           return IconArt.home(u)
        case .voice:          return IconArt.voice(u)
        case .briefs:         return IconArt.briefs(u)
        case .models:         return IconArt.models(u)
        case .settingsPage:   return IconArt.settingsPage(u)
        case .about:          return IconArt.about(u)

        case .chat:           return IconArt.chat(u)
        case .send:           return IconArt.send(u)
        case .stop:           return IconArt.stop(u)
        case .aiStar:         return IconArt.aiStar(u)
        case .user:           return IconArt.user(u)
        case .context:        return IconArt.context(u)
        case .clearChat:      return IconArt.clearChat(u)
        case .plus:           return IconArt.plus(u)

        case .quickSummary:   return IconArt.quickSummary(u)
        case .quickTasks:     return IconArt.quickTasks(u)
        case .quickNotes:     return IconArt.quickNotes(u)
        case .export:         return IconArt.export(u)
        case .report:         return IconArt.report(u)

        case .history:        return IconArt.history(u)
        case .eye:            return IconArt.eye(u)
        case .copy:           return IconArt.copy(u)
        case .copied:         return IconArt.copied(u)
        case .clearHour:      return IconArt.clearHour(u)
        case .clearToday:     return IconArt.clearDate(u, digit: .one)
        case .clearWeek:      return IconArt.clearDate(u, digit: .seven)
        case .clearAll:       return IconArt.clearAll(u)

        case .download:       return IconArt.download(u)
        case .refresh:        return IconArt.refresh(u)
        case .update:         return IconArt.update(u)
        case .disk:           return IconArt.disk(u)
        case .folder:         return IconArt.folder(u)
        case .radioOn:        return IconArt.radio(u, on: true)
        case .radioOff:       return IconArt.radio(u, on: false)

        case .success:        return IconArt.success(u)
        case .error:          return IconArt.error(u)
        case .warning:        return IconArt.warning(u)
        case .reminder:       return IconArt.reminder(u)
        case .clipboardReady: return IconArt.clipboardReady(u)
        case .lock:           return IconArt.lock(u)

        case .voicePulse:     return IconArt.voicePulse(u)
        case .waveform:       return IconArt.waveform(u)

        case .settings:       return IconArt.settings(u)
        case .search:         return IconArt.search(u)
        case .close:          return IconArt.close(u)
        case .chevronUp:      return IconArt.chevron(u, .up)
        case .chevronDown:    return IconArt.chevron(u, .down)
        case .chevronLeft:    return IconArt.chevron(u, .left)
        case .chevronRight:   return IconArt.chevron(u, .right)
        case .keyboard:       return IconArt.keyboard(u)
        case .textScale:      return IconArt.textScale(u)
        }
    }
}

// MARK: - Чертежи

enum IconArt {

    // MARK: Разделы

    /// Дом: замкнутый пятиугольник силуэта, дверь отдельным слоём.
    static func home(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in
                p.polyline([(3.5, 10.2), (12, 3.6), (20.5, 10.2), (20.5, 20.4), (3.5, 20.4)], closed: true)
            }),
            .primary(iconPath(unit: u) { p in
                p.polyline([(9.3, 20.4), (9.3, 13.8), (14.7, 13.8), (14.7, 20.4)])
            })
        ]
    }

    /// Микрофон: капсула несёт смысл, подвес и стойка — поддержка.
    static func voice(_ u: CGFloat) -> [IconLayer] {
        [
            .primary(iconPath(unit: u) { p in
                p.rect(8.6, 3, 6.8, 12, radius: 3.4)
            }),
            .secondary(iconPath(unit: u) { p in
                p.arc(12, 12.4, radius: 5.6, from: 0, to: 180)
                p.move(12, 18)
                p.line(12, 20.5)
                p.move(8.2, 20.5)
                p.line(15.8, 20.5)
            })
        ]
    }

    /// Лист с искрой — материал, который прошёл через ИИ.
    static func briefs(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(sheet(u)),
            .primary(sparkle(u, cx: 11.8, cy: 14.6, radius: 3.4))
        ]
    }

    /// Изометрический стек: верхний слой активен, нижние — глубина.
    static func models(_ u: CGFloat) -> [IconLayer] {
        [
            .primary(iconPath(unit: u) { p in
                p.polyline([(12, 3.2), (20.5, 8), (12, 12.8), (3.5, 8)], closed: true)
            }),
            .secondary(iconPath(unit: u) { p in
                p.polyline([(3.5, 12), (12, 16.8), (20.5, 12)])
                p.polyline([(3.5, 16), (12, 20.8), (20.5, 16)])
            })
        ]
    }

    /// Три ползунка: рельсы — фон, ручки — плотные точки.
    static func settingsPage(_ u: CGFloat) -> [IconLayer] {
        let rails: [(y: CGFloat, knob: CGFloat)] = [(6.5, 15.0), (12.0, 8.5), (17.5, 16.8)]
        return [
            .secondary(iconPath(unit: u) { p in
                for rail in rails {
                    p.move(3.5, rail.y)
                    p.line(20.5, rail.y)
                }
            }),
            .solid(iconPath(unit: u) { p in
                for rail in rails { p.circle(rail.knob, rail.y, radius: 2.4) }
            })
        ]
    }

    static func about(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in p.circle(12, 12, radius: 8.6) }),
            .solid(iconPath(unit: u) { p in p.circle(12, 7.9, radius: 1.0) }),
            .primary(iconPath(unit: u) { p in
                p.move(12, 11.2)
                p.line(12, 16.6)
            })
        ]
    }

    // MARK: Чат

    /// Пузырь с хвостом одним замкнутым контуром — линия хвоста не пересекает
    /// низ пузыря, как это происходит при наложении двух отдельных фигур.
    static func chat(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in
                p.move(7, 4)
                p.line(17, 4)
                p.corner(via: 21, 4, to: 21, 8, radius: 4)
                p.line(21, 13.5)
                p.corner(via: 21, 17.5, to: 17, 17.5, radius: 4)
                p.line(11.4, 17.5)
                p.line(4.9, 21.2)
                p.line(6.9, 17.5)
                p.corner(via: 3, 17.5, to: 3, 13.5, radius: 4)
                p.line(3, 8)
                p.corner(via: 3, 4, to: 7, 4, radius: 4)
                p.close()
            }),
            .solid(iconPath(unit: u) { p in
                for x in [CGFloat(8.5), 12, 15.5] { p.circle(x, 10.75, radius: 1.05) }
            })
        ]
    }

    /// Стрелка без обрамления: кнопка отправки сама круглая, и собственное
    /// кольцо у иконки давало кольцо внутри кольца.
    static func send(_ u: CGFloat) -> [IconLayer] {
        [.primary(iconPath(unit: u) { p in
            p.move(12, 20)
            p.line(12, 4.6)
            p.polyline([(5.4, 11.2), (12, 4.6), (18.6, 11.2)])
        })]
    }

    /// «Стоп» обязан быть плотным: контурный квадрат на 14 px читается как пауза.
    static func stop(_ u: CGFloat) -> [IconLayer] {
        [.solid(iconPath(unit: u) { p in p.rect(7, 7, 10, 10, radius: 2.6) })]
    }

    static func aiStar(_ u: CGFloat) -> [IconLayer] {
        [.primary(sparkle(u, cx: 12, cy: 12, radius: 8.5))]
    }

    /// Голова и плечи: между ними намеренный зазор, иначе на 11 px сливаются.
    static func user(_ u: CGFloat) -> [IconLayer] {
        [
            .primary(iconPath(unit: u) { p in p.circle(12, 8.4, radius: 4.1) }),
            .secondary(iconPath(unit: u) { p in p.arc(12, 21, radius: 7.6, from: 180, to: 360) })
        ]
    }

    /// Скрепка с единым радиусом разворотов — две вертикали и два полукруга.
    static func context(_ u: CGFloat) -> [IconLayer] {
        [
            .primary(iconPath(unit: u) { p in
                p.move(16.2, 9.6)
                p.line(16.2, 16.4)
                p.arc(12.2, 16.4, radius: 4, from: 0, to: 180, connected: true)
                p.line(8.2, 8.6)
                p.arc(10.7, 8.6, radius: 2.5, from: 180, to: 360, connected: true)
                p.line(13.2, 17)
            })
        ]
    }

    static func plus(_ u: CGFloat) -> [IconLayer] {
        [.primary(iconPath(unit: u) { p in
            p.move(12, 4.6); p.line(12, 19.4)
            p.move(4.6, 12); p.line(19.4, 12)
        })]
    }

    /// Метла: ручка — смысл, голова и ворс — поддержка.
    static func clearChat(_ u: CGFloat) -> [IconLayer] {
        [
            .primary(iconPath(unit: u) { p in
                p.move(18, 4.5)
                p.line(11.5, 11)
            }),
            .secondary(iconPath(unit: u) { p in
                p.polyline([(9.0, 8.5), (14.0, 13.5), (10.1, 17.4), (5.1, 12.4)], closed: true)
                p.move(10.7, 10.2)
                p.line(6.8, 14.1)
                p.move(12.3, 11.8)
                p.line(8.4, 15.7)
            })
        ]
    }

    // MARK: Брифы

    /// Молния одним простым многоугольником — без самопересечений.
    static func quickSummary(_ u: CGFloat) -> [IconLayer] {
        [.primary(iconPath(unit: u) { p in
            p.polyline([(13, 3), (6.5, 13.2), (11.4, 13.2), (10.6, 20.5), (17.5, 10.8), (12.6, 10.8)], closed: true)
        })]
    }

    static func quickTasks(_ u: CGFloat) -> [IconLayer] {
        let rows: [CGFloat] = [7.8, 16.6]
        return [
            .primary(iconPath(unit: u) { p in
                for y in rows { p.polyline([(3.4, y), (5.8, y + 2.4), (10.4, y - 2.6)]) }
            }),
            .secondary(iconPath(unit: u) { p in
                for y in rows {
                    p.move(13.0, y)
                    p.line(20.6, y)
                }
            })
        ]
    }

    static func quickNotes(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(sheet(u)),
            .primary(iconPath(unit: u) { p in
                p.move(8, 12.2);  p.line(16, 12.2)
                p.move(8, 16.4);  p.line(13.4, 16.4)
            })
        ]
    }

    /// Выгрузка: лоток принимает, стрелка уходит наружу.
    static func export(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in
                p.move(4, 14.75)
                p.line(4, 18.15)
                p.corner(via: 4, 20, to: 5.85, 20, radius: 1.85)
                p.line(18.15, 20)
                p.corner(via: 20, 20, to: 20, 18.15, radius: 1.85)
                p.line(20, 14.75)
            }),
            .primary(iconPath(unit: u) { p in
                p.move(12, 15.4)
                p.line(12, 4)
                p.polyline([(7.7, 8.3), (12, 4), (16.3, 8.3)])
            })
        ]
    }

    static func report(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(sheet(u)),
            .primary(iconPath(unit: u) { p in
                p.move(8.4, 17.6);  p.line(8.4, 14.2)
                p.move(12, 17.6);   p.line(12, 10.8)
                p.move(15.6, 17.6); p.line(15.6, 12.8)
            })
        ]
    }

    // MARK: История

    /// Циферблат со стрелками. Метафора отката живёт в `clearHour` —
    /// две стрелки сразу на 15 px превращаются в кашу.
    static func history(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in p.circle(12, 12, radius: 8.5) }),
            .primary(iconPath(unit: u) { p in
                p.move(12, 6.8)
                p.line(12, 12)
                p.line(15.8, 13.8)
            })
        ]
    }

    static func eye(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in
                p.move(3.2, 12)
                p.quad(control: 12, 4.4, to: 20.8, 12)
                p.quad(control: 12, 19.6, to: 3.2, 12)
                p.close()
            }),
            .primary(iconPath(unit: u) { p in p.circle(12, 12, radius: 2.7) })
        ]
    }

    /// Два листа без пересечений: задний нарисован только видимым фрагментом.
    static func copy(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in
                p.move(7.5, 7.5)
                p.line(7.5, 6.5)
                p.corner(via: 7.5, 3.5, to: 10.5, 3.5, radius: 3)
                p.line(17.5, 3.5)
                p.corner(via: 20.5, 3.5, to: 20.5, 6.5, radius: 3)
                p.line(20.5, 13.5)
                p.corner(via: 20.5, 16.5, to: 17.5, 16.5, radius: 3)
                p.line(16.5, 16.5)
            }),
            .primary(iconPath(unit: u) { p in p.rect(3.5, 7.5, 13, 13, radius: 3) })
        ]
    }

    static func copied(_ u: CGFloat) -> [IconLayer] {
        [.primary(iconPath(unit: u) { p in
            p.polyline([(4.5, 12.5), (9.5, 17.5), (19.5, 6.5)])
        })]
    }

    /// Часы с откатом: разрыв циферблата закрыт стрелкой против хода.
    static func clearHour(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in p.arc(12, 12.8, radius: 7.6, from: -55, to: 230) }),
            .primary(iconPath(unit: u) { p in
                p.polyline([(13.6, 5.7), (16.36, 6.57), (15.7, 9.4)])
                p.move(12, 12.8)
                p.line(12, 8.6)
                p.move(12, 12.8)
                p.line(15.0, 14.3)
            })
        ]
    }

    enum CalendarDigit { case one, seven }

    /// Календарь с цифрой. Кольца упираются в верхний край листа, а не
    /// протыкают его: пересечения в контурной иконке дают лишнюю засечку.
    static func clearDate(_ u: CGFloat, digit: CalendarDigit) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in
                p.rect(3.6, 5.2, 16.8, 15.6, radius: 3.4)
                p.move(3.6, 9.6)
                p.line(20.4, 9.6)
                p.move(8.4, 3.2);  p.line(8.4, 5.2)
                p.move(15.6, 3.2); p.line(15.6, 5.2)
            }),
            .primary(iconPath(unit: u) { p in
                switch digit {
                case .one:
                    p.polyline([(9.8, 13.8), (12.0, 12.0), (12.0, 19.2)])
                    p.move(9.4, 19.2)
                    p.line(14.6, 19.2)
                case .seven:
                    p.polyline([(9.0, 12.4), (15.2, 12.4), (10.6, 19.4)])
                }
            })
        ]
    }

    static func clearAll(_ u: CGFloat) -> [IconLayer] {
        [
            .primary(iconPath(unit: u) { p in
                p.polyline([(5.9, 6.6), (7.1, 20.6), (16.9, 20.6), (18.1, 6.6)])
            }),
            .secondary(iconPath(unit: u) { p in
                p.move(3.8, 6.6)
                p.line(20.2, 6.6)
                p.polyline([(9.2, 6.6), (9.2, 4.4), (14.8, 4.4), (14.8, 6.6)])
                p.move(10.2, 10.4); p.line(10.2, 17.0)
                p.move(13.8, 10.4); p.line(13.8, 17.0)
            })
        ]
    }

    // MARK: Модели и хранилище

    static func download(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in p.circle(12, 12, radius: 8.6) }),
            .primary(iconPath(unit: u) { p in
                p.move(12, 7)
                p.line(12, 15.4)
                p.polyline([(8.4, 11.8), (12, 15.4), (15.6, 11.8)])
            })
        ]
    }

    /// Одна дуга с наконечником — «проверить заново».
    static func refresh(_ u: CGFloat) -> [IconLayer] {
        [.primary(iconPath(unit: u) { p in
            p.arc(12, 12, radius: 7.8, from: -35, to: 255)
            p.polyline([(18.6, 3.8), (18.2, 7.4), (14.7, 6.6)])
        })]
    }

    /// Две встречные дуги — «обновить до новой версии».
    /// Намеренно отличается от `refresh`: это разные действия.
    static func update(_ u: CGFloat) -> [IconLayer] {
        [.primary(iconPath(unit: u) { p in
            p.arc(12, 12, radius: 7.6, from: 200, to: 340)
            p.polyline([(16.6, 9.0), (19.3, 9.5), (18.9, 12.2)])
            p.arc(12, 12, radius: 7.6, from: 20, to: 160)
            p.polyline([(7.4, 15.0), (4.7, 14.5), (5.1, 11.8)])
        })]
    }

    static func disk(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in
                p.rect(3.2, 6.4, 17.6, 11.2, radius: 3.2)
                p.move(3.2, 12.4); p.line(20.8, 12.4)
            }),
            .primary(iconPath(unit: u) { p in
                p.move(6.6, 15.4); p.line(13.0, 15.4)
            }),
            .solid(iconPath(unit: u) { p in p.circle(17.2, 15.4, radius: 1.25) })
        ]
    }

    static func folder(_ u: CGFloat) -> [IconLayer] {
        [.secondary(iconPath(unit: u) { p in
            p.move(3.4, 18.2)
            p.line(3.4, 6.6)
            p.corner(via: 3.4, 5.4, to: 4.6, 5.4, radius: 1.2)
            p.line(8.6, 5.4)
            p.line(10.8, 8.0)
            p.line(19.4, 8.0)
            p.corner(via: 20.6, 8.0, to: 20.6, 9.2, radius: 1.2)
            p.line(20.6, 18.2)
            p.corner(via: 20.6, 19.4, to: 19.4, 19.4, radius: 1.2)
            p.line(4.6, 19.4)
            p.corner(via: 3.4, 19.4, to: 3.4, 18.2, radius: 1.2)
            p.close()
        })]
    }

    /// Радиокнопка с одинаковой оптической массой в обоих состояниях —
    /// строки списка не «прыгают» при переключении.
    static func radio(_ u: CGFloat, on: Bool) -> [IconLayer] {
        var layers: [IconLayer] = [
            .secondary(iconPath(unit: u) { p in p.circle(12, 12, radius: 8) })
        ]
        if on {
            layers.append(.solid(iconPath(unit: u) { p in p.circle(12, 12, radius: 3.8) }))
        }
        return layers
    }

    // MARK: Состояния

    static func success(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in p.circle(12, 12, radius: 8.6) }),
            .tinted(.success, iconPath(unit: u) { p in
                p.polyline([(7.6, 12.3), (10.7, 15.4), (16.5, 8.9)])
            })
        ]
    }

    static func error(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in p.circle(12, 12, radius: 8.6) }),
            .tinted(.danger, iconPath(unit: u) { p in
                p.move(12, 7.4)
                p.line(12, 12.9)
            }),
            .tintedSolid(.danger, iconPath(unit: u) { p in p.circle(12, 16.1, radius: 1.05) })
        ]
    }

    static func warning(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in
                p.polyline([(12, 3.9), (21, 19.6), (3, 19.6)], closed: true)
            }),
            .tinted(.warning, iconPath(unit: u) { p in
                p.move(12, 9.6)
                p.line(12, 14.4)
            }),
            .tintedSolid(.warning, iconPath(unit: u) { p in p.circle(12, 17.1, radius: 1.0) })
        ]
    }

    /// Колокол с бейджем. Бейдж — отдельный тонированный слой, поэтому
    /// в сайдбаре и меню-баре он гасится вместе с остальной семантикой.
    static func reminder(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in
                p.move(5.2, 16.6)
                p.line(18.8, 16.6)
                p.move(6.6, 16.6)
                p.line(6.6, 11.6)
                p.arc(12, 11.6, radius: 5.4, from: 180, to: 360, connected: true)
                p.line(17.4, 16.6)
            }),
            .primary(iconPath(unit: u) { p in p.arc(12, 17.0, radius: 2.2, from: 0, to: 180) }),
            .tintedSolid(.warning, iconPath(unit: u) { p in p.circle(18.2, 6.2, radius: 2.6) })
        ]
    }

    /// Планшет: прищепка упирается в верхний край доски, общая линия —
    /// не пересечение.
    static func clipboardReady(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in
                p.rect(4.6, 6.2, 14.8, 14.4, radius: 3.2)
                p.rect(9, 3.2, 6, 3, radius: 1.5)
            }),
            .primary(iconPath(unit: u) { p in
                p.polyline([(8.6, 13.4), (11.2, 16.0), (15.6, 10.6)])
            })
        ]
    }

    static func lock(_ u: CGFloat) -> [IconLayer] {
        [
            .secondary(iconPath(unit: u) { p in
                p.move(7.9, 10.5)
                p.line(7.9, 9.6)
                p.arc(12, 9.6, radius: 4.1, from: 180, to: 360, connected: true)
                p.line(16.1, 10.5)
            }),
            .primary(iconPath(unit: u) { p in p.rect(4.6, 10.5, 14.8, 9.9, radius: 3) }),
            .solid(iconPath(unit: u) { p in p.circle(12, 14.4, radius: 1.15) })
        ]
    }

    // MARK: Голос и HUD

    /// Микрофон в эфире: две волны расходятся от капсулы.
    static func voicePulse(_ u: CGFloat) -> [IconLayer] {
        [
            .primary(iconPath(unit: u) { p in
                p.rect(9.2, 3.6, 5.6, 10.4, radius: 2.8)
                p.move(12, 16.4)
                p.line(12, 19.8)
            }),
            .secondary(iconPath(unit: u) { p in
                p.arc(12, 11.6, radius: 4.8, from: 0, to: 180)
                p.arc(12, 11.6, radius: 7.8, from: 22, to: 158)
            })
        ]
    }

    static func waveform(_ u: CGFloat) -> [IconLayer] {
        let bars: [(x: CGFloat, half: CGFloat)] = [
            (4.4, 3.4), (8.2, 6.2), (12, 8.6), (15.8, 6.2), (19.6, 3.4)
        ]
        return [.primary(iconPath(unit: u) { p in
            for bar in bars {
                p.move(bar.x, 12 - bar.half)
                p.line(bar.x, 12 + bar.half)
            }
        })]
    }

    // MARK: Управление

    /// Шестерня с настоящими зубцами: дуги по вершине и впадине,
    /// а не прямые лучи, которые читаются как цветок.
    static func settings(_ u: CGFloat) -> [IconLayer] {
        let outer: CGFloat = 8.6, root: CGFloat = 6.7
        return [
            .secondary(iconPath(unit: u) { p in
                for i in 0..<8 {
                    let a = CGFloat(i) * 45
                    p.arc(12, 12, radius: outer, from: a - 13, to: a + 13, connected: i > 0)
                    let inStart = p.polar(12, 12, radius: root, angle: a + 18)
                    p.line(inStart.0, inStart.1)
                    p.arc(12, 12, radius: root, from: a + 18, to: a + 27, connected: true)
                    let outStart = p.polar(12, 12, radius: outer, angle: a + 32)
                    p.line(outStart.0, outStart.1)
                }
                p.close()
            }),
            .primary(iconPath(unit: u) { p in p.circle(12, 12, radius: 3.1) })
        ]
    }

    static func search(_ u: CGFloat) -> [IconLayer] {
        [.primary(iconPath(unit: u) { p in
            p.circle(10.5, 10.5, radius: 6.2)
            p.move(14.9, 14.9)
            p.line(20.2, 20.2)
        })]
    }

    static func close(_ u: CGFloat) -> [IconLayer] {
        [.primary(iconPath(unit: u) { p in
            p.move(6.5, 6.5);  p.line(17.5, 17.5)
            p.move(17.5, 6.5); p.line(6.5, 17.5)
        })]
    }

    enum ChevronDirection { case up, down, left, right }

    static func chevron(_ u: CGFloat, _ direction: ChevronDirection) -> [IconLayer] {
        [.primary(iconPath(unit: u) { p in
            switch direction {
            case .down:  p.polyline([(6.5, 9.5), (12, 15), (17.5, 9.5)])
            case .up:    p.polyline([(6.5, 14.5), (12, 9), (17.5, 14.5)])
            case .right: p.polyline([(9.5, 6.5), (15, 12), (9.5, 17.5)])
            case .left:  p.polyline([(14.5, 6.5), (9, 12), (14.5, 17.5)])
            }
        })]
    }

    static func keyboard(_ u: CGFloat) -> [IconLayer] {
        let columns: [CGFloat] = [7.4, 12.0, 16.6]
        return [
            .secondary(iconPath(unit: u) { p in p.rect(2.8, 6.2, 18.4, 11.6, radius: 2.8) }),
            .solid(iconPath(unit: u) { p in
                for x in columns { p.circle(x, 10.4, radius: 1.15) }
            }),
            .primary(iconPath(unit: u) { p in
                p.move(7.6, 14.6)
                p.line(16.4, 14.6)
            })
        ]
    }

    static func textScale(_ u: CGFloat) -> [IconLayer] {
        [
            .primary(iconPath(unit: u) { p in
                p.polyline([(3.6, 19.4), (9.0, 5.6), (14.4, 19.4)])
                p.move(5.6, 14.6)
                p.line(12.4, 14.6)
            }),
            .secondary(iconPath(unit: u) { p in
                p.polyline([(15.4, 19.4), (18.1, 12.2), (20.8, 19.4)])
                p.move(16.4, 16.8)
                p.line(19.8, 16.8)
            })
        ]
    }

    // MARK: Общие детали

    /// Лист с загнутым уголком — общая подложка для брифов, заметок и отчётов.
    private static func sheet(_ u: CGFloat) -> Path {
        iconPath(unit: u) { p in
            p.polyline([(5, 3.5), (14.5, 3.5), (19, 8), (19, 20.5), (5, 20.5)], closed: true)
            p.polyline([(14.5, 3.5), (14.5, 8), (19, 8)])
        }
    }

    /// Четырёхлучевая искра с вогнутыми сторонами — фирменный знак ИИ.
    private static func sparkle(_ u: CGFloat, cx: CGFloat, cy: CGFloat, radius r: CGFloat) -> Path {
        let waist = r * 0.13
        return iconPath(unit: u) { p in
            p.move(cx, cy - r)
            p.quad(control: cx + waist, cy - waist, to: cx + r, cy)
            p.quad(control: cx + waist, cy + waist, to: cx, cy + r)
            p.quad(control: cx - waist, cy + waist, to: cx - r, cy)
            p.quad(control: cx - waist, cy - waist, to: cx, cy - r)
            p.close()
        }
    }
}
