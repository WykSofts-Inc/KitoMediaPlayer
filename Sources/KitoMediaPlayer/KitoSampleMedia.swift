//
//  KitoSampleMedia.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import Accelerate
@preconcurrency import AVFoundation

/// Free media for previews and demos.
public enum KitoSampleMedia {
    /// Apple's public HLS test stream (10 minutes, adaptive up to 1080p60, fMP4). Needs a network.
    public static let videoURL = remote("https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")
    /// Apple's classic 16:9 "BipBop" HLS test stream. Needs a network.
    public static let classicVideoURL = remote("https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8")
    /// Chapters that line up with `videoURL`.
    public static let videoChapters: [KitoChapter] = [
        KitoChapter("Opening", start: 0, systemImage: "sparkles"),
        KitoChapter("Colour bars", start: 95, systemImage: "rectangle.split.3x1.fill"),
        KitoChapter("Counting", start: 240, systemImage: "number"),
        KitoChapter("Motion test", start: 390, systemImage: "figure.run"),
        KitoChapter("Finale", start: 520, systemImage: "flag.checkered"),
    ]

    private static func remote(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}

/// Generates short, pleasant synth pieces into temporary files, so audio demos work offline
/// and without bundling assets. Files are cached, so repeat calls are instant.
public enum KitoSampleAudio {
    /// A chord progression, tempo and colour for a generated piece.
    public enum Tune: String, CaseIterable, Sendable {
        case sunrise, drift, ember, lullaby

        public var title: String {
            switch self {
            case .sunrise: return "Sunrise Drive"
            case .drift: return "Night Drift"
            case .ember: return "Ember"
            case .lullaby: return "Lullaby for Nala"
            }
        }

        public var artist: String {
            switch self {
            case .sunrise, .ember: return "Kito Ensemble"
            case .drift: return "Lumen"
            case .lullaby: return "Nala Waves"
            }
        }

        public var artwork: KitoArtwork {
            switch self {
            case .sunrise: return .gradient([Color(red: 1, green: 0.62, blue: 0.27), Color(red: 0.93, green: 0.27, blue: 0.52)], systemImage: "sun.horizon.fill")
            case .drift: return .gradient([Color(red: 0.29, green: 0.25, blue: 0.85), Color(red: 0.62, green: 0.3, blue: 0.9)], systemImage: "moon.stars.fill")
            case .ember: return .gradient([Color(red: 0.95, green: 0.3, blue: 0.2), Color(red: 1, green: 0.72, blue: 0.2)], systemImage: "flame.fill")
            case .lullaby: return .gradient([Color(red: 0.13, green: 0.7, blue: 0.75), Color(red: 0.2, green: 0.4, blue: 0.9)], systemImage: "cloud.moon.fill")
            }
        }

        var beatsPerMinute: Double {
            switch self {
            case .sunrise: return 96
            case .drift: return 72
            case .ember: return 108
            case .lullaby: return 80
            }
        }

        /// One chord per bar, as MIDI note numbers.
        var chords: [[Int]] {
            switch self {
            case .sunrise: return [[60, 64, 67, 72], [57, 60, 64, 69], [53, 57, 60, 65], [55, 59, 62, 67]]
            case .drift: return [[62, 65, 69, 72], [58, 62, 65, 69], [53, 57, 60, 64], [60, 64, 67, 71]]
            case .ember: return [[64, 67, 71, 76], [60, 64, 67, 72], [55, 62, 67, 71], [62, 66, 69, 74]]
            case .lullaby: return [[65, 69, 72, 77], [60, 64, 67, 72], [62, 65, 69, 74], [58, 62, 65, 70]]
            }
        }

        /// Which chord tone each eighth note plays.
        var pattern: [Int] {
            switch self {
            case .sunrise: return [0, 1, 2, 3, 2, 1, 2, 3]
            case .drift: return [0, 2, 1, 3, 0, 2, 3, 2]
            case .ember: return [0, 1, 2, 1, 3, 2, 1, 2]
            case .lullaby: return [0, 1, 2, 1, 3, 1, 2, 1]
            }
        }
    }

    static let sampleRate: Double = 22_050

    /// Renders `tune` (30 seconds by default) to a cached `.caf` file and returns its URL.
    /// Runs synchronously — call it off the main thread for long durations.
    public static func makeFile(_ tune: Tune = .sunrise, duration: TimeInterval = 30) throws -> URL {
        let seconds = min(max(duration, 2), 600)
        let name = "KitoSampleAudio-\(tune.rawValue)-\(Int(seconds))s-v2.caf"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }

