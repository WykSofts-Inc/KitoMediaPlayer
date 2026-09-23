//
//  KitoSleepTimer.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// A sleep timer's countdown. Playback fades out over the last few seconds and then pauses.
public struct KitoSleepTimer: Equatable, Sendable {
    public enum Mode: Hashable, Sendable {
        /// Stop after this many seconds.
        case duration(TimeInterval)
        /// Stop when the current track or episode finishes.
        case endOfTrack

        public static func minutes(_ minutes: Double) -> Mode { .duration(minutes * 60) }

        /// "15 minutes", "1 hour", "End of track".
        public var title: String {
            switch self {
            case .endOfTrack:
                return "End of track"
            case .duration(let seconds):
                return Duration.seconds(Int(seconds)).formatted(.units(allowed: [.hours, .minutes], width: .wide))
            }
        }

        /// The options a sleep-timer menu usually offers.
        public static let presets: [Mode] = [.minutes(5), .minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfTrack]
    }

    public let mode: Mode
    public let startedAt: Date
    /// Seconds of volume fade before the timer ends.
    public var fadeDuration: TimeInterval = 5

    public init(_ mode: Mode, startedAt: Date = .now) {
        self.mode = mode
        self.startedAt = startedAt
    }

    /// When a duration timer ends; `nil` for end of track.
    public var endsAt: Date? {
        guard case .duration(let seconds) = mode else { return nil }
        return startedAt.addingTimeInterval(max(0, seconds))
    }

    /// Seconds left, never negative; `nil` for end of track.
    public func remaining(at now: Date = .now) -> TimeInterval? {
        endsAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    public func isExpired(at now: Date = .now) -> Bool {
        remaining(at: now).map { $0 <= 0 } ?? false
    }

    /// Volume multiplier: 1 until the last `fadeDuration` seconds, then easing down to 0.
    public func volume(at now: Date = .now) -> Float {
        guard let remaining = remaining(at: now), fadeDuration > 0 else { return 1 }
        return Float(min(1, max(0, remaining / fadeDuration)))
    }

    /// "14:32" left, or "End of track".
    public func label(at now: Date = .now) -> String {
        guard let remaining = remaining(at: now) else { return Mode.endOfTrack.title }
        return KitoMediaTime.string(remaining.rounded(.up))
    }
}
