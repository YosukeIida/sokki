# sokki 引き継ぎ（handover）

> 記録: 2026-07-03（前回 2026-06-29 から更新）/ 新セッションでの再開用。**まずこのファイルと `docs/roadmap.md` を読む。**
> 関連メモリ: [[project-sokki-direction]] / [[project-sokki-phase1]]

> **2026-07-12 追記**: タスク管理を **Backlog.md（`backlog/`）へ移行し正本化**（GitHub Issues は同期ミラー。同期ルール・現在の優先は CLAUDE.md 参照）。実装済みだった #23/#24 はクローズ済み。未決だった話者ラベルは**ロケール追従（ja=話者A / en=Speaker A）に確定**し、P1-6 はサブタスク TASK-9.1〜9.3（Issues #58〜#60）へ分割。次の作業は backlog **TASK-6**（P1-3 E2E 確認 / #25）。

## 0. 一行サマリー
sokki は macOS ネイティブ音声文字起こしアプリ。方針を「完全ローカル」→「**API ハイブリッド**（オンデバイス基盤＋翻訳等は BYO key）」に転換。現在 **Phase 1（MVP）仕上げ中**。最小一気通貫（録音→文字起こし→保存→表示→エクスポート）のコード（P1-1/P1-2）は実装・テスト・コミット済み。**次は P1-3 の実機 E2E 確認**。

## 1. Git 状態
- ブランチ: **`feat/phase1-mvp-finish`**（`main` から分岐）
- コミット（このブランチ）:
  - `90c111c` fix: xcodegen 生成時の entitlements 空化バグを修正（project.yml に entitlements.properties 追加、.gitignore に .DS_Store。**codex がレビューし `xcodegen --only-plists` で3権限保持を検証済み**）
  - `48f75f5` feat(P1-1,P1-2): 録音音声のディスク保存と録音長の更新
- **未コミット（untracked のみ・作業ツリーはクリーン）**:
  - `docs/handover.md`（このファイル）
  - `docs/design/recording-view-v2.html` — RecordingView モックのローカル保存版（Artifact のソース。コミットするか判断を）
  - `.claude/`（settings + agmsg hooks）/ `.codex/`（agmsg codex hooks）— コミット対象か要判断

## 2. 完了したこと
### コード（P1-1 / P1-2・コミット済み）
- `Sources/SokkiKit/Audio/AudioFileWriter.swift`（新規）：録音音声をディスクへ。`.wav`=16bit PCM / 他=AAC(.m4a)。音声スレッド書込を `NSLock` で直列化、close 冪等。
- `AudioCaptureManager`：`startCapture(mode:outputURL:)` で書き出し配線。
- `SessionManager.audioURL(forSessionID:)` 追加（`createSession` の戻り値は非破壊＝既存テスト維持）。
- `TranscriptionPipeline`：録音 URL を渡し、stop 時に `durationSeconds` を更新。
- `Tests/sokkiTests/Phase1AudioSaveTests.swift`（新規・7テスト）。
- **テスト: 27 件中 23 pass。失敗 4 件は既存の Snapshot（macOS 26.2 の描画差・本変更と無関係）。**

### entitlements バグ修正（`90c111c`・コミット済み）
- xcodegen generate が `sokki.entitlements` を空で上書きする問題。`project.yml` の sokki target に `entitlements.properties`（audio-input / screen-capture / network.client）を明記して恒久修正。codex が実検証済み。

### 環境修正（2026-07-02）
- direnv 読込時の `SQLite database ... eval-cache-v6 ... is busy` エラー → `~/.cache/nix/eval-cache-v6/` を削除して解消（純キャッシュ・再生成済み。再発時は複数プロセス同時 eval が原因、恒久策は `eval-cache = false`）。

### 調査・設計ドキュメント（`docs/`）
- `roadmap.md` — **タスクの正本**（Phase 1〜6、GitHub Issue と対応）
- `recap-codebase-analysis.md` — Recap(MIT OSS) の copy レベル逆解析（§0 に検証済み訂正。WhisperKit download 引数の誤り等に注意）
- `implementation-feasibility.md` — 実装可能性・書き換え可否評価
- `realtime-translation-research.md` / `speaker-diarization-research.md` / `reference-projects.md` / `superintern-research-report.md` / `superintern-feature-plan.md` / `translation-architecture.md`

### 要件・仕様（改訂済み・main にコミット済み）
- `requirements.md` / `spec.md`：FR-TRANS-*（翻訳）追加、Core Audio Taps 既定化（D-9 改訂 / D-10〜D-17）、FluidAudio 推奨、要約はスコープ外（Phase 6）。

### GitHub Issues
- 旧 #2〜#22 を全クローズ → **新ロードマップから 35 件を新規作成**（`Phase1`〜`Phase6` ラベル）。
- **Phase1 の残 open: #23〜#28**。うち **#23 (P1-1) / #24 (P1-2) は実装済み（`48f75f5`）だが未クローズ** → クローズ推奨（コメント例:「実装完了、E2E は #25 で確認」）。

