// An alternative notification sound: a big Chinese tam-tam, the kung-fu-movie gong. About 5 seconds.
// Run from the repo root:  swift -O brand/gong.swift   → brand/gong.caf (the app uses the swoosh, brand/swoosh.swift)
//
// Unlike a bell (a few clear partials, so it has a note), a tam-tam is a dense wash of hundreds of clashing
// partials with no clear pitch. It "blooms" after the hit (the high partials swell in over half a second,
// the roar), and the pitch sags a little as it rings (the "wahhh").

import AVFoundation

let rate = 44_100.0
let length = 5.0
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
let frames = Int(rate * length)
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
buffer.frameLength = AVAudioFrameCount(frames)
let out = buffer.floatChannelData![0]

var seed: UInt64 = 0x4B4F4F4B // fixed, so the gong sounds the same every time it's made
func random() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(seed >> 11) / Double(1 << 53)
}

struct Partial { let freq, level, decay, bloomAt, phase: Double }
var partials: [Partial] = []
// Low body: a hum and its rough neighbours (felt more than heard on a phone)
for f in [72.0, 103, 131, 157] {
    partials.append(Partial(freq: f * (0.98 + 0.04 * random()), level: 0.5, decay: 0.55, bloomAt: 0.0, phase: random() * 6.3))
}
// The wash: 260 partials spread over 180–3600 Hz, quieter and slower to arrive the higher they are
for _ in 0..<260 {
    let f = 180 * pow(20, random()) // log-spaced, 180 Hz…3.6 kHz
    let height = log(f / 180) / log(20) // 0…1
    partials.append(Partial(freq: f, level: 0.09 * (1.1 - height) * (0.5 + random()),
                            decay: 0.7 + 1.6 * height + 0.4 * random(),
                            bloomAt: 0.15 + 0.55 * height + 0.15 * random(), // high partials swell in later
                            phase: random() * 6.3))
}

var peak: Float = 0
var phases = partials.map(\.phase)
for i in 0..<frames {
    let t = Double(i) / rate
    let sag = 1 - 0.035 * (1 - exp(-t / 0.9)) // the pitch drops 3.5% as it rings out
    var v = 0.0
    for (n, p) in partials.enumerated() {
        phases[n] += 2 * .pi * p.freq * sag / rate
        // Swell: rises to full around bloomAt, then fades
        let swell = p.bloomAt == 0 ? 1 : (1 - exp(-t / p.bloomAt))
        v += p.level * swell * exp(-p.decay * t) * sin(phases[n])
    }
    // The mallet: a soft, dull thud, and a short splash of noise
    v += 0.9 * exp(-t / 0.035) * sin(2 * .pi * 55 * t)
    v += 0.25 * exp(-t / 0.05) * (random() * 2 - 1)
    let sample = Float(v * min(1, t / 0.004))
    out[i] = sample
    peak = max(peak, abs(sample))
}

// Normalise just under full scale and fade the tail out.
let fade = Int(0.8 * rate)
for i in 0..<frames {
    out[i] *= 0.89 / peak
    if i >= frames - fade { out[i] *= Float(Double(frames - i) / Double(fade)) }
}

let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
for path in ["brand/gong.caf"] {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: buffer)
    print("wrote \(path)")
}
