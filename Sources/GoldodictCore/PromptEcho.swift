import Foundation

/// Retire un éventuel écho de l'`initial_prompt` Whisper en tête d'une transcription.
///
/// mlx_whisper exclut déjà les jetons du prompt du décodage final, mais le modèle
/// peut tout de même *générer* les mêmes termes. Sans ce filtre, le vocabulaire
/// transmis par l'application (lexique, dossier) repartait dans le collage.
public enum PromptEcho {

    private static let separators = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ",;·—-"))

    /// - Parameters:
    ///   - text: transcription brute.
    ///   - prompt: amorce passée à Whisper (`contextualStrings` joints par `", "`).
    public static func strip(_ text: String, prompt: String?) -> String {
        guard let prompt, !prompt.isEmpty, !text.isEmpty else { return text }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if let remainder = dropPrefix(trimmedPrompt, from: text) {
            return remainder.trimmingCharacters(in: separators)
        }

        // Écho partiel : au moins les trois premiers termes du prompt. En deçà,
        // une dictée qui commencerait par un seul nom du lexique serait mangée.
        let terms = trimmedPrompt.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard terms.count >= 3 else { return text }

        var remainder = text
        var matched = 0
        for term in terms {
            let trimmed = remainder.trimmingCharacters(in: separators)
            guard let next = dropPrefix(term, from: trimmed) else { break }
            remainder = next
            matched += 1
        }
        guard matched >= 3 else { return text }
        return remainder.trimmingCharacters(in: separators)
    }

    /// `nil` si `prefix` n'est pas en tête de `text` (casse et diacritiques ignorés).
    private static func dropPrefix(_ prefix: String, from text: String) -> String? {
        guard text.count >= prefix.count else { return nil }
        let head = String(text.prefix(prefix.count))
        let equal = head.compare(
            prefix,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "fr_FR")
        ) == .orderedSame
        guard equal else { return nil }
        return String(text.dropFirst(prefix.count))
    }
}
