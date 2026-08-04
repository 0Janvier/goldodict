import Foundation

/// Correcteur de repli, servi par Ollama sur la machine.
///
/// Il n'a pas les garde-fous de contenu du modèle Apple, ce qui en fait le recours
/// naturel pour les dossiers pénaux. En contrepartie il dépend d'un démon qui doit
/// tourner, et sa latence n'est acceptable que le modèle chargé : **1,6 s à chaud
/// contre 7,8 s à froid**, mesuré sur cette machine avec `qwen3:8b`. D'où le
/// préchargement au lancement de l'application.
final class OllamaCorrector: TextCorrector {

    let identifier = "ollama"
    var displayName: String { "Ollama (\(model))" }

    static let defaultModel = "qwen3:8b"
    private static let endpoint = URL(string: "http://localhost:11434/api/generate")!

    /// Durée pendant laquelle Ollama garde le modèle en mémoire après un appel.
    private static let keepAlive = "30m"

    let model: String

    init(model: String = OllamaCorrector.defaultModel) {
        self.model = model
    }

    /// Ce que le démon répond, et ce qu'on peut en faire.
    ///
    /// Les deux échecs demandent des gestes opposés : lancer Ollama d'un côté,
    /// choisir ou télécharger un modèle de l'autre. Les confondre en un seul `false`
    /// envoyait l'utilisateur démarrer un démon qui tournait déjà.
    enum Availability: Sendable, Equatable {
        case ready(served: [String])
        /// Le démon répond, mais il ne sert pas le modèle demandé.
        case modelMissing(served: [String])
        case daemonUnreachable

        /// Ce que le démon sert, quel que soit le verdict. La liste accompagne les
        /// deux cas où il répond : c'est elle qui permet de proposer un choix plutôt
        /// que de renvoyer l'utilisateur à la ligne de commande.
        var served: [String] {
            switch self {
            case .ready(let served), .modelMissing(let served): return served
            case .daemonUnreachable: return []
            }
        }

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    func availability() async -> Availability {
        var request = URLRequest(url: URL(string: "http://localhost:11434/api/tags")!)
        request.timeoutInterval = 1.5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = payload["models"] as? [[String: Any]] else {
            return .daemonUnreachable
        }

        let served = models.compactMap { $0["name"] as? String }.sorted()
        return served.contains(model) ? .ready(served: served) : .modelMissing(served: served)
    }

    func isAvailable() async -> Bool {
        await availability().isReady
    }

    /// Charge le modèle en mémoire sans rien lui demander, pour que la première
    /// correction réelle ne paie pas les six secondes de chargement.
    func warmUp() async {
        var body: [String: Any] = ["model": model, "keep_alive": Self.keepAlive]
        body["prompt"] = ""
        _ = try? await post(body, timeout: 60)
        Log.engine.notice("modèle Ollama préchargé : \(self.model, privacy: .public)")
    }

    func correct(_ text: String, styleNotes: [String]) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "system": CorrectionPrompt.instructions(styleNotes: styleNotes),
            "prompt": CorrectionPrompt.prompt(for: text),
            "stream": false,
            // Les modèles de la famille Qwen 3 raisonnent à voix haute par défaut,
            // ce qui polluerait la réponse et multiplierait la latence.
            "think": false,
            "keep_alive": Self.keepAlive,
            "options": ["temperature": 0.1],
        ]

        let payload = try await post(body, timeout: 20)
        guard let response = payload["response"] as? String else {
            throw CorrectionError.failed("réponse Ollama illisible")
        }
        return Self.stripDecoration(from: response)
    }

    private func post(_ body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CorrectionError.failed("réponse Ollama illisible")
            }
            return payload
        } catch let error as URLError where error.code == .cannotConnectToHost {
            throw CorrectionError.unavailable("Ollama (démon arrêté)")
        } catch let error as URLError where error.code == .timedOut {
            throw CorrectionError.timedOut
        }
    }

    /// Retire les ornements que les modèles ajoutent malgré la consigne : guillemets
    /// d'encadrement, préambule, blocs de raisonnement résiduels.
    static func stripDecoration(from response: String) -> String {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = text.range(of: "</think>") {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let pairs: [(Character, Character)] = [("\"", "\""), ("«", "»"), ("“", "”")]
        for (open, close) in pairs where text.first == open && text.last == close && text.count > 2 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }
}
