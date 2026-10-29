// StudioModel+Playback.swift
// Brim
//
// Live playback: an AVPlayer over the edited composition, rendered by the same custom compositor
// the export uses, at preview resolution. While paused the editor shows a still render instead,
// which redraws instantly as the look changes.

import AVFoundation
import Foundation

extension StudioModel {
    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        if playhead >= duration - 0.05 { playhead = 0 }
        isPlaying = true
        Task { await rebuildPlayerItem(andPlay: true) }
    }

    func pause() {
        player.pause()
        isPlaying = false
        refreshStill()
    }

    /// Moves the playhead (output seconds); scrubbing while playing seeks the player.
    func seek(to time: Double) {
        playhead = min(max(0, time), duration)
        if isPlaying {
            player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            refreshStill()
        }
    }

    /// Jumps to the previous / next cut (or the start / end).
    func step(forward: Bool) {
        let marks = ([0, duration] + edit.timeline.clipStarts).sorted()
        let target = forward ? marks.first { $0 > playhead + 0.05 } : marks.last { $0 < playhead - 0.05 }
        seek(to: target ?? (forward ? duration : 0))
    }

    func schedulePlayerRebuild() {
        playerRebuild?.cancel()
        playerRebuild = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.isPlaying else { return }
            await self.rebuildPlayerItem(andPlay: true)
        }
    }

    private func rebuildPlayerItem(andPlay: Bool) async {
        let canvas = previewCanvas
        do {
            let built = try await StudioCompositionBuilder.build(
                asset: asset, timeline: edit.timeline, renderer: renderer, renderSize: canvas, fps: 60)
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            item.audioTimePitchAlgorithm = .spectral
            player.replaceCurrentItem(with: item)
            installTimeObserver()
            await player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            if andPlay, isPlaying { player.play() }
        } catch {
            isPlaying = false
        }
    }

    private func installTimeObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.playhead = min(time.seconds, self.duration)
                if self.player.rate == 0, self.playhead >= self.duration - 0.05 { self.pause() }
            }
        }
    }

    func tearDownPlayer() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.replaceCurrentItem(with: nil)
        isPlaying = false
    }
}
