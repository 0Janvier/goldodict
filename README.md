# Abracadabra

Dictée vocale **entièrement locale** pour macOS. Le texte dicté arrive dans le presse-papiers et se colle automatiquement dans l'application active, quelle qu'elle soit.

Rien ne quitte l'ordinateur : ni l'audio, ni la transcription. Aucun fichier n'est conservé, l'historique des vingt dernières dictées reste en mémoire vive et disparaît à la fermeture.

## Usage

Le raccourci global est **⌘⇧J**.

- **Appui maintenu** : push-to-talk. Vous parlez, vous relâchez, le texte est inséré.
- **Appui bref** : bascule marche/arrêt, pour les longues dictées. Un second appui termine.

La capture démarre dès l'enfoncement de la touche, aucun début de phrase n'est perdu. Une pastille s'affiche en bas de l'écran pendant toute la dictée.

> L'icône de la barre des menus disparaît derrière le chevron `‹` quand la barre est chargée. Pour l'en sortir, maintenez ⌘ et faites-la glisser vers la gauche. La fenêtre de réglages s'ouvre d'elle-même au premier lancement.

## Moteurs de transcription

| Moteur | Caractéristiques |
|---|---|
| **Apple `SpeechTranscriber`** (défaut) | Natif macOS 26, transcription au fil de l'eau, texte disponible dès le relâchement |
| **Whisper MLX** | Modèles `large-v3-turbo`, `large-v3`, `base`, `tiny` — souvent plus juste sur le vocabulaire technique, mais transcription par lots, donc quelques secondes d'attente |

Le choix se fait dans le menu ou dans les réglages. Whisper s'appuie sur un démon Python maintenu en vie pour éviter de recharger le modèle à chaque dictée.

## Correction locale

La dictée passe, avant insertion, par un modèle de langue qui rétablit la ponctuation, les accents et les accords, et supprime les hésitations. **Il ne reformule pas** et ne quitte jamais l'ordinateur.

| Modèle | Rôle |
|---|---|
| **Apple, sur l'appareil** | Utilisé en premier. Instantané, aucune dépendance |
| **Ollama `qwen3:8b`** | Prend le relais si Apple refuse le contenu, est indisponible ou trop lent |

Le modèle d'Apple refuse parfois les contenus sensibles, fréquents en matière pénale. Le repli existe pour cela. Il est préchargé au lancement — à froid, une correction demande huit secondes contre une et demie à chaud.

**Garde-fou de fidélité.** Un modèle chargé de corriger peut glisser vers la reformulation, et « le délai était expiré » devenir « le délai semblait expiré ». Chaque correction est donc comparée au texte brut : si trop de mots ont changé, ou si la longueur s'écarte trop, **la correction est écartée et le texte brut inséré**, avec mention à l'écran. Le seuil se règle dans l'onglet Correction.

Passé quatre secondes, la correction est abandonnée et le texte brut inséré : un texte imparfait vaut mieux qu'un texte qui n'arrive pas.

## Profils par application

Le traitement s'adapte à l'application dans laquelle vous dictez, relevée au moment où vous enfoncez le raccourci.

| Profil | Applications | Traitement |
|---|---|---|
| **Rédaction** (défaut) | Word, Mail, Pages, Notes, Goldocab | Tout : correction, ponctuation, majuscules, insécables |
| **Brut** | Ghostty, Terminal, Xcode, VS Code, Cursor | Rien. Le texte arrive tel qu'il a été dit |
| **Messagerie** | Slack, Messages, WhatsApp, Telegram | Ponctuation et majuscules, sans correction ni insécables |

Fichier : `~/Library/Application Support/Abracadabra/profils.json`. Une application non répertoriée reçoit le premier profil de la liste.

## Vocabulaire personnalisé

Deux mécanismes cumulables, tous deux alimentés par le même fichier.

**Lexique de correction** — associe ce qui est entendu à ce qu'il faut écrire.

```json
[
  { "entendu": "cage de baisse", "corrige": "CAA de Bordeaux", "biaiser": true }
]
```

Emplacement : `~/Library/Application Support/Abracadabra/lexique.json`, éditable à la main ou depuis l'onglet Lexique des réglages.

Le drapeau `biaiser` transmet le terme au moteur **avant** transcription (`contextualStrings` chez Apple, `initial_prompt` chez Whisper) : mieux vaut que le moteur reconnaisse correctement que d'avoir à rattraper après coup.

**Commandes de ponctuation** — « virgule », « point », « à la ligne », « ouvrez les guillemets », « point d'interrogation ». Les espaces insécables de la typographie française sont posées automatiquement devant `; : ! ?` et à l'intérieur des guillemets.

Les marques simples sont désactivables dans les réglages : en droit, « le point de départ du délai » ne doit pas devenir une ponctuation.

## Installation

```bash
./scripts/make_app.sh
```

Le script compile, signe avec l'identité Developer ID et installe dans `/Applications`. Au premier lancement, autoriser le **Microphone** puis l'**Accessibilité** dans Réglages Système > Confidentialité et sécurité.

Sans l'Accessibilité, le texte est copié dans le presse-papiers mais n'est pas collé.

## Prérequis

- macOS 26 ou ultérieur (framework `Speech` avec `SpeechAnalyzer`)
- Pour le moteur Whisper : `mlx-whisper` installé via pipx, à `~/.local/pipx/venvs/mlx-whisper/bin/python`

`ffmpeg` n'est **pas** nécessaire : l'audio est transmis au démon en PCM brut et passé directement à `mlx_whisper.transcribe`, ce qui contourne l'interface en ligne de commande.

## Développement

```bash
swift build --scratch-path ~/.cache/abracadabra-build
swift test  --scratch-path ~/.cache/abracadabra-build
```

Le `--scratch-path` hors de `~/Documents` est indispensable : iCloud évince le contenu de `.build` et casse les compilations. Pour la même raison, `make_app.sh` assemble et signe le bundle hors du dossier du projet, `fileproviderd` y reposant des attributs étendus que `codesign` refuse.

Journal en direct :

```bash
log stream --predicate 'subsystem == "fr.sztulman.abracadabra"' --level debug
```

## Structure

| Chemin | Rôle |
|---|---|
| `Sources/AbracadabraCore/` | Logique pure et testable : état, geste de déclenchement, lexique, ponctuation, typographie |
| `Sources/Abracadabra/` | Application : raccourci, audio, moteurs, insertion, réglages |
| `sidecar/` | Démon Python pour Whisper MLX |
| `scripts/make_app.sh` | Construction du bundle, signature, installation |
| `docs/ARCHITECTURE.md` | Décisions de conception et pièges rencontrés |
