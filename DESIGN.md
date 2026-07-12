---
version: alpha
name: sokki-design-system
description: "macOS 15+ 向けネイティブ音声文字起こしアプリ sokki のデザインシステム。既定は Console（ダーク・鎮めた計器盤）— content-bg #1a1e24 の上にティール1点アクセント #35a597、mic/sys 2レーンの同軸波形が浮かぶ。ライトへ切り替えると Manuscript（冷たい紙・墨・朱）— content-bg #fafaf8 に紺 #2b4a78 のアクセントと朱 #c23b2c の録音インジケータが乗る、和紙のような温度感の文書面になる。フォントはシステムフォント（SF Pro Text / SF Mono）のみで自前のディスプレイ書体は持たない。派手な装飾・グラデーションを避け、「計器」と「原稿用紙」という2つの実在物の比喩で情報密度を制御する。競合の Pindrop（誠実で開放的なホワイトスペース）・SuperIntern（高コントラストなビジネス的信頼感）と同じ「音声文字起こしツール」市場に立つが、sokki は Web マーケティングサイトではなくネイティブアプリの内部 UI として一貫させる。"

colors:
  # Console（ダーク・既定）— 出典: docs/design/recording-view-v2.html .dir-console
  console-content-bg: "#1a1e24"
  console-titlebar: "#1e232a"
  console-sidebar: "#171b20"
  console-transcript-bg: "#16191e"
  console-controls-bg: "#171b20"
  console-seg-bg: "#13161b"
  console-line: "#2a2f37"
  console-text: "#e3e6eb"
  console-muted: "#939ba7"
  console-faint: "#626a76"
  console-accent: "#35a597"
  console-accent-on: "#042420"
  console-good: "#4fb48f"
  console-rec: "#d9534c"
  console-mic: "#6e96c9"
  console-sys: "#c27c6e"
  console-trans-rail: "#2e7e74"

  # Manuscript（ライト）— 出典: docs/design/recording-view-v2.html .dir-manuscript
  manuscript-content-bg: "#fafaf8"
  manuscript-titlebar: "#eeefec"
  manuscript-sidebar: "#f1f2f0"
  manuscript-transcript-bg: "#fbfbf9"
  manuscript-controls-bg: "#f1f2f0"
  manuscript-seg-bg: "#e9eae6"
  manuscript-line: "#e1e3df"
  manuscript-text: "#21242b"
  manuscript-muted: "#5e6571"
  manuscript-faint: "#9aa0a6"
  manuscript-accent: "#2b4a78"
  manuscript-accent-on: "#ffffff"
  manuscript-good: "#3c7a50"
  manuscript-rec: "#c23b2c"
  manuscript-mic: "#486593"
  manuscript-sys: "#a06b50"
  manuscript-trans-rail: "#c8d0dc"

  # 話者パレット（テーマ共通・声紋に紐づく固定色）
  speaker-a: "#4c7fc0"
  speaker-b: "#3e9d6a"
  speaker-c: "#7c5cff"

typography:
  window-title:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 13px
    fontWeight: 540
    lineHeight: 1.3
  nav-item:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 13.5px
    fontWeight: 520
    lineHeight: 1.3
  segment-label:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 12.5px
    fontWeight: 520
    lineHeight: 1.2
  status-chip:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 11.5px
    fontWeight: 560
    lineHeight: 1.2
  wave-caption:
    fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace"
    fontSize: 10px
    fontWeight: 400
    letterSpacing: 0.04em
  speaker-label:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 11.5px
    fontWeight: 560
    lineHeight: 1.2
  timestamp:
    fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace"
    fontSize: 10.5px
    fontWeight: 500
    fontVariantNumeric: tabular-nums
  transcript-body:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.55
  transcript-translation:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 13.5px
    fontWeight: 400
    lineHeight: 1.5
  transcript-hypothesis:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.55
  elapsed-timer:
    fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace"
    fontSize: 15px
    fontWeight: 400
    fontVariantNumeric: tabular-nums
  section-heading:
    fontFamily: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
    fontSize: 11px
    fontWeight: 600
    letterSpacing: 0.08em
    textTransform: uppercase

