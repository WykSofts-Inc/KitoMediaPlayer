//
//  KitoVideoPlayer.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore
@preconcurrency import AVFoundation

/// How `KitoVideoPlayer` dresses the video.
public enum KitoVideoPlayerStyle: String, CaseIterable, Sendable {
    /// Full chrome: title, speed, mute, Picture in Picture, fullscreen, ±10s and a chaptered scrubber.
    case cinema
    /// Just a play button and a slim scrubber that fade away.
    case minimal
    /// Vertical, edge-to-edge, Reels-style: tap to pause, double-tap to like, side actions and a thin progress line.
    case social
    /// A card with the video on top and compact controls below.
    case inline
}

/// A side button for the `.social` style. Toggleable actions (with an `activeSystemImage`)
/// switch on tap and count up; the first toggleable one also fires on double-tap.
public struct KitoVideoAction: Identifiable {
    public var title: String
    public var systemImage: String
    public var activeSystemImage: String?
    public var count: Int?
    public var isActive: Bool
    public var activeTint: Color
    /// Called with the new active state (always `false` for plain actions).
    public var action: (Bool) -> Void

    public var id: String { title }

    public init(
        _ title: String,
        systemImage: String,
        activeSystemImage: String? = nil,
        count: Int? = nil,
        isActive: Bool = false,
        activeTint: Color = .pink,
        action: @escaping (Bool) -> Void = { _ in }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.activeSystemImage = activeSystemImage
        self.count = count
        self.isActive = isActive
        self.activeTint = activeTint
        self.action = action
    }

    public static func like(count: Int? = nil, isActive: Bool = false, action: @escaping (Bool) -> Void = { _ in }) -> KitoVideoAction {
        KitoVideoAction("Like", systemImage: "heart.fill", activeSystemImage: "heart.fill", count: count, isActive: isActive, activeTint: Color(red: 1, green: 0.2, blue: 0.4), action: action)
    }

    public static func comments(count: Int? = nil, action: @escaping () -> Void = {}) -> KitoVideoAction {
        KitoVideoAction("Comments", systemImage: "bubble.right.fill", count: count) { _ in action() }
    }

    public static func save(count: Int? = nil, isActive: Bool = false, action: @escaping (Bool) -> Void = { _ in }) -> KitoVideoAction {
        KitoVideoAction("Save", systemImage: "bookmark.fill", activeSystemImage: "bookmark.fill", count: count, isActive: isActive, activeTint: .yellow, action: action)
    }

    public static func share(action: @escaping () -> Void = {}) -> KitoVideoAction {
        KitoVideoAction("Share", systemImage: "arrowshape.turn.up.right.fill") { _ in action() }
    }
}

/// An `AVPlayer`-backed video player with custom chrome: morphing play/pause, a chaptered
/// scrubber with buffered range and time bubble, double-tap ±10s with a ripple, speed menu,
/// mute, fullscreen, Picture in Picture, poster, loading and error states.
///
/// ```swift
/// KitoVideoPlayer(url: videoURL, chapters: chapters, style: .cinema, title: "Keynote")
/// ```
public struct KitoVideoPlayer: View {
    private let external: KitoVideoPlayerModel?
    @State private var owned: KitoVideoPlayerModel
    private let config: VideoConfig

    /// Drive the player from a model you own — to control playback from elsewhere.
    public init(
        model: KitoVideoPlayerModel,
        style: KitoVideoPlayerStyle = .cinema,
        title: String? = nil,
        subtitle: String? = nil,
        poster: Image? = nil,
        actions: [KitoVideoAction] = [],
        tint: Color? = nil
    ) {
        external = model
        _owned = State(initialValue: model)
        config = VideoConfig(style: style, title: title, subtitle: subtitle, poster: poster, actions: actions, tint: tint)
    }

    /// A player that owns its own model.
    public init(
        url: URL,
        chapters: [KitoChapter] = [],
        loops: Bool = false,
        isMuted: Bool = false,
        autoplay: Bool = false,
        style: KitoVideoPlayerStyle = .cinema,
        title: String? = nil,
        subtitle: String? = nil,
        poster: Image? = nil,
        actions: [KitoVideoAction] = [],
        tint: Color? = nil
    ) {
        external = nil
        _owned = State(initialValue: KitoVideoPlayerModel(url: url, chapters: chapters, loops: loops, isMuted: isMuted, autoplay: autoplay))
        config = VideoConfig(style: style, title: title, subtitle: subtitle, poster: poster, actions: actions, tint: tint)
    }

