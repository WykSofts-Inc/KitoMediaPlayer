//
//  KitoMediaPlayerTests.swift
//  KitoMediaPlayer
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoMediaPlayer

final class KitoMediaTimeTests: XCTestCase {
    func testFormatsMinutesAndHours() {
        XCTAssertEqual(KitoMediaTime.string(0), "0:00")
        XCTAssertEqual(KitoMediaTime.string(7), "0:07")
        XCTAssertEqual(KitoMediaTime.string(59.9), "0:59")
        XCTAssertEqual(KitoMediaTime.string(62), "1:02")
        XCTAssertEqual(KitoMediaTime.string(600), "10:00")
        XCTAssertEqual(KitoMediaTime.string(3723), "1:02:03")
        XCTAssertEqual(KitoMediaTime.string(36_000), "10:00:00")
    }

    func testInvalidTimesReadZero() {
        XCTAssertEqual(KitoMediaTime.string(-4), "0:00")
        XCTAssertEqual(KitoMediaTime.string(.nan), "0:00")
        XCTAssertEqual(KitoMediaTime.string(.infinity), "0:00")
    }

    func testRemainingString() {
        XCTAssertEqual(KitoMediaTime.remainingString(currentTime: 10, duration: 202), "-3:12")
        XCTAssertEqual(KitoMediaTime.remainingString(currentTime: 300, duration: 202), "-0:00")
        XCTAssertEqual(KitoMediaTime.remainingString(currentTime: 0.4, duration: 10), "-0:10")
    }

    func testSpokenDuration() {
        XCTAssertFalse(KitoMediaTime.spoken(62).isEmpty)
        XCTAssertNotEqual(KitoMediaTime.spoken(62), KitoMediaTime.spoken(3))
    }

    func testSeekClamping() {
        XCTAssertEqual(KitoMediaTime.clamped(-5, duration: 600), 0)
        XCTAssertEqual(KitoMediaTime.clamped(700, duration: 600), 600)
        XCTAssertEqual(KitoMediaTime.clamped(42, duration: 600), 42)
        XCTAssertEqual(KitoMediaTime.clamped(.nan, duration: 600), 0)
        // Unknown duration only clamps at zero.
        XCTAssertEqual(KitoMediaTime.clamped(30, duration: 0), 30)
        XCTAssertEqual(KitoMediaTime.clamped(30, duration: .nan), 30)
        XCTAssertEqual(KitoMediaTime.clamped(-1, duration: .infinity), 0)
    }

    func testProgress() {
        XCTAssertEqual(KitoMediaTime.progress(30, duration: 120), 0.25)
        XCTAssertEqual(KitoMediaTime.progress(30, duration: 0), 0)
        XCTAssertEqual(KitoMediaTime.progress(500, duration: 120), 1)
        XCTAssertEqual(KitoMediaTime.progress(-1, duration: 120), 0)
    }
}

final class KitoTapZoneTests: XCTestCase {
    func testZones() {
        XCTAssertEqual(KitoTapZone.zone(atX: 10, width: 300), .backward)
        XCTAssertEqual(KitoTapZone.zone(atX: 150, width: 300), .center)
        XCTAssertEqual(KitoTapZone.zone(atX: 290, width: 300), .forward)
    }

    func testBoundariesAndEdgeCases() {
        XCTAssertEqual(KitoTapZone.zone(atX: 104, width: 300), .backward)
        XCTAssertEqual(KitoTapZone.zone(atX: 106, width: 300), .center)
        XCTAssertEqual(KitoTapZone.zone(atX: 196, width: 300), .forward)
        XCTAssertEqual(KitoTapZone.zone(atX: -20, width: 300), .backward)
        XCTAssertEqual(KitoTapZone.zone(atX: 999, width: 300), .forward)
        XCTAssertEqual(KitoTapZone.zone(atX: 50, width: 0), .center)
        XCTAssertEqual(KitoTapZone.zone(atX: 140, width: 300, sideFraction: 0.5), .backward)
    }

