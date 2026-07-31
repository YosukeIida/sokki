import Foundation

/// diarization の正解ラベルを表す標準フォーマットのパーサ（純粋関数）。
///
/// - **RTTM**（Rich Transcription Time Marked）: NIST 由来で pyannote / md-eval が入出力に使う標準形式。
/// - **TSV**: `start<TAB>end<TAB>speaker` の 3 列。Audacity のラベルトラック書き出しがこの形式なので、
///   手作業でラベル付けした正解をそのまま食わせられる。
///
/// いずれも `[DiarizationInterval]` を返す。行番号付きのエラーで不正入力を報告する。
public enum RTTMParser {

    public enum ParseError: Error, LocalizedError, Equatable {
        case malformedLine(line: Int, content: String)
        case invalidNumber(line: Int, field: String)
        /// `end <= start`（区間長が 0 以下）。人手ラベリングの typo（点ラベルの取り違え等）を
        /// 黙って握りつぶさず報告するための専用ケース。
        case nonPositiveDuration(line: Int, start: TimeInterval, end: TimeInterval)

        public var errorDescription: String? {
            switch self {
            case .malformedLine(let line, let content):
                return "RTTM/TSV \(line) 行目を解釈できません: \(content)"
            case .invalidNumber(let line, let field):
                return "RTTM/TSV \(line) 行目の数値フィールドが不正です: \(field)"
            case .nonPositiveDuration(let line, let start, let end):
                return "RTTM/TSV \(line) 行目の区間が不正です（end <= start）: start=\(start), end=\(end)"
            }
        }
    }

    /// RTTM テキストをパースする。
    ///
    /// RTTM の `SPEAKER` 行は標準では空白区切りの 10 フィールド:
    /// `SPEAKER <file> <chnl> <start> <dur> <NA> <NA> <speaker> <conf> <NA>`。
    /// `start`（4 列目）と `dur`（5 列目）から `[start, start+dur)` を、`speaker`（8 列目）から
    /// 話者ラベルを取り出す。`SPEAKER` 以外の型行（`SPKR-INFO` 等）・空行・`;;` コメントは無視する。
    /// 本パーサは末尾の任意フィールド（`conf` 以降）を実際には参照しないため、8 列（`speaker` まで）
    /// あれば受理する寛容な実装にしてある（10 列未満だからといってエラーにはしない）。
    /// `dur <= 0`（区間長が 0 以下）は `.nonPositiveDuration` として明示的にエラー扱いする。
    public static func parseRTTM(_ text: String) throws -> [DiarizationInterval] {
        var intervals: [DiarizationInterval] = []
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNo = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";;") { continue }

            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.first == "SPEAKER" else { continue } // 型が SPEAKER の行だけを対象にする
            guard fields.count >= 8 else {
                throw ParseError.malformedLine(line: lineNo, content: line)
            }
            guard let start = Double(fields[3]), start.isFinite else {
                throw ParseError.invalidNumber(line: lineNo, field: fields[3])
            }
            guard let dur = Double(fields[4]), dur.isFinite else {
                throw ParseError.invalidNumber(line: lineNo, field: fields[4])
            }
            guard dur > 0 else {
                throw ParseError.nonPositiveDuration(line: lineNo, start: start, end: start + dur)
            }
            let speaker = fields[7]
            intervals.append(DiarizationInterval(start: start, end: start + dur, speaker: speaker))
        }
        return intervals
    }

    /// TSV（`start<TAB>end<TAB>speaker`）をパースする。Audacity のラベルトラック書き出し互換。
    ///
    /// タブまたは連続空白を区切りとして許容する。空行・`#` で始まるコメント行は無視する。
    /// Audacity は同一ラベルを 2 行（開始行と終了行）で書くことがあるが、通常のリージョンラベルは
    /// 1 行 3 列なのでそれを前提とする。
    public static func parseTSV(_ text: String) throws -> [DiarizationInterval] {
        var intervals: [DiarizationInterval] = []
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNo = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
                .map(String.init)
                .filter { !$0.isEmpty }
            guard fields.count >= 3 else {
                throw ParseError.malformedLine(line: lineNo, content: line)
            }
            guard let start = Double(fields[0]), start.isFinite else {
                throw ParseError.invalidNumber(line: lineNo, field: fields[0])
            }
            guard let end = Double(fields[1]), end.isFinite else {
                throw ParseError.invalidNumber(line: lineNo, field: fields[1])
            }
            guard end > start else {
                throw ParseError.nonPositiveDuration(line: lineNo, start: start, end: end)
            }
            // 話者ラベルは 3 列目以降を空白で連結（ラベルに空白を含む可能性に配慮）。
            let speaker = fields[2...].joined(separator: " ")
            intervals.append(DiarizationInterval(start: start, end: end, speaker: speaker))
        }
        return intervals
    }

    /// 拡張子から RTTM / TSV を判別してパースする（`.rttm` なら RTTM、それ以外は TSV）。
    public static func parse(contentsOf url: URL) throws -> [DiarizationInterval] {
        let text = try String(contentsOf: url, encoding: .utf8)
        if url.pathExtension.lowercased() == "rttm" {
            return try parseRTTM(text)
        }
        return try parseTSV(text)
    }
}
