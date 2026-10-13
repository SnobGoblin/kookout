// Kookout's notification sound: a wind swoosh, a gust that rushes past, about 2.5 seconds.
// Run from the repo root:  swift -O brand/swoosh.swift   → brand/swoosh.caf and ios/Kookout/kookout.caf
//
// Wind is noise through a resonant band-pass filter: sweeping the filter up and back down makes the "whoosh",
// a second, narrow filter on top gives the faint whistle you hear in rigging.

import AVFoundation

let rate = 44_100.0
let length = 2.6
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
let frames = Int(rate * length)
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
buffer.frameLength = AVAudioFrameCount(frames)
let out = buffer.floatChannelData![0]

var seed: UInt64 = 0x57494E44
func noise() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(seed >> 11) / Double(1 << 53) * 2 - 1
}

/// A state-variable band-pass filter (Chamberlin), retuned every sample.
struct BandPass {
    var low = 0.0, band = 0.0
    mutating func run(_ x: Double, freq: Double, q: Double) -> Double {
        let f = 2 * sin(.pi * min(freq, rate / 6) / rate)
        low += f * band
        let high = x - low - band / q
        band += f * high
        return band
    }
}

var rush = BandPass(), body = BandPass(), whistle = BandPass()
var peak: Float = 0
for i in 0..<frames {
    let t = Double(i) / rate
    let p = t / length // 0…1 through the gust
    // The gust: swells in, peaks at about 40%, and trails away
    let gust = pow(sin(.pi * pow(p, 0.75)), 2.2)
    // The filter rushes up to ~1.6 kHz and back down: the swoosh going past
    let sweep = 260 + 1350 * pow(sin(.pi * pow(p, 0.8)), 1.6)
    let n = noise()
    var v = 1.0 * rush.run(n, freq: sweep, q: 1.4)
    v += 0.6 * body.run(n, freq: 180 + 160 * gust, q: 0.8)              // low rumble under it
    v += 0.10 * gust * whistle.run(n, freq: sweep * 2.1, q: 25)          // faint whistle at the peak
    let sample = Float(v * gust)
    out[i] = sample
    peak = max(peak, abs(sample))
}
for i in 0..<frames { out[i] *= 0.89 / peak }

let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
for path in ["brand/swoosh.caf", "ios/Kookout/kookout.caf"] {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: buffer)
    print("wrote \(path)")
}