## 3. UI デザイン（確定事項・実装はこれから）
RecordingView の視覚案 Artifact（**最新 v4**）:
**https://claude.ai/code/artifact/0e1c604b-af3d-4bad-a922-2aa341944a69**
（ソース: `docs/design/recording-view-v2.html` に保存済み）

確定:
- **ライト = Manuscript（藍 #2B4A78 ＋ 判子朱 #C23B2C ＋ 冷たい紙）/ ダーク = Console（鎮めたティール、mic #6E96C9・録音 #D9534C）**。システム外観に自動追従＋手動切替。
- **書体は両モード統一**（UI 標準サンセリフ＝SF Pro / ヒラギノ角ゴ。明朝不採用）。
- **波形 = Voice Memos 風**（対称・細い棒＋隙間 3px/4px）。**モード対応**：Mic / System は単一の対称波形、Both は同軸で mic=上・sys=下。セグメント(Mic/System/Both)はクリックで切替（モック内で実装）。
- **タイムスタンプ**を字幕行頭に（mm:ss・等幅）。
- **未登録話者 = Speaker A / B**（色は話者ごと固定、リネーム→声紋に紐づき次回以降は実名）。

未決（次セッションで確認）:
- ~~話者ラベルは 「Speaker A」 vs 「話者A」 どちらにするか。~~ → **決定（2026-07-12）: ロケール追従（ja=話者A / en=Speaker A）**
- （希望あれば）両モード明朝にする選択肢。
- → 決まったら **一覧(SessionList)・詳細(SessionDetail)へ横展開** → **SwiftUI デザイントークン＋共通コンポーネント化** → **RenderPreview で反復**。

## 4. ツール/環境メモ
- **Xcode MCP**（`xcrun mcpbridge`）：Xcode を開いていれば使用可（macOS Automation 許可は付与済み）。`BuildProject`（windowtab1=sokki.xcodeproj）でアプリターゲットのビルド成功実績あり。`RenderPreview`/`RunAllTests`/`GetBuildLog` 等も使用可。**新セッションでは Xcode を開き直し → `/mcp` で xcode を reconnect** が必要なことがある。
- **agmsg チーム `sokki`**：この Claude = `claude`（monitor 稼働）。**`codex` ブリッジは稼働中**（`codex-bridge.js --team sokki` プロセス確認済み・双方向 push 成立）。`~/.agents/skills/agmsg/scripts/send.sh sokki claude codex "<msg>"` で連携可。新セッションでは codex 側の立ち上げ直しが必要なことがある。
- `codex-s-code`（tmux・別プロジェクト s-code・Jun 16）は無関係なので触らない。

