import AppKit
import Foundation
import GoldodictCore
import Observation

/// Apprentissage des corrections : observation du champ, propositions, lexique
/// et règles de style.
@Observable
@MainActor
final class LearningCoordinator {

    let store = StyleObservationStore()

    private struct LastInsertion {
        let text: String
        let bundleIdentifier: String?
        let profileName: String
        let date: Date
    }

    private var lastInsertion: LastInsertion?
    private static let observationWindow: TimeInterval = 15 * 60

    func rememberInsertion(text: String, bundleIdentifier: String?, profileName: String) {
        lastInsertion = LastInsertion(
            text: text,
            bundleIdentifier: bundleIdentifier,
            profileName: profileName,
            date: Date()
        )
    }

    /// Relit le champ de la dernière insertion et relève les retouches, sans
    /// aucun geste de l'utilisateur. Le champ lu ne quitte jamais la mémoire.
    func observeLastInsertionIfPossible(
        frontmost: String?,
        enabled: Bool,
        observeField: Bool,
        lexicon: Lexicon
    ) {
        guard enabled, observeField, let last = lastInsertion else { return }
        lastInsertion = nil

        guard last.bundleIdentifier == frontmost,
              Date().timeIntervalSince(last.date) < Self.observationWindow else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == last.bundleIdentifier else { return }
            guard let field = FocusedFieldReader.focusedFieldValue(),
                  let passage = InsertionLocator.modifiedPassage(of: last.text, in: field) else { return }
            let count = self.record(
                original: last.text,
                corrected: passage,
                profileName: last.profileName,
                enabled: true,
                lexicon: lexicon
            )
            if count > 0 {
                Log.learning.notice("observation du champ : \(count) correction(s) relevée(s)")
            }
        }
    }

    @discardableResult
    func record(
        original: String,
        corrected: String,
        profileName: String,
        enabled: Bool,
        lexicon: Lexicon
    ) -> Int {
        guard enabled else { return 0 }
        let before = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let after = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard before != after else { return 0 }

        let pairs = StyleDiffEngine.discardingAlreadyHandled(
            StyleDiffEngine.diff(original: before, corrected: after),
            lexicon: lexicon
        )
        for pair in pairs {
            store.record(
                before: pair.before,
                after: pair.after,
                profileName: profileName,
                kind: StyleDiffEngine.classify(pair)
            )
        }
        return pairs.count
    }

    var proposals: [StyleObservation] {
        store.observations.proposals()
    }

    func accept(_ observation: StyleObservation, as kind: StyleSuggestionKind) -> StyleAcceptAction {
        store.setStatus(.accepted, id: observation.id)
        switch kind {
        case .lexicon:
            return .lexicon(entendu: observation.before, corrige: observation.after)
        case .style:
            let note = StyleDiffEngine.styleInstruction(before: observation.before, after: observation.after)
            return .style(profileName: observation.profileName, note: note)
        }
    }

    func dismiss(_ observation: StyleObservation) {
        store.setStatus(.dismissed, id: observation.id)
    }
}

enum StyleAcceptAction {
    case lexicon(entendu: String, corrige: String)
    case style(profileName: String, note: String)
}
