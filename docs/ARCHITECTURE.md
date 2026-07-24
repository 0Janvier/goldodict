# Architecture d'Abracadabra

Ce document consigne les décisions de conception et, surtout, les pièges rencontrés — ceux qui ne se devinent pas et coûtent une demi-journée à qui les redécouvre.

## Vue d'ensemble

```
⌘⇧J ──▶ HotkeyMonitor ──▶ TriggerResolver ──▶ DictationController
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

La séparation en deux cibles n'est pas cosmétique : `AbracadabraCore` ne dépend d'aucun framework système, ce qui la rend testable sans micro, sans clavier et sans autorisation. `Abracadabra` est une cible `@main`, que SwiftPM ne sait pas tester directement.

## Décisions

### Carbon plutôt que CGEventTap pour le raccourci

`RegisterEventHotKey` délivre `kEventHotKeyReleased` autant que `kEventHotKeyPressed`, ce qui suffit à distinguer l'appui bref du maintien — **sans** réclamer l'autorisation « Surveillance de l'entrée » qu'exigerait un `CGEventTap`. Une permission système en moins à faire accepter.

**Piège** : le gestionnaire doit être installé sur `GetApplicationEventTarget()`. Avec `GetEventDispatcherTarget()`, l'enregistrement réussit, `RegisterEventHotKey` renvoie `noErr`, et **aucun événement n'arrive jamais**. Panne silencieuse, la pire à diagnostiquer.

### Le format audio est imposé par le moteur, jamais supposé

`SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` rend le format que le moteur Apple attend — sur cette machine, 16 kHz **Int16** mono. Whisper, lui, veut du 16 kHz **Float32**. `AudioCapture` prend donc son format cible en paramètre.

**Piège** : livrer au framework `Speech` un tampon d'un autre format ne produit pas une erreur mais une **assertion fatale** (`EXC_BREAKPOINT` dans `SpeechRecognizerWorker.preRunRecognition()`) qui tue le processus. Le format est résolu au lancement, avant toute capture, et un tampon non conforme est écarté dans `Session.feed` plutôt que transmis.

### Un relais FIFO entre le thread audio et le moteur

Lancer une `Task` par tampon ne garantit **aucun ordre d'exécution** : l'audio arriverait mélangé au moteur. `BufferRelay` s'appuie sur un `AsyncStream` à mise en file illimitée, consommé par une tâche unique.

Second bénéfice : la capture démarre dès l'enfoncement de la touche, alors que le moteur met quelques dizaines de millisecondes à s'ouvrir. Les tampons produits pendant ce laps sont mis en attente, non perdus.

### Retour visuel par panneau flottant

L'icône de la barre des menus **ne suffit pas**. Sur un écran large et une barre chargée, macOS relègue les icônes surnuméraires derrière un chevron où elles sont invisibles. L'utilisateur ne sait alors pas si sa dictée est en cours, ré-appuie sur le raccourci et l'interrompt.

`RecordingOverlay` est un `NSPanel` `.nonactivatingPanel` qui ignore la souris : il ne prend jamais le focus, sans quoi le collage automatique atterrirait dans la mauvaise application.

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

## Contraintes de la machine

### Signature et autorisations

Le bundle est signé avec l'identité **Developer ID Application**, pas en ad hoc. Une signature ad hoc change d'empreinte à chaque compilation, et l'application **perd ses autorisations micro et Accessibilité à chaque rebuild**.

### iCloud

Deux conséquences, toutes deux traitées dans `make_app.sh` :

1. `.build` sous `~/Documents` est évincé par iCloud en cours de compilation. D'où `--scratch-path ~/.cache/abracadabra-build`.
2. `fileproviderd` repose `com.apple.FinderInfo` et `com.apple.fileprovider.fpfs#P` **instantanément** sur tout fichier du dossier. `codesign` refuse alors de signer, et un `xattr -cr` préalable ne suffit pas : les attributs réapparaissent avant la signature. Le bundle est donc assemblé et signé hors du dossier du projet, puis copié.

## Ce qui n'est pas persisté, volontairement

Ni l'audio, ni les transcriptions ne touchent le disque. L'historique vit en mémoire et disparaît à la fermeture. Le fichier temporaire transmis au démon Whisper est supprimé immédiatement après lecture.

C'est une contrainte de conception liée au secret professionnel de l'article 66-5 de la loi du 31 décembre 1971, pas une simplification.
