import Darwin
import Foundation

/// Fichier de sortie créé de façon exclusive : `O_CREAT | O_EXCL` garantit
/// qu'un fichier existant n'est jamais tronqué, même en cas de course.
public struct CreatedRecordingFile {
    public let url: URL
    public let handle: FileHandle
}

public enum RecordingFile {
    public static func create(
        in folder: URL,
        date: Date,
        title: String,
        timeZone: TimeZone = .current
    ) throws -> CreatedRecordingFile {
        for attempt in 1...10_000 {
            let name = RecordingName.candidateFileName(
                date: date,
                title: title,
                attempt: attempt,
                timeZone: timeZone
            )
            let url = folder.appendingPathComponent(name, isDirectory: false)

            let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
            if descriptor >= 0 {
                return CreatedRecordingFile(
                    url: url,
                    handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                )
            }

            if errno != EEXIST {
                throw RecordingFileError.cannotCreate(
                    path: url.path,
                    code: errno
                )
            }
        }

        throw RecordingNameError.noAvailableName
    }
}

public enum RecordingFileError: Error, LocalizedError {
    case cannotCreate(path: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case let .cannotCreate(path, code):
            let reason = String(cString: strerror(code))
            return String(
                format: NSLocalizedString(
                    "Could not create “%@”: %@.",
                    bundle: .main,
                    comment: "Recording file creation error with path and reason"
                ),
                path,
                reason
            )
        }
    }
}
