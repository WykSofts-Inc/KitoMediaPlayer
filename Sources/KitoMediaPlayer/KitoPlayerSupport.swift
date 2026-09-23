//
//  KitoPlayerSupport.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
@preconcurrency import AVFoundation

/// Owns an `AVPlayer`'s observers and removes them when released, so the models that use it
/// never need a `deinit`.
final class PlayerObservation {
    private let player: AVPlayer
    private var timeToken: Any?
    private var notificationTokens: [NSObjectProtocol] = []
    var keyValue: [NSKeyValueObservation] = []

    init(player: AVPlayer) {
        self.player = player
    }

    func observeTime(every interval: TimeInterval, _ handler: @escaping @MainActor () -> Void) {
        if let timeToken { player.removeTimeObserver(timeToken) }
        let time = CMTime(seconds: interval, preferredTimescale: 600)
        timeToken = player.addPeriodicTimeObserver(forInterval: time, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    /// Calls `handler` on the main actor with the identity of the item that posted `name`.
    func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (ObjectIdentifier?) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
            let sender = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { handler(sender) }
        }
        notificationTokens.append(token)
    }

    deinit {
        if let timeToken { player.removeTimeObserver(timeToken) }
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        keyValue.forEach { $0.invalidate() }
    }
}

/// Audio session setup shared by the players.
public enum KitoMediaSession {
    /// Switches the app to the `.playback` category (sound with the silent switch on, and
    /// background audio when the app declares the `audio` background mode). Leaves a category
    /// the app chose itself alone. The players call this on first play.
    public static func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback && session.category != .playAndRecord {
            try? session.setCategory(.playback, mode: .default)
        }
        try? session.setActive(true)
    }
}

extension CMTime {
    var finiteSeconds: Double {
        let value = seconds
        return value.isFinite ? max(0, value) : 0
    }
}
