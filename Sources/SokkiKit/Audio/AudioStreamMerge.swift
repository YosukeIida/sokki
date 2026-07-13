import Foundation

/// 2 本の `AsyncStream<AudioChunk>`（mic / system）を、チャンク受信順にインターリーブした
/// 1 本のストリームへ合成する。
///
/// ## 順序契約（重要）
/// - **各レーン内の順序は保証する**（mic のチャンク同士 / system のチャンク同士は投入順を維持）。
/// - **レーン間（mic vs system）の順序は「到着順」であり、`AudioChunk.capturedAt` の時系列順は保証しない。**
///   2 レーンは独立した IO コールバック（`AVAudioEngine` の tap キューと Core Audio Taps の IO キュー）から
///   並行に yield されるため、合成側で明示的に並べ替えない限り厳密な時系列にはならない。
///
/// この MVP 実装が到着順インターリーブに留める理由:
/// - 両レーンは同一の 16kHz 変換パイプラインを通り、ほぼ同時刻の IO コールバックから同じ cadence で
///   チャンクを出す。到着順は `capturedAt` 順を小さな窓の中で概ね追従しており、実運用の乱れは限定的。
/// - `capturedAt` 基準の並べ替えには「両レーンが時刻 T まで出し切った」ことを待つ時間窓が必要で、
///   リアルタイム文字起こし（hypothesis）経路に固定遅延を持ち込む。単一タイムライン（mono 1 本）への
///   合成は本質的にレーン情報を潰す近似であり、少々の時系列乱れより固定遅延の害の方が大きい。
/// - `AudioChunk.lane` は保持されるため、レーンを分離したまま扱う正攻法（各レーン独立の文字起こし＋
///   時間軸マージ）は Phase 3（TASK-26）に委ねる。そこで `capturedAt` を用いた厳密アラインメントを行う。
///
/// ## バッファリング方針
/// `bufferingPolicy` は **`.unbounded`（明示指定）**。確定境界（confirmed-boundary）方式の文字起こしでは
/// 入力チャンクの欠落が確定テキストの「穴」に直結するため、消費が一時的に遅れてもチャンクを捨てない。
/// なお上流 `WhisperKitEngine.transcribeStream` は入力 drain を専用 Task に分離しており、合成ストリームを
/// 律速なく吸い出すため、実運用では unbounded バッファに無制限蓄積することはない。
///
/// ## 終了・キャンセル
/// 合成ストリームは **両方の入力が finish したとき**にのみ finish する。消費側がキャンセル
/// （`onTermination`）した場合は内部 Task をキャンセルして両入力の購読を打ち切る。
func mergeAudioStreams(
    _ first: AsyncStream<AudioChunk>,
    _ second: AsyncStream<AudioChunk>
) -> AsyncStream<AudioChunk> {
    AsyncStream<AudioChunk>(bufferingPolicy: .unbounded) { continuation in
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await chunk in first { continuation.yield(chunk) }
                }
                group.addTask {
                    for await chunk in second { continuation.yield(chunk) }
                }
                await group.waitForAll()
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
