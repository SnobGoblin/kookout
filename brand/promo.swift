// Draws Kookout's cartoon promo for social media (9:16, 1080 × 1920, 30 fps, 30 s) frame by frame, with the
// brand's own swoosh. Run from the repo root:  swift -O brand/promo.swift [folder for check frames]
//
// Writes brand/promo/kookout-cartoon.mp4. With a folder, also writes a PNG of a few frames there, to look at.
// This is the animatic for the script in brand/promo/README.md: captions stand in for the narrator.
//
//   1. 0–2.8 s      a gust races across the fjord: "Wind. Doesn't wait, bro."
//   2. 2.8–7.7 s    Gary the puffin at dawn, buried in made-up metrics: "Gary loves his charts. Seagull drift index. Respect."
//   3. 7.7–11.4 s   Gary in a meeting; wings glide past the window: "But Gary also has, like, a job."
//   4. 11.4–17 s    Kai the otter in his hammock; the notification pops out of his phone (swoosh): "…Swoosh means condish."
//   5. 17–22.8 s    the Lock Screen widget (Kookout 1.1), then his favourite sites: "Kookout taps you on the shoulder…"
//   6. 22.8–26.6 s  Kai and Gary pass each other on the water: "When, and where. I think."
//   7. 26.6–30 s    end card: the logo's eyes look left, right and back, as in the app's splash

import AppKit
import AVFoundation
import CoreText
import Foundation

let W: CGFloat = 1080, H: CGFloat = 1920
let fps: Int32 = 30
let duration: CGFloat = 30
let fade: CGFloat = 0.35
/// Film grain over the whole picture (0 = off): softens the too-clean generated look.
let grain: CGFloat = 0.10
/// Show each generated frame for two video frames (12 drawings a second), as hand-drawn animation does; for the 2D shots.
let onTwos = true
// Instagram Reels covers these (px): keep captions and anything that matters out of them
let instagramTop: CGFloat = 250, instagramBottom: CGFloat = 450, instagramRight: CGFloat = 140                                  // crossfade between scenes
// Scene 3's swoosh plays right after the narrator says "swoosh" (see scene3Lead); the second opens the end card.
var swooshes: [Double] { [11.4 + (plates["scene3"].map { Double(scene3Lead) + ($0.cue - $0.from) / $0.speed } ?? 0.6), 26.7] }
// The narrator ("Kookout narrator 2" in ElevenLabs): one take per line, placed so each scene's beats land on the words.
// `parts` (s, within the take) plays only those sentences, with a 0.2 s breath between them; nil plays the whole take.
let voice: [(file: String, at: Double, parts: [(Double, Double)]?)] = [
    // The 30 s cut keeps whole sentences only; what's left out is noted per line.
    ("vo-1.take-a", 0.3, nil),
    // "Gary loves his charts. Seagull drift index. Respect." (out: "This is Gary.", "Secondary swell median.",
    // "Gust-to-lull variance.")
    ("vo-2.take-a", 2.95, [(1.50, 3.20), (7.74, 9.32), (9.74, 10.50)]),
    ("vo-2b.take-a", 7.9, [(0, 3.12)]),                     // "But Gary also has, like, a job." (out: "And the wind came. In the afternoon.")
    ("vo-3.take-a", 11.6, [(1.0, 2.95)]),                  // "Kai just waited for the swoosh." (out: "Kai?"), then the swoosh
    ("vo-3.take-a", 14.4, [(3.30, 5.70)]),                 // "Swoosh means condish."
    ("vo-4.take-a", 17.2, nil),                            // (out: line 3b, "No app to open. Just. Glance.")
    ("vo-5.take-b", 23.0, nil), ("vo-6.take-a", 27.4, nil),
]

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
    text(c, s, x: 0, y: -size * 0.35, size: size, color: color, outline: navy, maxWidth: W - 2 * instagramRight - 20)
    c.endTransparencyLayer()
    c.restoreGState()
}

// MARK: - Characters

let shirt = rgb(0xCFE3F2), wood = rgb(0x6B4A33)
let pine = rgb(0x2F5D50)

enum Who { case kai, gary }
enum Mouth { case smile, flat, grin, o }

let otter = rgb(0x8A5A3B), otterLight = rgb(0xE8D2B0), otterDark = rgb(0x5E3B26)
let puffin = rgb(0x1A1D21), beakBlue = rgb(0x4B5A68), beakYellow = rgb(0xFFD45A)

