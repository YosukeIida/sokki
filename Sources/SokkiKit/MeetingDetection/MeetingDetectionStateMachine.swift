import Foundation

/// 「拒否したら同一会議セッション中は再提案しない」を実現する状態機械。
///
/// - 会議候補が検出され続けている間、同じ `key`（アプリ名+タイトル）の提案を拒否されたら
///   そのセッションが終わる（連続 `missesBeforeReset` 回 `evaluate(detected: nil)` が呼ばれる）
///   まで再提案しない。
/// - 会議が `missesBeforeReset` 回連続で検出されなくなった時点でセッション終了とみなし、
///   拒否状態をリセットする。これにより同じタイトルの会議が後日再開しても新しいセッションとして
///   再提案できる。1回の検出漏れ（例: Teams の通話画面から Chat タブへ一時的に切り替えて
///   ウィンドウタイトルが変わった等）だけで拒否状態が消えてしまわないよう、猶予を持たせている。
///
/// SCShareableContent など副作用のある API には依存しないため、モック不要でテストできる。
struct MeetingDetectionStateMachine {
    private var dismissedKey: String?
    private var consecutiveMisses = 0
    private let missesBeforeReset: Int

    /// - Parameter missesBeforeReset: 何回連続で検出されなくなったらセッション終了とみなすか。
    init(missesBeforeReset: Int = 2) {
        precondition(missesBeforeReset >= 1)
        self.missesBeforeReset = missesBeforeReset
    }

    /// 直近のポーリング結果を渡し、バナーとして表示すべき候補を返す。
    /// 拒否済みの会議（同じ key）の場合は nil を返す。
    mutating func evaluate(detected: MeetingCandidate?) -> MeetingCandidate? {
        guard let detected else {
            consecutiveMisses += 1
            if consecutiveMisses >= missesBeforeReset {
                // 会議が検出されなくなった状態が続いた＝セッション終了。次回は新規セッションとして扱う。
                dismissedKey = nil
            }
            return nil
        }
        consecutiveMisses = 0
        if detected.key == dismissedKey {
            return nil
        }
        return detected
    }

    /// ユーザーが提案を拒否したときに呼ぶ。同一セッション中は再提案しなくなる。
    mutating func markDismissed(key: String) {
        dismissedKey = key
    }

    /// 検出を停止する際などに状態をリセットする。
    mutating func reset() {
        dismissedKey = nil
        consecutiveMisses = 0
    }
}
