import Foundation

/// 話者区間（正解ラベルまたは diarization 出力の 1 区間）。半開区間 [start, end) として扱う。
///
/// `DiarizationSegment`（embedding 付き・エンジン内部型）とは別に、DER 計測という診断目的に
/// 絞った軽量な値型として定義する。RTTM / TSV パーサと DER 計算器の共通入力になる。
public struct DiarizationInterval: Sendable, Equatable {
    public let start: TimeInterval
    public let end: TimeInterval
    /// 話者ラベル。ref と hyp で命名規則が違っても DER 計算は最適マッピングで吸収するため、
    /// ここでは不透明な文字列として扱う。
    public let speaker: String

    public init(start: TimeInterval, end: TimeInterval, speaker: String) {
        self.start = start
        self.end = end
        self.speaker = speaker
    }

    /// 区間長（負なら 0 に丸める）。
    public var duration: TimeInterval { max(0, end - start) }
}

/// DER（Diarization Error Rate）の計算結果と内訳。
///
/// 率（`der` など）は「総リファレンス発話時間」を分母とする割合（例: 0.127 = 12.7%）。
/// 各 `*Duration` は秒単位の実時間で、`der == (missed + falseAlarm + confusion) / total` を満たす。
public struct DERResult: Sendable, Equatable {
    /// DER 合計（missed + falseAlarm + confusion のレート和）。
    public let der: Double
    /// 見逃し（missed detection）レート。リファレンスが話しているのに仮説が誰も割り当てていない時間。
    public let missedRate: Double
    /// 誤検出（false alarm）レート。リファレンスが無音なのに仮説が話者を割り当てている時間。
    public let falseAlarmRate: Double
    /// 話者取り違え（speaker confusion）レート。両者が話者を割り当てているが最適マッピング後も一致しない時間。
    public let confusionRate: Double

    public let missedDuration: TimeInterval
    public let falseAlarmDuration: TimeInterval
    public let confusionDuration: TimeInterval
    /// スコア対象となったリファレンス発話の総時間（collar 除外後）。DER レートの分母。
    public let totalReferenceDuration: TimeInterval

    /// 最適マッピング（仮説話者ラベル → リファレンス話者ラベル）。マッチしなかった仮説話者は含まれない。
    public let speakerMapping: [String: String]

    /// 百分率表記（`der * 100`）。ログ出力用の利便メソッド。
    public var derPercent: Double { der * 100 }
}

/// 標準的な NIST md-eval / pyannote.metrics 定義に従う DER 計算器（純粋関数）。
///
/// ## 定義
/// 共通タイムライン上の各素区間について、リファレンス側で発話中の話者数 `N_ref` と仮説側で発話中の
/// 話者数 `N_sys`、および最適マッピング下で一致している話者数 `N_correct` を数え、区間長 `d` で重み付けする:
///
/// - missed（見逃し）     += max(0, N_ref − N_sys) · d
/// - falseAlarm（誤検出） += max(0, N_sys − N_ref) · d
/// - confusion（取り違え）+= (min(N_ref, N_sys) − N_correct) · d
/// - total（分母）        += N_ref · d
///
/// `DER = (missed + falseAlarm + confusion) / total`。
///
/// 本プロジェクトの diarization は各時点で単一話者（非オーバーラップ）なので、実際には
/// `N_ref, N_sys ∈ {0, 1}` に収まるが、オーバーラップ入力が来ても定義どおり計算できるよう一般形で実装する。
///
/// ## 話者ラベルの最適マッピング
/// リファレンス話者と仮説話者の対応は未知なので、両者の共起時間（同時に発話している時間）を最大化する
/// 一対一マッチングを求める。話者数が少ない診断用途（会議で通常 2〜6 名）なので、
/// **小さい側の話者集合を大きい側へ割り当てる全単射を全列挙（順列）** して最大共起を選ぶ。
/// 厳密（Hungarian 相当の最適解）でありながら実装が単純で検証しやすい。列挙数が現実的な上限
/// （`maxExactPermutations`）を超える病的ケースのみ、貪欲マッチング（共起の大きいペアから確定）に退避する。
/// 貪欲は最適とは限らないが、そのような話者数はベンチマークでは通常発生しない。
///
/// ## collar
/// `collar > 0` のとき、各**リファレンス境界**（各区間の開始・終了時刻）の周囲 ±`collar` を
/// スコア対象外（no-score）とする。境界付近のアノテーション誤差を許容する CALLHOME 系の慣習
/// （「collar 0.25s」= 片側 0.25s）に合わせる。no-score 区間はリファレンス・仮説とも計測から除外し、
/// 分母 `total` にも含めない。
public enum DERCalculator {

    /// 全列挙する順列数の上限。これを超える場合は貪欲マッチングに退避する。
    /// 8! = 40320。会議の話者数（〜6 名）では全列挙で十分に収まる。
    static let maxExactPermutations = 40_320

