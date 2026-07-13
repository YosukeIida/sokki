# sokki リアルタイム翻訳アーキテクチャ設計（2段構え・切替式）

> 目的: Apple Translation（オンデバイス既定）と BYO key クラウド（Gemini Live / Google Cloud v3）を**実行時に切替・自動ルーティング**し、**プライバシーゲートで fail-closed** にする翻訳基盤の設計。
> 作成: 2026-06-26 / 3案並列 → 統合 → Swift 6 並行性・Apple API 実在性の**敵対的レビュー**（verdict: minor-issues）。
> ステータス: **設計確定。ただし Apple Translation 経路は実機 PoC 必須**（§0・§14 参照）。spec §4.6 / D-14〜D-17 と対。
> **D-18（2026-07-14）により DeepL は撤去済み。以下の DeepL 関連記載は当時の設計検討の履歴として残す（クラウド BYO は Gemini Live のみ）。**

---

## 0. レビューによる訂正・要検証事項（実装前に必読）

敵対的レビューで以下が判明。**本文の設計を実装に移す前に、特に 🔴 の 2 点は実機 PoC で検証すること。** 未検証のまま本文コードを貼ると動かない可能性がある。

### 🔴 high — Apple Translation 経路の2つの未検証前提

1. **`TranslationSession.Request`/`Response` が Sendable とは限らない**
   本文 §8.1 の `Bridge.Job` は `requests: [TranslationSession.Request]` と `resume: @Sendable ([Response]) -> Void` を `Sendable` struct に格納する前提だが、**Request/Response の Sendable 準拠は未確認**。`TranslationSession` 周辺型は `@MainActor` 隔離の可能性があり、非 Sendable なら strict concurrency でコンパイル不能。
   → **修正方針**: actor↔MainActor 境界を越えるのは **`Request`/`Response` オブジェクトではなく素の値**（`(sourceText: String, clientID: String)` と `(targetText: String, clientID: String)`）にする。`TranslationSession.Request` の生成と `Response` の読み出しは **`.translationTask` closure 内（MainActor）でのみ**行い、境界は String だけが渡る形に変える。実際の Swift 6 エラーは「main actor-isolated session を @concurrent な `translate(batch:)` に渡すと data race」という形で出る（Apple forum 816900）ので、session を一切外に出さない本設計の方向は正しいが、**Job の中身を値型に限定する**こと。

2. **「常駐ホストの drain ループで session を使い回す」は出典上未確証**
   本文 §8.2 / D-15 は `.translationTask` closure 内に `for await _ in wake { session.translate(...) }` の長時間ループを置き、アプリ生存中ずっと多数の翻訳を発行する設計。だが裏取りできたのは**単一 `translate(batch:)` の AsyncSequence を反復する**ところまでで、**1つの closure から独立した translate を無限に発行し続けられるか**は未確証。closure は configuration 単位で完結する設計かもしれず、その場合 §14.6 の「config 変更で closure 再走→ループ断絶」が常態化する。
   → **実機 PoC で必ず検証**。成立しない場合のフォールバック: 翻訳ジョブごとに `Configuration` を更新して closure を再走させる（レイテンシは上がる）か、短窓デバウンスで `translate(batch:)` を1回呼ぶ単位に設計し直す。**この検証が翻訳機能全体の前提**。

### 🟡 medium

3. **fail-closed の穴（teardown のエラー経路）**: 本文 §7 で stream エラー時に `pumpTask` の catch から `teardown()` を呼ぶが、`teardown()` 内の `pumpTask?.cancel()` は**実行中の自分自身をキャンセル**する。`await a.teardown()`（socket close）の前に中断が観測されると **クラウド socket が開いたまま残る**恐れ（fail-closed が最も効くべきエラー時に破れる）。
   → **修正**: socket クローズを最優先（`teardown` 冒頭で `await active?.teardown()` を先に）し、自タスクの cancel は最後に。または teardown を `Task.detached` で実行して自己キャンセルの影響を断つ。

4. **missing-key の二重判定**: Router の `unavailableReason="API キー未設定"` と Gate の `.missingApiKey` が同条件を二重に持ち drift しうる。Router は早期 return するため Gate の missingApiKey 経路が実行されないことがある。
   → 判定を **Gate に一本化**（Router は route だけ返し、key 有無は Gate）。また `hasValidApiKey` は**存在チェックのみ**で、失効/無効キーは検出されない（無効キーで送信が試行され `connectionFailed` で初めて露呈）。キー検証 API（プロバイダ提供の usage/検証エンドポイント等）を prepare 時に任意で。

5. **prepareOnly の race**: `bridge.setLanguages`（config 変更）直後に `enqueue(.prepareOnly)`+`wake` を送ると、**新しい translationTask closure が起動する前**に wake が消費され、旧 closure に流れる/取りこぼす可能性。
   → config 変更後は新 closure が wake を待ち受けてから enqueue する同期（世代カウンタ or closure 起動通知）を入れる。

6. **ObservableObject と @Observable の混在**: 本文 Bridge は `ObservableObject + @Published` だが、sokki の規約は `@Observable` マクロ。非 published 格納プロパティ（inbox/wakeCont）の MainActor 隔離保証が弱い。
   → Bridge も `@Observable` か、明示 `@MainActor final class` に統一。

### 🟢 low

7. **`.bufferingNewest(32)` は誤り**: 確定セグメントは1行も落とせない（落とすと訳文レーンに恒久的な穴）。「新しい者勝ち」は transcript に不適。
   → **`.unbounded` か `.bufferingOldest`**、または明示キューで取りこぼしを出さない。

8. **Google Cloud Translation v3 の認証が誤り**: 本文 §9.2 は `Authorization: Bearer <APIキー>` だが、v3 (`projects.translateText`) は **OAuth2 アクセストークン / サービスアカウント**が必要（生 API キーは `?key=` の v2 用）。サービスアカウント JSON→署名 JWT→トークン交換が未設計で、このままでは動かない。
   → BYO の現実解は **Gemini（キーがシンプル）** を先に。Google v3 を使うなら OAuth2/SA トークン取得を別途設計（DeepL は D-18 で撤去済み）。

> 総評（verdict: minor-issues）: ルーティング/Gate/Coordinator の骨格と「session を closure 外に出さない」方向性はレビューで**妥当と確認**。リスクは Apple Translation のヘッドレス運用（#1, #2）に集中しており、**最初の実装ステップは Apple 経路の最小 PoC（実機・1ペア翻訳 + DL 同意 UI）**にすべき。Gate/Router は実機なしでユニットテストできるので先行可能。

---

