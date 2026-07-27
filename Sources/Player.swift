import AVFoundation
import MediaPlayer
import UIKit
import Foundation
import SwiftUI

/// Queue-based player. Resolves each track on-device (VISIONOS) and STREAMS the URL
/// directly in AVPlayer — instant start, seek, background + lock screen, auto-advance.
///
/// AVPlayer misreads this fragmented-MP4 format's duration (~2×), so we always use
/// the REAL duration from the format metadata and cap playback at it via
/// `forwardPlaybackEndTime` — otherwise the song stalls at the real end (looking like
/// it paused halfway) and never fires "ended", so it wouldn't auto-advance.
final class Player: ObservableObject {

    enum RepeatMode { case off, all, one }

    @Published var queue: [Track] = []
    @Published var index = 0
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime = 0.0
    @Published var duration = 0.0
    @Published var showFullPlayer = false
    @Published var lastError: String?

    @Published var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var favorites: Set<String> = []
    /// Seed color for the player's dynamic gradient (from album art; amber fallback).
    @Published var artColor: Color = Blaze.amber

    /// Order before shuffle, so toggling shuffle off restores it.
    private var originalQueue: [Track] = []

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var hasTrack: Bool { current != nil }
    var progress: Double { duration > 0 ? min(max(currentTime / duration, 0), 1) : 0 }

    private var avPlayer: AVPlayer?
    private var timeObserver: Any?
    private var statusObs: NSKeyValueObservation?
    private var isSeeking = false
    private var endHandled = false
    private var artwork: MPMediaItemArtwork?

