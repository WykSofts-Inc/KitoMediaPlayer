//
//  KitoMediaComponents.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

// MARK: - Playback rate chip

/// A capsule showing the playback speed. Tap to step through `rates`; press and hold to pick one.
public struct KitoPlaybackRateChip: View {
    @Binding var rate: Float
    let rates: [Float]
    let tint: Color?

    @Environment(\.kitoTheme) private var theme

    public init(rate: Binding<Float>, rates: [Float] = KitoPlaybackRate.standard, tint: Color? = nil) {
        _rate = rate
        self.rates = rates
        self.tint = tint
    }

    public init(model: KitoAudioPlayerModel, rates: [Float] = KitoPlaybackRate.standard, tint: Color? = nil) {
        self.init(rate: Binding(get: { model.rate }, set: { model.setRate($0) }), rates: rates, tint: tint)
    }

    public init(model: KitoVideoPlayerModel, rates: [Float] = KitoPlaybackRate.standard, tint: Color? = nil) {
        self.init(rate: Binding(get: { model.rate }, set: { model.setRate($0) }), rates: rates, tint: tint)
    }

    public var body: some View {
        let color = tint ?? theme.colors.onSurface
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                rate = KitoPlaybackRate.next(after: rate, in: rates)
            }
        } label: {
            Text(KitoPlaybackRate.label(rate))
                .font(theme.typography.label.monospacedDigit().weight(.bold))
                .contentTransition(.numericText(value: Double(rate)))
                .foregroundStyle(color)
                .padding(.horizontal, theme.spacing.md)
                .padding(.vertical, theme.spacing.xs + 2)
                .background(Capsule().fill(color.opacity(0.12)))
                .overlay(Capsule().strokeBorder(color.opacity(rate == 1 ? 0.18 : 0.5), lineWidth: 1))
        }
        .buttonStyle(KitoPressStyle())
        .contextMenu {
            Picker("Playback speed", selection: $rate) {
                ForEach(rates, id: \.self) { Text(KitoPlaybackRate.label($0)).tag($0) }
            }
        }
        .sensoryFeedback(.selection, trigger: rate)
        .accessibilityLabel("Playback speed")
        .accessibilityValue(KitoPlaybackRate.label(rate))
        .accessibilityHint("Double-tap for the next speed")
    }
}

// MARK: - Chapter list