    public static func computeDER(
        reference: [DiarizationInterval],
        hypothesis: [DiarizationInterval],
        collar: TimeInterval = 0
    ) -> DERResult {
        // 有効な（長さ > 0 の）区間だけを対象にする。
        let ref = reference.filter { $0.duration > 0 }
        let hyp = hypothesis.filter { $0.duration > 0 }

        // no-score 区間（collar）を構築。リファレンス境界の周囲 ±collar。
        let noScore = noScoreRegions(reference: ref, collar: collar)

        // 素区間の境界点を収集（両者の全端点 + collar 境界）。
        var cuts = Set<TimeInterval>()
        for s in ref { cuts.insert(s.start); cuts.insert(s.end) }
        for s in hyp { cuts.insert(s.start); cuts.insert(s.end) }
        for r in noScore { cuts.insert(r.start); cuts.insert(r.end) }
        let boundaries = cuts.sorted()

        // 最適マッピングのための共起時間行列（no-score 除外後）。
        let refSpeakers = orderedSpeakers(ref)
        let sysSpeakers = orderedSpeakers(hyp)
        var cooccur: [String: [String: TimeInterval]] = [:] // ref -> sys -> 共起時間

        // 素区間ごとの集計を 2 パスに分けず、まず共起行列とスコアに必要な素区間情報を一度で作る。
        struct Slice { let duration: TimeInterval; let refActive: [String]; let sysActive: [String] }
        var slices: [Slice] = []
        slices.reserveCapacity(max(0, boundaries.count - 1))

        for i in 0..<max(0, boundaries.count - 1) {
            let a = boundaries[i]
            let b = boundaries[i + 1]
            let mid = (a + b) / 2
            let d = b - a
            guard d > 0 else { continue }
            if isInNoScore(mid, regions: noScore) { continue }

            let refActive = ref.filter { $0.start <= mid && mid < $0.end }.map { $0.speaker }
            let sysActive = hyp.filter { $0.start <= mid && mid < $0.end }.map { $0.speaker }
            slices.append(Slice(duration: d, refActive: refActive, sysActive: sysActive))

            for r in refActive {
                for s in sysActive {
                    cooccur[r, default: [:]][s, default: 0] += d
                }
            }
        }

        let mapping = optimalMapping(
            refSpeakers: refSpeakers,
            sysSpeakers: sysSpeakers,
            cooccur: cooccur
        )
        // speakerMapping は sys -> ref で公開する（呼び出し側が hyp ラベルを ref ラベルへ読み替える用途）。
        var sysToRef: [String: String] = [:]
        for (r, s) in mapping { sysToRef[s] = r }

        var missed: TimeInterval = 0
        var falseAlarm: TimeInterval = 0
        var confusion: TimeInterval = 0
        var total: TimeInterval = 0

        for slice in slices {
            let nRef = slice.refActive.count
            let nSys = slice.sysActive.count
            let refSet = Set(slice.refActive)
            // 一致数: マッピング先の ref がこの区間でも発話している sys の数。
            var correct = 0
            for s in slice.sysActive {
                if let r = sysToRef[s], refSet.contains(r) { correct += 1 }
            }
            let d = slice.duration
            missed += Double(max(0, nRef - nSys)) * d
            falseAlarm += Double(max(0, nSys - nRef)) * d
            confusion += Double(min(nRef, nSys) - correct) * d
            total += Double(nRef) * d
        }

        // total == 0（スコア対象のリファレンス発話が無い）のときはレートを 0 とする。
        // 誤検出時間は残るが、正規化する分母が無いため率は定義しない（0 とする）。
        let denom = total > 0 ? total : 1
        let missedRate = total > 0 ? missed / denom : 0
        let faRate = total > 0 ? falseAlarm / denom : 0
        let confRate = total > 0 ? confusion / denom : 0

        return DERResult(
            der: missedRate + faRate + confRate,
            missedRate: missedRate,
            falseAlarmRate: faRate,
            confusionRate: confRate,
            missedDuration: missed,
            falseAlarmDuration: falseAlarm,
            confusionDuration: confusion,
            totalReferenceDuration: total,
            speakerMapping: sysToRef
        )
    }

    // MARK: - マッピング

