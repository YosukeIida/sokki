import AVFoundation

@MainActor
enum PermissionManager {

    enum Status {
        case granted
        case denied
        case notDetermined
    }

    static func microphoneStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:       return .granted
        case .denied, .restricted: return .denied
        case .notDetermined:    return .notDetermined
        @unknown default:       return .denied
        }
    }

    static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
