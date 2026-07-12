# sokki

macOS 15+ ネイティブ音声文字起こしアプリ。xcodegen + Swift Package Manager + SwiftUI + SwiftData。

## 重要ドキュメント

- `spec.md` — アーキテクチャ仕様書・設計判断ログ（D-1〜D-17）
- `requirements.md` — 機能要件・非機能要件
- `docs/roadmap.md` — フェーズ構成・依存関係の設計スナップショット（タスク状態の正本は backlog）

## ビルド

```bash
swift build              # CLI ビルド
swift test               # テスト（27 件。既知の Snapshot 失敗 4 件は macOS 26.2 の描画差）
xcodegen generate        # sokki.xcodeproj を再生成（project.yml 変更後）
open sokki.xcodeproj     # Xcode で開く
```

## タスク管理（Backlog.md が正本 / GitHub Issues は同期ミラー）

**作業前に必ず backlog を確認する。** 状態（To Do / In Progress / Done）・依存関係・完了基準は backlog（`backlog/`）が正本。GitHub Issues は対外向けミラーで、backlog に合わせて同期する。

Claude Code からは backlog MCP サーバのツール（`task_list` / `task_view` / `task_create` / `task_edit`）を使う。CLI の場合:

```bash
backlog task list --plain     # タスク一覧
backlog task view 6 --plain   # タスク詳細
backlog board                 # ボード表示
```

### GitHub Issues との同期ルール

- 各 backlog タスクの references に対応 Issue の URL を記録してある
- **タスク完了時**: backlog を Done にし、対応 Issue を `gh issue close <n> --comment "実装完了: <概要>"` でクローズする
- **タスク新規作成時**: backlog に作成し、ミラー Issue も `gh issue create` で作成して相互参照する（Issue 本文に backlog TASK-ID、backlog references に Issue URL）
- 乖離を見つけたら backlog に合わせて Issues を直す

ラベル: `Phase1` / `Phase2` / `Phase2.5` / `Phase3` / `Phase4` / `Phase5` / `Phase6` / `design` / `bug` / `test` / `infra`

### 現在の優先

backlog の High priority を参照（現在: **TASK-6** = P1-3 録音一覧・詳細の E2E 動作確認 / Issue #25）。フェーズ構成と依存関係の設計根拠は `docs/roadmap.md`（スナップショット。タスク状態はそこでは更新しない）。

## アーキテクチャ（重要）

### ターゲット構成

| ターゲット | 種別 | パス |
|---|---|---|
| `SokkiKit` | Library（Framework） | `Sources/SokkiKit/` |
| `sokki` | Executable（@main のみ） | `Sources/sokki/` |
| `sokkiTests` | Unit Test | `Tests/sokkiTests/` |

UI コンポーネント・ビジネスロジックは全て `SokkiKit` に置く。  
`sokki` は `sokkiApp.swift` と `makeModelContainer()` 呼び出しのみ。

### Xcode MCP（Claude Code から使えるツール）

Xcode が起動中かつ `sokki.xcodeproj` を開いている状態で使用可能。

```
BuildProject   → ビルド確認
RenderPreview  → #Preview のスクリーンショット取得
RunAllTests    → テスト実行
GetBuildLog    → ビルドエラー詳細
XcodeListNavigatorIssues → 警告・エラー一覧
```

### `project.yml` の変更後

```bash
xcodegen generate   # xcodeproj を再生成
# → Xcode が自動リロード
```

## 注意事項

- macOS 15+ / Apple Silicon 専用
- `argmax-oss-swift` v1.0 に WhisperKit と SpeakerKit が同梱
- SwiftData モデルは `[Float]` を直サポートしないため `Data` 変換で保存（`SpeakerProfileModel.embeddingData`）
- 音声キャプチャは Phase 1 が `AVAudioEngine`、Phase 2 以降は **Core Audio Taps（ProcessTap）が既定・`SCStream` は代替**（設計判断 D-9 改訂 / D-10）
- デュアル SCStream は使わない（設計判断 D-1）
- `@Model` クラスは actor 境界を越えて渡せないため `PersistentIdentifier` を使う
