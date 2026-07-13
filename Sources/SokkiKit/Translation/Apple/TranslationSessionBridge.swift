import SwiftUI
import Translation

// MARK: - actor↔MainActor 境界を越える値型（String だけ）

/// 翻訳リクエストの素の値。`docs/translation-architecture.md` §0 訂正 #1 に従い、
/// actor↔MainActor 境界を越えるのは `TranslationSession.Request` そのものではなく **素の String**
/// だけにする。`TranslationSession.Request` の生成は `.translationTask` closure（nonisolated）内
/// でのみ行う（`LiveTranslationSession`）。
struct AppleTranslationRequest: Sendable, Equatable {
    let sourceText: String
    /// = `TranslationInput.id`（clientID）。応答の順序逆転に耐えるためのエコーバックキー。
    let clientID: String
}

/// 翻訳レスポンスの素の値。境界を越えるのは String だけ（同 §0 訂正 #1）。
struct AppleTranslationResponse: Sendable, Equatable {
    let targetText: String
    let clientID: String
}

// MARK: - session 抽象（drain ループをフレームワーク非依存でテストするための seam）

/// `AppleTranslationProvider` の drain ループが `TranslationSession` に要求する最小操作。
///
/// 実体は `LiveTranslationSession`（`TranslationSession` を包む）。テストではモックを注入して、
/// session の受け渡し・入力→翻訳呼び出し→出力の順序・teardown での drain 停止を検証する。
///
/// `.translationTask` の action closure は **nonisolated**（`@escaping (TranslationSession) async
/// -> Void`）で、`TranslationSession` は非 Sendable クラス。よってこの抽象と drain ループは
/// nonisolated に置き、非 Sendable な session を隔離境界越しに送らない（§0 訂正 #1）。
protocol AppleTranslationSession {
    /// 翻訳せずモデル DL 同意 UI のみを出す（ホスト view にアンカー表示）。
    func prepareTranslation() async throws
    /// 素の値の列を翻訳し、素の値の列で返す。`Request`/`Response` は closure 内に閉じ込める。
    func translate(_ requests: [AppleTranslationRequest]) async throws -> [AppleTranslationResponse]
}

// MARK: - ホストへ渡すジョブ（Sendable 値 + @Sendable 継続）

/// 常駐ホストへ渡すメッセージ。actor（provider）→ MainActor（ホスト）へ渡るため `Sendable`。
/// 境界を越えるペイロードは素の値型（`AppleTranslationRequest`）と、`CheckedContinuation` を
/// 再開する `@Sendable` クロージャのみ（`CheckedContinuation` は `Sendable`）。
enum HostMessage: Sendable {
    /// モデル DL 同意のみ。`completion(nil)` で成功、`completion(error)` で失敗。
    case prepareOnly(completion: @Sendable (Error?) -> Void)
    /// 翻訳ジョブ。`resume` に応答、`fail` にエラーを返す。
    case job(
        requests: [AppleTranslationRequest],
        resume: @Sendable ([AppleTranslationResponse]) -> Void,
        fail: @Sendable (Error) -> Void
    )
}

/// drain ループが session 呼び出しの結果をホストへ返すための結果値（Sendable）。
/// 完了の発火（一度きり）はホスト側（MainActor）で一元管理する。
enum JobOutcome: Sendable {
    case responses([AppleTranslationResponse])
    case prepared
    case failure(TranslationProviderError)
    /// teardown / 世代失効によるキャンセル。
    case cancelled
}

// MARK: - provider ↔ ホストの結線（provider をユニットテスト可能にする seam）

/// `AppleTranslationProvider`（actor）がホストへ委譲するライフサイクル操作。
///
/// 実体は `TranslationSessionBridge`。テストではモックホストを注入し、実 Translation
/// フレームワーク非依存で provider の `prepare`/`translateStream`/`teardown` を検証する。
/// ホストは MainActor 隔離なので existential も `Sendable`（actor から安全に握れる）。
///
/// **世代（generation）契約**: `setLanguages` は新しい session 世代 ID を返す。provider は以降の
/// `awaitReady` / `enqueue` にその世代を添えることで、旧 session への取りこぼし・誤配送や、
/// teardown 後のゾンビジョブ実行を防ぐ（codex レビュー MAJOR-1 / MAJOR-2）。
@MainActor
protocol AppleTranslationHosting: AnyObject, Sendable {
    /// 新しい言語ペアの session を要求し、その世代 ID を返す（= `.translationTask` 再走トリガー）。
    func setLanguages(source: Locale.Language, target: Locale.Language) -> UInt64
    /// 指定世代の session closure が受理可能（ready）になるまで待つ。
    /// timeout 超過・世代失効で `TranslationProviderError` を throw（fail-closed）。
    func awaitReady(generation: UInt64, timeout: Duration) async throws
    /// 指定世代へメッセージを積む。世代失効・session 破棄済みなら即座に `cancelled` で完了させる
    /// （継続リーク防止）。
    func enqueue(_ message: HostMessage, generation: UInt64)
    /// session を破棄し、キュー済み・実行中の全ジョブを **一度だけ** `cancelled` で完了させる。冪等。
    func endSession()
}