/// A face seen from the front, centred on `p`, head radius `r`: Kai is an otter in an orange beanie, Gary a puffin.
/// `lids` 0 = open, 1 = shut; `look` moves the pupils (in eye radii); `shades` nil = none, 0 = over the eyes,
/// 1 = pushed up on the forehead.
func face(_ c: CGContext, _ p: CGPoint, _ r: CGFloat, _ who: Who, lids: CGFloat = 0, look: CGPoint = .zero,
          mouth: Mouth = .smile, shades: CGFloat? = nil) {
    c.saveGState()
    c.translateBy(x: p.x, y: p.y)
    c.scaleBy(x: r / 100, y: r / 100)
    let base = who == .kai ? otter : puffin
    switch who {
    case .kai:
        for ex in [CGFloat(-74), 74] { fill(c, otter, circle(P(ex, 62), 26)); fill(c, otterDark, circle(P(ex, 62), 13)) }
        fill(c, otter, ellipse(.zero, 106, 96))
        fill(c, otterLight, ellipse(P(0, -40), 72, 50))
        c.saveGState()
        c.addPath(ellipse(.zero, 110, 100)); c.clip()
        fill(c, orange, CGPath(rect: CGRect(x: -120, y: 62, width: 240, height: 60), transform: nil))
        fill(c, orangeDark, rr(CGRect(x: -112, y: 50, width: 224, height: 28), 14))
        c.restoreGState()
    case .gary:
        fill(c, puffin, ellipse(.zero, 104, 102))
        fill(c, white, ellipse(P(0, -6), 90, 72))
    }
    for ex in [CGFloat(-38), 38] {
        let e = CGRect(x: ex - 22, y: -14, width: 44, height: 50)
        c.saveGState()
        c.addEllipse(in: e); c.clip()
        fill(c, white, CGPath(rect: e, transform: nil))
        fill(c, navy, circle(P(ex + look.x * 9, e.midY + look.y * 11), 11))
        if lids > 0 {
            let lid = e.maxY - lids * e.height
            fill(c, base, CGPath(rect: CGRect(x: e.minX, y: lid, width: e.width, height: e.maxY - lid), transform: nil))
            stroke(c, navy, 5, polyline(P(e.minX, lid), P(e.maxX, lid)))
        }
        c.restoreGState()
        stroke(c, who == .gary ? rgb(0xE5383B) : navy, who == .gary ? 5 : 4, CGPath(ellipseIn: e, transform: nil))
    }
    switch who {
    case .kai:                                           // nose, whiskers, mouth
        let nose = CGMutablePath()
        nose.addLines(between: [P(-18, -12), P(18, -12), P(0, -30)]); nose.closeSubpath()
        fill(c, navy, nose); stroke(c, navy, 8, nose)
        for side in [CGFloat(-1), 1] {
            for (i, dy) in [CGFloat(4), -8, -20].enumerated() {
                stroke(c, otterDark, 3, polyline(P(side * (44 + CGFloat(i) * 2), -36), P(side * 104, -36 + dy)))
            }
        }
        switch mouth {
        case .o: fill(c, navy, ellipse(P(0, -60), 13, 16))
        case .flat: stroke(c, navy, 6, polyline(P(-18, -54), P(18, -54)))
        case .grin:
            let g = CGMutablePath()
            g.move(to: P(-30, -44)); g.addQuadCurve(to: P(30, -44), control: P(0, -96)); g.closeSubpath()
            fill(c, navy, g)
        case .smile:
            stroke(c, navy, 6, curve(P(-24, -46), P(-12, -62), P(0, -46)))
            stroke(c, navy, 6, curve(P(0, -46), P(12, -62), P(24, -46)))
        }
    case .gary:                                          // the striped beak; open for "o"
        fill(c, beakBlue, rr(CGRect(x: -46, y: -32, width: 92, height: 20), 10))
        let beak = CGMutablePath()
        beak.move(to: P(-46, -26))
        beak.addQuadCurve(to: P(0, -90), control: P(-38, -66))
        beak.addQuadCurve(to: P(46, -26), control: P(38, -66))
        beak.closeSubpath()
        fill(c, orange, beak)
        c.saveGState(); c.addPath(beak); c.clip()
        stroke(c, beakYellow, 6, curve(P(-50, -44), P(0, -36), P(50, -44)))
        stroke(c, orangeDark, 5, curve(P(-50, -64), P(0, -56), P(50, -64)))
        c.restoreGState()
        if mouth == .o { fill(c, navy, ellipse(P(0, -52), 22, 9)) }
    }
    if let shades {
        let y = mix(12, 82, smooth(shades))
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
    let head = P(28, 350)
    switch who {
    case .kai:                                           // otter: tail out behind, board shorts, beanie
        stroke(c, otter, 36, polyline(P(0, 160), P(-70, 130)))
        stroke(c, otter, 22, polyline(P(-70, 130), P(-140, 80)))
        stroke(c, otter, 30, polyline(P(-45, 14), P(-18, 82), P(5, 150)))
        stroke(c, otter, 30, polyline(P(45, 14), P(62, 86), P(5, 150)))
        stroke(c, otter, 84, polyline(P(5, 150), P(20, 285)))
        stroke(c, otterLight, 40, polyline(P(26, 165), P(36, 280)))
        fill(c, navy, rr(CGRect(x: -36, y: 128, width: 84, height: 50), 20))
        stroke(c, otter, 24, polyline(P(20, 285), P(-30, 372), P(-62, 470)))
        stroke(c, otter, 24, polyline(P(20, 285), P(62, 378), P(92, 465)))
        fill(c, otterDark, circle(P(-62, 472), 16))
        fill(c, otterDark, circle(P(92, 467), 16))
        fill(c, otter, circle(P(head.x - 22, head.y + 38), 14))
        fill(c, otter, circle(head, 48))
        fill(c, otterLight, ellipse(P(head.x + 34, head.y - 14), 28, 20))
        fill(c, navy, circle(P(head.x + 58, head.y - 8), 8))
        c.saveGState()
        c.addPath(circle(head, 52)); c.clip()
        fill(c, orange, CGPath(rect: CGRect(x: head.x - 60, y: head.y + 18, width: 120, height: 60), transform: nil))
        c.restoreGState()
        fill(c, white, circle(P(head.x + 18, head.y + 4), 11))
        fill(c, navy, circle(P(head.x + 22, head.y + 4), 5))
        stroke(c, navy, 5, curve(P(head.x + 30, head.y - 30), P(head.x + 40, head.y - 40), P(head.x + 52, head.y - 28)))
    case .gary:                                          // puffin: orange feet, white belly, striped beak
        fill(c, orange, ellipse(P(-45, 18), 26, 10))
        fill(c, orange, ellipse(P(45, 18), 26, 10))
        stroke(c, orange, 14, polyline(P(-42, 18), P(-12, 80), P(5, 140)))
        stroke(c, orange, 14, polyline(P(42, 18), P(58, 82), P(5, 140)))
        fill(c, puffin, ellipse(P(14, 220), 62, 104))
        fill(c, white, ellipse(P(36, 205), 36, 80))
        stroke(c, puffin, 24, polyline(P(20, 285), P(-30, 372), P(-62, 470)))
        stroke(c, puffin, 24, polyline(P(20, 285), P(62, 378), P(92, 465)))
        fill(c, puffin, circle(P(-62, 472), 15))
        fill(c, puffin, circle(P(92, 467), 15))
        fill(c, puffin, circle(head, 48))
        fill(c, white, ellipse(P(head.x + 10, head.y - 4), 32, 28))
        fill(c, navy, circle(P(head.x + 20, head.y + 4), 6))
        stroke(c, rgb(0xE5383B), 3, circle(P(head.x + 20, head.y + 4), 9))
        fill(c, beakBlue, CGPath(rect: CGRect(x: head.x + 40, y: head.y - 22, width: 10, height: 36), transform: nil))
        let beak = CGMutablePath()
        beak.addLines(between: [P(head.x + 48, head.y + 14), P(head.x + 48, head.y - 24), P(head.x + 92, head.y - 8)])
        beak.closeSubpath()
        fill(c, orange, beak)
    }
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
    if let plate = plates["scene1"] {
        // The gust over the fjord; the captions sit in the open sky, where the later scenes put theirs too.
        plate.draw(c, t)
        caption(c, "Wind.", y: 1560, size: 110, appear: ramp(t, 0.35, 0.7))
        caption(c, "Doesn't wait, bro.", y: 1430, size: 90, appear: ramp(t, 1.4, 1.75), color: orange)
        return
    }
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

    caption(c, "Wind.", y: 680, size: 110, appear: ramp(t, 0.6, 1.0))
    caption(c, "Doesn't wait, bro.", y: 560, size: 90, appear: ramp(t, 1.5, 1.9), color: orange)
}

// MARK: - Scene 2a: Gary's morning analysis, buried in made-up metrics
// The joke is on Gary overdoing it, never on any real site: every metric here is invented.

let metrics: [(name: String, value: String?, at: CGPoint, tilt: CGFloat)] = [
    ("Secondary swell median", nil, P(270, 1270), -0.06),
    ("Gust-to-lull variance (adj.)", nil, P(790, 1250), 0.05),
    ("Seagull drift index", "NE-ish", P(250, 960), 0.04),
    ("Moon × tide phase", "Waxing-ish", P(800, 930), -0.05),
    ("Wind confidence index", "63 %", P(290, 640), 0.06),
    ("Kites on webcam 3", "2 (1 lost)", P(780, 640), -0.04),
    ("Swell period, 4th model", nil, P(540, 1330), 0.02),
]

func metricCard(_ c: CGContext, _ i: Int, appear: CGFloat, _ t: CGFloat) {
    guard appear > 0 else { return }
    let m = metrics[i], r = CGRect(x: -165, y: -100, width: 330, height: 200)
    c.saveGState()
    c.translateBy(x: m.at.x, y: m.at.y)
    c.rotate(by: m.tilt)
    c.scaleBy(x: pop(appear), y: pop(appear))
    fill(c, rgb(0x000000, 0.25), rr(r.offsetBy(dx: 8, dy: -10), 22))
    fill(c, white, rr(r, 22))
    text(c, m.name, x: r.minX + 22, y: r.maxY - 48, size: 30, weight: 800, color: navy, align: 0, maxWidth: r.width - 44)
    if let value = m.value {
        text(c, value, x: r.minX + 22, y: r.minY + 42, size: 56, weight: 800, color: orange, align: 0, maxWidth: r.width - 44)
    } else {
        let line = CGMutablePath()
        for k in 0...14 {
            let x = r.minX + 22 + CGFloat(k) * (r.width - 44) / 14
            let y = r.minY + 70 + 50 * noise(i * 31 + k) + 10 * sin(t * 6 + CGFloat(k))
            if k == 0 { line.move(to: P(x, y)) } else { line.addLine(to: P(x, y)) }
        }
        stroke(c, i % 2 == 0 ? sea : orange, 7, line)
    }
    c.restoreGState()
}

func scene2a(_ c: CGContext, _ t: CGFloat) {
    if let plate = plates["scene2a"] { plate.draw(c, t); scene2aOverlay(c, t); return }
    background(c, rgb(0x2E3F4B))
    // Dawn through the window, a lamp, coffee
    let win = CGRect(x: 640, y: 1120, width: 300, height: 330)
    fill(c, rgb(0xDCE3E8), rr(win.insetBy(dx: -16, dy: -16), 12))
    c.saveGState(); c.addPath(rr(win, 4)); c.clip()
    gradient(c, [rgb(0x34295A), rgb(0xFF9E7A)], from: win.maxY, to: win.minY)
    c.restoreGState()
    text(c, "06:12", x: 230, y: 1380, size: 90, weight: 700, color: rgb(0xFF4F4F))

    // Gary at the kitchen table, eyes going round
    fill(c, shirt, rr(CGRect(x: 380, y: 480, width: 320, height: 360), 120))
    let tie = CGMutablePath()
    tie.addLines(between: [P(540, 820), P(515, 600), P(540, 560), P(565, 600)]); tie.closeSubpath()
    fill(c, navy, tie)
    fill(c, puffin, CGPath(rect: CGRect(x: 505, y: 820, width: 70, height: 70), transform: nil))
    let dizzy = ramp(t, 5.0, 5.8)
    face(c, P(540, 980), 125, .gary, look: P(dizzy * cos(t * 9), dizzy * sin(t * 9)),
         mouth: dizzy > 0.5 ? .o : .flat)
    fill(c, rgb(0x3B4A55), CGPath(rect: CGRect(x: 0, y: 0, width: W, height: 540), transform: nil))
    fill(c, white, rr(CGRect(x: 760, y: 520, width: 80, height: 90), 14))
    stroke(c, white, 12, CGPath(ellipseIn: CGRect(x: 825, y: 540, width: 40, height: 46), transform: nil))
    fill(c, puffin, ellipse(P(380, 560), 60, 34))
    fill(c, puffin, ellipse(P(700, 560), 60, 34))

    scene2aOverlay(c, t)
}

func scene2aOverlay(_ c: CGContext, _ t: CGFloat) {
    // "Seagull drift index" lands as it's said (2.1 s); the others pile in around it
    let lands: [CGFloat] = [1.0, 1.6, 2.1, 2.6, 2.9, 3.2, 3.5]
    for i in metrics.indices { metricCard(c, i, appear: ramp(t, lands[i], lands[i] + 0.25), t) }

    caption(c, "Gary loves", y: 1600, size: 96, appear: ramp(t, 0.15, 0.5))
    caption(c, "his charts.", y: 1490, size: 96, appear: ramp(t, 0.9, 1.25), color: orange)
    caption(c, "Respect.", y: 500, size: 110, appear: ramp(t, 3.85, 4.1))
}

func scene2Captions(_ c: CGContext, _ t: CGFloat) {
    caption(c, "But Gary also has…", y: 1580, size: 90, appear: ramp(t, 0.25, 0.55))
    caption(c, "like… a job.", y: 1470, size: 96, appear: ramp(t, 2.1, 2.4), color: orange)
}

func scene2(_ c: CGContext, _ t: CGFloat) {
    if let plate = plates["scene2"] { plate.draw(c, t); scene2Captions(c, t); return }
    background(c, rgb(0xDDE3E6))
    // The window: a sunny fjord, wings gliding past
    c.saveGState()
    c.translateBy(x: 0, y: -130)                         // keeps the window clear of the captions
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
    for (i, start) in [3.4, 4.1, 4.8].enumerated() {
        let x = mix(-150, 1250, (t - CGFloat(start)) / 1.9)
        let by = 900 + CGFloat(i) * 25 + 6 * sin(t * 3 + CGFloat(i))
        foiler(c, x: x, by: by, scale: 0.28 - CGFloat(i) * 0.03, t, who: i == 1 ? .kai : .gary)
    }
    band(c, rgb(0x2A80B8), base: 880, amp: 6, k: 0.02, speed: 2.4, t)
    c.restoreGState()
    stroke(c, rgb(0xF4F6F7), 18, polyline(P(win.midX, win.minY), P(win.midX, win.maxY)))
    c.restoreGState()

    // Gary, bored, then turning round too late
    let turn = smooth(ramp(t, 6.2, 6.5))
    fill(c, shirt, rr(CGRect(x: 380, y: 480, width: 320, height: 360), 120))
    let tie = CGMutablePath()
    tie.addLines(between: [P(540, 820), P(515, 600), P(540, 560), P(565, 600)]); tie.closeSubpath()
    fill(c, navy, tie)
    fill(c, puffin, CGPath(rect: CGRect(x: 505, y: 820, width: 70, height: 70), transform: nil))
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
    fill(c, puffin, ellipse(P(330, 560), 60, 34))
    fill(c, puffin, ellipse(P(750, 560), 60, 34))

    scene2Captions(c, t)
}

// MARK: - Scene 3: Kai floating on his back, the swoosh

/// The Kookout notification, drawn in an 840 × 250 box at the origin.
func notificationCard(_ c: CGContext) {
    let banner = CGRect(x: 0, y: 0, width: 840, height: 250)
    fill(c, rgb(0xFFFFFF, 0.96), rr(banner, 56))
    let icon = CGRect(x: banner.minX + 34, y: banner.midY - 76, width: 152, height: 152)
    fill(c, navy, rr(icon, 36))
    eyes(c, P(icon.midX, icon.midY), width: 118)
    text(c, "Home spot", x: banner.minX + 216, y: banner.midY + 22, size: 62, weight: 800, color: rgb(0x111111), align: 0)
    text(c, "now", x: banner.maxX - 40, y: banner.midY + 22, size: 44, weight: 500, color: rgb(0x777777), align: 1)
    text(c, "Tomorrow 2–6 PM good", x: banner.minX + 216, y: banner.midY - 58, size: 54, weight: 500,
         color: rgb(0x222222), align: 0, maxWidth: banner.width - 250)
}

func scene3(_ c: CGContext, _ t: CGFloat) {
    if let plate = plates["scene3"] { scene3(c, t, on: plate); return }
    gradient(c, [rgb(0x4FAEE6), rgb(0xC4E8F8)], from: H, to: 900)
    // The far shore with a few pines, then the water
    let shore = CGMutablePath()
    shore.move(to: P(0, 900)); shore.addQuadCurve(to: P(W, 900), control: P(540, 1010)); shore.closeSubpath()
    fill(c, rgb(0x4E8C7A), shore)
    for x in [CGFloat(120), 200, 280, 820, 900, 980] {
        let tri = CGMutablePath()
        tri.addLines(between: [P(x - 45, 905), P(x + 45, 905), P(x, 1060)]); tri.closeSubpath()
        fill(c, pine, tri)
    }
    fill(c, rgb(0x3A93C9), CGPath(rect: CGRect(x: 0, y: 0, width: W, height: 905), transform: nil))
    band(c, rgb(0x2F86BF), base: 860, amp: 8, k: 0.02, speed: 1.6, t)
    band(c, rgb(0x2477AF), base: 760, amp: 12, k: 0.014, speed: 1.9, t)

    // Kai floating on his back, phone held on his belly
    let bob = 10 * sin(t * 1.6)
    let lift = ramp(t, 1.9, 2.4), lit = ramp(t, 0.6, 0.7)
    c.saveGState()
    c.translateBy(x: 600, y: 600 + bob)
    c.rotate(by: 0.03 * sin(t * 1.2))
    stroke(c, otter, 44, polyline(P(200, -6), P(280, 6)))
    stroke(c, otter, 26, polyline(P(280, 6), P(350, 24)))
    fill(c, otterDark, ellipse(P(210, 58), 26, 40))
    fill(c, otterDark, ellipse(P(172, 66), 26, 40))
    fill(c, otter, ellipse(.zero, 230, 82))
    fill(c, otterLight, ellipse(P(-10, 22), 170, 50))
    fill(c, rgb(0x111518), rr(CGRect(x: -40, y: 36, width: 72, height: 124), 14))
    fill(c, lit > 0 ? rgb(0xCFE8F7) : rgb(0x1D2329), rr(CGRect(x: -34, y: 44, width: 60, height: 108), 10))
    if lit > 0 { fill(c, rgb(0xFFFFFF, 0.25 * (1 + sin(t * 8)) / 2), circle(P(-4, 100), 110)) }
    fill(c, otterDark, ellipse(P(-50, 86), 22, 18))
    fill(c, otterDark, ellipse(P(42, 86), 22, 18))
    c.saveGState()
    c.translateBy(x: -270, y: 44)
    c.rotate(by: 0.3)
    face(c, .zero, 96, .kai, lids: lift > 0.5 ? 0.35 : 1, look: P(0.4, -0.3), mouth: lift > 0.5 ? .grin : .smile, shades: lift)
    c.restoreGState()
    c.restoreGState()
    band(c, sea, base: 575 + bob, amp: 10, k: 0.016, speed: 2.0, t, crest: rgb(0xFFFFFF, 0.5))
    band(c, rgb(0x155985), base: 300, amp: 14, k: 0.01, speed: 2.4, t)

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
        tail.addLines(between: [P(520, banner.minY + 10), P(600, banner.minY + 10), P(590, banner.minY - 160)]); tail.closeSubpath()
        fill(c, rgb(0xFFFFFF, 0.96), tail)
        c.saveGState()
        c.translateBy(x: banner.minX, y: banner.minY)
        notificationCard(c)
        c.restoreGState()
        c.endTransparencyLayer()
        c.restoreGState()
    }

    caption(c, "Kai?", y: 1560, size: 110, appear: ramp(t, 1.2, 1.5))
    caption(c, "Kai just waited for the swoosh.", y: 1440, size: 90, appear: ramp(t, 1.9, 2.3), color: orange)
}

