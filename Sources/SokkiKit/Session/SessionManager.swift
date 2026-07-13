import Foundation
import SwiftData

@ModelActor
actor SessionManager {

    func createSession(title: String, mode: AudioCaptureManager.CaptureMode) throws -> PersistentIdentifier {
        let path = makeAudioFilePath(title: title)
        let session = SessionModel(title: title, audioFilePath: path, captureMode: mode.rawValue)
        modelContext.insert(session)
        try modelContext.save()
        return session.persistentModelID
    }

    func appendSegment(_ segment: any TranscriptionSegment, toSessionID sessionID: PersistentIdentifier) throws {
        guard let session = modelContext.model(for: sessionID) as? SessionModel else { return }
        let model = SegmentModel(start: segment.start, end: segment.end, text: segment.text)
        model.avgLogProb = segment.avgLogProb
        model.session = session
        modelContext.insert(model)
        try modelContext.save()
    }

    /// diarization 結果をセッションのセグメントへ時間区間の重なりで割り当てる（P3）。
    ///
    /// 各 `SegmentModel` に対し、最も時間が重なる `DiarizationSegment` の話者ラベルを採用し、
    /// `profileMapping`（speakerID → プロファイル識別子）から対応する `SpeakerProfileModel` を紐づける。
    /// `SpeakerProfileModel` は @Model のため actor 境界を越えられない。ここでは Sendable な
    /// `PersistentIdentifier` を受け取り、この actor のコンテキスト内で解決する（CLAUDE.md 規約）。
    /// 精緻なマージ（境界の再調整など）は TASK-26 スコープ。
    func assignSpeakersByOverlap(
        sessionID: PersistentIdentifier,
        diarizationSegments: [DiarizationSegment],
        profileMapping: [String: PersistentIdentifier]
    ) throws {
        guard let session = modelContext.model(for: sessionID) as? SessionModel else { return }

        var resolvedProfiles: [String: SpeakerProfileModel] = [:]
        for (speakerID, profileID) in profileMapping {
            if let profile = modelContext.model(for: profileID) as? SpeakerProfileModel {
                resolvedProfiles[speakerID] = profile
            }
        }

        for segment in session.segments {
            guard let speakerID = Self.bestOverlapSpeaker(
                segmentStart: segment.start,
                segmentEnd: segment.end,
                diarizationSegments: diarizationSegments
            ) else { continue }
            segment.speakerLabel = speakerID
            if let profile = resolvedProfiles[speakerID] {
                segment.speakerProfile = profile
            }
        }
        try modelContext.save()
    }

    /// 設定モデルの diarization 有効フラグ。未保存の場合は既定値（有効）とみなす。
    func diarizationEnabled() -> Bool {
        let descriptor = FetchDescriptor<AppSettingsModel>()
        guard let settings = try? modelContext.fetch(descriptor).first else { return true }
        return settings.diarizationEnabled
    }

    /// セグメントとの時間の重なり（話者ごとの合計）が最大になる diarization 話者ラベルを返す。
    /// 重なりが無ければ nil。同一話者が複数区間に分かれていても合計で評価する
    /// （単一区間の最大値だと、細切れに長く話した話者より一区間だけ長い別話者を誤選択する）。
    /// 合計が同値の場合は speakerID の辞書順で決定的に選ぶ。
    private static func bestOverlapSpeaker(
        segmentStart: Double,
        segmentEnd: Double,
        diarizationSegments: [DiarizationSegment]
    ) -> String? {
        var totals: [String: Double] = [:]
        for d in diarizationSegments {
            let overlap = min(segmentEnd, d.end) - max(segmentStart, d.start)
            guard overlap > 0 else { continue }
            totals[d.speakerID, default: 0] += overlap
        }
        return totals.max { a, b in
            if a.value != b.value { return a.value < b.value }
            return a.key > b.key   // 同値時は辞書順で小さい speakerID を優先
        }?.key
    }

    func updateDuration(sessionID: PersistentIdentifier, duration: Double) throws {
        guard let session = modelContext.model(for: sessionID) as? SessionModel else { return }
        session.durationSeconds = duration
        try modelContext.save()
    }

    /// セッションの録音ファイル URL（録音書き出し先・P1-1）。
    func audioURL(forSessionID sessionID: PersistentIdentifier) -> URL? {
        guard let session = modelContext.model(for: sessionID) as? SessionModel else { return nil }
        return URL(fileURLWithPath: session.audioFilePath)
    }

    func allSessions() throws -> [SessionModel] {
        let descriptor = FetchDescriptor<SessionModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func sessionCount() throws -> Int {
        let descriptor = FetchDescriptor<SessionModel>()
        return try modelContext.fetchCount(descriptor)
    }

    func segmentCount(forSessionID sessionID: PersistentIdentifier) throws -> Int {
        guard let session = modelContext.model(for: sessionID) as? SessionModel else { return 0 }
        return session.segments.count
    }

    func firstSegmentText(forSessionID sessionID: PersistentIdentifier) throws -> String? {
        guard let session = modelContext.model(for: sessionID) as? SessionModel else { return nil }
        return session.segments.first?.text
    }

    func deleteSession(_ sessionID: UUID) throws {
        let descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.id == sessionID }
        )
        guard let session = try modelContext.fetch(descriptor).first else { return }
        if let audioFileURL = session.audioFileURL {
            try? FileManager.default.removeItem(at: audioFileURL)
        }
        modelContext.delete(session)
        try modelContext.save()
    }

    private func makeAudioFilePath(title: String) -> String {
        let dir = Self.recordingsBaseDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "\(title)_\(UUID().uuidString.prefix(8)).m4a"
        return dir.appendingPathComponent(filename).path
    }

    /// XCUITest が production の録音を汚染しないよう、環境変数 `SOKKI_UITEST_RECORDINGS_DIR`
    /// が設定されている場合はそのディレクトリを保存先として使う。
    private static func recordingsBaseDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["SOKKI_UITEST_RECORDINGS_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("sokki/recordings", isDirectory: true)
    }
}