    public var body: some View {
        VideoChrome(model: external ?? owned, config: config)
    }
}

struct VideoConfig {
    var style: KitoVideoPlayerStyle
    var title: String?
    var subtitle: String?
    var poster: Image?
    var actions: [KitoVideoAction]
    var tint: Color?
}

/// Just the picture, for building your own chrome around a `KitoVideoPlayerModel`.
public struct KitoVideoSurface: UIViewRepresentable {
    public enum Gravity: Sendable { case fit, fill }

    let model: KitoVideoPlayerModel
    let gravity: Gravity
    let isPrimary: Bool

    public init(model: KitoVideoPlayerModel, gravity: Gravity = .fit) {
        self.init(model: model, gravity: gravity, isPrimary: true)
    }

    init(model: KitoVideoPlayerModel, gravity: Gravity, isPrimary: Bool) {
        self.model = model
        self.gravity = gravity
        self.isPrimary = isPrimary
    }

    public func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .clear
        view.playerLayer?.player = model.player
        update(view)
        return view
    }

    public func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer?.player !== model.player { view.playerLayer?.player = model.player }
        update(view)
    }

    private func update(_ view: PlayerLayerView) {
        view.playerLayer?.videoGravity = gravity == .fill ? .resizeAspectFill : .resizeAspect
        guard isPrimary, let layer = view.playerLayer else { return }
        let model = model
        Task { @MainActor in model.attach(layer) }
    }

    /// A view whose backing layer is an `AVPlayerLayer`.
    public final class PlayerLayerView: UIView {
        override public class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    }
}

// MARK: - Chrome

struct VideoChrome: View {
    let model: KitoVideoPlayerModel
    let config: VideoConfig
    var isFullscreenPresentation = false
    var onClose: (() -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var ripple: SeekRipple?
    @State private var rippleTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var hearts: [HeartBurst] = []
    @State private var likeTrigger = 0
    @State private var seekHaptic = 0

    private var style: KitoVideoPlayerStyle { config.style }
    /// Over video the accent defaults to white; cards use the theme's primary colour.
    private var accent: Color { config.tint ?? (style == .inline ? theme.colors.primary : .white) }

    var body: some View {
        Group {
            if style == .inline {
                inlineLayout
            } else {
                overlayLayout
            }
        }
        .task { model.prepare() }
        .onChange(of: model.isPlaying) { _, playing in
            if !playing { show() } else { scheduleHide() }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: seekHaptic)
        .fullScreenCover(isPresented: fullscreenBinding) {
            FullscreenVideo(model: model, config: config)
        }
    }

    private var fullscreenBinding: Binding<Bool> {
        Binding(
            get: { !isFullscreenPresentation && model.isFullscreen },
            set: { if !isFullscreenPresentation { model.isFullscreen = $0 } }
        )
    }

    // MARK: Layouts

    private var overlayLayout: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea(edges: isFullscreenPresentation ? .all : [])
                KitoVideoSurface(model: model, gravity: style == .social ? .fill : .fit, isPrimary: isFullscreenPresentation || !model.isFullscreen)
                    .ignoresSafeArea(edges: isFullscreenPresentation ? .all : [])
                    .accessibilityHidden(true)
                gestureLayer(size: proxy.size)
                if let ripple {
                    SeekRippleView(ripple: ripple, size: proxy.size, reduceMotion: reduceMotion)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                ZStack {
                    ForEach(hearts) { heart in
                        HeartBurstView(burst: heart, reduceMotion: reduceMotion)
                            .position(heart.location)
                            .allowsHitTesting(false)
                    }
                }
                // Tap locations are physical, so place the hearts physically.
                .environment(\.layoutDirection, .leftToRight)
                switch style {
                case .cinema: cinemaChrome(size: proxy.size)
                case .minimal: minimalChrome
                case .social: socialChrome
                case .inline: EmptyView()
                }
                posterLayer
                statusLayer
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .animation(.easeOut(duration: 0.35), value: model.hasStarted)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.failureMessage)
        .statusBarHidden(isFullscreenPresentation && !controlsVisible)
        .persistentSystemOverlays(isFullscreenPresentation && !controlsVisible ? .hidden : .automatic)
    }

