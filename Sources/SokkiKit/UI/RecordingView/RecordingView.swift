import SwiftUI

struct RecordingView: View {
    @State private var captureMode: AudioCaptureManager.CaptureMode = .micOnly
    @State private var errorMessage: String? = nil
    @Environment(AppDependencyContainer.self) private var deps
    @Environment(\.sokkiTokens) private var tokens
    private var pipeline: TranscriptionPipeline { deps.pipeline }

    // フローティング字幕（TASK-19）。原文列を持つ SubtitleFeed と、それを載せる
    // フローティングパネルの所有者を View で保持する。
    // NOTE: 文字起こしパイプライン→feed.pushConfirmed の結線と TranslationCoordinator の
    // 注入は上流（TASK-14 系列）マージ後の統合。本ブランチではトグルでパネルを開閉できるが
    // 訳文レーンは Coordinator 注入まで「翻訳中…」表示のままになる。
    @State private var subtitleFeed = SubtitleFeed()
    @State private var floatingSubtitle: FloatingSubtitleController?
    @State private var floatingSubtitleVisible = false

    var body: some View {
        VStack(spacing: 0) {
            captureModeSelector
                .padding(.horizontal)
                .padding(.top, 12)

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
        .onChange(of: pipeline.isRunning) { _, isRunning in
            // 録音停止でフローティング字幕トグルは UI から消えるが、パネル自体は自動では
            // 閉じないため、放置すると最前面に残り続ける（トグルも消えて閉じる手段が無くなる）。
            // 録音停止を明示的なセッション境界として扱い、ここで破棄する。
            if !isRunning {
                floatingSubtitle?.close()
                floatingSubtitleVisible = false
            }
        }
        .onDisappear {
            // 所有者による明示破棄（@MainActor クラスの AppKit 破棄は deinit に頼らない）。
            floatingSubtitle?.close()
            floatingSubtitleVisible = false
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

            // フローティング字幕トグル（TASK-19）。
            // TODO(上流マージ後): 表示条件を settings.translationEnabled に絞る。
            // 現状は「翻訳有効」の設定信号が本ブランチに無いため録音中のみ提示する。
            if pipeline.isRunning {
                floatingSubtitleToggle
            }
        }
    }

    private var floatingSubtitleToggle: some View {
        Button {
            toggleFloatingSubtitle()
        } label: {
            Image(systemName: floatingSubtitleVisible ? "captions.bubble.fill" : "captions.bubble")
                .font(.system(size: 20))
                .foregroundStyle(floatingSubtitleVisible ? tokens.accent : .secondary)
        }
        .buttonStyle(.plain)
        .help("フローティング字幕")
        .accessibilityIdentifier("floatingSubtitleToggle")
    }

    private func toggleFloatingSubtitle() {
        let controller = floatingSubtitle ?? {
            // TranslationCoordinator は上流マージ後に attach する（訳文レーン有効化の結線点）。
            let c = FloatingSubtitleController(feed: subtitleFeed, tokens: tokens)
            floatingSubtitle = c
            return c
        }()
        controller.toggle()
        floatingSubtitleVisible = controller.isVisible
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
        .frame(width: 600, height: 500)
}

#Preview("ローディング中（ダウンロード進捗あり）") {
    RecordingView()
        .environment(AppDependencyContainer.preview(pipeline: PreviewPipeline.loading()))
        .frame(width: 600, height: 500)
}

#Preview("ローディング中（メモリロード・進捗なし）") {
    RecordingView()
        .environment(AppDependencyContainer.preview(pipeline: PreviewPipeline.loadingIntoMemory()))
        .frame(width: 600, height: 500)
}

#Preview("録音中（テキストあり）") {
    RecordingView()
        .environment(AppDependencyContainer.preview(pipeline: PreviewPipeline.recordingWithText()))
        .frame(width: 600, height: 500)
}
#endif
