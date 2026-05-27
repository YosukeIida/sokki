# sokki

macOS 15+ ネイティブ音声文字起こしアプリ。xcodegen + Swift Package Manager + SwiftUI + SwiftData。

## 重要ドキュメント

- `spec.md` — アーキテクチャ仕様書・設計判断ログ（D-1〜D-9）
- `requirements.md` — 機能要件・非機能要件・GitHub Issues 計画

## ビルド

```bash
swift build              # CLI ビルド
swift test               # テスト（20 件）
xcodegen generate        # sokki.xcodeproj を再生成（project.yml 変更後）
open sokki.xcodeproj     # Xcode で開く
```

## タスク管理（GitHub Issues）

**作業前に必ず Issues を確認する。**

```bash
# 未完了 Issues 一覧
gh issue list --label "Phase1"

# 特定 Issue の詳細
gh issue view 3

# 作業開始時（自分にアサイン）
gh issue edit 3 --add-assignee "@me"

# 完了時（クローズ + コメント）
gh issue close 3 --comment "実装完了: <変更の概要>"
```

### 現在の優先順序

1. **Issue #22** `[Design]` — claude.ai/design で各画面をデザイン（先行）
2. **Issue #2** `[P1]` — 録音一覧・詳細画面の E2E 動作確認
3. **Issue #3** `[P1]` — durationSeconds を停止後に更新
4. **Issue #4** `[P1]` — 音声ファイルをディスクへ保存（.m4a）
5. **Issue #5** `[P1]` — Markdown エクスポートの確認

Phase 2 以降は `gh issue list --label "Phase2"` を参照。

### Issue を新しく作る場合

```bash
gh issue create \
  --title "[P1] タイトル" \
  --label "Phase1" \
  --body "## 概要\n...\n\n## 完了基準\n- ..."
```

ラベル: `Phase1` / `Phase2` / `Phase3` / `Phase4` / `Phase5` / `design` / `bug` / `test`

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
- 音声キャプチャは Phase 1 が `AVAudioEngine`、Phase 2 以降が `SCStream`（設計判断 D-9）
- デュアル SCStream は使わない（設計判断 D-1）
- `@Model` クラスは actor 境界を越えて渡せないため `PersistentIdentifier` を使う