    private var inlineLayout: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack {
                    Color.black
                    KitoVideoSurface(model: model, gravity: .fit, isPrimary: !model.isFullscreen)
                        .accessibilityHidden(true)
                    gestureLayer(size: proxy.size)
                    if let ripple {
                        SeekRippleView(ripple: ripple, size: proxy.size, reduceMotion: reduceMotion)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                    if model.hasStarted && !model.isPlaying && model.failureMessage == nil {
                        PlayPauseButton(isPlaying: false, didFinish: model.didFinish, diameter: 56, glass: true) { model.togglePlayback() }
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    posterLayer
                    statusLayer
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: theme.spacing.md) {
                HStack(alignment: .top, spacing: theme.spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = config.title {
                            Text(title).font(theme.typography.bodyEmphasized).foregroundStyle(theme.colors.onSurface).lineLimit(2)
                        }
                        if let line = model.currentChapter?.title ?? config.subtitle {
                            Text(line)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.onSurface.opacity(0.6))
                                .lineLimit(1)
                                .contentTransition(.opacity)
                        }
                    }
                    Spacer(minLength: 0)
                    KitoPlaybackRateChip(model: model, tint: accent)
                }
                HStack(spacing: theme.spacing.sm) {
                    PlayPauseButton(isPlaying: model.isPlaying, didFinish: model.didFinish, diameter: 40, fill: accent, symbolColor: theme.colors.onPrimary) {
                        model.togglePlayback()
                    }
                    KitoScrubber(
                        currentTime: model.currentTime,
                        duration: model.duration,
                        buffered: model.bufferedTime,
                        chapters: model.chapters,
                        accent: accent,
                        track: theme.colors.onSurface.opacity(0.1),
                        bufferColor: theme.colors.onSurface.opacity(0.2),
                        onScrub: { model.scrub(to: $0) },
                        onSeek: { model.endScrub(at: $0) }
                    )
                    Text(KitoMediaTime.string(model.currentTime))
                        .font(theme.typography.caption.monospacedDigit())
                        .foregroundStyle(theme.colors.onSurface.opacity(0.6))
                        .contentTransition(.numericText())
                    iconButton(model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: model.isMuted ? "Unmute" : "Mute", color: theme.colors.onSurface) {
                        model.toggleMuted()
                    }
                    iconButton("arrow.up.left.and.arrow.down.right", label: "Full screen", color: theme.colors.onSurface) {
                        model.isFullscreen = true
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(theme.spacing.lg)
        }
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous).strokeBorder(theme.colors.border.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.isPlaying)
        .animation(.easeOut(duration: 0.35), value: model.hasStarted)
    }

    // MARK: Cinema

