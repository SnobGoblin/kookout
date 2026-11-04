// Draws Kookout's cartoon promo for social media (9:16, 1080 × 1920, 30 fps, 18 s) frame by frame, with the
// brand's own swoosh. Run from the repo root:  swift -O brand/promo.swift [folder for check frames]
//
// Writes brand/promo/kookout-cartoon.mp4. With a folder, also writes a PNG of a few frames there, to look at.
//
// The story (pitch: Kookout tells you when and where, no rechecking):
//   1. 0–4.4 s    a rider on the sofa on a rainy day, refreshing the forecast while the clock spins
//   2. 4.4–8.4 s  the phone buzzes: "Home spot: Tomorrow 2–6 PM good" (swoosh); the rider's eyes turn into Kookout's
//   3. 8.4–14 s   out wing foiling at the home spot
//   4. 14–18 s    end card: the logo's eyes look left, right and back, as in the app's splash

import AppKit
import AVFoundation
import CoreText
import Foundation

let W: CGFloat = 1080, H: CGFloat = 1920
let fps: Int32 = 30
let duration: CGFloat = 18
let fade: CGFloat = 0.35                                  // crossfade between scenes
let swooshes: [Double] = [4.9, 14.1]                      // when the swoosh plays (s)

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
            .init(kCTForegroundColorAttributeName as String): color]
        if stroke, let outline {
            a[.init(kCTStrokeColorAttributeName as String)] = outline
            a[.init(kCTStrokeWidthAttributeName as String)] = 24
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

// MARK: - Scene 1: the sofa, a rainy day, refreshing the forecast

func refreshIcon(_ c: CGContext, _ p: CGPoint, r: CGFloat, alpha: CGFloat) {
    c.saveGState()
    c.setAlpha(alpha)
    let start: CGFloat = 0.6, end: CGFloat = 0.6 + 4.9
    let arc = CGMutablePath()
    arc.addArc(center: p, radius: r, startAngle: start, endAngle: end, clockwise: false)
    stroke(c, white, r * 0.3, arc)
    let e = P(p.x + r * cos(end), p.y + r * sin(end))
    let along = P(-sin(end), cos(end)), out = P(cos(end), sin(end))
    let head = CGMutablePath()
    head.addLines(between: [P(e.x + along.x * r * 0.55, e.y + along.y * r * 0.55),
                            P(e.x + out.x * r * 0.42, e.y + out.y * r * 0.42),
                            P(e.x - out.x * r * 0.42, e.y - out.y * r * 0.42)])
    head.closeSubpath()
    fill(c, white, head)
    c.restoreGState()
}

func scene1(_ c: CGContext, _ t: CGFloat) {
    // Wall and floor
    fill(c, rgb(0x2E3F4B), CGPath(rect: CGRect(x: 0, y: 0, width: W, height: H), transform: nil))
    fill(c, rgb(0x22303A), CGPath(rect: CGRect(x: 0, y: 0, width: W, height: 470), transform: nil))

    // Window: grey sky, dark clouds, rain
    let win = CGRect(x: 110, y: 1010, width: 420, height: 470)
    fill(c, rgb(0xDCE3E8), rr(win.insetBy(dx: -22, dy: -22), 18))
    c.saveGState()
    c.addPath(rr(win, 6)); c.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let sky = CGGradient(colorsSpace: space, colors: [rgb(0x6F7E89), rgb(0xA9B5BD)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(sky, start: P(0, win.maxY), end: P(0, win.minY), options: [])
    for (x, y, r) in [(150.0, 1440.0, 70.0), (240, 1460, 80), (340, 1440, 66), (450, 1450, 74), (520, 1430, 60)] {
        fill(c, rgb(0x5E6C76), circle(P(x - fract(t * 0.05) * 40, y), r))
    }
    for i in 0..<34 {
        let x = win.minX + fract(CGFloat(i) * 0.618) * (win.width + 60)
        let y = win.maxY + 40 - fract(CGFloat(i) * 0.37 + t * 1.7) * (win.height + 100)
        stroke(c, rgb(0xFFFFFF, 0.55), 5, polyline(P(x, y), P(x - 14, y - 46)))
    }
    c.restoreGState()
    stroke(c, rgb(0xDCE3E8), 16, polyline(P(win.midX, win.minY), P(win.midX, win.maxY)))
    stroke(c, rgb(0xDCE3E8), 16, polyline(P(win.minX, win.midY), P(win.maxX, win.midY)))

    // Clock, spinning: hours go by
    let clock = P(850, 1330)
    fill(c, white, circle(clock, 95))
    stroke(c, navy, 12, circle(clock, 95))
    for i in 0..<12 {
        let a = CGFloat(i) * .pi / 6
        stroke(c, navy, 6, polyline(P(clock.x + 72 * cos(a), clock.y + 72 * sin(a)), P(clock.x + 82 * cos(a), clock.y + 82 * sin(a))))
    }
    let hour = .pi / 2 - t * 2.4, minute = .pi / 2 - t * 2.4 * 12
    stroke(c, navy, 12, polyline(clock, P(clock.x + 45 * cos(hour), clock.y + 45 * sin(hour))))
    stroke(c, navy, 8, polyline(clock, P(clock.x + 70 * cos(minute), clock.y + 70 * sin(minute))))
    fill(c, orange, circle(clock, 10))

    // Sofa
    fill(c, rgb(0x000000, 0.25), ellipse(P(540, 285), 520, 40))
    fill(c, sea, rr(CGRect(x: 90, y: 430, width: 900, height: 390), 70))
    fill(c, rgb(0x175C8A), rr(CGRect(x: 70, y: 300, width: 940, height: 220), 60))

    // The rider: legs, hoodie, arms, phone, head
    let jeans = rgb(0x34567A)
    fill(c, jeans, rr(CGRect(x: 428, y: 190, width: 98, height: 360), 46))
    fill(c, jeans, rr(CGRect(x: 554, y: 190, width: 98, height: 360), 46))
    fill(c, white, ellipse(P(470, 185), 66, 34))
    fill(c, white, ellipse(P(610, 185), 66, 34))
    fill(c, orange, rr(CGRect(x: 380, y: 500, width: 320, height: 380), 130))
    fill(c, rgb(0xE85A1E), rr(CGRect(x: 450, y: 560, width: 180, height: 90), 40))
    fill(c, skin, CGPath(rect: CGRect(x: 510, y: 840, width: 60, height: 70), transform: nil))

    // Phone, flickering through forecasts
    fill(c, rgb(0x111518), rr(CGRect(x: 478, y: 650, width: 124, height: 212), 22))
    fill(c, rgb(0xCFE8F7), rr(CGRect(x: 486, y: 660, width: 108, height: 192), 16))
    let page = Int(t * 6)
    for row in 0..<5 {
        let y = 820 - CGFloat(row) * 34
        fill(c, rgb(0x1C6EA4, 0.8), circle(P(502, y), 7))
        fill(c, rgb(0x0E2A3B, 0.55), rr(CGRect(x: 516, y: y - 6, width: 18 + 56 * noise(page * 7 + row), height: 12), 6))
    }
    let tap = max(0, sin(t * 18)) * 8
    stroke(c, orange, 64, polyline(P(405, 800), P(470, 720)))
    stroke(c, orange, 64, polyline(P(675, 800), P(612, 720 + tap)))
    fill(c, skin, circle(P(476, 724), 34))
    fill(c, skin, circle(P(606, 724 + tap), 34))

    // Head, beanie, bored eyes
    let head = P(540, 1010)
    fill(c, skinShade, circle(P(413, 995), 28))
    fill(c, skinShade, circle(P(667, 995), 28))
    fill(c, skin, circle(head, 125))
    c.saveGState()
    c.addPath(circle(head, 132)); c.clip()
    fill(c, navy, CGPath(rect: CGRect(x: 380, y: 1060, width: 320, height: 200), transform: nil))
    c.restoreGState()
    fill(c, rgb(0x0A1F2C), rr(CGRect(x: 405, y: 1040, width: 270, height: 50), 25))
    fill(c, orange, circle(P(540, 1150), 30))
    let blink = fract(t / 2.3) < 0.06
    for ex in [CGFloat(493), 587] {
        let e = CGRect(x: ex - 32, y: 966, width: 64, height: 72)
        c.saveGState()
        c.addEllipse(in: e); c.clip()
        fill(c, white, CGPath(rect: e, transform: nil))
        fill(c, navy, circle(P(ex + 2, 984), 16))
        let lid = e.maxY - (blink ? 1 : 0.45) * e.height
        fill(c, skin, CGPath(rect: CGRect(x: e.minX, y: lid, width: e.width, height: e.maxY - lid), transform: nil))
        stroke(c, navy, 7, polyline(P(e.minX, lid), P(e.maxX, lid)))
        c.restoreGState()
        stroke(c, navy, 5, CGPath(ellipseIn: e, transform: nil))
    }
    stroke(c, navy, 8, curve(P(505, 922), P(540, 940), P(575, 922)))

    // Refresh, refresh, refresh
    for k in 0..<12 {
        let age = (t - 0.2 - CGFloat(k) * 0.42) / 1.3
        guard age > 0, age < 1 else { continue }
        let side: CGFloat = k % 2 == 0 ? 1 : -1
        refreshIcon(c, P(540 + side * (110 + 230 * sqrt(age)), 860 + 440 * age), r: 30 + 12 * age, alpha: 1 - age * age)
    }

    caption(c, "Checking the", y: 1730, size: 104, appear: ramp(t, 0.3, 0.75))
    caption(c, "forecast again?", y: 1600, size: 104, appear: ramp(t, 1.1, 1.55), color: orange)
}

// MARK: - Scene 2: the phone buzzes

func scene2(_ c: CGContext, _ t: CGFloat) {
    let center = P(540, 860)
    fill(c, sea, CGPath(rect: CGRect(x: 0, y: 0, width: W, height: H), transform: nil))
    let burst = ramp(t, 0.5, 0.9)
    if burst > 0 {
        for i in 0..<18 {
            let a = CGFloat(i) * 2 * .pi / 18 + t * 0.15
            let wedge = CGMutablePath()
            wedge.move(to: center)
            wedge.addLine(to: P(center.x + 2000 * cos(a), center.y + 2000 * sin(a)))
            wedge.addLine(to: P(center.x + 2000 * cos(a + .pi / 18), center.y + 2000 * sin(a + .pi / 18)))
            wedge.closeSubpath()
            fill(c, rgb(0x2A86C0, burst), wedge)
        }
    }

    // Buzz: the phone shakes, with lines at its sides
    let buzz = max(0, 1 - abs(t - 0.45) / 0.35)
    if buzz > 0 {
        for i in [CGFloat(-1), 0, 1] {
            stroke(c, rgb(0xFFFFFF, buzz), 12, polyline(P(200, 860 + i * 130), P(150, 860 + i * 160)))
            stroke(c, rgb(0xFFFFFF, buzz), 12, polyline(P(880, 860 + i * 130), P(930, 860 + i * 160)))
        }
    }
    c.saveGState()
    c.translateBy(x: center.x, y: center.y)
    c.rotate(by: 0.045 * sin(t * 75) * buzz)
    c.translateBy(x: -center.x, y: -center.y)

    for i in 0..<3 {                                     // fingers behind the phone
        fill(c, skin, ellipse(P(845, 560 + CGFloat(i) * 115), 52, 40))
        fill(c, skin, ellipse(P(235, 600 + CGFloat(i) * 115), 52, 40))
    }
    let phone = CGRect(x: 240, y: 270, width: 600, height: 1180)
    fill(c, rgb(0x0B0F12), rr(phone, 96))
    let screen = phone.insetBy(dx: 22, dy: 22)
    c.saveGState()
    c.addPath(rr(screen, 76)); c.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let wall = CGGradient(colorsSpace: space, colors: [rgb(0x1B3B52), rgb(0x3E7FA8)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(wall, start: P(0, screen.maxY), end: P(0, screen.minY), options: [])
    c.restoreGState()
    fill(c, rgb(0x000000), rr(CGRect(x: 455, y: 1360, width: 170, height: 50), 25))
    text(c, "Friday, November 6", x: 540, y: 1270, size: 40, weight: 600, color: rgb(0xFFFFFF, 0.85))
    text(c, "10:42", x: 540, y: 1080, size: 200, weight: 700, color: rgb(0xFFFFFF, 0.95))

    // The notification
    let appear = ramp(t, 0.5, 0.85)
    if appear > 0 {
        let banner = CGRect(x: 280, y: 796, width: 520, height: 168)
        let k = mix(0.6, 1, pop(appear))
        c.saveGState()
        c.translateBy(x: banner.midX, y: banner.midY); c.scaleBy(x: k, y: k); c.translateBy(x: -banner.midX, y: -banner.midY)
        c.setAlpha(clamp(appear * 2))
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        fill(c, rgb(0xFFFFFF, 0.94), rr(banner, 40))
        let icon = CGRect(x: banner.minX + 22, y: banner.midY - 50, width: 100, height: 100)
        fill(c, navy, rr(icon, 24))
        eyes(c, P(icon.midX, icon.midY), width: 78)
        text(c, "Home spot", x: banner.minX + 142, y: banner.midY + 14, size: 40, weight: 800, color: rgb(0x111111), align: 0)
        text(c, "now", x: banner.maxX - 26, y: banner.midY + 14, size: 30, weight: 500, color: rgb(0x777777), align: 1)
        text(c, "Tomorrow 2–6 PM good", x: banner.minX + 142, y: banner.midY - 40, size: 36, weight: 500,
             color: rgb(0x222222), align: 0, maxWidth: banner.width - 166)
        c.endTransparencyLayer()
        c.restoreGState()
    }
    fill(c, skin, ellipse(P(250, 520), 48, 92))       // left thumb, in front
    c.restoreGState()

    // The rider pops up: eyes turned into Kookout's
    let up = ramp(t, 1.8, 2.25)
    if up > 0 {
        let y = mix(-260, 230, pop(up)), x: CGFloat = 835
        for i in 0..<3 {
            let a = 2.2 + CGFloat(i) * 0.35
            stroke(c, rgb(0xFFFFFF, up), 12, polyline(P(x + 230 * cos(a), y + 230 * sin(a)), P(x + 290 * cos(a), y + 290 * sin(a))))
        }
        fill(c, skinShade, circle(P(x - 185, y - 10), 36))
        fill(c, skinShade, circle(P(x + 185, y - 10), 36))
        fill(c, skin, circle(P(x, y), 185))
        c.saveGState()
        c.addPath(circle(P(x, y), 192)); c.clip()
        fill(c, navy, CGPath(rect: CGRect(x: x - 200, y: y + 85, width: 400, height: 200), transform: nil))
        c.restoreGState()
        fill(c, rgb(0x0A1F2C), rr(CGRect(x: x - 200, y: y + 62, width: 400, height: 64), 32))
        fill(c, orange, circle(P(x, y + 205), 40))
        eyes(c, P(x, y - 10), width: 290, look: 0.03 * sin(t * 9), pupil: navy, sclera: white)
        fill(c, navy, ellipse(P(x, y - 112), 30, 36))
    }

    caption(c, "Kookout tells you", y: 1730, size: 104, appear: ramp(t, 0.9, 1.3))
    caption(c, "when…", y: 1600, size: 104, appear: ramp(t, 1.3, 1.7), color: orange)
}

// MARK: - Scene 3: wing foiling at the home spot

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

func scene3(_ c: CGContext, _ t: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let sky = CGGradient(colorsSpace: space, colors: [rgb(0x4FAEE6), rgb(0xC4E8F8)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(sky, start: P(0, H), end: P(0, 820), options: [.drawsAfterEndLocation])

    // Sun and clouds, blown along
    let sun = P(880, 1250)
    for i in 0..<10 {
        let a = CGFloat(i) * .pi / 5 + t * 0.4
        stroke(c, rgb(0xFFD45A), 14, polyline(P(sun.x + 120 * cos(a), sun.y + 120 * sin(a)), P(sun.x + 160 * cos(a), sun.y + 160 * sin(a))))
    }
    fill(c, rgb(0xFFD45A), circle(sun, 90))
    for (x0, y, s, v) in [(300.0, 1420.0, 1.15, 70.0), (900, 1500, 0.8, 55), (650, 1130, 0.9, 85)] {
        cloud(c, P(fract((x0 + t * v) / (W + 400)) * (W + 400) - 200, y), s)
    }
    for i in 0..<5 {                                     // wind
        let y = 960 + CGFloat(i) * 105
        let x = fract((CGFloat(i) * 313 + t * 520) / (W + 600)) * (W + 600) - 300
        let streak = CGMutablePath()
        streak.move(to: P(x, y))
        streak.addCurve(to: P(x + 240, y + 6), control1: P(x + 80, y + 26), control2: P(x + 160, y - 20))
        stroke(c, rgb(0xFFFFFF, 0.75), 7, streak)
    }

    // Land across the fjord, then the sea
    let hills = CGMutablePath()
    hills.move(to: P(0, 800))
    hills.addQuadCurve(to: P(300, 820), control: P(130, 940))
    hills.addQuadCurve(to: P(620, 820), control: P(470, 900))
    hills.addQuadCurve(to: P(W, 820), control: P(860, 870))
    hills.addLine(to: P(W, 780)); hills.addLine(to: P(0, 780)); hills.closeSubpath()
    fill(c, rgb(0x4E8C7A), hills)
    fill(c, rgb(0x3A93C9), CGPath(rect: CGRect(x: 0, y: 0, width: W, height: 822), transform: nil))
    band(c, rgb(0x2F86BF), base: 770, amp: 8, k: 0.02, speed: 2.0, t)
    band(c, rgb(0x2477AF), base: 650, amp: 14, k: 0.012, speed: 2.6, t)

    // The rider, flying on the foil
    let x = mix(-160, 1180, t / 5.6), by = 560 + 14 * sin(t * 2.6)
    let front = (base: CGFloat(420), amp: CGFloat(22), k: CGFloat(0.009), speed: CGFloat(3.2))
    stroke(c, rgb(0x1D2329), 11, polyline(P(x + 20, by - 12), P(x + 20, by - 175)))
    fill(c, rgb(0x1D2329), ellipse(P(x + 40, by - 176), 62, 10))
    c.saveGState()
    c.translateBy(x: x + 20, y: by + 515)
    c.rotate(by: -0.15 + 0.05 * sin(t * 1.7))
    let wing = CGMutablePath()
    wing.move(to: P(-270, -30))
    wing.addQuadCurve(to: P(270, -30), control: P(0, 200))
    wing.addQuadCurve(to: P(-270, -30), control: P(0, 70))
    fill(c, orange, wing)
    fill(c, rgb(0xC4E8F8, 0.75), ellipse(P(-110, 40), 46, 22))
    stroke(c, orangeDark, 28, curve(P(-270, -30), P(0, 200), P(270, -30)))
    stroke(c, orangeDark, 20, polyline(P(0, 85), P(0, 22)))
    c.restoreGState()
    fill(c, rgb(0x0B1E2A), rr(CGRect(x: x - 115, y: by - 13, width: 230, height: 26), 13))
    stroke(c, wetsuit, 34, polyline(P(x - 45, by + 14), P(x - 15, by + 82), P(x + 5, by + 150)))
    stroke(c, wetsuit, 34, polyline(P(x + 45, by + 14), P(x + 62, by + 86), P(x + 5, by + 150)))
    stroke(c, wetsuit, 76, polyline(P(x + 5, by + 150), P(x + 20, by + 285)))
    fill(c, orange, rr(CGRect(x: x - 28, y: by + 185, width: 86, height: 104), 32))
    stroke(c, wetsuit, 26, polyline(P(x + 20, by + 285), P(x - 30, by + 372), P(x - 62, by + 470)))
    stroke(c, wetsuit, 26, polyline(P(x + 20, by + 285), P(x + 62, by + 378), P(x + 92, by + 465)))
    fill(c, skin, circle(P(x - 62, by + 472), 17))
    fill(c, skin, circle(P(x + 92, by + 467), 17))
    let head = P(x + 28, by + 350)
    fill(c, skin, circle(head, 46))
    c.saveGState()
    c.addPath(circle(head, 50)); c.clip()
    fill(c, orange, CGPath(rect: CGRect(x: head.x - 60, y: head.y + 8, width: 120, height: 60), transform: nil))
    c.restoreGState()
    fill(c, white, circle(P(head.x + 22, head.y - 4), 13))
    fill(c, navy, circle(P(head.x + 27, head.y - 4), 6))
    stroke(c, navy, 6, curve(P(head.x + 4, head.y - 22), P(head.x + 26, head.y - 44), P(head.x + 42, head.y - 22)))

    // Spray where the mast meets the water, then the near waves over the foil
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
    let sign = ramp(t, 2.0, 2.4)
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
        let board = CGRect(x: 60, y: 200, width: 340, height: 100)
        fill(c, white, rr(board, 22))
        stroke(c, navy, 6, rr(board, 22))
        text(c, "Home spot", x: board.minX + 24, y: board.midY - 15, size: 44, weight: 800, color: navy, align: 0)
        let pill = CGRect(x: board.maxX - 134, y: board.midY - 28, width: 116, height: 56)
        fill(c, green, rr(pill, 28))
        text(c, "GOOD", x: pill.midX, y: pill.midY - 11, size: 30, weight: 800, color: white)
        c.restoreGState()
    }

    caption(c, "…and where.", y: 1730, size: 120, appear: ramp(t, 0.5, 0.9))
    caption(c, "No more rechecking.", y: 1600, size: 96, appear: ramp(t, 2.6, 3.0), color: orange)
}

// MARK: - Scene 4: end card

func scene4(_ c: CGContext, _ t: CGFloat) {
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
        text(c, "On the App Store  ·  kookout.no", x: W / 2, y: 500, size: 44, weight: 700, color: orange)
        c.restoreGState()
    }
}

// MARK: - Timeline and output

let scenes: [(start: CGFloat, end: CGFloat, draw: (CGContext, CGFloat) -> Void)] = [
    (0, 4.4, scene1), (4.4, 8.4, scene2), (8.4, 14, scene3), (14, duration, scene4),
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
let checkTimes: [CGFloat] = [1.0, 2.6, 4.3, 5.5, 6.9, 7.9, 9.6, 11.3, 13.0, 14.6, 15.4, 17.5]

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
