import Foundation

/// 翻訳ライフサイクルの所有者（`@MainActor` 状態機械）。
///
/// - `reconcile`: Router で route を解決し、Gate で fail-closed 判定。allow のときだけ
///   provider を生成・`prepare`・pump 起動。
/// - `submitConfirmed`: 確定セグメントを入力ストリームへ。partial は渡さない（送信ゼロ保証）。
/// - `teardown`: provider を確実に閉じる。冪等・並行安全。
///
/// **ライフサイクル契約**: 起動した provider を確実に閉じる責務は所有者（本 Coordinator を
/// 生成した DI コンテナ / Pipeline）にある。録音停止・設定変更・アプリ終了・View 破棄の
/// いずれの契機でも **所有者は明示的に `teardown()` を呼ばねばならない**。`reconcile` は冒頭で
/// 必ず `teardown()` を呼ぶため設定変更経路は自動的に閉じるが、それ以外の破棄契機では
/// `deinit` に頼らず所有者が呼ぶこと（`@MainActor` の async クリーンアップは deinit から
/// 走らせられないため）。
///
/// **並行性**: `reconcile` は複数回・重複して呼ばれうる（設定連打・録音開始と設定変更の競合）。
/// 各 `reconcile` は開始時に世代トークンを採番し、`prepare()` 等の suspension から復帰した
/// 時点で最新世代と照合する。世代不一致なら作りかけの provider を teardown して破棄し、
/// 状態を一切書き換えない。これにより「privacy ON 完了後に旧 privacy OFF 経路が復帰して
/// クラウドを起動する」fail-closed 破れを防ぐ。
///
/// 不変条件: `active != nil` ⟺ 直近に完了した evaluate が `.allow`。クラウド socket は
/// `prepare()`〜`teardown()` の間だけ生存する（`docs/translation-architecture.md` §7 / D-15）。
@MainActor
@Observable
public final class TranslationCoordinator {
    // 2レーン UI バインディング。
    public private(set) var translations: [UUID: TranslationOutput] = [:]
    /// プライバシー透明性バナー（「クラウド送信中」「DL 必要」等）。
    public private(set) var statusBanner: String?
    public private(set) var isCloudActive = false
    /// 直近の起動失敗（provider 未登録・prepare 失敗など）。監査/UI 用。
    public private(set) var lastError: TranslationProviderError?

    private let router: TranslationRouter
    private let keychain: any APIKeyChecking
    /// bridge を握る常駐 Apple provider。
    private let appleProvider: any TranslationProvider
    /// BYO provider のファクトリ。TASK-18/21/22 が provider を1個ずつ差し込む注入点。
    private let makeBYO: (TranslationProviderKind) -> (any TranslationProvider)?

    private var active: (any TranslationProvider)?
    /// prepare 中（active 化前）の provider。teardown / 新 reconcile が即時に閉じられるよう保持する（BLOCKER-2）。
    private var preparingProvider: (any TranslationProvider)?
    private var inputCont: AsyncStream<TranslationInput>.Continuation?
    private var pumpTask: Task<Void, Never>?

    /// 単調増加のリクエスト列。reconcile / teardown の各エントリで採番し、await 復帰点で
    /// 「自分より後に始まった呼び出しがあるか」を照合する。自分より新しい呼び出しがあれば
    /// 作りかけを閉じて離脱し、最新のユーザー設定が必ず勝つようにする（BLOCKER-1）。
    /// 内部クリーンアップ（`closeActive`）はこの列を進めない。進めるのは公開エントリのみ。
    private var requestSeq: UInt64 = 0

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
    ///
    /// 重複呼び出しや所有者の明示 `teardown()` に備え、**入口で `requestSeq` を採番**し、
    /// 各 await 復帰点で「自分より後に始まった reconcile / teardown があるか」を照合する。
    /// あれば以降の処理を放棄する。既存 provider の close は `requestSeq` を進めない内部
    /// `closeActive()` で行うため、自分の req を採番したあとに閉じても req が奪われない。
    /// これにより、旧 reconcile が自身の close の suspension 中に停止し、その間に新しい
    /// reconcile が完走しても、旧 reconcile が復帰時に最新を奪い返せない（BLOCKER-1）。
    public func reconcile(ctx: RoutingContext) async {
        requestSeq &+= 1
        let req = requestSeq

        await closeActive()
        guard req == requestSeq else { return }   // close 中に新しい呼び出しが来たら離脱

        let decision = await router.resolve(ctx)
        guard req == requestSeq else { return }

        guard decision.unavailableReason == nil else {
            statusBanner = decision.unavailableReason
            return
        }

        let gateCtx = TranslationGateContext(
            translationEnabled: ctx.enabled,
            privacyModeEnabled: ctx.privacyMode,
            providerIsOnDevice: decision.isOnDevice,
            isUserExplicitChoice: decision.isUserExplicitChoice,
            hasValidApiKey: decision.isOnDevice
                ? true
                : keychain.hasKey(for: decision.kind.rawValue)
        )

        switch TranslationGate.evaluate(gateCtx) {
        case .denied(let reason):
            statusBanner = bannerFor(reason)   // 原文のみ。クラウド送信ゼロ。
        case .allow:
            await activate(decision: decision, ctx: ctx, req: req)
        }
    }

