//
//  KitoVideoPlayerModel.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import Observation
@preconcurrency import AVFoundation
@preconcurrency import AVKit

/// Playback state for `KitoVideoPlayer`, backed by `AVPlayer`. Create one per video and keep it
/// in `@State`; the view calls `prepare()` when it appears, so creating a model is cheap.
@MainActor
@Observable
public final class KitoVideoPlayerModel {
    public enum Status: Equatable, Sendable {
        case idle, loading, ready
        case failed(String)
    }

    public private(set) var url: URL
    public private(set) var chapters: [KitoChapter]
    /// Starts again from the beginning when the video ends.
    public var loops: Bool
    public private(set) var status: Status = .idle
    public private(set) var isPlaying = false
    /// Playing was requested but the player is waiting for data.
    public private(set) var isBuffering = false
    /// Becomes true the first time frames actually play, which is when the poster goes away.
    public private(set) var hasStarted = false
    public private(set) var didFinish = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    /// How far ahead of the start the player has data, in seconds.
    public private(set) var bufferedTime: TimeInterval = 0
    public private(set) var rate: Float = 1
    public private(set) var isMuted: Bool
    /// The video's natural size once known (zero before).
    public private(set) var presentationSize: CGSize = .zero
    /// A frame grabbed from file-based media, used as the poster when you don't pass one.
    public private(set) var thumbnail: UIImage?
    public internal(set) var isFullscreen = false
    public private(set) var isPictureInPictureActive = false
    public private(set) var isPictureInPicturePossible = false

    /// The underlying player, for things like AirPlay or external playback settings.
    public let player = AVPlayer()

    @ObservationIgnored private let autoplay: Bool
    @ObservationIgnored private var observation: PlayerObservation?
    @ObservationIgnored private var itemObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var isScrubbing = false
    @ObservationIgnored private weak var pipLayer: AVPlayerLayer?
    @ObservationIgnored private var pipController: AVPictureInPictureController?
    @ObservationIgnored private var pipObservation: NSKeyValueObservation?
    @ObservationIgnored private lazy var pipDelegate = PictureInPictureDelegate(model: self)

    /// - Parameters:
    ///   - url: a local file, progressive download or HLS stream.
    ///   - chapters: shown as markers on the scrubber.
    ///   - loops: restart when the end is reached.
    ///   - isMuted: start without sound (feeds, previews).
    ///   - autoplay: play as soon as the view appears.
    public init(url: URL, chapters: [KitoChapter] = [], loops: Bool = false, isMuted: Bool = false, autoplay: Bool = false) {
        self.url = url
        self.chapters = chapters.sorted { $0.start < $1.start }
        self.loops = loops
        self.isMuted = isMuted
        self.autoplay = autoplay
    }

    // MARK: Derived

