import SwiftUI
import Translation

// MARK: - actor↔MainActor 境界を越える値型（String だけ）

/// 翻訳リクエストの素の値。`docs/translation-architecture.md` §0 訂正 #1 に従い、
/// actor↔MainActor 境界を越えるのは `TranslationSession.Request` そのものではなく **素の String**
/// だけにする。`TranslationSession.Request` の生成は `.translationTask` closure（MainActor）内
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

/// 常駐ホストの drain ループへ渡すメッセージ。actor（provider）→ MainActor（ホスト）へ渡るため
/// `Sendable`。境界を越えるペイロードは素の値型（`AppleTranslationRequest`）と、`CheckedContinuation`
/// を再開する `@Sendable` クロージャのみ（`CheckedContinuation` は `Sendable`）。
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

// MARK: - provider ↔ ホストの結線（provider をユニットテスト可能にする seam）

/// `AppleTranslationProvider`（actor）がホストへ委譲する操作。
///
/// 実体は `TranslationSessionBridge`。テストではモックホストを注入し、実 Translation
/// フレームワーク非依存で provider の `prepare` 分岐・`translateStream`・`teardown` を検証する。
/// ホストは MainActor 隔離なので存在 existential も `Sendable`（actor から安全に握れる）。
@MainActor
protocol AppleTranslationHosting: AnyObject, Sendable {
    /// 言語ペアを設定する（= `.translationTask` の再走トリガー）。
    func setLanguages(source: Locale.Language, target: Locale.Language)
    /// ジョブ / DL 同意メッセージを drain ループへ積む。
    func enqueue(_ message: HostMessage)
    /// `Configuration` を手放して session を破棄する（teardown）。
    func clearConfiguration()
}

// MARK: - Bridge 本体

/// SwiftUI の `.translationTask` ホストと `AppleTranslationProvider`（actor）を橋渡しする
/// `@MainActor` オブジェクト。
///
/// - `configuration`: `.translationTask(configuration:)` の駆動値。`setLanguages` で更新すると
///   ホスト view の closure が（再）起動し、新しい `TranslationSession` が渡される。
/// - `runDrainLoop(messages:session:)`: ホスト view が closure 内で直接呼ぶ static。session を
///   **closure の外に一切出さず**、メッセージストリームを drain して翻訳/DL 同意を処理する
///   常駐ループ（`docs/…` §8.2 / D-15）。非 Sendable な `TranslationSession` を closure の
///   isolation region から出さないため、インスタンスメソッドではなく nonisolated static にする。
///
/// メッセージは `.unbounded` バッファのストリームに積む。`setLanguages` 直後の `enqueue` が
/// 新 closure の起動前に来ても、バッファに滞留し新 closure の drain ループが取りこぼさない
/// （§0 訂正 #5 のレース緩和）。
///
/// > 未検証（実機 PoC）: `.translationTask` closure が config 変更で再走した際の、単一
/// > メッセージストリームに対する旧/新 drain ループの同時消費挙動は `AsyncStream` の
/// > 単一コンシューマ前提を外れうる。`docs/translation-architecture.md` §0 訂正 #2 / §14.6。
@MainActor
@Observable
public final class TranslationSessionBridge: AppleTranslationHosting {
    /// `.translationTask(configuration:)` の駆動値。UI からは読み取り専用。
    public private(set) var configuration: TranslationSession.Configuration?

    // AsyncStream とその Continuation は Sendable。nonisolated let にして nonisolated な
    // drain ループ（run/runDrainLoop）から安全に読めるようにする。
    nonisolated private let messages: AsyncStream<HostMessage>
    nonisolated private let continuation: AsyncStream<HostMessage>.Continuation

    public init() {
        (messages, continuation) = AsyncStream<HostMessage>.makeStream(bufferingPolicy: .unbounded)
    }

    // MARK: AppleTranslationHosting

    public func setLanguages(source: Locale.Language, target: Locale.Language) {
        configuration = TranslationSession.Configuration(source: source, target: target)
    }

    public func clearConfiguration() {
        configuration = nil
    }

    nonisolated func enqueue(_ message: HostMessage) {
        continuation.yield(message)
    }

    // MARK: drain ループ

    /// drain ループが消費するメッセージストリーム。ホスト closure から直接 `runDrainLoop`
    /// へ渡すための nonisolated アクセサ（`AsyncStream` は Sendable）。
    nonisolated var hostMessages: AsyncStream<HostMessage> { messages }

    /// テスト可能な純粋 drain ロジック。メッセージを順に処理し、ストリーム終了で戻る
    /// （teardown 相当）。session への呼び出し順序と応答の受け渡しをここで保証する。
    nonisolated static func runDrainLoop(
        messages: AsyncStream<HostMessage>,
        session: some AppleTranslationSession
    ) async {
        for await message in messages {
            switch message {
            case .prepareOnly(let completion):
                do {
                    try await session.prepareTranslation()
                    completion(nil)
                } catch {
                    completion(error)
                }
            case .job(let requests, let resume, let fail):
                do {
                    let responses = try await session.translate(requests)
                    resume(responses)
                } catch {
                    fail(error)
                }
            }
        }
    }
}
