# Architecture de Goldodict

Ce document consigne les décisions de conception et, surtout, les pièges rencontrés — ceux qui ne se devinent pas et coûtent une demi-journée à qui les redécouvre.

## Vue d'ensemble

```
Geste ──▶ HotkeyMonitor ──▶ TriggerResolver ──▶ DictationController
                                                       │
                                      AudioCapture ────┤
                                           │           │
                                      BufferRelay ─────┤
                                           │           │
                                TranscriptionEngine ───┤
                                                       │
                                TranscriptPipeline ────┤
                                                       │
                                      TextInjector ────┘
```

Le contrôleur ne connaît que le protocole `TranscriptionEngine`. Ajouter un moteur ne touche aucune autre couche.

La séparation en deux cibles n'est pas cosmétique : `GoldodictCore` ne dépend d'aucun framework système, ce qui la rend testable sans micro, sans clavier et sans autorisation. `Goldodict` est une cible `@main`, que SwiftPM ne sait pas tester directement.

## Décisions

### CGEventTap plutôt que Carbon pour le raccourci (v2.2.0)

Jusqu'à la v2.1.5, le raccourci passait par `RegisterEventHotKey`, qui délivre `kEventHotKeyReleased` autant que `kEventHotKeyPressed` — de quoi distinguer l'appui bref du maintien sans réclamer l'autorisation « Surveillance de l'entrée ». Une permission système en moins à faire accepter.

Carbon ne sait pourtant faire ni l'un ni l'autre de ce que la v2.2.0 demande. Ses modificateurs sont des masques de famille (`cmdKey`, `optionKey`) qui ignorent le côté du clavier, la touche `fn` ne fait partie d'aucun d'eux, et un modificateur seul ne constitue pas un raccourci enregistrable. Latéralité, `fn` et déclenchement au modificateur seul tombent donc ensemble, et l'autorisation devient le prix à payer.

`HotkeyMonitor` installe un `CGEvent.tapCreate` sur `.cgSessionEventTap`, écoutant `keyDown`, `keyUp` et `flagsChanged`. Trois points méritent d'être retenus.

**La latéralité vit dans les bits de poids faible.** Le masque d'un événement porte les bits de famille (`0x100000` pour ⌘) **et** les bits hérités d'IOKit (`NX_DEVICELCMDKEYMASK` = `0x08`, `NX_DEVICERCMDKEYMASK` = `0x10`). C'est `deviceIndependentFlagsMask` — le masque que tout le monde applique par réflexe — qui les efface, d'où la croyance que macOS ne distingue pas les deux touches ⌘. Voir `ModifierFlags` dans `GoldodictCore`. Certains claviers tiers ne posent que le bit de famille : `isPressed` retombe alors dessus, et la latéralité est perdue faute d'être rapportée, jamais faute d'être demandée.

**La consommation est asymétrique.** Une combinaison doit être retirée du flux (`return nil`), sans quoi la lettre s'écrit dans le document en même temps que la dictée démarre. Un modificateur seul ne doit **jamais** l'être : avaler l'appui sur ⌘ le supprimerait pour tout le système, jusqu'au ⌘Q. D'où `HotkeyTrigger.consumesEvent`.

**Le tap se désarme tout seul.** `tapDisabledByTimeout` arrive quand le rappel a mis trop de temps, `tapDisabledByUserInput` sur intervention système. Les deux se rattrapent par un `CGEvent.tapEnable` depuis l'intérieur du rappel. Sans cela, le raccourci meurt en cours de session sans le moindre message.

Le déclenchement au modificateur seul pose un dernier problème, qui n'est pas technique : ⌘ seul est aussi le début de ⌘S. `HotkeyMonitor` annule donc le geste dès qu'un modificateur étranger ou une touche ordinaire survient, et l'annulation tient jusqu'au relâchement complet.

### Le statut du modèle de langue ne vaut que pour le processus courant

`AssetInventory.status(forModules:)` ne dit pas si le modèle est présent sur la machine, mais s'il est attaché au processus qui pose la question. Il rend `.supported` à chaque démarrage, et ne passe à `.installed` qu'après un `downloadAndInstall()` — lequel est immédiat lorsque les fichiers sont déjà sur le disque. Rien ne survit à la sortie du processus. La notion système, elle, est `SpeechTranscriber.installedLocales` : sur cette machine elle contient le français depuis toujours, sans que le statut du module en dise autant.

Vérifier au seul lancement ne suffit donc pas. `AppleSpeechEngine.install(_:locale:)` est appelé au démarrage **et** à l'ouverture de chaque dictée, sur un module construit par la fabrique commune `makeTranscriber(locale:)` — l'installation et la session doivent porter sur la même configuration. Le coût à chaud est nul, et la capture tourne déjà pendant ce temps : le relais FIFO conserve les tampons.

