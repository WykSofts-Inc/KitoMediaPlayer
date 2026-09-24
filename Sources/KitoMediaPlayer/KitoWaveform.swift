//
//  KitoWaveform.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore
import Accelerate
@preconcurrency import AVFoundation

public enum KitoWaveformError: Error, Sendable {
    case noAudioTrack
    case unreadable
}

/// Turns audio into bar heights for `KitoWaveformView`.
public enum KitoWaveformAnalyzer {
    /// Peak levels of a local audio file, `count` values in `0…1`. Reads the file once with
    /// `AVAssetReader` off the main thread, keeping only a small running peak per chunk.
    public static func peaks(of url: URL, count: Int = 64) async throws -> [Float] {
        try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                throw KitoWaveformError.noAudioTrack
            }
            let chunkPeaks = try readChunkPeaks(asset: asset, track: track)
            guard !chunkPeaks.isEmpty else { throw KitoWaveformError.unreadable }
            return downsample(chunkPeaks, into: count)
        }.value
    }

    /// Reduces `samples` to exactly `count` peaks (the loudest absolute value in each bucket).
    /// With `normalize`, the loudest peak becomes 1. Empty input gives silence.
    public static func downsample(_ samples: [Float], into count: Int, normalize: Bool = true) -> [Float] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else { return Array(repeating: 0, count: count) }
        var peaks = [Float](repeating: 0, count: count)
        let total = samples.count
        for bucket in 0..<count {
            let lower = bucket * total / count
            let upper = max(lower + 1, (bucket + 1) * total / count)
            var peak: Float = 0
            for index in lower..<min(upper, total) {
                let value = samples[index]
                let magnitude = value.isFinite ? abs(value) : 0
                if magnitude > peak { peak = magnitude }
            }
            peaks[bucket] = peak
        }
        guard normalize, let loudest = peaks.max(), loudest > 0 else { return peaks }
        return peaks.map { $0 / loudest }
    }

    /// A deterministic, natural-looking waveform for media that can't be analysed (streams,
    /// remote files) or while analysis runs. The same `seed` always gives the same bars.
    public static func placeholder(count: Int, seed: String) -> [Float] {
        guard count > 0 else { return [] }
        var generator = SeededGenerator(seed: stableHash(seed))
        let phase = Double(generator.next() % 1000) / 1000 * .pi * 2
        let phrase = 0.05 + Double(generator.next() % 100) / 2000
        return (0..<count).map { index in
            let x = Double(index)
            let swell = 0.55 + 0.35 * sin(x * phrase + phase)
            let detail = 0.25 * sin(x * 0.9 + phase * 2) * sin(x * 0.31)
            let noise = Double(generator.next() % 1000) / 1000 * 0.35
            let envelope = min(1, Double(index + 1) / 4) * min(1, Double(count - index) / 4)
            return Float(min(1, max(0.08, (swell + detail) * (0.65 + noise) * envelope)))
        }
    }

    private static func readChunkPeaks(asset: AVAsset, track: AVAssetTrack, chunk: Int = 256) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw KitoWaveformError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw KitoWaveformError.unreadable }

        var peaks: [Float] = []
        var integers: [Int16] = []
        var floats: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let sampleCount = CMBlockBufferGetDataLength(block) / MemoryLayout<Int16>.size
            guard sampleCount > 0 else { continue }
            if integers.count < sampleCount {
                integers = [Int16](repeating: 0, count: sampleCount)
                floats = [Float](repeating: 0, count: sampleCount)
            }
            let status = integers.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: sampleCount * MemoryLayout<Int16>.size, destination: base)
            }
            guard status == noErr else { continue }
            // Vectorised: convert to Float, then take the loudest magnitude per chunk.
            integers.withUnsafeBufferPointer { source in
                floats.withUnsafeMutableBufferPointer { target in
                    guard let from = source.baseAddress, let to = target.baseAddress else { return }
                    vDSP_vflt16(from, 1, to, 1, vDSP_Length(sampleCount))
                    var offset = 0
                    while offset < sampleCount {
                        let length = min(chunk, sampleCount - offset)
                        var peak: Float = 0
                        vDSP_maxmgv(to + offset, 1, &peak, vDSP_Length(length))
                        peaks.append(peak / Float(Int16.max))
                        offset += length
                    }
                }
            }
        }
        if reader.status == .failed { throw KitoWaveformError.unreadable }
        return peaks
    }

    /// FNV-1a, stable across launches (unlike `hashValue`).
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }
}

/// SplitMix64: tiny, fast and deterministic.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}

