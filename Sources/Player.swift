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

    enum RepeatMode: Int { case off, all, one }

    @Published var queue: [Track] = []
    @Published var index = 0
    @Published var isPlaying = false
    @Published var isLoading = false
    /// Live position lives on its OWN observable. As a @Published on Player it
    /// re-rendered every screen observing the player four times a second —
    /// Home, Artist, the whole shell — which is exactly the lag that showed.
    let clock = PlaybackClock()
    var currentTime: Double {
        get { clock.currentTime }
        set { clock.currentTime = newValue }
    }
    @Published var duration = 0.0
    @Published var showFullPlayer = false
    @Published var lastError: String?

    @Published var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var favorites: Set<String> = []
    /// Full tracks for the Favorites tab (works offline and signed out).
    @Published var favoriteTracks: [Track] = []
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
    private var rateObs: NSKeyValueObservation?
    private var isSeeking = false
    /// Crossfade needs a second player: one AVPlayer holds one item, so the
    /// outgoing song keeps playing on this one while the new song starts.
    private var fadePlayer: AVPlayer?
    private var fadeTimer: Timer?
    /// True while a crossfade is running, so the normal end-of-track handler
    /// doesn't also try to advance.
    private var crossfading = false
    /// The next track, already built and buffered but paused. Swapping to this
    /// on end is what removes the gap — loading from scratch is the gap.
    private var preparedPlayer: AVPlayer?
    private var preparedIndex: Int?
    private var endHandled = false
    private var artwork: MPMediaItemArtwork?

    init() {
        configureSession()
        setupRemoteCommands()
        loadFavorites()
        restoreModes()
        restoreQueue()
        observeRouteChanges()
        observeInterruptions()
        NotificationCenter.default.addObserver(
            forName: .blazifyAudioPrefsChanged, object: nil, queue: .main,
        ) { [weak self] _ in self?.applyAudioPrefs() }
        // Backgrounding is the moment worth persisting the position.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main,
        ) { [weak self] _ in self?.saveQueue() }
        Task { await syncFavorites() }
        Task { @MainActor in
            ListenTogether.shared.onRemote = { [weak self] action in
                self?.applyRemote(action)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.trackEnded()
        }
    }

    // MARK: - Persistence of the session

    private struct SavedQueue: Codable {
        let tracks: [Track]
        let index: Int
        let position: Double
    }

    /// Settings → Player → Remember the queue.
    private func saveQueue() {
        guard PlaybackPrefs.shared.persistentQueue else { return }
        let saved = SavedQueue(tracks: queue, index: index, position: currentTime)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "savedQueue")
        }
    }

    /// Restores the queue paused at where you left off — never auto-playing,
    /// which would start music the moment the app opens.
    private func restoreQueue() {
        guard PlaybackPrefs.shared.persistentQueue,
              let data = UserDefaults.standard.data(forKey: "savedQueue"),
              let saved = try? JSONDecoder().decode(SavedQueue.self, from: data),
              !saved.tracks.isEmpty else { return }
        queue = saved.tracks
        originalQueue = saved.tracks
        index = min(max(saved.index, 0), saved.tracks.count - 1)
        resumePosition = saved.position
        // Fill the transport in now so the slider and times aren't blank before
        // the first tap.
        if let track = current {
            duration = Downloads.shared.duration(for: track.videoId) ?? track.duration
            currentTime = saved.position
        }
    }

    /// Where a restored session left off, applied once the stream is ready.
    private var resumePosition: Double = 0
    /// Set when the load was triggered by the user pressing play, so the stream
    /// starts as soon as it's seeked instead of needing a second press.
    private var playWhenReady = false

    private func saveModes() {
        guard PlaybackPrefs.shared.rememberShuffleRepeat else { return }
        UserDefaults.standard.set(isShuffled, forKey: "shuffleOn")
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
    }

    private func restoreModes() {
        guard PlaybackPrefs.shared.rememberShuffleRepeat else { return }
        isShuffled = UserDefaults.standard.bool(forKey: "shuffleOn")
        repeatMode = RepeatMode(rawValue: UserDefaults.standard.integer(forKey: "repeatMode")) ?? .off
    }

    /// Settings → Player → Resume on Bluetooth: start again when headphones or
    /// a speaker reconnect, which iOS reports as an route change.
    /// Audio interruptions (a call, Siri) and iOS pausing us. Without this the
    /// transport keeps claiming it's playing after the system has stopped us.
    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main,
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.isPlaying = false
                self.updateNowPlaying()
            case .ended:
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
                guard options.contains(.shouldResume) else { return }
                // The session goes inactive during an interruption; it has to be
                // reactivated before the player will make sound again.
                try? AVAudioSession.sharedInstance().setActive(true)
                self.avPlayer?.play()
                self.avPlayer?.rate = Float(PlaybackPrefs.shared.speed)
            @unknown default:
                break
            }
        }
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main,
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            switch reason {
            case .oldDeviceUnavailable:
                // Headphones or a speaker went away — iOS pauses us, so the
                // transport must stop claiming it's playing.
                self.avPlayer?.pause()
                self.isPlaying = false
                self.updateNowPlaying()
            case .newDeviceAvailable:
                guard PlaybackPrefs.shared.resumeOnBluetooth,
                      self.hasTrack, !self.isPlaying else { return }
                self.toggle()
            default:
                break
            }
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

    /// Advance if there's somewhere to go. Returns false at the end of the
    /// queue so the caller can stop rather than sit there looking like it plays.
    @discardableResult
    func next() -> Bool {
        if index < queue.count - 1 {
            index += 1
            loadCurrent()
            return true
        } else if repeatMode == .all {
            index = 0
            loadCurrent()
            return true
        }
        return false
    }

    // MARK: - Shuffle / repeat / favorite

    func toggleShuffle() {
        defer { saveModes() }
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
        defer { saveModes() }
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func toggleFavorite() {
        guard let track = current else { return }
        setFavorite(track, liked: !favorites.contains(track.videoId))
    }

    /// Optimistic local toggle, mirrored to the YouTube library when signed in
    /// (and reverted if the call fails). The whole track is kept so the
    /// Favorites tab works offline and signed out.
    func setFavorite(_ track: Track, liked: Bool) {
        // Settings → Player: save it offline the moment it's favourited.
        if liked, PlaybackPrefs.shared.autoDownloadOnLike {
            Downloads.shared.download(track)
        }
        Task { await LastFM.shared.love(track, loved: liked) }
        let id = track.videoId
        apply(track, liked: liked)
        guard Auth.shared.isLoggedIn else { return }
        Task {
            let ok = await YouTube.rateSong(videoId: id, like: liked)
            if !ok {
                await MainActor.run { self.apply(track, liked: !liked) }
            }
        }
    }

    private func apply(_ track: Track, liked: Bool) {
        if liked {
            favorites.insert(track.videoId)
            if !favoriteTracks.contains(where: { $0.videoId == track.videoId }) {
                favoriteTracks.insert(track, at: 0)
            }
        } else {
            favorites.remove(track.videoId)
            favoriteTracks.removeAll { $0.videoId == track.videoId }
        }
        saveFavorites()
    }

    var isCurrentFavorite: Bool {
        guard let id = current?.videoId else { return false }
        return favorites.contains(id)
    }

    /// Pull the account's Liked songs so hearts reflect the real library.
    func syncFavorites() async {
        guard Auth.shared.isLoggedIn else { return }
        let liked = await YouTube.likedSongs()
        guard !liked.isEmpty else { return }
        await MainActor.run {
            for track in liked where !self.favorites.contains(track.videoId) {
                self.favorites.insert(track.videoId)
                self.favoriteTracks.append(track)
            }
            self.saveFavorites()
        }
    }

    private func saveFavorites() {
        guard let data = try? JSONEncoder().encode(favoriteTracks) else { return }
        UserDefaults.standard.set(data, forKey: "favoriteTracks")
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: "favoriteTracks"),
              let saved = try? JSONDecoder().decode([Track].self, from: data) else { return }
        favoriteTracks = saved
        favorites = Set(saved.map(\.videoId))
    }

    /// Log the play so Trending, Stats and History all have something to read.
    private func countPlay(_ track: Track) {
        PlayHistory.record(track)
    }

    /// Jump to a specific queue position (from the Queue screen).
    /// Drag-to-reorder from the queue. The playing song keeps playing: its index
    /// just follows it to wherever it ended up.
    func moveInQueue(from offsets: IndexSet, to destination: Int) {
        guard let playing = current else { return }
        queue.move(fromOffsets: offsets, toOffset: destination)
        originalQueue = queue
        if let now = queue.firstIndex(where: { $0.videoId == playing.videoId }) {
            index = now
        }
        saveQueue()
    }

    /// Remove one track. Dropping the playing song moves to what took its place.
    func removeFromQueue(at position: Int) {
        guard queue.indices.contains(position) else { return }
        let wasPlaying = position == index
        let removed = queue.remove(at: position)
        originalQueue.removeAll { $0.videoId == removed.videoId }

        if queue.isEmpty {
            avPlayer?.pause()
            isPlaying = false
            index = 0
            saveQueue()
            return
        }
        if wasPlaying {
            index = min(position, queue.count - 1)
            loadCurrent()
        } else if position < index {
            index -= 1
        }
        saveQueue()
    }

    func jump(to i: Int) {
        cancelCrossfade()
        discardPrepared()
        guard queue.indices.contains(i) else { return }
        index = i
        loadCurrent()
    }

    /// Slot a song in right after the current one — Android's "Play next".
    func playNext(_ track: Track) {
        guard hasTrack else {
            play([track], startAt: 0)
            return
        }
        guard !admissible([track]).isEmpty else { return }
        queue.insert(track, at: min(index + 1, queue.count))
        originalQueue.insert(track, at: min(index + 1, originalQueue.count))
    }

    /// Append songs to the end of the queue, starting playback if idle.
    /// Drops anything already queued when "No duplicates" is on.
    private func admissible(_ tracks: [Track]) -> [Track] {
        guard PlaybackPrefs.shared.preventDuplicates else { return tracks }
        let known = Set(queue.map(\.videoId))
        var seen = Set<String>()
        return tracks.filter {
            !known.contains($0.videoId) && seen.insert($0.videoId).inserted
        }
    }

    func addToQueue(_ tracks: [Track]) {
        let fresh = admissible(tracks)
        guard !fresh.isEmpty else { return }
        if queue.isEmpty {
            play(fresh, startAt: 0)
        } else {
            queue.append(contentsOf: fresh)
            originalQueue.append(contentsOf: fresh)
        }
    }

    /// Apply an action the room host performed.
    private func applyRemote(_ action: ListenTogether.RemoteAction) {
        switch action {
        case .play(let position):
            if duration > 0 { seekSilently(to: position) }
            avPlayer?.play()
            isPlaying = true
            updateNowPlaying()
        case .pause(let position):
            if duration > 0 { seekSilently(to: position) }
            avPlayer?.pause()
            isPlaying = false
            updateNowPlaying()
        case .seek(let position):
            seekSilently(to: position)
        case .changeTrack(let track, let position):
            guard track.videoId != current?.videoId else {
                seekSilently(to: position)
                return
            }
            queue = [track]
            index = 0
            loadCurrent()
        }
    }

    /// Seek without broadcasting it back to the room.
    private func seekSilently(to seconds: Double) {
        guard let avPlayer, seconds.isFinite, seconds >= 0 else { return }
        currentTime = seconds
        avPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                      toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    // MARK: - Sleep timer

    @Published var sleepEndDate: Date?         // countdown target; nil = off
    @Published var sleepAtEndOfSong = false
    /// Stop after this many more songs (Android's "+/- N songs" option).
    @Published var sleepSongsRemaining: Int?
    private var sleepTimer: Timer?

    var sleepActive: Bool { sleepEndDate != nil || sleepAtEndOfSong || sleepSongsRemaining != nil }
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

    func startSleepAfterSongs(_ count: Int) {
        cancelSleepTimer()
        sleepSongsRemaining = max(1, count)
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepEndDate = nil
        sleepAtEndOfSong = false
        sleepSongsRemaining = nil
    }

    private func stopForSleep() {
        cancelSleepTimer()
        guard PlaybackPrefs.shared.sleepFadeOut, let player = avPlayer, isPlaying else {
            avPlayer?.pause()
            isPlaying = false
            updateNowPlaying()
            return
        }
        // Ease the volume down over five seconds rather than cutting off
        // mid-note, then restore it so the next play isn't silent.
        let startVolume = player.volume
        let steps = 25
        let interval = 5.0 / Double(steps)
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(step)) { [weak self] in
                guard let self, let player = self.avPlayer else { return }
                player.volume = startVolume * Float(1 - Double(step) / Double(steps))
                guard step == steps else { return }
                player.pause()
                player.volume = startVolume
                self.isPlaying = false
                self.updateNowPlaying()
            }
        }
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
        // A crossfade is already advancing the queue; the outgoing item hitting
        // its end must not advance it a second time.
        guard !crossfading, !endHandled else { return }
        endHandled = true
        if sleepAtEndOfSong {
            sleepAtEndOfSong = false
            stopForSleep()
            return
        }
        if let left = sleepSongsRemaining {
            let next = left - 1
            if next <= 0 {
                sleepSongsRemaining = nil
                stopForSleep()
                return
            }
            sleepSongsRemaining = next
        }
        if repeatMode == .one {
            endHandled = false
            seek(to: 0)
            avPlayer?.play()
            isPlaying = true
            updateNowPlaying()
            return
        }
        // Gapless: the next track is already built and buffered, so hand over
        // rather than loading, which is where the silence comes from.
        if adoptPreparedPlayer() { return }

        if !next() {
            // Queue's empty. Autoplay keeps going with songs related to the last
            // one — Android's auto radio queue — otherwise settle on paused at
            // the end instead of showing "playing" forever.
            if PlaybackPrefs.shared.autoplay, PlaybackPrefs.shared.autoRadioQueue,
               let last = current, !last.videoId.isEmpty {
                extendWithRadio(from: last)
                return
            }
            avPlayer?.pause()
            isPlaying = false
            currentTime = duration
            updateNowPlaying()
        }
    }

    /// Pull the last song's related tracks in and carry on playing.
    private func extendWithRadio(from track: Track) {
        isLoading = true
        Task { @MainActor in
            // `related` hands back shelves of cards, so flatten to the songs —
            // items with a videoId and no browseId are playable tracks.
            let shelves = await YouTube.related(videoId: track.videoId)
            let known = Set(self.queue.map(\.videoId))
            let fresh = shelves
                .flatMap(\.items)
                .filter { $0.browseId == nil }
                .map(\.asTrack)
                .filter { !$0.videoId.isEmpty && !known.contains($0.videoId) }
            guard !fresh.isEmpty else {
                self.isLoading = false
                self.avPlayer?.pause()
                self.isPlaying = false
                self.currentTime = self.duration
                self.updateNowPlaying()
                return
            }
            self.queue.append(contentsOf: fresh)
            self.endHandled = false
            _ = self.next()
        }
    }

    // MARK: - Load / stream

    private func loadCurrent() {
        guard let track = current else { return }
        if !crossfading { cancelCrossfade() }
        discardPrepared()
        // Last.fm: announce the song now, and arm the scrobble for later.
        scrobbleStart = Date()
        scrobbled = false
        Task { await LastFM.shared.nowPlaying(track) }
        duration = track.duration
        currentTime = 0
        // Only now that the position is reset — saving earlier stored the
        // previous song's position against this song's index.
        saveQueue()
        isLoading = true
        endHandled = false
        lastError = nil
        artwork = nil
        artColor = Blaze.amber
        loadArtwork(track.thumbnailURL)
        updateNowPlaying()

        let videoId = track.videoId
        countPlay(track)
        Task { @MainActor in ListenTogether.shared.broadcastTrack(track, position: 0) }

        // Disk before network: a deliberate download first, then the automatic
        // cache of things you've already played.
        if let local = Downloads.shared.localAudioURL(for: videoId) {
            let dur = Downloads.shared.duration(for: videoId) ?? track.duration
            duration = dur
            isLoading = false
            playStream(local, realDuration: dur)
            warmLyrics(for: track, duration: dur)
            prefetchNext()
            return
        }
        if let cached = AudioCache.shared.cachedURL(for: videoId), track.duration > 0 {
            duration = track.duration
            isLoading = false
            playStream(cached, realDuration: track.duration)
            warmLyrics(for: track, duration: track.duration)
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
                // Keep a copy so the next play needs no network.
                let cacheable = Track(videoId: track.videoId, title: track.title,
                                      artist: track.artist, thumbnail: track.thumbnail,
                                      duration: stream.duration, artistId: track.artistId)
                AudioCache.shared.cache(cacheable, from: stream.url)
                self.warmLyrics(for: track, duration: stream.duration)
                self.prefetchNext()
            }
        }
    }

    private func prefetchNext() {
        let n = index + 1
        guard queue.indices.contains(n) else { return }
        let next = queue[n]
        let vid = next.videoId
        Task.detached { _ = await YouTube.streamURL(for: vid) }
        // Warm the next song's lyrics too, so they're ready the moment it starts.
        Task.detached {
            await LyricsCache.shared.warm(videoId: vid, title: next.title,
                                          artist: next.artist, duration: next.duration)
        }
    }

    /// Fetch the current song's lyrics in the background, so the lyrics pane
    /// opens already populated instead of starting a five-provider search.
    private func warmLyrics(for track: Track, duration: Double) {
        let vid = track.videoId
        guard !vid.isEmpty else { return }
        Task.detached {
            await LyricsCache.shared.warm(videoId: vid, title: track.title,
                                          artist: track.artist, duration: duration)
        }
    }

    private func playStream(_ url: URL, realDuration: Double) {
        removeTimeObserver()
        statusObs = nil

        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: YouTube.visionUA])
        let item = AVPlayerItem(asset: asset)

        // The equaliser rides on an audio tap attached to the item. It's
        // installed for every track whether or not the EQ is on — the DSP
        // simply passes audio through when it's off — so toggling it never
        // rebuilds the audio graph mid-song.
        Task { @MainActor [weak item] in
            guard let mix = await EqualizerTap.audioMix(for: asset) else { return }
            item?.audioMix = mix
        }
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
                    // Don't strand the queue on one bad stream.
                    if PlaybackPrefs.shared.autoSkipOnError { _ = self.next() }
                default: break
                }
            }
        }

        // Playback speed keeps pitch by default (spectral is the good algorithm;
        // varispeed is the chipmunk one Android calls "varispeed").
        item.audioTimePitchAlgorithm = PlaybackPrefs.shared.preservePitch
            ? .timeDomain : .varispeed

        let p = AVPlayer(playerItem: item)
        avPlayer = p
        applyAudioPrefs()
        // The single source of truth for the transport: whatever the player is
        // actually doing. Anything that pauses us — an interruption, a route
        // change, a stall — now moves the icon too.
        attachObservers(to: p)
        // A session restored from disk resumes at its saved position, paused —
        // opening the app should never start music on its own.
        let target = resumePosition
        resumePosition = 0
        if target > 1, realDuration > target {
            let wanted = playWhenReady
            playWhenReady = false
            p.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
                guard let self else { return }
                self.currentTime = target
                guard wanted else { return }
                p.play()
                p.rate = Float(PlaybackPrefs.shared.speed)
            }
            isPlaying = wanted
            updateNowPlaying()
            return
        }
        playWhenReady = false
        p.play()
        // Rate has to be set after play(), which resets it to 1.
        p.rate = Float(PlaybackPrefs.shared.speed)
        isPlaying = true
        updateNowPlaying()
    }

    // MARK: - Gapless

    /// Build the next track's player early so it can start the instant this one
    /// ends. Crossfade already overlaps the two, so it takes precedence.
    private func considerGapless() {
        let prefs = PlaybackPrefs.shared
        guard prefs.gapless, !prefs.crossfade, !crossfading, isPlaying,
              repeatMode != .one, duration > 0
        else { return }
        let next = index + 1
        guard queue.indices.contains(next), preparedIndex != next else { return }
        // Ten seconds is enough to resolve and buffer without holding a second
        // stream open for most of the song.
        guard duration - currentTime <= 10 else { return }

        preparedIndex = next
        let track = queue[next]
        Task { @MainActor in
            guard let url = await self.resolvedURL(for: track),
                  self.preparedIndex == next else { return }
            let asset = AVURLAsset(url: url,
                                   options: [AVURLAssetHTTPUserAgentKey: YouTube.visionUA])
            let item = AVPlayerItem(asset: asset)
            item.audioTimePitchAlgorithm = PlaybackPrefs.shared.preservePitch
                ? .timeDomain : .varispeed
            let player = AVPlayer(playerItem: item)
            player.volume = self.avPlayer?.volume ?? 1
            // Buffer without making a sound.
            player.pause()
            self.preparedPlayer = player
        }
    }

    /// Swap to the pre-built player. Returns false when nothing was ready, so
    /// the caller falls back to a normal load.
    private func adoptPreparedPlayer() -> Bool {
        guard PlaybackPrefs.shared.gapless,
              let prepared = preparedPlayer,
              let target = preparedIndex,
              target == index + 1, queue.indices.contains(target)
        else { return false }

        avPlayer?.pause()
        removeTimeObserver()
        statusObs = nil
        rateObs = nil

        preparedPlayer = nil
        preparedIndex = nil
        avPlayer = prepared
        index = target
        prepared.play()
        prepared.rate = Float(PlaybackPrefs.shared.speed)
        adoptPlayingTrack()
        return true
    }

    private func discardPrepared() {
        preparedPlayer?.pause()
        preparedPlayer = nil
        preparedIndex = nil
    }

    // MARK: - Crossfade

    /// Begin blending into the next song once the current one is inside the
    /// configured window. Only for a real next track — a radio continuation or
    /// the end of the queue falls through to the normal handler.
    private func considerCrossfade() {
        let prefs = PlaybackPrefs.shared
        guard prefs.crossfade, !crossfading, isPlaying,
              repeatMode != .one, duration > 0,
              queue.indices.contains(index + 1)
        else { return }
        let window = prefs.crossfadeDuration
        guard duration - currentTime <= window, duration - currentTime > 0.2 else { return }

        crossfading = true
        let upcoming = queue[index + 1]
        Task { @MainActor in
            guard let url = await self.resolvedURL(for: upcoming) else {
                self.crossfading = false
                return
            }
            self.startCrossfade(to: url, over: window)
        }
    }

    /// The playable URL for a track: a download, then the cache, then the network.
    private func resolvedURL(for track: Track) async -> URL? {
        if let local = Downloads.shared.localAudioURL(for: track.videoId) { return local }
        if let cached = AudioCache.shared.cachedURL(for: track.videoId) { return cached }
        return await YouTube.streamURL(for: track.videoId)?.url
    }

    private func startCrossfade(to url: URL, over seconds: Double) {
        guard let outgoing = avPlayer else { crossfading = false; return }

        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: YouTube.visionUA])
        let item = AVPlayerItem(asset: asset)
        let incoming = AVPlayer(playerItem: item)
        incoming.volume = 0
        fadePlayer = incoming
        incoming.play()
        incoming.rate = Float(PlaybackPrefs.shared.speed)

        let startVolume = outgoing.volume
        let steps = max(Int(seconds * 20), 1)
        var step = 0
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: seconds / Double(steps),
                                         repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            let t = Float(min(Double(step) / Double(steps), 1))
            outgoing.volume = startVolume * (1 - t)
            incoming.volume = startVolume * t
            guard step >= steps else { return }
            timer.invalidate()
            self.finishCrossfade(volume: startVolume)
        }
    }

    /// Hand over to the faded-in player. Deliberately does NOT call
    /// `loadCurrent()` — that would build a third player and restart the song
    /// we've just spent the whole fade blending into. Everything except the
    /// audio is refreshed here instead.
    private func finishCrossfade(volume: Float) {
        fadeTimer?.invalidate()
        fadeTimer = nil
        guard let incoming = fadePlayer, index < queue.count - 1 else {
            cancelCrossfade()
            return
        }

        avPlayer?.pause()
        removeTimeObserver()
        statusObs = nil
        rateObs = nil

        avPlayer = incoming
        incoming.volume = volume
        fadePlayer = nil
        crossfading = false

        index += 1
        adoptPlayingTrack()
    }

    /// Refresh everything the UI and the system need for the track that is
    /// already playing on the adopted player.
    private func adoptPlayingTrack() {
        guard let track = current, let player = avPlayer else { return }

        scrobbleStart = Date()
        scrobbled = false
        Task { await LastFM.shared.nowPlaying(track) }

        endHandled = false
        isLoading = false
        lastError = nil
        artwork = nil
        artColor = Blaze.amber
        loadArtwork(track.thumbnailURL)

        let realDuration = player.currentItem?.duration.seconds ?? track.duration
        duration = realDuration.isFinite && realDuration > 0 ? realDuration : track.duration
        currentTime = player.currentTime().seconds
        isPlaying = true

        countPlay(track)
        saveQueue()
        updateNowPlaying()
        warmLyrics(for: track, duration: duration)
        prefetchNext()
        Task { @MainActor in ListenTogether.shared.broadcastTrack(track, position: 0) }

        attachObservers(to: player)
    }

    /// The time and rate observers, shared by a freshly built player and one
    /// adopted from a crossfade.
    private func attachObservers(to player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main,
        ) { [weak self] time in
            guard let self, !self.isSeeking else { return }
            self.currentTime = time.seconds.isFinite ? time.seconds : 0
            self.considerScrobble()
            self.considerCrossfade()
            self.considerGapless()
        }
        rateObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let playing = player.timeControlStatus != .paused
                if self.isPlaying != playing {
                    self.isPlaying = playing
                    self.updateNowPlaying()
                }
            }
        }
    }

    private func cancelCrossfade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        fadePlayer?.pause()
        fadePlayer = nil
        crossfading = false
    }

    /// When the current song started, and whether it's already been scrobbled.
    private var scrobbleStart = Date()
    private var scrobbled = false

    /// Last.fm's rule, the same one the Android module uses: songs of at least
    /// 30 s, scrobbled at half their length or four minutes in, whichever first.
    private func considerScrobble() {
        guard !scrobbled, let track = current,
              duration >= LastFMRules.minDuration else { return }
        let threshold = min(duration * LastFMRules.scrobbleFraction, LastFMRules.scrobbleCap)
        guard currentTime >= threshold else { return }
        scrobbled = true
        let started = scrobbleStart
        Task { await LastFM.shared.scrobble(track, startedAt: started) }
    }

    /// The playing song's loudness, if YouTube told us when resolving the stream.
    private var currentLoudnessDb: Double? {
        current.flatMap { YouTube.loudnessDb(for: $0.videoId) }
    }

    /// Speed, pitch handling and per-song volume, re-applied whenever the
    /// settings change or a new item starts.
    func applyAudioPrefs() {
        let prefs = PlaybackPrefs.shared
        avPlayer?.currentItem?.audioTimePitchAlgorithm =
            prefs.preservePitch ? .timeDomain : .varispeed
        if isPlaying { avPlayer?.rate = Float(prefs.speed) }
        // Volume normalisation: YouTube hands us the track's loudness, so trim
        // the player's gain toward the target instead of leaving loud masters
        // twice as loud as quiet ones.
        if prefs.normalizeVolume, let loudness = currentLoudnessDb {
            let trim = prefs.loudnessTarget - loudness
            avPlayer?.volume = Float(pow(10, min(trim, 0) / 20))
        } else {
            avPlayer?.volume = 1
        }
    }

    func toggle() {
        // A session restored from disk has a queue but nothing loaded yet;
        // pressing play should start it rather than silently do nothing.
        guard let avPlayer else {
            // Nothing loaded yet (a session restored from disk). Load it AND
            // play — without the intent flag this only loaded, and it took a
            // second press to actually start.
            if hasTrack {
                playWhenReady = true
                loadCurrent()
            }
            return
        }
        if isPlaying {
            avPlayer.pause()
        } else {
            avPlayer.play()
            avPlayer.rate = Float(PlaybackPrefs.shared.speed)
        }
        isPlaying.toggle()
        updateNowPlaying()
        let position = currentTime
        let playing = isPlaying
        Task { @MainActor in
            if playing { ListenTogether.shared.broadcastPlay(position: position) }
            else { ListenTogether.shared.broadcastPause(position: position) }
        }
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
        Task { @MainActor in ListenTogether.shared.broadcastSeek(position: target) }
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
            AppTheme.shared.setArtworkSeed(img.gradientSeed)
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
                AppTheme.shared.setArtworkSeed(seed)
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



/// The 4 Hz playback position, isolated so only views that actually draw time
/// (sliders, rings, lyrics) re-render with it.
final class PlaybackClock: ObservableObject {
    @Published var currentTime = 0.0
}
