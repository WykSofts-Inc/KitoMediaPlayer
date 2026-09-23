//
//  KitoChapter.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// A named point in a video or episode. Chapters show as gaps on the scrubber, in the time
/// bubble while dragging, and as rows in `KitoChapterList`.
public struct KitoChapter: Identifiable, Hashable, Sendable {
    public var title: String
    /// Seconds from the start of the media.
    public var start: TimeInterval
    /// An optional SF Symbol shown in chapter lists.
    public var systemImage: String?

    public var id: String { "\(start)|\(title)" }

    public init(_ title: String, start: TimeInterval, systemImage: String? = nil) {
        self.title = title
        self.start = max(0, start)
        self.systemImage = systemImage
    }

    /// The chapter playing at `time`: the one with the latest start at or before it.
    /// `nil` when the list is empty or `time` falls before the first chapter.
    public static func index(at time: TimeInterval, in chapters: [KitoChapter]) -> Int? {
        var best: Int?
        for (index, chapter) in chapters.enumerated() where chapter.start <= time {
            if let current = best, chapters[current].start > chapter.start { continue }
            best = index
        }
        return best
    }

    /// Where chapter `index` starts and ends. The last chapter runs to `duration`.
    public static func range(of index: Int, in chapters: [KitoChapter], duration: TimeInterval) -> ClosedRange<TimeInterval>? {
        guard chapters.indices.contains(index) else { return nil }
        let sorted = chapters.map(\.start).sorted()
        let start = chapters[index].start
        let end = sorted.first(where: { $0 > start }) ?? max(duration, start)
        return start...max(start, end)
    }

    /// Chapter boundaries as fractions of `duration`, skipping zero and anything past the end.
    public static func markers(_ chapters: [KitoChapter], duration: TimeInterval) -> [Double] {
        guard duration > 0, duration.isFinite else { return [] }
        return Set(chapters.map(\.start))
            .filter { $0 > 0 && $0 < duration }
            .sorted()
            .map { $0 / duration }
    }
}
