# sokki

macOS 15+ ネイティブ音声文字起こしアプリ。Swift Package Manager + SwiftUI + SwiftData。

## 重要ドキュメント

- `HANDOVER_20260527_0057.md` — 現在の進捗・未完了タスク・次のステップ（最初に読む）
- `spec.md` — アーキテクチャ仕様書・設計判断ログ
- `requirements.md` — 機能要件・非機能要件

## ビルド

```bash
swift package resolve   # 初回のみ（WhisperKit モデルのダウンロード含む）
xed .                   # Xcode で開く
```

## 注意事項

- macOS 15+ / Apple Silicon 専用
- `argmax-oss-swift` v1.0 に WhisperKit と SpeakerKit が同梱
- SwiftData モデルは `[Float]` を直サポートしないため `Data` 変換で保存している（`SpeakerProfileModel.embeddingData`）
- 音声キャプチャは単一 SCStream で `.audio` / `.microphone` レーン分岐（デュアルSCStream は使わない）