    func testSeekOffsets() {
        XCTAssertEqual(KitoTapZone.backward.seekOffset(), -10)
        XCTAssertEqual(KitoTapZone.forward.seekOffset(), 10)
        XCTAssertEqual(KitoTapZone.center.seekOffset(), 0)
        XCTAssertEqual(KitoTapZone.forward.seekOffset(step: 15), 15)
    }
}

final class KitoPlaybackRateTests: XCTestCase {
    func testNextRateWraps() {
        XCTAssertEqual(KitoPlaybackRate.next(after: 1), 1.25)
        XCTAssertEqual(KitoPlaybackRate.next(after: 2), 0.5)
        XCTAssertEqual(KitoPlaybackRate.next(after: 1.1), 1.25)
        XCTAssertEqual(KitoPlaybackRate.next(after: 5), 0.5)
        XCTAssertEqual(KitoPlaybackRate.next(after: 1, in: []), 1)
    }

    func testLabels() {
        XCTAssertTrue(KitoPlaybackRate.label(1).hasSuffix("×"))
        XCTAssertEqual(KitoPlaybackRate.label(1), "1×")
        XCTAssertEqual(KitoPlaybackRate.label(2), "2×")
    }
}

final class KitoChapterTests: XCTestCase {
    let chapters = [
        KitoChapter("Intro", start: 0),
        KitoChapter("Guest", start: 90),
        KitoChapter("Q&A", start: 300),
    ]

    func testLookup() {
        XCTAssertEqual(KitoChapter.index(at: 0, in: chapters), 0)
        XCTAssertEqual(KitoChapter.index(at: 89.9, in: chapters), 0)
        XCTAssertEqual(KitoChapter.index(at: 90, in: chapters), 1)
        XCTAssertEqual(KitoChapter.index(at: 1_000, in: chapters), 2)
        XCTAssertNil(KitoChapter.index(at: 5, in: []))
        XCTAssertNil(KitoChapter.index(at: 5, in: [KitoChapter("Late", start: 10)]))
    }

    func testLookupIgnoresOrder() {
        let shuffled = [chapters[2], chapters[0], chapters[1]]
        XCTAssertEqual(KitoChapter.index(at: 120, in: shuffled).map { shuffled[$0].title }, "Guest")
    }

    func testRanges() {
        XCTAssertEqual(KitoChapter.range(of: 0, in: chapters, duration: 600), 0...90)
        XCTAssertEqual(KitoChapter.range(of: 2, in: chapters, duration: 600), 300...600)
        XCTAssertNil(KitoChapter.range(of: 3, in: chapters, duration: 600))
    }

    func testMarkers() {
        XCTAssertEqual(KitoChapter.markers(chapters, duration: 600), [0.15, 0.5])
        XCTAssertEqual(KitoChapter.markers(chapters, duration: 200), [0.45])
        XCTAssertEqual(KitoChapter.markers(chapters, duration: 0), [])
    }

    func testNegativeStartClamps() {
        XCTAssertEqual(KitoChapter("Pre-roll", start: -3).start, 0)
    }
}

final class KitoPlaybackQueueTests: XCTestCase {
    func testAdvanceStopsAtEndWithRepeatOff() {
        var queue = KitoPlaybackQueue(["a", "b", "c"])
        XCTAssertEqual(queue.current, "a")
        XCTAssertEqual(queue.advance(), "b")
        XCTAssertEqual(queue.advance(), "c")
        XCTAssertNil(queue.advance())
        XCTAssertEqual(queue.current, "c")
        XCTAssertFalse(queue.hasNext)
    }

    func testRepeatAllWraps() {
        var queue = KitoPlaybackQueue(["a", "b"], startAt: 1)
        queue.repeatMode = .all
        XCTAssertTrue(queue.hasNext)
        XCTAssertEqual(queue.advance(), "a")
        XCTAssertEqual(queue.retreat(), "b")
    }

