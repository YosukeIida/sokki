import SwiftUI

struct SessionDetailView: View {
    let session: SessionModel
    @State private var showingExport = false
    @State private var exportText = ""
    @State private var selectedFormat: ExportFormat = .markdown
    @State private var playback = AudioPlaybackController()

    private let exportService = ExportService()
    private let exportSaveService = ExportSaveService()

    var body: some View {
        VStack(spacing: 0) {
            if hasAudioFile {
                PlaybackBarView(playback: playback)
                Divider()
            }
            SegmentListView(session: session, playback: hasAudioFile ? playback : nil)
        }
        .navigationTitle(session.title)
        .onAppear { loadAudioIfNeeded() }
        .onDisappear { playback.stop() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button("\(format.rawValue) としてコピー") {
                            copyToClipboard(format: format)
                        }
                    }
                    Divider()
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button("\(format.rawValue) としてファイルへ保存…") {
                            Task { await saveToFile(format: format) }
                        }
                    }
                } label: {
                    Label("エクスポート", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func copyToClipboard(format: ExportFormat) {
        let text = exportService.export(session: session, format: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveToFile(format: ExportFormat) async {
        let text = exportService.export(session: session, format: format)
        let fileName = ExportSaveService.suggestedFileName(title: session.title, date: session.createdAt)
        _ = await exportSaveService.save(text: text, suggestedFileName: fileName, contentType: format.contentType)
    }

    /// 音声ファイルが保存されており、かつディスク上に存在するかどうか。
    /// パス未設定・録音中断・削除済みなどで欠落している場合は再生バーを出さない。
    private var hasAudioFile: Bool {
        guard !session.audioFilePath.isEmpty, let url = session.audioFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func loadAudioIfNeeded() {
        guard hasAudioFile, let url = session.audioFileURL else { return }
        playback.load(url: url)
    }
}

/// 再生/一時停止ボタン・シーク用スライダー・現在時刻/総時間ラベルの再生バー（TASK-33）。
private struct PlaybackBarView: View {
    let playback: AudioPlaybackController

    var body: some View {
        HStack(spacing: 12) {
            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .disabled(playback.duration <= 0)
            .accessibilityLabel(playback.isPlaying ? "一時停止" : "再生")

            Text(formatTimestamp(playback.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { playback.currentTime },
                    set: { playback.seek(to: $0) }
                ),
                in: 0...max(playback.duration, 0.01)
            )
            .disabled(playback.duration <= 0)

            Text(formatTimestamp(playback.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
