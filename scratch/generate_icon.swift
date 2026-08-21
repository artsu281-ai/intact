import AppKit
import CoreGraphics

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    exit(1)
}

ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

// MARK: - 1. Внешняя геометрия (macOS Squircle)
let margin: CGFloat = 100
let iconRect = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
let cornerRadius: CGFloat = 185
let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Тень иконки
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 48, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
ctx.addPath(squirclePath)
ctx.setFillColor(CGColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1.0))
ctx.fillPath()
ctx.restoreGState()

// Базовый темный титановый градиент
ctx.saveGState()
ctx.addPath(squirclePath)
ctx.clip()

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bgColors = [
    CGColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1.0),
    CGColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1.0),
    CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0)
] as CFArray
let bgLocations: [CGFloat] = [0.0, 0.5, 1.0]
if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
    ctx.drawLinearGradient(bgGradient, start: CGPoint(x: size/2, y: size - margin), end: CGPoint(x: size/2, y: margin), options: [])
}

// Фоновое неоновое свечение в центре
let glowColors = [
    CGColor(red: 0.38, green: 0.40, blue: 0.95, alpha: 0.28),
    CGColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.15),
    CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
] as CFArray
if let radialGlow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.45, 1.0]) {
    ctx.drawRadialGradient(radialGlow, startCenter: CGPoint(x: size/2, y: size/2), startRadius: 20, endCenter: CGPoint(x: size/2, y: size/2), endRadius: 360, options: [])
}

// MARK: - 2. Центральный стеклянный диск с ободом
let discRadius: CGFloat = 220
let discCenter = CGPoint(x: size/2, y: size/2)
let discRect = CGRect(x: discCenter.x - discRadius, y: discCenter.y - discRadius, width: discRadius * 2, height: discRadius * 2)

// Тень под диском
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 32, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
ctx.addEllipse(in: discRect)
ctx.setFillColor(CGColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 0.85))
ctx.fillPath()
ctx.restoreGState()

// Ободок диска с градиентной обводкой
let discBorderColors = [
    CGColor(red: 0.45, green: 0.50, blue: 0.65, alpha: 0.45),
    CGColor(red: 0.20, green: 0.22, blue: 0.30, alpha: 0.20),
    CGColor(red: 0.60, green: 0.70, blue: 0.95, alpha: 0.35)
] as CFArray
if let discBorderGrad = CGGradient(colorsSpace: colorSpace, colors: discBorderColors, locations: [0.0, 0.5, 1.0]) {
    ctx.saveGState()
    ctx.addEllipse(in: discRect)
    ctx.setLineWidth(3.0)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(discBorderGrad, start: CGPoint(x: size/2, y: discRect.maxY), end: CGPoint(x: size/2, y: discRect.minY), options: [])
    ctx.restoreGState()
}

// MARK: - 3. Центральный футуристичный спектр / звуковая волна (5 неоновых столбиков)
let barWidth: CGFloat = 34
let barSpacing: CGFloat = 22
let barCorner: CGFloat = barWidth / 2
let barHeights: [CGFloat] = [120, 210, 290, 230, 140]
let totalWaveWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * barSpacing
let startX = (size - totalWaveWidth) / 2

let barGradColors = [
    CGColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 1.0),
    CGColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1.0),
    CGColor(red: 0.48, green: 0.35, blue: 0.98, alpha: 1.0),
    CGColor(red: 0.68, green: 0.25, blue: 0.90, alpha: 1.0)
] as CFArray
let barGrad = CGGradient(colorsSpace: colorSpace, colors: barGradColors, locations: [0.0, 0.35, 0.75, 1.0])!

for (i, h) in barHeights.enumerated() {
    let x = startX + CGFloat(i) * (barWidth + barSpacing)
    let y = size / 2 - h / 2
    let bRect = CGRect(x: x, y: y, width: barWidth, height: h)
    let bPath = CGPath(roundedRect: bRect, cornerWidth: barCorner, cornerHeight: barCorner, transform: nil)

    // Неоновое свечение столбика
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: CGColor(red: 0.45, green: 0.60, blue: 1.0, alpha: 0.65))
    ctx.addPath(bPath)
    ctx.setFillColor(CGColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Градиентное заполнение
    ctx.saveGState()
    ctx.addPath(bPath)
    ctx.clip()
    ctx.drawLinearGradient(barGrad, start: CGPoint(x: x, y: y + h), end: CGPoint(x: x, y: y), options: [])
    ctx.restoreGState()

    // Внутренний яркий световой блик на верхушке
    let capRect = CGRect(x: x + 6, y: y + h - barWidth + 6, width: barWidth - 12, height: barWidth - 12)
    ctx.saveGState()
    ctx.addEllipse(in: capRect)
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.75))
    ctx.fillPath()
    ctx.restoreGState()
}

// MARK: - 4. Верхний стеклянный световой отблеск и контурная рамка иконки
let highlightColors = [
    CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.35),
    CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08),
    CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
] as CFArray
if let highlightGrad = CGGradient(colorsSpace: colorSpace, colors: highlightColors, locations: [0.0, 0.25, 1.0]) {
    ctx.saveGState()
    ctx.drawLinearGradient(highlightGrad, start: CGPoint(x: size/2, y: size - margin), end: CGPoint(x: size/2, y: size/2), options: [])
    ctx.restoreGState()
}

ctx.restoreGState() // Снятие клиппинга сквиркла

// Внешний ободок иконки (границы Apple Squircle)
ctx.saveGState()
let borderGradColors = [
    CGColor(red: 0.55, green: 0.60, blue: 0.75, alpha: 0.45),
    CGColor(red: 0.25, green: 0.28, blue: 0.35, alpha: 0.20),
    CGColor(red: 0.15, green: 0.16, blue: 0.22, alpha: 0.35)
] as CFArray
if let borderGrad = CGGradient(colorsSpace: colorSpace, colors: borderGradColors, locations: [0.0, 0.5, 1.0]) {
    ctx.addPath(squirclePath)
    ctx.setLineWidth(4.0)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(borderGrad, start: CGPoint(x: size/2, y: size - margin), end: CGPoint(x: size/2, y: margin), options: [])
}
ctx.restoreGState()

image.unlockFocus()

// MARK: - Сохранение в PNG и создание .icns
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}

let outPngPath = "/Users/artsu/work_tree/voice/scratch/AppIcon_1024.png"
try! pngData.write(to: URL(fileURLWithPath: outPngPath))
print("Saved 1024x1024 PNG to:", outPngPath)