// MARK: - Scene 3b: the Lock Screen widget (Kookout 1.1)
// As KookoutWidget draws it: rectangular = three lines, spot and when ("now" in bold, today's hours, else the
// weekday), one colour; circular = the sport icon and a tick when it's good now.

let lockSpots: [(name: String, when: String, now: Bool)] = [("Home spot", "now", true), ("The reef", "14–18", false),
                                                             ("Ski hill", "Sat", false)]

func windIcon(_ c: CGContext, _ p: CGPoint, _ s: CGFloat, _ color: CGColor) {
    for (i, len) in [CGFloat(1), 0.75, 0.9].enumerated() {
        let y = p.y + (1 - CGFloat(i)) * 0.32 * s
        let line = CGMutablePath()
        line.move(to: P(p.x - 0.5 * s, y))
        line.addLine(to: P(p.x + (len - 0.6) * s, y))
        line.addArc(center: P(p.x + (len - 0.6) * s, y + 0.12 * s), radius: 0.12 * s, startAngle: -.pi / 2, endAngle: .pi,
                    clockwise: false)
        stroke(c, color, 0.09 * s, line)
    }
}

/// The rectangular widget's three lines, `size` points per line, white.
func lockWidget(_ c: CGContext, origin: CGPoint, size: CGFloat) {
    for (i, s) in lockSpots.enumerated() {
        let y = origin.y - CGFloat(i) * size * 1.25
        let nameFont = archivo(size: size, weight: s.now ? 700 : 500)
        let w = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: s.name,
                    attributes: [.init(kCTFontAttributeName as String): nameFont])), nil, nil, nil))
        text(c, s.name, x: origin.x, y: y, size: size, weight: s.now ? 700 : 500, color: white, align: 0)
        text(c, s.when, x: origin.x + w + size * 0.35, y: y, size: size, weight: s.now ? 800 : 500, color: white, align: 0)
    }
}