/// Rounded bars with a progress fill. Pass `onSeek` to make it a scrubber: drag anywhere to
/// seek, with a selection tick as you go and VoiceOver swipe-to-adjust.
public struct KitoWaveformView: View {
    let samples: [Float]
    let progress: Double
    let duration: Double?
    let barWidth: CGFloat
    let spacing: CGFloat
    let tint: Color?
    let trackColor: Color?
    let onScrub: ((Double) -> Void)?
    let onSeek: ((Double) -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragProgress: Double?
    @State private var grow: CGFloat = 0

    /// - Parameters:
    ///   - samples: levels in `0…1`, resampled to fit the width.
    ///   - progress: played fraction, `0…1`.
    ///   - duration: seconds, for the time bubble and VoiceOver. Optional.
    ///   - onScrub: called continuously while dragging.
    ///   - onSeek: called with the final fraction when the drag ends.
    public init(
        samples: [Float],
        progress: Double,
        duration: Double? = nil,
        barWidth: CGFloat = 3,
        spacing: CGFloat = 2,
        tint: Color? = nil,
        trackColor: Color? = nil,
        onScrub: ((Double) -> Void)? = nil,
        onSeek: ((Double) -> Void)? = nil
    ) {
        self.samples = samples
        self.progress = progress
        self.duration = duration
        self.barWidth = max(1, barWidth)
        self.spacing = max(0, spacing)
        self.tint = tint
        self.trackColor = trackColor
        self.onScrub = onScrub
        self.onSeek = onSeek
    }

    private var shown: Double { min(max(dragProgress ?? progress, 0), 1) }
    private var fill: Color { tint ?? theme.colors.primary }

    public var body: some View {
        GeometryReader { proxy in
            let count = max(1, Int((proxy.size.width + spacing) / (barWidth + spacing)))
            let levels = KitoWaveformAnalyzer.downsample(samples, into: count, normalize: false)
            let shape = WaveformBars(levels: levels, barWidth: barWidth, spacing: spacing, grow: grow)
            ZStack(alignment: .leading) {
                shape.fill(trackColor ?? theme.colors.onSurface.opacity(0.18))
                shape.fill(fill)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: proxy.size.width * shown)
                    }
                if let dragProgress {
                    Capsule()
                        .fill(fill)
                        .frame(width: 2, height: proxy.size.height + 8)
                        .offset(x: proxy.size.width * dragProgress - 1)
                        .transition(.opacity)
                    if let duration {
                        bubble(KitoMediaTime.string(duration * dragProgress))
                            .position(x: min(max(28, proxy.size.width * dragProgress), proxy.size.width - 28), y: -22)
                            .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(scrubGesture(width: proxy.size.width), including: onSeek == nil ? .none : .all)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragProgress == nil)
        }
        // A playback timeline: stays left to right in every layout direction, like the transport
        // controls, so the physical drag location maps straight onto the fill.
        .environment(\.layoutDirection, .leftToRight)
        .sensoryFeedback(.selection, trigger: dragProgress.map { Int($0 * 24) } ?? -1)
        .onAppear(perform: animateIn)
        .onChange(of: samples) { animateIn() }
        .accessibilityElement()
        .accessibilityLabel("Waveform")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard let onSeek else { return }
            let step = duration.map { $0 > 0 ? 15 / $0 : 0.05 } ?? 0.05
            switch direction {
            case .increment: onSeek(min(1, progress + step))
            case .decrement: onSeek(max(0, progress - step))
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        guard let duration, duration > 0 else { return "\(Int(shown * 100)) percent" }
        return "\(KitoMediaTime.spoken(shown * duration)) of \(KitoMediaTime.spoken(duration))"
    }

    private func bubble(_ text: String) -> some View {
        Text(text)
            .font(theme.typography.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(theme.colors.onPrimary)
            .padding(.horizontal, theme.spacing.sm)
            .padding(.vertical, theme.spacing.xs)
            .background(Capsule().fill(fill).shadow(color: fill.opacity(0.35), radius: 8, y: 4))
            .fixedSize()
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                let fraction = min(max(0, value.location.x / width), 1)
                dragProgress = fraction
                onScrub?(fraction)
            }
            .onEnded { value in
                guard width > 0 else { return }
                let fraction = min(max(0, value.location.x / width), 1)
                onSeek?(fraction)
                dragProgress = nil
            }
    }

    private func animateIn() {
        guard !reduceMotion else { grow = 1; return }
        grow = 0.15
        withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { grow = 1 }
    }
}

/// Vertically centred rounded bars; `grow` scales every bar for the entrance animation.
struct WaveformBars: Shape {
    var levels: [Float]
    var barWidth: CGFloat
    var spacing: CGFloat
    var grow: CGFloat
    var minimumHeight: CGFloat = 3

    var animatableData: CGFloat {
        get { grow }
        set { grow = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !levels.isEmpty else { return path }
        let step = barWidth + spacing
        let used = CGFloat(levels.count) * step - spacing
        let inset = max(0, (rect.width - used) / 2)
        for (index, level) in levels.enumerated() {
            let staggered = min(1, max(0, grow * 1.3 - CGFloat(index) / CGFloat(levels.count) * 0.3))
            let height = max(minimumHeight, rect.height * CGFloat(min(max(level, 0), 1)) * staggered)
            let x = rect.minX + inset + CGFloat(index) * step
            let bar = CGRect(x: x, y: rect.midY - height / 2, width: barWidth, height: height)
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }
        return path
    }
}
