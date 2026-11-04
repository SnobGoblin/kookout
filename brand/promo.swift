// Draws Kookout's cartoon promo for social media (9:16, 1080 × 1920, 30 fps, 25 s) frame by frame, with the
// brand's own swoosh. Run from the repo root:  swift -O brand/promo.swift [folder for check frames]
//
// Writes brand/promo/kookout-cartoon.mp4. With a folder, also writes a PNG of a few frames there, to look at.
// This is the animatic for the script in brand/promo/README.md: captions stand in for the narrator.
//
//   1. 0–3 s    80s title "THE WIND": "In a world… where the wind waits for no one…"
//   2. 3–8 s    Gary in a meeting; behind him, wings glide past the window. He turns round too late.
//   3. 8–12 s   Kai asleep in a hammock; "Home spot: Tomorrow 2–6 PM good" (swoosh); he lifts his sunglasses
//   4. 12–16 s  Kai fills in the details on his favourite sites (generic wind map, station, webcam)
//   5. 16–21 s  Kai and Gary out on the water at the home spot
//   6. 21–25 s  end card: the logo's eyes look left, right and back, as in the app's splash

import AppKit
import AVFoundation
import CoreText
import Foundation

let W: CGFloat = 1080, H: CGFloat = 1920
let fps: Int32 = 30
let duration: CGFloat = 25
let fade: CGFloat = 0.35                                  // crossfade between scenes
let swooshes: [Double] = [8.6, 21.1]                      // when the swoosh plays (s)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let navy = rgb(0x0E2A3B), orange = rgb(0xFF6B2C), orangeDark = rgb(0xD9531A), sea = rgb(0x1C6EA4)
let nearBlack = rgb(0x05121A), white = rgb(0xFFFFFF), skin = rgb(0xF1C9A5), skinShade = rgb(0xD9A983)
let green = rgb(0x2EA44F), wetsuit = rgb(0x12364C)

// MARK: - Font and logo (as in brand/render.swift)

var fonts: [String: CTFont] = [:]
func archivo(size: CGFloat, weight: Int = 900, width: Int = 100) -> CTFont {
    let key = "\(size) \(weight) \(width)"
    if let font = fonts[key] { return font }
    let url = URL(fileURLWithPath: "brand/fonts/Archivo[wdth,wght].ttf")
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
          let base = descriptors.first else { fatalError("Can't read \(url.path)") }
    let tag = { (s: String) in s.utf8.reduce(0) { $0 << 8 | Int($1) } }
    let variation = [tag("wght"): weight, tag("wdth"): width] as CFDictionary
    let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: variation] as CFDictionary)
    let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
    fonts[key] = font
    return font
}

struct Letters {
    let path: CGPath
    let glyphBounds: [CGRect]
    let size: CGFloat
}

func letters(_ text: String, size: CGFloat, tracking: CGFloat = 0.01) -> Letters {
    let font = archivo(size: size, weight: 900, width: 125)
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

func dot(in o: CGRect, size: CGFloat) -> CGRect {
    let d = 0.15 * size
    return CGRect(x: o.midX + 0.08 * size - d / 2, y: o.midY + 0.05 * size - d / 2, width: d, height: d)
}

let oo = letters("OO", size: 1000, tracking: 0)
let name = letters("KOOKOUT", size: 1000, tracking: 0.32)

/// Kookout's eyes (the logo's two O's) centred on `center`, `width` wide. `look` moves the pupils sideways in em
/// (0 = the logo's own "looking out"); `sclera` fills the O's holes (for a face).
func eyes(_ c: CGContext, _ center: CGPoint, width: CGFloat, look: CGFloat = 0, pupil: CGColor = white,
          sclera: CGColor? = nil) {
    let box = oo.path.boundingBoxOfPath, s = width / box.width
    c.saveGState()
    c.translateBy(x: center.x - box.midX * s, y: center.y - box.midY * s)
    c.scaleBy(x: s, y: s)
    if let sclera {
        for o in oo.glyphBounds { fill(c, sclera, CGPath(ellipseIn: o.insetBy(dx: o.width * 0.12, dy: o.height * 0.12), transform: nil)) }
    }
    fill(c, orange, oo.path)
    for o in oo.glyphBounds {
        fill(c, pupil, CGPath(ellipseIn: dot(in: o, size: oo.size).offsetBy(dx: look * oo.size, dy: 0), transform: nil))
    }
    c.restoreGState()
}

// MARK: - Helpers

func clamp(_ x: CGFloat) -> CGFloat { min(max(x, 0), 1) }
func ramp(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { clamp((t - a) / (b - a)) }
func smooth(_ x: CGFloat) -> CGFloat { let x = clamp(x); return x * x * (3 - 2 * x) }
func pop(_ x: CGFloat) -> CGFloat {                       // ease out with a little overshoot
    let x = clamp(x), k: CGFloat = 1.70158
    return 1 + (k + 1) * pow(x - 1, 3) + k * pow(x - 1, 2)
}
func mix(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { a + (b - a) * x }
func fract(_ x: CGFloat) -> CGFloat { x - floor(x) }
func noise(_ i: Int) -> CGFloat { fract(sin(CGFloat(i) * 12.9898) * 43758.5453) }
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

func fill(_ c: CGContext, _ color: CGColor, _ path: CGPath) {
    c.addPath(path); c.setFillColor(color); c.fillPath()
}
func rr(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
}
func circle(_ p: CGPoint, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r), transform: nil)
}
func ellipse(_ p: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: p.x - rx, y: p.y - ry, width: 2 * rx, height: 2 * ry), transform: nil)
}
func stroke(_ c: CGContext, _ color: CGColor, _ width: CGFloat, _ path: CGPath) {
    c.addPath(path); c.setStrokeColor(color); c.setLineWidth(width)
    c.setLineCap(.round); c.setLineJoin(.round); c.strokePath()
}
func polyline(_ points: CGPoint...) -> CGPath {
    let p = CGMutablePath(); p.addLines(between: points); return p
}
func curve(_ a: CGPoint, _ control: CGPoint, _ b: CGPoint) -> CGPath {
    let p = CGMutablePath(); p.move(to: a); p.addQuadCurve(to: b, control: control); return p
}