<!-- ===== 統合設計本文（敵対的レビュー前の推奨設計。§0 の訂正が優先） ===== -->

# sokki リアルタイム翻訳アーキテクチャ 最終推奨設計

3案を統合した sokki 向け推奨アーキテクチャです。実 API 検証（WebSearch/WebFetch）の結果、**最大の争点だった「TranslationSession をクロージャ外に持ち出してよいか」は明確に NG** と確定したため、その制約を満たす案（案2/案3 系）を基準にし、案1の最小 protocol・id エコーバック・テスタビリティを採り入れています。

---

## 0. 採否サマリ（3案の統合判断）

| 論点 | 採用 | 理由 |
|---|---|---|
| protocol 形状 | **案1（最小）+ 案3の `teardown()`/`providerID`** | 知能は Coordinator/Gate/Router に集約。provider は変換とリソース管理だけ。`teardown()` は WebSocket/URLSession の確実クローズに必須。 |
| プライバシー判定 | **案3（純粋関数 `TranslationGate`, fail-closed）** | クラウド送信可否を単一の純粋関数に一元化。実機なしで真理値表を全網羅テストできる。監査点が1つ。 |
| 2段ルーティング | **案2（`RoutingContext`/`RoutingDecision` + `AvailabilityCache`）** | 言語ペア判定を副作用ゼロの `resolve()` に切り出し、status をキャッシュ。テスト容易。 |
| Apple session 供給 | **案2/案3 の「常駐ホスト + クロージャ内 drain」**（案1の per-batch continuation hop は**却下**） | 実 API 検証で「session をクロージャ外で使うと fatal error」が確定。案1の `runBatch` 方式は session を closure 外の continuation から触る形になり危険。session は closure 内に閉じ込め、ジョブを AsyncStream で流し込む。 |
| ライフサイクル | **案3（allow のときだけ生成、不許可で即 teardown）** | 「クラウド接続を長命にしない」= プライバシー要件の構造的担保。 |
| id 対応付け | **案1（`clientID` エコーバック）+ Apple `translate(batch:)` の `clientIdentifier`** | 実 API が順序逆転前提で `clientIdentifier` を提供。原文/訳文 2レーンの行対応に直結。 |
| key 保管 | **案3（Keychain 単一アクセス点）** | SwiftData 平文保存を避ける。`AppSettingsModel.translationApiKey` は廃止し Keychain へ。 |
| 役割分担の所有者 | **案3 `TranslationCoordinator`（@MainActor 状態機械）** | SwiftUI ホスト・@Observable UI バインディングと同じ MainActor に置くのが自然。 |

---

## 1. 検証済みの実 API（裏取り結果）

macOS 15+ / Apple Silicon 実機専用（シミュレータ不可）。

- `TranslationSession` は**公開イニシャライザを持たない**。`.translationTask(_ configuration:, action:)`（SwiftUI View modifier）の action クロージャ引数としてのみ取得。
- **`TranslationSession` をホスト view の生存期間外で使うと fatal error**（Apple 明言）。永続モデルや actor に保存してはならない。正しい再翻訳トリガーは「`Configuration` を変える / `Configuration.invalidate()` を呼ぶ」で closure を再走させること。
- **closure 内に長時間ループを置いてよい**（`for try await` で複数翻訳を順次処理する例が公式・polpiella にある）。view が生きている限り session は有効。→ **常駐ホスト + ジョブ drain ループ**が正攻法。
- `session.translate(batch:)` は `Request` の列を受け、応答が出来次第 `AsyncSequence<Response>` で返す（throwing）。`Request(sourceText:clientIdentifier:)` / `Response.targetText` / `Response.clientIdentifier`。**応答は要求と異なる順序で来る**ため `clientIdentifier` で対応付ける。1バッチは同一ソース言語前提。
- `session.translate(_ text:) async throws -> Response`（単発）。
- `session.prepareTranslation() async throws`（翻訳せずモデル DL 同意 UI のみ。ホスト view にアンカー表示）。
- `LanguageAvailability()`（class, 非 Sendable）。`status(from:to:) async -> Status`（`.installed` / `.supported` / `.unsupported`、`@unknown default` 必須）。`supportedLanguages` は async プロパティ。