    private func activate(decision: RoutingDecision, ctx: RoutingContext, req: UInt64) async {
        // provider の実体化。クラウド decision なのに factory が未登録なら fail-closed。
        let provider: any TranslationProvider
        if decision.isOnDevice {
            provider = appleProvider
        } else if let byo = makeBYO(decision.kind) {
            provider = byo
        } else {
            // MAJOR-3: appleProvider への暗黙フォールバックはしない（監査状態の不一致を招く）。
            lastError = .providerError("cloud provider '\(decision.kind.rawValue)' is not registered")
            statusBanner = "翻訳プロバイダを初期化できませんでした"
            return   // active は nil のまま。isCloudActive は false のまま。
        }

        // MAJOR（監査タグ照合）: decision と実 provider の `isOnDevice` が食い違ったら fail-closed。
        // 例: クラウド provider が appleProvider に誤注入され、Gate をオンデバイスとして
        //     迂回して prepare に到達する DI 事故を防ぐ。provider の nonisolated 監査タグを
        //     Gate が信頼した decision と突き合わせ、不一致は起動しない。
        guard provider.isOnDevice == decision.isOnDevice else {
            lastError = .providerError(
                "provider '\(provider.providerID)' isOnDevice=\(provider.isOnDevice) "
                + "mismatches routing decision isOnDevice=\(decision.isOnDevice)"
            )
            statusBanner = "翻訳プロバイダの構成が不正です"
            return
        }

        // BLOCKER-2: prepare 中に teardown / 新 reconcile が来ても即時にソケットを閉じられるよう、
        // active 化前の provider をここで保持する。`closeActive()` が preparing も teardown する。
        preparingProvider = provider

        // prepare は唯一の suspension 点。ここでは共有状態を書き換えず結果だけ判定に持ち帰る。
        enum PrepareOutcome { case ready, needsDownload, failed(Error) }
        let outcome: PrepareOutcome
        do {
            try await provider.prepare(source: ctx.source, target: ctx.target)
            outcome = .ready
        } catch TranslationProviderError.modelNotDownloaded {
            outcome = .needsDownload
        } catch {
            outcome = .failed(error)
        }

        // BLOCKER: prepare 復帰後、最新でなければ作りかけの provider を破棄して離脱。
        // 状態は一切書き換えない（新しい reconcile の結果を上書きしない）。teardown() が既に
        // preparing を閉じている場合もあるが、teardown() は冪等契約なので二重 close は無害。
        guard req == requestSeq else {
            preparingProvider = nil
            await provider.teardown()
            return
        }
        preparingProvider = nil

        switch outcome {
        case .failed(let error):
            lastError = error as? TranslationProviderError
            statusBanner = "翻訳を開始できませんでした: \(error)"
            await provider.teardown()
            return
        case .needsDownload:
            // Apple host が prepareTranslation() の同意 UI をアンカー表示する。起動は続行。
            active = provider
            isCloudActive = !decision.isOnDevice
            statusBanner = "翻訳モデルのダウンロードが必要です"
            startPump(with: provider, req: req)
        case .ready:
            active = provider
            isCloudActive = !decision.isOnDevice
            statusBanner = decision.isOnDevice
                ? nil
                : "\(decision.kind.rawValue) で翻訳中（クラウド送信）"
            startPump(with: provider, req: req)
        }
    }