    public var progress: Double { KitoMediaTime.progress(currentTime, duration: duration) }
    public var bufferedProgress: Double { KitoMediaTime.progress(bufferedTime, duration: duration) }
    public var currentChapterIndex: Int? { KitoChapter.index(at: currentTime, in: chapters) }
    public var currentChapter: KitoChapter? { currentChapterIndex.map { chapters[$0] } }
    public var isPictureInPictureSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }
    public var failureMessage: String? {
        if case .failed(let message) = status { return message }
        return nil
    }

    // MARK: Lifecycle

    /// Creates the player item and starts loading. Safe to call more than once.
    public func prepare() {
        guard status == .idle else { return }
        let observation = PlayerObservation(player: player)
        observation.observeTime(every: 0.1) { [weak self] in self?.sync() }
        observation.observe(AVPlayerItem.didPlayToEndTimeNotification) { [weak self] sender in
            self?.itemDidFinish(sender)
        }
        observation.observe(AVPlayerItem.failedToPlayToEndTimeNotification) { [weak self] sender in
            guard let self, sender == self.player.currentItem.map(ObjectIdentifier.init) else { return }
            self.fail(self.player.currentItem?.error)
        }
        observation.keyValue.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.sync() }
        })
        self.observation = observation
        player.isMuted = isMuted
        player.actionAtItemEnd = .pause
        loadItem()
        if autoplay { play() }
        loadThumbnail()
    }

    /// Swaps in different media, keeping mute, rate and loop settings.
    public func replace(url: URL, chapters: [KitoChapter] = []) {
        self.url = url
        self.chapters = chapters.sorted { $0.start < $1.start }
        hasStarted = false
        thumbnail = nil
        currentTime = 0
        duration = 0
        bufferedTime = 0
        if status == .idle { return }
        loadItem()
        loadThumbnail()
    }

    /// Reloads after a failure and resumes from where playback stopped.
    public func retry() {
        let resumeAt = currentTime
        loadItem()
        if resumeAt > 0 { seek(to: resumeAt) }
        if wantsPlayback || hasStarted { play() }
    }

    // MARK: Transport

    public func play() {
        if status == .idle { prepare() }
        KitoMediaSession.activatePlayback()
        if didFinish {
            didFinish = false
            seek(to: 0)
        }
        wantsPlayback = true
        player.defaultRate = rate
        player.play()
        isPlaying = true
    }

    public func pause() {
        wantsPlayback = false
        player.pause()
        isPlaying = false
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// Seeks to `time`, clamped to the video. Frame-accurate unless `precise` is false
    /// (faster, for live scrubbing).
    public func seek(to time: TimeInterval, precise: Bool = true) {
        let target = KitoMediaTime.clamped(time, duration: duration)
        currentTime = target
        if target < duration - 0.25 { didFinish = false }
        isSeeking = true
        let tolerance: CMTime = precise ? .zero : CMTime(seconds: 0.4, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor in self?.isSeeking = false }
        }
    }

    /// Jumps by `seconds` (negative to go back).
    public func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    public func setRate(_ rate: Float) {
        self.rate = min(max(rate, 0.25), 3)
        player.defaultRate = self.rate
        if isPlaying { player.rate = self.rate }
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        player.isMuted = muted
    }

    public func toggleMuted() { setMuted(!isMuted) }

    public func togglePictureInPicture() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else if pipController.isPictureInPicturePossible {
            KitoMediaSession.activatePlayback()
            pipController.startPictureInPicture()
        }
    }

    // MARK: Scrubbing (used by the chrome)

    func scrub(to time: TimeInterval) {
        isScrubbing = true
        seek(to: time, precise: false)
    }

    func endScrub(at time: TimeInterval) {
        seek(to: time)
        isScrubbing = false
    }

    // MARK: Picture in Picture

    func attach(_ layer: AVPlayerLayer) {
        guard pipLayer !== layer else { return }
        pipLayer = layer
        pipObservation = nil
        pipController = nil
        isPictureInPicturePossible = false
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: layer) else { return }
        controller.delegate = pipDelegate
        pipController = controller
        pipObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, change in
            let possible = change.newValue ?? false
            Task { @MainActor in self?.isPictureInPicturePossible = possible }
        }
    }

    func pictureInPictureChanged(active: Bool) {
        isPictureInPictureActive = active
    }

    // MARK: Private

    private func loadItem() {
        status = .loading
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 8
        itemObservations = [
            item.observe(\.status, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.sync() }
            },
            item.observe(\.presentationSize, options: [.new]) { [weak self] _, change in
                let size = change.newValue ?? .zero
                Task { @MainActor in self?.presentationSize = size }
            },
        ]
        player.replaceCurrentItem(with: item)
    }

    private func sync() {
        guard let item = player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            if status != .ready { status = .ready }
        case .failed:
            fail(item.error)
            return
        default:
            break
        }
        let itemDuration = item.duration.finiteSeconds
        if itemDuration > 0, abs(itemDuration - duration) > 0.01 { duration = itemDuration }
        if !isSeeking && !isScrubbing { currentTime = item.currentTime().finiteSeconds }
        bufferedTime = bufferedEnd(of: item)

        let control = player.timeControlStatus
        let playing = control != .paused
        if playing != isPlaying { isPlaying = playing }
        let buffering = control == .waitingToPlayAtSpecifiedRate
        if buffering != isBuffering { isBuffering = buffering }
        if control == .playing && !hasStarted { hasStarted = true }
    }

    private func bufferedEnd(of item: AVPlayerItem) -> TimeInterval {
        let now = item.currentTime().finiteSeconds
        var end: TimeInterval = 0
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.finiteSeconds
            let finish = start + range.duration.finiteSeconds
            if start <= now + 0.5 && finish > end { end = finish }
        }
        return end
    }

    private func fail(_ error: Error?) {
        let message = error?.localizedDescription ?? "The video couldn't be loaded."
        status = .failed(message)
        isPlaying = false
        isBuffering = false
    }

    private func itemDidFinish(_ sender: ObjectIdentifier?) {
        guard let item = player.currentItem, sender == ObjectIdentifier(item) else { return }
        if loops {
            seek(to: 0)
            player.play()
        } else {
            didFinish = true
            wantsPlayback = false
            isPlaying = false
            currentTime = duration
        }
    }

    private func loadThumbnail() {
        guard url.pathExtension.lowercased() != "m3u8" else { return }
        let url = url
        Task { [weak self] in
            let image = await Task.detached(priority: .utility) { () -> CGImage? in
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 1280, height: 1280)
                return try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
            }.value
            guard let self, let image, self.url == url else { return }
            self.thumbnail = UIImage(cgImage: image)
        }
    }
}

/// Forwards Picture in Picture state to the model.
private final class PictureInPictureDelegate: NSObject, AVPictureInPictureControllerDelegate {
    private weak var model: KitoVideoPlayerModel?

    init(model: KitoVideoPlayerModel) {
        self.model = model
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        report(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        report(false)
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        report(false)
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    private func report(_ active: Bool) {
        let model = model
        Task { @MainActor in model?.pictureInPictureChanged(active: active) }
    }
}