/// One line of text with its baseline at y; `align` 0 = left of x, 0.5 = centred, 1 = right. Shrinks to `maxWidth`.
/// `outline` draws a thick rim around the letters, cartoon style.
func text(_ c: CGContext, _ s: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: Int = 900, color: CGColor = white,
          outline: CGColor? = nil, align: CGFloat = 0.5, maxWidth: CGFloat = W - 120) {
    func line(_ size: CGFloat, stroke: Bool) -> CTLine {
        var a: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): archivo(size: size, weight: weight),
            .init(kCTForegroundColorAttributeName as String): color,
            .init(kCTKernAttributeName as String): outline == nil ? 0 : size * 0.02]
        if stroke, let outline {
            a[.init(kCTStrokeColorAttributeName as String)] = outline
            a[.init(kCTStrokeWidthAttributeName as String)] = 16
        }
        return CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: a))
    }
    var size = size
    let natural = CGFloat(CTLineGetTypographicBounds(line(size, stroke: false), nil, nil, nil))
    if natural > maxWidth { size = (size * maxWidth / natural).rounded(.down) }
    let body = line(size, stroke: false)
    let w = CGFloat(CTLineGetTypographicBounds(body, nil, nil, nil))
    c.saveGState()
    c.textMatrix = .identity
    c.setLineJoin(.round)
    if outline != nil {
        c.textPosition = P(x - w * align, y)
        CTLineDraw(line(size, stroke: true), c)
    }
    c.textPosition = P(x - w * align, y)
    CTLineDraw(body, c)
    c.restoreGState()
}

/// A caption across the top that pops in as `appear` goes from 0 to 1.
func caption(_ c: CGContext, _ s: String, y: CGFloat, size: CGFloat, appear: CGFloat, color: CGColor = white) {
    guard appear > 0 else { return }
    let k = pop(appear)
    c.saveGState()
    c.translateBy(x: W / 2, y: y + size * 0.35)
    c.scaleBy(x: k, y: k)
    c.setAlpha(clamp(appear * 3))
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    text(c, s, x: 0, y: -size * 0.35, size: size, color: color, outline: navy)
    c.endTransparencyLayer()
    c.restoreGState()
}

// MARK: - Characters

let kaiHair = rgb(0xE8C36A), garyHair = rgb(0x4A3426), shirt = rgb(0xCFE3F2), wood = rgb(0x6B4A33)
let pine = rgb(0x2F5D50)

enum Who { case kai, gary }
enum Mouth { case smile, flat, grin, o }

/// A face seen from the front, centred on `p`, head radius `r`. `lids` 0 = open, 1 = shut; `look` moves the pupils
/// (in eye radii); `shades` nil = none, 0 = over the eyes, 1 = pushed up on the forehead.
func face(_ c: CGContext, _ p: CGPoint, _ r: CGFloat, _ who: Who, lids: CGFloat = 0, look: CGPoint = .zero,
          mouth: Mouth = .smile, shades: CGFloat? = nil) {
    c.saveGState()
    c.translateBy(x: p.x, y: p.y)
    c.scaleBy(x: r / 100, y: r / 100)
    fill(c, skinShade, circle(P(-98, -5), 22))
    fill(c, skinShade, circle(P(98, -5), 22))
    fill(c, skin, circle(.zero, 100))
    c.saveGState()
    c.addPath(circle(.zero, 106)); c.clip()
    switch who {
    case .kai:                                           // shaggy blond fringe under an orange beanie
        let fringe = CGMutablePath()
        fringe.move(to: P(-110, 120))
        for i in 0...11 { fringe.addLine(to: P(-110 + CGFloat(i) * 20, i % 2 == 0 ? 30 : 52)) }
        fringe.addLine(to: P(120, 120)); fringe.closeSubpath()
        fill(c, kaiHair, fringe)
        fill(c, orange, CGPath(rect: CGRect(x: -110, y: 62, width: 220, height: 60), transform: nil))
        fill(c, orangeDark, rr(CGRect(x: -106, y: 50, width: 212, height: 30), 15))
    case .gary:                                          // short dark hair
        let hair = CGMutablePath()
        hair.move(to: P(-110, 120)); hair.addLine(to: P(-110, 30))
        hair.addQuadCurve(to: P(110, 40), control: P(0, 80))
        hair.addLine(to: P(110, 120)); hair.closeSubpath()
        fill(c, garyHair, hair)
    }
    c.restoreGState()
    for ex in [CGFloat(-36), 36] {
        let e = CGRect(x: ex - 24, y: -28, width: 48, height: 56)
        c.saveGState()
        c.addEllipse(in: e); c.clip()
        fill(c, white, CGPath(rect: e, transform: nil))
        fill(c, navy, circle(P(ex + look.x * 10, look.y * 12), 12))
        if lids > 0 {
            let lid = e.maxY - lids * e.height
            fill(c, skin, CGPath(rect: CGRect(x: e.minX, y: lid, width: e.width, height: e.maxY - lid), transform: nil))
            stroke(c, navy, 5, polyline(P(e.minX, lid), P(e.maxX, lid)))
        }
        c.restoreGState()
        stroke(c, navy, 4, CGPath(ellipseIn: e, transform: nil))
    }
    switch mouth {
    case .smile: stroke(c, navy, 7, curve(P(-30, -45), P(0, -75), P(30, -45)))
    case .flat: stroke(c, navy, 7, polyline(P(-22, -52), P(22, -52)))
    case .o: fill(c, navy, ellipse(P(0, -58), 14, 18))
    case .grin:
        let g = CGMutablePath()
        g.move(to: P(-36, -42)); g.addQuadCurve(to: P(36, -42), control: P(0, -98)); g.closeSubpath()
        fill(c, navy, g)
        c.saveGState(); c.addPath(g); c.clip()
        fill(c, white, CGPath(rect: CGRect(x: -40, y: -52, width: 80, height: 12), transform: nil))
        c.restoreGState()
    }
    if let shades {
        let y = mix(0, 78, smooth(shades))
        for ex in [CGFloat(-38), 38] {
            fill(c, rgb(0x111518), rr(CGRect(x: ex - 34, y: y - 22, width: 68, height: 46), 18))
            stroke(c, rgb(0xFFFFFF, 0.6), 4, polyline(P(ex - 20, y + 10), P(ex - 6, y + 14)))
        }
        stroke(c, rgb(0x111518), 6, polyline(P(-6, y + 6), P(6, y + 6)))
    }
    c.restoreGState()
}