    private func cinemaChrome(size: CGSize) -> some View {
        let compact = size.height < 260
        return ZStack {
            if controlsVisible && model.hasStarted && model.failureMessage == nil {
                LinearGradient(colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                    .ignoresSafeArea(edges: isFullscreenPresentation ? .all : [])
                    .transition(.opacity)
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    HStack(spacing: compact ? 28 : 44) {
                        SkipButton(seconds: -10, size: compact ? 24 : 30) { skip(-10) }
                        PlayPauseButton(isPlaying: model.isPlaying, didFinish: model.didFinish, diameter: compact ? 56 : 72, glass: true) {
                            model.togglePlayback()
                        }
                        SkipButton(seconds: 10, size: compact ? 24 : 30) { skip(10) }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        if let chapter = model.currentChapter {
                            Label(chapter.title, systemImage: chapter.systemImage ?? "list.bullet")
                                .font(theme.typography.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentTransition(.opacity)
                        }
                        scrubber(thin: false)
                        HStack {
                            Text(KitoMediaTime.string(model.currentTime))
                            Spacer()
                            Text(KitoMediaTime.remainingString(currentTime: model.currentTime, duration: model.duration))
                        }
                        .font(theme.typography.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .padding(.horizontal, theme.spacing.lg)
                .padding(.vertical, compact ? theme.spacing.sm : theme.spacing.md)
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: theme.spacing.xs) {
            if isFullscreenPresentation {
                iconButton("chevron.down", label: "Close full screen") { onClose?() }
            }
            VStack(alignment: .leading, spacing: 1) {
                if let title = config.title {
                    Text(title).font(theme.typography.bodyEmphasized).lineLimit(1)
                }
                if let subtitle = config.subtitle {
                    Text(subtitle).font(theme.typography.caption).opacity(0.7).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            Spacer(minLength: theme.spacing.sm)
            speedMenu
            iconButton(model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: model.isMuted ? "Unmute" : "Mute") {
                model.toggleMuted()
                poke()
            }
            if model.isPictureInPictureSupported {
                iconButton(model.isPictureInPictureActive ? "pip.exit" : "pip.enter", label: "Picture in Picture") {
                    model.togglePictureInPicture()
                }
                .disabled(!model.isPictureInPicturePossible)
                .opacity(model.isPictureInPicturePossible ? 1 : 0.4)
            }
            if !isFullscreenPresentation {
                iconButton("arrow.up.left.and.arrow.down.right", label: "Full screen") { model.isFullscreen = true }
            }
        }
    }

    private var speedMenu: some View {
        Menu {
            Picker("Playback speed", selection: Binding(get: { model.rate }, set: { model.setRate($0); poke() })) {
                ForEach(KitoPlaybackRate.standard, id: \.self) { rate in
                    Text(KitoPlaybackRate.label(rate)).tag(rate)
                }
            }
        } label: {
            Text(KitoPlaybackRate.label(model.rate))
                .font(theme.typography.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(model.rate)))
                .padding(.horizontal, theme.spacing.sm)
                .padding(.vertical, theme.spacing.xs)
                .background(Capsule().fill(.white.opacity(model.rate == 1 ? 0.15 : 0.3)))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue(KitoPlaybackRate.label(model.rate))
    }

    // MARK: Minimal

    private var minimalChrome: some View {
        ZStack {
            if controlsVisible && model.hasStarted && model.failureMessage == nil {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                PlayPauseButton(isPlaying: model.isPlaying, didFinish: model.didFinish, diameter: 56, glass: true) {
                    model.togglePlayback()
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                VStack {
                    Spacer()
                    HStack(spacing: theme.spacing.sm) {
                        Text("\(KitoMediaTime.string(model.currentTime)) / \(KitoMediaTime.string(model.duration))")
                            .font(theme.typography.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                        scrubber(thin: true)
                        iconButton(model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: model.isMuted ? "Unmute" : "Mute", size: 14) {
                            model.toggleMuted()
                            poke()
                        }
                        if !isFullscreenPresentation {
                            iconButton("arrow.up.left.and.arrow.down.right", label: "Full screen", size: 14) { model.isFullscreen = true }
                        } else {
                            iconButton("arrow.down.right.and.arrow.up.left", label: "Close full screen", size: 14) { onClose?() }
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.bottom, theme.spacing.xs)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Social

    private var socialChrome: some View {
        ZStack {
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            if model.hasStarted && !model.isPlaying && model.failureMessage == nil {
                Image(systemName: model.didFinish ? "arrow.counterclockwise" : "play.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.35), radius: 12)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    iconButton(model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: model.isMuted ? "Unmute" : "Mute", size: 15) {
                        model.toggleMuted()
                    }
                    .background(Circle().fill(.black.opacity(0.25)).frame(width: 36, height: 36))
                }
                .padding(theme.spacing.md)
                Spacer()
                HStack(alignment: .bottom, spacing: theme.spacing.md) {
                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        if let title = config.title {
                            Text(title).font(theme.typography.bodyEmphasized)
                        }
                        if let subtitle = config.subtitle {
                            Text(subtitle).font(theme.typography.caption).lineLimit(3).opacity(0.9)
                        }
                        if let chapter = model.currentChapter {
                            Label(chapter.title, systemImage: "music.note")
                                .font(theme.typography.caption.weight(.semibold))
                                .opacity(0.85)
                                .contentTransition(.opacity)
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    SocialActionColumn(actions: config.actions, likeTrigger: likeTrigger, isPlaying: model.isPlaying, accent: accent)
                }
                .padding(.horizontal, theme.spacing.md)
                .padding(.bottom, theme.spacing.sm)
                scrubber(thin: true, showsThumb: false)
                    .padding(.horizontal, isScrubbing ? theme.spacing.md : 0)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.isPlaying)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isScrubbing)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Shared layers

    private func scrubber(thin: Bool, showsThumb: Bool = true) -> some View {
        KitoScrubber(
            currentTime: model.currentTime,
            duration: model.duration,
            buffered: model.bufferedTime,
            chapters: model.chapters,
            accent: accent,
            thin: thin,
            showsThumb: showsThumb,
            onEditingChanged: { editing in
                isScrubbing = editing
                if editing { hideTask?.cancel() } else { scheduleHide() }
            },
            onScrub: { model.scrub(to: $0) },
            onSeek: { model.endScrub(at: $0) }
        )
    }

    @ViewBuilder
    private var posterLayer: some View {
        if !model.hasStarted && model.failureMessage == nil {
            ZStack {
                posterImage
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                if !model.isPlaying {
                    PlayPauseButton(isPlaying: false, didFinish: false, diameter: style == .inline ? 60 : 76, glass: true, pulses: !reduceMotion) {
                        model.play()
                    }
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
                if style == .cinema || style == .minimal {
                    VStack(alignment: .leading, spacing: 2) {
                        Spacer()
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                if let title = config.title { Text(title).font(theme.typography.bodyEmphasized) }
                                if let subtitle = config.subtitle { Text(subtitle).font(theme.typography.caption).opacity(0.75) }
                            }
                            Spacer()
                            if model.duration > 0 {
                                Text(KitoMediaTime.string(model.duration))
                                    .font(theme.typography.caption.monospacedDigit().weight(.semibold))
                                    .padding(.horizontal, theme.spacing.sm)
                                    .padding(.vertical, theme.spacing.xxs + 1)
                                    .background(Capsule().fill(.black.opacity(0.5)))
                                    .transition(.opacity)
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(theme.spacing.lg)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.play() }
            .transition(.opacity.combined(with: .scale(scale: 1.06)))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.isPlaying)
            .animation(.easeOut(duration: 0.25), value: model.duration > 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(config.title.map { "Play \($0)" } ?? "Play video")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.play() }
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let poster = config.poster {
            poster.resizable().scaledToFill()
        } else if let thumbnail = model.thumbnail {
            Image(uiImage: thumbnail).resizable().scaledToFill().transition(.opacity)
        } else {
            GeneratedPoster(accent: config.tint ?? theme.colors.primary)
        }
    }

    @ViewBuilder
    private var statusLayer: some View {
        if let message = model.failureMessage {
            VideoErrorView(message: message, accent: config.tint ?? theme.colors.primary) { model.retry() }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        } else if model.isBuffering {
            KitoSpinner(color: .white, size: style == .inline ? 36 : 46)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func gestureLayer(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { doubleTap(at: $0.location, size: size) }
                    .exclusively(before: SpatialTapGesture(count: 1).onEnded { singleTap(at: $0.location, size: size) })
            )
            // Seek zones, ripples and hearts all work in physical left-to-right coordinates.
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement()
            .accessibilityLabel(config.title ?? "Video")
            .accessibilityValue(model.isPlaying ? "Playing, \(KitoMediaTime.spoken(model.currentTime))" : "Paused")
            .accessibilityAddTraits(.startsMediaSession)
            .accessibilityAction(.magicTap) { model.togglePlayback() }
            .accessibilityAction { model.togglePlayback() }
            .accessibilityAction(named: "Skip back 10 seconds") { model.skip(by: -10) }
            .accessibilityAction(named: "Skip forward 10 seconds") { model.skip(by: 10) }
    }

    private func iconButton(_ symbol: String, label: String, color: Color = .white, size: CGFloat = 17, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(KitoPressStyle())
        .accessibilityLabel(label)
    }

    // MARK: Interaction

    private func singleTap(at location: CGPoint, size: CGSize) {
        let zone = KitoTapZone.zone(atX: location.x, width: size.width)
        if let ripple, ripple.zone == zone, zone != .center, style != .social {
            seekTap(zone, at: location)
            return
        }
        switch style {
        case .social, .inline:
            model.togglePlayback()
        case .cinema, .minimal:
            controlsVisible ? hide() : show()
        }
    }

    private func doubleTap(at location: CGPoint, size: CGSize) {
        if style == .social {
            let heart = HeartBurst(location: location, tilt: Double.random(in: -18...18))
            hearts.append(heart)
            likeTrigger += 1
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.1))
                hearts.removeAll { $0.id == heart.id }
            }
            return
        }
        let zone = KitoTapZone.zone(atX: location.x, width: size.width)
        if zone == .center {
            model.togglePlayback()
        } else {
            seekTap(zone, at: location)
        }
    }

    private func seekTap(_ zone: KitoTapZone, at location: CGPoint) {
        guard model.duration > 0 else { return }
        model.skip(by: zone.seekOffset())
        seekHaptic += 1
        var next = ripple?.zone == zone ? (ripple ?? SeekRipple(zone: zone)) : SeekRipple(zone: zone)
        next.taps += 1
        next.location = location
        next.pulse += 1
        withAnimation(.easeOut(duration: 0.15)) { ripple = next }
        rippleTask?.cancel()
        rippleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { ripple = nil }
        }
        scheduleHide()
    }

    private func skip(_ seconds: TimeInterval) {
        model.skip(by: seconds)
        seekHaptic += 1
        poke()
    }

    private func show() {
        controlsVisible = true
        scheduleHide()
    }

    private func hide() {
        hideTask?.cancel()
        controlsVisible = false
    }

    private func poke() {
        if !controlsVisible { controlsVisible = true }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard model.isPlaying, !voiceOver, style == .cinema || style == .minimal else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !isScrubbing, model.isPlaying else { return }
            controlsVisible = false
        }
    }
}

// MARK: - Fullscreen

struct FullscreenVideo: View {
    let model: KitoVideoPlayerModel
    let config: VideoConfig
    @State private var rotated = false

    var body: some View {
        var fullscreen = config
        if fullscreen.style == .inline { fullscreen.style = .cinema }
        return VideoChrome(model: model, config: fullscreen, isFullscreenPresentation: true) {
            close()
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            let size = model.presentationSize
            if size.width > size.height * 1.1 {
                rotated = true
                OrientationRequest.request(.landscapeRight)
            }
        }
        .onDisappear {
            if rotated { OrientationRequest.request(.portrait) }
        }
    }

    private func close() {
        model.isFullscreen = false
    }
}

@MainActor
enum OrientationRequest {
    /// Asks the scene to rotate. Only takes effect for orientations the app supports.
    static func request(_ orientations: UIInterfaceOrientationMask) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let scene else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations), errorHandler: nil)
    }
}

// MARK: - Pieces

struct PlayPauseButton: View {
    let isPlaying: Bool
    let didFinish: Bool
    var diameter: CGFloat = 64
    var glass = false
    var fill: Color = .white
    var symbolColor: Color = .black
    var pulses = false
    let action: () -> Void

    @State private var ring = false

    private var symbol: String {
        if didFinish { return "arrow.counterclockwise" }
        return isPlaying ? "pause.fill" : "play.fill"
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if pulses {
                    Circle()
                        .stroke(.white.opacity(0.6), lineWidth: 2)
                        .scaleEffect(ring ? 1.45 : 1)
                        .opacity(ring ? 0 : 0.8)
                        .onAppear {
                            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { ring = true }
                        }
                }
                if glass {
                    Circle().fill(.ultraThinMaterial)
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
                } else {
                    Circle().fill(fill).shadow(color: fill.opacity(0.35), radius: 8, y: 4)
                }
                Image(systemName: symbol)
                    .font(.system(size: diameter * 0.38, weight: .bold))
                    .foregroundStyle(glass ? .white : symbolColor)
                    .offset(x: symbol == "play.fill" ? diameter * 0.04 : 0)
                    .contentTransition(.symbolEffect(.replace.downUp.byLayer))
            }
            .frame(width: diameter, height: diameter)
            .environment(\.colorScheme, glass ? .dark : .light)
        }
        .buttonStyle(KitoPressStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: isPlaying)
        .accessibilityLabel(didFinish ? "Replay" : (isPlaying ? "Pause" : "Play"))
    }
}

struct SkipButton: View {
    let seconds: Int
    var size: CGFloat = 30
    let action: () -> Void
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = reduceMotion
        return Button {
            taps += 1
            action()
        } label: {
            Image(systemName: seconds < 0 ? "gobackward.\(abs(seconds))" : "goforward.\(seconds)")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .keyframeAnimator(initialValue: 0.0, trigger: taps) { content, angle in
                    content.rotationEffect(.degrees(still ? 0 : angle))
                } keyframes: { _ in
                    SpringKeyframe(seconds < 0 ? -40 : 40, duration: 0.15)
                    SpringKeyframe(0, duration: 0.45, spring: .bouncy)
                }
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(KitoPressStyle())
        .accessibilityLabel(seconds < 0 ? "Skip back \(abs(seconds)) seconds" : "Skip forward \(seconds) seconds")
    }
}

struct SeekRipple: Equatable {
    var zone: KitoTapZone
    var taps = 0
    var location: CGPoint = .zero
    var pulse = 0
}

struct SeekRippleView: View {
    let ripple: SeekRipple
    let size: CGSize
    let reduceMotion: Bool

    var body: some View {
        let forward = ripple.zone == .forward
        ZStack {
            Ellipse()
                .fill(.white.opacity(0.13))
                .frame(width: size.width * 0.8, height: size.height * 1.7)
                .position(x: forward ? size.width * 1.02 : -size.width * 0.02, y: size.height / 2)
            PulseCircle(reduceMotion: reduceMotion)
                .id(ripple.pulse)
                .position(ripple.location)
            VStack(spacing: 6) {
                ChevronTrain(forward: forward, animated: !reduceMotion)
                Text("\(ripple.taps * 10) seconds")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(ripple.taps)))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 4)
            .position(x: forward ? size.width * 0.8 : size.width * 0.2, y: size.height / 2)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: ripple.taps)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        // Seek zones are physical (left = back), like the transport controls.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

struct PulseCircle: View {
    let reduceMotion: Bool
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(.white.opacity(0.3))
            .frame(width: 70, height: 70)
            .scaleEffect(expanded ? 3.2 : 0.4)
            .opacity(expanded ? 0 : 1)
            .onAppear {
                guard !reduceMotion else { expanded = true; return }
                withAnimation(.easeOut(duration: 0.6)) { expanded = true }
            }
    }
}

struct ChevronTrain: View {
    let forward: Bool
    let animated: Bool

    var body: some View {
        PhaseAnimator([0, 1, 2], trigger: animated ? 0 : 1) { phase in
            HStack(spacing: -2) {
                ForEach(0..<3, id: \.self) { index in
                    let lit = forward ? index : 2 - index
                    Image(systemName: forward ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill")
                        .font(.system(size: 12, weight: .bold))
                        .opacity(!animated || lit == phase ? 1 : 0.35)
                }
            }
        } animation: { _ in .easeInOut(duration: 0.16) }
    }
}

struct HeartBurst: Identifiable, Equatable {
    let id = UUID()
    let location: CGPoint
    let tilt: Double
}

struct HeartBurstView: View {
    let burst: HeartBurst
    let reduceMotion: Bool

    private struct Frame {
        var scale: CGFloat = 0.2
        var lift: CGFloat = 0
        var opacity: Double = 1
    }

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 92, weight: .bold))
            .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.35, blue: 0.55), Color(red: 1, green: 0.15, blue: 0.3)], startPoint: .top, endPoint: .bottom))
            .shadow(color: Color(red: 1, green: 0.2, blue: 0.4).opacity(0.5), radius: 14)
            .rotationEffect(.degrees(burst.tilt))
            .keyframeAnimator(initialValue: Frame(), repeating: false) { content, frame in
                content
                    .scaleEffect(frame.scale)
                    .offset(y: frame.lift)
                    .opacity(frame.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.2, duration: 0.22, spring: .bouncy)
                    SpringKeyframe(1, duration: 0.18)
                    LinearKeyframe(1, duration: 0.3)
                    LinearKeyframe(reduceMotion ? 1 : 1.35, duration: 0.3)
                }
                KeyframeTrack(\.lift) {
                    LinearKeyframe(0, duration: 0.6)
                    CubicKeyframe(reduceMotion ? 0 : -110, duration: 0.4)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.65)
                    LinearKeyframe(0, duration: 0.35)
                }
            }
            .accessibilityHidden(true)
    }
}