**Piège n° 1** : `AssetInventory.assetInstallationRequest(supporting:)` peut rendre `nil`. Ce n'est pas un succès, mais l'aveu que le module n'est pas installé et que le système n'offre rien pour l'installer. Le traiter comme un cas nominal produit une préparation silencieusement réussie, puis un échec à la première dictée, sans une ligne de journal pour relier les deux.

**Piège n° 2, plus retors** : la réservation de la locale (`AssetInventory.reserve(locale:)`) n'est pas plus persistante que le statut. La documentation Apple le dit en une ligne discrète : *« the system may unsubscribe your app from assets that haven't been used in a while »* — et la réservation part avec. Une fois évincée, `assetInstallationRequest(supporting:)` rend tout de même une requête, et `downloadAndInstall()` rend la main sans lever d'erreur, mais le statut relu ensuite reste `.supported`, indéfiniment (vérifié à la sonde jusqu'à 1,5 s d'attente, pour écarter un simple délai de propagation). La v2.1.3 vérifiait le statut à chaque dictée mais ne réservait qu'au lancement, dans `prepareAssets` — insuffisant après une heure d'inactivité. La v2.1.4 déplace la réservation dans `install(_:locale:)` lui-même, rejouée à chaque appel plutôt qu'une fois pour toutes.

### Le format audio est imposé par le moteur, jamais supposé

`SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` rend le format que le moteur Apple attend — sur cette machine, 16 kHz **Int16** mono. Whisper, lui, veut du 16 kHz **Float32**. `AudioCapture` prend donc son format cible en paramètre.

**Piège** : livrer au framework `Speech` un tampon d'un autre format ne produit pas une erreur mais une **assertion fatale** (`EXC_BREAKPOINT` dans `SpeechRecognizerWorker.preRunRecognition()`) qui tue le processus. Le format est résolu au lancement, avant toute capture, et un tampon non conforme est écarté dans `Session.feed` plutôt que transmis.

### Un relais FIFO entre le thread audio et le moteur

Lancer une `Task` par tampon ne garantit **aucun ordre d'exécution** : l'audio arriverait mélangé au moteur. `BufferRelay` s'appuie sur un `AsyncStream` à mise en file illimitée, consommé par une tâche unique.

Second bénéfice : la capture démarre dès l'enfoncement de la touche, alors que le moteur met quelques dizaines de millisecondes à s'ouvrir. Les tampons produits pendant ce laps sont mis en attente, non perdus.

### Retour visuel par panneau flottant

L'icône de la barre des menus **ne suffit pas**. Sur un écran large et une barre chargée, macOS relègue les icônes surnuméraires derrière un chevron où elles sont invisibles. L'utilisateur ne sait alors pas si sa dictée est en cours, ré-appuie sur le raccourci et l'interrompt.

`RecordingOverlay` est un `NSPanel` `.nonactivatingPanel` qui ignore la souris : il ne prend jamais le focus, sans quoi le collage automatique atterrirait dans la mauvaise application.

La pastille montre le **signal**, pas seulement l'état de l'application. Un voyant fixe confond « j'écoute » et « je capte quelque chose », deux situations que rien ne distinguait quand le micro était coupé ou pris par une autre application. Le vumètre est alimenté par `AudioLevel`, qui convertit la valeur efficace en décibels — une échelle linéaire écraserait toute voix ordinaire contre le bas — puis lisse le résultat de façon asymétrique, l'attaque devant se voir immédiatement là où une fin de mot peut retomber.

### Barre des menus : `NSStatusItem`, pas `MenuBarExtra`

`MenuBarExtra(.menu)` construit un `NSMenu` et **abandonne en silence** tout ce qui n'est ni `Text`, ni `Button`, ni `Divider`, ni `Menu`. Le panneau voulu — bandeaux d'autorisation, sélecteur de moteur, historique cliquable — n'aurait affiché que ses boutons. D'où un `NSStatusItem` portant un `NSPopover`, dont le contenu est un `NSHostingController` en `sizingOptions: [.preferredContentSize]` pour que la hauteur suive celle de la vue SwiftUI.

**Piège** : dicter depuis ce panneau. L'ouverture du popover et `NSApp.activate` mettent Goldodict au premier plan, si bien que l'application « précédente » relevée par `beginCapture` serait Goldodict lui-même, et le texte n'irait nulle part. Le frontmost est donc capturé **avant** l'activation, réactivé à la fermeture, et la capture attend 180 ms que le changement d'application ait pris effet.

Second piège, invisible au test manuel : une dictée lancée par le menu laissait `TriggerResolver` au repos, et l'appui suivant sur le raccourci en démarrait une **seconde** au lieu d'arrêter la première. D'où `adoptToggle()`, qui déclare au résolveur une bascule qu'il n'a pas vue passer.