## 5. 次にやること（再開ポイント）
1. **P1-3 (#25) E2E 手動確認** ← 今ここ。実機 ⌘R：マイク録音→文字起こし→一覧で録音長表示→詳細→Markdown、`~/Library/Application Support/sokki/recordings/*.m4a` 生成確認。「一番シンプルな動作」の最終確認。Xcode を開いて Xcode MCP 経由でビルド・実行。
2. ~~**#23 / #24 をクローズ**（実装済み・上記コメント例で）。~~ → **完了（2026-07-12）**
3. **P1-4 (#26)** Markdown エクスポート動作確認 → **P1-5 (#27)** ファイル保存ダイアログ + Security-Scoped Bookmark。
4. UI デザイン（**P1-6 #28**）：話者ラベル確定 → 一覧/詳細を同2モードで横展開 → SwiftUI トークン化 → RenderPreview。
5. Phase 2（Core Audio Taps システム音声）着手。**P2-0 (#29) 配布方針の意思決定がブロッカー**なので先に。難所は opus、機械的実装は sonnet に dynamic workflow で委譲する方針。

## 6. 作業スタイル（ユーザー指示・モデル不問で適用）
- 比較的簡単な実装は **sonnet に委譲**、難所は **opus**。**dynamic workflow（Workflow ツール）を積極活用**。委譲は対象ファイル・設計方針・完了条件・規約を明記し、成果はメインでレビュー。

---

## 7. 2026-07-12 セッションの記録（次回はここから読む）

> ⚠️ **セクション 1〜5 は 2026-07-03 時点の記述で一部古い。最新状態は本セクションと backlog（正本）で確認すること。** タスク状態は backlog（`backlog/`）、GitHub Issues は同期ミラー。

### 7.1 このセッションで完了・コミットしたこと（すべて push 済みでなく local commit）
ブランチ `feat/phase1-mvp-finish` に以下を積んだ（新しい順）:
- `c64ec93` chore(backlog): P1-6 完了処理 + TASK-38 追加
- `647cc5e` design(P1-6c): 話者プロファイル / 設定モック（TASK-9.3 / #60 closed）
- `fd7aac9` feat(P1-6b): **SwiftUI デザイントークン基盤**（TASK-9.2 / #59 closed・opus 実装）
- `45a387c` design(P1-6a): 一覧 / 詳細モック（TASK-9.1 / #58 closed）
- `5cd5388` feat(P1-5): エクスポート保存ダイアログ + Security-Scoped Bookmark（TASK-8 / #27 closed）
- `d82240d` docs: タスク正本を backlog へ移行 + design モック追加
- `015852f` chore(backlog): **Backlog.md 導入・正本化**（マイルストーン Phase1〜6、TASK-1〜38+DRAFT-1）

`swift test` は 48 件全 pass（既知 Snapshot 失敗も今回は未発生）。作業ツリーはクリーン、`.claude/` `.codex/` のみ未追跡（ユーザー指示で追跡しない）。

### 7.2 タスク管理の状態
- **backlog が正本**。マイルストーン Phase1〜6、TASK-1〜39 + DRAFT-1。GitHub Issues #23〜#62 が同期ミラー。同期ルールは CLAUDE.md 参照。
- Phase1 の残 To Do: **TASK-39（バグ・最優先）→ TASK-6（E2E, #25）→ TASK-7（Markdown 実機確認, #26）**。TASK-6 は TASK-39 に依存。
- 確定事項: 話者ラベルは**ロケール追従**（ja=話者A / en=Speaker A）。SwiftUI 側は `SpeakerLabel.displayName` として実装済み（`Sources/SokkiKit/DesignSystem/`）。
- デザインモック 5 枚（`docs/design/*.html`）と SwiftUI デザイントークン基盤は完成。ただし**既存画面（RecordingView 等）への再スタイリング（トークン適用）は未着手**＝現状の実機 UI は素の SwiftUI。必要ならタスク新設。

### 7.3 ⚠️ 実機起動で判明したブロッカー: TASK-39 / #62（次回まず対応）
- **症状**: ビルド済み `sokki.app`（DerivedData）の Info.plist に `NSMicrophoneUsageDescription` が無い → 録音時にクラッシュする（macOS 仕様）。**テストでは検出できない実行時バグ。** アプリの起動自体はでき、録音ボタンを押すまでは動くと見込まれる。
- **根本原因（確定済み）**: `project.yml` の `sokki` アプリターゲットの `info:` が `path: Info.plist` のみで **`properties:` を持たない**（HEAD 版 51 行目 `sokki:` → 56 行目付近）。そのため xcodegen 生成の Info.plist に使用目的キーが入らない。
- **修正（ターンキー）**: `sokki` ターゲットの `info:` に `properties:` を足し、`NSMicrophoneUsageDescription` と `NSSpeechRecognitionUsageDescription` を記述 → `xcodegen generate` → クリーンビルド → `plutil -p .../sokki.app/Contents/Info.plist | grep -i microphone` で確認。entitlements（4 権限）は `sokki.entitlements` 側にあり触らない。
- **project.yml は破損していない**（調査中のツール不安定で「マイクキーがある」「依存重複」と誤認したが、安定後の `git show HEAD:project.yml` で否定済み。settings/info/dependencies の複数出現は 3 ターゲットぶんの正常構造）。

### 7.4 環境メモ（重要な更新）
- **Xcode MCP の自動化許可ダイアログ問題は恒久解決済み**（TCC.db 直挿入）。詳細は memory `xcode-automation-tcc.md`。Homebrew で claude が更新されパスが変わると再発しうる（対処手順も同メモに記載）。
- Xcode MCP の `tabIdentifier` はセッションごとに変わる（`windowtab1`→`windowtab2` 等）。`XcodeListWindows` で都度確認。
- **このセッション終盤、大量の PNG（RenderPreview 結果）を Read した後にツール出力が不安定化**（Bash/Read の出力が途中で切れる・幻のテキスト混入）。→ ユーザーに `/clear` を依頼。**破壊的操作の前は必ず `git show`/`git status` で裏取りすること**（この教訓で TASK-39 の誤認を回避できた）。

### 7.5 次にやること（順番）
1. **TASK-39（#62）を修正** — project.yml の sokki ターゲットに info.properties 追加 → xcodegen generate → 再ビルド → plutil でマイク/音声認識キーを確認。
2. **TASK-6（#25）実機 E2E** — ⌘R でマイク録音→文字起こし→一覧の録音長→詳細セグメント→`~/Library/Application Support/sokki/recordings/*.m4a` 生成を確認（マイク操作・許可はユーザー）。
3. **TASK-7（#26）** Markdown エクスポート実機確認（ついでに TASK-8 の「ファイルへ保存…」動作確認）。
4. （任意）既存画面を `SokkiTokens` で再スタイリングするタスクを新設し、モックの見た目に寄せる。
5. Phase1 完了後、Phase2 は **TASK-10（P2-0 配布方針決定）がブロッカー**なので先に。
