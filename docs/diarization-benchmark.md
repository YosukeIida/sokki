# 話者分離（diarization）ベンチマーク手順書

TASK-31「日本語 DER・声紋閾値の実測」用の計測ハーネスと、実測手順をまとめる。
コード側の準備（DER 計算器・RTTM/TSV パーサ・計測テスト）は済んでいる。**実音声での DER 値取得と
Open Question のクローズはこのドキュメントに従ってユーザーが実施する。**

- 参考ベンチ（arXiv 2509.26177）: **Sortformer v2 = 12.7%** / DiariZen = 15.6% / **Pyannote community-1 = 28.8%**
- sokki の diarization は FluidAudio（WeSpeaker ResNet34 + Sortformer 系パイプライン）を採用。
- 声紋照合の暫定閾値は **0.82**（`EmbeddingMatcher` / `SpeakerProfileStore`）。

---

## 1. 何を測るか

| 指標 | 意味 | 出力元 |
|---|---|---|
| **DER**（Diarization Error Rate） | 見逃し + 誤検出 + 話者取り違えの合計 ÷ 総発話時間 | `DERCalculator` |
| missed / falseAlarm / confusion | DER の 3 内訳 | 同上 |
| 話者セントロイド間コサイン類似度 | 別話者どうしが閾値 0.82 で分離できているか | 計測テストが embedding から算出 |

### DER の定義（実装準拠）

共通タイムライン上の各素区間で、リファレンス発話話者数 `N_ref`、仮説発話話者数 `N_sys`、
最適マッピング下の一致話者数 `N_correct` を数え、区間長 `d` で重み付けする:

```
missed     += max(0, N_ref − N_sys) · d
falseAlarm += max(0, N_sys − N_ref) · d
confusion  += (min(N_ref, N_sys) − N_correct) · d
total      += N_ref · d

DER = (missed + falseAlarm + confusion) / total
```

- **話者ラベルの最適マッピング**: リファレンス話者と仮説話者の対応は未知なので、共起時間を最大化する
  一対一マッチングを求める（話者数が少ないので全順列を厳密に評価。詳細は `DERCalculator.swift`）。
  これにより「仮説のラベルが `S1/S2`、正解が `話者A/話者B`」でも正しく対応付く。
- **collar**: `collar > 0` のとき各リファレンス境界の周囲 ±collar（片側半径）をスコア対象外にする。
  境界付近のアノテーション誤差を許容するための仕組みで、CALLHOME 系の評価でよく使われる
  「collar 0.25s」という表記も片側半径として運用されることが多い。
  > **注意**: ただし collar の数値規約（片側半径か全体幅か）はツール・論文によって流儀が分かれる。
  > `SOKKI_DER_COLLAR` は本実装では常に**片側**の半径（秒）を指す。他ツール（pyannote.metrics の
  > `DiarizationErrorRate(collar=...)` 等）の出力と数値を直接突き合わせる場合は、必ずそのツールの
  > ドキュメントで collar 引数の定義を確認すること。同じ数値を渡しても除外幅が異なりうる。
  参考値と厳密に揃えるなら、参照した論文の collar 設定に合わせること（DIHARD は collar 0）。

DER の計算式自体（missed + falseAlarm + confusion を最適マッピング下で集計し、総リファレンス発話時間で
正規化する）は NIST md-eval / pyannote.metrics の `DiarizationErrorRate` と同じ定義で実装している。
したがって Sortformer / Pyannote の公表値とおおむね同じ土俵で比較できるが、**collar の数値規約と
評価コーパス（テストデータの質・話者数・言語）が異なれば数値は単純比較できない**点に注意（下記 6 節）。

---

## 2. 日本語テストデータの用意

CSJ（日本語話し言葉コーパス）は有償・要申請なので、まずは**無償で入手できる複数話者の日本語音声**を使う。
以下から 1 つ選ぶ（いずれも 5〜10 分程度あれば十分に傾向が出る）。

1. **公開されている日本語の対談・座談 podcast / YouTube**（ライセンス・利用規約を確認）
   - 2〜4 名がはっきり交代で話すものが理想。BGM・強い残響・同時発話が少ないものを選ぶ。
   - 収録後、手作業で話者境界をラベル付けする（次節）。
