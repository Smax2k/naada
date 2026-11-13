import CoreAudio
import Foundation
import NaadaCore

/// Une entrée de microphone décrite par Core Audio.
///
/// L'identité durable est l'UID, jamais un `AudioObjectID` : celui-ci peut
/// être réattribué après un rebranchement.
struct MicrophoneDevice: Equatable, Sendable {
    let uid: String
    let name: String

    var choice: MicrophoneChoice {
        .selected(uid: uid, name: name)
    }
}

/// Entrée proposée dans le sélecteur de microphone.
///
/// Un microphone mémorisé mais absent de la liste courante y figure quand
/// même, marqué indisponible : la sélection reste visible et aucun démarrage
/// n'est tenté avec elle.
struct MicrophoneOption: Identifiable, Equatable {
    let choice: MicrophoneChoice
    let name: String
    let isAvailable: Bool

    var id: MicrophoneChoice { choice }
}

/// Énumération en lecture seule des entrées audio du système.
///
/// Aucun flux n'est ouvert, aucun périphérique n'est démarré, aucune
/// permission n'est demandée : seules les propriétés de description de Core
/// Audio sont lues. `AVCaptureDevice` n'est jamais utilisé.
enum MicrophoneCatalog {
    /// Microphones d'entrée disponibles, triés par nom.
    static func devices() -> [MicrophoneDevice] {
        var seenUIDs = Set<String>()

        return deviceIDs()
            .compactMap { deviceID -> MicrophoneDevice? in
                guard hasInputStreams(deviceID),
                      let uid = stringProperty(
                          deviceID,
                          selector: kAudioDevicePropertyDeviceUID
                      ),
                      !uid.isEmpty
                else {
                    return nil
                }
                guard seenUIDs.insert(uid).inserted else { return nil }

                let name = stringProperty(
                    deviceID,
                    selector: kAudioObjectPropertyName
                )
                return MicrophoneDevice(
                    uid: uid,
                    name: normalized(name) ?? uid
                )
            }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if order == .orderedSame {
                    return lhs.uid < rhs.uid
                }
                return order == .orderedAscending
            }
    }

    /// Nom affichable de l'entrée système par défaut, s'il en existe une.
    ///
    /// Sert uniquement à nommer le choix « microphone système par défaut » :
    /// rien n'est ouvert ni démarré.
    static func defaultInputDeviceName() -> String? {
        guard let deviceID = defaultInputDeviceID() else { return nil }
        return normalized(
            stringProperty(deviceID, selector: kAudioObjectPropertyName)
        )
    }

    /// Vrai si une entrée d'entrée système par défaut existe, même si son nom
    /// ne peut pas être lu.
    static func hasDefaultInputDevice() -> Bool {
        defaultInputDeviceID() != nil
    }

    // MARK: - Core Audio

    private static func deviceIDs() -> [AudioDeviceID] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            systemObject,
            &address,
            0,
            nil,
            &size
        ) == noErr, size > 0 else {
            return []
        }

        let stride = MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](
            repeating: AudioDeviceID(kAudioObjectUnknown),
            count: Int(size) / stride
        )
        let status = devices.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else {
                return OSStatus(-1)
            }
            return AudioObjectGetPropertyData(
                systemObject,
                &address,
                0,
                nil,
                &size,
                baseAddress
            )
        }
        guard status == noErr else { return [] }

        return Array(devices.prefix(Int(size) / stride))
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            systemObject,
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return nil
        }
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    /// Vrai si le périphérique expose au moins un flux d'entrée.
    ///
    /// Seule la taille de la liste de flux est lue : aucun flux n'est ouvert.
    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return false
        }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
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
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension MicrophoneChoice {
    /// UID Core Audio du micro précis, ou `nil` pour les choix génériques.
    var microphoneUID: String? {
        guard case let .selected(uid, _) = self else { return nil }
        return uid
    }

    /// Nom lisible indépendamment de la liste courante.
    ///
    /// Sert à nommer une source mémorisée qui manque, sans replier
    /// silencieusement sur une autre.
    var rememberedDisplayName: String {
        switch self {
        case .none:
            return NSLocalizedString("No microphone", comment: "No microphone choice")
        case .systemDefault:
            return NSLocalizedString("System default microphone", comment: "System default microphone choice")
        case let .selected(uid, name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? uid : trimmed
        }
    }
}