/// A wing foiler seen from the side, flying left to right; (x, by) is the board's centre. `scale` 1 ≈ 600 px tall.
func foiler(_ c: CGContext, x: CGFloat, by: CGFloat, scale s: CGFloat, _ t: CGFloat, who: Who) {
    c.saveGState()
    c.translateBy(x: x, y: by)
    c.scaleBy(x: s, y: s)
    let wingColor = who == .kai ? orange : rgb(0xF2F5F7), wingEdge = who == .kai ? orangeDark : sea
    stroke(c, rgb(0x1D2329), 11, polyline(P(20, -12), P(20, -175)))
    fill(c, rgb(0x1D2329), ellipse(P(40, -176), 62, 10))
    c.saveGState()
    c.translateBy(x: 20, y: 515)
    c.rotate(by: -0.15 + 0.05 * sin(t * 1.7))
    let wing = CGMutablePath()
    wing.move(to: P(-270, -30))
    wing.addQuadCurve(to: P(270, -30), control: P(0, 200))
    wing.addQuadCurve(to: P(-270, -30), control: P(0, 70))
    fill(c, wingColor, wing)
    fill(c, rgb(0xC4E8F8, 0.75), ellipse(P(-110, 40), 46, 22))
    stroke(c, wingEdge, 28, curve(P(-270, -30), P(0, 200), P(270, -30)))
    stroke(c, wingEdge, 20, polyline(P(0, 85), P(0, 22)))
    c.restoreGState()
    fill(c, rgb(0x0B1E2A), rr(CGRect(x: -115, y: -13, width: 230, height: 26), 13))
    let legs = who == .kai ? navy : wetsuit
    stroke(c, legs, 34, polyline(P(-45, 14), P(-15, 82), P(5, 150)))
    stroke(c, legs, 34, polyline(P(45, 14), P(62, 86), P(5, 150)))
    let top = who == .kai ? skin : wetsuit
    stroke(c, top, 76, polyline(P(5, 150), P(20, 285)))
    if who == .kai { fill(c, navy, rr(CGRect(x: -34, y: 130, width: 80, height: 50), 20)) }   // board shorts
    else { fill(c, orange, rr(CGRect(x: -28, y: 185, width: 86, height: 104), 32)) }          // vest
    stroke(c, top, 26, polyline(P(20, 285), P(-30, 372), P(-62, 470)))
    stroke(c, top, 26, polyline(P(20, 285), P(62, 378), P(92, 465)))
    fill(c, skin, circle(P(-62, 472), 17))
    fill(c, skin, circle(P(92, 467), 17))
    let head = P(28, 350)
    fill(c, skin, circle(head, 46))
    c.saveGState()
    c.addPath(circle(head, 50)); c.clip()
    if who == .kai {
        fill(c, kaiHair, CGPath(rect: CGRect(x: head.x - 60, y: head.y - 4, width: 120, height: 70), transform: nil))
        fill(c, orange, CGPath(rect: CGRect(x: head.x - 60, y: head.y + 16, width: 120, height: 60), transform: nil))
    } else {
        fill(c, garyHair, CGPath(rect: CGRect(x: head.x - 60, y: head.y + 14, width: 120, height: 60), transform: nil))
    }
    c.restoreGState()
    fill(c, white, circle(P(head.x + 22, head.y - 6), 13))
    fill(c, navy, circle(P(head.x + 27, head.y - 6), 6))
    stroke(c, navy, 6, curve(P(head.x + 4, head.y - 24), P(head.x + 26, head.y - 46), P(head.x + 42, head.y - 24)))
    c.restoreGState()
}

func background(_ c: CGContext, _ color: CGColor) {
    fill(c, color, CGPath(rect: CGRect(x: 0, y: 0, width: W, height: H), transform: nil))
}

func gradient(_ c: CGContext, _ colors: [CGColor], from top: CGFloat, to bottom: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: nil)!
    c.drawLinearGradient(g, start: P(0, top), end: P(0, bottom), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func sparkle(_ c: CGContext, _ p: CGPoint, _ r: CGFloat, alpha: CGFloat) {
    guard alpha > 0 else { return }
    fill(c, rgb(0xFFFFFF, 0.35 * alpha), circle(p, r * 0.45))
    let star = CGMutablePath()
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4, d = i % 2 == 0 ? r : r * 0.12
        let q = P(p.x + d * cos(a), p.y + d * sin(a))
        if i == 0 { star.move(to: q) } else { star.addLine(to: q) }
    }
    star.closeSubpath()
    fill(c, rgb(0xFFFFFF, alpha), star)
}

// MARK: - Scene 1: 80s title, "In a world…"