2. **自分たちで録音した会議音声**（最も確実。話者数・境界が既知にできる）。
3. **合成データ**: TTS で話者ごとに読み上げた発話を無音で連結し、正解ラベルを機械生成する。
   セグメント境界が厳密に分かるので DER 計算器の妥当性確認にも使える（ただし実会議より簡単なので DER は楽観的）。

> 実音声ファイルはリポジトリに**コミットしない**（サイズ・著作権）。ローカルの作業ディレクトリに置く。

### 音声フォーマット

`AVAudioFile` が読める形式なら何でもよい（wav / m4a など）。計測テストが内部で 16kHz mono へ変換する
（`AudioFileReader.readMonoSamples`）。理想は 16kHz mono WAV。

---

## 3. 正解ラベル（リファレンス）の作り方

計測ハーネスは **RTTM** と **TSV** の両方を読める（`RTTMParser`）。

### 方法 A: Audacity でラベル付け → TSV 書き出し（手軽）

1. Audacity で音声を開く。
2. 発話区間ごとに **ラベルトラック**（Tracks → Add Label Track）へラベルを打つ。
   - 区間を選択 →「Edit → Labels → Add Label at Selection」。
   - ラベルのテキストに**話者名**を入れる（例: `話者A`, `話者B`）。同一人物は必ず同じ文字列にする。
3. **File → Export → Export Labels** で `.txt` を書き出す。中身は次のタブ区切り 3 列:
   ```
   0.000000	5.250000	話者A
   5.250000	8.100000	話者B
   ```
   これがそのまま TSV リファレンスになる（拡張子は `.tsv` でも `.txt` でもよい。`.rttm` 以外は TSV として解釈）。

### 方法 B: RTTM を直接書く

pyannote など既存ツールと揃えたい場合。`SPEAKER` 行は空白区切りの 10 フィールド:

```
SPEAKER meeting 1 0.000 5.250 <NA> <NA> 話者A <NA> <NA>
SPEAKER meeting 1 5.250 2.850 <NA> <NA> 話者B <NA> <NA>
```

- 4 列目 = 開始秒、5 列目 = **継続秒（duration）**、8 列目 = 話者ラベル。
- `;;` 始まりはコメント、`SPKR-INFO` など `SPEAKER` 以外の型行は無視される。

### ラベル付けの指針

- **話者交代の境界**を優先して正確に。無音・相槌の扱いは一貫させる。
- 同時発話（オーバーラップ）は、正確に測るなら両話者の区間を重ねて記録してよい（計算器はオーバーラップ対応）。
  ただし手間なので、まずは主話者のみの非オーバーラップで測り、必要なら精緻化する。

---

## 4. 計測の実行

環境変数でファイルパスを渡すと、通常はスキップされる計測テストが有効になる。

```bash
SOKKI_DER_AUDIO=/abs/path/audio.wav \
SOKKI_DER_REFERENCE=/abs/path/reference.tsv \
SOKKI_DER_COLLAR=0.25 \
swift test --filter DiarizationBenchmark
```

| 環境変数 | 必須 | 意味 |
|---|---|---|
| `SOKKI_DER_AUDIO` | ○ | 音声ファイルの絶対パス |
| `SOKKI_DER_REFERENCE` | ○ | 正解ラベル（`.rttm` は RTTM、それ以外は TSV） |
| `SOKKI_DER_COLLAR` | – | collar 秒（既定 0.0）。参照ベンチに合わせて設定 |

- **環境変数が未設定なら計測テストは skip され、CI や通常の `swift test` を汚さない。**
- 初回は FluidAudio が Core ML モデルをダウンロードするためネットワークと時間がかかる。
- 出力例（コンソール）:
  ```
  ================ DER Benchmark (TASK-31) ================
  audio      : /abs/path/audio.wav
  reference  : /abs/path/reference.tsv
  collar     : 0.25s
  ref segments: 42 / hyp segments: 39
  ref speakers: 3 / hyp speakers: 3
  --------------------------------------------------------
  DER        : 14.20%
    missed   : 3.10%  (12.40s)
    falseAlrm: 4.00%  (16.00s)
    confusion: 7.10%  (28.40s)
    scored ref total: 400.00s
  speaker map (hyp -> ref): ["S1": "話者A", "S2": "話者B", "S3": "話者C"]
  --------------------------------------------------------
  参考ベンチ: Sortformer v2 = 12.70% / Pyannote community-1 = 28.80%
             DiariZen = 15.60%（arXiv 2509.26177）
  --------------------------------------------------------
  話者セントロイド間コサイン類似度（別話者ペア / 閾値 0.82 の妥当性材料）:
    S1 vs S2 : 0.5130
    S1 vs S3 : 0.6021
    S2 vs S3 : 0.4488
  ========================================================
  ```

