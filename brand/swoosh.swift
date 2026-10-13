// Kookout's notification sound: a wind swoosh, a gust that rushes past, about 2.5 seconds.
// Run from the repo root:  swift -O brand/swoosh.swift   → brand/swoosh.caf and ios/Kookout/kookout.caf
//
// Wind is noise through a band-pass filter: sweeping it up and back down makes the "whoosh". It stays below
// ~1 kHz with a low-pass on top: iPhone speakers are loudest at 2–4 kHz, where any hiss turns into a saw.

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

var rush = BandPass(), body = BandPass()
var smooth1 = 0.0, smooth2 = 0.0 // two one-pole low-passes, cutting the hiss above ~1.2 kHz
let cut = 1 - exp(-2 * .pi * 1200 / rate)
var peak: Float = 0
for i in 0..<frames {
    let t = Double(i) / rate
    let p = t / length // 0…1 through the gust
    // The gust: swells in, peaks at about 40%, and trails away
    let gust = pow(sin(.pi * pow(p, 0.75)), 2.2)
    // The filter rushes up to ~800 Hz and back down: the swoosh going past
    let sweep = 300 + 500 * pow(sin(.pi * pow(p, 0.8)), 1.6)
    let n = noise()
    var v = 1.0 * rush.run(n, freq: sweep, q: 0.9)
    v += 0.7 * body.run(n, freq: 220 + 120 * gust, q: 0.7)              // low body under it
    smooth1 += cut * (v - smooth1)
    smooth2 += cut * (smooth1 - smooth2)
    let sample = Float(smooth2 * gust)
    out[i] = sample
    peak = max(peak, abs(sample))
}
for i in 0..<frames { out[i] *= 0.7 / peak } // a little quieter than full scale

let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
for path in ["brand/swoosh.caf", "ios/Kookout/kookout.caf"] {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: buffer)
    print("wrote \(path)")
}