    /// 共起時間を最大化する ref↔sys の一対一マッチングを返す（ref -> sys のペア配列）。
    static func optimalMapping(
        refSpeakers: [String],
        sysSpeakers: [String],
        cooccur: [String: [String: TimeInterval]]
    ) -> [(String, String)] {
        guard !refSpeakers.isEmpty, !sysSpeakers.isEmpty else { return [] }

        // 小さい側を「割り当てる側」にして順列数を抑える。
        let (small, large, smallIsRef): ([String], [String], Bool) =
            refSpeakers.count <= sysSpeakers.count
            ? (refSpeakers, sysSpeakers, true)
            : (sysSpeakers, refSpeakers, false)

        func weight(ref: String, sys: String) -> TimeInterval {
            cooccur[ref]?[sys] ?? 0
        }

        // 全列挙が現実的かどうか判定: P(large, small) = large! / (large - small)!
        let permutationCount = partialPermutationCount(n: large.count, k: small.count)

        let pairs: [(small: String, large: String)]
        if permutationCount <= maxExactPermutations {
            pairs = exactBestMatching(small: small, large: large) { s, l in
                smallIsRef ? weight(ref: s, sys: l) : weight(ref: l, sys: s)
            }
        } else {
            pairs = greedyMatching(small: small, large: large) { s, l in
                smallIsRef ? weight(ref: s, sys: l) : weight(ref: l, sys: s)
            }
        }

        // 共起 0 のペアは対応なしとみなして除外する。
        return pairs.compactMap { pair in
            let w = smallIsRef ? weight(ref: pair.small, sys: pair.large)
                               : weight(ref: pair.large, sys: pair.small)
            guard w > 0 else { return nil }
            return smallIsRef ? (pair.small, pair.large) : (pair.large, pair.small)
        }
    }

    /// small の各要素を large の相異なる要素へ割り当てる全単射を全列挙し、重み合計最大の割当を返す。
    private static func exactBestMatching(
        small: [String],
        large: [String],
        weight: (String, String) -> TimeInterval
    ) -> [(small: String, large: String)] {
        var bestPairs: [(small: String, large: String)] = []
        var bestScore = -Double.greatestFiniteMagnitude
        var used = Array(repeating: false, count: large.count)
        var current: [(small: String, large: String)] = []

        func recurse(_ index: Int, _ score: TimeInterval) {
            if index == small.count {
                if score > bestScore {
                    bestScore = score
                    bestPairs = current
                }
                return
            }
            for j in 0..<large.count where !used[j] {
                used[j] = true
                current.append((small[index], large[j]))
                recurse(index + 1, score + weight(small[index], large[j]))
                current.removeLast()
                used[j] = false
            }
        }
        recurse(0, 0)
        return bestPairs
    }

    /// 共起の大きいペアから貪欲に確定する（病的な話者数のときの退避）。
    private static func greedyMatching(
        small: [String],
        large: [String],
        weight: (String, String) -> TimeInterval
    ) -> [(small: String, large: String)] {
        var candidates: [(s: String, l: String, w: TimeInterval)] = []
        for s in small {
            for l in large {
                candidates.append((s, l, weight(s, l)))
            }
        }
        // 重み降順、同値は決定性のためラベル順で安定化。
        candidates.sort { lhs, rhs in
            if lhs.w != rhs.w { return lhs.w > rhs.w }
            if lhs.s != rhs.s { return lhs.s < rhs.s }
            return lhs.l < rhs.l
        }
        var usedSmall = Set<String>()
        var usedLarge = Set<String>()
        var pairs: [(small: String, large: String)] = []
        for c in candidates {
            guard c.w > 0, !usedSmall.contains(c.s), !usedLarge.contains(c.l) else { continue }
            usedSmall.insert(c.s)
            usedLarge.insert(c.l)
            pairs.append((c.s, c.l))
        }
        return pairs
    }

    // MARK: - ヘルパ

    /// 話者ラベルを初出順で安定に列挙する（決定的な出力のため）。
    private static func orderedSpeakers(_ intervals: [DiarizationInterval]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for i in intervals where !seen.contains(i.speaker) {
            seen.insert(i.speaker)
            ordered.append(i.speaker)
        }
        return ordered.sorted() // ラベル置換不変性のため辞書順に正規化する
    }

    private struct Region { let start: TimeInterval; let end: TimeInterval }

    private static func noScoreRegions(reference: [DiarizationInterval], collar: TimeInterval) -> [Region] {
        guard collar > 0 else { return [] }
        var regions: [Region] = []
        for s in reference {
            regions.append(Region(start: s.start - collar, end: s.start + collar))
            regions.append(Region(start: s.end - collar, end: s.end + collar))
        }
        return regions
    }

    private static func isInNoScore(_ t: TimeInterval, regions: [Region]) -> Bool {
        for r in regions where t >= r.start && t < r.end { return true }
        return false
    }

    /// P(n, k) = n! / (n-k)! を安全に計算（上限超過時は `.max` を返して全列挙を回避させる）。
    private static func partialPermutationCount(n: Int, k: Int) -> Int {
        guard k <= n else { return 0 }
        var result = 1
        for i in 0..<k {
            let (product, overflow) = result.multipliedReportingOverflow(by: n - i)
            if overflow || product > maxExactPermutations { return Int.max }
            result = product
        }
        return result
    }
}