func scene1(_ c: CGContext, _ t: CGFloat) {
    let horizon: CGFloat = 860
    gradient(c, [rgb(0x0B0420), rgb(0x4A1450)], from: H, to: horizon)
    // The sun, striped at the bottom
    c.saveGState()
    c.addRect(CGRect(x: 0, y: horizon, width: W, height: H)); c.clip()
    c.addPath(circle(P(540, horizon + 40), 300)); c.clip()
    gradient(c, [rgb(0xFFD45A), rgb(0xFF6B2C), rgb(0xFF4F7B)], from: horizon + 340, to: horizon)
    for i in 0..<6 {
        let y = horizon + 20 + CGFloat(i) * 34
        fill(c, rgb(0x3A1046), CGPath(rect: CGRect(x: 0, y: y, width: W, height: 14 - CGFloat(i) * 2), transform: nil))
    }
    c.restoreGState()
    // The grid, rolling towards us
    fill(c, rgb(0x12082A), CGPath(rect: CGRect(x: 0, y: 0, width: W, height: horizon), transform: nil))
    for i in -14...14 {
        stroke(c, rgb(0xFF4FA0, 0.7), 4, polyline(P(540 + CGFloat(i) * 20, horizon), P(540 + CGFloat(i) * 230, 0)))
    }
    for k in 0..<14 {
        let d = fract((CGFloat(k) + t * 1.5) / 14)
        let y = horizon - horizon * pow(d, 2.4)
        stroke(c, rgb(0xFF4FA0, 0.3 + 0.6 * d), 4, polyline(P(0, y), P(W, y)))
    }
    // Chrome title
    let title = letters("THE WIND", size: 1000, tracking: 0.04)
    let box = title.path.boundingBoxOfPath
    let k = mix(1.5, 1, pop(ramp(t, 0.1, 0.6))) * 880 / box.width
    if t > 0.1 {
        c.saveGState()
        c.setAlpha(clamp((t - 0.1) * 4))
        c.translateBy(x: 540 - box.midX * k, y: 1300 - box.midY * k)
        c.scaleBy(x: k, y: k)
        c.addPath(title.path); c.setStrokeColor(rgb(0xFF4FA0)); c.setLineWidth(70); c.setLineJoin(.round); c.strokePath()
        c.addPath(title.path); c.setStrokeColor(rgb(0x0B0420)); c.setLineWidth(30); c.strokePath()
        c.addPath(title.path); c.clip()
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [white, rgb(0x9FD3F5), rgb(0x1C3F66), rgb(0xFFB067), white] as CFArray,
                           locations: [0, 0.45, 0.5, 0.56, 1])!
        c.drawLinearGradient(g, start: P(0, box.maxY), end: P(0, box.minY), options: [])
        c.restoreGState()
    }
    let glint = ramp(t, 0.8, 1.6)
    sparkle(c, P(mix(160, 920, glint), 1390), 90, alpha: sin(glint * .pi))

    caption(c, "In a world…", y: 560, size: 84, appear: ramp(t, 0.6, 1.0))
    caption(c, "where the wind waits for no one…", y: 440, size: 64, appear: ramp(t, 1.3, 1.7), color: orange)
}

// MARK: - Scene 2: Gary in a meeting, the good wind behind him

func scene2(_ c: CGContext, _ t: CGFloat) {
    background(c, rgb(0xDDE3E6))
    // The window: a sunny fjord, wings gliding past
    let win = CGRect(x: 60, y: 760, width: 960, height: 740)
    fill(c, rgb(0xF4F6F7), rr(win.insetBy(dx: -24, dy: -24), 20))
    c.saveGState()
    c.addPath(rr(win, 8)); c.clip()
    gradient(c, [rgb(0x4FAEE6), rgb(0xC4E8F8)], from: win.maxY, to: 1000)
    fill(c, rgb(0xFFD45A), circle(P(880, 1380), 60))
    let hills = CGMutablePath()
    hills.move(to: P(60, 1000)); hills.addQuadCurve(to: P(560, 1000), control: P(300, 1110))
    hills.addQuadCurve(to: P(1020, 1000), control: P(800, 1070)); hills.closeSubpath()
    fill(c, rgb(0x4E8C7A), hills)
    fill(c, rgb(0x3A93C9), CGPath(rect: CGRect(x: 0, y: 0, width: W, height: 1002), transform: nil))
    for (i, start) in [0.2, 1.3, 2.3].enumerated() {
        let x = mix(-150, 1250, (t - CGFloat(start)) / 2.2)
        let by = 900 + CGFloat(i) * 25 + 6 * sin(t * 3 + CGFloat(i))
        foiler(c, x: x, by: by, scale: 0.28 - CGFloat(i) * 0.03, t, who: i == 1 ? .kai : .gary)
    }
    band(c, rgb(0x2A80B8), base: 880, amp: 6, k: 0.02, speed: 2.4, t)
    c.restoreGState()
    stroke(c, rgb(0xF4F6F7), 18, polyline(P(win.midX, win.minY), P(win.midX, win.maxY)))

    // Gary, bored, then turning round too late
    let turn = smooth(ramp(t, 3.3, 3.7))
    fill(c, shirt, rr(CGRect(x: 380, y: 480, width: 320, height: 360), 120))
    let tie = CGMutablePath()
    tie.addLines(between: [P(540, 820), P(515, 600), P(540, 560), P(565, 600)]); tie.closeSubpath()
    fill(c, navy, tie)
    fill(c, skin, CGPath(rect: CGRect(x: 510, y: 820, width: 60, height: 70), transform: nil))
    face(c, P(540 + turn * 30, 980), 125, .gary, lids: mix(0.45, 0, turn),
         look: P(mix(0, 0.9, turn), mix(-0.6, 0.6, turn)), mouth: turn > 0.5 ? .o : .flat)
    if turn > 0.5 {
        text(c, "!", x: 760, y: 1080, size: 140, color: orange, outline: navy)
    }
    // The meeting table, a laptop, coffee
    let table = CGMutablePath()
    table.addLines(between: [P(0, 0), P(0, 470), P(160, 600), P(920, 600), P(W, 470), P(W, 0)]); table.closeSubpath()
    fill(c, rgb(0x3B4A55), table)
    fill(c, rgb(0x9AA6AE), rr(CGRect(x: 370, y: 480, width: 340, height: 30), 10))
    fill(c, rgb(0xB8C2C8), rr(CGRect(x: 395, y: 505, width: 290, height: 190), 14))
    fill(c, white, rr(CGRect(x: 150, y: 470, width: 80, height: 90), 14))
    stroke(c, white, 12, CGPath(ellipseIn: CGRect(x: 215, y: 490, width: 40, height: 46), transform: nil))
    fill(c, skin, ellipse(P(330, 560), 60, 34))
    fill(c, skin, ellipse(P(750, 560), 60, 34))

    caption(c, "He checked the forecast", y: 1730, size: 96, appear: ramp(t, 0.3, 0.7))
    caption(c, "every morning.", y: 1610, size: 96, appear: ramp(t, 0.6, 1.0))
    caption(c, "The wind came in the afternoon.", y: 300, size: 70, appear: ramp(t, 2.2, 2.6), color: orange)
}

