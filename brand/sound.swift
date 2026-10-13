// Makes Kookout's notification sound: two strikes of a small buoy bell, about 1.3 seconds.
// Run from the repo root:  swift brand/sound.swift   → ios/Kookout/kookout.caf
// (iOS plays a custom notification sound from the app bundle when it's under 30 seconds and in CAF/AIFF/WAV.)

import AVFoundation

let rate = 44_100.0
let length = 1.3
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
let frames = AVAudioFrameCount(rate * length)
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
buffer.frameLength = frames
let out = buffer.floatChannelData![0]

/// A bell: a few inharmonic partials, each fading at its own speed, with a soft attack.
func strike(at start: Double, pitch: Double, loudness: Double) {
    let partials: [(ratio: Double, level: Double, decay: Double)] = [
        (1.0, 1.0, 3.2), (2.0, 0.5, 4.5), (2.76, 0.35, 6.0), (5.4, 0.12, 9.0),
    ]
    for i in Int(start * rate)..<Int(frames) {
        let t = Double(i) / rate - start
        let attack = min(1, t / 0.004)
        var v = 0.0
        for p in partials { v += p.level * exp(-p.decay * t) * sin(2 * .pi * pitch * p.ratio * t) }
        out[i] += Float(v * attack * loudness)
    }
}

strike(at: 0.0, pitch: 1046.5, loudness: 0.32)  // C6
strike(at: 0.16, pitch: 1318.5, loudness: 0.28) // E6

// Fade the last 0.15 s so it ends cleanly.
let fade = Int(0.15 * rate)
for i in 0..<fade { out[Int(frames) - fade + i] *= Float(1 - Double(i) / Double(fade)) }

let url = URL(fileURLWithPath: "ios/Kookout/kookout.caf")
try? FileManager.default.removeItem(at: url)
let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
try file.write(from: buffer)
print("wrote \(url.path)")
