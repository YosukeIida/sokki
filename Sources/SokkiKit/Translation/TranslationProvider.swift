import Foundation

// MARK: - I/O 値型（actor 境界を越えるのは Sendable 値型のみ）

/// 翻訳への入力。確定セグメント1件に対応。
///
/// `id` は原文セグメントと同一キー（= clientID）。訳文の順序逆転・遅延到着に
/// 強くするため、出力側で同じ `id` をエコーバックして原文行と突き合わせる。
public struct TranslationInput: Sendable, Identifiable, Equatable {
    /// = clientID。原文セグメントと同一キー。
    public let id: UUID
    public let text: String
    /// セグメント開始時刻（並び順・行対応の補助）。
    public let sourceTime: TimeInterval

    public init(id: UUID, text: String, sourceTime: TimeInterval) {
        self.id = id
        self.text = text
        self.sourceTime = sourceTime
    }
}

/// 翻訳結果。入力 `id` をエコーバックして UI 側で原文行と突き合わせる。
public struct TranslationOutput: Sendable, Identifiable, Equatable {
    /// 対応する `TranslationInput.id`。
    public let id: UUID
    public let translatedText: String
    /// `true` = 確定訳（partial 訳は将来用）。
    public let isConcluded: Bool
    public let sourceTime: TimeInterval

    public init(id: UUID, translatedText: String, isConcluded: Bool, sourceTime: TimeInterval) {
        self.id = id
        self.translatedText = translatedText
        self.isConcluded = isConcluded
        self.sourceTime = sourceTime
    }
}

// MARK: - エラー

public enum TranslationProviderError: Error, Sendable, Equatable {
    /// 言語ペア非対応（Apple: `.unsupported`）。
    case languagePairUnsupported(source: String, target: String)
    /// Apple: `.supported`（DL 可能だが未 DL）。
    case modelNotDownloaded
    /// BYO キー未設定。
    case missingAPIKey
    /// 接続失敗（WebSocket / REST）。
    case connectionFailed(String)
    /// その他 provider 固有エラー。
    case providerError(String)
}

// MARK: - Provider 種別

/// 翻訳プロバイダの種別。`auto` はルーティングで実体に解決される。
public enum TranslationProviderKind: String, Sendable, CaseIterable, Codable {
    case auto
    case apple
    case geminiLive
    case googleCloudV3

    /// この種別が構造的にオンデバイス（クラウド送信を伴わない）であることが確定するか。
    public var isOnDeviceImplied: Bool { self == .apple }
}

// MARK: - API キー照会の注入点

/// BYO クラウドキーの存在確認。TASK-23 の Keychain 実装がこの protocol に適合する。
///
/// Gate / Coordinator はこの抽象越しにキー有無だけを同期照会する。
/// 実キーの取り出しは provider の `prepare()` 内で行い、ここでは扱わない。
public protocol APIKeyChecking: Sendable {
    /// 指定 `providerID`（= `TranslationProviderKind.rawValue`）のキーが登録済みか。
    func hasKey(for providerID: String) -> Bool
}

// MARK: - Provider protocol（最小契約 + ライフサイクル）

/// 翻訳の最小契約。ルーティング / プライバシー / フォールバックは持たない。
///
/// provider は「自分が呼ばれた＝許可済み」を前提に、変換とリソース管理だけを行う。
/// クラウド送信可否の判定は `TranslationGate` に一元化されており、provider は関与しない。
public protocol TranslationProvider: Actor {
    /// 監査タグ。Gate/Router が actor hop なしに同期参照できるよう `nonisolated`。
    nonisolated var providerID: String { get }
    /// クラウド送信を伴わないか。Gate の入力。`nonisolated`。
    nonisolated var isOnDevice: Bool { get }

    /// 言語ペアの準備。対応不可・key 無し・接続失敗は throw。
    func prepare(source: Locale.Language, target: Locale.Language) async throws

    /// 確定セグメントのストリームを翻訳ストリームに変換。
    /// 入力 `finish` またはタスクキャンセルで出力も終了する。
    func translateStream(
        _ inputs: AsyncStream<TranslationInput>
    ) -> AsyncThrowingStream<TranslationOutput, Error>

    /// socket / URLSession を確実に閉じる。冪等。
    func teardown() async
}

/// PCM 音声を直接扱える翻訳 provider の追加契約。
///
/// テキスト入力の既存 Coordinator とは意図的に分離し、音声配線は後続タスクで行う。
/// Gemini Live では同一 ID の原文字幕を `isConcluded == false`、確定訳文を
/// `isConcluded == true` として順に返す。現行 UI へは後続タスクで lane を分けて配線する。
public protocol AudioTranslationProviding: TranslationProvider {
    func translateAudioStream(
        _ samples: AsyncStream<[Float]>
    ) -> AsyncThrowingStream<TranslationOutput, Error>
}