    func testRepeatOneReplaysOnlyAutomatically() {
        var queue = KitoPlaybackQueue(["a", "b", "c"])
        queue.repeatMode = .one
        XCTAssertEqual(queue.advance(automatically: true), "a")
        XCTAssertEqual(queue.advance(automatically: true), "a")
        XCTAssertEqual(queue.advance(), "b")
        queue.jump(to: 2)
        XCTAssertEqual(queue.advance(), "a", "Skipping at the end with repeat one wraps")
    }

    func testRetreatStaysOnFirstWithRepeatOff() {
        var queue = KitoPlaybackQueue(["a", "b"])
        XCTAssertFalse(queue.hasPrevious)
        XCTAssertEqual(queue.retreat(), "a")
        queue.advance()
        XCTAssertTrue(queue.hasPrevious)
        XCTAssertEqual(queue.retreat(), "a")
    }

    func testJumpAndUpNext() {
        var queue = KitoPlaybackQueue(["a", "b", "c", "d"])
        queue.jump(to: 2)
        XCTAssertEqual(queue.current, "c")
        XCTAssertEqual(queue.upNext, ["d"])
        queue.jump(to: 42)
        XCTAssertEqual(queue.current, "c")
    }

    func testShuffleKeepsCurrentFirstAndEveryItem() {
        var queue = KitoPlaybackQueue(Array(0..<10), startAt: 4)
        var generator = SeededGenerator(seed: 7)
        queue.setShuffled(true, using: &generator)
        XCTAssertTrue(queue.isShuffled)
        XCTAssertEqual(queue.current, 4)
        XCTAssertEqual(queue.order.first, 4)
        XCTAssertEqual(Set(queue.order), Set(0..<10))
        XCTAssertEqual(queue.upNext.count, 9)
    }

    func testShuffleIsDeterministicWithASeed() {
        var first = KitoPlaybackQueue(Array(0..<12))
        var second = KitoPlaybackQueue(Array(0..<12))
        var a = SeededGenerator(seed: 99), b = SeededGenerator(seed: 99)
        first.setShuffled(true, using: &a)
        second.setShuffled(true, using: &b)
        XCTAssertEqual(first.order, second.order)
        XCTAssertNotEqual(first.order, Array(0..<12))
    }

    func testUnshuffleRestoresNaturalOrderAtCurrentItem() {
        var queue = KitoPlaybackQueue(["a", "b", "c", "d"])
        var generator = SeededGenerator(seed: 3)
        queue.setShuffled(true, using: &generator)
        queue.advance()
        let playing = queue.current
        queue.setShuffled(false)
        XCTAssertFalse(queue.isShuffled)
        XCTAssertEqual(queue.order, [0, 1, 2, 3])
        XCTAssertEqual(queue.current, playing)
    }

    func testEmptyQueue() {
        var queue = KitoPlaybackQueue<String>([])
        XCTAssertNil(queue.current)
        XCTAssertNil(queue.advance())
        XCTAssertNil(queue.retreat())
        XCTAssertFalse(queue.hasNext)
        queue.setShuffled(true)
        XCTAssertTrue(queue.upNext.isEmpty)
    }

    func testReplaceResetsShuffle() {
        var queue = KitoPlaybackQueue(["a", "b"])
        queue.setShuffled(true)
        queue.replace(with: ["x", "y", "z"], startAt: 2)
        XCTAssertFalse(queue.isShuffled)
        XCTAssertEqual(queue.current, "z")
    }

    func testRepeatModeCycle() {
        XCTAssertEqual(KitoRepeatMode.off.next, .all)
        XCTAssertEqual(KitoRepeatMode.all.next, .one)
        XCTAssertEqual(KitoRepeatMode.one.next, .off)
    }