// MARK: - Bridge 本体

/// SwiftUI の `.translationTask` ホストと `AppleTranslationProvider`（actor）を橋渡しする
/// `@MainActor` オブジェクト兼ライフサイクル状態機械。
///
/// - `configuration`: `.translationTask(configuration:)` の駆動値。`setLanguages` で更新すると
///   ホスト view の closure が（再）起動し、新しい `TranslationSession` が渡される。
/// - `runDrainLoop(bridge:session:)`: ホスト view が closure 内で直接呼ぶ static。session を
///   **closure の外に一切出さず**、キューを drain して翻訳/DL 同意を処理する（§8.2 / D-15）。
///   非 Sendable な `TranslationSession` を closure の isolation region から出さないため、
///   インスタンスメソッドではなく nonisolated static にする。
///
/// **ライフサイクル不変条件（codex MAJOR-1/2 対応）**:
/// - ジョブは世代付きで登録し、`pendingQueue`（未処理）/ `inFlight`（処理中）で追跡する。
/// - 完了はすべて MainActor 上の `fire(_:_:)` を通し、`inFlight`/`pendingQueue` からの除去を
///   once-guard として二重 resume を防ぐ。
/// - `endSession()` は世代を進め、残存する全ジョブを `cancelled` で完了させる（継続リークゼロ）。
/// - `awaitReady` は closure が `beginDrain()` で ready 通知するまで待ち、host 未マウント時は
///   timeout で fail-closed。
@MainActor
@Observable
public final class TranslationSessionBridge: AppleTranslationHosting {
    /// `.translationTask(configuration:)` の駆動値。UI からは読み取り専用。
    public private(set) var configuration: TranslationSession.Configuration?

    // 以降はライフサイクル内部状態（観測不要）。
    @ObservationIgnored private var currentGeneration: UInt64 = 0
    @ObservationIgnored private var readyGeneration: UInt64?
    @ObservationIgnored private var idCounter: UInt64 = 0
    @ObservationIgnored private var pendingQueue: [JobEnvelope] = []
    @ObservationIgnored private var inFlight: [UInt64: JobEnvelope] = [:]
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// 世代付きのジョブ封筒。`inFlight` から nonisolated drain ループへ返すため Sendable。
    private struct JobEnvelope: Sendable {
        let id: UInt64
        let generation: UInt64
        let message: HostMessage
    }

    // MARK: AppleTranslationHosting

