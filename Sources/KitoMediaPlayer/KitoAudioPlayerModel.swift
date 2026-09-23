//
//  KitoAudioPlayerModel.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import Observation
@preconcurrency import AVFoundation
@preconcurrency import MediaPlayer

/// Cover art for a track.
public enum KitoArtwork {
    case image(UIImage)
    case remote(URL)
    /// Generated art: a gradient with a symbol, handy for placeholders and demos.
    case gradient([Color], systemImage: String)

    public static let placeholder = KitoArtwork.gradient([Color(white: 0.35), Color(white: 0.12)], systemImage: "music.note")

    /// Colours used for the player's backdrop.
    var palette: [Color] {
        switch self {
        case .gradient(let colors, _): return colors.isEmpty ? [.gray, .black] : colors
        case .image, .remote: return [Color(white: 0.25), Color(white: 0.08)]
        }
    }
}

/// One item in a `KitoAudioPlayerModel` queue.
public struct KitoAudioTrack: Identifiable, Hashable {
    public let id: String
    public var title: String
    public var artist: String
    public var album: String?
    public var url: URL
    public var artwork: KitoArtwork
    /// Podcast-style chapters, shown in `KitoChapterList` and on the lock screen's elapsed time.
    public var chapters: [KitoChapter]

    public init(
        id: String? = nil,
        title: String,
        artist: String,
        album: String? = nil,
        url: URL,
        artwork: KitoArtwork = .placeholder,
        chapters: [KitoChapter] = []
    ) {
        self.id = id ?? url.absoluteString
        self.title = title
        self.artist = artist
        self.album = album
        self.url = url
        self.artwork = artwork
        self.chapters = chapters.sorted { $0.start < $1.start }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Queue, transport, waveform and sleep timer for `KitoAudioPlayer` and `KitoMiniPlayer`.
/// Lock-screen and Control Center controls are opt-in: pass `systemControls: true` or call
/// `enableSystemControls()`.
@MainActor
@Observable
public final class KitoAudioPlayerModel {
    public private(set) var queue: KitoPlaybackQueue<KitoAudioTrack>
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var rate: Float = 1
    /// Bar levels for the current track: analysed for local files, generated otherwise.
    public private(set) var waveform: [Float] = []
    public private(set) var sleepTimer: KitoSleepTimer?
    /// "14:32" while a sleep timer runs.
    public private(set) var sleepTimerLabel: String?
    public private(set) var systemControlsEnabled = false
    public private(set) var failureMessage: String?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var observation: PlayerObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var waveforms: [String: [Float]] = [:]
    @ObservationIgnored private var renderedArtwork: [String: UIImage] = [:]
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var isScrubbing = false
    @ObservationIgnored private var isSeeking = false

    public init(tracks: [KitoAudioTrack], startAt index: Int = 0, systemControls: Bool = false) {
        queue = KitoPlaybackQueue(tracks, startAt: index)
        setUpObservers()
        loadCurrent(autoplay: false)
        if systemControls { enableSystemControls() }
    }

    // MARK: Derived

    public var tracks: [KitoAudioTrack] { queue.items }
    public var currentTrack: KitoAudioTrack? { queue.current }
    public var upNext: [KitoAudioTrack] { queue.upNext }
    public var repeatMode: KitoRepeatMode { queue.repeatMode }
    public var isShuffled: Bool { queue.isShuffled }
    public var progress: Double { KitoMediaTime.progress(currentTime, duration: duration) }
    public var chapters: [KitoChapter] { currentTrack?.chapters ?? [] }
    public var currentChapterIndex: Int? { KitoChapter.index(at: currentTime, in: chapters) }
    public var currentChapter: KitoChapter? { currentChapterIndex.map { chapters[$0] } }

    // MARK: Transport

    public func play() {
        guard currentTrack != nil else { return }
        KitoMediaSession.activatePlayback()
        if failureMessage != nil { loadCurrent(autoplay: false) }
        player.defaultRate = rate
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    public func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    public func togglePlayback() { isPlaying ? pause() : play() }

    public func seek(to time: TimeInterval) {
        let target = KitoMediaTime.clamped(time, duration: duration)
        currentTime = target
        isSeeking = true
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
                self?.updateNowPlaying()
            }
        }
    }

    /// Jumps by `seconds`; ±15 is the podcast convention.
    public func skip(by seconds: TimeInterval) { seek(to: currentTime + seconds) }

    /// The next track. At the end of the queue with repeat off, returns to the first track, paused.
    public func next() {
        if queue.advance() != nil {
            loadCurrent(autoplay: isPlaying)
        } else {
            queue.jump(to: queue.order.first ?? 0)
            loadCurrent(autoplay: false)
        }
    }

    /// Restarts the track after three seconds, otherwise goes to the previous one.
    public func previous() {
        if KitoPlaybackQueue<KitoAudioTrack>.restartsOnPrevious(elapsed: currentTime) || !queue.hasPrevious {
            seek(to: 0)
        } else {
            queue.retreat()
            loadCurrent(autoplay: isPlaying)
        }
    }

    /// Plays `track` if it's in the queue.
    public func play(_ track: KitoAudioTrack) {
        guard let index = queue.items.firstIndex(of: track) else { return }
        if index == queue.currentIndex {
            if !isPlaying { play() }
            return
        }
        queue.jump(to: index)
        loadCurrent(autoplay: true)
    }

    public func replaceQueue(with tracks: [KitoAudioTrack], startAt index: Int = 0, autoplay: Bool = false) {
        queue.replace(with: tracks, startAt: index)
        loadCurrent(autoplay: autoplay)
    }

    public func setRate(_ rate: Float) {
        self.rate = min(max(rate, 0.25), 3)
        player.defaultRate = self.rate
        if isPlaying { player.rate = self.rate }
        updateNowPlaying()
    }

    public func setRepeatMode(_ mode: KitoRepeatMode) { queue.repeatMode = mode }
    public func cycleRepeatMode() { queue.repeatMode = queue.repeatMode.next }
    public func setShuffled(_ shuffled: Bool) { queue.setShuffled(shuffled) }
    public func toggleShuffle() { queue.setShuffled(!queue.isShuffled) }

    // MARK: Sleep timer

    public func startSleepTimer(_ mode: KitoSleepTimer.Mode) {
        sleepTask?.cancel()
        let timer = KitoSleepTimer(mode)
        sleepTimer = timer
        sleepTimerLabel = timer.label()
        guard case .duration = mode else { return }
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let timer = self.sleepTimer else { return }
                let now = Date.now
                self.sleepTimerLabel = timer.label(at: now)
                self.player.volume = timer.volume(at: now)
                if timer.isExpired(at: now) {
                    self.pause()
                    self.cancelSleepTimer()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    public func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimer = nil
        sleepTimerLabel = nil
        player.volume = 1
    }

    // MARK: System integration

    /// Publishes Now Playing info and handles lock-screen, Control Center, headphone and
    /// CarPlay commands. Only one model owns them at a time; the latest caller wins.
    /// Background playback also needs the `audio` background mode in your Info.plist.
    public func enableSystemControls() {
        KitoMediaSession.activatePlayback()
        systemControlsEnabled = true
        RemoteCommandHub.shared.owner = self
        updateNowPlaying()
    }

    public func disableSystemControls() {
        systemControlsEnabled = false
        if RemoteCommandHub.shared.owner === self { RemoteCommandHub.shared.owner = nil }
    }

    // MARK: Scrubbing (used by the views)

    func scrub(to time: TimeInterval) {
        isScrubbing = true
        currentTime = KitoMediaTime.clamped(time, duration: duration)
    }

    func endScrub(at time: TimeInterval) {
        isScrubbing = false
        seek(to: time)
    }

    // MARK: Private

    private func setUpObservers() {
        let observation = PlayerObservation(player: player)
        observation.observeTime(every: 0.1) { [weak self] in self?.sync() }
        observation.observe(AVPlayerItem.didPlayToEndTimeNotification) { [weak self] sender in
            self?.itemDidFinish(sender)
        }
        observation.keyValue.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.sync() }
        })
        self.observation = observation
    }

    private func loadCurrent(autoplay: Bool) {
        failureMessage = nil
        currentTime = 0
        duration = 0
        guard let track = currentTrack else {
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            waveform = []
            return
        }
        let item = AVPlayerItem(url: track.url)
        item.audioTimePitchAlgorithm = .spectral
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.sync() }
        }
        player.replaceCurrentItem(with: item)
        loadWaveform(for: track)
        if autoplay {
            play()
        } else {
            player.pause()
            isPlaying = false
            updateNowPlaying()
        }
    }

    private func sync() {
        guard let item = player.currentItem else { return }
        if item.status == .failed {
            failureMessage = item.error?.localizedDescription ?? "This track couldn't be played."
            isPlaying = false
            return
        }
        let itemDuration = item.duration.finiteSeconds
        if itemDuration > 0, abs(itemDuration - duration) > 0.01 {
            duration = itemDuration
            updateNowPlaying()
        }
        if !isScrubbing && !isSeeking { currentTime = item.currentTime().finiteSeconds }
        let control = player.timeControlStatus
        let playing = control != .paused
        if playing != isPlaying { isPlaying = playing; updateNowPlaying() }
        let buffering = control == .waitingToPlayAtSpecifiedRate
        if buffering != isBuffering { isBuffering = buffering }
    }

    private func itemDidFinish(_ sender: ObjectIdentifier?) {
        guard let item = player.currentItem, sender == ObjectIdentifier(item) else { return }
        if sleepTimer?.mode == .endOfTrack {
            cancelSleepTimer()
            isPlaying = false
            if queue.advance(automatically: false) != nil { loadCurrent(autoplay: false) }
            return
        }
        if queue.repeatMode == .one {
            seek(to: 0)
            player.play()
        } else if queue.advance(automatically: true) != nil {
            loadCurrent(autoplay: true)
        } else {
            queue.jump(to: queue.order.first ?? 0)
            loadCurrent(autoplay: false)
        }
    }

    private func loadWaveform(for track: KitoAudioTrack) {
        if let cached = waveforms[track.id] {
            waveform = cached
            return
        }
        let placeholder = KitoWaveformAnalyzer.placeholder(count: 96, seed: track.id)
        waveform = placeholder
        guard track.url.isFileURL else { return }
        let url = track.url, id = track.id
        Task { [weak self] in
            guard let peaks = try? await KitoWaveformAnalyzer.peaks(of: url, count: 96) else { return }
            guard let self else { return }
            self.waveforms[id] = peaks
            if self.currentTrack?.id == id { self.waveform = peaks }
        }
    }

    fileprivate func updateNowPlaying() {
        guard systemControlsEnabled, RemoteCommandHub.shared.owner === self, let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.items.count,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: queue.position,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let album = track.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let chapter = currentChapter { info[MPNowPlayingInfoPropertyChapterNumber] = currentChapterIndex ?? 0; info[MPMediaItemPropertyComments] = chapter.title }
        if let image = artworkImage(for: track) { info[MPMediaItemPropertyArtwork] = Self.makeArtwork(image) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func artworkImage(for track: KitoAudioTrack) -> UIImage? {
        switch track.artwork {
        case .image(let image):
            return image
        case .remote(let url):
            if let cached = renderedArtwork[track.id] { return cached }
            let id = track.id
            Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
                self?.renderedArtwork[id] = image
                self?.updateNowPlaying()
            }
            return nil
        case .gradient:
            if let cached = renderedArtwork[track.id] { return cached }
            let renderer = ImageRenderer(content: KitoArtworkView(track.artwork, cornerRadius: 0).frame(width: 600, height: 600))
            renderer.scale = 1
            let image = renderer.uiImage
            renderedArtwork[track.id] = image
            return image
        }
    }

    /// Built outside the main actor so the system can call the handler from any queue.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    fileprivate func handle(_ command: RemoteCommandHub.Command) -> Bool {
        switch command {
        case .play: play()
        case .pause: pause()
        case .toggle: togglePlayback()
        case .next: next()
        case .previous: previous()
        case .skip(let seconds): skip(by: seconds)
        case .seek(let time): seek(to: time)
        case .rate(let rate): setRate(rate)
        }
        return true
    }
}

