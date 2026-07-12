import SwiftUI
import SwiftData

@Observable
@MainActor
public final class AppDependencyContainer {
    let captureManager: AudioCaptureManager
    let transcriptionEngine: WhisperKitEngine
    let diarizationEngine: SpeakerKitEngine
    let speakerProfileStore: SpeakerProfileStore
    let sessionManager: SessionManager
    var pipeline: TranscriptionPipeline

    // MARK: - 翻訳（TASK-20 / Phase2.5）
    //
    // appleProvider / keychain / makeBYO は TASK-18・TASK-23・TASK-21・TASK-22 の
    // 実装がそれぞれ差し替えるプレースホルダ。現時点では常にプレースホルダ経由で
    // fail-closed（クラウド送信ゼロ）になる。

    /// 翻訳ライフサイクルの所有者。`reconcileTranslation` 経由で設定変更を反映する。
    let translationCoordinator: TranslationCoordinator
    /// アプリが実体化できる（= `makeBYO` が非 nil を返す）BYO クラウド種別。
    /// TASK-21/22 が provider を追加するまでは空集合（登録済み種別なし）。
    let registeredCloudTranslationKinds: Set<TranslationProviderKind> = []

    public init(modelContainer: ModelContainer) {
        // 専用の一時 ModelContext で seed する。既存の `ctx`（下で SpeakerProfileStore へ
        // 渡す）を先に別呼び出しへ渡すと、strict concurrency の region 排他性チェックが
        // 崩れ「sending risks data race」になるため、独立したインスタンスを使う。
        Self.seedAppSettingsIfNeeded(ModelContext(modelContainer))

        let ctx = ModelContext(modelContainer)

        captureManager = AudioCaptureManager()
        transcriptionEngine = WhisperKitEngine()
        diarizationEngine = SpeakerKitEngine()
        speakerProfileStore = SpeakerProfileStore(modelContext: ctx)
        sessionManager = SessionManager(modelContainer: modelContainer)

        pipeline = TranscriptionPipeline(
            captureManager: captureManager,
            transcriptionEngine: transcriptionEngine,
            diarizationEngine: diarizationEngine,
            speakerStore: speakerProfileStore,
            sessionManager: sessionManager
        )

        translationCoordinator = TranslationCoordinator(
            router: TranslationRouter(availability: AvailabilityCache()),
            keychain: PlaceholderAPIKeyChecking(),
            appleProvider: PlaceholderAppleTranslationProvider(),
            makeBYO: { _ in nil }   // TASK-21/22 マージ後、種別ごとに実 provider を返す
        )
    }

    /// 設定変更・録音開始時に呼ぶ。翻訳ライフサイクルを現在の設定へ再評価する
    /// （`TranslationCoordinator.reconcile` の fail-closed 契約に乗る）。
    func reconcileTranslation(_ snapshot: TranslationSettingsSnapshot) async {
        let ctx = TranslationSettingsMapper.routingContext(
            from: snapshot,
            registeredCloudKinds: registeredCloudTranslationKinds
        )
        await translationCoordinator.reconcile(ctx: ctx)
    }

    /// 起動時に `AppSettingsModel` を必ず1件だけ用意する。
    ///
    /// SettingsView / RecordingView の `settings` computed property は「無ければ作る」
    /// フォールバックを持つが、body 評価のたびに呼ばれうる（RecordingView は録音中の
    /// ストリーミング更新で高頻度に再評価される）ため、@Query が反映するまでの間に
    /// 複数回 insert されて `AppSettingsModel` が重複するリスクがある。起動時にここで
    /// 確実に1件 seed しておくことで、View 側のフォールバック経路が実運用で
    /// 発火しないようにする（TASK-20 レビュー指摘）。
    private static func seedAppSettingsIfNeeded(_ ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<AppSettingsModel>())) ?? []
        guard existing.isEmpty else { return }
        ctx.insert(AppSettingsModel())
        try? ctx.save()
    }
}