    /// codex 再レビュー MAJOR 対応: 同一言語ペアの再設定は `Configuration` を素朴に作り直すだけでは
    /// `.translationTask` が再走しない恐れがある（`Configuration` は `Equatable` で `version` を含み、
    /// 同一 source/target でも別世代を示したいなら Apple 推奨の `invalidate()` で version を進める
    /// 必要がある）。また、世代を supersede する際に旧世代の queued/in-flight ジョブを放置すると
    /// 二度と drain されず continuation リークになるため、ここで endSession と同じ経路で解放する。
    func setLanguages(source: Locale.Language, target: Locale.Language) -> UInt64 {
        cancelOutstandingJobs()
        currentGeneration &+= 1
        readyGeneration = nil
        if var existing = configuration, existing.source == source, existing.target == target {
            existing.invalidate()
            configuration = existing
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
        signalWake()   // 旧世代 drain ループを起こして失効・離脱させる。
        return currentGeneration
    }

    func awaitReady(generation: UInt64, timeout: Duration) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if readyGeneration == generation { return }
            if generation != currentGeneration {
                throw TranslationProviderError.providerError("translation session superseded before ready")
            }
            if ContinuousClock.now >= deadline {
                throw TranslationProviderError.providerError("translation host did not become ready within \(timeout)")
            }
            // MainActor を明け渡し、closure の beginDrain() が ready を立てる隙を作る。
            // codex 再レビュー MAJOR 対応: `try?` で CancellationError を握り潰すと、キャンセル後も
            // deadline まで MainActor を占有する busy-spin になる。`try await` にしてキャンセルを
            // 呼び出し元へ素直に伝播させる。
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func enqueue(_ message: HostMessage, generation: UInt64) {
        // 世代失効 or session 破棄済みなら即キャンセル完了（継続リーク防止）。
        guard generation == currentGeneration, configuration != nil else {
            fire(JobEnvelope(id: nextID(), generation: generation, message: message), .cancelled)
            return
        }
        pendingQueue.append(JobEnvelope(id: nextID(), generation: generation, message: message))
        signalWake()
    }

    func endSession() {
        currentGeneration &+= 1     // 以降のジョブ受理と旧 drain ループを無効化。
        configuration = nil
        readyGeneration = nil
        cancelOutstandingJobs()
        signalWake()                // 待機中の drain ループ / nextJob を起こす。
    }

    /// pendingQueue + inFlight の全件を一度だけ `.cancelled` で完了させる（continuation リーク防止）。
    /// `endSession`（teardown）と `setLanguages`（世代 supersede）の双方から呼ぶ共通経路。
    private func cancelOutstandingJobs() {
        let queued = pendingQueue
        let flying = Array(inFlight.values)
        pendingQueue.removeAll()
        inFlight.removeAll()
        for env in queued { fire(env, .cancelled) }
        for env in flying { fire(env, .cancelled) }
    }

    /// closure 構築時（`TranslationHostView.body` の MainActor 同期読み取り）に読む世代スナップショット。
    /// `configuration` と `currentGeneration` は `setLanguages`/`endSession` 内で await を挟まず
    /// 同時に更新されるため、この2値は常に一致した状態で観測される（MainActor が直列化する）。
    ///
    /// `TranslationSession.Configuration` 自体は `Sendable` ではないため、nonisolated な
    /// drain ループ（`runDrainLoop`）へ越境させて `beginDrain` に渡すことはできない
    /// （Swift 6 の sending 越境チェックに引っかかる）。`UInt64` の世代番号だけを渡すことで、
    /// 素の値型のみが actor↔MainActor 境界を越える設計（§0 訂正 #1）を破らずに済む。
    var generationSnapshot: UInt64 { currentGeneration }

    // MARK: drain ループ（ホスト closure から呼ぶ）

    /// closure 起動時に呼ぶ。**渡された `expectedGeneration` が現在の `currentGeneration` と一致する
    /// 場合のみ** ready を通知し、その世代を返す。不一致（= closure が構築されてから呼ばれるまでの
    /// 間に別の `setLanguages`/`endSession` で supersede 済み）なら `nil` を返し、drain ループは
    /// 一度も session を使わずに終了する。
    ///
    /// codex 再レビュー BLOCKER 対応: closure 実行が MainActor hop で遅延した **旧** closure が、
    /// もし `currentGeneration` を実行時に直接読んでいたら「たまたま」現在の世代と一致してしまい、
    /// 古い（=もう無効な）`TranslationSession` を新世代のジョブに使ってしまう恐れがある（Apple
    /// ドキュメント上、configuration 変更後に古い session を使うのは fatal）。`expectedGeneration`
    /// は closure 構築時点（= `TranslationHostView.body` の同期読み取り）に固定されたスナップショット
    /// なので、実行時にどれだけ遅延しても「この closure が起動された時点の世代」を正しく表す。
    private func beginDrain(expectedGeneration: UInt64) -> UInt64? {
        guard expectedGeneration == currentGeneration, configuration != nil else { return nil }
        readyGeneration = expectedGeneration
        signalWake()
        return expectedGeneration
    }

    /// 次のジョブを1件取り出して `inFlight` へ移す。世代失効・session 破棄・task キャンセルで
    /// `nil`（drain ループ終了）。
    private func nextJob(generation: UInt64) async -> JobEnvelope? {
        while true {
            // codex 再レビュー BLOCKER 対応: View 消失等で closure の Task がキャンセルされた場合、
            // ジョブが来ないまま `waitForWake()` に取り残されないよう明示的に確認する。
            if Task.isCancelled { return nil }
            if generation != currentGeneration { return nil }
            // session 破棄済み（teardown 後に起動した drain ループ等）は待たずに終了する。
            if configuration == nil { return nil }
            if let index = pendingQueue.firstIndex(where: { $0.generation == generation }) {
                let envelope = pendingQueue.remove(at: index)
                inFlight[envelope.id] = envelope
                return envelope
            }
            await waitForWake()
        }
    }

    /// drain ループの処理結果を反映する。既に完了済み（teardown 済み）なら no-op（once-guard）。
    private func finish(id: UInt64, outcome: JobOutcome) {
        guard let envelope = inFlight.removeValue(forKey: id) else { return }
        fire(envelope, outcome)
    }

    /// `runDrainLoop` がループを抜けた直後に必ず呼ぶ後始末（codex 再レビュー [NEW] 対応）。
    ///
    /// ループが終了する理由は2通りある: (1) 別の `setLanguages`/`endSession` による世代
    /// supersede（この場合 `generation != currentGeneration` になっており、supersede した側が
    /// すでに `cancelOutstandingJobs()`/`configuration = nil` 等の後始末を済ませているので
    /// ここでは no-op）、(2) View 消失等による **task cancellation**（この場合
    /// `generation == currentGeneration` のまま誰も後始末していない）。
    ///
    /// (2) を放置すると、`configuration`/`readyGeneration` が有効なまま残り、この世代への
    /// 以降の `enqueue` が「受理はされるが誰も drain しない」状態になって continuation が
    /// 永久に完了しない。`configuration = nil` にすることで `enqueue` の fail-closed guard
    /// （`configuration != nil` 要求）が働き、以降のジョブは即座に `.cancelled` になる。
    private func drainEnded(generation: UInt64) {
        guard generation == currentGeneration else { return }   // 既に別経路で処理済み。
        configuration = nil
        readyGeneration = nil
        cancelOutstandingJobs()
    }

    /// ホスト view が `.translationTask` closure 内で直接呼ぶ常駐 drain ループ。
    /// session はこのメソッド内（= closure スコープ）だけで使い、外へ持ち出さない。
    /// action closure と同じ nonisolated 文脈で動かし、非 Sendable session を越境させない。
    ///
    /// - Parameter expectedGeneration: この closure 構築時（`TranslationHostView.body` の
    ///   MainActor 同期読み取り）に読んだ世代スナップショット（`bridge.generationSnapshot`）。
    ///   `beginDrain` がこれを実行時点の `currentGeneration` と突き合わせて、この closure が
    ///   今も現行世代かを確認する（BLOCKER 対応。`TranslationSession.Configuration` は
    ///   `Sendable` でないため、越境させられる `UInt64` を代わりに使う）。
    nonisolated static func runDrainLoop(
        bridge: TranslationSessionBridge,
        session: some AppleTranslationSession,
        expectedGeneration: UInt64
    ) async {
        guard let generation = await bridge.beginDrain(expectedGeneration: expectedGeneration) else {
            return   // 起動までの間に supersede 済み。session は一度も使わず終了。
        }
        while let envelope = await bridge.nextJob(generation: generation) {
            let outcome: JobOutcome
            switch envelope.message {
            case .prepareOnly:
                do {
                    try await session.prepareTranslation()
                    outcome = .prepared
                } catch is CancellationError {
                    outcome = .cancelled
                } catch {
                    // DL 同意/準備の失敗は「モデル未 DL」に正規化（契約 error 化, MAJOR-4）。
                    outcome = .failure(.modelNotDownloaded)
                }
            case .job(let requests, _, _):
                do {
                    let responses = try await session.translate(requests)
                    outcome = .responses(responses)
                } catch is CancellationError {
                    outcome = .cancelled
                } catch {
                    // 翻訳失敗は providerError に正規化（契約 error 化, MAJOR-4）。
                    outcome = .failure(.providerError(String(describing: error)))
                }
            }
            await bridge.finish(id: envelope.id, outcome: outcome)
        }
        // codex 再レビュー [NEW] 対応: ループが（世代 supersede 以外の理由 = task cancellation で）
        // 終了した場合、`readyGeneration`/`configuration` を放置すると、この世代への `enqueue` は
        // 今後も受理され続けるが、drain ループはもう存在しないため continuation が永久に完了しない。
        await bridge.drainEnded(generation: generation)
    }

    // MARK: 完了発火（once-guard は inFlight/pendingQueue からの除去で担保）

    private func fire(_ envelope: JobEnvelope, _ outcome: JobOutcome) {
        switch envelope.message {
        case .job(_, let resume, let fail):
            switch outcome {
            case .responses(let responses): resume(responses)
            case .cancelled: fail(CancellationError())
            case .failure(let error): fail(error)
            case .prepared: fail(TranslationProviderError.providerError("unexpected prepared outcome for job"))
            }
        case .prepareOnly(let completion):
            switch outcome {
            case .prepared: completion(nil)
            case .cancelled: completion(CancellationError())
            case .failure(let error): completion(error)
            case .responses: completion(TranslationProviderError.providerError("unexpected responses outcome for prepareOnly"))
            }
        }
    }

    // MARK: wake / id

    private func nextID() -> UInt64 {
        idCounter &+= 1
        return idCounter
    }

    /// codex 再レビュー BLOCKER 対応: 待機中に呼び出し元 Task がキャンセルされた場合（View 消失等で
    /// `.translationTask` の action task が cancel されたが、`endSession`/`setLanguages` のような
    /// 明示的な `signalWake()` が二度と来ない場合）、`waitForWake` に取り残されないよう
    /// `withTaskCancellationHandler` で cancel を検知し、全 waiter を起こす。起きた側は
    /// `nextJob` の `Task.isCancelled` チェックで自分がキャンセルされていれば即座に抜ける。
    private func waitForWake() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters.append(continuation)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.signalWake() }
        }
    }

    private func signalWake() {
        guard !waiters.isEmpty else { return }
        let current = waiters
        waiters.removeAll()
        for continuation in current { continuation.resume() }
    }
}
