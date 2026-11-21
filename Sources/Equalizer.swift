import AVFoundation
import Combine
import MediaToolbox
import os
import SwiftUI

/// The named curves. Values are
/// per-band gain in dB across the ten ISO centres.
enum EQPreset: String, CaseIterable, Identifiable {
    case flat, bass, vocal, treble, rock, jazz, electronic, acoustic, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat: return String(localized: "Flat")
        case .bass: return String(localized: "Bass")
        case .vocal: return String(localized: "Vocal")
        case .treble: return String(localized: "Treble")
        case .rock: return String(localized: "Rock")
        case .jazz: return String(localized: "Jazz")
        case .electronic: return String(localized: "Electronic")
        case .acoustic: return String(localized: "Acoustic")
        case .custom: return String(localized: "Custom")
        }
    }

 /// Deliberately gentle — nothing here exceeds +6 dB. the presets push
    /// far harder, which is most of why they sound like they're breaking.
    var gains: [Double] {
        switch self {
        case .flat, .custom: return Array(repeating: 0, count: 10)
        case .bass:          return [5, 4.5, 3.5, 2, 0, 0, 0, 0, 0, 0]
        case .vocal:         return [-2, -1.5, 0, 1.5, 3, 3.5, 3, 1.5, 0, -1]
        case .treble:        return [0, 0, 0, 0, 0, 1, 2.5, 4, 4.5, 4]
        case .rock:          return [4, 3, 1.5, -0.5, -1, 0.5, 2.5, 3.5, 4, 4]
        case .jazz:          return [3, 2, 0.5, 1.5, -1, -1, 0, 1.5, 2.5, 3]
        case .electronic:    return [4.5, 3.5, 0.5, -1, -1.5, 1, 0.5, 2, 4, 4.5]
        case .acoustic:      return [3.5, 3, 1.5, 0.5, 1, 1, 2, 2.5, 2.5, 1.5]
        }
    }
}

/// Settings → Equaliser. One published `enabled` flag is the whole truth: the
/// audio tap is installed for the life of every item and simply runs at unity
/// when off. Nothing else can turn it on, which designs out a whole class of
/// "the equaliser did nothing" bug.
final class Equalizer: ObservableObject {
    static let shared = Equalizer()

    @Published var enabled: Bool { didSet { save(); push() } }
    @Published var preset: EQPreset { didSet { applyPreset(); save(); push() } }
    @Published var bands: [Double] { didSet { save(); push() } }
    @Published var bass: Double { didSet { save(); push() } }
    /// 1 = untouched stereo, up to 2 = widened.
    @Published var width: Double { didSet { save(); push() } }

    static let gainRange: ClosedRange<Double> = -12...12
    static let bassRange: ClosedRange<Double> = 0...12
    static let widthRange: ClosedRange<Double> = 1...2

    /// How much the preamp is pulling back to make room for the boosts.
    var headroom: Double { -max(0, max(bands.max() ?? 0, bass)) }

    private var loading = true

    private init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "eqEnabled")
        preset = EQPreset(rawValue: d.string(forKey: "eqPreset") ?? "") ?? .flat
        let stored = d.array(forKey: "eqBands") as? [Double] ?? []
        bands = stored.count == 10 ? stored : Array(repeating: 0, count: 10)
        bass = d.double(forKey: "eqBass")
        width = d.object(forKey: "eqWidth") as? Double ?? 1
        loading = false
        push()
    }

    /// Selecting a preset writes its curve; nudging a band makes it Custom.
    private func applyPreset() {
        guard !loading, preset != .custom else { return }
        loading = true
        bands = preset.gains
        loading = false
    }

    /// Call when the user drags a band directly.
    func markCustom() {
        guard preset != .custom else { return }
        loading = true
        preset = .custom
        loading = false
        save()
    }

    func reset() {
        loading = true
        preset = .flat
        bands = Array(repeating: 0, count: 10)
        bass = 0
        width = 1
        loading = false
        save()
        push()
    }

    private func push() {
        EqualizerDSP.shared.update(enabled: enabled, bands: bands, bass: bass, width: width)
    }

    private func save() {
        guard !loading else { return }
        let d = UserDefaults.standard
        d.set(enabled, forKey: "eqEnabled")
        d.set(preset.rawValue, forKey: "eqPreset")
        d.set(bands, forKey: "eqBands")
        d.set(bass, forKey: "eqBass")
        d.set(width, forKey: "eqWidth")
    }
}

// MARK: - The tap that puts the DSP inside AVPlayer

/// `AVAudioUnitEQ` belongs to AVAudioEngine and can't be attached to AVPlayer,
/// so the processing goes in through an `MTAudioProcessingTap` on the item's
/// audio track. The tap is always installed and always passes audio through —
/// when the equaliser is off the DSP returns immediately, so switching it on and
/// off never touches the audio graph and can never break playback.
enum EqualizerTap {
    static func audioMix(for asset: AVAsset) async -> AVAudioMix? {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: nil,
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess)

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        guard status == noErr, let tap else { return nil }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap

        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }
}

