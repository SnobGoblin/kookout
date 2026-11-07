import AVFoundation
// swift brand/promo/tools/segments.swift <audio>. Prints the spoken segments (gaps ≥ 0.18 s below -40 dB) of an audio file.
let file = try! AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
let fmt = file.processingFormat, n = AVAudioFrameCount(file.length)
let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!; try! file.read(into: buf)
let sr = fmt.sampleRate, d = buf.floatChannelData![0], win = Int(sr * 0.02)
var segs: [(Double, Double)] = []; var start: Double? = nil; var lastLoud = 0.0
var i = 0
while i + win < Int(buf.frameLength) {
  var s: Float = 0; for k in i..<i+win { s += d[k]*d[k] }
  let db = 10 * log10(s / Float(win) + 1e-12), t = Double(i) / sr
  if db > -40 { if start == nil { start = t }; lastLoud = t + 0.02 }
  else if let st = start, t - lastLoud > 0.18 { segs.append((st, lastLoud)); start = nil }
  i += win
}
if let st = start { segs.append((st, lastLoud)) }
print(String(format: "length %.2f", Double(file.length) / sr))
for (a, b) in segs { print(String(format: "  %.2f–%.2f", a, b)) }
