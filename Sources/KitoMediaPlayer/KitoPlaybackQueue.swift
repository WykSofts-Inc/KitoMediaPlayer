//
//  KitoPlaybackQueue.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// Repeat behaviour for a queue.
public enum KitoRepeatMode: String, CaseIterable, Sendable {
    case off, all, one

    /// Off → all → one → off, the order a repeat button cycles through.
    public var next: KitoRepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var systemImage: String { self == .one ? "repeat.1" : "repeat" }

    var accessibilityValue: String {
        switch self {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }
}

/// An ordered play queue with repeat and shuffle. Pure value logic, so the rules are the same
/// whichever player drives it:
///
/// - **Next** at the end stops (repeat off) or wraps (repeat all or one). Repeat one only
///   replays the track when it finishes by itself.
/// - **Previous** at the start wraps with repeat on, otherwise stays on the first item.
/// - **Shuffle** keeps the current item playing and shuffles everything after it.
public struct KitoPlaybackQueue<Item> {
    public private(set) var items: [Item]
    /// Indices into `items`, in play order.
    public private(set) var order: [Int]
    /// Position in `order` of the current item.
    public private(set) var position: Int
    public var repeatMode: KitoRepeatMode = .off
    public private(set) var isShuffled = false

    public init(_ items: [Item], startAt index: Int = 0) {
        self.items = items
        self.order = Array(items.indices)
        self.position = items.indices.contains(index) ? index : 0
    }

    /// Index into `items` of the current item.
    public var currentIndex: Int? { order.indices.contains(position) ? order[position] : nil }
    public var current: Item? { currentIndex.map { items[$0] } }
    /// Items that will play after the current one, in order.
    public var upNext: [Item] {
        guard order.indices.contains(position) else { return [] }
        return order[(position + 1)...].map { items[$0] }
    }
    public var isEmpty: Bool { items.isEmpty }
    public var hasNext: Bool { !items.isEmpty && (position < order.count - 1 || repeatMode != .off) }
    public var hasPrevious: Bool { !items.isEmpty && (position > 0 || repeatMode != .off) }

    /// Moves forward and returns the new current item, or `nil` when the queue has ended.
    /// Pass `automatically: true` when the previous item finished playing by itself.
    @discardableResult
    public mutating func advance(automatically: Bool = false) -> Item? {
        guard !items.isEmpty else { return nil }
        if automatically && repeatMode == .one { return current }
        if position < order.count - 1 {
            position += 1
        } else if repeatMode == .off {
            return nil
        } else {
            position = 0
        }
        return current
    }

    /// Moves back and returns the new current item.
    @discardableResult
    public mutating func retreat() -> Item? {
        guard !items.isEmpty else { return nil }
        if position > 0 {
            position -= 1
        } else if repeatMode != .off {
            position = order.count - 1
        }
        return current
    }

    /// Makes `items[index]` current without changing the order.
    public mutating func jump(to index: Int) {
        guard let target = order.firstIndex(of: index) else { return }
        position = target
    }

    /// Turns shuffle on or off with a custom generator (handy for deterministic tests).
    public mutating func setShuffled<G: RandomNumberGenerator>(_ shuffled: Bool, using generator: inout G) {
        guard let current = currentIndex else { isShuffled = shuffled; return }
        if shuffled {
            var rest = items.indices.filter { $0 != current }
            rest.shuffle(using: &generator)
            order = [current] + rest
            position = 0
        } else {
            order = Array(items.indices)
            position = current
        }
        isShuffled = shuffled
    }

    public mutating func setShuffled(_ shuffled: Bool) {
        var generator = SystemRandomNumberGenerator()
        setShuffled(shuffled, using: &generator)
    }

    /// Replaces the items and starts at `index`. Shuffle turns off.
    public mutating func replace(with items: [Item], startAt index: Int = 0) {
        self.items = items
        order = Array(items.indices)
        position = items.indices.contains(index) ? index : 0
        isShuffled = false
    }

    /// "Previous" restarts the current item when more than `threshold` seconds have played,
    /// the way music apps do.
    public static func restartsOnPrevious(elapsed: TimeInterval, threshold: TimeInterval = 3) -> Bool {
        elapsed > threshold
    }
}

extension KitoPlaybackQueue: Sendable where Item: Sendable {}
extension KitoPlaybackQueue: Equatable where Item: Equatable {}
