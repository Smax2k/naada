import Foundation

/// Mélange de deux tampons PCM 16 bits entrelacés stéréo.
///
/// L'addition se fait échantillon par échantillon : l'entrelacement stéréo ne
/// change rien, chaque voie est additionnée séparément. Aucun gain n'est
/// appliqué et le résultat sature aux bornes `Int16`.
public enum PCMMix {
    /// Additionne deux tampons, l'un ou l'autre pouvant être absent.
    ///
    /// Un côté absent vaut silence de la longueur de l'autre. Les deux absents
    /// donnent un tampon vide. Si les longueurs diffèrent, la partie manquante
    /// du tampon le plus court est traitée comme du silence.
    public static func mix(_ first: [Int16]?, _ second: [Int16]?) -> [Int16] {
        guard let first else { return second ?? [] }
        guard let second else { return first }

        let count = max(first.count, second.count)
        var output = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let left = index < first.count ? Int(first[index]) : 0
            let right = index < second.count ? Int(second[index]) : 0
            output[index] = Int16(clamping: left + right)
        }
        return output
    }
}
