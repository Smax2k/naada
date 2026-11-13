import AVFoundation
import CoreAudio
import Darwin
import Foundation
import NaadaCore

/// Sonde de capture en ligne de commande.
///
/// Elle appelle exactement le même moteur que l'interface, mais sort avant
/// toute fenêtre, toute scène et toute activation de l'application. Elle sert
/// à prouver, sans l'interface, quels PID sont réellement tapés, le RMS du
/// callback et celui du MP3 décodé, et l'identité de la sortie par défaut
/// avant/après. La sortie par défaut n'est jamais modifiée.
enum CaptureProbe {
    static let flag = "--capture-probe"
    static let proofFileName = "chrome-capture-proof.json"

    /// Si l'argument est présent, exécute la sonde et termine le processus.
    /// Sinon, rend la main à SwiftUI sans rien créer.
    static func exitIfRequested(arguments: [String]) {
        guard let index = arguments.firstIndex(of: flag) else { return }

        let remaining = Array(arguments.dropFirst(index + 1))
        guard remaining.count >= 2, let pid = pid_t(remaining[0]) else {
            fputs(
                "usage: Naada --capture-probe <pid> <proof-folder> [seconds]\n",
                stderr
            )
            exit(64)
        }

        let folder = URL(fileURLWithPath: remaining[1], isDirectory: true)
        guard isOutsideRecordingsFolder(folder) else {
            fputs(
                "refusing to write the proof inside the recordings folder; use .orchestrator\n",
                stderr
            )
            exit(64)
        }

        let seconds = remaining.count >= 3
            ? (Double(remaining[2]) ?? 5)
            : 5
        run(pid: pid, folder: folder, seconds: seconds)
    }

    private static func run(
        pid: pid_t,
        folder: URL,
        seconds: TimeInterval
    ) -> Never {
        let semaphore = DispatchSemaphore(value: 0)
        let recorder = RMSRecorder()
        let outcome = ProbeOutcome()

        // `Task.detached` : la sonde ne dépend pas du MainActor, que
        // `semaphore.wait()` bloque volontairement jusqu'à la fin de la
        // capture. Aucune fenêtre ni scène n'existe encore.
        Task.detached {
            let engine = AudioCaptureEngine()
            do {
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true
                )

                let writer = try MP3FileWriter(
                    folder: folder,
                    date: Date(),
                    title: "capture-probe"
                )
                engine.onAudioLevel = { level in
                    recorder.record(level)
                }

                let outputBefore = defaultOutputIdentity()
                let application = SourceApplication(
                    pid: pid,
                    name: "PID \(pid)",
                    bundleIdentifier: nil
                )
                try await engine.start(
                    application: application,
                    writer: writer
                )

                let duration = min(60, max(1, seconds))
                try await Task.sleep(
                    nanoseconds: UInt64(duration * 1_000_000_000)
                )

                let diagnostics = engine.captureDiagnostics
                let result = try await engine.stop()
                let outputAfter = defaultOutputIdentity()
                let size = (try? FileManager.default.attributesOfItem(
                    atPath: result.url.path
                )[.size] as? Int) ?? 0
                let decoded = try decodedPCM(url: result.url)
                let callbackRMS = recorder.maximum
                let outputUnchanged = outputBefore != nil
                    && outputAfter != nil
                    && outputBefore == outputAfter
                let requestedRootJSON: Any = diagnostics.requestedRootPID
                    .map { Int($0) as Any } ?? NSNull()
                let outputBeforeJSON: Any = outputBefore
                    .map { $0.json as Any } ?? NSNull()
                let outputAfterJSON: Any = outputAfter
                    .map { $0.json as Any } ?? NSNull()

                var payload: [String: Any] = [
                    "requestedRootPID": requestedRootJSON,
                    "rootIsTranslated": diagnostics.rootIsTranslated,
                    "tappedPIDs": diagnostics.tappedPIDs.map(Int.init),
                    "untranslatedPIDs": diagnostics.untranslatedPIDs.map(Int.init),
                    "processObjectIDs": diagnostics.processObjectIDs.map(Int.init),
                    "callbackRMSMax": Double(callbackRMS),
                    "mp3RMS": Double(decoded.rms),
                    "mp3SampleRate": decoded.sampleRate,
                    "mp3Channels": decoded.channels,
                    "mp3Frames": decoded.frames,
                    "mp3": result.url.path,
                    "bytes": size,
                    "defaultOutputBefore": outputBeforeJSON,
                    "defaultOutputAfter": outputAfterJSON,
                    "defaultOutputUnchanged": outputUnchanged,
                ]
                if let warning = result.warning {
                    payload["warning"] = warning
                }

                payload = try writeProof(payload, to: folder)

                let valid = callbackRMS > 0.02
                    && decoded.rms > 0.02
                    && decoded.frames > 0
                    && decoded.sampleRate == 48_000
                    && decoded.channels == 2
                    && outputUnchanged
                outcome.set(payload: payload, code: valid ? 0 : 3)
            } catch {
                let diagnostics = engine.captureDiagnostics
                let failure: [String: Any] = [
                    "requestedRootPID": diagnostics.requestedRootPID
                        .map { Int($0) } ?? Int(pid),
                    "rootIsTranslated": diagnostics.rootIsTranslated,
                    "tappedPIDs": diagnostics.tappedPIDs.map(Int.init),
                    "untranslatedPIDs": diagnostics.untranslatedPIDs.map(Int.init),
                    "processObjectIDs": diagnostics.processObjectIDs.map(Int.init),
                    "error": error.localizedDescription,
                ]
                let written = (try? writeProof(failure, to: folder)) ?? failure
                outcome.set(payload: written, code: 2)
            }
            semaphore.signal()
        }