func scene3b(_ c: CGContext, _ t: CGFloat) { scene3b(c, t, captions: true) }

func scene3b(_ c: CGContext, _ t: CGFloat, captions: Bool) {
    let center = P(540, 860)
    background(c, sea)
    for i in 0..<18 {
        let a = CGFloat(i) * 2 * .pi / 18 - t * 0.15
        let wedge = CGMutablePath()
        wedge.move(to: center)
        wedge.addLine(to: P(center.x + 2000 * cos(a), center.y + 2000 * sin(a)))
        wedge.addLine(to: P(center.x + 2000 * cos(a + .pi / 18), center.y + 2000 * sin(a + .pi / 18)))
        wedge.closeSubpath()
        fill(c, rgb(0x2A86C0), wedge)
    }
    // The phone's Lock Screen
    c.saveGState()
    c.translateBy(x: 540, y: 1030); c.scaleBy(x: 0.68, y: 0.68); c.translateBy(x: -540, y: -860)
    let phone = CGRect(x: 240, y: 270, width: 600, height: 1180)
    fill(c, rgb(0x0B0F12), rr(phone, 96))
    let screen = phone.insetBy(dx: 22, dy: 22)
    c.saveGState()
    c.addPath(rr(screen, 76)); c.clip()
    gradient(c, [rgb(0x1B3B52), rgb(0x3E7FA8), rgb(0xF2A65A)], from: screen.maxY, to: screen.minY)
    band(c, rgb(0x1C6EA4), base: 520, amp: 14, k: 0.02, speed: 1.5, t)
    band(c, rgb(0x155985), base: 440, amp: 18, k: 0.014, speed: 2.2, t)
    c.restoreGState()
    fill(c, rgb(0x000000), rr(CGRect(x: 455, y: 1360, width: 170, height: 50), 25))
    text(c, "Saturday 7 November", x: 540, y: 1270, size: 40, weight: 600, color: rgb(0xFFFFFF, 0.9))
    text(c, "07:42", x: 540, y: 1080, size: 200, weight: 700, color: rgb(0xFFFFFF, 0.95))
    let glow = 0.5 + 0.5 * sin(t * 5)
    let rect = CGRect(x: 290, y: 860, width: 340, height: 140)
    fill(c, rgb(0xFFFFFF, 0.14), rr(rect, 24))
    lockWidget(c, origin: P(rect.minX + 20, rect.maxY - 42), size: 30)
    let round = P(720, 930)
    fill(c, rgb(0xFFFFFF, 0.14), circle(round, 70))
    windIcon(c, P(round.x, round.y + 26), 44, white)
    stroke(c, white, 9, polyline(P(round.x - 22, round.y - 22), P(round.x - 6, round.y - 38), P(round.x + 24, round.y - 4)))
    stroke(c, rgb(0xFF6B2C, 0.6 + 0.4 * glow), 8, rr(rect.insetBy(dx: -10, dy: -10), 30))
    stroke(c, rgb(0xFF6B2C, 0.6 + 0.4 * glow), 8, circle(round, 80))
    c.restoreGState()

    // The widget again, big enough to read on a phone
    let zoom = ramp(t, 0.7, 1.05)
    if zoom > 0 {
        let card = CGRect(x: 220, y: 470, width: 640, height: 250)
        c.saveGState()
        c.translateBy(x: card.midX, y: card.maxY); c.scaleBy(x: pop(zoom), y: pop(zoom)); c.translateBy(x: -card.midX, y: -card.maxY)
        fill(c, rgb(0x0B1E2A, 0.92), rr(card, 40))
        stroke(c, orange, 6, rr(card, 40))
        lockWidget(c, origin: P(card.minX + 40, card.maxY - 70), size: 54)
        c.restoreGState()
    }

    guard captions else { return }
    caption(c, "No app to open.", y: 1600, size: 90, appear: ramp(t, 0.2, 0.6))
    caption(c, "Just… glance.", y: 1490, size: 90, appear: ramp(t, 2.0, 2.4), color: orange)
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

/// Kai's phone with his favourite sites swiping by (generic wind map, station, webcam), then "Going tomorrow"; drawn
/// around (540, 860), 600 × 1180. `hands` adds his paws holding it.
func sitesPhone(_ c: CGContext, _ t: CGFloat, swipes: (CGFloat, CGFloat), going goingAt: CGFloat, hands: Bool) {
    if hands {
        for i in 0..<3 {
            fill(c, otterDark, ellipse(P(845, 560 + CGFloat(i) * 115), 52, 40))
            fill(c, otterDark, ellipse(P(235, 600 + CGFloat(i) * 115), 52, 40))
        }
    }
    let phone = CGRect(x: 240, y: 270, width: 600, height: 1180)
    fill(c, rgb(0x0B0F12), rr(phone, 96))
    let screen = phone.insetBy(dx: 22, dy: 22)
    c.saveGState()
    c.addPath(rr(screen, 76)); c.clip()
    fill(c, rgb(0xEEF2F4), CGPath(rect: screen, transform: nil))
    let swipe = smooth(ramp(t, swipes.0, swipes.0 + 0.35)) + smooth(ramp(t, swipes.1, swipes.1 + 0.35))
    for kind in 0..<3 {
        let x = 540 + (CGFloat(kind) - swipe) * 600
        card(c, CGRect(x: x - 250, y: 420, width: 500, height: 880), kind, t)
    }
    let going = ramp(t, goingAt, goingAt + 0.3)
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
    if hands { fill(c, otter, ellipse(P(250, 520), 48, 92)) }
}

func scene4Captions(_ c: CGContext, _ t: CGFloat) {
    caption(c, "Kookout taps you when your spots are firing.", y: 1600, size: 80, appear: ramp(t, 0.2, 0.6))
    caption(c, "Your favourite sites do the rest.", y: 1500, size: 76, appear: ramp(t, 3.6, 4.0), color: orange)
}

func scene4(_ c: CGContext, _ t: CGFloat) {
    if let plate = plates["scene4"] {
        // "Kookout taps you on the shoulder…" over the Lock Screen widget, then Kai scrolling in the hammock; his screen
        // floats beside him (right, over the water, clear of his face) on "Your favourite sites…"
        plate.draw(c, t)
        let widget = 1 - ramp(t, 3.1, 3.5)
        if widget > 0 {
            c.saveGState(); c.setAlpha(widget); c.beginTransparencyLayer(auxiliaryInfo: nil)
            scene3b(c, t, captions: false)
            c.endTransparencyLayer(); c.restoreGState()
        }
        let show = ramp(t, 3.5, 3.9)
        if show > 0 {
            let k = 0.45 * pop(show)
            c.saveGState()
            c.translateBy(x: 800, y: 1150); c.scaleBy(x: k, y: k); c.rotate(by: -0.05); c.translateBy(x: -540, y: -860)
            c.setShadow(offset: CGSize(width: 0, height: -24), blur: 50, color: rgb(0x000000, 0.4))
            c.beginTransparencyLayer(auxiliaryInfo: nil)
            sitesPhone(c, t, swipes: (4.3, 4.9), going: 5.4, hands: false)
            c.endTransparencyLayer()
            c.restoreGState()
        }
        scene4Captions(c, t)
        return
    }
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
    c.saveGState()
    c.translateBy(x: 580, y: 990); c.scaleBy(x: 0.76, y: 0.76); c.translateBy(x: -540, y: -860)
    sitesPhone(c, t, swipes: (0.9, 1.9), going: 2.8, hands: true)
    c.restoreGState()

    // Kai in the corner, nodding along
    let nod = 10 * sin(t * 7)
    face(c, P(210, 610 + nod), 150, .kai, lids: 0.3, look: P(0.7, 0.6), mouth: .smile, shades: 1)

    scene4Captions(c, t)
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
    if let plate = plates["scene5"] { plate.draw(c, t); scene5Captions(c, t); return }
    gradient(c, [rgb(0x4FAEE6), rgb(0xC4E8F8)], from: H, to: 820)

    let sun = P(860, 1170)
    for i in 0..<10 {
        let a = CGFloat(i) * .pi / 5 + t * 0.4
        stroke(c, rgb(0xFFD45A), 14, polyline(P(sun.x + 120 * cos(a), sun.y + 120 * sin(a)), P(sun.x + 160 * cos(a), sun.y + 160 * sin(a))))
    }
    fill(c, rgb(0xFFD45A), circle(sun, 90))
    for (x0, y, s, v) in [(300.0, 1300.0, 1.0, 70.0), (900, 1380, 0.75, 55), (650, 1060, 0.85, 85)] {
        cloud(c, P(fract((x0 + t * v) / (W + 400)) * (W + 400) - 200, y), s)
    }
    for i in 0..<4 {
        let y = 940 + CGFloat(i) * 100
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
        stroke(c, navy, 14, polyline(P(150, 90), P(150, 780)))
        let flag = CGMutablePath()
        let flap = { (u: CGFloat) in 10 * sin(u * 0.05 - t * 9) * (u / 150) }
        flag.move(to: P(157, 775))
        for u in stride(from: CGFloat(0), through: 150, by: 10) { flag.addLine(to: P(157 + u, 775 - u * 0.15 + flap(u))) }
        for u in stride(from: CGFloat(150), through: 0, by: -10) { flag.addLine(to: P(157 + u, 695 + u * 0.15 + flap(u))) }
        flag.closeSubpath()
        fill(c, orange, flag)
        let board = CGRect(x: 70, y: 500, width: 400, height: 100)
        fill(c, white, rr(board, 22))
        stroke(c, navy, 6, rr(board, 22))
        text(c, "Home spot", x: board.minX + 24, y: board.midY - 15, size: 44, weight: 800, color: navy, align: 0)
        let pill = CGRect(x: board.maxX - 134, y: board.midY - 28, width: 116, height: 56)
        fill(c, green, rr(pill, 28))
        text(c, "GOOD", x: pill.midX, y: pill.midY - 11, size: 30, weight: 800, color: white)
        c.restoreGState()
    }

    scene5Captions(c, t)
}

func scene5Captions(_ c: CGContext, _ t: CGFloat) {
    caption(c, "When… and where.", y: 1560, size: 96, appear: ramp(t, 0.3, 0.65))
    caption(c, "I think.", y: 1430, size: 100, appear: ramp(t, 2.75, 3.05), color: orange)
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
    c.translateBy(x: W / 2, y: 1240); c.scaleBy(x: k, y: k); c.translateBy(x: -W / 2, y: -1240)
    eyes(c, P(W / 2, 1240), width: 700, look: look)
    let box = name.path.boundingBoxOfPath, s = 560 / box.width
    c.saveGState()
    c.translateBy(x: W / 2 - box.midX * s, y: 1020 - box.maxY * s)
    c.scaleBy(x: s, y: s)
    fill(c, rgb(0xFFFFFF, 0.85), name.path)
    c.restoreGState()
    c.restoreGState()

    caption(c, "Know when your spots are good.", y: 790, size: 64, appear: ramp(t, 0.9, 1.3))
    let link = ramp(t, 1.5, 1.9)
    if link > 0 {
        c.saveGState(); c.setAlpha(link)
        text(c, "Free on the App Store  ·  kookout.no", x: W / 2, y: 670, size: 44, weight: 700, color: orange,
             maxWidth: W - 2 * instagramRight - 20)
        c.restoreGState()
    }
}

// MARK: - Video plates: generated shots under our overlays

/// A generated shot used as a scene's picture. `from` and `length` pick the part of the clip (s); after it, its last
/// frame holds with a slow push-in. `anchor` tracks a point in the clip (the phone), in its pixels from the top left,
/// so overlays can follow it. `cue` is when the key moment happens in the clip (the phone lights up). Shots are used
/// whole: anything wrong in them (burned-in text, fake screens) is fixed by regenerating, never by cropping.
struct Plate {
    let generator: AVAssetImageGenerator
    let size: CGSize
    let from: Double, length: Double, cue: Double
    let anchor: [(t: Double, p: CGPoint)]
    /// Playback speed; below 1 the source frames are cross-faded so slow motion stays smooth.
    let speed: Double
    let frameRate: Double

    init?(_ path: String, from: Double, length: Double, cue: Double, speed: Double = 1,
          anchor: [(t: Double, p: CGPoint)] = []) {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let track = asset.tracks(withMediaType: .video).first
        size = track?.naturalSize ?? CGSize(width: 720, height: 1280)
        frameRate = Double(track?.nominalFrameRate ?? 24)
        self.from = from; self.length = length; self.cue = cue; self.speed = speed; self.anchor = anchor
    }

    private func fit(_ t: CGFloat) -> (scale: CGFloat, origin: CGPoint) {
        let s = max(W / size.width, H / size.height) * (1 + 0.025 * max(0, t - CGFloat(length)))
        return (s, P((W - size.width * s) / 2, (H - size.height * s) / 2))
    }

    func draw(_ c: CGContext, _ t: CGFloat) {
        let t = onTwos ? (t * 12).rounded(.down) / 12 : t
        let at = from + max(0, min(Double(t), length - 0.05)) * speed
        let (s, o) = fit(t)
        let rect = CGRect(x: o.x, y: o.y, width: size.width * s, height: size.height * s)
        c.interpolationQuality = .high
        func frame(_ i: Double) -> CGImage? {
            try? generator.copyCGImage(at: CMTime(seconds: (i + 0.5) / frameRate, preferredTimescale: 6000), actualTime: nil)
        }
        let index = (at * frameRate).rounded(.down), blend = at * frameRate - index
        guard let image = frame(index) else { return }
        c.draw(image, in: rect)
        if speed < 1, !onTwos, blend > 0.02, let next = frame(index + 1) {
            c.saveGState(); c.setAlpha(blend); c.draw(next, in: rect); c.restoreGState()
        }
    }

    /// The tracked point, in the video's coordinates (y up).
    func point(_ t: CGFloat) -> CGPoint {
        let at = from + max(0, min(Double(t), length)) * speed
        var p = anchor.first?.p ?? .zero
        for (a, b) in zip(anchor, anchor.dropFirst()) where at >= a.t {
            let f = CGFloat(min(1, (at - a.t) / (b.t - a.t)))
            p = P(mix(a.p.x, b.p.x, f), mix(a.p.y, b.p.y, f))
        }
        let (s, o) = fit(t)
        return P(o.x + p.x * s, o.y + (size.height - p.y) * s)
    }
}

let plates: [String: Plate] = ([
    // Shot 1, 2D (from shot-1-still.jpg, midday): the gust line runs from the far right toward the jetty, whitecaps
    // from 3 s, a wave splashes over the jetty at 4.1–4.3 s (2.5 s into the scene, just after "…bro."); camera still.
    // It splashes again at 8 s and 9.5 s (unused).
    "scene1": Plate("brand/promo/generated/shot-1.mp4", from: 1.6, length: 2.8, cue: 1.6),
    // Shot 3, 2D (from shot-3-still.jpg, sunset): asleep until 1.75 s, eyes open at 2 s, paw to the sunglasses and a
    // peek over them 3.5–5.5 s, open grin 5.9–7.2 s; the phone barely moves and its screen is never seen. Gemini took
    // it slower than asked, so it plays from 1.5 s at 1.3× (the grin lands on "…condish."); camera still.
    "scene3": Plate("brand/promo/generated/shot-3.mp4", from: 1.5, length: 4.0, cue: 1.75, speed: 1.3,
                    anchor: [(1.5, P(402, 665)), (2.5, P(405, 670)), (3.5, P(397, 670)), (4.5, P(402, 670)),
                             (5.5, P(397, 670)), (6.5, P(410, 660))]),
    // Shot 2a, 2D (from shot-2a-still.jpg, pink dawn): Gary types, eyes darting between laptop and charts, blinks;
    // camera still. The upper half is plain wall and window, where the metric cards land.
    "scene2a": Plate("brand/promo/generated/shot-2a.mp4", from: 0.3, length: 4.9, cue: 0.3),
    // Shot 2b, 2D (from shot-2b-still.jpg, midday): three riders cross the window left to right from 1 s to 6.2 s,
    // Gary drops his wing at 6.25 s and has turned to the window by 7.2 s, too late.
    "scene2": Plate("brand/promo/generated/shot-2b.mp4", from: 3.5, length: 3.7, cue: 3.5),
    // Shot 4, 2D (from shot-4-still.jpg = shot 3 at 6.63 s, the frame scene 3 ends on): Kai holds the phone in one
    // paw (we see only its back) and taps and scrolls with the other, content, blinks now and then; camera still.
    "scene4": Plate("brand/promo/generated/shot-4.mp4", from: 0.0, length: 5.8, cue: 0.0),
    // Shot 5, 2D (from shot-5-still.jpg, sunset; edited in Gemini after Christian's notes: no handles on the leading
    // edges, Gary both hands on his boom, Kai one paw on his boom and waving): they foil side by side left to right,
    // the camera travels with them and slowly pulls back; Kai waves from the first frame to ~2.5 s, then holds the
    // boom with both paws.
    "scene5": Plate("brand/promo/generated/shot-5.mp4", from: 0.0, length: 3.8, cue: 0.0),
] as [String: Plate?]).compactMapValues { $0 }

/// How long scene 3 holds the shot's first frame (Kai dozing, camera still), so the phone lights up just after the
/// narrator says "…waited for the swoosh."
let scene3Lead: CGFloat = 1.6

/// Scene 3 on a generated shot: the notification pops out of the phone, curves up over the water beside Kai (never
/// over his face: his grin is the payoff) and floats above, trailing bubbles.
func scene3(_ c: CGContext, _ t: CGFloat, on plate: Plate) {
    let shot = t - scene3Lead
    plate.draw(c, shot)
    let phone = plate.point(shot), cue = scene3Lead + CGFloat((plate.cue - plate.from) / plate.speed)
    let out = ramp(t, cue, cue + 0.45), rise = smooth(ramp(t, cue, cue + 0.7))
    let top = P(640, 1590 + 6 * sin(t * 2.4)), bend = P(1150, 820)
    func path(_ u: CGFloat) -> CGPoint {                 // phone → round the left of his face → above his head
        let v = 1 - u
        return P(v * v * phone.x + 2 * v * u * bend.x + u * u * top.x, v * v * phone.y + 2 * v * u * bend.y + u * u * top.y)
    }
    if out > 0 {
        let card = path(rise)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.4 * clamp(out * 2)), rgb(0xBFF3FF, 0)] as CFArray,
                              locations: [0, 1])!
        c.drawRadialGradient(glow, startCenter: card, startRadius: 0, endCenter: card, endRadius: 380, options: [])
        for i in 0..<14 {
            let age = fract(CGFloat(i) / 14 + t * 0.6)
            guard age < rise else { continue }
            let q = path(age)
            let r = 5 + 9 * noise(i)
            let wobble = P(q.x + 18 * sin(CGFloat(i) * 2 + t * 3), q.y)
            fill(c, rgb(0xFFFFFF, 0.3 * (1 - age / max(rise, 0.01))), circle(wobble, r))
            stroke(c, rgb(0xFFFFFF, 0.8 * (1 - age / max(rise, 0.01))), 2, circle(wobble, r))
        }
        let k = mix(0.12, 0.56, pop(out))
        c.saveGState()
        c.translateBy(x: card.x, y: card.y)
        c.rotate(by: mix(0.3, -0.03, rise))
        c.scaleBy(x: k, y: k)
        c.translateBy(x: -420, y: -125)
        c.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0x000000, 0.35))
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        notificationCard(c)
        c.endTransparencyLayer()
        c.restoreGState()
    }
    if t < 2.9 {
        caption(c, "Kai just waited", y: 590, size: 100, appear: ramp(t, 0.25, 0.55))
        caption(c, "for the swoosh.", y: 485, size: 100, appear: ramp(t, 1.0, 1.3), color: orange)
    } else {
        caption(c, "Swoosh means", y: 590, size: 100, appear: ramp(t, 3.0, 3.3))
        caption(c, "condish.", y: 485, size: 100, appear: ramp(t, 4.1, 4.4), color: orange)
    }
}

