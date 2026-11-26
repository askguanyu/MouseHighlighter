// 生成 App 图标：swift Tools/make_icon.swift <输出目录>
// 输出 <输出目录>/AppIcon.icns（以及预览用的 AppIcon-1024.png）

import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// 在 1024×1024 的坐标系（左下原点）里绘制图标
func drawIcon(_ ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // 背景：macOS 图标网格（824pt 圆角方块，四周留 100pt）
    let bgRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bgPath)
    ctx.setFillColor(color(0x1B2233))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [color(0x323C55), color(0x141924)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // 光圈：填充 + 外圈 + 外发光（与 app 默认样式一致）
    func halo(center: CGPoint, radius: CGFloat, rgb: UInt32, fill: CGFloat, ring: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: radius * 0.35, color: color(rgb, 0.9))
        ctx.setFillColor(color(rgb, fill))
        ctx.fillEllipse(in: rect)
        ctx.restoreGState()
        ctx.setStrokeColor(color(rgb, ring))
        ctx.setLineWidth(radius * 0.07)
        ctx.strokeEllipse(in: rect.insetBy(dx: radius * 0.035, dy: radius * 0.035))
    }
    halo(center: CGPoint(x: 690, y: 330), radius: 125, rgb: 0xFF2626, fill: 0.40, ring: 0.85)
    let tip = CGPoint(x: 430, y: 610)
    halo(center: tip, radius: 235, rgb: 0xFFD900, fill: 0.35, ring: 0.90)
    ctx.restoreGState()

    // 鼠标指针：尖端位于黄色光圈中心
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4, 13.2), (6.8, 19.6), (9.4, 18.5), (6.7, 12.2), (12, 12.2)]
    let s: CGFloat = 19
    let arrow = CGMutablePath()
    for (i, p) in pts.enumerated() {
        let q = CGPoint(x: tip.x + p.0 * s, y: tip.y - p.1 * s)
        i == 0 ? arrow.move(to: q) : arrow.addLine(to: q)
    }
    arrow.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 6, height: -10), blur: 18, color: color(0x000000, 0.45))
    ctx.addPath(arrow)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.addPath(arrow)
    ctx.setStrokeColor(color(0x111111))
    ctx.setLineWidth(20)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.addPath(arrow)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
}

func render(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024).write(to: outDir.appendingPathComponent("AppIcon-1024.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "Wrote \(outDir.path)/AppIcon.icns" : "iconutil failed")