/// Registers remote commands once and forwards them to whichever model currently owns them.
@MainActor
private final class RemoteCommandHub {
    enum Command {
        case play, pause, toggle, next, previous
        case skip(TimeInterval)
        case seek(TimeInterval)
        case rate(Float)
    }

    static let shared = RemoteCommandHub()

    weak var owner: KitoAudioPlayerModel? {
        didSet {
            registerIfNeeded()
            if owner == nil { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        }
    }

    private var isRegistered = false

    private func registerIfNeeded() {
        guard !isRegistered else { return }
        isRegistered = true
        let center = MPRemoteCommandCenter.shared()
        add(center.playCommand) { _ in .play }
        add(center.pauseCommand) { _ in .pause }
        add(center.togglePlayPauseCommand) { _ in .toggle }
        add(center.nextTrackCommand) { _ in .next }
        add(center.previousTrackCommand) { _ in .previous }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        add(center.skipForwardCommand) { event in
            .skip((event as? MPSkipIntervalCommandEvent)?.interval ?? 15)
        }
        add(center.skipBackwardCommand) { event in
            .skip(-((event as? MPSkipIntervalCommandEvent)?.interval ?? 15))
        }
        add(center.changePlaybackPositionCommand) { event in
            (event as? MPChangePlaybackPositionCommandEvent).map { .seek($0.positionTime) }
        }
        center.changePlaybackRateCommand.supportedPlaybackRates = KitoPlaybackRate.standard.map { NSNumber(value: $0) }
        add(center.changePlaybackRateCommand) { event in
            (event as? MPChangePlaybackRateCommandEvent).map { .rate($0.playbackRate) }
        }
    }

    private func add(_ command: MPRemoteCommand, _ translate: @escaping (MPRemoteCommandEvent) -> Command?) {
        command.isEnabled = true
        command.addTarget { [weak self] event in
            guard let action = translate(event) else { return .commandFailed }
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    self?.owner?.handle(action) == true ? .success : .noActionableNowPlayingItem
                }
            }
            Task { @MainActor in _ = self?.owner?.handle(action) }
            return .success
        }
    }
}