rounded:
  xs: 2px
  sm: 4px
  md: 7px
  lg: 8px
  xl: 12px
  pill: 999px
  full: 50%

spacing:
  xxs: 2px
  xs: 4px
  sm: 8px
  base: 12px
  md: 14px
  lg: 16px
  xl: 18px

components:
  window:
    backgroundColor: "{colors.content-bg}"
    borderColor: "{colors.line}"
    rounded: "{rounded.xl}"
  titlebar:
    backgroundColor: "{colors.titlebar}"
    borderColor: "{colors.line}"
    height: 40px
  sidebar:
    backgroundColor: "{colors.sidebar}"
    borderColor: "{colors.line}"
    width: 196px
    padding: 12px 10px
  nav-item:
    textColor: "{colors.text}"
    typography: "{typography.nav-item}"
    rounded: "{rounded.md}"
    padding: 7px 10px
  nav-item-active:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent-on}"
    typography: "{typography.nav-item}"
    rounded: "{rounded.md}"
  capture-mode-segment:
    backgroundColor: "{colors.seg-bg}"
    borderColor: "{colors.line}"
    rounded: "{rounded.lg}"
    padding: 2px
  capture-mode-segment-item-active:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent-on}"
    typography: "{typography.segment-label}"
    rounded: "{rounded.md}"
  status-chip-local:
    backgroundColor: "color-mix(in srgb, {colors.good} 12%, transparent)"
    textColor: "{colors.good}"
    typography: "{typography.status-chip}"
    rounded: "{rounded.pill}"
    padding: 4px 9px
  toggle-switch:
    backgroundColor: "{colors.accent}"
    rounded: "{rounded.pill}"
    width: 30px
    height: 18px
  waveform-bar-mic:
    backgroundColor: "{colors.mic}"
    width: 3px
    gap: 4px
    rounded: "{rounded.xs}"
  waveform-bar-sys:
    backgroundColor: "{colors.sys}"
    width: 3px
    gap: 4px
    rounded: "{rounded.xs}"
  transcript-line:
    textColor: "{colors.text}"
    typography: "{typography.transcript-body}"
    padding: 0
  transcript-line-translated:
    borderColor: "{colors.trans-rail}"
    textColor: "{colors.muted}"
    typography: "{typography.transcript-translation}"
    padding: 0 0 0 12px
  speaker-color-bar:
    width: 3px
    rounded: "{rounded.xs}"
  record-button-idle:
    backgroundColor: "{colors.rec}"
    size: 56px
    rounded: "{rounded.full}"
  record-button-recording:
    backgroundColor: "{colors.rec}"
    borderColor: "color-mix(in srgb, {colors.rec} 50%, transparent)"
    size: 56px
    rounded: "{rounded.full}"
  session-row:
    textColor: "{colors.text}"
    typography: "{typography.nav-item}"
    padding: 4px 0
  export-menu-button:
    textColor: "{colors.text}"
    typography: "{typography.nav-item}"
    rounded: "{rounded.md}"
---

## Overview

sokki は「計器」と「原稿用紙」という2つの実在物の比喩で情報密度を制御する、macOS 15+ 向けネイティブ音声文字起こしアプリのデザインシステムである。Web マーケティングサイトの派手なブランド表現とは異なり、sokki は録音中に長時間見つめ続けるアプリ内部の作業画面であるため、装飾よりも「読みやすさ」「録音状態の一目での把握」を優先する。

システムは2つの明確なテーマを持ち、どちらもユーザーが `SokkiAppearance`（システム / ライト / ダーク）で切り替える：

