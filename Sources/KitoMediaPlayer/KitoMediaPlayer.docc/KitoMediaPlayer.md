# ``KitoMediaPlayer``

Video and audio players for SwiftUI with custom chrome on top of AVPlayer.

## Overview

``KitoVideoPlayer`` offers four styles, from full cinema chrome to vertical,
edge-to-edge Reels-style playback. It supports tap-to-show controls,
double-tap seeking, a scrubber with buffered range and chapter gaps, playback
speed, mute, Picture in Picture, fullscreen, and looping.

```swift
KitoVideoPlayer(
    url: videoURL,
    chapters: [KitoChapter("Intro", start: 0), KitoChapter("Demo", start: 95)],
    style: .cinema,
    title: "Keynote",
    subtitle: "Day one"
)
.aspectRatio(16 / 9, contentMode: .fit)
```

Keep a ``KitoVideoPlayerModel`` yourself when something else needs to control
the video, or pair it with ``KitoVideoSurface`` to build your own controls.

For audio, ``KitoAudioPlayerModel`` manages a queue of ``KitoAudioTrack``
values with repeat, shuffle, playback speed, and a sleep timer.
``KitoAudioPlayer`` is the full "now playing" screen, and the
`kitoMiniPlayer(_:isExpanded:artworkStyle:tint:)` modifier adds a floating bar
that expands into it. Lock screen and Control Center integration is opt-in.

Supporting components include waveforms (``KitoWaveformView`` and
``KitoWaveformAnalyzer``), a chapter list, a playback-rate chip, and a sleep
timer menu. For background audio and Picture in Picture, add the `audio`
background mode to your app.

## Topics

### Video

- ``KitoVideoPlayer``
- ``KitoVideoPlayerModel``
- ``KitoVideoPlayerStyle``
- ``KitoVideoAction``
- ``KitoVideoSurface``

### Audio

- ``KitoAudioPlayer``
- ``KitoMiniPlayer``
- ``KitoAudioPlayerModel``
- ``KitoAudioTrack``
- ``KitoArtwork``
- ``KitoArtworkStyle``
- ``KitoArtworkView``

### Queue and Sleep Timer

- ``KitoPlaybackQueue``
- ``KitoRepeatMode``
- ``KitoSleepTimer``
- ``KitoSleepTimerMenu``

### Chapters and Speed

- ``KitoChapter``
- ``KitoChapterList``
- ``KitoPlaybackRateChip``
- ``KitoPlaybackRate``

### Waveforms

- ``KitoWaveformView``
- ``KitoWaveformAnalyzer``
- ``KitoWaveformError``

### Utilities

- ``KitoMediaTime``
- ``KitoTapZone``
- ``KitoMediaSession``
- ``KitoSampleMedia``
- ``KitoSampleAudio``