### Glisser-déposer sur l'icône : `NSStatusItem.view`, dépréciée mais seule viable

Déposer un fichier audio sur l'icône (v2.3.0) demande une conformité `NSDraggingDestination` — `draggingEntered`, `performDragOperation`. Or `NSStatusItem.button` est un `NSStatusBarButton` que le système instancie lui-même : AppKit ne dispatche qu'aux méthodes réellement surchargées sur la classe concrète d'un objet, et rien ne permet de sous-classer ce bouton-là pour y ajouter les siennes.

La seule voie qui reste est `NSStatusItem.view`, dépréciée depuis 10.14 au profit de `.button`, mais toujours fonctionnelle. `StatusItemDropView` est une `NSView` ordinaire portant un `NSImageView` interne — pour recevoir telles quelles les images de `StatusIcon` — et surchargeant `mouseDown` pour le clic et les deux méthodes de `NSDraggingDestination` pour le dépôt. Affecter `.view` fait passer `.button` à `nil` : `configureStatusItem()`, `reflect(_:)` et `togglePopover()` visent tous la vue déposée, plus jamais le bouton.

Le filtrage du fichier déposé se fait à la lecture du pasteboard de glissement (`readObjects(forClasses:options:)`, `.urlReadingContentsConformToTypes: [UTType.audio.identifier]`), pas sur l'extension du nom — un fichier renommé sans son extension d'origine serait sinon accepté ou refusé à tort.

### L'icône de la barre des menus est dessinée à part

L'icône d'application est illisible à 18 px : la visière, deux losanges, une bouche et deux arcs s'y confondent. `StatusIcon` retrace la silhouette à la main dans un `NSImage` en mode gabarit, ce qui lui vaut en prime de suivre le thème clair ou sombre du système. La bouche s'ouvre en enregistrement, et la teinte passe au rouge — une forme change en même temps que la couleur, pour ne pas reposer sur elle seule.

Le même raisonnement vaut pour le fichier `.icns` : sous 48 px, les arcs de son se referment sur la bouche. `make_icon.sh` bascule alors sur `goldodict-icon-small.svg`, où ils disparaissent au profit du seul casque. Chaque taille est par ailleurs tracée depuis le vectoriel, jamais rééchantillonnée depuis la plus grande.

### Le premier lancement demande les autorisations une à une

Réclamer micro et Accessibilité au lancement produisait deux boîtes de dialogue superposées, sans contexte, dans une application sans fenêtre. `OnboardingWindow` les présente séparément, chacune avec sa conséquence, et offre une porte de sortie explicite — « Continuer sans coller automatiquement » — plutôt que de laisser l'utilisateur refuser l'Accessibilité et découvrir plus tard que rien ne se colle.

**Piège** : ces autorisations changent dans Réglages Système, hors du champ d'observation de SwiftUI. Rien ne rafraîchit la vue au retour. Un `Timer` d'une seconde relit donc l'état tant que la fenêtre est ouverte.

### Fenêtre de réglages construite à la main

La scène `Settings` de SwiftUI s'ouvre par un sélecteur (`showSettingsWindow:`) dont le nom a changé selon les versions de macOS, et qui reste sans effet dans une application `LSUIElement`. `sendAction` renvoie `true` sans rien afficher. Une `NSWindow` explicite ne dépend d'aucun de ces aléas.

### Whisper par démon Python, sans ffmpeg

L'interface en ligne de commande de `mlx_whisper` exige `ffmpeg`, absent de la machine. L'API Python accepte un tableau NumPy : l'audio est écrit en PCM brut et lu par `np.fromfile`, ce qui court-circuite entièrement le décodage.

Le démon reste vivant entre deux dictées — recharger `large-v3-turbo` coûterait plusieurs secondes à chaque fois. Le dialogue est en JSON, une ligne par message ; les barres de progression HuggingFace partent sur `stderr`, drainé séparément pour ne pas saturer le tube.

**Piège** : Whisper **invente du texte sur du silence**. Deux secondes de bruit imperceptible produisent « Merci. ». Sans garde-fou, une dictée déclenchée par erreur insérerait des mots jamais prononcés dans un écrit. Un seuil de crête (`silenceThreshold`) écarte ces cas.

### Ordre de la chaîne de traitement

`ponctuation → lexique → typographie → majuscules`

La ponctuation passe avant le lexique pour qu'une entrée de lexique puisse contenir des signes. La typographie vient en dernier parce qu'elle rattrape les espaces laissées par les deux étapes précédentes.

Les substitutions n'utilisent **pas** `NSRegularExpression`, incapable d'ignorer les diacritiques. `String.range(of:options:)` avec `.diacriticInsensitive` le fait nativement, et les bornes de mots sont vérifiées à la main — ce qui traite correctement l'apostrophe typographique, devant laquelle `\b` se comporte de façon inattendue.