// MARK: - Scene 3: Kai in the hammock, the swoosh

func pineTree(_ c: CGContext, _ x: CGFloat, _ base: CGFloat) {
    fill(c, wood, rr(CGRect(x: x - 22, y: base, width: 44, height: 560), 18))
    for i in 0..<3 {
        let y = base + 380 + CGFloat(i) * 150, w = 240 - CGFloat(i) * 55
        let tri = CGMutablePath()
        tri.addLines(between: [P(x - w, y), P(x + w, y), P(x, y + 260)]); tri.closeSubpath()
        fill(c, pine, tri)
    }
}

func scene3(_ c: CGContext, _ t: CGFloat) {
    gradient(c, [rgb(0x4FAEE6), rgb(0xC4E8F8)], from: H, to: 900)
    fill(c, rgb(0x3A93C9), CGPath(rect: CGRect(x: 0, y: 0, width: W, height: 900), transform: nil))
    band(c, rgb(0x2F86BF), base: 860, amp: 8, k: 0.02, speed: 1.6, t)
    let edge = stride(from: CGFloat(0), through: W, by: 10).map { P($0, 700 + 20 * sin($0 * 0.006)) }
    let sand = CGMutablePath()
    sand.move(to: P(0, 0)); sand.addLines(between: edge); sand.addLine(to: P(W, 0)); sand.closeSubpath()
    fill(c, rgb(0xEAD6A8), sand)
    pineTree(c, 120, 180)
    pineTree(c, 960, 180)

    // Ropes and hammock, with Kai lying in it
    let sway = 10 * sin(t * 1.6)
    stroke(c, rgb(0x8C6B4A), 8, polyline(P(140, 640), P(250, 560 + sway)))
    stroke(c, rgb(0x8C6B4A), 8, polyline(P(940, 640), P(830, 560 + sway)))
    stroke(c, skin, 70, polyline(P(760, 520 + sway), P(820, 560 + sway)))         // legs, feet up
    fill(c, skin, ellipse(P(835, 575 + sway), 26, 36))
    fill(c, skin, ellipse(P(805, 590 + sway), 26, 36))
    let lift = ramp(t, 1.9, 2.4)
    c.saveGState()
    c.translateBy(x: 330, y: 590 + sway)
    c.rotate(by: 0.35)
    face(c, .zero, 95, .kai, lids: lift > 0.5 ? 0.35 : 1, look: P(0.3, -0.2),
         mouth: lift > 0.5 ? .grin : .smile, shades: lift)
    c.restoreGState()
    let hammock = CGMutablePath()
    hammock.move(to: P(250, 560 + sway))
    hammock.addQuadCurve(to: P(830, 560 + sway), control: P(540, 280 + sway))
    hammock.addQuadCurve(to: P(250, 560 + sway), control: P(540, 500 + sway))
    fill(c, sea, hammock)
    for i in 1..<4 {
        let f = CGFloat(i) / 4
        stroke(c, rgb(0xFFFFFF, 0.6), 8, curve(P(250 + 580 * f - 30, 540 + sway), P(250 + 580 * f, 470 + sway),
                                                P(250 + 580 * f + 10, 430 + sway - 40 * sin(f * .pi))))
    }
    // The phone on his belly, lighting up
    let lit = ramp(t, 0.6, 0.7)
    fill(c, rgb(0x111518), rr(CGRect(x: 520, y: 470 + sway, width: 70, height: 120), 14))
    fill(c, lit > 0 ? rgb(0xCFE8F7) : rgb(0x1D2329), rr(CGRect(x: 526, y: 478 + sway, width: 58, height: 104), 10))
    if lit > 0 {
        fill(c, rgb(0xFFFFFF, 0.25 * (1 + sin(t * 8)) / 2), circle(P(555, 530 + sway), 110))
    }

    // The notification, big, above
    let appear = ramp(t, 0.6, 0.95)
    if appear > 0 {
        let banner = CGRect(x: 120, y: 1040, width: 840, height: 250)
        let k = mix(0.5, 1, pop(appear))
        c.saveGState()
        c.translateBy(x: banner.midX, y: banner.midY); c.scaleBy(x: k, y: k); c.translateBy(x: -banner.midX, y: -banner.midY)
        c.setAlpha(clamp(appear * 2))
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        let tail = CGMutablePath()
        tail.addLines(between: [P(500, banner.minY + 10), P(580, banner.minY + 10), P(560, banner.minY - 120)]); tail.closeSubpath()
        fill(c, rgb(0xFFFFFF, 0.96), tail)
        fill(c, rgb(0xFFFFFF, 0.96), rr(banner, 56))
        let icon = CGRect(x: banner.minX + 34, y: banner.midY - 76, width: 152, height: 152)
        fill(c, navy, rr(icon, 36))
        eyes(c, P(icon.midX, icon.midY), width: 118)
        text(c, "Home spot", x: banner.minX + 216, y: banner.midY + 22, size: 62, weight: 800, color: rgb(0x111111), align: 0)
        text(c, "now", x: banner.maxX - 40, y: banner.midY + 22, size: 44, weight: 500, color: rgb(0x777777), align: 1)
        text(c, "Tomorrow 2–6 PM good", x: banner.minX + 216, y: banner.midY - 58, size: 54, weight: 500,
             color: rgb(0x222222), align: 0, maxWidth: banner.width - 250)
        c.endTransparencyLayer()
        c.restoreGState()
    }

    caption(c, "Kai…", y: 1730, size: 110, appear: ramp(t, 1.2, 1.5))
    caption(c, "just waited for the swoosh.", y: 1600, size: 90, appear: ramp(t, 1.9, 2.3), color: orange)
}

// MARK: - Scene 4: Kai fills in the details on his favourite sites

