//
//  KitoMediaTime.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation
import CoreGraphics

/// Time helpers shared by every player: labels, spoken values and safe seeking.
public enum KitoMediaTime {
    /// `7` → "0:07", `62` → "1:02", `3723` → "1:02:03". Invalid or negative input reads "0:00".
    public static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Time left, with a leading minus: "-3:12".
    public static func remainingString(currentTime: Double, duration: Double) -> String {
        let left = max(0, sanitized(duration) - sanitized(currentTime))
        return "-" + string(left.rounded(.up))
    }

    /// A VoiceOver-friendly duration: "1 minute, 2 seconds".
    public static func spoken(_ seconds: Double) -> String {
        let value = Int(sanitized(seconds).rounded(.down))
        return Duration.seconds(value).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// Keeps a seek target inside `0…duration`. An unknown duration (0, NaN, ∞) only clamps at zero.
    public static func clamped(_ time: Double, duration: Double) -> Double {
        let time = sanitized(time)
        let duration = sanitized(duration)
        guard duration > 0 else { return time }
        return min(max(0, time), duration)
    }

    /// `currentTime / duration` in `0…1`, or 0 while the duration is unknown.
    public static func progress(_ time: Double, duration: Double) -> Double {
        let duration = sanitized(duration)
        guard duration > 0 else { return 0 }
        return min(max(0, sanitized(time) / duration), 1)
    }

    static func sanitized(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}

/// Which third of a player a tap landed in, for double-tap seeking.
public enum KitoTapZone: Equatable, Sendable {
    case backward, center, forward

    /// The zone for a tap at `x` in a view `width` points wide. `sideFraction` is how much of
    /// each edge counts as a seek zone (35% by default, like most video apps).
    public static func zone(atX x: CGFloat, width: CGFloat, sideFraction: CGFloat = 0.35) -> KitoTapZone {
        guard width > 0 else { return .center }
        let fraction = min(max(0, x / width), 1)
        let side = min(max(0, sideFraction), 0.5)
        if fraction < side { return .backward }
        if fraction > 1 - side { return .forward }
        return .center
    }

    /// Seconds to seek for one tap in this zone.
    public func seekOffset(step: Double = 10) -> Double {
        switch self {
        case .backward: return -step
        case .forward: return step
        case .center: return 0
        }
    }
}

/// Playback speeds offered by the speed menu and the rate chip.
public enum KitoPlaybackRate {
    /// 0.5×, 0.75×, 1×, 1.25×, 1.5× and 2×.
    public static let standard: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    /// "1×", "1.5×", "0.75×".
    public static func label(_ rate: Float) -> String {
        let text = rate.formatted(.number.precision(.fractionLength(0...2)))
        return text + "×"
    }

    /// The rate after `rate` in `rates`, wrapping to the first.
    public static func next(after rate: Float, in rates: [Float] = standard) -> Float {
        guard let first = rates.first else { return rate }
        guard let index = rates.firstIndex(where: { abs($0 - rate) < 0.001 }) else {
            return rates.first(where: { $0 > rate }) ?? first
        }
        return rates.indices.contains(index + 1) ? rates[index + 1] : first
    }
}
