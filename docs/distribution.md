# 配布ガイド（dmg / GitHub Releases）

TASK-10 の決定（`backlog/tasks/task-10 - 配布方針の意思決定（ブロッカー）.md`）に基づき、
sokki は当面 **無署名の dmg を GitHub Releases 経由で配布**する。Developer ID Program 取得後は
Developer ID 署名 + 公証に移行し、Homebrew Cask 配布（TASK-37）も検討する。

このドキュメントは TASK-42 の実行内容として、(1) dmg のビルド手順、(2) GitHub Releases への
公開手順、(3) 利用者向けの Gatekeeper 回避手順、をまとめる。

## 前提

- 無署名ビルド（Developer ID 未取得のため）。`codesign` は既定では行わない
- そのため利用者は初回起動時に Gatekeeper の警告に遭遇する（後述の回避手順が必要）
- Core Audio Taps（システム音声キャプチャ、Phase 2 以降）は無署名/ad-hoc 署名では
  TCC プロンプトが発火しない可能性が高いことが分かっている（TASK-10 調査結果）。
  無署名配布での動作は別途実機検証が必要（未解決・TASK-10 に記載の既知の制約）
- 実際に `CODE_SIGNING_ALLOWED=NO` でビルドして確認したところ、Apple Silicon の要件により
  実行ファイルには linker が自動付与する ad-hoc 署名（`codesign -dv` で
  `flags=0x20002(adhoc,linker-signed)` と表示される）が付くが、これは entitlements を
  含まない。`codesign -d --entitlements -` は空を返す。つまり `sokki.entitlements` の
  `audio-input` / `screen-capture` 等は無署名配布ビルドには一切埋め込まれない。上記の
  Core Audio Taps の制約はこの事実が根拠であり、Phase 2 以降の実機検証で再確認が必要

## 1. dmg のビルド手順

`scripts/make-dmg.sh` が xcodebuild の Release ビルドから dmg 作成までを行う。

```bash
# ヘルプ
bash scripts/make-dmg.sh --help

# 既定設定でビルド（バージョンは Info.plist の CFBundleShortVersionString から自動取得、
# 出力先は ./dist/sokki-<version>.dmg）
bash scripts/make-dmg.sh

# バージョン・出力先を明示
bash scripts/make-dmg.sh --version 0.2.0 --output ~/Desktop

# 実ビルドをせずコマンドの流れだけ確認したい場合（CI やレビュー時向け）
bash scripts/make-dmg.sh --dry-run
```

内部の流れ:

1. `sokki.xcodeproj` が無ければ `xcodegen generate` を実行
2. `xcodebuild build -scheme sokki -configuration Release` を
   `CODE_SIGNING_ALLOWED=NO` で実行（無署名ビルド。TASK-10 決定に準拠）
3. （`--adhoc-sign` を指定した場合のみ）`codesign --force --deep --sign - sokki.app` で ad-hoc 署名
4. `sokki.app` と `/Applications` へのシンボリックリンクをステージングディレクトリに配置
5. `hdiutil create -format UDZO` で dmg を作成（外部ツール非依存。create-dmg 等の brew ツールは使わない）

既定では ad-hoc 署名を行わない（TASK-10 の決定＝無署名配布に合わせた既定値）。ad-hoc 署名を
試したい場合は `--adhoc-sign` を付ける。ただし ad-hoc 署名しても Gatekeeper 警告は解消されない
（Developer ID 署名 + 公証がない限り「開発元を確認できません」は表示され続ける）。

> **注記**: Release ビルドは WhisperKit / SpeakerKit 依存の解決・コンパイルを含むため、
> 環境によっては数分〜十数分かかることがある。時間を確保できない場合は `--dry-run` で
> スクリプトのロジック（引数解析・パス組み立て・コマンド列）だけ検証すればよい。

## 2. GitHub Releases へのアップロード手順

dmg 生成後、`gh` CLI でリリースを作成する（例。実際のタグ名・バージョンは適宜置き換える）。

```bash
# dmg を作成
bash scripts/make-dmg.sh --version v0.2.0 --output ./dist

# タグを打ってリリースを作成し、dmg をアセットとして添付
git tag v0.2.0
git push origin v0.2.0

gh release create v0.2.0 \
  ./dist/sokki-v0.2.0.dmg \
  --title "sokki v0.2.0" \
  --notes "無署名ビルドです。初回起動時の Gatekeeper 警告の回避手順は docs/distribution.md を参照してください。"
```

リリースノートには、無署名ビルドである旨と本ドキュメントへのリンク（あるいは
下記「3. 利用者向け Gatekeeper 回避手順」の要約）を必ず記載する。

> 本 TASK-42 の作業ではこの `gh release create` を実際には実行しない（禁止事項）。
> 手順の検証・実際のリリース作成はユーザー側で行う。

## 3. 利用者向け Gatekeeper 回避手順

sokki は現在 Apple の Developer ID 署名・公証を受けていない無署名アプリです。
そのため dmg からインストールして初めて起動する際、macOS の Gatekeeper が
警告ダイアログを表示します。以下のいずれかの方法で起動できます。

### 症状 1: 「"sokki" は壊れているため開けません」

これは実際にファイルが壊れているのではなく、**quarantine 属性（隔離フラグ）が
付与された未署名アプリ**に対して macOS が表示する定型メッセージです（macOS 13 以降）。

**対処（ターミナルで quarantine 属性を除去する）**:

```bash
xattr -cr /Applications/sokki.app
```

- `-c` : quarantine を含む拡張属性をすべて削除
- `-r` : `.app` バンドル内を再帰的に処理

実行後、Finder から通常どおり `sokki.app` をダブルクリックして起動できます。

### 症状 2: 「"sokki" は開発元を確認できないため開けません」

**macOS 15 (Sequoia) の場合**:

1. `sokki.app` をダブルクリックすると警告ダイアログが表示され、「完了」しか選べない
2. **システム設定 > プライバシーとセキュリティ** を開く
3. 画面下部に「"sokki" は開発元が未確認のため使用がブロックされました」という表示があるので
   **「このまま開く」** をクリック
4. 確認ダイアログが出るので再度「開く」を選択すると起動する（この操作は初回起動時のみ必要）

**macOS 26 (Tahoe) 以降の場合**:

UI 文言・導線は概ね同様だが、確認ダイアログの文言が
「"sokki" は Apple により悪意のあるソフトウェアが含まれていないか確認されていません。
本当に開いてもよろしいですか？」のように変わることがある。手順自体は同じ:

1. 一度ダブルクリックしてブロックさせる
2. **システム設定 > プライバシーとセキュリティ** を開き、下部の「このまま開く」をクリック
3. 確認ダイアログで「開く」を選択

### どちらを使うべきか

- ターミナルに抵抗がなければ `xattr -cr /Applications/sokki.app` が最も確実（1コマンドで完了し、
  以後は警告なく起動できる）
- GUI 操作を好む場合はシステム設定からの「このまま開く」でよい
- 両方試しても起動しない場合は、dmg のダウンロードが壊れている可能性があるため
  再ダウンロードするか、`shasum -a 256` でチェックサムを確認する

### 将来的な解消について

Developer ID Program 取得後、Developer ID 署名 + 公証済みビルドに移行する予定（TASK-10）。
その時点でこれらの回避手順は不要になる。

## 参照

- `backlog/tasks/task-10 - 配布方針の意思決定（ブロッカー）.md` — 配布方針の決定内容
- `backlog/tasks/task-42 - dmg配布とGatekeeper回避手順のドキュメント化.md` — 本タスクの完了基準
- `scripts/make-dmg.sh` — dmg ビルドスクリプト本体
