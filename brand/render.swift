// Draws Kookout's logo files from the real letter outlines of Archivo (Black, widest), so nothing depends on a
// font being installed. Run from the repo root:  swift brand/render.swift
//
// Writes:
//   ios/Kookout/Assets.xcassets/AppIcon.appiconset/  icon-1024.png, icon-dark-1024.png, icon-tinted-1024.png
//   brand/kookout-wordmark-navy.svg, brand/kookout-wordmark-white.svg   (KOOKOUT, the O's "looking out")
//   brand/kookout-mark.svg                                             (the two O's alone)
//   apple-touch-icon.png (180 px) and brand/favicon-64.png, for the web page
//
// The look: the two O's are eyes looking out: an orange dot in each, both shifted the same way
// (right and a little up), 0.15 em across.

import AppKit
import CoreText
import Foundation

let navy = CGColor(red: 0x0E / 255, green: 0x2A / 255, blue: 0x3B / 255, alpha: 1)
let orange = CGColor(red: 1, green: 0x6B / 255, blue: 0x2C / 255, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let nearBlack = CGColor(red: 0x05 / 255, green: 0x12 / 255, blue: 0x1A / 255, alpha: 1)

// MARK: - The font: Archivo at weight 900, width 125

func archivo(size: CGFloat) -> CTFont {
    let url = URL(fileURLWithPath: "brand/fonts/Archivo[wdth,wght].ttf")
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
          let base = descriptors.first else { fatalError("Can't read \(url.path)") }
    let tag = { (s: String) in s.utf8.reduce(0) { $0 << 8 | Int($1) } }
    let variation = [tag("wght"): 900, tag("wdth"): 125] as CFDictionary
    let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: variation] as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

/// The letters of `text` as one path (y up, baseline at 0), the bounds of each glyph, and the font size.
struct Letters {
    let path: CGPath
    let glyphBounds: [CGRect]
    let size: CGFloat
}

func letters(_ text: String, size: CGFloat, tracking: CGFloat = 0.01) -> Letters {
    let font = archivo(size: size)
    let attributed = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTKernAttributeName as String): tracking * size,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let path = CGMutablePath()
    var bounds: [CGRect] = []
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for (glyph, position) in zip(glyphs, positions) {
            guard let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { bounds.append(.null); continue }
            let move = CGAffineTransform(translationX: position.x, y: position.y)
            path.addPath(outline, transform: move)
            bounds.append(outline.boundingBoxOfPath.applying(move))
        }
    }
    return Letters(path: path, glyphBounds: bounds, size: size)
}

/// The "looking out" dot in an O: right of centre by 0.08 em and up by 0.05 em, 0.15 em across.
func dot(in o: CGRect, size: CGFloat) -> CGRect {
    let d = 0.15 * size
    return CGRect(x: o.midX + 0.08 * size - d / 2, y: o.midY + 0.05 * size - d / 2, width: d, height: d)
}

// MARK: - App icons

func icon(background: CGColor, letters color: CGColor, dots: CGColor, to file: String, pixels: Int = 1024) {
    let oo = letters("OO", size: 1000, tracking: 0)
    let box = oo.path.boundingBoxOfPath
    let scale = CGFloat(pixels) * 0.70 / box.width // the two O's fill 70% of the width
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(background)
    context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    // Centre the letters' outline (not the line box) in the square.
    context.translateBy(x: CGFloat(pixels) / 2, y: CGFloat(pixels) / 2)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -box.midX, y: -box.midY)
    context.addPath(oo.path)
    context.setFillColor(color)
    context.fillPath()
    context.setFillColor(dots)
    for o in oo.glyphBounds { context.fillEllipse(in: dot(in: o, size: oo.size)) }
    let image = context.makeImage()!
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: file))
    print("wrote \(file)")
}

// MARK: - SVG wordmarks

func svgPath(_ path: CGPath, flipHeight: CGFloat, offset: CGPoint) -> String {
    var d = ""
    let f = { (p: CGPoint) in String(format: "%.1f %.1f", p.x - offset.x, flipHeight - (p.y - offset.y)) }
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: d += "M\(f(e.points[0]))"
        case .addLineToPoint: d += "L\(f(e.points[0]))"
        case .addQuadCurveToPoint: d += "Q\(f(e.points[0])) \(f(e.points[1]))"
        case .addCurveToPoint: d += "C\(f(e.points[0])) \(f(e.points[1])) \(f(e.points[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

func svg(_ text: String, dotIndexes: [Int], letterColor: String, dotColor: String, to file: String) {
    let word = letters(text, size: 100)
    let box = word.path.boundingBoxOfPath.insetBy(dx: -2, dy: -2)
    let height = box.height
    let origin = CGPoint(x: box.minX, y: box.minY)
    var out = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(String(format: "%.1f", box.width)) \(String(format: "%.1f", height))" role="img" aria-label="Kookout">
    <path fill="\(letterColor)" d="\(svgPath(word.path, flipHeight: height, offset: origin))"/>

    """
    for i in dotIndexes {
        let c = dot(in: word.glyphBounds[i], size: word.size)
        out += String(format: "<circle fill=\"%@\" cx=\"%.1f\" cy=\"%.1f\" r=\"%.1f\"/>\n",
                      dotColor, c.midX - origin.x, height - (c.midY - origin.y), c.width / 2)
    }
    out += "</svg>\n"
    try! out.write(toFile: file, atomically: true, encoding: .utf8)
    print("wrote \(file)")
}

let icons = "ios/Kookout/Assets.xcassets/AppIcon.appiconset"
try! FileManager.default.createDirectory(atPath: icons, withIntermediateDirectories: true)
icon(background: navy, letters: white, dots: orange, to: "\(icons)/icon-1024.png")
icon(background: nearBlack, letters: orange, dots: white, to: "\(icons)/icon-dark-1024.png")
icon(background: CGColor(gray: 0, alpha: 1), letters: CGColor(gray: 0.9, alpha: 1), dots: CGColor(gray: 0.55, alpha: 1),
     to: "\(icons)/icon-tinted-1024.png")
icon(background: navy, letters: white, dots: orange, to: "apple-touch-icon.png", pixels: 180)
icon(background: navy, letters: white, dots: orange, to: "brand/favicon-64.png", pixels: 64)

svg("KOOKOUT", dotIndexes: [1, 2], letterColor: "#0E2A3B", dotColor: "#FF6B2C", to: "brand/kookout-wordmark-navy.svg")
svg("KOOKOUT", dotIndexes: [1, 2], letterColor: "#FFFFFF", dotColor: "#FF6B2C", to: "brand/kookout-wordmark-white.svg")
svg("OO", dotIndexes: [0, 1], letterColor: "#0E2A3B", dotColor: "#FF6B2C", to: "brand/kookout-mark.svg")