/// Podcast-style chapters: the playing one is highlighted with a live progress fill and an
/// animated equaliser. Tap a row to jump to it.
public struct KitoChapterList: View {
    let chapters: [KitoChapter]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let tint: Color?
    let onSelect: (KitoChapter) -> Void

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        chapters: [KitoChapter],
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool = true,
        tint: Color? = nil,
        onSelect: @escaping (KitoChapter) -> Void
    ) {
        self.chapters = chapters.sorted { $0.start < $1.start }
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.tint = tint
        self.onSelect = onSelect
    }

    /// Chapters of the model's current track; selecting one seeks and plays.
    public init(model: KitoAudioPlayerModel, tint: Color? = nil) {
        self.init(chapters: model.chapters, currentTime: model.currentTime, duration: model.duration, isPlaying: model.isPlaying, tint: tint) { chapter in
            model.seek(to: chapter.start)
            if !model.isPlaying { model.play() }
        }
    }

    public init(model: KitoVideoPlayerModel, tint: Color? = nil) {
        self.init(chapters: model.chapters, currentTime: model.currentTime, duration: model.duration, isPlaying: model.isPlaying, tint: tint) { chapter in
            model.seek(to: chapter.start)
            if !model.isPlaying { model.play() }
        }
    }

    public var body: some View {
        let current = KitoChapter.index(at: currentTime, in: chapters)
        VStack(spacing: theme.spacing.xs) {
            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                row(chapter, index: index, isCurrent: index == current)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
    }

    private func row(_ chapter: KitoChapter, index: Int, isCurrent: Bool) -> some View {
        let accent = tint ?? theme.colors.primary
        let range = KitoChapter.range(of: index, in: chapters, duration: duration)
        let fraction: Double = {
            guard isCurrent, let range, range.upperBound > range.lowerBound else { return 0 }
            return min(1, max(0, (currentTime - range.lowerBound) / (range.upperBound - range.lowerBound)))
        }()
        return Button { onSelect(chapter) } label: {
            HStack(spacing: theme.spacing.md) {
                ZStack {
                    Circle().fill(isCurrent ? accent : theme.colors.onSurface.opacity(0.08))
                    if let symbol = chapter.systemImage {
                        Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                    } else {
                        Text("\(index + 1)").font(theme.typography.label.monospacedDigit().weight(.bold))
                    }
                }
                .foregroundStyle(isCurrent ? theme.colors.onPrimary : theme.colors.onSurface.opacity(0.7))
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .font(isCurrent ? theme.typography.bodyEmphasized : theme.typography.body)
                        .foregroundStyle(theme.colors.onSurface)
                        .lineLimit(1)
                    Text(range.map { "\(KitoMediaTime.string($0.lowerBound)) · \(KitoMediaTime.string($0.upperBound - $0.lowerBound))" } ?? KitoMediaTime.string(chapter.start))
                        .font(theme.typography.caption.monospacedDigit())
                        .foregroundStyle(theme.colors.onSurface.opacity(0.55))
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                        .symbolEffect(.variableColor.iterative.reversing, isActive: isPlaying && !reduceMotion)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
                    .fill(isCurrent ? accent.opacity(0.1) : .clear)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
                                .fill(accent.opacity(0.12))
                                .frame(width: proxy.size.width * fraction)
                                .animation(.linear(duration: 0.2), value: fraction)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(KitoPressStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chapter \(index + 1), \(chapter.title)")
        .accessibilityValue(isCurrent ? "Playing" : "Starts at \(KitoMediaTime.spoken(chapter.start))")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

// MARK: - Sleep timer menu

/// A moon button with the sleep-timer presets; shows the countdown while one runs.
public struct KitoSleepTimerMenu: View {
    let model: KitoAudioPlayerModel
    let options: [KitoSleepTimer.Mode]
    let tint: Color?

    @Environment(\.kitoTheme) private var theme

    public init(model: KitoAudioPlayerModel, options: [KitoSleepTimer.Mode] = KitoSleepTimer.Mode.presets, tint: Color? = nil) {
        self.model = model
        self.options = options
        self.tint = tint
    }

    public var body: some View {
        let color = tint ?? theme.colors.onSurface
        let active = model.sleepTimer != nil
        Menu {
            if active {
                Button("Turn off timer", systemImage: "moon.zzz") { model.cancelSleepTimer() }
                Divider()
            }
            ForEach(options, id: \.self) { mode in
                Button(mode.title) { model.startSleepTimer(mode) }
            }
        } label: {
            HStack(spacing: theme.spacing.xs) {
                Image(systemName: active ? "moon.zzz.fill" : "moon.zzz")
                    .symbolEffect(.bounce, value: active)
                if let label = model.sleepTimerLabel {
                    Text(label)
                        .font(theme.typography.caption.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText(countsDown: true))
                        .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(active ? color : color.opacity(0.7))
            .padding(.horizontal, active ? theme.spacing.sm : 0)
            .padding(.vertical, theme.spacing.xs)
            .background(Capsule().fill(color.opacity(active ? 0.14 : 0)))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: model.sleepTimerLabel)
        }
        .accessibilityLabel("Sleep timer")
        .accessibilityValue(model.sleepTimer.map { $0.mode == .endOfTrack ? "End of track" : "\($0.label()) left" } ?? "Off")
    }
}

// MARK: - Artwork

/// Renders a `KitoArtwork` filling its frame — the same art the players draw, for your library
/// grids and lists.
public struct KitoArtworkView: View {
    let artwork: KitoArtwork
    let cornerRadius: CGFloat

    public init(_ artwork: KitoArtwork, cornerRadius: CGFloat = 12) {
        self.artwork = artwork
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            switch artwork {
            case .image(let image):
                Image(uiImage: image).resizable().scaledToFill()
            case .remote(let url):
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill().transition(.opacity)
                    } else {
                        generated(KitoArtwork.placeholder.palette, symbol: "music.note")
                    }
                }
            case .gradient(let colors, let symbol):
                generated(colors, symbol: symbol)
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private func generated(_ colors: [Color], symbol: String) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(colors: colors.isEmpty ? [.gray, .black] : colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: side * 0.9)
                    .blur(radius: side * 0.12)
                    .offset(x: -side * 0.3, y: -side * 0.35)
                Circle()
                    .strokeBorder(.white.opacity(0.14), lineWidth: max(1, side * 0.012))
                    .frame(width: side * 0.72)
                    .offset(x: side * 0.28, y: side * 0.3)
                Image(systemName: symbol)
                    .font(.system(size: side * 0.34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.2), radius: side * 0.04, y: side * 0.02)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

// MARK: - Spinner

/// A glowing, rotating arc used while media buffers.
struct KitoSpinner: View {
    var color: Color = .white
    var size: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        Group {
            if reduceMotion {
                ProgressView().tint(color).controlSize(.large)
            } else {
                ZStack {
                    Circle().stroke(color.opacity(0.18), lineWidth: size * 0.09)
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(AngularGradient(colors: [color.opacity(0), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(260)),
                                style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                        .rotationEffect(.degrees(spinning ? 360 : 0))
                        .shadow(color: color.opacity(0.5), radius: size * 0.12)
                }
                .frame(width: size, height: size)
                .onAppear {
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spinning = true }
                }
            }
        }
        .accessibilityLabel("Loading")
    }
}

// MARK: - Buttons

/// Springy press feedback for icon buttons.
struct KitoPressStyle: ButtonStyle {
    var scale: CGFloat = 0.86

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension View {
    /// `matchedGeometryEffect` only when a namespace is supplied.
    @ViewBuilder
    func matched(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Scrubber

/// The video scrubber: chapter gaps, buffered range, a thumb that grows while dragging and a
/// time bubble with the chapter name. Always runs left to right, like the playback controls.
struct KitoScrubber: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let buffered: TimeInterval
    let chapters: [KitoChapter]
    var accent: Color = .white
    var track: Color = .white.opacity(0.25)
    var bufferColor: Color = .white.opacity(0.45)
    var thin = false
    var showsThumb = true
    var onEditingChanged: (Bool) -> Void = { _ in }
    let onScrub: (TimeInterval) -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @Environment(\.kitoTheme) private var theme

    private var fraction: Double { dragFraction ?? KitoMediaTime.progress(currentTime, duration: duration) }
    private var isDragging: Bool { dragFraction != nil }
    private var barHeight: CGFloat { isDragging ? (thin ? 6 : 8) : (thin ? 2.5 : 4) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let markers = KitoChapter.markers(chapters, duration: duration)
            let segments = SegmentedTrack(markers: markers, gap: markers.isEmpty ? 0 : 3)
            ZStack(alignment: .leading) {
                segments.fill(track)
                segments.fill(bufferColor)
                    .mask(alignment: .leading) { Rectangle().frame(width: width * KitoMediaTime.progress(buffered, duration: duration)) }
                segments.fill(accent)
                    .mask(alignment: .leading) { Rectangle().frame(width: width * fraction) }
            }
            .frame(height: barHeight)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) {
                if showsThumb || isDragging {
                    Circle()
                        .fill(accent)
                        .frame(width: isDragging ? 20 : 12, height: isDragging ? 20 : 12)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                        .offset(x: width * fraction - (isDragging ? 10 : 6))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if let dragFraction {
                    bubble(time: dragFraction * duration)
                        .fixedSize()
                        .alignmentGuide(.leading) { $0.width / 2 }
                        .offset(x: min(max(64, width * dragFraction), width - 64), y: -36)
                        .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0, duration > 0 else { return }
                        if dragFraction == nil { onEditingChanged(true) }
                        let next = min(max(0, value.location.x / width), 1)
                        dragFraction = next
                        onScrub(next * duration)
                    }
                    .onEnded { value in
                        guard width > 0, duration > 0 else { return }
                        let next = min(max(0, value.location.x / width), 1)
                        onSeek(next * duration)
                        dragFraction = nil
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: thin ? 18 : 28)
        .environment(\.layoutDirection, .leftToRight)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isDragging)
        .sensoryFeedback(.impact(weight: .light), trigger: dragFraction.flatMap { KitoChapter.index(at: $0 * duration, in: chapters) } ?? -1)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(KitoMediaTime.spoken(currentTime)) of \(KitoMediaTime.spoken(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(KitoMediaTime.clamped(currentTime + 10, duration: duration))
            case .decrement: onSeek(KitoMediaTime.clamped(currentTime - 10, duration: duration))
            @unknown default: break
            }
        }
    }

    private func bubble(time: TimeInterval) -> some View {
        let chapter = KitoChapter.index(at: time, in: chapters).map { chapters[$0].title }
        return VStack(spacing: 1) {
            Text(KitoMediaTime.string(time))
                .font(.system(size: 15, weight: .bold).monospacedDigit())
            if let chapter {
                Text(chapter)
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.75)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.xs + 1)
        .background(Capsule().fill(.black.opacity(0.72)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

/// Capsule segments with small gaps at each chapter boundary.
struct SegmentedTrack: Shape {
    let markers: [Double]
    let gap: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let edges = [0] + markers + [1]
        let radius = rect.height / 2
        for index in 0..<(edges.count - 1) {
            let start = rect.minX + rect.width * edges[index] + (index == 0 ? 0 : gap / 2)
            let end = rect.minX + rect.width * edges[index + 1] - (index == edges.count - 2 ? 0 : gap / 2)
            guard end > start else { continue }
            path.addRoundedRect(in: CGRect(x: start, y: rect.minY, width: end - start, height: rect.height),
                                cornerSize: CGSize(width: radius, height: radius))
        }
        return path
    }
}
