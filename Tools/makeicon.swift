//
//  makeicon.swift
//  生成应用图标（1024×1024 PNG），供 iconutil 打包为 icns
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

let full = CGFloat(size)

// 圆角底：Windows 蓝渐变
let bgRect = CGRect(x: 52, y: 52, width: full - 104, height: full - 104)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 200, cornerHeight: 200, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let gradient = CGGradient(colorsSpace: space,
                          colors: [CGColor(red: 0.24, green: 0.55, blue: 0.92, alpha: 1),
                                   CGColor(red: 0.10, green: 0.36, blue: 0.72, alpha: 1)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: full), end: CGPoint(x: full, y: 0), options: [])
ctx.restoreGState()

// 纸张阴影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
let paperRect = CGRect(x: 226, y: 168, width: 572, height: 700)
let paperPath = CGPath(roundedRect: paperRect, cornerWidth: 34, cornerHeight: 34, transform: nil)
ctx.addPath(paperPath)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// 纸张右上折角
ctx.saveGState()
ctx.addPath(paperPath)
ctx.clip()
let fold = CGMutablePath()
fold.move(to: CGPoint(x: paperRect.maxX - 150, y: paperRect.maxY))
fold.addLine(to: CGPoint(x: paperRect.maxX, y: paperRect.maxY))
fold.addLine(to: CGPoint(x: paperRect.maxX, y: paperRect.maxY - 150))
fold.closeSubpath()
ctx.addPath(fold)
ctx.setFillColor(CGColor(red: 0.88, green: 0.93, blue: 1.0, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// 顶部标题条
ctx.saveGState()
ctx.addPath(paperPath)
ctx.clip()
ctx.setFillColor(CGColor(red: 0.16, green: 0.45, blue: 0.82, alpha: 1))
ctx.fill(CGRect(x: paperRect.minX, y: paperRect.maxY - 96, width: paperRect.width, height: 96))
// 三条白色短横线（“≡”）
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
for i in 0..<3 {
    let w: CGFloat = i == 2 ? 150 : 210
    ctx.fill(CGRect(x: paperRect.minX + 46, y: paperRect.maxY - 34 - CGFloat(i) * 24, width: w, height: 12))
}

// 正文行
ctx.setFillColor(CGColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1))
let widths: [CGFloat] = [420, 372, 440, 300, 396, 348, 430, 260, 410, 330]
var y = paperRect.maxY - 156
for w in widths {
    ctx.fill(CGRect(x: paperRect.minX + 46, y: y, width: w, height: 18))
    y -= 52
    if y < paperRect.minY + 40 { break }
}
ctx.restoreGState()

// 光标（呼应“文本编辑”）
ctx.setFillColor(CGColor(red: 0.98, green: 0.72, blue: 0.16, alpha: 1))
ctx.fill(CGRect(x: paperRect.minX + 46, y: paperRect.maxY - 156 - 52 * CGFloat(widths.count - 1), width: 8, height: 40))

guard let image = ctx.makeImage() else { exit(1) }
let outURL = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png")
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("icon written: \(outURL.path)")
