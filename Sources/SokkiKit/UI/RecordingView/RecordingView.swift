import SwiftUI
import SwiftData

struct RecordingView: View {
    @State private var captureMode: AudioCaptureManager.CaptureMode = .micOnly
    @State private var errorMessage: String? = nil
    @Environment(AppDependencyContainer.self) private var deps
    @Query private var settingsArray: [AppSettingsModel]
    @Environment(\.modelContext) private var modelContext
    private var pipeline: TranscriptionPipeline { deps.pipeline }

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
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            controlBar
                .padding()
        }
        // 翻訳設定が変わるたびに Coordinator を再評価する（録音中の ON/OFF 切替も含む）。
        .onChange(of: translationSnapshot) { _, snapshot in
            Task { await deps.reconcileTranslation(snapshot) }
        }
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

            Spacer()

            // 録音中のみ表示（TASK-36）。文字起こしは常にローカルなので、翻訳がクラウドを
            // 使っているか（`isCloudActive`）だけでバッジ種別が決まる。
            if pipeline.isRunning {
                processingModeBadge
            }
        }
    }

    /// 「ローカル処理」/「API 使用中」バッジ。状態決定は `ProcessingModeIndicator`
    /// （純粋関数）に切り出してあり、ここでは表示のみを担当する。
    private var processingModeBadge: some View {
        let mode = ProcessingModeIndicator.current(isCloudActive: deps.translationCoordinator.isCloudActive)
        return Label(mode.label, systemImage: mode.systemImage)
            .font(.caption)
            .foregroundStyle(mode == .cloudAPI ? Color.orange : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
            .accessibilityIdentifier("processingModeIndicator")
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

    private var captureModeSelector: some View {
        HStack(spacing: 0) {
            modeButton("Mic", mode: .micOnly)
            modeButton("System", mode: .systemOnly, disabled: true)
            modeButton("Both", mode: .both, disabled: true)
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
                    do {
                        if pipeline.isRunning {
                            try await pipeline.stop()
                        } else {
                            errorMessage = nil
                            // マイク権限チェック
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
                            try await pipeline.start(mode: captureMode, sessionTitle: "")
                        }
                    } catch {
                        errorMessage = error.localizedDescription
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
    RecordingView()
        .environment(AppDependencyContainer.preview(pipeline: PreviewPipeline.idle()))
        .modelContainer(for: AppSettingsModel.self, inMemory: true)
        .frame(width: 600, height: 500)
}

#Preview("ローディング中（ダウンロード進捗あり）") {
    RecordingView()
        .environment(AppDependencyContainer.preview(pipeline: PreviewPipeline.loading()))
        .modelContainer(for: AppSettingsModel.self, inMemory: true)
        .frame(width: 600, height: 500)
}

#Preview("ローディング中（メモリロード・進捗なし）") {
    RecordingView()
        .environment(AppDependencyContainer.preview(pipeline: PreviewPipeline.loadingIntoMemory()))
        .modelContainer(for: AppSettingsModel.self, inMemory: true)
        .frame(width: 600, height: 500)
}

#Preview("録音中（テキストあり）") {
    RecordingView()
        .environment(AppDependencyContainer.preview(pipeline: PreviewPipeline.recordingWithText()))
        .modelContainer(for: AppSettingsModel.self, inMemory: true)
        .frame(width: 600, height: 500)
}
#endif
