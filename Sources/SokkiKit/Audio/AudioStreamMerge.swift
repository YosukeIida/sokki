import Foundation

/// 2 本の `AsyncStream<AudioChunk>`（mic / system）を、チャンク受信順にインターリーブした
/// 1 本のストリームへ合成する。
///
/// Both モード（TASK-12）の MVP 方針: 文字起こしエンジンは 1 本のオーディオストリームを消費するため、
/// mic と system のチャンクを到着順に 1 本化して供給する。レーン情報（`AudioChunk.lane`）は保持される
/// ので、話者／レーン分離の高度化は Phase 3 のマージ（TASK-26）に委ねる。
///
/// 合成ストリームは **両方の入力が finish したとき**にのみ finish する。消費側がキャンセル
/// （`onTermination`）した場合は内部 Task をキャンセルして両入力の購読を打ち切る。
func mergeAudioStreams(
    _ first: AsyncStream<AudioChunk>,
    _ second: AsyncStream<AudioChunk>
) -> AsyncStream<AudioChunk> {
    AsyncStream<AudioChunk> { continuation in
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