    func testPreviousRestartsAfterThreeSeconds() {
        XCTAssertFalse(KitoPlaybackQueue<Int>.restartsOnPrevious(elapsed: 2.5))
        XCTAssertTrue(KitoPlaybackQueue<Int>.restartsOnPrevious(elapsed: 3.5))
    }
}

final class KitoWaveformTests: XCTestCase {
    func testDownsampleTakesPeaksPerBucket() {
        let peaks = KitoWaveformAnalyzer.downsample([0, 1, 0, -0.5], into: 2)
        XCTAssertEqual(peaks, [1, 0.5])
    }

    func testDownsampleWithoutNormalising() {
        let peaks = KitoWaveformAnalyzer.downsample([0.1, 0.2, -0.4, 0.3, 0.05, 0.1], into: 3, normalize: false)
        XCTAssertEqual(peaks, [0.2, 0.4, 0.1])
    }

    func testDownsampleAlwaysReturnsCount() {
        XCTAssertEqual(KitoWaveformAnalyzer.downsample(Array(repeating: 0.5, count: 1_000), into: 64).count, 64)
        XCTAssertEqual(KitoWaveformAnalyzer.downsample([0.5, 1], into: 6).count, 6)
        XCTAssertEqual(KitoWaveformAnalyzer.downsample([], into: 8), Array(repeating: 0, count: 8))
        XCTAssertEqual(KitoWaveformAnalyzer.downsample([1], into: 0), [])
    }

    func testDownsampleIgnoresNonFiniteValues() {
        let peaks = KitoWaveformAnalyzer.downsample([.nan, 0.5, .infinity, 0.25], into: 2)
        XCTAssertEqual(peaks, [1, 0.5])
    }

