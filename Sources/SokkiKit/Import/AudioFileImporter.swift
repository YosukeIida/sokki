import AVFoundation
import AppKit
import Foundation
import UniformTypeIdentifiers
import os

/// 音声/動画ファイルのインポートに関するエラー（TASK-34 / P4-3）。
enum AudioFileImportError: Error, LocalizedError {
    case unsupportedFormat(extension: String)
    case emptyAudio
    case audioPreparationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            let label = ext.isEmpty ? "(不明)" : ".\(ext)"
            return "対応していないファイル形式です（\(label)）。.mp4 / .m4a / .wav / .mp3 のみ取り込めます。"
        case .emptyAudio:
            return "音声データを読み取れませんでした（無音または空のファイルの可能性があります）。"
        case .audioPreparationFailed(let error):
            return "音声ファイルの取り込みに失敗しました: \(error.localizedDescription)"
        }
    }
}

/// 既存の録音ファイル（.mp4 / .m4a / .wav / .mp3）を取り込み、文字起こし・話者分離まで実行する（TASK-34 / P4-3）。
///
/// 処理の流れ:
/// 1. ファイル選択（NSOpenPanel）
/// 2. アプリ管理領域へコピー（.mp4 は動画コンテナのため AVAssetExportSession で音声トラックのみ .m4a へ抽出）
/// 3. セッション作成（`SessionModel.captureMode` = "file"）
/// 4. `WhisperKitEngine.transcribe(audioArray:)` によるバッチ文字起こし（全量）
/// 5. 既存の diarization バッチ（`TranscriptionPipeline.diarizeAndAssign`）を呼び出して話者を付与
///
/// 重い処理（ファイル I/O・変換・文字起こし・話者分離）はすべて他 actor（`SessionManager` /
/// `TranscriptionEngine` / `TranscriptionPipeline`）へ await 委譲し、このクラス自身は @MainActor として
/// UI に見せる進捗状態（`isImporting` 等）だけを保持・更新する（CLAUDE.md の Swift 6 方針）。
@Observable
@MainActor
final class AudioFileImporter {

    /// 取り込み対応拡張子（大小文字を無視）。
    static let supportedExtensions: Set<String> = ["mp4", "m4a", "wav", "mp3"]

    /// NSOpenPanel に指定する UTType（.mp4 は動画コンテナのため `.mpeg4Movie`）。
    static let supportedContentTypes: [UTType] = [.mpeg4Movie, .mpeg4Audio, .wav, .mp3]

    private(set) var isImporting = false
    private(set) var importingMessage = ""
    private(set) var importErrorMessage: String?

    private let transcriptionEngine: any TranscriptionEngine
    private let sessionManager: SessionManager
    private let pipeline: TranscriptionPipeline

    private let logger = Logger(subsystem: "com.sokki.app", category: "import")

    init(
        transcriptionEngine: any TranscriptionEngine,
        sessionManager: SessionManager,
        pipeline: TranscriptionPipeline
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.sessionManager = sessionManager
        self.pipeline = pipeline
    }

    /// ファイル選択パネルを表示し、選ばれたファイルを取り込む。パネルがキャンセルされた場合は何もしない。
    func presentOpenPanelAndImport() async {
        let panel = NSOpenPanel()
        panel.title = "音声/動画ファイルを読み込む"
        panel.allowedContentTypes = Self.supportedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard await panel.begin() == .OK, let url = panel.url else { return }
        await importFile(at: url)
    }

    /// 指定 URL のファイルを取り込む（UI・テスト双方から利用できる公開経路）。
    func importFile(at sourceURL: URL) async {
        importErrorMessage = nil
        do {
            try await performImport(sourceURL: sourceURL)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logger.error("ファイルインポートに失敗しました: \(message, privacy: .public)")
            importErrorMessage = message
        }
    }

    /// 利用者がエラーバナーを閉じたときに呼ぶ。
    func dismissImportError() {
        importErrorMessage = nil
    }

    // MARK: - Private

