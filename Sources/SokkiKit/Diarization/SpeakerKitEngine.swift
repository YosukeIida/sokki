import Foundation
import SpeakerKit

actor SpeakerKitEngine: DiarizationEngine {

    private var speakerKit: SpeakerKit?
    private let numberOfSpeakers: Int?

    private(set) var isReady = false

    init(numberOfSpeakers: Int? = nil) {
        self.numberOfSpeakers = numberOfSpeakers
    }

    func prepare() async throws {
        do {
            speakerKit = try await SpeakerKit()
            isReady = true
        } catch {
            throw DiarizationEngineError.modelLoadFailed(underlying: error)
        }
    }

    func diarize(audioArray: [Float]) async throws -> DiarizationResult {
        guard let sk = speakerKit else { throw DiarizationEngineError.notPrepared }

        let options = PyannoteDiarizationOptions(
            numberOfSpeakers: numberOfSpeakers,
            clusterDistanceThreshold: 0.6,
            useExclusiveReconciliation: false
        )
        let result = try await sk.diarize(audioArray: audioArray, options: options)

        let segments = result.segments.map { seg in
            let speakerLabel: String
            if let id = seg.speaker.speakerId {
                speakerLabel = String(format: "SPEAKER_%02d", id)
            } else {
                speakerLabel = "SPEAKER_UNKNOWN"
            }
            return DiarizationSegment(
                start: TimeInterval(seg.startTime),
                end: TimeInterval(seg.endTime),
                speakerID: speakerLabel,
                embedding: nil  // Phase 3 で実装（SpeakerKit は埋め込みを直接公開しない）
            )
        }

        return DiarizationResult(
            segments: segments,
            numberOfSpeakers: result.speakerCount
        )
    }
}