struct GeneratedPoster: View {
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(white: 0.12), .black], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(accent.opacity(0.55))
                    .frame(width: proxy.size.width * 0.8)
                    .blur(radius: 60)
                    .offset(x: -proxy.size.width * 0.25, y: -proxy.size.height * 0.2)
                Circle()
                    .fill(Color.purple.opacity(0.35))
                    .frame(width: proxy.size.width * 0.6)
                    .blur(radius: 60)
                    .offset(x: proxy.size.width * 0.3, y: proxy.size.height * 0.25)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct VideoErrorView: View {
    let message: String
    let accent: Color
    let retry: () -> Void

    @Environment(\.kitoTheme) private var theme
    @State private var attempts = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
            VStack(spacing: theme.spacing.md) {
                ZStack {
                    Circle().fill(theme.colors.danger.opacity(0.18)).frame(width: 64, height: 64)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(theme.colors.danger)
                        .symbolEffect(.bounce, value: attempts)
                }
                VStack(spacing: theme.spacing.xxs) {
                    Text("Can't play this video")
                        .font(theme.typography.bodyEmphasized)
                    Text(message)
                        .font(theme.typography.caption)
                        .opacity(0.7)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .foregroundStyle(.white)
                Button {
                    attempts += 1
                    retry()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(theme.typography.button)
                        .foregroundStyle(.black)
                        .padding(.horizontal, theme.spacing.lg)
                        .padding(.vertical, theme.spacing.sm)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(KitoPressStyle(scale: 0.94))
            }
            .padding(theme.spacing.xl)
        }
        .sensoryFeedback(.error, trigger: message)
    }
}