/// The 3D sound choice as the audio thread sees it. Set from the settings,
/// read once per buffer under a try-lock: if the settings happen to hold the
/// lock, that buffer keeps the choice it had, which nobody can hear.
final class SpatialSoundSwitch {
    static let shared = SpatialSoundSwitch()

    private var lock = os_unfair_lock_s()
    private var sound: SpatialSound

    private init() {
        sound = SpatialSound(rawValue: UserDefaults.standard.string(forKey: "spatialSound") ?? "") ?? .off
    }

    func set(_ next: SpatialSound) {
        os_unfair_lock_lock(&lock)
        sound = next
        os_unfair_lock_unlock(&lock)
    }

    /// The choice now, or nil when the lock is busy this instant.
    func current() -> SpatialSound? {
        guard os_unfair_lock_trylock(&lock) else { return nil }
        let now = sound
        os_unfair_lock_unlock(&lock)
        return now
    }
}

/// What one tap keeps between buffers: its own 3D sound engine, made in
/// prepare for the item's sample rate when the sound is stereo, and the choice
/// it last played with. Each item has its own, so two songs blending in a
/// crossfade never share one room.
private final class TapState {
    var spatial: Spatializer?
    var lastSound: SpatialSound = .off
}

private let tapInit: MTAudioProcessingTapInitCallback = { _, _, tapStorageOut in
    tapStorageOut.pointee = Unmanaged.passRetained(TapState()).toOpaque()
}

/// The tap's state, from the storage init gave it.
private func tapState(_ tap: MTAudioProcessingTap) -> TapState? {
    let storage: UnsafeMutableRawPointer? = MTAudioProcessingTapGetStorage(tap)
    return storage.map { Unmanaged<TapState>.fromOpaque($0).takeUnretainedValue() }
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    let storage: UnsafeMutableRawPointer? = MTAudioProcessingTapGetStorage(tap)
    if let raw = storage { Unmanaged<TapState>.fromOpaque(raw).release() }
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, format in
    EqualizerDSP.shared.setSampleRate(Float(format.pointee.mSampleRate))
    // Every buffer the 3D sound needs is taken here, never on the audio thread.
    guard let state = tapState(tap) else { return }
    let rate = format.pointee.mSampleRate
    state.spatial = format.pointee.mChannelsPerFrame == 2 && rate > 0
        ? Spatializer(rate: Int(rate)) : nil
    state.lastSound = .off
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
    tapState(tap)?.spatial = nil
}

private let tapProcess: MTAudioProcessingTapProcessCallback = {
    tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in

    let status = MTAudioProcessingTapGetSourceAudio(
        tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }

    let list = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    let dsp = EqualizerDSP.shared

    // AVPlayer hands us non-interleaved Float32, one buffer per channel.
    var channelPointers: [UnsafeMutablePointer<Float>] = []
    var frames = 0
    for buffer in list {
        guard let data = buffer.mData else { continue }
        let samples = data.assumingMemoryBound(to: Float.self)
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        channelPointers.append(samples)
        frames = max(frames, count)
    }
    guard !channelPointers.isEmpty else { return }

    for (index, pointer) in channelPointers.enumerated() {
        dsp.process(pointer, count: frames, channel: min(index, 1))
    }
    if channelPointers.count >= 2 {
        dsp.widen(left: channelPointers[0], right: channelPointers[1], count: frames)
    }
    spatialize(tap: tap, list: list)
    dsp.measure(channelPointers[0], count: frames)
}

/// 3D sound, after the equaliser, so the sound placed round the head is the
/// sound the person tuned. Off, or anything but stereo, passes untouched.
private func spatialize(tap: MTAudioProcessingTap, list: UnsafeMutableAudioBufferListPointer) {
    guard let state = tapState(tap), let engine = state.spatial else { return }
    let sound = SpatialSoundSwitch.shared.current() ?? state.lastSound
    if sound == .off {
        state.lastSound = .off
        return
    }
    // Back on after a while off: start from silence, not the last echoes.
    if state.lastSound == .off { engine.clear() }
    state.lastSound = sound
    engine.mode = sound == .orbit ? .orbit : .speakers

    if list.count == 2 {
        guard let l = list[0].mData, let r = list[1].mData else { return }
        let frames = Int(min(list[0].mDataByteSize, list[1].mDataByteSize)) / MemoryLayout<Float>.size
        engine.process(left: l.assumingMemoryBound(to: Float.self),
                       right: r.assumingMemoryBound(to: Float.self),
                       stride: 1, frames: frames)
    } else if list.count == 1, list[0].mNumberChannels == 2, let data = list[0].mData {
        let samples = data.assumingMemoryBound(to: Float.self)
        let frames = Int(list[0].mDataByteSize) / MemoryLayout<Float>.size / 2
        engine.process(left: samples, right: samples + 1, stride: 2, frames: frames)
    }
}
