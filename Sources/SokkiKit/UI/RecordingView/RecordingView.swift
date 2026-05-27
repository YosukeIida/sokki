import SwiftUI

struct RecordingView: View {
    @State private var captureMode: AudioCaptureManager.CaptureMode = .micOnly
    @State private var errorMessage: String? = nil
    @Environment(AppDependencyContainer.self) private var deps
    private var pipeline: TranscriptionPipeline { deps.pipeline }

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
                    errorBanner(err)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            controlBar
                .padding()
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(pipeline.loadingMessage)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Button { errorMessage = nil } label: {
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
        .frame(width: 600, height: 500)
}

#Preview("ローディング中") {
    RecordingView()
        .environment(AppDependencyContainer.preview(pipeline: PreviewPipeline.loading()))
        .frame(width: 600, height: 500)
}

#Preview("録音中（テキストあり）") {
    RecordingView()
        .environment(AppDependencyContainer.preview(pipeline: PreviewPipeline.recordingWithText()))
        .frame(width: 600, height: 500)
}
#endif
