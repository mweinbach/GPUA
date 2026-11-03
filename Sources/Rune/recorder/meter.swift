// Ported from: crates/rune/src/recorder/meter.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Meter ballistics shared by the fake microphone and the macOS backend.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(CRT)
import CRT
#endif

/// The quietest level a meter reports, in dBFS, as AVAudioRecorder does.
let RECORDER_FLOOR_DB: Float = -160.0
/// The level `Level.meter` maps to 0.
private let METER_FLOOR_DB: Float = -60.0
/// RMS rises with this time constant (seconds)...
private let METER_ATTACK: Double = 0.03
/// ...and falls with this one, so speech reads as a steady bar rather than flicker.
private let METER_RELEASE: Double = 0.3
/// The peak jumps up at once and falls this many dB a second.
private let METER_PEAK_FALL: Double = 20.0

/// An input level, smoothed like a meter: the peak jumps up at once and falls at 20 dB/s, and
/// the RMS rises over about 30 ms and falls over about 300 ms. Silence is -160 dBFS.
public struct Level: Sendable, Equatable {
    private var peakDbValue: Float
    private var rmsDbValue: Float

    /// No input.
    public static let SILENT = Level(peakDbValue: RECORDER_FLOOR_DB, rmsDbValue: RECORDER_FLOOR_DB)

    private init(peakDbValue: Float, rmsDbValue: Float) {
        self.peakDbValue = peakDbValue
        self.rmsDbValue = rmsDbValue
    }

    static func new(_ peakDb: Float, _ rmsDb: Float) -> Level {
        Level(
            peakDbValue: min(max(peakDb, RECORDER_FLOOR_DB), 0.0),
            rmsDbValue: min(max(rmsDb, RECORDER_FLOOR_DB), 0.0)
        )
    }

    /// The smoothed peak sample in dBFS (-160 to 0).
    public func peakDb() -> Float {
        peakDbValue
    }

    /// The smoothed RMS in dBFS (-160 to 0). A full-scale sine reads about -3.
    public func rmsDb() -> Float {
        rmsDbValue
    }

    /// The RMS for a level bar: -60 dBFS and below is 0, full scale is 1.
    public func meter() -> Float {
        toMeterScale(rmsDbValue)
    }

    /// The peak for a level bar, on `meter`'s scale.
    public func peakMeter() -> Float {
        toMeterScale(peakDbValue)
    }
}

private func toMeterScale(_ db: Float) -> Float {
    min(max((db - METER_FLOOR_DB) / (-METER_FLOOR_DB), 0.0), 1.0)
}

private func amplitudeToDb(_ amplitude: Double) -> Double {
    if amplitude > 0.0 {
        return max(20.0 * log10(amplitude), Double(RECORDER_FLOOR_DB))
    }
    return Double(RECORDER_FLOOR_DB)
}

/// Smooths raw block measurements into a `Level`.
struct AudioMeter: Sendable {
    var peakDb: Double = Double(RECORDER_FLOOR_DB)
    /// Smoothed mean square.
    var ms: Double = 0.0

    init() {}

    /// Folds in one block lasting `dt` seconds: its peak amplitude and mean square.
    mutating func push(_ peak: Double, _ meanSquare: Double, _ dt: Double) {
        if !(dt > 0.0) { return }
        let safeMs = meanSquare.isFinite ? max(meanSquare, 0.0) : 0.0
        let tau = safeMs > ms ? METER_ATTACK : METER_RELEASE
        ms += (safeMs - ms) * (1.0 - exp(-dt / tau))
        let pDb = peak.isFinite ? amplitudeToDb(abs(peak)) : Double(RECORDER_FLOOR_DB)
        peakDb = max(max(pDb, peakDb - METER_PEAK_FALL * dt), Double(RECORDER_FLOOR_DB))
    }

    /// Folds in a block measured in dBFS, as AVAudioRecorder reports it.
    mutating func pushDb(_ peakDbInput: Float, _ rmsDbInput: Float, _ dt: Double) {
        func amp(_ db: Float) -> Double {
            if db.isFinite && db > RECORDER_FLOOR_DB {
                return pow(10.0, Double(db) / 20.0)
            }
            return 0.0
        }
        let rms = amp(rmsDbInput)
        push(amp(peakDbInput), rms * rms, dt)
    }

    /// Folds in a block of samples lasting `samples.count / rate` seconds.
    mutating func pushSamples<S: Swift.Sequence>(_ samples: S, _ rate: UInt32) where S.Element == Float {
        var peak: Double = 0.0
        var sum: Double = 0.0
        var n: Int = 0
        for raw in samples {
            let s = raw.isFinite ? Double(raw) : 0.0
            peak = max(peak, abs(s))
            sum += s * s
            n += 1
        }
        if n > 0 && rate > 0 {
            push(peak, sum / Double(n), Double(n) / Double(rate))
        }
    }

    func level() -> Level {
        let rDb = ms > 0.0 ? max(10.0 * log10(ms), Double(RECORDER_FLOOR_DB)) : Double(RECORDER_FLOOR_DB)
        return Level.new(Float(peakDb), Float(rDb))
    }
}
