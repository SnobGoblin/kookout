// Puts the App Store screenshots in a phone frame on navy, with a caption above. Run from the repo root:
//   swift appstore/frame.swift
// Reads appstore/screenshots/*.png (plain Simulator screenshots, 6.9-inch: 1320 × 2868) and writes the
// framed versions, the same size, to appstore/framed/. Captions are the ones in appstore/listing-en.md.

import AppKit
import CoreText
import Foundation

let captions: [(file: String, caption: String)] = [
    ("1-list", "Know when your spots are good"),
    ("2-notification", "Get told when it's on"),
    ("3-forecast", "See why, hour by hour"),
    ("4-rules", "Your spot, your rules"),
    ("5-add-spot", "Popular spots, or any spot in the world"),
]

let width = 1320, height = 2868
let navy = CGColor(red: 0x0E / 255, green: 0x2A / 255, blue: 0x3B / 255, alpha: 1)
let navyLight = CGColor(red: 0x1C / 255, green: 0x4A / 255, blue: 0x66 / 255, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let bezel = CGColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1)

func archivo(size: CGFloat) -> CTFont {
    let url = URL(fileURLWithPath: "brand/fonts/Archivo[wdth,wght].ttf")
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
          let base = descriptors.first else { fatalError("Can't read \(url.path)") }
    func tag(_ s: String) -> Int { s.utf8.reduce(0) { $0 << 8 | Int($1) } }
    let variation = [tag("wght"): 800, tag("wdth"): 100] as CFDictionary
    let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: variation] as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

// The phone: the screenshot at 76 %, in a thin dark bezel with the iPhone's rounded corners.
let scale: CGFloat = 0.76
let screen = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
let border: CGFloat = 20
let screenRadius: CGFloat = 186 * scale
let phoneTop: CGFloat = 560   // from the top; the caption sits in the space above

func frame(_ name: String, _ caption: String) throws {
    let input = URL(fileURLWithPath: "appstore/screenshots/\(name).png")
    guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
          let shot = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Can't read \(input.path)") }
    guard shot.width == width, shot.height == height else {
        fatalError("\(name).png is \(shot.width) × \(shot.height), expected \(width) × \(height)")
    }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let H = CGFloat(height), W = CGFloat(width)

    // Background: navy, a little lighter towards the bottom.
    let gradient = CGGradient(colorsSpace: cs, colors: [navy, navyLight] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    // Caption: centred, wrapped, in the space above the phone.
    var centred = CTTextAlignment.center
    let style = withUnsafeBytes(of: &centred) { bytes in
        CTParagraphStyleCreate([CTParagraphStyleSetting(spec: .alignment, valueSize: bytes.count,
                                                        value: bytes.baseAddress!)], 1)
    }
    let text = NSAttributedString(string: caption, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): archivo(size: 104),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): white,
        NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style])
    let setter = CTFramesetterCreateWithAttributedString(text)
    let textWidth: CGFloat = 1120
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: textWidth, height: 1000), nil)
    let textTop = (phoneTop - fit.height) / 2 + 10
    let textRect = CGRect(x: (W - textWidth) / 2, y: H - textTop - fit.height, width: textWidth, height: ceil(fit.height))
    CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: textRect, transform: nil), nil), ctx)

    // Phone: shadow, bezel, then the screenshot clipped to the screen's corners.
    let screenRect = CGRect(x: (W - screen.width) / 2, y: H - phoneTop - border - screen.height,
                            width: screen.width, height: screen.height)
    let bodyRect = screenRect.insetBy(dx: -border, dy: -border)
    let body = CGPath(roundedRect: bodyRect, cornerWidth: screenRadius + border, cornerHeight: screenRadius + border, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 80, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
    ctx.addPath(body); ctx.setFillColor(bezel); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screenRect, cornerWidth: screenRadius, cornerHeight: screenRadius, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(shot, in: screenRect)
    ctx.restoreGState()

    let output = URL(fileURLWithPath: "appstore/framed/\(name).png")
    let dest = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("Can't write \(output.path)") }
    print("wrote \(output.path)")
}

try FileManager.default.createDirectory(atPath: "appstore/framed", withIntermediateDirectories: true)
for (file, caption) in captions { try frame(file, caption) }
