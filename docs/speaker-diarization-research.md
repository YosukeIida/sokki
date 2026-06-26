<!-- sokki 調査ドキュメント / 生成: 2026-06-26 / 話者分離(diarization)の技術選定 -->
> 注: 本書は調査エージェントが返した要点ダイジェスト。

# 話者分離実装調査 — 主要ファインディング

## argmax SpeakerKit v1.0

- ベースモデル: Pyannote v4 community-1 (Core ML)、< 10MB、macOS 13+
- WhisperKit との統合: `addSpeakerInfo()` が内蔵されており数行で完了。マージ戦略は `.subsegment`（単語ギャップで分割）と `.segment` の 2 種
- **日本語 DER: 28.8%**（arXiv 2509.26177 評価）— Pyannote v4 は日本語が苦手
- **埋め込み取り出し API: v1.0 時点で未確認**。voiceprint 機能は「今後の予定」として言及のみ
- リアルタイム処理: OSS 版はバッチのみ。ストリーミングは商用の Pro SDK（Sortformer）専用
- ライセンス: MIT（商用可）

## FluidAudio

- diarization エンジン 3 種: Offline（バッチ、DER 10.62%）/ LS-EEND（ストリーミング 100ms、DER 26.2%）/ Sortformer（80ms、最大 4 話者）
- **`extractEmbedding()` が public API として明示的に存在**。256 次元 L2 正規化済みで sokki の `SpeakerProfileStore` 設計と完全一致
- `SpeakerManager.initializeKnownSpeakers()` でセッション横断 ID も文書化済み
- ライセンス: Apache 2.0
- WhisperKit との統合は自前実装が必要（ただし ~30 行程度）

## 日本語 DER 比較（arXiv 2509.26177）

| モデル | 日本語 DER |
|---|---|
| Sortformer v2 | **12.7%** |
| PyannoteAI (商用) | 13.8% |
| DiariZen | 15.6% |
| Pyannote (OSS community-1) | 28.8% |

## sokki 推奨

**Phase 1（今すぐ）**: SpeakerKit v1.0 で始める（統合が最も簡単）。ただし先に GitHub でembedding API の有無を確認。

**Phase 1.5（SpeakerProfileStore 統合時）**: FluidAudio に切り替え。`extractEmbedding()` が確実に使えるため。

**Phase 2（リアルタイム録音）**: FluidAudio Sortformer（macOS 15+ 必須、日本語 DER が大幅に改善）。

**sherpa-onnx・WhisperX**: ANE 非対応または Python 専用のため sokki では非採用。WhisperX はマージアルゴリズムの参照実装として参考にする。