    /// 入力ストリームを張り、翻訳結果を `translations` に流し込む pump を起動する。
    ///
    /// MAJOR（pump 所有権）: pump に自分の `req` を渡し、出力反映・エラー処理の前に現在の
    /// `requestSeq` と照合する。旧世代 provider の pump が close 待ちの間に生き残っても、
    /// (1) 旧 provider の出力で `translations` を汚さない、(2) 旧 provider の stream error で
    /// 並行起動済みの新 provider を `teardown()` しない。
    private func startPump(with provider: any TranslationProvider, req: UInt64) {
        // #7: 確定セグメントは1行も落とせない。バッファは .unbounded。
        let (stream, cont) = AsyncStream<TranslationInput>.makeStream(bufferingPolicy: .unbounded)
        inputCont = cont
        pumpTask = Task { @MainActor [weak self] in
            let out = await provider.translateStream(stream)
            do {
                for try await o in out {
                    guard let self, req == self.requestSeq else { break }   // 旧世代の出力は反映しない
                    self.translations[o.id] = o
                }
            } catch is CancellationError {
                // teardown による正常終了。
            } catch {
                guard let self, req == self.requestSeq else { return }   // 旧世代の error で新 provider を閉じない
                self.statusBanner = "翻訳エラー: \(error.localizedDescription)"
                await self.teardown()   // ストリームエラーも fail-closed。
            }
        }
    }

    /// Pipeline が確定セグメントを得るたびに呼ぶ。partial は呼ばない。
    public func submitConfirmed(_ input: TranslationInput) {
        inputCont?.yield(input)
    }

    /// 録音停止 / 設定変化 / アプリ終了で呼ぶ。冪等・並行安全。
    ///
    /// `requestSeq` を進めることで、`prepare()` / `closeActive()` suspension 中の進行中
    /// `reconcile` を無効化する。所有者が prepare 停止中に `teardown()`（録音停止・アプリ終了）
    /// を呼んで完了しても、その後 prepare が復帰した際に req 照合で弾かれ、作りかけ provider は
    /// 起動されず破棄される。
    public func teardown() async {
        requestSeq &+= 1   // 最新化: 進行中の reconcile/activate を無効化する。
        await closeActive()
    }

    /// active / preparing provider と入出力を閉じる内部クリーンアップ。**`requestSeq` は進めない**。
    ///
    /// `reconcile` 冒頭の再評価と公開 `teardown()` の両方から呼ぶ。列を進めないため、
    /// 自分の req を採番したあとに呼んでも自分の req が奪われない（BLOCKER-1）。
    ///
    /// MAJOR-1: `active`/`preparingProvider`/`inputCont`/`pumpTask` をローカルへ退避して
    /// **await 前に即 nil クリア** する。これにより (1) 割り込みで再入しても同一 provider を
    /// 二重 teardown しない、(2) await 中に別 `reconcile` が設定した新しい状態を誤って破棄しない。
    ///
    /// BLOCKER-2: prepare 中の `preparingProvider` も閉じ、拒否 / 停止時にクラウド接続が
    /// 残らないようにする。
    ///
    /// #3: fail-closed が最も効くべきエラー時に破れないよう、退避した provider の
    /// `teardown()`（socket/session close）を **最優先** で実行し、入力ストリームの
    /// `finish()` と自タスクの `pumpTask.cancel()` はその後に回す。
    private func closeActive() async {
        let provider = active
        let preparing = preparingProvider
        let cont = inputCont
        let pump = pumpTask
        active = nil
        preparingProvider = nil
        inputCont = nil
        pumpTask = nil
        isCloudActive = false

        await provider?.teardown()    // 最優先: 稼働中 provider の socket/session を閉じる（#3）。
        await preparing?.teardown()   // prepare 中の provider も閉じる（BLOCKER-2）。冪等契約により二重 close は無害。
        cont?.finish()                // 入力ストリームを finish。
        pump?.cancel()                // 最後: pump をキャンセル。
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