        semaphore.wait()
        let result = outcome.result
        emit(result.payload)
        exit(result.code)
    }

    /// Écrit la preuve JSON dans le dossier de preuves et renvoie le payload
    /// complété avec son chemin. Le dossier d'enregistrements humain est déjà
    /// refusé avant l'appel.
    private static func writeProof(
        _ payload: [String: Any],
        to folder: URL
    ) throws -> [String: Any] {
        var written = payload
        let proofURL = folder.appendingPathComponent(proofFileName)
        written["proof"] = proofURL.path
        let data = try JSONSerialization.data(
            withJSONObject: written,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: proofURL, options: .atomic)
        return written
    }

    /// Le dossier de preuve ne doit jamais être le dossier d'enregistrements
    /// choisi par la personne, ni un de ses sous-dossiers.
    private static func isOutsideRecordingsFolder(_ folder: URL) -> Bool {
        guard
            let path = UserDefaults.standard.string(
                forKey: SessionSettingsStore.outputFolderPathKey
            ),
            !path.isEmpty
        else {
            return true
        }

        let recordings = URL(fileURLWithPath: path).standardizedFileURL.path
        let proof = folder.standardizedFileURL.path
        return proof != recordings && !proof.hasPrefix(recordings + "/")
    }

    /// Décode le MP3 produit et mesure son PCM réel. Le succès de la sonde
    /// dépend de ce PCM et du RMS du callback, jamais d'un seul des deux.
    private static func decodedPCM(
        url: URL
    ) throws -> (rms: Float, sampleRate: Double, channels: Int, frames: Int) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard
            frameCount > 0,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            )
        else {
            return (0, format.sampleRate, Int(format.channelCount), 0)
        }

        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else {
            return (0, format.sampleRate, Int(format.channelCount), 0)
        }

        var sumOfSquares = 0.0
        var sampleCount = 0
        for channel in 0..<Int(format.channelCount) {
            let samples = channels[channel]
            for index in 0..<Int(buffer.frameLength) {
                let value = Double(samples[index])
                sumOfSquares += value * value
                sampleCount += 1
            }
        }

        let rms = sampleCount > 0
            ? Float((sumOfSquares / Double(sampleCount)).squareRoot())
            : 0
        return (
            rms,
            format.sampleRate,
            Int(format.channelCount),
            Int(buffer.frameLength)
        )
    }

    /// Lecture seule de la sortie par défaut : aucun réglage n'est écrit.
    private static func defaultOutputIdentity() -> DefaultOutputIdentity? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard
            status == noErr,
            deviceID != AudioObjectID(kAudioObjectUnknown),
            let uid = stringProperty(
                deviceID,
                selector: kAudioDevicePropertyDeviceUID
            ),
            let name = stringProperty(
                deviceID,
                selector: kAudioObjectPropertyName
            )
        else {
            return nil
        }

        return DefaultOutputIdentity(
            deviceID: deviceID,
            uid: uid,
            name: name
        )
    }

    private static func stringProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func emit(_ payload: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys]
            ),
            let text = String(data: data, encoding: .utf8)
        else {
            fputs("NAADA_CAPTURE_PROBE {}\n", stdout)
            return
        }
        print("NAADA_CAPTURE_PROBE \(text)")
        fflush(stdout)
    }
}

/// Identité de la sortie par défaut, lue avant et après la capture.
private struct DefaultOutputIdentity: Equatable {
    let deviceID: AudioObjectID
    let uid: String
    let name: String

    var json: [String: Any] {
        [
            "deviceID": Int(deviceID),
            "uid": uid,
            "name": name,
        ]
    }
}

/// Maximum RMS observé, écrit depuis la file audio et lu après l'arrêt.
private final class RMSRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var maximumValue: Float = 0

    func record(_ level: Float) {
        lock.lock()
        maximumValue = max(maximumValue, level)
        lock.unlock()
    }

    var maximum: Float {
        lock.lock()
        defer { lock.unlock() }
        return maximumValue
    }
}

/// Résultat de la sonde, partagé entre la tâche détachée et le thread qui
/// attend sa fin. Le sémaphore établit l'ordre ; le verrou protège la lecture.
private final class ProbeOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var payload: [String: Any] = [:]
    private var code: Int32 = 2

    func set(payload: [String: Any], code: Int32) {
        lock.lock()
        self.payload = payload
        self.code = code
        lock.unlock()
    }

    var result: (payload: [String: Any], code: Int32) {
        lock.lock()
        defer { lock.unlock() }
        return (payload, code)
    }
}
