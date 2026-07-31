import SwiftUI
import Translation

/// 実 `TranslationSession` を `AppleTranslationSession` 抽象に適合させるアダプタ。
///
/// `TranslationSession.Request` の生成と `Response` の読み出しは **この nonisolated スコープ内
/// （= `.translationTask` closure 内）だけ**で行う。境界を越えるのは素の String 値だけ
/// （`docs/translation-architecture.md` §0 訂正 #1）。`TranslationSession` は非 Sendable なので
/// この struct も nonisolated のまま closure 内に閉じる。
struct LiveTranslationSession: AppleTranslationSession {
    let session: TranslationSession

    func prepareTranslation() async throws {
        try await session.prepareTranslation()
    }

    func translate(_ requests: [AppleTranslationRequest]) async throws -> [AppleTranslationResponse] {
        // Request は closure 内で生成（持ち出さない）。clientIdentifier で順序逆転に対応。
        let batch = requests.map {
            TranslationSession.Request(sourceText: $0.sourceText, clientIdentifier: $0.clientID)
        }
        var responses: [AppleTranslationResponse] = []
        for try await response in session.translate(batch: batch) {
            responses.append(
                AppleTranslationResponse(
                    targetText: response.targetText,
                    clientID: response.clientIdentifier ?? ""
                )
            )
        }
        return responses
    }
}

/// `.translationTask` を保持する不可視のホスト View。
///
/// アプリのルートに常駐させ（録音画面の有無に依存しない）、`bridge.configuration` の変化で
/// closure を（再）起動して `TranslationSession` を受け取る。session は `bridge.run(with:)` の
/// drain ループ内に閉じ込め、closure の外へ出さない（`docs/…` §8.2 / D-15）。
///
/// ```swift
/// RootView().background(TranslationHostView(bridge: deps.translationSessionBridge))
/// ```
///
/// > サイズ 0 の不可視ホストで `prepareTranslation()` の DL 同意シートが前面表示されるかは
/// > 実機 PoC 項目（`docs/translation-architecture.md` §14.3）。
public struct TranslationHostView: View {
    private let bridge: TranslationSessionBridge

    public init(bridge: TranslationSessionBridge) {
        self.bridge = bridge
    }

    public var body: some View {
        // `.translationTask` の id（`expected`）と drain ループへ渡す世代スナップショット
        // （`expectedGeneration`）は、同じ MainActor 同期区間で一度だけ読む（codex 再レビュー
        // BLOCKER 対応）。`configuration`/`currentGeneration` は bridge 側で await を挟まず
        // 同時に更新されるため、この2値は常に一致した状態で観測できる。`expectedGeneration`
        // （`Sendable` な `UInt64`）を closure に持たせることで、`beginDrain` 側でこの closure が
        // 今も現行世代かを検証できる（`TranslationSession.Configuration` 自体は `Sendable` でない
        // ため、これを nonisolated 文脈へ越境させることはできない）。
        let expected = bridge.configuration
        let expectedGeneration = bridge.generationSnapshot
        return Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            // `@Sendable` を付けて closure を nonisolated 化する。これで `session`（非 Sendable
            // な `TranslationSession`）が MainActor 隔離ではなく nonisolated ローカルになり、
            // nonisolated な session メソッド（`prepareTranslation` / `translate(batch:)`）を
            // データ競合なく呼べる。session はこの closure スコープ内に閉じ込める（§0 訂正 #1）。
            // drain ループは static `runDrainLoop` を直接呼ぶ（`LiveTranslationSession` を
            // `sending` で closure region ごと移し、インスタンスメソッド経由の region 分割を避ける）。
            .translationTask(expected) { @Sendable session in
                await TranslationSessionBridge.runDrainLoop(
                    bridge: bridge,
                    session: LiveTranslationSession(session: session),
                    expectedGeneration: expectedGeneration
                )
            }
    }
}
