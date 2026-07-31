# sokki（速記）

macOS 15+ ネイティブの音声文字起こしアプリ。日本語高精度オンデバイス文字起こし / 声紋を記憶する
話者分離 / リアルタイム翻訳（API ハイブリッド）を三本柱とする。

xcodegen + Swift Package Manager + SwiftUI + SwiftData 構成。詳細な設計判断・アーキテクチャは
`spec.md`、機能要件は `requirements.md` を参照。

## インストール

現在 sokki は Apple Developer ID 署名を受けていない **無署名アプリ** として GitHub Releases 経由で
dmg 配布している（配布方針の決定は backlog TASK-10 を参照）。

1. [GitHub Releases](https://github.com/YosukeIida/sokki/releases) から最新の `sokki-<version>.dmg`
   をダウンロードする
2. dmg をマウントし、`sokki.app` を `/Applications` にドラッグ&ドロップする
3. 無署名アプリのため、初回起動時に Gatekeeper の警告（「壊れているため開けません」/
   「開発元を確認できません」）が表示される。回避手順（`xattr -cr` またはシステム設定からの
   「このまま開く」）は **[docs/distribution.md](docs/distribution.md)** に詳しく記載している
4. 起動後、マイク（および必要に応じてシステム音声）へのアクセス許可を求められるので許可する

自分で dmg をビルドしたい場合は `scripts/make-dmg.sh --help` を参照（同じく
`docs/distribution.md` にビルド手順とリリース手順をまとめてある）。

## ビルド（開発者向け）

```bash
swift build              # CLI ビルド
swift test               # テスト実行（既知の Snapshot 失敗 4 件は macOS 26.2 の描画差）
xcodegen generate        # sokki.xcodeproj を再生成（project.yml 変更後）
open sokki.xcodeproj      # Xcode で開く
```

`just` コマンドでの操作は `justfile` を参照（`just --list`）。

## ドキュメント

- `spec.md` — アーキテクチャ仕様書・設計判断ログ（D-1〜D-17）
- `requirements.md` — 機能要件・非機能要件
- `docs/roadmap.md` — フェーズ構成・依存関係の設計スナップショット
- `docs/distribution.md` — dmg 配布手順・GitHub Releases 公開手順・Gatekeeper 回避手順
- `backlog/` — タスク管理の正本（状態・依存関係・完了基準）

## 動作環境

- macOS 15+ (Apple Silicon)