1. **Console**（ダーク・既定）— `{colors.console-content-bg}` #1a1e24 を基調とした「鎮めた計器盤」。ティール `{colors.console-accent}` #35a597 のみを彩度の高い色として使い、mic/sys 2レーンの同軸波形（`{colors.console-mic}` 青灰 / `{colors.console-sys}` 橙灰）が中心的なビジュアル要素になる。
2. **Manuscript**（ライト）— `{colors.manuscript-content-bg}` #fafaf8 を基調とした「冷たい紙・墨・朱」。紺 `{colors.manuscript-accent}` #2b4a78 のアクセントと、朱 `{colors.manuscript-rec}` #c23b2c の録音インジケータが、原稿用紙に赤入れするような文書感を作る。

フォントは **自前のディスプレイ書体を持たない**。本文・UI ラベルはシステムサンセリフ（`-apple-system` / SF Pro Text）、タイムスタンプ・波形キャプション・経過時間表示はシステム等幅（SF Mono / Menlo）のみで構成する。これは Linear や ElevenLabs のような「ブランド専用書体で差別化する」戦略とは逆方向で、sokki は macOS ネイティブに完全に溶け込むことを選んでいる。

**Key Characteristics:**
- ダーク（Console）を既定とする。ティール1点アクセントのみが彩度を持ち、他は無彩色〜低彩度グレーのレンジに収める。
- ライト（Manuscript）は白ではなく温かみのないクールな紙色 `#fafaf8` を使い、朱 `#c23b2c` の録音インジケータと紺 `#2b4a78` のアクセントで「墨で書かれた原稿に朱で校正が入る」文書メタファーを維持する。
- mic（自分の声）と sys（相手の声・システム音）を常に異なる色相のペアで区別する — Console では青灰 vs 橙灰、Manuscript では紺 vs 焦茶。話者パレット（青・緑・紫の3色巡回）とは独立した軸。
- 角丸は 2px（波形バー）〜12px（ウィンドウ）の狭いレンジに収め、CTA・トグルのみ 999px のピル形状を使う。カード的な「浮いた面」はほぼ存在せず、区切りは背景色の階調変化と 1px の hairline で表現する。
- タイムスタンプ・経過時間・波形キャプションは必ず等幅数字（tabular figures）。
- 翻訳行は左レール（`{colors.trans-rail}`）2px のボーダーで示す — カードではなく罫線でセグメント化する Manuscript の思想を翻訳表示にも適用している。

## Colors

> **テーマ解決についての注記**: このセクション以降・および `components:` 内で使われる `{colors.content-bg}` `{colors.line}` `{colors.accent}` のようなプレフィックスなし参照は、frontmatter の `colors:` に列挙した `console-*` / `manuscript-*` いずれかへ実行時に解決される**セマンティックロール名**を指す（例: `{colors.accent}` は Console 実効時 `console-accent` #35a597、Manuscript 実効時 `manuscript-accent` #2b4a78）。SwiftUI 実装では `SokkiTokens.resolve(for:)` と `@Environment(\.sokkiTokens)` がこの解決を担う（`Sources/SokkiKit/DesignSystem/SokkiAppearance.swift`）。話者パレット（`speaker-a/b/c`）のみテーマに依存せず常に固定値を指す。

