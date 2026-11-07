// Contact sheet: swift brand/promo/tools/sheet.swift <out.png> <frame.png>… (5 columns, 270 × 480 each)
import AppKit
let files = CommandLine.arguments.dropFirst(2).map { URL(fileURLWithPath: $0) }
let w = 270, h = 480, cols = 5, rows = (files.count + cols - 1) / cols
let c = CGContext(data: nil, width: w*cols, height: h*rows, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
c.interpolationQuality = .high
for (i, f) in files.enumerated() {
  guard let img = NSImage(contentsOf: f)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
  c.draw(img, in: CGRect(x: (i % cols) * w, y: (rows - 1 - i / cols) * h, width: w, height: h))
}
try! NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