        let samples = render(tune, duration: seconds)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        try write(samples, to: scratch)
        do {
            try FileManager.default.moveItem(at: scratch, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: scratch)
            guard FileManager.default.fileExists(atPath: destination.path) else { throw error }
        }
        return destination
    }

    /// Every tune as a ready-to-play queue, rendered in the background.
    @MainActor
    public static func playlist(duration: TimeInterval = 30) async throws -> [KitoAudioTrack] {
        let urls = try await withThrowingTaskGroup(of: (Tune, URL).self) { group in
            for tune in Tune.allCases {
                group.addTask(priority: .userInitiated) { (tune, try makeFile(tune, duration: duration)) }
            }
            var found: [Tune: URL] = [:]
            for try await (tune, url) in group { found[tune] = url }
            return found
        }
        return Tune.allCases.compactMap { tune in urls[tune].map { (tune, $0) } }.map { tune, url in
            KitoAudioTrack(id: tune.rawValue, title: tune.title, artist: tune.artist, album: "Kito Sessions", url: url, artwork: tune.artwork)
        }
    }

    // MARK: Synthesis

    static func render(_ tune: Tune, duration: TimeInterval) -> [Float] {
        let frameCount = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: frameCount)
        let beat = 60 / tune.beatsPerMinute
        let bar = beat * 4
        let eighth = beat / 2
        let chords = tune.chords

        func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

