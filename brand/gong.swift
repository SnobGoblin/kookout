// A big gong as an alternative notification sound, about 4 seconds.
// Run from the repo root:  swift brand/gong.swift   → brand/gong.caf  (copy to ios/Kookout/kookout.caf to use it)

import AVFoundation

let rate = 44_100.0
let length = 4.0
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
let frames = AVAudioFrameCount(rate * length)
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
buffer.frameLength = frames
let out = buffer.floatChannelData![0]

// Inharmonic partials over a low fundamental. "bloom" makes the higher ones swell after the hit, like a real gong,
// and a slow wobble ("beat") between close pairs gives the shimmer. Phone speakers can't play the 98 Hz hum,
// so the 200–900 Hz partials carry the size.
let fundamental = 98.0
let partials: [(ratio: Double, level: Double, decay: Double, bloom: Double)] = [
    (1.00, 0.55, 0.9, 0.00), (1.52, 0.45, 1.1, 0.05), (2.03, 0.70, 1.0, 0.10), (2.08, 0.55, 1.0, 0.12),
    (2.94, 0.65, 1.3, 0.25), (3.40, 0.50, 1.6, 0.30), (4.16, 0.45, 1.9, 0.45), (4.22, 0.35, 1.9, 0.50),
    (5.43, 0.30, 2.4, 0.60), (6.79, 0.22, 3.0, 0.70), (8.21, 0.14, 4.0, 0.80), (11.3, 0.08, 6.0, 0.90),
]
var peak: Float = 0
for i in 0..<Int(frames) {
    let t = Double(i) / rate
    var v = 0.0
    for (n, p) in partials.enumerated() {
        let swell = 1 - p.bloom * exp(-t / 0.35)              // starts quieter, blooms in over ~0.4 s
        let wobble = 1 + 0.08 * sin(2 * .pi * (0.7 + Double(n) * 0.13) * t)
        v += p.level * swell * wobble * exp(-p.decay * t) * sin(2 * .pi * fundamental * p.ratio * t + Double(n))
    }
    // The mallet: a short, soft thump at the start
    v += 0.6 * exp(-t / 0.02) * sin(2 * .pi * 60 * t)
    let sample = Float(v * min(1, t / 0.006))
    out[i] = sample
    peak = max(peak, abs(sample))
}
// Normalise to just under full scale, and fade the end.
let fade = Int(0.4 * rate)
for i in 0..<Int(frames) {
    out[i] *= 0.89 / peak
    if i >= Int(frames) - fade { out[i] *= Float(Double(Int(frames) - i) / Double(fade)) }
}

let url = URL(fileURLWithPath: "brand/gong.caf")
try? FileManager.default.removeItem(at: url)
let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
try file.write(from: buffer)
print("wrote \(url.path)")
