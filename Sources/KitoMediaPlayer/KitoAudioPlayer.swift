//
//  KitoAudioPlayer.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// How the full player shows cover art.
public enum KitoArtworkStyle: String, CaseIterable, Sendable {
    /// A rounded card that breathes while playing and settles back when paused.
    case card
    /// A spinning record with the art as its label.
    case vinyl
}

/// A full-screen "now playing" view: artwork, title, waveform scrubber, ±15s, previous and
/// next, repeat, shuffle, speed, sleep timer, and the queue or chapters.
///
/// ```swift
/// @State private var player = KitoAudioPlayerModel(tracks: tracks, systemControls: true)
/// KitoAudioPlayer(model: player)
/// ```
public struct KitoAudioPlayer: View {
    let model: KitoAudioPlayerModel
    let artworkStyle: KitoArtworkStyle
    let tint: Color?
    let onCollapse: (() -> Void)?

    /// - Parameter onCollapse: shows a chevron that calls this (and enables swipe-down).
    public init(model: KitoAudioPlayerModel, artworkStyle: KitoArtworkStyle = .card, tint: Color? = nil, onCollapse: (() -> Void)? = nil) {
        self.model = model
        self.artworkStyle = artworkStyle
        self.tint = tint
        self.onCollapse = onCollapse
    }

    public var body: some View {
        FullAudioPlayer(model: model, artworkStyle: artworkStyle, tint: tint, namespace: nil, onCollapse: onCollapse)
    }
}

/// A floating now-playing bar. Tap it (or swipe up) and it expands into the full player with a
/// shared-element transition; swipe down or tap the chevron to shrink it back.
/// Place it at the bottom of a screen, or use `.kitoMiniPlayer(_:)`.
public struct KitoMiniPlayer: View {
    let model: KitoAudioPlayerModel
    let externalExpanded: Binding<Bool>?
    let artworkStyle: KitoArtworkStyle
    let tint: Color?

    @State private var internalExpanded = false
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: KitoAudioPlayerModel, isExpanded: Binding<Bool>? = nil, artworkStyle: KitoArtworkStyle = .card, tint: Color? = nil) {
        self.model = model
        self.externalExpanded = isExpanded
        self.artworkStyle = artworkStyle
        self.tint = tint
    }

    private var isExpanded: Bool { externalExpanded?.wrappedValue ?? internalExpanded }

    private func setExpanded(_ value: Bool) {
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.5, dampingFraction: 0.86)
        withAnimation(animation) {
            if let externalExpanded { externalExpanded.wrappedValue = value } else { internalExpanded = value }
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if isExpanded {
                FullAudioPlayer(model: model, artworkStyle: artworkStyle, tint: tint, namespace: namespace) { setExpanded(false) }
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.15)), removal: .opacity.animation(.easeIn(duration: 0.2).delay(0.1))))
                    .zIndex(1)
            } else if model.currentTrack != nil {
                MiniBar(model: model, tint: tint, namespace: namespace) { setExpanded(true) }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: isExpanded ? .infinity : nil, alignment: .bottom)
    }
}

public extension View {
    /// Pins a `KitoMiniPlayer` to the bottom of this view; it expands over the whole view.
    func kitoMiniPlayer(_ model: KitoAudioPlayerModel, isExpanded: Binding<Bool>? = nil, artworkStyle: KitoArtworkStyle = .card, tint: Color? = nil) -> some View {
        overlay(alignment: .bottom) {
            KitoMiniPlayer(model: model, isExpanded: isExpanded, artworkStyle: artworkStyle, tint: tint)
        }
    }
}

// MARK: - Mini bar

struct MiniBar: View {
    let model: KitoAudioPlayerModel
    let tint: Color?
    let namespace: Namespace.ID
    let onExpand: () -> Void

    @Environment(\.kitoTheme) private var theme
    @GestureState private var lift: CGFloat = 0

