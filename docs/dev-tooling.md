# sokki 開発ツール・テスト自動化ガイド

> 作成日: 2026-05-27  
> 対象: macOS ネイティブ SwiftUI アプリ（SPM ベース）の開発環境と自動化手法

---

## 1. Pindrop から参考にした設計パターン

[Pindrop](https://github.com/watzon/pindrop) は sokki と同じく macOS ネイティブの音声文字起こしアプリ（169 Swiftファイル）。  
以下のパターンを参考にした。

### 採用したもの

| パターン | Pindrop での実装 | sokki での実装 |
|---|---|---|
| **PreviewMocks** | `Pindrop/Mocks/PreviewMocks.swift` | `Sources/sokki/Mocks/PreviewMocks.swift` |
| **PermissionManager** | `Services/PermissionManager.swift` | `Sources/sokki/Audio/PermissionManager.swift` |
| **justfile** | `justfile`（ビルド自動化） | `justfile`（swift build / test / smoke） |
| **SwiftData スキーマバージョニング** | V1〜V7 マイグレーション | 現在 V1（Phase 3 以降で追加予定） |
| **Protocol ベースエンジン抽象化** | `TranscriptionEngine` / `AudioCaptureBackend` | `TranscriptionEngine` / `DiarizationEngine` |

### 採用しなかったもの・理由

| パターン | Pindrop | 不採用理由 |
|---|---|---|
| AppCoordinator (4595行) | 全サービスを1クラスで管理 | sokki の分散 actor 設計の方が Swift 6 の並行性安全に適合 |
| Combine フレームワーク | リアクティブプログラミング | sokki は Swift Concurrency (AsyncStream) を使用 |
| Sparkle 自動更新 | アプリ内アップデート | Phase 5 (Homebrew Cask) まで不要 |
| LSUIElement（メニューバーアプリ） | ステータスバーアプリ形式 | Phase 1 は通常ウィンドウアプリ |
| MCP サーバー実装 | HTTP MCPサーバー内蔵 | LLM 連携は Phase 5 |

---

## 2. Claude Code / Codex での Xcode 動作確認手法

### 2-1. macOS ネイティブアプリへの制約

sokki は macOS ウィンドウアプリ（SwiftUI + SwiftData）。  
**iOS Simulator ベースのツールは使えない**（`xcode-studio-mcp` の UI 操作、`ios-simulator-skill` 等）。

macOS アプリの UI 自動化に使えるツール:

```
Swift Concurrency で動く macOS SwiftUI アプリ
         ↓
┌────────────────────────────────────────────────────┐
│ Layer 1: swift test（Xcode 不要）                   │
│   - EmbeddingMatcherTests, ExportTests             │
│   - MockTranscriptionEngine, SessionManager        │
│   - SnapshotTests（swift-snapshot-testing）        │
├────────────────────────────────────────────────────┤
│ Layer 2: #Preview + PreviewMocks（Xcode 必要）      │
│   - RecordingView: idle/loading/recordingWithText  │
│   - SessionDetailView, SettingsView               │
├────────────────────────────────────────────────────┤
│ Layer 3: xcrun mcpbridge（Xcode 26+ 内蔵）          │
│   - Claude Code からビルド・起動・スクリーンショット │
│   - アクセシビリティツリー取得・UI 操作             │
└────────────────────────────────────────────────────┘
```

---

### 2-2. Layer 1: swift test（今すぐ使える）

#### 実行方法

```bash
# 全テスト
just test          # justfile 経由
swift test         # 直接

# スイート指定
swift test --filter EmbeddingMatcherTests
swift test --filter SessionManagerTests
swift test --filter SnapshotTests

# スナップショット再記録
RECORD=1 swift test --filter SnapshotTests
```

#### テストスイート一覧

| スイート | ファイル | テスト数 | テスト内容 |
|---|---|---|---|
| EmbeddingMatcher | `EmbeddingMatcherTests.swift` | 4 | vDSP コサイン類似度・L2 正規化 |
| Exporter | `ExportTests.swift` | 3 | Markdown・SRT・タイムスタンプ |
| MockTranscriptionEngine | `MockTranscriptionEngineTests.swift` | 6 | エンジン状態遷移・ストリーミング |
| SessionManager | `MockTranscriptionEngineTests.swift` | 3 | SwiftData CRUD（in-memory） |
| RecordingView Snapshots | `SnapshotTests.swift` | 3 | アイドル・ローディング・録音中 |
| SessionDetailView Snapshots | `SnapshotTests.swift` | 1 | セグメントあり状態 |

#### スナップショットファイルの管理

```
Tests/sokkiTests/__Snapshots__/SnapshotTests/
├── idle.1.png              ← RecordingView アイドル状態
├── loading.1.png           ← WhisperKit ロード中
├── recordingWithText.1.png ← 録音中（テキストあり）
└── withSegments.1.png      ← SessionDetailView
```

**git でコミットすること**（ベースラインとして使用）。

---

### 2-3. Layer 2: PreviewMocks + #Preview

#### 使い方（Xcode で確認）

```swift
// RecordingView.swift 末尾に追加済み
#Preview("アイドル") {
    RecordingView()
        .environment(AppDependencyContainer.preview(pipeline: PreviewPipeline.idle()))
}
#Preview("ローディング中") { ... }
#Preview("録音中（テキストあり）") { ... }
```

Xcode の Canvas（⌥⌘↩）で3状態を手動操作なしに確認可能。

#### PreviewPipeline の状態

| 状態 | メソッド | 内容 |
|---|---|---|
| アイドル | `PreviewPipeline.idle()` | 初期状態、録音前 |
| ローディング | `PreviewPipeline.loading()` | モデルDL中スピナー表示 |
| 録音中 | `PreviewPipeline.recording()` | タイマー動作中 |
| テキストあり | `PreviewPipeline.recordingWithText()` | confirmedSegments 3件 |

**ファイル**: `Sources/sokki/Mocks/PreviewMocks.swift`（`#if DEBUG` ガード済み）

---

### 2-4. Layer 3: xcrun mcpbridge（Xcode 26 内蔵）

#### 概要

Apple が Xcode 26 に内蔵した **公式 MCP サーバー**。  
Claude Code から sokki を直接ビルド・操作できる。

```bash
# 存在確認
xcrun --find mcpbridge
# → /Applications/Xcode.app/Contents/Developer/usr/bin/mcpbridge ✅
```

#### 設定（`.claude/settings.json`）

```json
{
  "mcpServers": {
    "xcode": {
      "command": "xcrun",
      "args": ["mcpbridge"]
    }
  }
}
```

#### 事前設定（Xcode 側）

1. Xcode → Settings（⌘,） → Intelligence
2. **Model Context Protocol** → **Xcode Tools** を ON
3. Claude Code から接続すると Xcode に許可ダイアログが表示される → Allow

#### できること（Claude Code から指示するだけ）

```
「sokki をビルドして起動してスクリーンショットを撮って」
「録音ボタンをクリックしてマイク権限ダイアログを確認して」
「SessionDetailView に遷移してエクスポートメニューを開いて」
```

---

## 3. 発見した外部ツール・MCP サーバー一覧

### macOS ネイティブアプリに使えるもの

| ツール | URL | 方法 | 依存 |
|---|---|---|---|
| **xcrun mcpbridge** | Apple 内蔵 (Xcode 26+) | ビルド・実行・スクリーンショット・UI 操作 | Xcode 26 |
| **swift-snapshot-testing** | github.com/pointfreeco/swift-snapshot-testing | `swift test` でスナップショット比較 | なし |
| **Iron-Ham/XcodePreviews** | github.com/Iron-Ham/Claude-XcodePreviews | `#Preview` をCLIから PNG キャプチャ（SPM対応） | Xcode + Simulator |
| **swiftui-render** | github.com/olliewagner/swiftui-render | 単一 .swift ファイル → PNG（Simulator 不要） | CLT のみ |
| **xcode-mcp-server** | github.com/drewster99/xcode-mcp-server | AppleScript で Xcode 制御 | Python + Xcode |

### iOS Simulator 専用（sokki には使えない）

| ツール | URL | 理由 |
|---|---|---|
| `xcode-studio-mcp` | github.com/kevinswint/xcode-studio-mcp | iOS Simulator の UI 操作のみ |
| `xc-mcp` | npm xc-mcp | iOS Simulator ベース |
| `ios-simulator-skill` | github.com/dazuiba/ios-simulator-skill | IDB 依存（iOS のみ） |
| `swiftui-autotest-skill` | github.com/yusufkaran/swiftui-autotest-skill | Computer Use（Pro/Max プラン必要） |

### Claude Code Skill（コマンドラインのみ）

| Skill | URL | コマンド | 機能 |
|---|---|---|---|
| `snapshot-test-setup` | github.com/rshankras/claude-code-apple-skills | `/snapshot-test-setup` | swift-snapshot-testing セットアップ支援 |
| `apple-platform-build-tools` | github.com/kylehughes/apple-platform-build-tools | 自動発動 | `xcodebuild` / `swift build` 知識 |
| `AppTestCircuit` | github.com/webcoyote/AppTestCircuit | `/AppTestCircuit:test-loop` | ビルド→テスト自動ループ |

---

## 4. 日常の開発フロー

### コード変更 → テスト（Claude Code のみ）

```bash
# 1. ビルド確認
just build

# 2. ロジックテスト
just test

# 3. スナップショット比較（UI 変更確認）
swift test --filter SnapshotTests

# 4. スモークテスト（クラッシュ確認）
just smoke
```

### UI 変更 → ビジュアル確認（Xcode 必要）

```
1. Xcode を開く（xed .）
2. Canvas を開く（⌥⌘↩）
3. RecordingView.swift を開く
4. 右ペインで3つの #Preview を確認
```

### Claude Code から Xcode アプリを動かす（xcrun mcpbridge）

```
Claude Code に指示:
  「sokki をビルドして起動して、
   録音ボタンを押してマイク権限ダイアログが出るか確認して」
```

---

## 5. 今後追加を検討するもの

### accessibilityIdentifier の付与（xcrun mcpbridge 操作の精度向上）

```swift
// RecordingView.swift
Button { ... } label: { ... }
    .accessibilityIdentifier("record-button")

// Mic/System/Both ボタン
modeButton("Mic", mode: .micOnly)
    .accessibilityIdentifier("mode-mic")
```

アクセシビリティ識別子があると `mcpbridge` がセマンティックに要素を見つけられる。

### Iron-Ham/XcodePreviews（SPM 対応 Preview キャプチャ）

```bash
git clone https://github.com/Iron-Ham/Claude-XcodePreviews ~/tools/XcodePreviews
cd ~/tools/XcodePreviews && ./scripts/install.sh

# sokki の Preview をキャプチャ
preview Sources/sokki/UI/RecordingView/RecordingView.swift --package Package.swift
```

Claude Code から `/preview RecordingView.swift` で UI スクリーンショットを取得・分析できる。