### Le garde-fou de correction est la pièce maîtresse

Un modèle de langue à qui l'on demande de « corriger » peut dériver vers la reformulation. En matière juridique, remplacer « était expiré » par « semblait expiré » change la portée d'un moyen sans qu'une relecture rapide le voie.

`CorrectionGuard` compare le texte corrigé au brut sur deux axes : la part des mots conservés (seuil 0,75) et le rapport des longueurs (0,6 à 1,4). Les mots sont normalisés sans casse ni diacritiques, précisément parce que rétablir les accents fait partie du travail attendu et ne doit pas compter comme une altération. Le décompte se fait en **sac de mots** et non en ensemble : un modèle qui répéterait dix fois un mot présent au brut ne doit pas passer pour fidèle.

Hors des bornes, la correction est refusée et le brut inséré. Le fait est signalé à l'écran par un état `notice` distinct de `failed` — une correction écartée n'est pas une panne, mais l'utilisateur doit le savoir.

### Ordre des correcteurs et repli

Apple d'abord pour la latence. Ollama prend le relais sur trois motifs : modèle indisponible, refus de contenu (`GenerationError.guardrailViolation`, cas réel en pénal), ou dépassement du délai de quatre secondes.

Une correction jugée **infidèle** n'entraîne en revanche aucune seconde tentative : le second modèle produirait la même dérive à partir du même texte. On garde le brut.

**Mesure sur cette machine** : `qwen3:8b` répond en 1,6 s à chaud contre 7,8 s à froid, dont 6,1 s de chargement. D'où le préchargement au lancement — sans lui, la première correction de la journée dépasserait le délai pour rien.

### Le profil est arrêté à l'enfoncement de la touche

`NSWorkspace.shared.frontmostApplication` est relevé dans `beginCapture`, jamais dans `deliver`. Entre les deux, l'application au premier plan a pu changer, et le texte serait alors traité selon les règles d'une fenêtre qui n'est plus la cible.

### Bindings sur une source de vérité, pas sur une copie

Piège rencontré dans l'onglet Profils : construire un `Binding` à partir de la valeur rendue par `ForEach` capture une **copie figée**. La vue affiche alors un état périmé, et toute écriture repart de cette copie en réinscrivant au passage les réglages voisins — le fichier de profils s'était retrouvé avec deux valeurs erronées. Le binding relit désormais le profil dans son magasin à chaque accès.

### Le renommage déplace deux magasins, et en casse un troisième

`Abracadabra` est devenu `Goldodict` avec la version 0.1.0. Trois emplacements en dépendaient.

1. `~/Library/Application Support/Abracadabra/` — lexique et profils, recopiés par `SupportDirectory` au premier accès. Copie et non déplacement, pour qu'un retour en arrière reste possible ; la reprise ne s'exécute qu'une fois et seulement sur un dossier de destination inexistant.
2. Le domaine de préférences, indexé sur l'identifiant de bundle. `Preferences` relit l'ancien domaine clé par clé, sous drapeau de migration — sans lui, une valeur remise volontairement à son défaut serait réécrite au lancement suivant depuis l'ancien domaine.
3. Les autorisations TCC, que macOS indexe sur l'identifiant de bundle **et** sur la signature. Rien ne peut les reprendre : elles sont à redonner. C'est précisément le rôle de la fenêtre d'accueil.

## Contraintes de la machine

### Signature et autorisations

Le bundle est signé avec l'identité **Developer ID Application**, pas en ad hoc. Une signature ad hoc change d'empreinte à chaque compilation, et l'application **perd ses autorisations micro et Accessibilité à chaque rebuild**.

### iCloud

Deux conséquences, toutes deux traitées dans `make_app.sh` :

1. `.build` sous `~/Documents` est évincé par iCloud en cours de compilation. D'où `--scratch-path ~/.cache/goldodict-build`.
2. `fileproviderd` repose `com.apple.FinderInfo` et `com.apple.fileprovider.fpfs#P` **instantanément** sur tout fichier du dossier. `codesign` refuse alors de signer, et un `xattr -cr` préalable ne suffit pas : les attributs réapparaissent avant la signature. Le bundle est donc assemblé et signé hors du dossier du projet, puis copié.

## Ce qui n'est pas persisté, volontairement

Ni l'audio, ni les transcriptions ne touchent le disque. L'historique vit en mémoire et disparaît à la fermeture. Le fichier temporaire transmis au démon Whisper est supprimé immédiatement après lecture.

C'est une contrainte de conception liée au secret professionnel de l'article 66-5 de la loi du 31 décembre 1971, pas une simplification.
