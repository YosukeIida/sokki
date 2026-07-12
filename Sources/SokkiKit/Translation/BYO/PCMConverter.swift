import Foundation

public enum PCMConverter {
    /// 16 kHz mono Float32 samples を signed 16-bit little-endian PCM に変換する。
    /// Gemini Live の realtime input は `audio/pcm;rate=16000` を受け付けるため、
    /// AudioCaptureManager の 16 kHz 出力は再サンプリングせず送信する。
    public static func int16LittleEndianData(from samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clamped = min(1, max(-1, sample))
            let value: Int16 = clamped == -1
                ? .min
                : Int16((clamped * Float(Int16.max)).rounded())
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        return data
    }
}