---

## 5. 結果の読み方（Sortformer / Pyannote との比較）

- **DER が低いほど良い**。目安: Sortformer v2 の 12.7% に近い〜下回れば非常に良好、Pyannote の 28.8% より
  十分低ければ「FluidAudio 採用は日本語でも妥当」と言える。
- **内訳で原因を切り分ける**:
  - `missed` が大きい → 発話区間の取りこぼし（VAD が弱い / 小声・相槌を拾えていない）。
  - `falseAlarm` が大きい → 無音・雑音を発話と誤認。
  - `confusion` が大きい → 話者数推定または embedding 分離の問題。声紋閾値・話者数のチューニング対象。
- **公平な比較のための注意**（次節）。

---

## 6. 公平な比較の前提（重要）

参考値と DER を厳密に比較するには、以下を揃える必要がある。揃わない場合は「参考」として傾向比較にとどめる。

- **評価コーパス**: 参考値は各論文の評価セット（多くは英語 CALLHOME / DIHARD など）。日本語自作データでの
  絶対値は直接比較できない。**同一データで複数手法を回すのが理想**（例: 同じ音声を pyannote でも回して DER を出す）。
- **collar**: DIHARD は collar 0、CALLHOME 系は 0.25s。参照した値の設定に `SOKKI_DER_COLLAR` を合わせる。
- **オーバーラップの扱い**: オーバーラップ込みで測るか除外するか。本ハーネスは込みで測れるが、正解ラベルの
  精度に依存する。
- したがって本タスクのゴールは「日本語実データで DER の**桁感**を把握し、FluidAudio 採用の妥当性を判断する」こと。

---

## 7. 声紋閾値 0.82 のチューニング

DER（誰がいつ話したか）とは別に、**声紋照合閾値**（同一話者かの判定境界）を日本語で検証する。

### この手順書で得られる材料

計測テストは、diarization が付けた各話者の **embedding セントロイド間コサイン類似度**を出力する。

- **別話者ペアの類似度が 0.82 を明確に下回る** → 閾値 0.82 で別人として正しく弾ける（良好）。
- 別話者ペアが 0.82 付近〜超過（出力に `⚠ >=0.82`）→ 閾値が高すぎて別人を同一視する危険。閾値を上げる方向で再検討。
- 同一話者の別区間どうしの類似度も見たい場合は、TASK-27 の類似度ハーネス
  （`Diagnostics/EmbeddingSimilarityReport.swift`、別ブランチ `feat/task-27`）を併用する。
  同一話者ペアは高く（> 0.82）、別話者ペアは低く（< 0.82）分布していれば 0.82 は妥当。

### 判断の指針

- 理想は「同一話者ペアの最小類似度 > 閾値 > 別話者ペアの最大類似度」。
  この 2 分布の谷（EER 付近）に閾値を置く。
- 誤って別人を統合する（false accept）コストと、同一人物を分けてしまう（false reject）コストの
  どちらを重く見るかで閾値を微調整する。sokki は「話者ラベルの取り違え」を嫌うので、迷ったら閾値をやや高めに保つ。
- 実測後、`SpeakerProfileStore(matchThreshold:)` の既定値、または設定 UI 経由の `updateThreshold(_:)` で反映する。

---

## 8. Open Question のクローズ手順

実測が済んだら `requirements.md` §9 の以下 2 項目を更新する（本タスクの範囲外・ユーザー作業）。

- [ ] 話者分離の日本語 DER 実測 → 実測 DER と比較所見を記入してチェック。
- [ ] 声紋照合閾値の日本語音声での最適値 → 検証結果（0.82 妥当 or 調整値）を記入してチェック。

あわせて backlog TASK-31 の Acceptance Criteria を満たしたら Done にし、Issue #50 を実測サマリでクローズする。
