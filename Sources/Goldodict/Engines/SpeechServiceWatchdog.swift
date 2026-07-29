import AppKit

/// Chien de garde de la connexion au service de reconnaissance Apple.
///
/// Quand la connexion XPC du framework Speech est morte (voir
/// `AppleSpeechEngine.probeHealth`), aucune API publique ne la ranime : seul un
/// processus neuf obtient une connexion fraîche. Ce chien de garde sonde l'état
/// à intervalle régulier et au réveil de la machine, et déclenche une relance
/// silencieuse de l'application dès que la panne est constatée hors dictée —
/// avant que l'utilisateur ne se heurte à « modèle non installé ».
@MainActor
final class SpeechServiceWatchdog {

    private let controller: DictationController
    private let relaunch: () -> Void
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var probing = false

    /// Garde anti-boucle : si une relance ne réparait pas, on ne relance pas en
    /// rafale pour autant.
    private static let lastRelaunchKey = "speechWatchdogLastRelaunch"
    private static let relaunchCooldown: TimeInterval = 600

    /// La panne suit l'inactivité : deux minutes suffisent pour qu'une relance
    /// ait eu lieu avant la dictée suivante, pour quelques millisecondes d'XPC.
    private static let probeInterval: TimeInterval = 120

    init(controller: DictationController, relaunch: @escaping () -> Void) {
        self.controller = controller
        self.relaunch = relaunch
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.probeInterval, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.probe() }
        }
        // Le réveil est le moment le plus probable de la panne, mais le démon
        // remonte en quelques secondes : sonder trop tôt conclurait à tort.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                self?.probe()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func probe() {
        // Une connexion morte est sans conséquence tant que le moteur Apple n'est
        // pas celui qui dicte ; et une relance en pleine dictée ou session de
        // document détruirait du travail en cours.
        guard !probing,
              controller.currentEngineIdentifier == "apple",
              !controller.isOccupied else { return }
        probing = true

        let locale = controller.locale
        Task { [weak self] in
            let health = await AppleSpeechEngine.probeHealth(locale: locale)
            Log.engine.debug("sonde Speech : \(String(describing: health), privacy: .public)")
            guard let self else { return }
            self.probing = false
            guard health == .deadConnection, !self.controller.isOccupied else { return }

            let last = UserDefaults.standard.double(forKey: Self.lastRelaunchKey)
            guard Date().timeIntervalSince1970 - last > Self.relaunchCooldown else {
                Log.engine.error("connexion Speech morte mais relance trop récente — abandon")
                return
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastRelaunchKey)
            Log.engine.error("connexion au service Speech morte — relance silencieuse de l'application")
            self.relaunch()
        }
    }
}