        out.withUnsafeMutableBufferPointer { buffer in
            guard let output = buffer.baseAddress else { return }
            let synth = Synth(output: output, count: frameCount, rate: sampleRate)
            defer { synth.release() }
            var noise = SeededGenerator(seed: KitoWaveformAnalyzer.stableHash(tune.rawValue))
            var barStart = 0.0
            var barIndex = 0
            while barStart < duration {
                let chord = chords[barIndex % chords.count]

                // Warm pad: detuned sine pairs an octave down, swelling over the bar.
                for note in chord.prefix(3) {
                    let f = frequency(note - 12)
                    synth.tone(start: barStart, length: bar + 0.4, frequency: f, gain: 0.035, attack: 0.5, release: 0.6)
                    synth.tone(start: barStart, length: bar + 0.4, frequency: f + 0.7, gain: 0.035, attack: 0.5, release: 0.6)
                }

                // Round bass on beats one and three.
                if let root = chord.first {
                    let f = frequency(root - 24)
                    for beatOffset in [0.0, 2.0] {
                        let start = barStart + beatOffset * beat
                        synth.tone(start: start, length: 1.2, frequency: f, gain: 0.3, attack: 0.006, tau: 0.35)
                        synth.tone(start: start, length: 0.8, frequency: f * 2, gain: 0.06, attack: 0.006, tau: 0.35)
                    }
                }

                // Electric-piano arpeggio in eighth notes, with a bell-like attack.
                for (step, toneIndex) in tune.pattern.enumerated() {
                    let note = chord[toneIndex % chord.count] + (step >= 4 && barIndex % 2 == 1 ? 12 : 0)
                    let f = frequency(note)
                    let gain: Float = step % 2 == 0 ? 0.16 : 0.115
                    let start = barStart + Double(step) * eighth
                    synth.tone(start: start, length: 1.8, frequency: f, gain: gain, attack: 0.004, tau: 0.55)
                    synth.tone(start: start, length: 0.7, frequency: f * 2, gain: gain * 0.3, attack: 0.004, tau: 1 / (6 + 1 / 0.55))
                    synth.tone(start: start, length: 0.5, frequency: f * 3, gain: gain * 0.08, attack: 0.004, tau: 1 / (9 + 1 / 0.55))
                }

                // Soft shaker on the off-beats.
                for step in stride(from: 1, to: 8, by: 2) {
                    synth.shaker(start: barStart + Double(step) * eighth, gain: 0.035, noise: &noise)
                }

                barStart += bar
                barIndex += 1
            }

            // Fades, then normalise and soft-clip.
            synth.ramp(from: 0, to: 1, at: 0, length: Int(0.3 * sampleRate))
            let fadeOut = min(frameCount, Int(2.5 * sampleRate))
            synth.ramp(from: 1, to: 0, at: frameCount - fadeOut, length: fadeOut)
            var peak: Float = 0
            vDSP_maxmgv(output, 1, &peak, vDSP_Length(frameCount))
            var gain: Float = peak > 0 ? 0.85 / peak * 1.1 : 1
            vDSP_vsmul(output, 1, &gain, output, 1, vDSP_Length(frameCount))
            var length = Int32(frameCount)
            vvtanhf(output, output, &length)
        }
        return out
    }

    /// Vectorised oscillators (Accelerate), so rendering stays fast even in debug builds.
    private struct Synth {
        let output: UnsafeMutablePointer<Float>
        let count: Int
        let rate: Double
        private let capacity: Int
        private let wave: UnsafeMutablePointer<Float>
        private let envelope: UnsafeMutablePointer<Float>

        init(output: UnsafeMutablePointer<Float>, count: Int, rate: Double) {
            self.output = output
            self.count = count
            self.rate = rate
            capacity = Int(rate * 4)
            wave = .allocate(capacity: capacity)
            envelope = .allocate(capacity: capacity)
        }

        func release() {
            wave.deallocate()
            envelope.deallocate()
        }

        /// Adds a sine at `frequency` with a linear attack, exponential decay (`tau` seconds to
        /// fall to 1/e; infinite for none) and a linear release at the end.
        func tone(start: Double, length: Double, frequency: Double, gain: Float, attack: Double, tau: Double = .infinity, release: Double = 0.12) {
            let first = max(0, Int(start * rate))
            let last = min(count, Int((start + length) * rate), first + capacity)
            guard first < last else { return }
            let total = last - first
            let size = vDSP_Length(total)
            var n = Int32(total)

            var phase: Float = 0
            var step = Float(2 * Double.pi * frequency / rate)
            vDSP_vramp(&phase, &step, wave, 1, size)
            vvsinf(wave, wave, &n)

            if tau.isFinite && tau > 0 {
                var zero: Float = 0
                var fall = Float(-1 / (tau * rate))
                vDSP_vramp(&zero, &fall, envelope, 1, size)
                vvexpf(envelope, envelope, &n)
                vDSP_vmul(wave, 1, envelope, 1, wave, 1, size)
            }
            shape(wave, total: total, attack: Int(attack * rate), release: Int(release * rate))
            var level = gain
            vDSP_vsma(wave, 1, &level, output + first, 1, output + first, 1, size)
        }

        /// Multiplies `length` samples of the output from `at` by a line from `from` to `to`.
        func ramp(from: Float, to: Float, at start: Int, length: Int) {
            let first = max(0, start)
            let total = min(length, count - first, capacity)
            guard total > 0 else { return }
            var begin = from
            var step = (to - from) / Float(max(1, total - 1))
            vDSP_vramp(&begin, &step, envelope, 1, vDSP_Length(total))
            vDSP_vmul(output + first, 1, envelope, 1, output + first, 1, vDSP_Length(total))
        }

        private func shape(_ buffer: UnsafeMutablePointer<Float>, total: Int, attack: Int, release: Int) {
            let attack = min(max(1, attack), total)
            var zero: Float = 0
            var up = 1 / Float(attack)
            vDSP_vramp(&zero, &up, envelope, 1, vDSP_Length(attack))
            vDSP_vmul(buffer, 1, envelope, 1, buffer, 1, vDSP_Length(attack))
            let release = min(max(1, release), total)
            var one: Float = 1
            var down = -1 / Float(release)
            vDSP_vramp(&one, &down, envelope, 1, vDSP_Length(release))
            let tail = buffer + (total - release)
            vDSP_vmul(tail, 1, envelope, 1, tail, 1, vDSP_Length(release))
        }

        /// A short burst of brightened noise.
        func shaker(start: Double, gain: Float, noise: inout SeededGenerator) {
            let first = max(0, Int(start * rate))
            let last = min(count, first + Int(0.05 * rate))
            guard first < last else { return }
            let total = last - first
            var previous: Float = 0
            for index in 0..<total {
                let grain = Float(noise.next() % 2000) / 1000 - 1
                wave[index] = grain - previous
                previous = grain
            }
            var zero: Float = 0
            var fall = Float(-1 / (0.018 * rate))
            var n = Int32(total)
            vDSP_vramp(&zero, &fall, envelope, 1, vDSP_Length(total))
            vvexpf(envelope, envelope, &n)
            vDSP_vmul(wave, 1, envelope, 1, wave, 1, vDSP_Length(total))
            var level = gain
            vDSP_vsma(wave, 1, &level, output + first, 1, output + first, 1, vDSP_Length(total))
        }
    }

    private static func write(_ samples: [Float], to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        // The file is flushed and closed when it goes out of scope.
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw KitoWaveformError.unreadable }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        try file.write(from: buffer)
    }
}