func card(_ c: CGContext, _ r: CGRect, _ kind: Int, _ t: CGFloat) {
    fill(c, white, rr(r, 36))
    c.saveGState()
    c.addPath(rr(r, 36)); c.clip()
    let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - 110)
    switch kind {
    case 0:                                              // a wind map
        fill(c, rgb(0xBFE3F5), CGPath(rect: body, transform: nil))
        let land = CGMutablePath()
        land.move(to: P(body.minX, body.minY + 120))
        land.addQuadCurve(to: P(body.minX + 220, body.maxY), control: P(body.minX + 260, body.midY))
        land.addLine(to: P(body.minX, body.maxY)); land.closeSubpath()
        fill(c, rgb(0xE6D9B5), land)
        for row in 0..<6 {
            for col in 0..<4 {
                let p = P(body.minX + 80 + CGFloat(col) * 110, body.minY + 80 + CGFloat(row) * 110)
                let a: CGFloat = 0.5 + 0.1 * sin(CGFloat(row + col) + t * 2), len: CGFloat = 50
                let q = P(p.x + len * cos(a), p.y + len * sin(a))
                stroke(c, navy, 8, polyline(p, q))
                fill(c, navy, circle(q, 9))
            }
        }
    case 1:                                              // a station graph: mean and gusts
        stroke(c, rgb(0xDDE3E6), 4, polyline(P(body.minX + 40, body.minY + 80), P(body.maxX - 40, body.minY + 80)))
        let mean = CGMutablePath(), gust = CGMutablePath()
        for i in 0...12 {
            let x = body.minX + 40 + CGFloat(i) * (body.width - 80) / 12
            let m = body.minY + 160 + 260 * (0.5 + 0.5 * sin(CGFloat(i) * 0.5 - 1)) + 30 * noise(i)
            if i == 0 { mean.move(to: P(x, m)); gust.move(to: P(x, m + 120)) }
            else { mean.addLine(to: P(x, m)); gust.addLine(to: P(x, m + 120 + 40 * noise(i + 9))) }
        }
        stroke(c, orange, 8, gust)
        stroke(c, sea, 10, mean)
    default:                                             // a webcam
        gradient(c, [rgb(0x4FAEE6), rgb(0xC4E8F8)], from: body.maxY, to: body.midY)
        fill(c, rgb(0x3A93C9), CGPath(rect: CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height / 2), transform: nil))
        fill(c, rgb(0xEAD6A8), CGPath(rect: CGRect(x: body.minX, y: body.minY, width: body.width, height: 120), transform: nil))
        foiler(c, x: body.midX + 40 * sin(t), by: body.midY - 40, scale: 0.3, t, who: .gary)
        fill(c, rgb(0xE5383B), rr(CGRect(x: body.maxX - 150, y: body.maxY - 70, width: 110, height: 48), 24))
        text(c, "LIVE", x: body.maxX - 95, y: body.maxY - 56, size: 28, weight: 800, color: white)
    }
    c.restoreGState()
    text(c, ["Wind map", "Station", "Webcam"][kind], x: r.minX + 40, y: r.maxY - 72, size: 44, weight: 800,
         color: navy, align: 0)
}

func scene4(_ c: CGContext, _ t: CGFloat) {
    let center = P(540, 860)
    background(c, sea)
    for i in 0..<18 {
        let a = CGFloat(i) * 2 * .pi / 18 + t * 0.15
        let wedge = CGMutablePath()
        wedge.move(to: center)
        wedge.addLine(to: P(center.x + 2000 * cos(a), center.y + 2000 * sin(a)))
        wedge.addLine(to: P(center.x + 2000 * cos(a + .pi / 18), center.y + 2000 * sin(a + .pi / 18)))
        wedge.closeSubpath()
        fill(c, rgb(0x2A86C0), wedge)
    }
    for i in 0..<3 {
        fill(c, skin, ellipse(P(845, 560 + CGFloat(i) * 115), 52, 40))
        fill(c, skin, ellipse(P(235, 600 + CGFloat(i) * 115), 52, 40))
    }
    let phone = CGRect(x: 240, y: 270, width: 600, height: 1180)
    fill(c, rgb(0x0B0F12), rr(phone, 96))
    let screen = phone.insetBy(dx: 22, dy: 22)
    c.saveGState()
    c.addPath(rr(screen, 76)); c.clip()
    fill(c, rgb(0xEEF2F4), CGPath(rect: screen, transform: nil))
    let swipe = smooth(ramp(t, 0.9, 1.25)) + smooth(ramp(t, 1.9, 2.25))
    for kind in 0..<3 {
        let x = 540 + (CGFloat(kind) - swipe) * 600
        card(c, CGRect(x: x - 250, y: 420, width: 500, height: 880), kind, t)
    }
    let going = ramp(t, 2.8, 3.1)
    if going > 0 {
        let chip = CGRect(x: 290, y: 440, width: 500, height: 90)
        c.saveGState()
        c.translateBy(x: chip.midX, y: chip.midY); c.scaleBy(x: pop(going), y: pop(going)); c.translateBy(x: -chip.midX, y: -chip.midY)
        fill(c, orange, rr(chip, 45))
        text(c, "Going tomorrow, 2–6 PM", x: chip.midX, y: chip.midY - 14, size: 40, weight: 800, color: white,
             maxWidth: chip.width - 50)
        c.restoreGState()
    }
    c.restoreGState()
    fill(c, rgb(0x000000), rr(CGRect(x: 455, y: 1360, width: 170, height: 50), 25))
    fill(c, skin, ellipse(P(250, 520), 48, 92))

    // Kai in the corner, nodding along
    let nod = 10 * sin(t * 7)
    face(c, P(850, 230 + nod), 175, .kai, lids: 0.3, look: P(-0.7, 0.6), mouth: .smile, shades: 1)

    caption(c, "Kookout taps you on the shoulder.", y: 1730, size: 80, appear: ramp(t, 0.2, 0.6))
    caption(c, "Your favourite sites fill in the details.", y: 1610, size: 70, appear: ramp(t, 1.2, 1.6), color: orange)
}

// MARK: - Scene 5: both out on the water at the home spot