// MARK: - Social actions

struct SocialActionColumn: View {
    let actions: [KitoVideoAction]
    let likeTrigger: Int
    let isPlaying: Bool
    let accent: Color

    @State private var active: [String: Bool] = [:]
    @State private var bumps: [String: Int] = [:]
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: theme.spacing.lg) {
            ForEach(actions) { action in
                button(action)
            }
            SpinningDisc(isPlaying: isPlaying && !reduceMotion)
        }
        .onChange(of: likeTrigger) {
            guard let like = actions.first(where: { $0.activeSystemImage != nil }) else { return }
            if !isOn(like) { toggle(like) } else { bumps[like.id, default: 0] += 1 }
        }
    }

    private func isOn(_ action: KitoVideoAction) -> Bool { active[action.id] ?? action.isActive }

    private func toggle(_ action: KitoVideoAction) {
        guard action.activeSystemImage != nil else {
            bumps[action.id, default: 0] += 1
            action.action(false)
            return
        }
        let next = !isOn(action)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { active[action.id] = next }
        bumps[action.id, default: 0] += 1
        action.action(next)
    }

    private func button(_ action: KitoVideoAction) -> some View {
        let on = isOn(action)
        let base = action.count ?? 0
        let count = action.count.map { _ in base + (on ? 1 : 0) - (action.isActive ? 1 : 0) }
        return Button { toggle(action) } label: {
            VStack(spacing: 3) {
                ZStack {
                    if on {
                        PulseCircle(reduceMotion: reduceMotion)
                            .id(bumps[action.id] ?? 0)
                            .frame(width: 30, height: 30)
                            .opacity(0.6)
                    }
                    Image(systemName: on ? (action.activeSystemImage ?? action.systemImage) : action.systemImage)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(on ? action.activeTint : .white)
                        .symbolEffect(.bounce.up, value: bumps[action.id] ?? 0)
                        .shadow(color: .black.opacity(0.3), radius: 6)
                }
                .frame(width: 44, height: 40)
                if let count {
                    Text(count.formatted(.number.notation(.compactName)))
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(count)))
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
            }
        }
        .buttonStyle(KitoPressStyle(scale: 0.8))
        .sensoryFeedback(.impact(weight: .light), trigger: bumps[action.id] ?? 0)
        .accessibilityLabel(action.title)
        .accessibilityValue(count.map { "\($0)" } ?? "")
        .accessibilityAddTraits(on && action.activeSystemImage != nil ? .isSelected : [])
    }
}

struct SpinningDisc: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isPlaying)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) * 60
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(white: 0.25), .black], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(.white.opacity(0.12), lineWidth: 6)
                Image(systemName: "music.note")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .rotationEffect(.degrees(angle))
        }
        .accessibilityHidden(true)
    }
}
