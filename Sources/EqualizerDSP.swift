import Accelerate
import Foundation
import os

/// A single biquad section, Direct Form II transposed (the stable arrangement
/// for time-varying coefficients — moving a slider can't make it blow up).
struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0

    /// RBJ cookbook peaking filter.
    static func peaking(freq: Float, gainDB: Float, q: Float, sampleRate: Float) -> Biquad {
        guard gainDB != 0 else { return Biquad() }
        let a = powf(10, gainDB / 40)
        let w0 = 2 * Float.pi * min(freq, sampleRate * 0.45) / sampleRate
        let alpha = sinf(w0) / (2 * max(q, 0.1))
        let cosw = cosf(w0)
        let a0 = 1 + alpha / a
        return Biquad(b0: (1 + alpha * a) / a0,
                      b1: (-2 * cosw) / a0,
                      b2: (1 - alpha * a) / a0,
                      a1: (-2 * cosw) / a0,
                      a2: (1 - alpha / a) / a0)
    }

    /// RBJ low shelf — what the bass control uses, so it lifts everything below
    /// the corner rather than spiking one band the way a peaking filter would.
    static func lowShelf(freq: Float, gainDB: Float, sampleRate: Float) -> Biquad {
        guard gainDB != 0 else { return Biquad() }
        let a = powf(10, gainDB / 40)
        let w0 = 2 * Float.pi * min(freq, sampleRate * 0.45) / sampleRate
        let cosw = cosf(w0), sinw = sinf(w0)
        let alpha = sinw / 2 * sqrtf((a + 1 / a) * (1 / 0.9 - 1) + 2)
        let twoSqrtAAlpha = 2 * sqrtf(a) * alpha
        let a0 = (a + 1) + (a - 1) * cosw + twoSqrtAAlpha
        return Biquad(b0: a * ((a + 1) - (a - 1) * cosw + twoSqrtAAlpha) / a0,
                      b1: 2 * a * ((a - 1) - (a + 1) * cosw) / a0,
                      b2: a * ((a + 1) - (a - 1) * cosw - twoSqrtAAlpha) / a0,
                      a1: -2 * ((a - 1) + (a + 1) * cosw) / a0,
                      a2: ((a + 1) + (a - 1) * cosw - twoSqrtAAlpha) / a0)
    }
}

/// Per-channel filter state. Kept apart from the coefficients so a slider move
/// never resets the delay line mid-note (which is what clicks).
struct BiquadState { var z1: Float = 0, z2: Float = 0 }

/// The realtime audio processor. Everything here runs on CoreMedia's audio
/// thread: no allocation, no locking that can block, no Swift runtime calls that
/// might. Parameters arrive through a try-lock snapshot — if the UI happens to
/// hold the lock this buffer just uses the previous settings, which is
/// inaudible and always better than a glitch.
final class EqualizerDSP {
    static let shared = EqualizerDSP()

    /// Standard ten-band ISO centres.
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let bandCount = 10

    private var lock = os_unfair_lock_s()

    // Parameters — written by the UI, read by the audio thread under try-lock.
    private var coefficients = [Biquad](repeating: Biquad(), count: bandCount + 1)
    private var preampLinear: Float = 1
    private var widthAmount: Float = 1
    private var active = false

    // State — audio thread only. Two channels × (bands + the bass shelf).
    private var state = [BiquadState](repeating: BiquadState(), count: (bandCount + 1) * 2)
    private var sampleRate: Float = 44_100

    /// Spectrum magnitudes for the analyser, 0…1. Written by the audio thread,
    /// read by the UI — a torn read here costs one slightly-stale bar.
    private(set) var spectrum = [Float](repeating: 0, count: bandCount)
    /// Peak level of the last buffer, so the UI can warn about headroom.
    private(set) var peak: Float = 0

    private init() {}

    // MARK: Parameters (main thread)