func wave(_ x: CGFloat, base: CGFloat, amp: CGFloat, k: CGFloat, speed: CGFloat, _ t: CGFloat) -> CGFloat {
    base + amp * sin(k * x + speed * t) + 0.35 * amp * sin(2.3 * k * x - 1.7 * speed * t)
}

func band(_ c: CGContext, _ color: CGColor, base: CGFloat, amp: CGFloat, k: CGFloat, speed: CGFloat, _ t: CGFloat,
          crest: CGColor? = nil) {
    let top = stride(from: CGFloat(0), through: W, by: 10).map { P($0, wave($0, base: base, amp: amp, k: k, speed: speed, t)) }
    let body = CGMutablePath()
    body.move(to: P(0, 0)); body.addLines(between: top); body.addLine(to: P(W, 0)); body.closeSubpath()
    fill(c, color, body)
    if let crest {
        let line = CGMutablePath(); line.addLines(between: top)
        stroke(c, crest, 7, line)
    }
}

func cloud(_ c: CGContext, _ p: CGPoint, _ s: CGFloat) {
    for (dx, dy, r) in [(-70.0, 0.0, 52.0), (0, 28, 70), (72, 6, 50), (-20, -10, 55), (40, -12, 50)] {
        fill(c, rgb(0xFFFFFF, 0.96), circle(P(p.x + dx * s, p.y + dy * s), r * s))
    }
}

func scene5(_ c: CGContext, _ t: CGFloat) {
    gradient(c, [rgb(0x4FAEE6), rgb(0xC4E8F8)], from: H, to: 820)

    let sun = P(880, 1250)
    for i in 0..<10 {
        let a = CGFloat(i) * .pi / 5 + t * 0.4
        stroke(c, rgb(0xFFD45A), 14, polyline(P(sun.x + 120 * cos(a), sun.y + 120 * sin(a)), P(sun.x + 160 * cos(a), sun.y + 160 * sin(a))))
    }
    fill(c, rgb(0xFFD45A), circle(sun, 90))
    for (x0, y, s, v) in [(300.0, 1420.0, 1.15, 70.0), (900, 1500, 0.8, 55), (650, 1130, 0.9, 85)] {
        cloud(c, P(fract((x0 + t * v) / (W + 400)) * (W + 400) - 200, y), s)
    }
    for i in 0..<5 {
        let y = 960 + CGFloat(i) * 105
        let x = fract((CGFloat(i) * 313 + t * 520) / (W + 600)) * (W + 600) - 300
        let streak = CGMutablePath()
        streak.move(to: P(x, y))
        streak.addCurve(to: P(x + 240, y + 6), control1: P(x + 80, y + 26), control2: P(x + 160, y - 20))
        stroke(c, rgb(0xFFFFFF, 0.75), 7, streak)
    }

    let hills = CGMutablePath()
    hills.move(to: P(0, 800))
    hills.addQuadCurve(to: P(300, 820), control: P(130, 940))
    hills.addQuadCurve(to: P(620, 820), control: P(470, 900))
    hills.addQuadCurve(to: P(W, 820), control: P(860, 870))
    hills.addLine(to: P(W, 780)); hills.addLine(to: P(0, 780)); hills.closeSubpath()
    fill(c, rgb(0x4E8C7A), hills)
    fill(c, rgb(0x3A93C9), CGPath(rect: CGRect(x: 0, y: 0, width: W, height: 822), transform: nil))
    band(c, rgb(0x2F86BF), base: 770, amp: 8, k: 0.02, speed: 2.0, t)
    // Gary, further out
    foiler(c, x: mix(-300, 1000, t / 5), by: 720 + 8 * sin(t * 2.2 + 1), scale: 0.55, t, who: .gary)
    band(c, rgb(0x2477AF), base: 650, amp: 14, k: 0.012, speed: 2.6, t)

    // Kai, close
    let x = mix(-160, 1180, t / 5.0), by = 560 + 14 * sin(t * 2.6)
    let front = (base: CGFloat(420), amp: CGFloat(22), k: CGFloat(0.009), speed: CGFloat(3.2))
    foiler(c, x: x, by: by, scale: 1, t, who: .kai)
    let mast = x + 20
    let surface = wave(mast, base: front.base, amp: front.amp, k: front.k, speed: front.speed, t)
    for i in 0..<12 {
        let age = fract(CGFloat(i) / 12 + t * 1.8)
        fill(c, rgb(0xFFFFFF, 1 - age), circle(P(mast - age * 150, surface + 120 * age * (1 - age)), 13 * (1 - age) + 2))
    }
    band(c, sea, base: front.base, amp: front.amp, k: front.k, speed: front.speed, t, crest: rgb(0xFFFFFF, 0.45))

    // The beach, with the spot's sign
    let edge = stride(from: CGFloat(0), through: W, by: 10).map { P($0, 150 + 18 * sin($0 * 0.008 + 0.5)) }
    let beach = CGMutablePath()
    beach.move(to: P(0, 0)); beach.addLines(between: edge); beach.addLine(to: P(W, 0)); beach.closeSubpath()
    fill(c, rgb(0xEAD6A8), beach)
    let foam = CGMutablePath(); foam.addLines(between: edge)
    stroke(c, rgb(0xFFFFFF, 0.8), 10, foam)
    let sign = ramp(t, 1.0, 1.4)
    if sign > 0 {
        c.saveGState()
        c.translateBy(x: 150, y: 90); c.scaleBy(x: pop(sign), y: pop(sign)); c.translateBy(x: -150, y: -90)
        stroke(c, navy, 14, polyline(P(150, 90), P(150, 480)))
        let flag = CGMutablePath()
        let flap = { (u: CGFloat) in 10 * sin(u * 0.05 - t * 9) * (u / 150) }
        flag.move(to: P(157, 475))
        for u in stride(from: CGFloat(0), through: 150, by: 10) { flag.addLine(to: P(157 + u, 475 - u * 0.15 + flap(u))) }
        for u in stride(from: CGFloat(150), through: 0, by: -10) { flag.addLine(to: P(157 + u, 395 + u * 0.15 + flap(u))) }
        flag.closeSubpath()
        fill(c, orange, flag)
        let board = CGRect(x: 60, y: 200, width: 400, height: 100)
        fill(c, white, rr(board, 22))
        stroke(c, navy, 6, rr(board, 22))
        text(c, "Home spot", x: board.minX + 24, y: board.midY - 15, size: 44, weight: 800, color: navy, align: 0)
        let pill = CGRect(x: board.maxX - 134, y: board.midY - 28, width: 116, height: 56)
        fill(c, green, rr(pill, 28))
        text(c, "GOOD", x: pill.midX, y: pill.midY - 11, size: 30, weight: 800, color: white)
        c.restoreGState()
    }

    caption(c, "Kookout tells you when…", y: 1730, size: 96, appear: ramp(t, 0.4, 0.8))
    caption(c, "…and where.", y: 1600, size: 110, appear: ramp(t, 1.6, 2.0), color: orange)
}

