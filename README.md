# KitoMediaPlayer

**[Documentation](https://wyksofts-inc.github.io/KitoMediaPlayer/documentation/kitomediaplayer/)**

Video and audio players for SwiftUI, with custom chrome on top of `AVPlayer`. The video player has
four styles, from cinema to Reels. The audio player has a mini player that expands into a full
"now playing" screen. There are waveforms, podcast chapters, a sleep timer and lock-screen
controls. Part of the [Kito](https://github.com/WykSofts-Inc/KitoDevKit) ecosystem.

## Video

```swift
KitoVideoPlayer(
    url: videoURL,
    chapters: [KitoChapter("Intro", start: 0), KitoChapter("Demo", start: 95)],
    style: .cinema,            // .minimal, .social, .inline
    title: "Keynote",
    subtitle: "Day one"
)
.aspectRatio(16 / 9, contentMode: .fit)
```

- **Tap** shows the controls, which hide after three seconds while playing. **Double-tap** the left
  or right third to seek ±10s, with a ripple and a running "20 seconds" label.
- The **scrubber** shows the buffered range, chapter gaps and a time bubble with the chapter name
  while you drag. VoiceOver can swipe up or down on it to seek.
- **Speed menu** (0.5×–2×), **mute**, **Picture in Picture** (when the device supports it),
  **fullscreen** (rotates to landscape for wide videos if your app allows landscape) and **loop**.
- A **poster** shows before playback: yours, a frame grabbed from file-based media, or a
  generated backdrop. A spinner appears while buffering, and errors show **Try again**.

Styles: `.cinema` (full chrome), `.minimal` (play button and slim scrubber), `.social` (vertical,
edge-to-edge: tap to pause, double-tap to like, side actions and a thin progress line) and
`.inline` (a card with controls below the picture).

```swift
KitoVideoPlayer(url: reelURL, loops: true, style: .social, title: "@kito.studio", subtitle: caption,
                actions: [.like(count: 12_400) { liked in … }, .comments(count: 318) { … }, .save(), .share { … }])
```

Keep a `KitoVideoPlayerModel` yourself when something else needs to control the video:

```swift
@State private var player = KitoVideoPlayerModel(url: videoURL, chapters: chapters)

KitoVideoPlayer(model: player, style: .minimal)
KitoChapterList(model: player)
KitoPlaybackRateChip(model: player)
Button("Skip intro") { player.seek(to: 95) }
```

To build your own controls, use `KitoVideoSurface(model:gravity:)` (call `player.prepare()`) and read
`isPlaying`, `currentTime`, `duration`, `bufferedTime`, `progress` and `currentChapter`.

## Audio

```swift
@State private var player = KitoAudioPlayerModel(tracks: [
    KitoAudioTrack(title: "Sunrise Drive", artist: "Kito Ensemble", url: fileURL,
                   artwork: .image(cover))   // or .remote(url), .gradient(colors, systemImage:)
], systemControls: true)

LibraryView()
    .kitoMiniPlayer(player)                  // a floating bar that expands into the full player

KitoAudioPlayer(model: player, artworkStyle: .vinyl)   // or on its own; .card by default
```

The full player has artwork that breathes while playing (or a spinning record), title and artist,
a waveform scrubber, ±15s, previous and next, repeat (off, all, one), shuffle, a speed chip, a sleep
timer and an Up Next or Chapters panel. The mini player expands with matched geometry. Swipe down to
close it again.

Queue rules: **Previous** restarts the track after three seconds. **Next** at the end stops (repeat
off) or wraps. Repeat one only replays when a track finishes by itself. Shuffle keeps the current
track playing.

```swift
player.next(); player.previous(); player.skip(by: 15)
player.cycleRepeatMode(); player.toggleShuffle(); player.setRate(1.5)
player.startSleepTimer(.minutes(15))     // or .endOfTrack; fades out over the last five seconds
KitoSleepTimerMenu(model: player)
```

**Lock screen and Control Center** are opt-in. Pass `systemControls: true` or call
`enableSystemControls()` to publish Now Playing info (title, artist, artwork, elapsed time, rate)
and handle play, pause, skip, previous and next, scrubbing and speed commands. Only one model owns
the controls at a time.

## Waveforms

```swift
let peaks = try await KitoWaveformAnalyzer.peaks(of: fileURL, count: 96)   // AVAssetReader, off the main thread
KitoWaveformView(samples: peaks, progress: progress, duration: duration, tint: .pink) { fraction in
    player.seek(to: fraction * duration)
}
KitoWaveformAnalyzer.placeholder(count: 80, seed: episode.id)   // deterministic bars for streams
```

The audio model analyses local files for you (`player.waveform`) and uses the placeholder for
remote ones.

## Chapters and speed

```swift
KitoChapterList(model: player)                 // live progress fill, tap to jump
KitoPlaybackRateChip(rate: $rate)               // tap to step, press and hold to pick
KitoMediaTime.string(3723)                      // "1:02:03"
KitoMediaTime.remainingString(currentTime: 10, duration: 202)   // "-3:12"
```

## Sample media

`KitoSampleMedia.videoURL` is Apple's public HLS test stream, which needs a network connection.
`KitoSampleAudio.makeFile(.sunrise)` renders a 30-second synth piece into a cached temporary file,
and `KitoSampleAudio.playlist()` gives you four ready-made tracks. Both audio helpers work offline.

## App setup

- **Background audio, lock-screen playback and Picture in Picture:** add the `audio` background
  mode (`UIBackgroundModes` → `audio`, "Audio, AirPlay, and Picture in Picture" in Signing &
  Capabilities).
- **Landscape fullscreen:** include the landscape orientations in `UISupportedInterfaceOrientations`.
- **Remote media over plain HTTP:** needs an App Transport Security exception. HTTPS works as is.
- On first play, the players switch the audio session to `.playback` so sound plays with the silent
  switch on. If your app already chose a category, it's left alone.

## Installation

```swift
.package(url: "https://github.com/WykSofts-Inc/KitoMediaPlayer.git", from: "0.1.0")
```

## License

MIT — see [LICENSE](LICENSE).