出典: [Translating text within your app](https://developer.apple.com/documentation/Translation/translating-text-within-your-app) / [translate(batch:)](https://developer.apple.com/documentation/translation/translationsession/translate(batch:)) / [Response.clientIdentifier](https://developer.apple.com/documentation/translation/translationsession/response/clientidentifier) / [TranslationSession](https://developer.apple.com/documentation/translation/translationsession) / [polpiella.dev](https://www.polpiella.dev/swift-translation-api/) / [createwithswift](https://www.createwithswift.com/using-the-translation-framework-for-language-to-language-translation/)

---

## 2. レイヤ構成と結線図

```
┌─────────────────────────────────────────────────────────────────┐
│ TranscriptionPipeline (@MainActor, @Observable)                   │
│   WhisperKit → TranscriptSegment(partial/confirmed)               │
│     partial   → 原文レーンのみ更新（翻訳に渡さない＝送信ゼロ保証）   │
│     confirmed → TranslationInput を Coordinator.submit(_:)         │
└───────────────────────────┬─────────────────────────────────────┘
                            │ TranslationInput (Sendable)
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ TranslationCoordinator (@MainActor, @Observable)  状態機械の所有者  │
│   reconcile(): Router.resolve → Gate.evaluate(純粋)               │
│        .denied → teardown()（原文のみ）                           │
│        .allow  → provider 生成・prepare・pumpTask 起動            │
│   translations[clientID] = TranslationOutput   ← 2レーン UI バインド │
└───────┬───────────────────────────────┬─────────────────────────┘
        │ resolve                        │ allow 時のみ
        ▼                                ▼
┌──────────────────────┐   ┌──────────────────────────────────────┐
│ TranslationRouter      │   │ TranslationProvider (protocol: Actor)  │
│  (actor)               │   │  ├ AppleTranslationProvider (onDevice) │──┐
│  resolve(ctx)→Decision │   │  ├ GeminiLiveProvider     (cloud, WS)  │  │
│  AvailabilityCache     │   │  └ GoogleCloudV3Provider   (cloud,REST)│  │
└──────────────────────┘   └──────────────────────────────────────┘  │
                Apple のみ ▲ ジョブ AsyncStream / 結果 continuation     │
                          │                                            │
              ┌───────────┴───────────────┐                           │
              │ AppleTranslationHost(View) │  ← サイズ0で常駐           │
              │  .translationTask(config){ │     session は closure 内 │
              │     session を drain ループ │     だけで使用             │
              │  }  @MainActor             │                           │
              └────────────────────────────┘                          │
                                                                       │
   TranslationOutput (clientID で原文行に対応付け) ──────────────────────┘
```

データフロー（確定セグメントのみ翻訳・2レーン）:
1. WhisperKit の partial は原文レーンに即時表示するだけ（**翻訳経路に一切入れない**）。
2. `isConfirmed == true` のセグメントだけ `TranslationInput` 化して Coordinator へ。
3. Coordinator が allow なら provider の `translateStream` を購読、`TranslationOutput` を `translations[clientID]` に格納。
4. UI は原文行ごとに `translations[seg.clientID]` を引いて訳文レーンを描画（順序逆転に強い）。

---

## 3. ディレクトリ構成

```
Sources/SokkiKit/Translation/
├── TranslationProvider.swift          # protocol + I/O struct + error
├── TranslationGate.swift              # 純粋関数ゲート（fail-closed の核）★
├── TranslationRouter.swift            # 2段ルーティング + RoutingContext/Decision
├── AvailabilityCache.swift            # LanguageAvailability ラップ + プロトコル化
├── TranslationCoordinator.swift       # @MainActor ライフサイクル所有者 ★
├── Apple/
│   ├── AppleTranslationHost.swift     # 不可視 SwiftUI ホスト + Bridge（@MainActor）
│   └── AppleTranslationProvider.swift # オンデバイス既定（bridge 委譲）
├── BYO/
│   ├── GeminiLiveTranslateClient.swift   # WebSocket
│   ├── GoogleCloudTranslationV3Provider.swift # REST
│   └── PCMConverter.swift             # （Gemini Live 音声経路を使う場合）
└── Mocks/
    └── MockTranslationProvider.swift  # ルーティング/ライフサイクルテスト用
Sources/SokkiKit/Security/
└── KeychainStore.swift                # BYO key 単一アクセス点 ★
```

---

## 4. TranslationProvider protocol（最小 + ライフサイクル）

```swift
import Foundation

/// 翻訳への入力。確定セグメント1件に対応。
public struct TranslationInput: Sendable, Identifiable, Equatable {
    public let id: UUID                  // = clientID。原文セグメントと同一キー
    public let text: String
    public let sourceTime: TimeInterval  // セグメント開始時刻（並び順・行対応の補助）
    public init(id: UUID, text: String, sourceTime: TimeInterval) {
        self.id = id; self.text = text; self.sourceTime = sourceTime
    }
}

/// 翻訳結果。入力 id をエコーバックして UI 側で原文行と突き合わせる。
public struct TranslationOutput: Sendable, Identifiable, Equatable {
    public let id: UUID                  // 対応する TranslationInput.id
    public let translatedText: String
    public let isConcluded: Bool         // true=確定訳（partial 訳は将来用）
    public let sourceTime: TimeInterval
    public init(id: UUID, translatedText: String, isConcluded: Bool, sourceTime: TimeInterval) {
        self.id = id; self.translatedText = translatedText
        self.isConcluded = isConcluded; self.sourceTime = sourceTime
    }
}

public enum TranslationProviderError: Error, Sendable, Equatable {
    case languagePairUnsupported(source: String, target: String)
    case modelNotDownloaded            // Apple: .supported（DL 可能だが未DL）
    case missingAPIKey
    case connectionFailed(String)
    case providerError(String)
}

/// 最小契約。ルーティング/プライバシー/フォールバックは持たない。
/// provider は「自分が呼ばれた＝許可済み」を前提に変換とリソース管理だけ行う。
public protocol TranslationProvider: Actor {
    /// 監査タグ。Gate の入力。クラウド送信を伴うか。
    nonisolated var providerID: String { get }
    nonisolated var isOnDevice: Bool { get }

    /// 言語ペアの準備。対応不可・key 無し・接続失敗は throw。
    func prepare(source: Locale.Language, target: Locale.Language) async throws

    /// 確定セグメントのストリームを翻訳ストリームに変換。
    /// 入力 finish or タスクキャンセルで出力も終了。
    func translateStream(
        _ inputs: AsyncStream<TranslationInput>
    ) -> AsyncThrowingStream<TranslationOutput, Error>

    /// socket/URLSession を確実に閉じる。冪等。
    func teardown() async
}
```

`providerID`/`isOnDevice` を `nonisolated let` にすることで、Gate と Router が actor hop なしに同期参照できます（案1・案3の共通点を採用）。

---

## 5. TranslationGate（プライバシーゲート・純粋関数・fail-closed）

クラウド送信可否を**単一の純粋関数**に閉じ込めます。provider に権限判定を分散させません。

```swift
public struct TranslationGateContext: Sendable, Equatable {
    public let translationEnabled: Bool
    public let privacyModeEnabled: Bool
    public let providerIsOnDevice: Bool
    public let isUserExplicitChoice: Bool   // ユーザーが provider を明示選択したか（auto でない）
    public let hasValidApiKey: Bool         // Keychain 照会結果
}

public enum TranslationDecision: Sendable, Equatable {
    case allow
    case denied(DenyReason)
    public enum DenyReason: String, Sendable, Equatable {
        case toggleOff
        case privacyBlocksAutoCloud   // privacy ON + 自動フォールバックでのクラウド（越権防止）
        case missingApiKey
    }
}

public enum TranslationGate {
    /// 副作用なし・全分岐網羅。テストの主対象。
    public static func evaluate(_ c: TranslationGateContext) -> TranslationDecision {
        // 1. トグル最優先
        guard c.translationEnabled else { return .denied(.toggleOff) }
        // 2. オンデバイスは常に許可（送信が起きない）
        if c.providerIsOnDevice { return .allow }
        // --- 以下クラウドのみ到達 ---
        // 3. key 必須
        guard c.hasValidApiKey else { return .denied(.missingApiKey) }
        // 4. プライバシーモードの扱い:
        //    - ユーザー明示選択 = オプトイン成立 → 許可
        //    - 自動フォールバック（auto から Apple 未対応で BYO に流れた）→ 越権なので拒否
        if c.privacyModeEnabled && !c.isUserExplicitChoice {
            return .denied(.privacyBlocksAutoCloud)
        }
        return .allow
    }
}
```

### プライバシーゲート真理値表（privacyMode × translationEnabled × isOnDevice）

要件「OFF/プライバシー時はクラウド送信ゼロ」「明示オプトイン時のみクラウド」を、案1の「自動 vs 明示の区別」と案3の fail-closed で統合。

| translationEnabled | privacyMode | isOnDevice | 明示選択 | key | 判定 | 送信 |
|:---:|:---:|:---:|:---:|:---:|:---|:---:|
| false | – | – | – | – | `denied(.toggleOff)` | なし |
| true | 任意 | true (Apple) | – | – | **`allow`** | なし(オンデバイス) |
| true | ON | false (BYO) | **明示** | あり | **`allow`**（オプトイン成立） | あり |
| true | ON | false (BYO) | 自動FB | あり | `denied(.privacyBlocksAutoCloud)` | なし |
| true | ON | false (BYO) | 任意 | なし | `denied(.missingApiKey)` | なし |
| true | OFF | false (BYO) | 任意 | あり | **`allow`** | あり |
| true | OFF | false (BYO) | 任意 | なし | `denied(.missingApiKey)` | なし |

要点: **「ユーザー明示選択」と「auto の自動フォールバック」を区別**する。privacy ON でも、ユーザーが provider を明示選択し key を入れた場合だけクラウドを許可（要件の「翻訳トグル ON + BYO key 設定 = オプトイン」）。auto のまま Apple 未対応ペアで黙ってクラウドへ流すのは越権なので privacy ON では拒否する。

---

## 6. TranslationRouter（2段ルーティング・actor）

```swift
import Translation

public enum TranslationProviderKind: String, Sendable, CaseIterable, Codable {
    case auto, apple, geminiLive, googleCloudV3
    public var isOnDeviceImplied: Bool { self == .apple }
}

public struct RoutingContext: Sendable, Equatable {
    public let enabled: Bool
    public let preferred: TranslationProviderKind   // auto を含む
    public let source: Locale.Language
    public let target: Locale.Language
    public let privacyMode: Bool
    public let availableKeys: Set<TranslationProviderKind>     // key が入っている cloud 種別
    public let cloudPreferenceOrder: [TranslationProviderKind] // 自動FBの試行順
}

public struct RoutingDecision: Sendable, Equatable {
    public let kind: TranslationProviderKind        // 実体（auto は解決済み）
    public let isOnDevice: Bool
    public let isUserExplicitChoice: Bool
    public let needsModelDownload: Bool             // Apple .supported
    public let unavailableReason: String?           // ルート不能時
}

public actor TranslationRouter {
    private let availability: any AvailabilityChecking
    public init(availability: any AvailabilityChecking) { self.availability = availability }

    public func resolve(_ ctx: RoutingContext) async -> RoutingDecision {
        guard ctx.enabled else {
            return .init(kind: .auto, isOnDevice: true, isUserExplicitChoice: false,
                         needsModelDownload: false, unavailableReason: nil)  // disabled は Gate.toggleOff で弾く
        }

        // 1. ユーザー明示選択（auto 以外）
        if ctx.preferred != .auto {
            if ctx.preferred == .apple {
                return await resolveApple(ctx, explicit: true)
            }
            // 明示 BYO（key 検証は Gate.hasValidApiKey が担う。ここでは route だけ）
            return .init(kind: ctx.preferred, isOnDevice: false, isUserExplicitChoice: true,
                         needsModelDownload: false,
                         unavailableReason: ctx.availableKeys.contains(ctx.preferred)
                            ? nil : "API キー未設定")
        }

        // 2. auto: まず Apple
        let apple = await resolveApple(ctx, explicit: false)
        if apple.unavailableReason == nil { return apple }

        // 3. auto フォールバック: Apple 未対応 → BYO（自動。Gate が privacy で最終判断）
        let usable = ctx.cloudPreferenceOrder.first { ctx.availableKeys.contains($0) }
        guard let fb = usable else {
            return .init(kind: .auto, isOnDevice: true, isUserExplicitChoice: false,
                         needsModelDownload: false,
                         unavailableReason: "オンデバイス未対応。BYO キーを設定すると翻訳できます")
        }
        return .init(kind: fb, isOnDevice: false, isUserExplicitChoice: false /* ← 自動FB */,
                     needsModelDownload: false, unavailableReason: nil)
    }

    private func resolveApple(_ ctx: RoutingContext, explicit: Bool) async -> RoutingDecision {
        switch await availability.status(from: ctx.source, to: ctx.target) {
        case .installed:
            return .init(kind: .apple, isOnDevice: true, isUserExplicitChoice: explicit,
                         needsModelDownload: false, unavailableReason: nil)
        case .supported:
            return .init(kind: .apple, isOnDevice: true, isUserExplicitChoice: explicit,
                         needsModelDownload: true, unavailableReason: nil)
        case .unsupported:
            return .init(kind: .apple, isOnDevice: true, isUserExplicitChoice: explicit,
                         needsModelDownload: false, unavailableReason: "Apple 未対応の言語ペア")
        @unknown default:
            return .init(kind: .apple, isOnDevice: true, isUserExplicitChoice: explicit,
                         needsModelDownload: false, unavailableReason: "不明な対応状況")  // fail-closed
        }
    }
}
```

ルーティング優先順位: **ユーザー明示選択 → auto の Apple 対応判定 → Apple 未対応なら BYO 自動FB → 不能なら原文のみ**。最終的なクラウド送信可否は Router ではなく Gate が握る（責務分離）。

### AvailabilityCache（プロトコル化してテスト注入可能に）

```swift
public protocol AvailabilityChecking: Sendable {
    func status(from: Locale.Language, to: Locale.Language) async -> LanguageAvailability.Status
    func supportedLanguages() async -> [Locale.Language]
}

public actor AvailabilityCache: AvailabilityChecking {
    private let backing = LanguageAvailability()     // 非 Sendable → actor 内に閉じ込め
    private var cache: [String: LanguageAvailability.Status] = [:]
    private var snapshot: [Locale.Language]?

    private func key(_ f: Locale.Language, _ t: Locale.Language) -> String {
        "\(f.maximalIdentifier)->\(t.maximalIdentifier)"
    }
    public func status(from f: Locale.Language, to t: Locale.Language) async -> LanguageAvailability.Status {
        let k = key(f, t)
        if let c = cache[k] { return c }
        let s = await backing.status(from: f, to: t)
        cache[k] = s; return s
    }
    public func supportedLanguages() async -> [Locale.Language] {
        if let s = snapshot { return s }
        let s = await backing.supportedLanguages; snapshot = s; return s
    }
    public func invalidate(from f: Locale.Language, to t: Locale.Language) { cache[key(f, t)] = nil }
}
```

---

## 7. TranslationCoordinator（@MainActor・ライフサイクル状態機械）

```swift
import Foundation

@MainActor
@Observable
public final class TranslationCoordinator {
    // 2レーン UI バインディング
    public private(set) var translations: [UUID: TranslationOutput] = [:]
    public private(set) var statusBanner: String?          // 「クラウド送信中」「DL 必要」等
    public private(set) var isCloudActive = false

    private let router: TranslationRouter
    private let keychain: KeychainStore
    private let appleProvider: TranslationProvider          // bridge を握る常駐 Apple
    private let makeBYO: (TranslationProviderKind) -> TranslationProvider?

    private var active: TranslationProvider?
    private var inputCont: AsyncStream<TranslationInput>.Continuation?
    private var pumpTask: Task<Void, Never>?

    public init(router: TranslationRouter,
                keychain: KeychainStore,
                appleProvider: TranslationProvider,
                makeBYO: @escaping (TranslationProviderKind) -> TranslationProvider?) {
        self.router = router; self.keychain = keychain
        self.appleProvider = appleProvider; self.makeBYO = makeBYO
    }

    /// 録音開始時 / 設定変更時に呼ぶ。fail-closed で再評価。
    public func reconcile(ctx: RoutingContext) async {
        await teardown()
        let decision = await router.resolve(ctx)

        let gateCtx = TranslationGateContext(
            translationEnabled: ctx.enabled,
            privacyModeEnabled: ctx.privacyMode,
            providerIsOnDevice: decision.isOnDevice,
            isUserExplicitChoice: decision.isUserExplicitChoice,
            hasValidApiKey: decision.isOnDevice ? true
                : keychain.hasKey(for: decision.kind.rawValue))

        guard decision.unavailableReason == nil else {
            statusBanner = decision.unavailableReason; return
        }
        switch TranslationGate.evaluate(gateCtx) {
        case .denied(let r):
            statusBanner = bannerFor(r); return            // 原文のみ。送信ゼロ。
        case .allow:
            await activate(decision: decision, ctx: ctx)
        }
    }

    private func activate(decision: RoutingDecision, ctx: RoutingContext) async {
        let provider: TranslationProvider = decision.isOnDevice
            ? appleProvider
            : (makeBYO(decision.kind) ?? appleProvider)

        do {
            try await provider.prepare(source: ctx.source, target: ctx.target)
        } catch TranslationProviderError.modelNotDownloaded {
            statusBanner = "翻訳モデルのダウンロードが必要です"
            // Apple host が prepareTranslation() の同意 UI を出す（後述）
        } catch {
            statusBanner = "翻訳を開始できませんでした: \(error)"
            await teardown(); return
        }

        active = provider
        isCloudActive = !decision.isOnDevice
        statusBanner = decision.isOnDevice ? nil : "\(decision.kind.rawValue) で翻訳中（クラウド送信）"

        let (stream, cont) = AsyncStream<TranslationInput>.makeStream(
            bufferingPolicy: .bufferingNewest(32))         // バックプレッシャ: 古い未訳を捨てる
        inputCont = cont
        let out = provider.translateStream(stream)
        pumpTask = Task { [weak self] in
            do {
                for try await o in out {
                    self?.translations[o.id] = o
                }
            } catch is CancellationError {
            } catch {
                self?.statusBanner = "翻訳エラー: \(error.localizedDescription)"
                await self?.teardown()                     // ストリームエラーも fail-closed
            }
        }
    }

    /// Pipeline が確定セグメントを得るたびに呼ぶ。partial は呼ばない。
    public func submitConfirmed(_ input: TranslationInput) {
        inputCont?.yield(input)
    }

    /// 録音停止 / 設定変化 / アプリ終了で呼ぶ。冪等。
    public func teardown() async {
        inputCont?.finish(); inputCont = nil
        pumpTask?.cancel(); pumpTask = nil
        if let a = active { await a.teardown() }
        active = nil; isCloudActive = false
    }

    private func bannerFor(_ r: TranslationDecision.DenyReason) -> String? {
        switch r {
        case .toggleOff: return nil
        case .privacyBlocksAutoCloud: return "プライバシーモードのため自動クラウド翻訳は無効です"
        case .missingApiKey: return "BYO の API キーを設定してください"
        }
    }
}
```

ライフサイクル不変条件: `active != nil` ⟺ 直近 `evaluate` が `.allow`。クラウド socket は `prepare()`〜`teardown()` の間だけ生存。`privacyMode`/`translationEnabled` が変化したら UI 側が `reconcile` を再呼出し → `teardown` が走る。

---

## 8. AppleTranslationProvider + 不可視ホスト（session を closure 内に閉じ込める）

**案1の per-batch continuation hop は却下**。実 API 検証で session を closure 外で使うと fatal error が確定したため、**常駐ホスト view の `.translationTask` closure 内に「ジョブ drain ループ」を置き、session をそこから一歩も出さない**設計にします（案2/案3 を統合・修正）。

### 8.1 Bridge（@MainActor・actor とホストの結線）

```swift
import SwiftUI
import Translation

@MainActor
public final class AppleTranslationBridge: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    public struct Job: Sendable {
        let requests: [TranslationSession.Request]
        let resume: @Sendable ([TranslationSession.Response]) -> Void
        let fail: @Sendable (Error) -> Void
    }
    enum HostMessage { case prepareOnly(@Sendable (Error?) -> Void); case job(Job) }

    private var inbox: [HostMessage] = []
    private var wakeCont: AsyncStream<Void>.Continuation?
    let wake: AsyncStream<Void>

    public init() {
        var c: AsyncStream<Void>.Continuation!
        self.wake = AsyncStream { c = $0 }; self.wakeCont = c
    }

    /// 言語設定（= translationTask 再走トリガー）
    public func setLanguages(source: Locale.Language, target: Locale.Language) {
        configuration = .init(source: source, target: target)
    }
    func enqueue(_ m: HostMessage) { inbox.append(m); wakeCont?.yield(()) }
    func drain() -> [HostMessage] { defer { inbox.removeAll() }; return inbox }
}
```

### 8.2 不可視ホスト View（session は closure 内だけで使用）

```swift
public struct AppleTranslationHostView: View {
    @ObservedObject var bridge: AppleTranslationBridge
    public init(bridge: AppleTranslationBridge) { self.bridge = bridge }

    public var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .translationTask(bridge.configuration) { session in
                // ★ session はこの closure スコープ内だけで使う（持ち出さない）。
                //   view が生きている限り wake を待ち続けてジョブを処理する常駐ループ。
                for await _ in bridge.wake {
                    for msg in bridge.drain() {
                        switch msg {
                        case .prepareOnly(let done):
                            do { try await session.prepareTranslation(); done(nil) }
                            catch { done(error) }
                        case .job(let job):
                            do {
                                var out: [TranslationSession.Response] = []
                                for try await r in session.translate(batch: job.requests) {
                                    out.append(r)
                                }
                                job.resume(out)
                            } catch { job.fail(error) }
                        }
                    }
                }
            }
    }
}
```

このホストは**アプリのルートに常駐**させます（録音画面の有無に依存しない）。

```swift
// sokkiApp / RootView
RootView().background(AppleTranslationHostView(bridge: deps.appleBridge))
```

### 8.3 AppleTranslationProvider（actor → bridge 委譲）

```swift
import Translation

public actor AppleTranslationProvider: TranslationProvider {
    public nonisolated let providerID = "apple"
    public nonisolated let isOnDevice = true

    private let bridge: AppleTranslationBridge
    private let availability: any AvailabilityChecking
    public init(bridge: AppleTranslationBridge, availability: any AvailabilityChecking) {
        self.bridge = bridge; self.availability = availability
    }

    public func prepare(source: Locale.Language, target: Locale.Language) async throws {
        switch await availability.status(from: source, to: target) {
        case .unsupported:
            throw TranslationProviderError.languagePairUnsupported(
                source: source.maximalIdentifier, target: target.maximalIdentifier)
        case .supported:
            await bridge.setLanguages(source: source, target: target)
            try await prepareOnly()                       // DL 同意 UI をホストにアンカー
        case .installed:
            await bridge.setLanguages(source: source, target: target)
        @unknown default:
            throw TranslationProviderError.providerError("unknown availability")
        }
    }

    private func prepareOnly() async throws {
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                bridge.enqueue(.prepareOnly { err in err.map { k.resume(throwing: $0) } ?? k.resume() })
            }
        }
    }

    public func translateStream(
        _ inputs: AsyncStream<TranslationInput>
    ) -> AsyncThrowingStream<TranslationOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for await input in inputs {
                        if Task.isCancelled { break }
                        let req = TranslationSession.Request(
                            sourceText: input.text,
                            clientIdentifier: input.id.uuidString)     // ← id エコーバック
                        let responses = try await self.runBatch([req])
                        for r in responses {
                            let id = UUID(uuidString: r.clientIdentifier ?? "") ?? input.id
                            continuation.yield(TranslationOutput(
                                id: id, translatedText: r.targetText,
                                isConcluded: true, sourceTime: input.sourceTime))
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// actor → MainActor へジョブを渡し、結果（値型のみ）を受け取る。
    /// session 自体は MainActor の closure 内に閉じたまま。境界を越えるのは Request/Response。
    private func runBatch(_ reqs: [TranslationSession.Request]) async throws
        -> [TranslationSession.Response] {
        try await withCheckedThrowingContinuation { k in
            Task { @MainActor in
                bridge.enqueue(.job(.init(requests: reqs,
                    resume: { k.resume(returning: $0) },
                    fail: { k.resume(throwing: $0) })))
            }
        }
    }

    public func teardown() async {
        await MainActor.run { bridge.configuration = nil }   // session を手放す
    }
}
```

**案1との差**: 案1も `runBatch` を使うが、案1のホストは「config 再走ごとに新しい closure で session を受け取り、その closure 内で `control.batches` を for-await」する構造で、再走時に古い closure の session を触る競合リスクがあった。本設計は **wake ストリーム1本に集約し、closure は1つの drain ループだけを回す**。`Request`/`Response` は値型 Sendable なので境界越えは安全（既存方針「actor 境界は Sendable 値型のみ」と一致）。確定セグメントは1件ずつ来るので実質1要素バッチですが、`translate(batch:)` を使うことで `clientIdentifier` の順序逆転耐性をそのまま得られます。

---

## 9. BYO プロバイダ骨子

### 9.1 GeminiLiveTranslateClient（WebSocket）

```swift
import Foundation

public actor GeminiLiveProvider: TranslationProvider {
    public nonisolated let providerID = "geminiLive"
    public nonisolated let isOnDevice = false

    private let keychain: KeychainStore
    private var socket: URLSessionWebSocketTask?
    private var src: Locale.Language?; private var tgt: Locale.Language?
    public init(keychain: KeychainStore) { self.keychain = keychain }

    public func prepare(source: Locale.Language, target: Locale.Language) async throws {
        guard let key = keychain.key(for: providerID) else {
            throw TranslationProviderError.missingAPIKey
        }
        src = source; tgt = target
        // Gemini Live API の WS（v1beta ...:BidiGenerateContent）に接続。
        // setup メッセージで systemInstruction="translate {src}->{tgt}, output only translation"
        var req = URLRequest(url: Self.liveURL(key: key))
        socket = URLSession.shared.webSocketTask(with: req); socket?.resume()
        try await sendSetup(source: source, target: target)   // BidiGenerateContentSetup
    }

    public func translateStream(_ inputs: AsyncStream<TranslationInput>)
        -> AsyncThrowingStream<TranslationOutput, Error> {
        AsyncThrowingStream { continuation in
            // 受信ループ: serverContent を集約し turnComplete で1訳確定 → yield（id 対応付け）
            let recv = Task { try await self.receiveLoop(yield: { continuation.yield($0) }) }
            // 送信ループ: 確定セグメントを clientContent で送信。turn id ↔ input.id を対応表で管理
            let send = Task {
                do {
                    for await input in inputs {
                        if Task.isCancelled { break }
                        try await self.sendTurn(input)        // ← 送信が起きる唯一の箇所（Gate 通過後）
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in recv.cancel(); send.cancel() }
        }
    }

    public func teardown() async {
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
    }
    // sendSetup / sendTurn / receiveLoop / liveURL は実装で埋める
}
```

> 注: Gemini Live は本来音声/動画も扱える双方向 API。sokki ではテキスト翻訳に限定して使う（音声を直接 Live に流すモードを将来追加する場合のみ §9.4 PCMConverter が要る）。Live API のメッセージ形（`BidiGenerateContentSetup` / `clientContent` / `serverContent` / `turnComplete`）は着手前に実機で要確認。

### 9.2 GoogleCloudTranslationV3Provider（REST）

```swift
public actor GoogleCloudV3Provider: TranslationProvider {
    public nonisolated let providerID = "googleCloudV3"
    public nonisolated let isOnDevice = false
    private let keychain: KeychainStore
    private var src = "auto"; private var tgt = "en"; private var projectID = ""
    public init(keychain: KeychainStore) { self.keychain = keychain }

    public func prepare(source: Locale.Language, target: Locale.Language) async throws {
        guard keychain.hasKey(for: providerID) else { throw TranslationProviderError.missingAPIKey }
        src = source.languageCode?.identifier ?? "auto"
        tgt = target.languageCode?.identifier ?? "en"
        projectID = keychain.metadata(for: providerID, field: "projectID") ?? ""
    }

    public func translateStream(_ inputs: AsyncStream<TranslationInput>)
        -> AsyncThrowingStream<TranslationOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for await input in inputs {                // 確定単位 = 1 POST（逐次で律速）
                        if Task.isCancelled { break }
                        let t = try await self.translateText(input.text)   // projects.translateText
                        continuation.yield(TranslationOutput(
                            id: input.id, translatedText: t,
                            isConcluded: true, sourceTime: input.sourceTime))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    public func teardown() async { /* URLSession は共有なら no-op、専用なら invalidateAndCancel */ }
    private func translateText(_ s: String) async throws -> String {
        // POST https://translation.googleapis.com/v3/projects/{projectID}:translateText
        // body: { contents:[s], sourceLanguageCode:src, targetLanguageCode:tgt, mimeType:"text/plain" }
        // header: Authorization: Bearer <key>  → translations[0].translatedText
        ""
    }
}
```

（当初 DeepL も同型の REST provider として検討していたが、D-18 で撤去済み。クラウド BYO は Gemini Live のみ。）

### 9.3 共通方針

- 全 BYO は `isOnDevice = false`。Gate を通らない限り `translateStream` に到達しない。
- key は引数で渡さず `prepare()` 時に `KeychainStore` から取得（メモリ滞留最小化、`grep KeychainStore` で全アクセス列挙可能）。
- REST 系は「1確定セグメント = 1リクエスト」を基本。レイテンシ最適化が必要なら 200–300ms デバウンスで micro-batch。
- DEBUG ビルドでは送信直前に `assert(isOnDevice == false)` 経路がゲート通過済みであることを監査ログで二重化（任意）。

### 9.4 PCMConverter（Gemini Live に音声を直接流す将来モード用）

現状は WhisperKit のテキストを翻訳するため不要ですが、要件にあるため骨子を置きます。Live API は 16kHz mono PCM16 を要求するため、`AVAudioEngine` のキャプチャ形式（多くは 44.1/48kHz Float32）から変換します。

```swift
import AVFoundation

public struct PCMConverter: Sendable {
    /// 任意形式 → 16kHz mono Int16 LE（Gemini Live 入力 / 多くの STT 互換）
    public static func toPCM16k(_ buffer: AVAudioPCMBuffer) -> Data? {
        let dstFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                      sampleRate: 16_000, channels: 1, interleaved: true)!
        guard let conv = AVAudioConverter(from: buffer.format, to: dstFormat) else { return nil }
        let ratio = dstFormat.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: cap) else { return nil }

        var fed = false
        var err: NSError?
        let status = conv.convert(to: out, error: &err) { _, inStatus in
            if fed { inStatus.pointee = .noDataNow; return nil }
            fed = true; inStatus.pointee = .haveData; return buffer
        }
        guard status != .error, err == nil,
              let ch = out.int16ChannelData else { return nil }
        return Data(bytes: ch[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
    }
}
```

---

## 10. TranscriptionPipeline との結線（確定セグメントのみ・2レーン）

既存 `TranscriptionPipeline` の確定セグメント分岐に最小差し込み。partial は翻訳経路に入れない＝構造的に送信ゼロ。

```swift
// TranscriptionPipeline に注入
private let translation: TranslationCoordinator

// start(...) 冒頭
await translation.reconcile(ctx: RoutingContext(
    enabled: settings.translationEnabled,
    preferred: settings.translationProviderKind,
    source: settings.translationSourceLanguage.localeLanguage,
    target: settings.translationTargetLanguage.localeLanguage,
    privacyMode: settings.privacyModeEnabled,
    availableKeys: keychain.availableCloudKinds(),
    cloudPreferenceOrder: [.geminiLive, .googleCloudV3]))

// 既存のセグメント処理（確定分岐）
if segment.isConfirmed {
    let vm = TranscriptSegmentViewModel(segment)        // vm.id: UUID
    confirmedSegments.append(vm)
    hypothesisText = ""
    translation.submitConfirmed(TranslationInput(       // ★ 確定のみ翻訳へ
        id: vm.id, text: segment.text, sourceTime: segment.start))
} else {
    hypothesisText = segment.text                       // partial は原文のみ（翻訳しない）
}

// stop() 冒頭
await translation.teardown()
```

### 2レーン字幕 UI

```swift
ForEach(pipeline.confirmedSegments) { seg in
    VStack(alignment: .leading, spacing: 2) {
        Text(seg.text)                                  // 原文レーン（即時）
        if let t = coordinator.translations[seg.id] {
            Text(t.translatedText).foregroundStyle(.secondary)  // 訳文レーン（遅延到着）
        } else if coordinator.isCloudActive || coordinator.statusBanner == nil {
            ProgressView().controlSize(.mini)           // 翻訳待ち
        }
    }
}
// プライバシー透明性バー（常時可視化）
if let banner = coordinator.statusBanner {
    Label(banner, systemImage: coordinator.isCloudActive ? "cloud" : "info.circle")
}
```

`id`（= clientID）で原文行と訳文を突き合わせるため、BYO の応答遅延・順序逆転に強い（`sourceTime` は安定ソート用の補助）。

---

## 11. DI 結線（AppDependencyContainer 追加）

```swift
let appleBridge = AppleTranslationBridge()                          // @MainActor
let availabilityCache = AvailabilityCache()
let keychain = KeychainStore()
let router = TranslationRouter(availability: availabilityCache)
let appleProvider = AppleTranslationProvider(bridge: appleBridge, availability: availabilityCache)

let translationCoordinator = TranslationCoordinator(
    router: router, keychain: keychain, appleProvider: appleProvider,
    makeBYO: { kind in
        switch kind {
        case .geminiLive:    return GeminiLiveProvider(keychain: keychain)
        case .googleCloudV3: return GoogleCloudV3Provider(keychain: keychain)
        default:             return nil
        }
    })
// RootView.background(AppleTranslationHostView(bridge: appleBridge)) を常駐
// pipeline 生成時に translationCoordinator を注入
```

`AppSettingsModel` の変更: `translationApiKey: String` を**廃止**し Keychain へ移行。`translationProvider` を `TranslationProviderKind` 化（`auto` 追加）。`translationEnabled` / `privacyModeEnabled` / `translationSourceLanguage` / `translationTargetLanguage` は維持。

---

## 12. Swift 6 strict concurrency 整理

| 論点 | 方針 |
|---|---|
| actor 分離 | provider は全て `actor`（`TranscriptionEngine: Actor` と同型）。Router・AvailabilityCache も actor。 |
| @MainActor | `TranslationCoordinator`・`AppleTranslationBridge`・`AppleTranslationHostView`。SwiftUI 制約 + `@Observable` UI バインド。 |
| Sendable | 境界を越えるのは `TranslationInput`/`TranslationOutput`/`RoutingContext`/`RoutingDecision`/`TranslationGateContext`/`Request`/`Response`（全て値型）。`@Model` は渡さず `id: UUID` のみ（既存 `PersistentIdentifier` 方針と一致）。 |
| 非 Sendable 封じ込め | `LanguageAvailability` は `AvailabilityCache` actor 内、`TranslationSession` は `.translationTask` closure 内に閉じる（**actor へ越境させない**）。 |
| nonisolated | `providerID`/`isOnDevice` は `nonisolated let`。Gate/Router/Coordinator が actor hop なしに読む。 |
| バックプレッシャ | 入力 `AsyncStream` は `.bufferingNewest(32)`（古い未訳を捨て最新優先）。REST は逐次 await で自然律速。 |
| キャンセル | `translateStream` の `onTermination` で内部 Task cancel。`teardown()` で `inputCont.finish()` → for-await 終了 → WS close。`pumpTask.cancel()`。 |
| continuation | actor↔MainActor 往復は `withCheckedThrowingContinuation`（リーク検出）。 |

---

## 13. テスト計画

実機なしで回せる中核（Gate/Router）と、実機必須（Apple session）を分離。

1. **Gate 真理値表（§5）全行** を `TranslationGate.evaluate` で網羅。特に「privacy ON + 自動FB → denied」「privacy ON + 明示選択 → allow」の境界。
2. **プライバシー回帰**: `privacyMode=ON` + auto + Apple 未対応ペア → クラウド `activate` が**1度も起きない**（Mock の `prepare`/`teardown` 呼出し検証）。
3. **Router**: `MockAvailability` で `.installed`/`.supported`/`.unsupported` を注入し、`resolve` の分岐（Apple 採用 / DL 必要 / 自動FB / 不能）を網羅。
4. **ライフサイクル**: `privacyMode` を false→true に変えて `reconcile` 再呼出し → `active == nil` かつ Mock の `teardown` が呼ばれること。
5. **id 突き合わせ**: 出力順を入れ替える `MockTranslationProvider` でも `translations[id]` が正しく対応。
6. **partial 非送信**: partial セグメントが `submitConfirmed` を経由しない（Pipeline テスト）。
7. **キャンセル**: `teardown()` で Mock stream が finish し pumpTask 終了。
8. **実機統合（macOS 15 実機のみ）**: `AppleTranslationHostView` 経由で `.installed` ペアの実翻訳、`.supported` ペアの DL 同意フロー。

`AvailabilityChecking` と `KeychainStore` をプロトコル/注入可能にしてあるため、Apple フレームワーク非依存で 1–7 が回ります。

---

## 14. 未確定点・要実機検証

1. **Gemini Live API のメッセージ形式**: `BidiGenerateContentSetup` / `clientContent` / `serverContent` / `turnComplete` の正確な JSON と、テキストのみ翻訳での `systemInstruction` 指定法。2026 時点のエンドポイント（`v1beta` 系）とモデル名は着手前に実機確認が必要。
2. **`translate(batch:)` の単発呼び出しコスト**: 確定セグメントごとに1要素バッチで `translationTask` closure を起こす方式の実レイテンシ。詰まるなら短窓デバウンスで複数セグメントを1バッチ化（同一ソース言語前提を守る）。
3. **`prepareTranslation()` の DL 同意 UI**: 不可視（0pt）ホストにアンカーした際、システムの DL シートが正しく前面表示されるか。表示されない場合はホストを 0pt でなく画面外配置にする等の調整が要る（**最重要の実機検証項目**）。
4. **自動言語検出（source nil）**: `LanguageAvailability.status(from:to:)` は source 必須。auto 検出は初期は「ユーザーが source 明示指定」前提とし、検出は後続フェーズへ。
5. **macOS 26 の API 拡張**: view 非依存で session を取る系の拡張がある可能性。配布ターゲット macOS 15+ なので `.translationTask` 経由を基準とし、足すなら `if #available(macOS 26, *)` で Bridge 実装だけ差し替え（`TranslationProvider` 抽象は不変）。着手前に `developer.apple.com/documentation/translation` を再確認。
6. **設定変更時の Apple session 再走**: `bridge.setLanguages` で `Configuration` を作り直すと closure が再走し、進行中の drain ループが切れる。言語ペア変更時の in-flight ジョブの扱い（破棄 or 再投入）を実機で確認。

---

## 15. spec.md / Issue 反映提案

- `spec.md 4.6` を本設計で差し替え。`TranslationInput/Output` に `id: UUID`、protocol に `providerID`/`teardown()` 追加、`isOnDevice` を `nonisolated`。
- 設計判断ログ追記:
  - **D-13**: クラウド送信可否は `TranslationGate.evaluate`（純粋関数・fail-closed）に一元化。provider に権限判定を持たせない。
  - **D-14**: provider は `prepare()`〜`teardown()` の間だけ生存。privacy/enabled 変化で即 teardown。
  - **D-15**: `TranslationSession` は `.translationTask` closure 内に閉じ、常駐ホストの drain ループで処理。actor へ越境させるのは `Request`/`Response` 値型のみ。
  - **D-16**: BYO key は SwiftData ではなく Keychain（`KeychainStore` 単一アクセス点）。`AppSettingsModel.translationApiKey` を廃止。
- Phase2 Issue 候補（依存順）: (a) protocol + Gate + Router + AvailabilityCache + Mock + ユニットテスト → (b) AppleTranslationHost + Provider（実機 DL 検証含む）→ (c) Coordinator + Pipeline 結線 + 2レーン UI → (d) BYO（Google v3 が最軽量 → Gemini Live、(a) 完了後に並行可。DeepL は D-18 で撤去済み）。

---

Sources:
- [Translating text within your app — Apple Developer](https://developer.apple.com/documentation/Translation/translating-text-within-your-app)
- [translate(batch:) — Apple Developer](https://developer.apple.com/documentation/translation/translationsession/translate(batch:))
- [TranslationSession.Response.clientIdentifier — Apple Developer](https://developer.apple.com/documentation/translation/translationsession/response/clientidentifier)
- [TranslationSession — Apple Developer](https://developer.apple.com/documentation/translation/translationsession)
- [LanguageAvailability — Apple Developer](https://developer.apple.com/documentation/translation/languageavailability)
- [Free, on-device translations with the Swift Translation API — polpiella.dev](https://www.polpiella.dev/swift-translation-api/)
- [Using the Translation framework — createwithswift.com](https://www.createwithswift.com/using-the-translation-framework-for-language-to-language-translation/)
