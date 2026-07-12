import Foundation

/// 1回のデコードで得られたセグメント（確定判定前の生データ）。
/// Whisper 特殊トークン除去は済み・前後空白のトリムは未実施。
struct DecodedSegment: Sendable, Equatable {
    var start: Float
    var end: Float
    var text: String
    var avgLogProb: Float

    init(start: Float, end: Float, text: String, avgLogProb: Float = 0) {
        self.start = start
        self.end = end
        self.text = text
        self.avgLogProb = avgLogProb
    }
}

/// WhisperKit の `AudioStreamTranscriber` が持つ確定境界ロジックを、
/// WhisperKit 非依存の純粋な値ロジックとして切り出したもの（単体テスト可能）。
///
/// 各デコードは直近の確定境界 `lastConfirmedEnd`（秒）から末尾までを再デコードして得た
/// セグメント列を `ingest` に渡す。末尾 `requiredSegments` 本は「まだ揺れる可能性がある」
/// ため未確定（hypothesis）として保持し、それより前を確定する。
/// 停止時は `flush` で残り全部を確定する。
struct ConfirmedBoundaryTracker {

    /// 末尾側に保持して確定を保留するセグメント数（WhisperKit 既定と同じく 2）。
    let requiredSegments: Int

    /// 直近に確定したセグメントの終端（秒）。次回デコードの `clipTimestamps` 起点になる。
    private(set) var lastConfirmedEnd: Float = 0

    /// 直近の `ingest` で未確定として保持しているセグメント。
    /// 停止時に最終デコードが空・欠落を返した場合のフォールバック確定に使う（未確定分の消失防止）。
    private(set) var pendingHypothesis: [DecodedSegment] = []

    init(requiredSegments: Int = 2) {
        self.requiredSegments = max(0, requiredSegments)
    }

    /// 中間デコード結果を取り込み、新規確定分と現在の hypothesis を返す。
    mutating func ingest(_ segments: [DecodedSegment]) -> TranscriptionStreamUpdate {
        guard segments.count > requiredSegments else {
            // 確定に足りる本数がない → すべて未確定
            pendingHypothesis = segments
            return TranscriptionStreamUpdate(newlyConfirmed: [], hypothesis: Self.join(segments))
        }

        let confirmCount = segments.count - requiredSegments
        // 既確定境界より後ろのセグメントだけを確定候補にする（二重確定の防止）。
        // 例: prefix が [end=4, end=6] で lastConfirmedEnd=5 のとき、end=4 は既に確定済みなので除外する。
        let confirmSlice = Array(segments.prefix(confirmCount)).filter { $0.end > lastConfirmedEnd }
        let remaining = Array(segments.suffix(requiredSegments))
        pendingHypothesis = remaining

        if let last = confirmSlice.last {
            lastConfirmedEnd = last.end
            return TranscriptionStreamUpdate(
                newlyConfirmed: Self.snapshots(confirmSlice),
                hypothesis: Self.join(remaining)
            )
        } else {
            // 境界が前進しない（新規確定なし）。
            return TranscriptionStreamUpdate(newlyConfirmed: [], hypothesis: Self.join(remaining))
        }
    }

    /// 停止時: 確定境界より後ろのセグメントをすべて確定し、hypothesis を空にする。
    ///
    /// 最終デコード結果が空や一時的な欠落を返した場合は、保持中の hypothesis（`pendingHypothesis`）を
    /// フォールバックとして確定する。これにより「停止直前まで画面に出ていた未確定テキスト」を取りこぼさない。
    mutating func flush(_ segments: [DecodedSegment]) -> TranscriptionStreamUpdate {
        let fresh = segments.filter { $0.end > lastConfirmedEnd }
        let toConfirm = fresh.isEmpty
            ? pendingHypothesis.filter { $0.end > lastConfirmedEnd }
            : fresh
        if let last = toConfirm.last {
            lastConfirmedEnd = last.end
        }
        pendingHypothesis = []
        return TranscriptionStreamUpdate(newlyConfirmed: Self.snapshots(toConfirm), hypothesis: "")
    }

    // MARK: - Helpers

    private static func snapshots(_ segs: [DecodedSegment]) -> [TranscriptionSegmentSnapshot] {
        segs.compactMap { s in
            let trimmed = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return TranscriptionSegmentSnapshot(
                start: TimeInterval(s.start),
                end: TimeInterval(s.end),
                text: trimmed,
                isConfirmed: true,
                avgLogProb: s.avgLogProb
            )
        }
    }

    /// 未確定セグメント群を表示用の1本のテキストに連結する。
    /// Whisper のセグメントテキストは前置スペースを含むため、そのまま連結して全体をトリムする。
    private static func join(_ segs: [DecodedSegment]) -> String {
        segs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