    var body: some View {
        let accent = tint ?? theme.colors.primary
        let track = model.currentTrack
        HStack(spacing: theme.spacing.md) {
            KitoArtworkView(track?.artwork ?? .placeholder, cornerRadius: theme.radii.md)
                .matchedGeometryEffect(id: "artwork", in: namespace)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(track?.title ?? "")
                    .font(theme.typography.bodyEmphasized)
                    .foregroundStyle(theme.colors.onSurface)
                    .lineLimit(1)
                    .matchedGeometryEffect(id: "title", in: namespace, properties: .position)
                Text(track?.artist ?? "")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.onSurface.opacity(0.6))
                    .lineLimit(1)
                    .matchedGeometryEffect(id: "artist", in: namespace, properties: .position)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.colors.onSurface)
                    .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KitoPressStyle())
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            .matchedGeometryEffect(id: "play", in: namespace, properties: .position)
            Button { model.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.colors.onSurface)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KitoPressStyle())
            .accessibilityLabel("Next track")
        }
        .padding(.leading, theme.spacing.sm)
        .padding(.trailing, theme.spacing.xs)
        .padding(.vertical, theme.spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous).strokeBorder(theme.colors.border.opacity(0.5), lineWidth: 0.5))
                .matchedGeometryEffect(id: "background", in: namespace)
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Capsule().fill(accent.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent).frame(width: proxy.size.width * model.progress)
                            .animation(.linear(duration: 0.15), value: model.progress)
                    }
            }
            .frame(height: 2.5)
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, theme.spacing.xl)
            .padding(.bottom, 3)
            .allowsHitTesting(false)
        }
        .offset(y: lift)
        .contentShape(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous))
        .onTapGesture(perform: onExpand)
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($lift) { value, state, _ in state = min(0, value.translation.height) * 0.4 }
                .onEnded { value in if value.translation.height < -40 { onExpand() } }
        )
        .padding(.horizontal, theme.spacing.md)
        .padding(.bottom, theme.spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing, \(track?.title ?? ""), \(track?.artist ?? "")")
        .accessibilityAction(named: "Open player", onExpand)
    }
}

// MARK: - Full player

struct FullAudioPlayer: View {
    let model: KitoAudioPlayerModel
    let artworkStyle: KitoArtworkStyle
    let tint: Color?
    let namespace: Namespace.ID?
    let onCollapse: (() -> Void)?

    enum Panel: String, CaseIterable, Identifiable {
        case queue = "Up Next", chapters = "Chapters"
        var id: String { rawValue }
    }

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var local
    @State private var panel: Panel?
    @State private var dragOffset: CGFloat = 0
    @State private var skipTaps = 0
    @State private var trackChange = 0

    private var accent: Color { tint ?? .white }

    var body: some View {
        let track = model.currentTrack
        GeometryReader { proxy in
            let compact = proxy.size.height < 640
            VStack(spacing: compact ? theme.spacing.md : theme.spacing.lg) {
                header
                if let panel {
                    panelView(panel, track: track)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Spacer(minLength: 0)
                    artwork(track: track, size: min(proxy.size.width - theme.spacing.xl * 2, proxy.size.height * (compact ? 0.4 : 0.45)))
                    Spacer(minLength: 0)
                    titleBlock(track: track)
                }
                scrubber
                transport(compact: compact)
                toolbar
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.top, theme.spacing.sm)
            .padding(.bottom, theme.spacing.md)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundStyle(.white)
        .background {
            AudioBackdrop(artwork: track?.artwork ?? .placeholder, isPlaying: model.isPlaying && !reduceMotion)
                .clipShape(RoundedRectangle(cornerRadius: dragOffset > 0 ? theme.radii.xl * 2 : 0, style: .continuous))
                .matched("background", in: namespace)
                .ignoresSafeArea()
        }
        .offset(y: dragOffset)
        .gesture(collapseGesture, including: onCollapse == nil ? .subviews : .all)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: panel)
        .onChange(of: track?.id) { trackChange += 1 }
        .sensoryFeedback(.impact(weight: .light), trigger: skipTaps)
        .sensoryFeedback(.selection, trigger: trackChange)
    }

