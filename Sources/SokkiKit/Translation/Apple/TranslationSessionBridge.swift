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

    func setLanguages(source: Locale.Language, target: Locale.Language) -> UInt64 {
        currentGeneration &+= 1
        readyGeneration = nil
        configuration = TranslationSession.Configuration(source: source, target: target)
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
            try? await Task.sleep(for: .milliseconds(10))
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
        let queued = pendingQueue
        let flying = Array(inFlight.values)
        pendingQueue.removeAll()
        inFlight.removeAll()
        for env in queued { fire(env, .cancelled) }
        for env in flying { fire(env, .cancelled) }
        signalWake()                // 待機中の drain ループ / nextJob を起こす。
    }

    // MARK: drain ループ（ホスト closure から呼ぶ）

    /// closure 起動時に呼ぶ。現行世代を採用して ready を通知し、その世代を返す。
    private func beginDrain() -> UInt64 {
        let generation = currentGeneration
        if configuration != nil { readyGeneration = generation }
        signalWake()
        return generation
    }

    /// 次のジョブを1件取り出して `inFlight` へ移す。世代失効・session 破棄で `nil`（drain ループ終了）。
    private func nextJob(generation: UInt64) async -> JobEnvelope? {
        while true {
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

    /// ホスト view が `.translationTask` closure 内で直接呼ぶ常駐 drain ループ。
    /// session はこのメソッド内（= closure スコープ）だけで使い、外へ持ち出さない。
    /// action closure と同じ nonisolated 文脈で動かし、非 Sendable session を越境させない。
    nonisolated static func runDrainLoop(
        bridge: TranslationSessionBridge,
        session: some AppleTranslationSession
    ) async {
        let generation = await bridge.beginDrain()
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

    private func waitForWake() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func signalWake() {
        guard !waiters.isEmpty else { return }
        let current = waiters
        waiters.removeAll()
        for continuation in current { continuation.resume() }
    }
}