    func testPlaceholderIsDeterministicAndInRange() {
        let a = KitoWaveformAnalyzer.placeholder(count: 80, seed: "episode-42")
        let b = KitoWaveformAnalyzer.placeholder(count: 80, seed: "episode-42")
        let c = KitoWaveformAnalyzer.placeholder(count: 80, seed: "episode-43")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.count, 80)
        XCTAssertTrue(a.allSatisfy { $0 >= 0.08 && $0 <= 1 })
        XCTAssertEqual(KitoWaveformAnalyzer.placeholder(count: 0, seed: "x"), [])
    }

    func testStableHashIsFNV1a() {
        XCTAssertEqual(KitoWaveformAnalyzer.stableHash(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(KitoWaveformAnalyzer.stableHash("a"), 0xaf63_dc4c_8601_ec8c)
    }

    func testAnalysesGeneratedAudio() async throws {
        let url = try KitoSampleAudio.makeFile(.ember, duration: 4)
        XCTAssertEqual(try KitoSampleAudio.makeFile(.ember, duration: 4), url, "Generated files are cached")
        let peaks = try await KitoWaveformAnalyzer.peaks(of: url, count: 48)
        XCTAssertEqual(peaks.count, 48)
        XCTAssertEqual(peaks.max() ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue(peaks.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertLessThan(peaks.first ?? 1, 0.9, "The piece fades in")
    }

    func testAnalysingAMissingFileThrows() async {
        do {
            _ = try await KitoWaveformAnalyzer.peaks(of: URL(fileURLWithPath: "/nonexistent/file.caf"))
            XCTFail("Expected an error")
        } catch {}
    }
}

final class KitoSleepTimerTests: XCTestCase {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func testCountdown() {
        let timer = KitoSleepTimer(.minutes(5), startedAt: start)
        XCTAssertEqual(timer.remaining(at: start), 300)
        XCTAssertEqual(timer.remaining(at: start + 60), 240)
        XCTAssertEqual(timer.label(at: start + 60), "4:00")
        XCTAssertFalse(timer.isExpired(at: start + 299))
        XCTAssertTrue(timer.isExpired(at: start + 300))
        XCTAssertEqual(timer.remaining(at: start + 900), 0)
    }

    func testFadesOverTheLastSeconds() {
        let timer = KitoSleepTimer(.duration(60), startedAt: start)
        XCTAssertEqual(timer.volume(at: start + 10), 1)
        XCTAssertEqual(timer.volume(at: start + 57.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(timer.volume(at: start + 60), 0)
    }

    func testEndOfTrackNeverExpiresByTime() {
        let timer = KitoSleepTimer(.endOfTrack, startedAt: start)
        XCTAssertNil(timer.remaining(at: start + 10_000))
        XCTAssertFalse(timer.isExpired(at: start + 10_000))
        XCTAssertEqual(timer.volume(at: start + 10_000), 1)
        XCTAssertEqual(timer.label(), "End of track")
        XCTAssertNil(timer.endsAt)
    }

    func testModeTitles() {
        XCTAssertEqual(KitoSleepTimer.Mode.minutes(15), .duration(900))
        XCTAssertEqual(KitoSleepTimer.Mode.endOfTrack.title, "End of track")
        XCTAssertTrue(KitoSleepTimer.Mode.minutes(15).title.contains("15"))
        XCTAssertEqual(KitoSleepTimer.Mode.presets.last, .endOfTrack)
    }
}

@MainActor
final class KitoAudioPlayerModelTests: XCTestCase {
    private func tracks() -> [KitoAudioTrack] {
        ["one", "two", "three"].map {
            KitoAudioTrack(id: $0, title: $0.capitalized, artist: "Tester", url: URL(fileURLWithPath: "/tmp/\($0).caf"))
        }
    }

    func testNextAndPreviousMoveThroughTheQueue() {
        let model = KitoAudioPlayerModel(tracks: tracks())
        XCTAssertEqual(model.currentTrack?.id, "one")
        model.next()
        XCTAssertEqual(model.currentTrack?.id, "two")
        model.previous()
        XCTAssertEqual(model.currentTrack?.id, "one")
        XCTAssertFalse(model.waveform.isEmpty, "A placeholder waveform shows straight away")
    }

    func testNextAtTheEndReturnsToTheFirstTrack() {
        let model = KitoAudioPlayerModel(tracks: tracks(), startAt: 2)
        model.next()
        XCTAssertEqual(model.currentTrack?.id, "one")
        XCTAssertFalse(model.isPlaying)
    }

    func testRepeatShuffleAndRate() {
        let model = KitoAudioPlayerModel(tracks: tracks())
        model.cycleRepeatMode()
        XCTAssertEqual(model.repeatMode, .all)
        model.toggleShuffle()
        XCTAssertTrue(model.isShuffled)
        XCTAssertEqual(model.currentTrack?.id, "one")
        model.setRate(9)
        XCTAssertEqual(model.rate, 3)
    }

    func testSleepTimerStartsAndCancels() {
        let model = KitoAudioPlayerModel(tracks: tracks())
        model.startSleepTimer(.minutes(15))
        XCTAssertEqual(model.sleepTimerLabel, "15:00")
        model.cancelSleepTimer()
        XCTAssertNil(model.sleepTimer)
        XCTAssertNil(model.sleepTimerLabel)
    }
}

@MainActor
final class KitoVideoPlayerModelTests: XCTestCase {
    func testChaptersAreSortedAndLookedUp() {
        let model = KitoVideoPlayerModel(url: KitoSampleMedia.videoURL, chapters: [
            KitoChapter("B", start: 60), KitoChapter("A", start: 0),
        ])
        XCTAssertEqual(model.chapters.map(\.title), ["A", "B"])
        XCTAssertEqual(model.currentChapter?.title, "A")
        XCTAssertEqual(model.status, .idle)
        XCTAssertNil(model.failureMessage)
    }

    func testRateAndMute() {
        let model = KitoVideoPlayerModel(url: KitoSampleMedia.videoURL, isMuted: true)
        XCTAssertTrue(model.isMuted)
        model.toggleMuted()
        XCTAssertFalse(model.isMuted)
        model.setRate(0.1)
        XCTAssertEqual(model.rate, 0.25)
    }
}