    private func performImport(sourceURL: URL) async throws {
        let sourceExtension = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(sourceExtension) else {
            throw AudioFileImportError.unsupportedFormat(extension: sourceExtension)
        }

        isImporting = true
        importingMessage = "ファイルを取り込み中…"
        defer {
            isImporting = false
            importingMessage = ""
        }

        let title = sourceURL.deletingPathExtension().lastPathComponent
        // mp4（動画コンテナ）は音声トラックのみ抽出して .m4a として保存する（他はそのままコピー）。
        let destinationExtension = sourceExtension == "mp4" ? "m4a" : sourceExtension
        let (sessionID, destinationURL) = try await sessionManager.createImportedSession(
            title: title,
            fileExtension: destinationExtension
        )

        do {
            try await Self.prepareAudioFile(
                sourceURL: sourceURL,
                sourceExtension: sourceExtension,
                destinationURL: destinationURL
            )

            let samples = try await Self.decodeMonoSamples(url: destinationURL)
            guard !samples.isEmpty else { throw AudioFileImportError.emptyAudio }

            importingMessage = "文字起こし中…"
            if await !transcriptionEngine.isReady {
                try await transcriptionEngine.prepare()
            }
            let segments = try await transcriptionEngine.transcribe(audioArray: samples)
            for segment in segments {
                try await sessionManager.appendSegment(segment, toSessionID: sessionID)
            }

            let duration = Double(samples.count) / 16_000
            try await sessionManager.updateDuration(sessionID: sessionID, duration: duration)

            importingMessage = "話者を識別中…"
            // 話者分離は録音経路（TranscriptionPipeline.runDiarizationIfEnabled）と同じく設定でオン/オフされる。
            // ここで確認せず無条件に呼ぶと、設定を無効にしていても声紋モデル推論・プロファイル保存が
            // 実行されてしまい契約に反するため、必ずゲートする。
            if await sessionManager.diarizationEnabled() {
                await pipeline.diarizeAndAssign(audioSamples: samples, sessionID: sessionID)
            }
        } catch {
            // 取り込みに失敗したら中途半端なセッションを残さない（AC #5: 失敗セッションは作らない）。
            try? await sessionManager.deleteSession(persistentID: sessionID)
            if error is AudioFileImportError {
                throw error
            }
            throw AudioFileImportError.audioPreparationFailed(underlying: error)
        }
    }

    /// ソースファイルをアプリ管理領域へコピー、または（mp4 の場合）音声トラックを抽出する。
    /// sandbox 化に備え、ソース URL へは security-scoped アクセスを宣言してから読み取る
    /// （非 sandbox では `start` が false を返しても実害はない・ExportSaveService と同じ方針）。
    ///
    /// `nonisolated` にして MainActor から切り離す: `FileManager.copyItem` は同期・ブロッキング呼び出しであり、
    /// 大きな動画/音声ファイルのコピーで数百 ms〜数秒かかり得る。`@MainActor` のまま呼ぶと UI がフリーズする
    /// ため、await 時にグローバルな並行実行コンテキストへホップさせる（nonisolated な async 関数は
    /// 呼び出し元アクターに留まらない）。
    private nonisolated static func prepareAudioFile(
        sourceURL: URL,
        sourceExtension: String,
        destinationURL: URL
    ) async throws {
        let isAccessingSource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        if sourceExtension == "mp4" {
            try await extractAudioTrack(from: sourceURL, to: destinationURL)
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    /// 変換済みファイルを 16kHz mono Float 配列へデコードする（`AudioFileReader.readMonoSamples` はブロッキング）。
    /// `prepareAudioFile` 同様 `nonisolated` にして MainActor をブロックしないようにする。
    private nonisolated static func decodeMonoSamples(url: URL) async throws -> [Float] {
        try AudioFileReader.readMonoSamples(url: url)
    }

    /// AVAssetExportSession の audio-only プリセットで mp4 の音声トラックのみを .m4a として書き出す。
    /// `AVAudioFile` は動画コンテナを直接開けないため、既存のバッチ経路
    /// （`AudioFileReader` → `transcribe` → `diarizeAndAssign`）に載せられる形へ事前変換する。
    private nonisolated static func extractAudioTrack(from sourceURL: URL, to destinationURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioFileImportError.audioPreparationFailed(
                underlying: NSError(
                    domain: "AudioFileImporter",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "音声トラックの抽出セッションを作成できませんでした。"]
                )
            )
        }
        try await exportSession.export(to: destinationURL, as: .m4a)
    }
}