    init() {
        configureSession()
        setupRemoteCommands()
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.trackEnded()
        }
    }

    // MARK: - Queue control

    func play(_ tracks: [Track], startAt: Int) {
        originalQueue = tracks
        queue = tracks
        index = startAt
        if isShuffled { applyShuffle() }
        loadCurrent()
    }

    func next() {
        if index < queue.count - 1 {
            index += 1
            loadCurrent()
        } else if repeatMode == .all {
            index = 0
            loadCurrent()
        }
    }

    // MARK: - Shuffle / repeat / favorite

    func toggleShuffle() {
        isShuffled.toggle()
        guard let cur = current else { return }
        if isShuffled {
            applyShuffle()
        } else {
            queue = originalQueue
            index = originalQueue.firstIndex(of: cur) ?? 0
        }
    }

    /// Keep the current track, shuffle everything else after it.
    private func applyShuffle() {
        guard let cur = current else { return }
        var rest = queue
        rest.removeAll { $0 == cur }
        rest.shuffle()
        queue = [cur] + rest
        index = 0
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func toggleFavorite() {
        guard let id = current?.videoId else { return }
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    }

    var isCurrentFavorite: Bool {
        guard let id = current?.videoId else { return false }
        return favorites.contains(id)
    }

    /// Jump to a specific queue position (from the Queue screen).
    func jump(to i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        loadCurrent()
    }

    // MARK: - Sleep timer

    @Published var sleepEndDate: Date?         // countdown target; nil = off
    @Published var sleepAtEndOfSong = false
    private var sleepTimer: Timer?

    var sleepActive: Bool { sleepEndDate != nil || sleepAtEndOfSong }
    var sleepRemaining: TimeInterval? {
        guard let end = sleepEndDate else { return nil }
        return max(0, end.timeIntervalSinceNow)
    }

    func startSleepTimer(minutes: Int) {
        sleepAtEndOfSong = false
        sleepEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let end = self.sleepEndDate else { return }
            if Date() >= end {
                self.stopForSleep()
            } else {
                self.objectWillChange.send()   // refresh the live countdown
            }
        }
    }

    func setSleepAtEndOfSong() {
        cancelSleepTimer()
        sleepAtEndOfSong = true
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepEndDate = nil
        sleepAtEndOfSong = false
    }

    private func stopForSleep() {
        cancelSleepTimer()
        avPlayer?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func prev() {
        if currentTime > 3 || index == 0 {
            seek(to: 0)
        } else {
            index -= 1
            loadCurrent()
        }
    }

    /// Advance once per track, whether triggered by the end notification or the
    /// time-observer backup.
    private func trackEnded() {
        guard !endHandled else { return }
        endHandled = true
        if sleepAtEndOfSong {
            sleepAtEndOfSong = false
            stopForSleep()
            return
        }
        if repeatMode == .one {
            endHandled = false
            seek(to: 0)
            avPlayer?.play()
            isPlaying = true
            updateNowPlaying()
            return
        }
        next()
    }

    // MARK: - Load / stream

    private func loadCurrent() {
        guard let track = current else { return }
        duration = track.duration
        currentTime = 0
        isLoading = true
        endHandled = false
        lastError = nil
        artwork = nil
        artColor = Blaze.amber
        loadArtwork(track.thumbnailURL)
        updateNowPlaying()

        let videoId = track.videoId

        // Offline first: play the downloaded file with no network if we have it.
        if let local = Downloads.shared.localAudioURL(for: videoId) {
            let dur = Downloads.shared.duration(for: videoId) ?? track.duration
            duration = dur
            isLoading = false
            playStream(local, realDuration: dur)
            prefetchNext()
            return
        }

        Task {
            let stream = await YouTube.streamURL(for: videoId)
            await MainActor.run {
                guard self.current?.videoId == videoId else { return }
                guard let stream else {
                    self.isLoading = false
                    self.lastError = "Couldn't load this track. Try again."
                    return
                }
                self.duration = stream.duration
                self.playStream(stream.url, realDuration: stream.duration)
                self.prefetchNext()
            }
        }
    }

    private func prefetchNext() {
        let n = index + 1
        guard queue.indices.contains(n) else { return }
        let vid = queue[n].videoId
        Task.detached { _ = await YouTube.streamURL(for: vid) }
    }

    private func playStream(_ url: URL, realDuration: Double) {
        removeTimeObserver()
        statusObs = nil

        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: YouTube.visionUA])
        let item = AVPlayerItem(asset: asset)
        if realDuration > 0 {
            item.forwardPlaybackEndTime = CMTime(seconds: realDuration, preferredTimescale: 600)
        }
        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay: self.isLoading = false
                case .failed:
                    self.isLoading = false
                    self.lastError = item.error?.localizedDescription ?? "Playback failed"
                default: break
                }
            }
        }

        let p = AVPlayer(playerItem: item)
        avPlayer = p
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main,
        ) { [weak self] time in
            guard let self, !self.isSeeking else { return }
            self.currentTime = time.seconds.isFinite ? time.seconds : 0
        }
        p.play()
        isPlaying = true
        updateNowPlaying()
    }

    func toggle() {
        guard let avPlayer else { return }
        if isPlaying { avPlayer.pause() } else { avPlayer.play() }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func seek(to fraction: Double) {
        guard duration > 0, let avPlayer else { return }
        let target = fraction * duration
        isSeeking = true
        currentTime = target
        updateNowPlaying()
        avPlayer.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero,
        ) { [weak self] _ in
            self?.isSeeking = false
        }
    }

    // MARK: - Session / remote / now-playing

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.prev(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard
                let self,
                let e = event as? MPChangePlaybackPositionCommandEvent,
                self.duration > 0
            else { return .commandFailed }
            self.seek(to: e.positionTime / self.duration)
            return .success
        }
    }

    private func resume() { avPlayer?.play(); isPlaying = true; updateNowPlaying() }
    private func pause() { avPlayer?.pause(); isPlaying = false; updateNowPlaying() }

    private func loadArtwork(_ url: URL?) {
        guard let url else { return }
        // Downloaded art is a local file:// URL — load it directly.
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return }
            artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            artColor = img.gradientSeed
            updateNowPlaying()
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let img = UIImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            let seed = img.gradientSeed
            DispatchQueue.main.async {
                self.artwork = art
                self.artColor = seed
                self.updateNowPlaying()
            }
        }.resume()
    }

    private func updateNowPlaying() {
        guard let track = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist.isEmpty ? "Blazify" : track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func removeTimeObserver() {
        if let timeObserver { avPlayer?.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }
}