// MARK: - Timeline and output

let scenes: [(name: String, start: CGFloat, end: CGFloat, draw: (CGContext, CGFloat) -> Void)] = [
    ("scene1", 0, 2.8, scene1), ("scene2a", 2.8, 7.7, scene2a), ("scene2", 7.7, 11.4, scene2),
    ("scene3", 11.4, 17, scene3), ("scene4", 17, 22.8, scene4), ("scene5", 22.8, 26.6, scene5),
    ("scene6", 26.6, duration, scene6),
]

// Arguments: [--only <scene> | --cover] [folder for check frames]
let arguments = Array(CommandLine.arguments.dropFirst())
let only = arguments.firstIndex(of: "--only").map { arguments[$0 + 1] }
let span: (from: CGFloat, to: CGFloat) = only.map { name in
    guard let s = scenes.first(where: { $0.name == name }) else { fatalError("No scene called \(name)") }
    return (s.start, s.end)
} ?? (0, duration)

func frame(_ c: CGContext, _ t: CGFloat) {
    if let only, let scene = scenes.first(where: { $0.name == only }) { scene.draw(c, t - scene.start); return }
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

let checks = arguments.last.flatMap { $0.hasPrefix("--") || $0 == only ? nil : URL(fileURLWithPath: $0) }
let checkTimes: [CGFloat] = only == nil ? [2.0, 6.5, 10.0, 13.5, 16.0, 18.0, 21.5, 25.5, 29.0]
                                        : stride(from: span.from, to: span.to, by: 0.5).map { $0 }

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
/// Six half-resolution noise tiles, cycled frame by frame and drawn with overlay blending (coarser grain, like film).
let grainTiles: [CGImage] = (0..<6).map { seed in
    let w = Int(W) / 2, h = Int(H) / 2
    var state = UInt64(seed + 1) &* 0x9E3779B97F4A7C15
    var pixels = [UInt8](repeating: 0, count: w * h)
    for i in pixels.indices {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        let a = Int(state & 0xFF), b = Int(state >> 8 & 0xFF)          // two samples: a softer, near-Gaussian spread
        pixels[i] = UInt8((a + b) / 2)
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                   decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

// --cover: the Reel's cover image (brand/promo/kookout-cover.png): the opening shot at the splash, Kookout's eyes and
// the first line in the open sky. The profile grid shows only the middle 3:4 (1080 × 1440), so everything that
// matters sits inside it; the check folder gets a copy with the grid crop and Reels' covered areas shaded.
if arguments.contains("--cover"), let plate = plates["scene1"] {
    let c = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    plate.draw(c, 2.5)
    eyes(c, P(W / 2, 1595), width: 340)
    caption(c, "Wind.", y: 1390, size: 130, appear: 1)
    caption(c, "Doesn't wait, bro.", y: 1262, size: 100, appear: 1, color: orange)
    c.saveGState()
    c.setBlendMode(.overlay); c.setAlpha(grain * 2.5)
    c.draw(grainTiles[0], in: CGRect(x: 0, y: 0, width: W, height: H))
    c.restoreGState()
    let image = c.makeImage()!
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "brand/promo/kookout-cover.png"))
    if let checks {
        let gridTop = (H - W * 4 / 3) / 2
        for r in [CGRect(x: 0, y: 0, width: W, height: gridTop), CGRect(x: 0, y: H - gridTop, width: W, height: gridTop)] {
            fill(c, rgb(0x000000, 0.55), CGPath(rect: r, transform: nil))
        }
        for r in [CGRect(x: 0, y: H - instagramTop, width: W, height: instagramTop),
                  CGRect(x: 0, y: 0, width: W, height: instagramBottom),
                  CGRect(x: W - instagramRight, y: instagramBottom, width: instagramRight, height: 650)] {
            fill(c, rgb(0xFF0000, 0.3), CGPath(rect: r, transform: nil))
        }
        try NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
            .write(to: checks.appendingPathComponent("cover-check.png"))
    }
    print("wrote brand/promo/kookout-cover.png")
    exit(0)
}

let output = URL(fileURLWithPath: "brand/promo/kookout-\(only ?? "cartoon").mp4")
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

let frameCount = Int((span.to - span.from) * CGFloat(fps))
for f in 0..<frameCount {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    let pb = buffer!
    CVPixelBufferLockBaseAddress(pb, [])
    let c = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Int(W), height: Int(H), bitsPerComponent: 8,
                      bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: srgb,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let t = span.from + CGFloat(f) / CGFloat(fps)
    frame(c, t)
    if grain > 0 {
        c.saveGState()
        c.setBlendMode(.overlay); c.setAlpha(grain * 2.5)
        c.draw(grainTiles[f % grainTiles.count], in: CGRect(x: 0, y: 0, width: W, height: H))
        c.restoreGState()
    }
    if let checks, checkTimes.contains(where: { abs($0 - t) < 0.5 / CGFloat(fps) }) {
        // Check frames show what Instagram Reels covers: top bar, caption and audio at the bottom, buttons on the right
        let check = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        check.draw(c.makeImage()!, in: CGRect(x: 0, y: 0, width: W, height: H))
        for r in [CGRect(x: 0, y: H - instagramTop, width: W, height: instagramTop),
                  CGRect(x: 0, y: 0, width: W, height: instagramBottom),
                  CGRect(x: W - instagramRight, y: instagramBottom, width: instagramRight, height: 650)] {
            fill(check, rgb(0xFF0000, 0.3), CGPath(rect: r, transform: nil))
        }
        let png = NSBitmapImageRep(cgImage: check.makeImage()!).representation(using: .png, properties: [:])!
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

// Add the swooshes and the narrator, and write the MP4
let video = AVURLAsset(url: silent)
let swoosh = AVURLAsset(url: URL(fileURLWithPath: "brand/swoosh.caf"))
let length = CMTime(value: CMTimeValue(frameCount), timescale: fps)
let composition = AVMutableComposition()
let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: video.tracks(withMediaType: .video)[0], at: .zero)
let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
audioTrack.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: length))
for at in swooshes.map({ $0 - Double(span.from) }) where at >= 0 && at < Double(span.to - span.from) {
    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: swoosh.duration),
                                   of: swoosh.tracks(withMediaType: .audio)[0], at: CMTime(seconds: at, preferredTimescale: 600))
}
let voiceTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
voiceTrack.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: length))
for line in voice {
    let at = line.at - Double(span.from)
    guard at >= 0, at < Double(span.to - span.from) else { continue }
    let take = AVURLAsset(url: URL(fileURLWithPath: "brand/promo/vo/\(line.file).mp3"))
    guard let source = take.tracks(withMediaType: .audio).first else { continue }
    var cursor = at
    for (from, to) in line.parts ?? [(0, take.duration.seconds)] {
        try voiceTrack.insertTimeRange(CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 44100),
                                                   end: CMTime(seconds: to, preferredTimescale: 44100)), of: source,
                                       at: CMTime(seconds: cursor, preferredTimescale: 44100))
        cursor += to - from + 0.2
    }
}
let mix = AVMutableAudioMix()
let swooshLevel = AVMutableAudioMixInputParameters(track: audioTrack)
swooshLevel.setVolume(0.5, at: .zero)
mix.inputParameters = [swooshLevel]
let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
export.audioMix = mix
export.outputURL = output
export.outputFileType = .mp4
export.timeRange = CMTimeRange(start: .zero, duration: length)
let exported = DispatchSemaphore(value: 0)
export.exportAsynchronously { exported.signal() }
exported.wait()
guard export.status == .completed else { fatalError("Export failed: \(String(describing: export.error))") }
print("wrote \(output.path)")