### Console（ダーク・既定）
- **Content BG** (`{colors.console-content-bg}` — #1a1e24): ウィンドウ全体の基調色。
- **Titlebar** (`{colors.console-titlebar}` — #1e232a): タイトルバー。
- **Sidebar** (`{colors.console-sidebar}` — #171b20): サイドバー背景。content-bg よりわずかに暗い。
- **Transcript BG** (`{colors.console-transcript-bg}` — #16191e): 文字起こし本文の背景。content-bg よりわずかに暗く、読み込む面として区別する。
- **Controls BG** (`{colors.console-controls-bg}` — #171b20): 録音コントロールバーの背景。
- **Segment BG** (`{colors.console-seg-bg}` — #13161b): モード切替セグメントの溝の色。全面色中もっとも暗い。
- **Line** (`{colors.console-line}` — #2a2f37): 罫線・区切り線。
- **Text** (`{colors.console-text}` — #e3e6eb): 本文・見出しの主色。
- **Muted** (`{colors.console-muted}` — #939ba7): 話者ラベル・ナビ非活性文字。
- **Faint** (`{colors.console-faint}` — #626a76): タイムスタンプ・キャプションなど最弱の階調。
- **Accent** (`{colors.console-accent}` — #35a597): 唯一の彩度アクセント。アクティブなナビ・セグメント・トグルに使用。
- **Accent On** (`{colors.console-accent-on}` — #042420): アクセント面の上に乗る前景色。
- **Good** (`{colors.console-good}` — #4fb48f): 「ローカル処理中」等の肯定的ステータス。
- **Rec** (`{colors.console-rec}` — #d9534c): 録音インジケータ・録音ボタン。
- **Mic** (`{colors.console-mic}` — #6e96c9): マイク波形レーン。
- **Sys** (`{colors.console-sys}` — #c27c6e): システム音声波形レーン。
- **Trans Rail** (`{colors.console-trans-rail}` — #2e7e74): 翻訳あり行の左レール。

### Manuscript（ライト）
- **Content BG** (`{colors.manuscript-content-bg}` — #fafaf8): 冷たい紙色の基調。純白ではない。
- **Titlebar** (`{colors.manuscript-titlebar}` — #eeefec)
- **Sidebar** (`{colors.manuscript-sidebar}` — #f1f2f0)
- **Transcript BG** (`{colors.manuscript-transcript-bg}` — #fbfbf9)
- **Controls BG** (`{colors.manuscript-controls-bg}` — #f1f2f0)
- **Segment BG** (`{colors.manuscript-seg-bg}` — #e9eae6)
- **Line** (`{colors.manuscript-line}` — #e1e3df)
- **Text** (`{colors.manuscript-text}` — #21242b): 純黒ではない墨色。
- **Muted** (`{colors.manuscript-muted}` — #5e6571)
- **Faint** (`{colors.manuscript-faint}` — #9aa0a6)
- **Accent** (`{colors.manuscript-accent}` — #2b4a78): 紺。アクティブなナビ・セグメント。
- **Accent On** (`{colors.manuscript-accent-on}` — #ffffff)
- **Good** (`{colors.manuscript-good}` — #3c7a50)
- **Rec** (`{colors.manuscript-rec}` — #c23b2c): 朱。校正の朱入れを思わせる録音インジケータ。
- **Mic** (`{colors.manuscript-mic}` — #486593)
- **Sys** (`{colors.manuscript-sys}` — #a06b50)
- **Trans Rail** (`{colors.manuscript-trans-rail}` — #c8d0dc)

### 話者パレット（テーマ共通）
声紋に紐づく固定色。ライト/ダークで変化しない — 話者の色は「その人自身」を指す識別子であり、テーマ切り替えで揺らいではならない。
- **Speaker A** (`{colors.speaker-a}` — #4c7fc0): 青
- **Speaker B** (`{colors.speaker-b}` — #3e9d6a): 緑
- **Speaker C** (`{colors.speaker-c}` — #7c5cff): 紫
- 4人以上は先頭に戻って巡回する（4人以上のスケーリングはオープンクエスチョン）。

## Typography

### Font Family
sokki は自前のディスプレイ書体を持たない。すべて macOS システムフォントで構成する。
- **UI・本文**: `-apple-system`（実体は SF Pro Text）、フォールバック `system-ui, sans-serif`
- **等幅（タイムスタンプ・経過時間・波形キャプション）**: `ui-monospace`（実体は SF Mono）、フォールバック `Menlo, monospace`

### Hierarchy

| Token | Size | Weight | Use |
|---|---|---|---|
| `{typography.window-title}` | 13px | 540 | タイトルバーのセッション名 |
| `{typography.nav-item}` | 13.5px | 520 | サイドバーナビ・セッション一覧行 |
| `{typography.segment-label}` | 12.5px | 520 | Mic/System/Both 切替セグメント |
| `{typography.status-chip}` | 11.5px | 560 | 「オンデバイス」等のステータスバッジ |
| `{typography.speaker-label}` | 11.5px | 560 | 話者ラベル（Speaker A 等） |
| `{typography.timestamp}` | 10.5px | 500 | 行頭タイムスタンプ（等幅数字） |
| `{typography.wave-caption}` | 10px | 400 | 波形レーンのキャプション（mono） |
| `{typography.transcript-body}` | 15px | 400 | 確定済み文字起こし本文 |
| `{typography.transcript-hypothesis}` | 15px | 400 | 未確定（流動中）の仮説テキスト |
| `{typography.transcript-translation}` | 13.5px | 400 | 翻訳行 |
| `{typography.elapsed-timer}` | 15px | 400 | 録音経過時間（等幅数字） |
| `{typography.section-heading}` | 11px | 600 | セクション見出し（大文字・トラッキング広め） |

### Principles
- **等幅数字は「動く数字」専用。** タイムスタンプ・経過時間・波形キャプションのみ mono。本文・ラベルは全てシステムサンセリフ。
- **ウェイトは 400/500/520/540/560/600 の細かい刻みを使うが、太字（700+）は使わない。** 強調は色（accent）と面（アクティブ背景）で行い、ウェイトでの強調は最小限に留める。
- **仮説テキスト（未確定の文字起こし）は本文と同じサイズ・ウェイトだが `faint` 色。** カーソルのような点滅記号（`▏`）を末尾に付け、「まだ確定していない」ことを視覚的に示す。

## Layout

### Spacing System
- **Base unit**: 2px。
- **Tokens**: `{spacing.xxs}` 2px · `{spacing.xs}` 4px · `{spacing.sm}` 8px · `{spacing.base}` 12px · `{spacing.md}` 14px · `{spacing.lg}` 16px · `{spacing.xl}` 18px。
- コントロールバー・文字起こし領域の内側パディングは `{spacing.lg}`〜`{spacing.xl}`（16–18px）。セグメント・トグルなど小さなコントロールは `{spacing.xxs}`〜`{spacing.xs}`（2–4px）。

### Window & Sidebar Structure
Web の Grid & Container の代わりに、sokki は `NavigationSplitView` 相当の 2 ペイン構成を基本とする。
- サイドバー幅: 196px 固定（`{component.sidebar}`）。
- コンテンツ領域: 残り全幅（`min-width: 0` で内部の折り返しを許可）。
- タイトルバー高さ: 40px 固定、macOS 標準のトラフィックライト（赤黄緑）と共存する。

### Whitespace Philosophy
sokki は「密度を絞った計器盤」であり、Web マーケティングサイトのような大きな余白（96px セクション間隔など）は取らない。文字起こし本文は行間 1.5–1.55 で読みやすさを確保しつつ、コントロール要素（chip・segment・toggle）は詰めて配置し、画面を占有する面積を最小化する。Manuscript テーマのみ、文字起こし領域に `max-width: 640px` の読み幅制限をかけ、原稿用紙的な縦長のリズムを作る（Console にはこの制限を課さない — 計器盤は全幅を使う）。

## Elevation & Depth

sokki は **ドロップシャドウをほぼ使わない**。奥行きは「面の階調差」と「1px の罫線」のみで表現する。

| Level | Treatment | Use |
|---|---|---|
| Content BG | `{colors.content-bg}` | ウィンドウ全体の基調 |
| Titlebar / Sidebar / Controls | それぞれ専用トークン（content-bg よりわずかに暗い/明るい） | 面の役割分担 |
| Transcript BG | content-bg よりわずかに暗い（Console）/ わずかに明るい（Manuscript） | 読み込む本文面を独立させる |
| Segment BG | 全面色中もっとも暗い/濃い | 切替コントロールの「溝」表現 |
| Hairline | 1px `{colors.line}` | 全ての面の区切り |
| ウィンドウの外部シャドウ | `0 24px 60px -24px rgba(20,22,30,.45), 0 2px 8px rgba(0,0,0,.08)` | ウィンドウ自体が背景から浮く唯一のシャドウ（デザインモック上の演出。実アプリでは OS のウィンドウシャドウに委譲） |

### Decorative Depth
- 装飾的な奥行き表現は持たない。唯一の「装飾」は mic/sys 波形の動き（アニメーション）と、録音中インジケータの pulse アニメーション（1.8s ease-in-out、`prefers-reduced-motion` 尊重）。

## Shapes

### Border Radius Scale

| Token | Value | Use |
|---|---|---|
| `{rounded.xs}` | 2px | 波形バー、話者カラーバー |
| `{rounded.sm}` | 4px | 予備 |
| `{rounded.md}` | 7px | ナビ項目、トグルの土台 |
| `{rounded.lg}` | 8px | セグメントコントロール |
| `{rounded.xl}` | 12px | ウィンドウ全体 |
| `{rounded.pill}` | 999px | ステータスチップ、トグルスイッチ、録音ボタン外周 |
| `{rounded.full}` | 50% | トラフィックライト、話者ドット、録音ボタン本体 |

角丸は「小さい要素ほど鋭角寄り（2px）、大きい面ほど緩やか（12px）、操作系トグルはピル（999px）」という一貫した論理を持つ。カード的な浮いた面がほぼ存在しないため、Web の DESIGN.md によくある「カード border-radius」の概念は薄く、代わりに「面の境界」の角丸が中心になる。

## Components

### Titlebar & Sidebar

**`titlebar`** — 高さ 40px。背景 `{colors.titlebar}`、下に 1px `{colors.line}` の罫線。セッション名を `{typography.window-title}` で中央〜左寄せ表示。

**`sidebar`** — 幅 196px 固定。背景 `{colors.sidebar}`、右に 1px `{colors.line}` の罫線。セクション見出し（`{typography.section-heading}`）+ ナビ項目のリスト。

**`nav-item`** / **`nav-item-active`** — 非活性時は透明背景・`{colors.text}` の文字。活性時は `{colors.accent}` 背景 + `{colors.accent-on}` 文字、`{rounded.md}` の角丸。

### Capture Mode Segment

**`capture-mode-segment`** — Mic / System / Both を切り替えるセグメントコントロール。背景 `{colors.seg-bg}`（全面色中最も濃い「溝」）、1px `{colors.line}` 枠、内側パディング 2px、`{rounded.lg}`。

**`capture-mode-segment-item-active`** — 選択中の項目のみ `{colors.accent}` 背景に反転する。

### Status & Toggle

**`status-chip-local`** — 「オンデバイス処理中」を示す常時表示バッジ。背景は `{colors.good}` の 12% 透過、文字 `{colors.good}`、`{rounded.pill}`、パディング 4px×9px。先頭に currentColor のドットを持つ。

**`toggle-switch`** — 翻訳 ON/OFF 等のトグル。幅 30px・高さ 18px、背景 `{colors.accent}`、`{rounded.pill}`。つまみは白円、右寄せで ON を示す。

### Waveform

**`waveform-bar-mic`** / **`waveform-bar-sys`** — 幅 3px の縦棒、間隔 4px、`{rounded.xs}`（2px）。mic レーンは `{colors.mic}`、sys レーンは `{colors.sys}`。Both モードでは中心線を挟んで mic が上・sys が下に伸びる同軸波形（`wave-dual`）になる。

### Transcript

**`transcript-line`** — 確定済みの1発話単位。話者ラベル（`{typography.speaker-label}` + 話者ドット + `{typography.timestamp}`）を上段、本文（`{typography.transcript-body}`）を下段に積む。

**`transcript-line-translated`** — 翻訳がある行のみ、左に `{colors.trans-rail}` の 2px ボーダーを立て、内側パディング 12px を取る。翻訳文は本文の下に `{typography.transcript-translation}`（`{colors.muted}`）で表示。

**`transcript-hypothesis`** — 未確定の流動テキスト。本文と同サイズだが `{colors.faint}`、末尾にカーソル状の `▏` を付ける。

**`speaker-color-bar`** — 話者インデックスから解決した色（`speaker-a/b/c` の巡回）を幅 3px・`{rounded.xs}` の縦バーで表示する。

### Controls & Record Button

**`record-button-idle`** — 56px 円形、`{colors.rec}` のグリフ（録音時は停止アイコンに切り替え）。

**`record-button-recording`** — アイドルと同形状に加え、`{colors.rec}` の 50% 透過で 3px のリングを外側に足す。リングとタイマー横のドットは 1.8s の pulse アニメーション（`prefers-reduced-motion: reduce` では静止）。

**`elapsed-timer`** — `{typography.elapsed-timer}`（等幅・tabular-nums）、録音中のみ先頭に `{colors.rec}` のドット（pulse）を伴う。

### Session List & Export

**`session-row`** — セッション一覧の1行。タイトル（`{typography.nav-item}` 相当）+ 日時 + duration + セグメント数のメタ行（`faint` 色）。

**`export-menu-button`** — Markdown/SRT/VTT/テキストへのコピー、ファイル保存を提供するメニューボタン。特別な装飾は持たず、macOS 標準のメニュー外観に委ねる。

## Do's and Don'ts

### Do
- ダーク（Console）を既定として設計し、ライト（Manuscript）は「同じ情報構造の別テーマ」として同時に成立させる。片方だけで機能する UI 決定をしない。
- アクセントカラー（`{colors.accent}`）は「今アクティブなもの」だけに使う。ナビの選択状態・セグメントの選択状態・トグルの ON 状態、これ以外に広げない。
- mic/sys の色分けと話者 A/B/C の色分けは常に独立した軸として扱う。同じ色相を再利用して混同させない。
- タイムスタンプ・経過時間・波形キャプションは必ず等幅数字にする。
- 面の区切りは 1px hairline と背景階調差で表現し、ドロップシャドウやカード浮遊を持ち込まない。

### Don't
- 彩度の高い色を Console のアクセント（ティール）以外に追加しない。ElevenLabs のような多色グラデーションはブランド方針として採用しない。
- Manuscript を「ダークの反転」として機械的に作らない。朱・墨・紙という独立したメタファーを持つ配色として設計する。
- 太字（700+）で強調しない。強調は色（accent）・面（アクティブ背景）・階調（faint/muted/text）で行う。
- カード的な浮いた面（角丸+shadow+padding の組み合わせ）を安易に増やさない。sokki の面は「役割ごとの背景色 + 罫線」であり、Web SaaS 的なカードコンポーネントの多用は避ける。
- 話者パレット（A/B/C の3色）をテーマ（Console/Manuscript）で変えない。声紋に紐づく識別子は不変。

## Platform Behavior

sokki は Web ではなく macOS ネイティブアプリであるため、Responsive Behavior（ブレークポイント）の代わりに、ウィンドウリサイズとサイドバーの挙動を定義する。

### Window Resizing
- サイドバー幅は 196px 固定 — ウィンドウリサイズで伸縮しない。
- コンテンツ領域（文字起こし・詳細）はウィンドウ幅に追従して伸縮する。Manuscript のみ `max-width: 640px` の読み幅制限を持ち、それ以上は左右に余白ができる。
- 最小ウィンドウ幅は、コントロールバー（記録ボタン + タイマー + スペーサー）が折り返さない幅を下限とする。

### Sidebar Collapsing
- `NavigationSplitView` 標準の挙動に従い、ウィンドウが十分に狭い場合はサイドバーがオーバーレイ化する（macOS 標準ジェスチャー・ボタンで開閉）。sokki 独自のカスタム折りたたみロジックは持たない。

### Pointer & Keyboard
- クリックターゲットの最小サイズは Apple HIG に従う（目安 22×22pt 以上）。ナビ項目・セグメント項目はパディング込みでこれを満たす。
- 録音ボタンは十分に大きい 56px 円で、誤操作を避ける。

## Reference Inspirations

sokki 自体の色・タイポグラフィは `docs/design/*.html` のモックが正（このドキュメントはその体系化）。以下は「トーン・構造」の参照元であり、色そのものの模倣元ではない。

- **[Pindrop](https://pindropstt.com/)** — 同じ音声入力・文字起こし市場の実プロダクト。「誠実で開放的なホワイトスペース」「Privacy-First」の打ち出し方は、sokki のプライバシーモード表現（オンデバイスバッジ）の参考になる。
- **[SuperIntern](https://super-intern.com/en)** — 同じ会議文字起こし市場の実プロダクト。モノトーン基調・高コントラストな「ビジネス的信頼感」は、Manuscript テーマの墨・朱の緊張感と方向性が近い。
- **[ElevenLabs](https://getdesign.md/elevenlabs/design-md)**（voltagent/awesome-design-md）— audio-waveform を主要なビジュアル要素として扱う構造が、sokki の mic/sys 波形表示の設計と直接的に対応する。ただし ElevenLabs の「パステルグラデーションオーブ」は sokki には採用しない（彩度アクセントはティール1点のみという方針と矛盾するため）。
- **[Linear](https://getdesign.md/linear.app/design-md)**（voltagent/awesome-design-md）— 「彩度の高い色は1つだけ、面は階調ラダーで積む、ドロップシャドウをほぼ使わない」という構造的な思想が、sokki の Console テーマの設計原則そのものと一致する。
- **[aeru（和える）](https://a-eru.co.jp/)**（kzhrknt/awesome-design-md-jp）— 朱色 `#c73120` をブランドカラーに据え、和紙のような温かみのあるオフホワイトを面色にする構成は、Manuscript テーマの「朱の録音インジケータ + 冷たい紙面」という設計方針の裏付けになる（ただし aeru は温かみのあるオフホワイトなのに対し、sokki の Manuscript は意図的に「冷たい」紙を選んでいる点で異なる）。

## Iteration Guide

1. 色は必ず `{colors.xxx}` トークン参照で扱う。hex を直接コンポーネントに埋め込まない。
2. Console と Manuscript は常にペアで検討する。片方のテーマだけで意思決定をしない。
3. 新しいアクセント色が必要に思えたら、まず「本当に Do's and Don'ts に反しないか」を確認する。ほとんどの場合、階調（muted/faint）か罫線で解決できる。
4. コンポーネントを追加するときは `components:` に別エントリとして追加し、既存コンポーネントを上書きしない。
5. macOS ネイティブ実装（SwiftUI）が正。この DESIGN.md は `Sources/SokkiKit/DesignSystem/SokkiTokens.swift` 等の実装コードと矛盾してはならない — 変更が生じたら両方を同時に更新する。

## Known Gaps

- 話者プロファイル画面・設定画面（`docs/design/speaker-profile-v1.html` / `settings-v1.html`）のコンポーネント詳細は本ドキュメントに未反映。今後 SessionDetailView 等の再スタイリング作業と合わせて拡充する。
- Pindrop / SuperIntern は Web 上のマーケティングサイトの外観からの推測に基づく参照であり、正確な色コード・フォントは未確認（sokki のトークンを直接引いてはいない）。
- ダーク/ライト以外の中間テーマ（例: 高コントラストモード）は現時点で未定義。
- アニメーション仕様は pulse（録音インジケータ）のみ定義済み。波形の描画更新レート・トランジションのイージングは未文書化。
