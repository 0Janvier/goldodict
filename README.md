# Goldodict

Dictée vocale **entièrement locale** pour macOS. Le texte dicté arrive dans le presse-papiers et se colle automatiquement dans l'application active, quelle qu'elle soit.

Rien ne quitte l'ordinateur : ni l'audio, ni la transcription. Aucun fichier n'est conservé, l'historique des vingt dernières dictées reste en mémoire vive et disparaît à la fermeture.

## Usage

Le raccourci global est **⌘⇧J**.

- **Appui maintenu** : push-to-talk. Vous parlez, vous relâchez, le texte est inséré.
- **Appui bref** : bascule marche/arrêt, pour les longues dictées. Un second appui termine.

La capture démarre dès l'enfoncement de la touche, aucun début de phrase n'est perdu.

**La pastille.** Pendant la dictée, une pilule s'affiche en bas de l'écran : point rouge, vumètre animé sur le niveau du micro, minuterie. Le vumètre est là pour une raison précise — il distingue « l'application écoute » de « le micro capte quelque chose », deux états qu'un simple voyant confond. La transcription puis l'insertion s'y affichent ensuite, et la pastille se referme sur le nombre de signes insérés et le nom de l'application destinataire.

**Le menu.** Un clic sur l'icône de la barre des menus ouvre un panneau : état, autorisations manquantes, bouton de dictée, choix du moteur, cinq dernières dictées recopiables d'un clic. La dictée lancée depuis ce panneau revient à l'application où vous étiez, et non à Goldodict.

> L'icône de la barre des menus disparaît derrière le chevron `‹` quand la barre est chargée. Pour l'en sortir, maintenez ⌘ et faites-la glisser vers la gauche. Au premier lancement, une fenêtre d'accueil demande les deux autorisations une à une, propose le choix du moteur et offre un champ d'essai.

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

Fichier : `~/Library/Application Support/Goldodict/profils.json`. Une application non répertoriée reçoit le premier profil de la liste.

## Vocabulaire personnalisé

Deux mécanismes cumulables, tous deux alimentés par le même fichier.

**Lexique de correction** — associe ce qui est entendu à ce qu'il faut écrire.

```json
[
  { "entendu": "cage de baisse", "corrige": "CAA de Bordeaux", "biaiser": true }
]
```

Emplacement : `~/Library/Application Support/Goldodict/lexique.json`, éditable à la main ou depuis l'onglet Lexique des réglages.

Le drapeau `biaiser` transmet le terme au moteur **avant** transcription (`contextualStrings` chez Apple, `initial_prompt` chez Whisper) : mieux vaut que le moteur reconnaisse correctement que d'avoir à rattraper après coup.

**Commandes de ponctuation** — « virgule », « point », « à la ligne », « ouvrez les guillemets », « point d'interrogation ». Les espaces insécables de la typographie française sont posées automatiquement devant `; : ! ?` et à l'intérieur des guillemets.

Les marques simples sont désactivables dans les réglages : en droit, « le point de départ du délai » ne doit pas devenir une ponctuation.

## Installation

```bash
./scripts/make_app.sh
```

Le script compile, signe avec l'identité Developer ID et installe dans `/Applications`. Au premier lancement, autoriser le **Microphone** puis l'**Accessibilité** dans Réglages Système > Confidentialité et sécurité.

Sans l'Accessibilité, le texte est copié dans le presse-papiers mais n'est pas collé. C'est le seul défaut silencieux de l'application : il est signalé dans le menu, dans les réglages et dans la fenêtre d'accueil.

**Reprise d'Abracadabra.** L'application portait ce nom jusqu'à la version 0.1.0. Le lexique et les profils laissés dans `~/Library/Application Support/Abracadabra/` sont recopiés au premier lancement, et les réglages repris depuis l'ancien domaine de préférences. L'ancien dossier n'est pas supprimé. Les autorisations Microphone et Accessibilité, elles, sont à redonner : macOS les indexe sur l'identifiant de bundle, qui a changé.

## Prérequis

- macOS 26 ou ultérieur (framework `Speech` avec `SpeechAnalyzer`)
- Pour le moteur Whisper : `mlx-whisper` installé via pipx, à `~/.local/pipx/venvs/mlx-whisper/bin/python`

`ffmpeg` n'est **pas** nécessaire : l'audio est transmis au démon en PCM brut et passé directement à `mlx_whisper.transcribe`, ce qui contourne l'interface en ligne de commande.

## Développement

```bash
swift build --scratch-path ~/.cache/goldodict-build
swift test  --scratch-path ~/.cache/goldodict-build
```

Le `--scratch-path` hors de `~/Documents` est indispensable : iCloud évince le contenu de `.build` et casse les compilations. Pour la même raison, `make_app.sh` assemble et signe le bundle hors du dossier du projet, `fileproviderd` y reposant des attributs étendus que `codesign` refuse.

Journal en direct :

```bash
log stream --predicate 'subsystem == "fr.sztulman.goldodict"' --level debug
```

## Structure

| Chemin | Rôle |
|---|---|
| `Sources/GoldodictCore/` | Logique pure et testable : état, geste de déclenchement, lexique, ponctuation, typographie |
| `Sources/Goldodict/` | Application : raccourci, audio, moteurs, insertion, réglages |
| `sidecar/` | Démon Python pour Whisper MLX |
| `design/` | Icône vectorielle, et sa déclinaison pour les petites tailles |
| `scripts/make_app.sh` | Construction du bundle, signature, installation |
| `scripts/make_icon.sh` | Rendu de `Resources/AppIcon.icns` depuis le vectoriel |
| `docs/ARCHITECTURE.md` | Décisions de conception et pièges rencontrés |
