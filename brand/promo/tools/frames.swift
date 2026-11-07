import AVFoundation
import AppKit
// Writes a PNG every `step` seconds (default 0.5) of a video, to look at a generated shot before cutting it in.
// swift brand/promo/tools/frames.swift <video> <out folder> [step] [from]
let url = URL(fileURLWithPath: CommandLine.arguments[1]), out = CommandLine.arguments[2]
let step = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3])! : 0.5
let asset = AVURLAsset(url: url)
let dur = CMTimeGetSeconds(asset.duration)
for t in asset.tracks { print(t.mediaType.rawValue, t.naturalSize, t.nominalFrameRate, CMTimeGetSeconds(t.timeRange.duration)) }
let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
var t = CommandLine.arguments.count > 4 ? Double(CommandLine.arguments[4])! : 0; var i = 0
while t < dur {
  if let img = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
    let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: out + String(format: "/f%02d-%05.2f.png", i, t)))
  }
  t += step; i += 1
}