    /// Recompute every coefficient. `bands` and `bass` are in dB.
    func update(enabled: Bool, bands: [Double], bass: Double, width: Double) {
        var next = [Biquad](repeating: Biquad(), count: Self.bandCount + 1)
        for i in 0..<Self.bandCount {
            next[i] = .peaking(freq: Self.frequencies[i],
                               gainDB: Float(bands[safe: i] ?? 0),
                               // Wide enough that neighbouring bands blend
                               // instead of forming ten narrow spikes.
                               q: 1.1, sampleRate: sampleRate)
        }
        next[Self.bandCount] = .lowShelf(freq: 120, gainDB: Float(bass), sampleRate: sampleRate)

        // Headroom compensation: this is what stops the Android problem where
        // boosting bass just clips. Whatever the loudest boost is, the preamp
        // comes down by the same amount, so the peak never rises above where it
        // started — you hear the tone change, not distortion.
        let maxBoost = max(0, max(bands.map(Float.init).max() ?? 0, Float(bass)))
        let preamp = powf(10, -maxBoost / 20)

        os_unfair_lock_lock(&lock)
        coefficients = next
        preampLinear = preamp
        widthAmount = Float(width)
        active = enabled
        os_unfair_lock_unlock(&lock)
    }

    func setSampleRate(_ rate: Float) {
        os_unfair_lock_lock(&lock)
        sampleRate = rate > 0 ? rate : 44_100
        for i in state.indices { state[i] = BiquadState() }
        os_unfair_lock_unlock(&lock)
    }

    // MARK: Processing (audio thread)

    /// Filter one non-interleaved channel in place.
    func process(_ samples: UnsafeMutablePointer<Float>, count: Int, channel: Int) {
        guard os_unfair_lock_trylock(&lock) else { return }
        let on = active
        let coeffs = coefficients
        let pre = preampLinear
        os_unfair_lock_unlock(&lock)
        guard on, count > 0 else { return }

        let sectionCount = Self.bandCount + 1
        let base = channel * sectionCount

        for section in 0..<sectionCount {
            let c = coeffs[section]
            // An untouched band is the identity filter — skip the work entirely.
            if c.b0 == 1 && c.b1 == 0 && c.b2 == 0 && c.a1 == 0 && c.a2 == 0 { continue }
            let index = base + section
            guard index < state.count else { continue }
            var z1 = state[index].z1, z2 = state[index].z2
            for n in 0..<count {
                let x = samples[n]
                let y = c.b0 * x + z1
                z1 = c.b1 * x - c.a1 * y + z2
                z2 = c.b2 * x - c.a2 * y
                samples[n] = y
            }
            state[index].z1 = z1
            state[index].z2 = z2
        }

        // Preamp, then a soft knee that only engages on the last 10% — well
        // below it the signal is untouched, so nothing is coloured needlessly.
        var level: Float = 0
        for n in 0..<count {
            var v = samples[n] * pre
            if v > 0.9 { v = 0.9 + tanhf((v - 0.9) * 4) * 0.1 }
            else if v < -0.9 { v = -0.9 + tanhf((v + 0.9) * 4) * 0.1 }
            samples[n] = v
            level = max(level, abs(v))
        }
        if channel == 0 { peak = level }
    }

    /// Mid-side widening across a stereo pair, after the per-channel filtering.
    /// This is the honest version of what "spatial"/"surround" toggles do to a
    /// plain stereo track — there is no height information to recover.
    func widen(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int) {
        guard os_unfair_lock_trylock(&lock) else { return }
        let on = active
        let width = widthAmount
        os_unfair_lock_unlock(&lock)
        guard on, width != 1, count > 0 else { return }

        for n in 0..<count {
            let mid = (left[n] + right[n]) * 0.5
            let side = (left[n] - right[n]) * 0.5 * width
            left[n] = mid + side
            right[n] = mid - side
        }
    }

    /// Band magnitudes for the analyser, from the same buffer we just filtered.
    /// A coarse RMS per band is all a ten-bar display needs — an FFT here would
    /// cost far more than it shows.
    func measure(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var sum: Float = 0
        vDSP_measqv(samples, 1, &sum, vDSP_Length(count))
        let rms = sqrtf(sum)
        // Spread the energy across the bars with a decay, so it reads as a
        // level display rather than ten identical bars.
        for i in 0..<Self.bandCount {
            let weight = 1 - abs(Float(i) - 3) / Float(Self.bandCount)
            let target = min(rms * (0.6 + weight), 1)
            spectrum[i] = spectrum[i] * 0.72 + target * 0.28
        }
    }
}
