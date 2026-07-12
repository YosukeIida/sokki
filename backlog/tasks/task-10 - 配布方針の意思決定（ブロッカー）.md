---
id: TASK-10
title: 配布方針の意思決定（ブロッカー）
status: Done
assignee: []
created_date: '2026-07-11 16:35'
updated_date: '2026-07-12 18:56'
labels:
  - Phase2
  - infra
milestone: m-1
dependencies: []
references:
  - 'https://github.com/YosukeIida/sokki/issues/29'
  - >-
    https://dgrlabs.co/blog/2026-04-25-capturing-system-audio-on-macos-in-2026.html
  - 'https://github.com/Homebrew/brew/issues/20755'
priority: high
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布方針を段階的に確定した（Phase2着手のブロッカー解消）。

**決定（2026-07-13）**: 初期は無署名で dmg 配布（GitHub Releases）。Developer ID Program 未登録のため、当面は Gatekeeper 回避手順をドキュメント化して利用者に案内する。Developer ID 取得後、Developer ID 署名 + 公証に移行し、その時点で Homebrew Cask 配布（TASK-37）も検討する。App Store 配布（sandbox 必須）は採用しない。

**調査結果（Web一次情報 + Codex gpt-5.6-luna xhigh による反証検証）**:
1. Core Audio Taps（ProcessTap）は無署名/ad-hoc 署名では TCC prompt が発火しない可能性が高い（複数の実体験報告あり、Apple公式の明文規定は未確認）。→ TASK-11（システム音声キャプチャ）の実機検証は、無署名ビルドでは機能しない可能性があるため要注意。
2. Homebrew は 2026-09-01 に Gatekeeper 非対応 cask のサポートを終了（Homebrew/brew #20755、PR #20973 で実装済み）。Developer ID 署名+公証済みアプリは引き続き Cask と両立する。
3. Mac App Store 配布は Core Audio Taps 使用アプリの前例あり（Phosphor, Faders が sandboxed + notarized で公開）。「App Store は不可能」という当初想定は誤りだったが、Developer ID 未取得の現状では採用しない。

**未確定・今後の課題**:
- 無署名ビルドでの Core Audio Taps 実機動作は未検証（Developer ID 取得後 or ad-hoc 署名での実機確認が必要）
- Gatekeeper 回避手順のドキュメント化（requirements.md の Open Question として継続）
- Developer ID 取得のタイミングは Phase2 着手時期に合わせて別途判断

GitHub Issue #29 (P2-0) 対応。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Core Audio Taps使用時の署名要件（無署名では TCC prompt 不発の可能性）を調査し制約を文書化した
- [x] #2 配布方式を段階的方針（初期=無署名 dmg 配布 / Developer ID取得後=署名+公証+Homebrew Cask）として確定し、requirements.md の NFR-5 と Open Question を更新した
<!-- AC:END -->
