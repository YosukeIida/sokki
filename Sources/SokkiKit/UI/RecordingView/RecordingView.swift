import SwiftUI
import SwiftData

struct RecordingView: View {
    @State private var captureMode: AudioCaptureManager.CaptureMode = .micOnly
    @State private var errorMessage: String? = nil
    @Environment(AppDependencyContainer.self) private var deps
    @Environment(\.sokkiTokens) private var tokens
    @Query private var settingsArray: [AppSettingsModel]
    @Environment(\.modelContext) private var modelContext
    private var pipeline: TranscriptionPipeline { deps.pipeline }
    private var meetingDetector: MeetingDetector { deps.meetingDetector }
    private var meetingDetectionEnabled: Bool { settingsArray.first?.meetingDetectionEnabled ?? false }
    private var transcriptionLanguage: String { settingsArray.first?.transcriptionLanguage ?? "auto" }

    private var settings: AppSettingsModel {
        if let s = settingsArray.first { return s }
        let s = AppSettingsModel()
        modelContext.insert(s)
        return s
    }

    private var translationSnapshot: TranslationSettingsSnapshot {
        TranslationSettingsSnapshot(settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            captureModeSelector
                .padding(.horizontal)
                .padding(.top, 12)

            translationToggleBar
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()
                .padding(.top, 8)

            if pipeline.isRunning {
                levelMeterBand
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()
            }

            ZStack {
                LiveTranscriptView(
                    segments: pipeline.confirmedSegments,
                    hypothesis: pipeline.hypothesisText
                )

                if pipeline.isLoading {
                    loadingOverlay
                }

                if let err = errorMessage {
                    errorBanner(err) { errorMessage = nil }
                } else if let saveErr = pipeline.recordingSaveErrorMessage {
                    errorBanner(saveErr) { pipeline.dismissRecordingSaveError() }
                } else if let notice = pipeline.transcriptionNoticeMessage {
                    errorBanner(notice) { pipeline.dismissTranscriptionNotice() }
                } else if !pipeline.isRunning, let suggestion = meetingDetector.suggestion {
                    meetingSuggestionBanner(suggestion)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            controlBar
                .padding()
        }
        // 翻訳設定が変わるたびに Coordinator を再評価する（録音中の ON/OFF 切替も含む）。
        // initial: true — `onChange` は初期表示では発火しないため、これが無いと
        // 前回セッションで translationEnabled=true のまま永続化された状態でこの
        // View を開いても（≒ アプリ再起動直後）Coordinator は非アクティブのまま
        // 同期されず、トグルは ON 表示なのに実体は未起動という不整合が残る
        // （TASK-20 レビュー指摘）。`reconcile` 自身が冒頭で必ず `teardown()` して
        // から再評価するため、表示のたびに呼んでも冪等・安全。
        .onChange(of: translationSnapshot, initial: true) { _, snapshot in
            Task { await deps.reconcileTranslation(snapshot) }
        }
        .onAppear { syncMeetingDetection() }
        .onDisappear { syncMeetingDetection() }
        .onChange(of: meetingDetectionEnabled) { _, _ in syncMeetingDetection() }
        .onChange(of: pipeline.isRunning) { _, _ in syncMeetingDetection() }
    }

    /// 録音中でも切り替えられる翻訳 ON/OFF の軽量トグル。詳細設定（プロバイダ/言語）は
    /// SettingsView に置く。
    ///
    /// macOS の `.switch` スタイル Toggle は Form/List 外では title を視覚表示しないため、
    /// 独立した Text をラベルとして添える（`.labelsHidden()` で Toggle 側の重複表示を抑止）。
    private var translationToggleBar: some View {
        HStack(spacing: 6) {
            Text("翻訳")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle("翻訳", isOn: Binding(
                get: { settings.translationEnabled },
                set: { settings.translationEnabled = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityIdentifier("translationToggle")
        }
    }

    /// 設定（ON/OFF）と録音中かどうかから、会議検出ポーリングの開始/停止を決める。
    /// OFF の間は `start()` を呼ばないため SCShareableContent には一切触れない。
    ///
    /// `deps.meetingDetector` は `AppDependencyContainer` が保持する単一のインスタンスで、
    /// `ContentView` はサイドバーの `NavigationLink` 先と detail の既定表示の2箇所に
    /// `RecordingView()` を持つ。ナビゲーション遷移中は一方の `onDisappear` ともう一方の
    /// `onAppear` が前後不定の順で発火しうるため、`onDisappear` でも無条件に `stop()` せず
    /// この関数（現在の望ましい状態を毎回再計算する冪等な処理）に統一している。
    /// これによりどちらが先に発火しても最終的な状態は「有効かつ非録音中なら動作中」に収束する。
    private func syncMeetingDetection() {
        if meetingDetectionEnabled {
            if pipeline.isRunning {
                // 録音中はポーリングを止めるが、拒否状態は維持する（pause）。
                // 録音の開始は会議の終了ではないため、ここで stop() すると
                // 「拒否 → 手動録音 → 録音停止」で同じ会議が再提案されてしまう。
                meetingDetector.pause()
            } else {
                meetingDetector.start()
            }
        } else {
            meetingDetector.stop()
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            if let progress = pipeline.downloadProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 220)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
            }
            Text(pipeline.loadingMessage)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
    }

    private func errorBanner(_ message: String, onDismiss: @escaping () -> Void) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding()
            Spacer()
        }
    }

    /// mic=青 / system=赤の実レベルメーター（TASK-13）。captureMode に応じて表示するレーンを切り替える:
    /// `.micOnly` はマイクのみ、`.systemOnly` はシステムのみ、`.both` は 2 本並べて両方表示する。
    @ViewBuilder
    private var levelMeterBand: some View {
        switch captureMode {
        case .micOnly:
            levelMeterColumn(label: "マイク", stream: pipeline.micLevelStream, color: tokens.mic)
        case .systemOnly:
            levelMeterColumn(label: "システム", stream: pipeline.systemLevelStream, color: tokens.sys)
        case .both:
            HStack(spacing: 16) {
                levelMeterColumn(label: "マイク", stream: pipeline.micLevelStream, color: tokens.mic)
                levelMeterColumn(label: "システム", stream: pipeline.systemLevelStream, color: tokens.sys)
            }
        }
    }

    private func levelMeterColumn(label: String, stream: AsyncStream<Float>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tokens.faint)
            }
            WaveformView(levelStream: stream, color: color)
                .frame(height: 58)
        }
    }

    private func meetingSuggestionBanner(_ suggestion: MeetingCandidate) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .foregroundStyle(.blue)
                Text("\(suggestion.app.displayName) の会議を検出しました。録音を開始しますか？")
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Button("後で") {
                    meetingDetector.dismissCurrentSuggestion()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button("開始") {
                    meetingDetector.acceptCurrentSuggestion()
                    Task { await startRecording() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding()
            Spacer()
        }
        .accessibilityIdentifier("meetingSuggestionBanner")
    }

    /// マイク権限チェックを行った上で録音を開始する。録音ボタンと会議検出バナーの「開始」から共有する。
    private func startRecording() async {
        errorMessage = nil
        let status = PermissionManager.microphoneStatus()
        if status == .denied {
            errorMessage = "マイクへのアクセスが拒否されています。システム設定 > プライバシーとセキュリティ > マイク で許可してください。"
            return
        }
        if status == .notDetermined {
            let granted = await PermissionManager.requestMicrophoneAccess()
            if !granted {
                errorMessage = "マイクへのアクセスが必要です。"
                return
            }
        }
        do {
            try await pipeline.start(
                mode: captureMode,
                sessionTitle: "",
                transcriptionLanguage: transcriptionLanguage
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var captureModeSelector: some View {
        HStack(spacing: 0) {
            modeButton("Mic", mode: .micOnly)
            modeButton("System", mode: .systemOnly, disabled: true)
            modeButton("Both", mode: .both)
        }
        .fixedSize()
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private func modeButton(_ label: String, mode: AudioCaptureManager.CaptureMode, disabled: Bool = false) -> some View {
        Button {
            captureMode = mode
        } label: {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    captureMode == mode
                        ? Color.accentColor
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .foregroundStyle(
                    disabled ? Color.secondary :
                    (captureMode == mode ? Color.white : Color.primary)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled || pipeline.isRunning)
        .help(disabled ? "Phase 2 で実装予定" : "")
    }

    private var controlBar: some View {
        HStack {
            if pipeline.isRunning {
                Text(formatElapsed(pipeline.elapsedSeconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    if pipeline.isRunning {
                        do {
                            try await pipeline.stop()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } else {
                        await startRecording()
                    }
                }
            } label: {
                Image(systemName: pipeline.isRunning ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(pipeline.isRunning ? .red : .primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recordStopButton")

            Spacer()
        }
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

#if DEBUG
#Preview("アイドル") {
    let deps = AppDependencyContainer.preview(pipeline: PreviewPipeline.idle())
    RecordingView()
        .environment(deps)
        .modelContainer(deps.modelContainer)
        .frame(width: 600, height: 500)
}

#Preview("ローディング中（ダウンロード進捗あり）") {
    let deps = AppDependencyContainer.preview(pipeline: PreviewPipeline.loading())
    RecordingView()
        .environment(deps)
        .modelContainer(deps.modelContainer)
        .frame(width: 600, height: 500)
}

#Preview("ローディング中（メモリロード・進捗なし）") {
    let deps = AppDependencyContainer.preview(pipeline: PreviewPipeline.loadingIntoMemory())
    RecordingView()
        .environment(deps)
        .modelContainer(deps.modelContainer)
        .frame(width: 600, height: 500)
}

#Preview("録音中（テキストあり）") {
    let deps = AppDependencyContainer.preview(pipeline: PreviewPipeline.recordingWithText())
    RecordingView()
        .environment(deps)
        .modelContainer(deps.modelContainer)
        .frame(width: 600, height: 500)
}
#endif
