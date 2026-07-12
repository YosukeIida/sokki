import Foundation

/// 翻訳ライフサイクルの所有者（`@MainActor` 状態機械）。
///
/// - `reconcile`: Router で route を解決し、Gate で fail-closed 判定。allow のときだけ
///   provider を生成・`prepare`・pump 起動。
/// - `submitConfirmed`: 確定セグメントを入力ストリームへ。partial は渡さない（送信ゼロ保証）。
/// - `teardown`: provider を確実に閉じる。冪等。
///
/// 不変条件: `active != nil` ⟺ 直近 `evaluate` が `.allow`。クラウド socket は
/// `prepare()`〜`teardown()` の間だけ生存する（`docs/translation-architecture.md` §7 / D-15）。
@MainActor
@Observable
public final class TranslationCoordinator {
    // 2レーン UI バインディング。
    public private(set) var translations: [UUID: TranslationOutput] = [:]
    /// プライバシー透明性バナー（「クラウド送信中」「DL 必要」等）。
    public private(set) var statusBanner: String?
    public private(set) var isCloudActive = false

    private let router: TranslationRouter
    private let keychain: any APIKeyChecking
    /// bridge を握る常駐 Apple provider。
    private let appleProvider: any TranslationProvider
    /// BYO provider のファクトリ。TASK-18/21/22 が provider を1個ずつ差し込む注入点。
    private let makeBYO: (TranslationProviderKind) -> (any TranslationProvider)?

    private var active: (any TranslationProvider)?
    private var inputCont: AsyncStream<TranslationInput>.Continuation?
    private var pumpTask: Task<Void, Never>?

    /// テスト用: provider が起動中か（`active != nil` ⟺ 直近 evaluate が `.allow`）。
    var hasActiveProvider: Bool { active != nil }

    public init(
        router: TranslationRouter,
        keychain: any APIKeyChecking,
        appleProvider: any TranslationProvider,
        makeBYO: @escaping (TranslationProviderKind) -> (any TranslationProvider)?
    ) {
        self.router = router
        self.keychain = keychain
        self.appleProvider = appleProvider
        self.makeBYO = makeBYO
    }

    /// 録音開始時 / 設定変更時に呼ぶ。fail-closed で再評価する。
    public func reconcile(ctx: RoutingContext) async {
        await teardown()
        let decision = await router.resolve(ctx)

        let gateCtx = TranslationGateContext(
            translationEnabled: ctx.enabled,
            privacyModeEnabled: ctx.privacyMode,
            providerIsOnDevice: decision.isOnDevice,
            isUserExplicitChoice: decision.isUserExplicitChoice,
            hasValidApiKey: decision.isOnDevice
                ? true
                : keychain.hasKey(for: decision.kind.rawValue)
        )

        guard decision.unavailableReason == nil else {
            statusBanner = decision.unavailableReason
            return
        }

        switch TranslationGate.evaluate(gateCtx) {
        case .denied(let reason):
            statusBanner = bannerFor(reason)   // 原文のみ。クラウド送信ゼロ。
        case .allow:
            await activate(decision: decision, ctx: ctx)
        }
    }

    private func activate(decision: RoutingDecision, ctx: RoutingContext) async {
        let provider: any TranslationProvider = decision.isOnDevice
            ? appleProvider
            : (makeBYO(decision.kind) ?? appleProvider)

        do {
            try await provider.prepare(source: ctx.source, target: ctx.target)
        } catch TranslationProviderError.modelNotDownloaded {
            // Apple host が prepareTranslation() の同意 UI をアンカー表示する。
            statusBanner = "翻訳モデルのダウンロードが必要です"
        } catch {
            statusBanner = "翻訳を開始できませんでした: \(error)"
            await teardown()
            return
        }

        active = provider
        isCloudActive = !decision.isOnDevice
        statusBanner = decision.isOnDevice
            ? nil
            : "\(decision.kind.rawValue) で翻訳中（クラウド送信）"

        // #7: 確定セグメントは1行も落とせない。バッファは .unbounded。
        let (stream, cont) = AsyncStream<TranslationInput>.makeStream(bufferingPolicy: .unbounded)
        inputCont = cont
        let out = await provider.translateStream(stream)
        pumpTask = Task { @MainActor [weak self] in
            do {
                for try await o in out {
                    self?.translations[o.id] = o
                }
            } catch is CancellationError {
                // teardown による正常終了。
            } catch {
                self?.statusBanner = "翻訳エラー: \(error.localizedDescription)"
                await self?.teardown()   // ストリームエラーも fail-closed。
            }
        }
    }

    /// Pipeline が確定セグメントを得るたびに呼ぶ。partial は呼ばない。
    public func submitConfirmed(_ input: TranslationInput) {
        inputCont?.yield(input)
    }

    /// 録音停止 / 設定変化 / アプリ終了で呼ぶ。冪等。
    ///
    /// #3: fail-closed が最も効くべきエラー時に破れないよう、クラウド socket の
    /// クローズ（`active.teardown()`）を **最優先** で実行し、自タスクの
    /// `pumpTask.cancel()` は **最後** に回す（自己キャンセルが socket close を
    /// 先取り中断するのを防ぐ）。
    public func teardown() async {
        if let a = active { await a.teardown() }   // 最優先: socket/session を閉じる。
        inputCont?.finish()
        inputCont = nil
        active = nil
        isCloudActive = false
        pumpTask?.cancel()                          // 最後: 自タスクをキャンセル。
        pumpTask = nil
    }

    private func bannerFor(_ reason: TranslationDecision.DenyReason) -> String? {
        switch reason {
        case .toggleOff:
            return nil
        case .privacyBlocksAutoCloud:
            return "プライバシーモードのため自動クラウド翻訳は無効です"
        case .missingApiKey:
            return "BYO の API キーを設定してください"
        }
    }
}