    private var collapseGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard onCollapse != nil, value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard let onCollapse else { return }
                if value.translation.height > 140 || value.predictedEndTranslation.height > 320 {
                    onCollapse()
                    dragOffset = 0
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { dragOffset = 0 }
                }
            }
    }

    // MARK: Sections

    private var header: some View {
        ZStack {
            if let onCollapse {
                Capsule().fill(.white.opacity(0.35)).frame(width: 40, height: 5)
                    .frame(maxHeight: .infinity, alignment: .top)
                HStack {
                    Button(action: onCollapse) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(KitoPressStyle())
                    .accessibilityLabel("Close player")
                    Spacer()
                }
            }
            VStack(spacing: 1) {
                Text("PLAYING FROM")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .opacity(0.6)
                Text(model.currentTrack?.album ?? "Your queue")
                    .font(theme.typography.label.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 56)
        }
        .frame(height: 48)
    }

    private func artwork(track: KitoAudioTrack?, size: CGFloat) -> some View {
        let art = track?.artwork ?? .placeholder
        return Group {
            switch artworkStyle {
            case .card:
                BreathingArtwork(artwork: art, isPlaying: model.isPlaying, animated: !reduceMotion, cornerRadius: theme.radii.xl)
            case .vinyl:
                VinylArtwork(artwork: art, isPlaying: model.isPlaying && !reduceMotion)
            }
        }
        .matched("artwork", in: namespace)
        .matchedGeometryEffect(id: "art-local", in: local)
        .frame(width: max(0, size), height: max(0, size))
        .id(artworkStyle)
        .accessibilityElement()
        .accessibilityLabel(track.map { "Artwork for \($0.title)" } ?? "Artwork")
        .accessibilityAddTraits(.isImage)
    }

    private func titleBlock(track: KitoAudioTrack?) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track?.title ?? "Nothing playing")
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .matched("title", in: namespace)
                Text(track?.artist ?? "")
                    .font(theme.typography.body)
                    .opacity(0.7)
                    .lineLimit(1)
                    .matched("artist", in: namespace)
            }
            .id(track?.id)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: track?.id)
            Spacer(minLength: 0)
            if let chapter = model.currentChapter {
                Label(chapter.title, systemImage: chapter.systemImage ?? "list.bullet")
                    .font(theme.typography.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, theme.spacing.sm)
                    .padding(.vertical, theme.spacing.xs)
                    .background(Capsule().fill(.white.opacity(0.14)))
                    .contentTransition(.opacity)
                    .onTapGesture { panel = .chapters }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrubber: some View {
        VStack(spacing: theme.spacing.xs) {
            KitoWaveformView(
                samples: model.waveform,
                progress: model.progress,
                duration: model.duration,
                barWidth: 3,
                spacing: 2,
                tint: accent,
                trackColor: .white.opacity(0.25),
                onScrub: { model.scrub(to: $0 * model.duration) },
                onSeek: { model.endScrub(at: $0 * model.duration) }
            )
            .frame(height: 44)
            HStack {
                Text(KitoMediaTime.string(model.currentTime))
                Spacer()
                if model.isBuffering {
                    KitoSpinner(color: .white, size: 12)
                }
                Spacer()
                Text(KitoMediaTime.remainingString(currentTime: model.currentTime, duration: model.duration))
            }
            .font(theme.typography.caption.monospacedDigit().weight(.medium))
            .opacity(0.7)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func transport(compact: Bool) -> some View {
        HStack {
            transportButton("backward.fill", size: 24, label: "Previous track", disabled: false) { model.previous() }
            Spacer()
            transportButton("gobackward.15", size: 26, label: "Skip back 15 seconds", disabled: model.duration == 0) { model.skip(by: -15) }
            Spacer()
            Button { model.togglePlayback() } label: {
                ZStack {
                    Circle().fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: compact ? 26 : 30, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: model.isPlaying ? 0 : 2)
                        .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                }
                .frame(width: compact ? 64 : 76, height: compact ? 64 : 76)
            }
            .buttonStyle(KitoPressStyle(scale: 0.9))
            .matched("play", in: namespace)
            .sensoryFeedback(.impact(weight: .medium), trigger: model.isPlaying)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            Spacer()
            transportButton("goforward.15", size: 26, label: "Skip forward 15 seconds", disabled: model.duration == 0) { model.skip(by: 15) }
            Spacer()
            transportButton("forward.fill", size: 24, label: "Next track", disabled: !model.queue.hasNext && model.queue.items.count < 2) { model.next() }
        }
        // Transport controls follow the direction of playback, not of reading.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func transportButton(_ symbol: String, size: CGFloat, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        TransportButton(symbol: symbol, size: size, label: label) {
            skipTaps += 1
            action()
        }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    private var toolbar: some View {
        HStack {
            KitoPlaybackRateChip(model: model, tint: .white)
            Spacer()
            KitoSleepTimerMenu(model: model, tint: .white)
            Spacer()
            toggle(model.repeatMode.systemImage, isOn: model.repeatMode != .off, label: "Repeat", value: model.repeatMode.accessibilityValue) {
                model.cycleRepeatMode()
            }
            Spacer()
            toggle("shuffle", isOn: model.isShuffled, label: "Shuffle", value: model.isShuffled ? "On" : "Off") {
                model.toggleShuffle()
            }
            Spacer()
            toggle(model.chapters.isEmpty ? "list.bullet" : "list.bullet.rectangle", isOn: panel != nil, label: model.chapters.isEmpty ? "Up next" : "Chapters", value: panel == nil ? "Hidden" : "Shown") {
                panel = panel == nil ? (model.chapters.isEmpty ? .queue : .chapters) : nil
            }
        }
    }

    private func toggle(_ symbol: String, isOn: Bool, label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isOn ? .black : .white.opacity(0.75))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(isOn ? 0.95 : 0)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .symbolEffect(.bounce, value: isOn)
        }
        .buttonStyle(KitoPressStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    // MARK: Panel

    private func panelView(_ panel: Panel, track: KitoAudioTrack?) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            HStack(spacing: theme.spacing.md) {
                KitoArtworkView(track?.artwork ?? .placeholder, cornerRadius: theme.radii.md)
                    .matchedGeometryEffect(id: "art-local", in: local)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track?.title ?? "").font(theme.typography.bodyEmphasized).lineLimit(1)
                    Text(track?.artist ?? "").font(theme.typography.caption).opacity(0.7).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if !model.chapters.isEmpty {
                Picker("Show", selection: Binding(get: { panel }, set: { self.panel = $0 })) {
                    ForEach(Panel.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ScrollView {
                switch panel {
                case .chapters:
                    KitoChapterList(model: model, tint: .white)
                        .environment(\.kitoTheme, darkTheme)
                case .queue:
                    queueList
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
        }
    }

    private var darkTheme: KitoTheme {
        var dark = theme
        dark.colors.onSurface = .white
        dark.colors.onPrimary = .black
        return dark
    }

    private var queueList: some View {
        let playing = model.currentTrack
        return VStack(alignment: .leading, spacing: theme.spacing.xs) {
            if model.upNext.isEmpty {
                Text(model.repeatMode == .off ? "Nothing up next." : "The queue repeats from the top.")
                    .font(theme.typography.caption)
                    .opacity(0.6)
                    .padding(.vertical, theme.spacing.md)
            }
            ForEach(model.upNext) { item in
                Button { model.play(item) } label: {
                    HStack(spacing: theme.spacing.md) {
                        KitoArtworkView(item.artwork, cornerRadius: theme.radii.sm)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(theme.typography.body).lineLimit(1)
                            Text(item.artist).font(theme.typography.caption).opacity(0.6).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "play.circle")
                            .font(.system(size: 20))
                            .opacity(0.6)
                    }
                    .padding(theme.spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(KitoPressStyle(scale: 0.97))
                .accessibilityLabel("Play \(item.title) by \(item.artist)")
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.upNext.map(\.id))
        .id(playing?.id)
    }
}

// MARK: - Artwork styles

struct BreathingArtwork: View {
    let artwork: KitoArtwork
    let isPlaying: Bool
    let animated: Bool
    let cornerRadius: CGFloat

    var body: some View {
        let glow = artwork.palette.first ?? .black
        KitoArtworkView(artwork, cornerRadius: cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .phaseAnimator([false, true]) { content, phase in
                content
                    .rotation3DEffect(.degrees(isPlaying && animated ? (phase ? 3 : -3) : 0), axis: (x: phase ? 1 : 0.4, y: phase ? -0.6 : 1, z: 0), perspective: 0.6)
                    .rotationEffect(.degrees(isPlaying && animated ? (phase ? 1.2 : -1.2) : 0))
            } animation: { _ in .easeInOut(duration: 3.2) }
            .scaleEffect(isPlaying ? 1 : 0.82)
            .shadow(color: glow.opacity(isPlaying ? 0.55 : 0.25), radius: isPlaying ? 34 : 14, y: isPlaying ? 22 : 8)
            .animation(.spring(response: 0.55, dampingFraction: 0.62), value: isPlaying)
    }
}

struct VinylArtwork: View {
    let artwork: KitoArtwork
    let isPlaying: Bool

    @State private var baseAngle: Double = 0
    @State private var startedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isPlaying)) { context in
            let angle = baseAngle + (startedAt.map { context.date.timeIntervalSince($0) * 40 } ?? 0)
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                ZStack {
                    Circle().fill(Color(white: 0.06))
                    ForEach(0..<9, id: \.self) { ring in
                        Circle()
                            .strokeBorder(.white.opacity(ring % 2 == 0 ? 0.05 : 0.025), lineWidth: 1)
                            .padding(side * (0.04 + CGFloat(ring) * 0.035))
                    }
                    KitoArtworkView(artwork, cornerRadius: side)
                        .frame(width: side * 0.42, height: side * 0.42)
                    Circle().fill(Color(white: 0.06)).frame(width: side * 0.045)
                }
                .rotationEffect(.degrees(angle))
                .overlay {
                    Circle()
                        .fill(AngularGradient(colors: [.white.opacity(0), .white.opacity(0.14), .white.opacity(0), .white.opacity(0.1), .white.opacity(0)], center: .center))
                        .allowsHitTesting(false)
                }
                .frame(width: side, height: side)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
            }
        }
        .onAppear { if isPlaying { startedAt = .now } }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                startedAt = .now
            } else if let startedAt {
                baseAngle += Date.now.timeIntervalSince(startedAt) * 40
                self.startedAt = nil
            }
        }
    }
}

/// Soft colour fields from the artwork's palette, drifting slowly while music plays.
struct AudioBackdrop: View {
    let artwork: KitoArtwork
    let isPlaying: Bool

    var body: some View {
        let palette = artwork.palette
        let first = palette.first ?? .gray
        let last = palette.last ?? .black
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [first.opacity(0.95), last.opacity(0.9), .black], startPoint: .top, endPoint: .bottom)
                if case .image(let image) = artwork {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 60)
                        .opacity(0.8)
                }
                PhaseAnimator([0, 1, 2]) { phase in
                    ZStack {
                        Circle()
                            .fill(first)
                            .frame(width: proxy.size.width * 1.1)
                            .blur(radius: 80)
                            .offset(x: isPlaying ? [-60, 40, -10][phase] : -30, y: isPlaying ? [-proxy.size.height * 0.3, -proxy.size.height * 0.2, -proxy.size.height * 0.35][phase] : -proxy.size.height * 0.28)
                        Circle()
                            .fill(last)
                            .frame(width: proxy.size.width)
                            .blur(radius: 90)
                            .offset(x: isPlaying ? [70, -30, 50][phase] : 40, y: isPlaying ? [proxy.size.height * 0.25, proxy.size.height * 0.1, proxy.size.height * 0.3][phase] : proxy.size.height * 0.2)
                    }
                    .opacity(0.7)
                } animation: { _ in .easeInOut(duration: 6) }
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .animation(.easeInOut(duration: 0.8), value: palette.count)
        .accessibilityHidden(true)
    }
}

struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .symbolEffect(.bounce.down, value: taps)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(KitoPressStyle())
        .accessibilityLabel(label)
    }
}