// MARK: - Scene 6: end card

func scene6(_ c: CGContext, _ t: CGFloat) {
    fill(c, nearBlack, CGPath(rect: CGRect(x: 0, y: 0, width: W, height: H), transform: nil))
    // Pupils: out, left, a little right, back (em), as the app's splash does
    let keys: [(CGFloat, CGFloat)] = [(0.4, 0), (0.7, -0.16), (1.3, -0.16), (1.6, 0.02), (2.0, 0.02), (2.3, 0)]
    var look: CGFloat = 0
    for (a, b) in zip(keys, keys.dropFirst()) where t >= a.0 { look = mix(a.1, b.1, smooth(ramp(t, a.0, b.0))) }
    let k = mix(0.85, 1, pop(ramp(t, -0.2, 0.4)))
    c.saveGState()
    c.translateBy(x: W / 2, y: 1120); c.scaleBy(x: k, y: k); c.translateBy(x: -W / 2, y: -1120)
    eyes(c, P(W / 2, 1120), width: 700, look: look)
    let box = name.path.boundingBoxOfPath, s = 560 / box.width
    c.saveGState()
    c.translateBy(x: W / 2 - box.midX * s, y: 900 - box.maxY * s)
    c.scaleBy(x: s, y: s)
    fill(c, rgb(0xFFFFFF, 0.85), name.path)
    c.restoreGState()
    c.restoreGState()

    caption(c, "Know when your spots are good.", y: 620, size: 64, appear: ramp(t, 0.9, 1.3))
    let link = ramp(t, 1.5, 1.9)
    if link > 0 {
        c.saveGState(); c.setAlpha(link)
        text(c, "Free on the App Store  ·  kookout.no", x: W / 2, y: 500, size: 44, weight: 700, color: orange)
        c.restoreGState()
    }
}

// MARK: - Timeline and output

let scenes: [(start: CGFloat, end: CGFloat, draw: (CGContext, CGFloat) -> Void)] = [
    (0, 3, scene1), (3, 8, scene2), (8, 12, scene3), (12, 16, scene4), (16, 21, scene5), (21, duration, scene6),
]

func frame(_ c: CGContext, _ t: CGFloat) {
    for (i, scene) in scenes.enumerated() where t >= scene.start - (i == 0 ? 0 : fade) && t < scene.end + 0.001 {
        let a = i == 0 ? 1 : clamp((t - (scene.start - fade)) / fade)
        c.saveGState()
        c.setAlpha(a)
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        scene.draw(c, t - scene.start)
        c.endTransparencyLayer()
        c.restoreGState()
    }
}

let checks = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil
let checkTimes: [CGFloat] = [2.0, 4.5, 7.0, 9.0, 10.9, 13.0, 15.2, 17.5, 19.5, 23.5]

let output = URL(fileURLWithPath: "brand/promo/kookout-cartoon.mp4")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let silent = FileManager.default.temporaryDirectory.appendingPathComponent("kookout-promo-silent.mov")
try? FileManager.default.removeItem(at: silent)
try? FileManager.default.removeItem(at: output)

let writer = try AVAssetWriter(outputURL: silent, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(W), AVVideoHeightKey: Int(H),
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000,
                                      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: Int(W), kCVPixelBufferHeightKey as String: Int(H)])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let frameCount = Int(duration * CGFloat(fps))
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
for f in 0..<frameCount {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    let pb = buffer!
    CVPixelBufferLockBaseAddress(pb, [])
    let c = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Int(W), height: Int(H), bitsPerComponent: 8,
                      bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: srgb,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let t = CGFloat(f) / CGFloat(fps)
    frame(c, t)
    if let checks, checkTimes.contains(where: { abs($0 - t) < 0.5 / CGFloat(fps) }) {
        let png = NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
        try png.write(to: checks.appendingPathComponent(String(format: "frame-%05.2f.png", Double(t))))
    }
    CVPixelBufferUnlockBaseAddress(pb, [])
    adaptor.append(pb, withPresentationTime: CMTime(value: Int64(f), timescale: fps))
}
input.markAsFinished()
let written = DispatchSemaphore(value: 0)
writer.finishWriting { written.signal() }
written.wait()
guard writer.status == .completed else { fatalError("Writing failed: \(String(describing: writer.error))") }

// Add the swooshes and write the MP4
let video = AVURLAsset(url: silent)
let swoosh = AVURLAsset(url: URL(fileURLWithPath: "brand/swoosh.caf"))
let length = CMTime(value: CMTimeValue(frameCount), timescale: fps)
let composition = AVMutableComposition()
let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: video.tracks(withMediaType: .video)[0], at: .zero)
let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
audioTrack.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: length))
for at in swooshes {
    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: swoosh.duration),
                                   of: swoosh.tracks(withMediaType: .audio)[0], at: CMTime(seconds: at, preferredTimescale: 600))
}
let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
export.outputURL = output
export.outputFileType = .mp4
export.timeRange = CMTimeRange(start: .zero, duration: length)
let exported = DispatchSemaphore(value: 0)
export.exportAsynchronously { exported.signal() }
exported.wait()
guard export.status == .completed else { fatalError("Export failed: \(String(describing: export.error))") }
print("wrote \(output.path)")
