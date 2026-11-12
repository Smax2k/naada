import Foundation
import NaadaCore

enum RecorderPhase: Equatable {
    case idle
    case preparing
    case recording
    case stopping
    case failed(String)

    init(_ state: RecordingSessionState) {
        switch state {
        case .idle:
            self = .idle
        case .preparing:
            self = .preparing
        case .recording:
            self = .recording
        case .stopping:
            self = .stopping
        case let .failed(message):
            self = .failed(message)
        }
    }

    var isBusy: Bool {
        switch self {
        case .preparing, .recording, .stopping:
            return true
        case .idle, .failed:
            return false
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle:
            return NSLocalizedString("Ready", comment: "Recorder phase label")
        case .preparing:
            return NSLocalizedString("Preparing", comment: "Recorder phase label")
        case .recording:
            return NSLocalizedString("Recording", comment: "Recorder phase label")
        case .stopping:
            return NSLocalizedString("Finalizing", comment: "Recorder phase label")
        case .failed:
            return NSLocalizedString("Error", comment: "Recorder phase label")
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return NSLocalizedString(
                "Choose an application and a folder, then start.",
                comment: "Recorder idle detail"
            )
        case .preparing:
            return NSLocalizedString("Connecting to the audio source…", comment: "Recorder preparing detail")
        case .recording:
            return NSLocalizedString(
                "System sound stays audible during capture.",
                comment: "Recorder recording detail"
            )
        case .stopping:
            return NSLocalizedString("Writing the last MP3 frame…", comment: "Recorder stopping detail")
        case let .failed(message):
            return message
        }
    }
}
