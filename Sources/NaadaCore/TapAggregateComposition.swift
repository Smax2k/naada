import Foundation

/// Clés du dictionnaire d'agrégat Core Audio, recopiées comme chaînes pures
/// pour que ce plan reste testable sans ouvrir de périphérique audio. Les
/// tests comparent ces valeurs aux constantes du SDK.
public enum TapAggregateKey {
    public static let name = "name"
    public static let uid = "uid"
    public static let isPrivate = "private"
    public static let isStacked = "stacked"
    public static let tapAutoStart = "tapautostart"
    public static let tapList = "taps"
    public static let tapUID = "uid"
    public static let tapDriftCompensation = "drift"
}

/// Composition pure d'un agrégat privé qui expose un seul tap.
///
/// Les valeurs numériques sont des `NSNumber` entiers : le SDK attend des
/// `CFNumber` pour `private`, `stacked`, `tapautostart` et la compensation de
/// dérive. Un `Bool` Swift se bride en `CFBoolean`, que `CFNumberGetValue`
/// refuse.
public struct TapAggregateComposition: Equatable {
    public let name: String
    public let uid: String
    public let tapUID: String
    public let isPrivate: Bool
    public let isStacked: Bool
    /// Faux : `AudioDeviceStart` ne doit jamais attendre le premier son du
    /// processus tapé, sous peine de bloquer un démarrage sans borne.
    public let tapAutoStart: Bool
    public let usesDriftCompensation: Bool

    public init(
        name: String,
        uid: String,
        tapUID: String,
        isPrivate: Bool = true,
        isStacked: Bool = false,
        tapAutoStart: Bool = false,
        usesDriftCompensation: Bool = true
    ) {
        self.name = name
        self.uid = uid
        self.tapUID = tapUID
        self.isPrivate = isPrivate
        self.isStacked = isStacked
        self.tapAutoStart = tapAutoStart
        self.usesDriftCompensation = usesDriftCompensation
    }

    /// Un agrégat privé, non empilé, sans attente de premier son, avec un
    /// unique tap et sa compensation de dérive.
    public var isCanonical: Bool {
        isPrivate
            && !isStacked
            && !tapAutoStart
            && usesDriftCompensation
            && !tapUID.isEmpty
    }

    /// Dictionnaire prêt pour `AudioHardwareCreateAggregateDevice`.
    ///
    /// Chaque valeur numérique est un `NSNumber` entier, jamais un `Bool` :
    /// c'est le contrat du SDK pour `private`, `stacked`, `tapautostart` et
    /// la compensation de dérive.
    public var dictionary: [String: Any] {
        [
            TapAggregateKey.name: name,
            TapAggregateKey.uid: uid,
            TapAggregateKey.isPrivate: NSNumber(value: isPrivate ? 1 : 0),
            TapAggregateKey.isStacked: NSNumber(value: isStacked ? 1 : 0),
            TapAggregateKey.tapAutoStart: NSNumber(value: tapAutoStart ? 1 : 0),
            TapAggregateKey.tapList: [
                [
                    TapAggregateKey.tapUID: tapUID,
                    TapAggregateKey.tapDriftCompensation: NSNumber(
                        value: usesDriftCompensation ? 1 : 0
                    ),
                ],
            ],
        ]
    }
}
