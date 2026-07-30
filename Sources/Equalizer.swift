import AVFoundation
import Combine
import MediaToolbox
import SwiftUI

/// The named curves, ported from the Android equaliser's presets. Values are
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

    /// Deliberately gentle — nothing here exceeds +6 dB. Android's presets push
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
/// when off. Nothing else can turn it on — which is the Android bug this
/// deliberately designs out.
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

private let tapInit: MTAudioProcessingTapInitCallback = { _, _, tapStorageOut in
    tapStorageOut.pointee = nil
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { _ in }

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { _, _, format in
    EqualizerDSP.shared.setSampleRate(Float(format.pointee.mSampleRate))
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in }

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
    dsp.measure(channelPointers[0], count: frames)
}
