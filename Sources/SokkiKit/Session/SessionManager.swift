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

    func assignSpeakers(
        segmentIDs: [UUID],
        profileMapping: [String: SpeakerProfileModel],
        speakerLabels: [UUID: String]
    ) throws {
        for segmentID in segmentIDs {
            let descriptor = FetchDescriptor<SegmentModel>(
                predicate: #Predicate { $0.id == segmentID }
            )
            guard let segment = try modelContext.fetch(descriptor).first else { continue }
            if let label = speakerLabels[segmentID],
               let profile = profileMapping[label] {
                segment.speakerProfile = profile
                segment.speakerLabel = label
            }
        }
        try modelContext.save()
    }

    func updateDuration(sessionID: PersistentIdentifier, duration: Double) throws {
        guard let session = modelContext.model(for: sessionID) as? SessionModel else { return }
        session.durationSeconds = duration
        try modelContext.save()
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
        modelContext.delete(session)
        try modelContext.save()
    }

    private func makeAudioFilePath(title: String) -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("sokki/recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "\(title)_\(UUID().uuidString.prefix(8)).m4a"
        return dir.appendingPathComponent(filename).path
    }
}
