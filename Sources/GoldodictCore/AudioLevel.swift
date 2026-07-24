import Foundation

/// Conversion du niveau sonore brut en une hauteur de barre affichable.
///
/// La valeur efficace rendue par la capture n'est pas montrable telle quelle : une
/// voix ordinaire se tient entre 0,01 et 0,2, si bien qu'une échelle linéaire écrase
/// tout contre le bas et ne distingue pas le silence d'un murmure. L'oreille percevant
/// l'intensité de façon logarithmique, la conversion passe par les décibels.
public enum AudioLevel {

    /// En dessous, c'est du silence : bruit de ventilateur, pièce vide, micro coupé.
    public static let floorDecibels: Float = -55

    /// Au-dessus, la barre est pleine. Une voix proche du micro plafonne vers -12 dB.
    public static let ceilingDecibels: Float = -12

    /// Ramène une valeur efficace (0…1) à une hauteur de barre (0…1).
    ///
    /// Un micro coupé rend exactement zéro, cas que le logarithme ne sait pas traiter :
    /// il est écarté avant, et rend zéro, ce qui est précisément l'information utile.
    public static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        guard decibels > floorDecibels else { return 0 }
        guard decibels < ceilingDecibels else { return 1 }
        return (decibels - floorDecibels) / (ceilingDecibels - floorDecibels)
    }

    /// Lissage exponentiel entre deux relevés.
    ///
    /// Les tampons arrivent une quinzaine de fois par seconde et le niveau saute d'un
    /// tampon à l'autre à l'intérieur d'une même syllabe. Sans lissage, les barres
    /// clignotent au lieu de respirer. La montée est plus rapide que la descente :
    /// une attaque de voix doit se voir tout de suite, une fin de mot peut retomber.
    public static func smoothed(previous: Float, target: Float) -> Float {
        let coefficient: Float = target > previous ? 0.55 : 0.18
        return previous + (target - previous) * coefficient
    }
}
