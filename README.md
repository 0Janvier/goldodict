# Goldodict

Dictée vocale **entièrement locale** pour macOS. Le texte dicté arrive dans le presse-papiers et se colle automatiquement dans l'application active, quelle qu'elle soit.

Rien ne quitte l'ordinateur : ni l'audio, ni la transcription. Aucun fichier n'est conservé, l'historique des vingt dernières dictées reste en mémoire vive et disparaît à la fermeture.

## Usage

Le raccourci global est **⌘⇧J** par défaut.

- **Appui maintenu** : push-to-talk. Vous parlez, vous relâchez, le texte est inséré.
- **Appui bref** : bascule marche/arrêt, pour les longues dictées. Un second appui termine.

La capture démarre dès l'enfoncement de la touche, aucun début de phrase n'est perdu.

**Personnaliser le raccourci.** Réglages, onglet Dictée. Trois formes sont possibles.

| Forme | Exemple |
|---|---|
| Combinaison | ⌘⇧J, ⌃⌥Espace |
| Modificateur seul, maintenu | ⌘ de droite, `fn` |
| Double appui sur un modificateur | ⌃ ×2, dans les 300 ms |

Le réglage se fait au geste : cliquez sur *Modifier*, faites le raccourci, il est retenu. Les deux touches d'une même famille sont distinguées, notées `ᴸ` et `ᴿ` — ⌘ᴿ ne déclenche rien si vous appuyez sur celle de gauche. La case *Distinguer les touches de gauche et de droite* rend le raccourci indifférent au côté. La touche `fn` est acceptée, sans côté puisqu'il n'y en a qu'une.

Un modificateur seul reste utilisable comme modificateur : frapper une autre touche pendant qu'il est enfoncé annule la dictée, et ⌘S enregistre comme d'habitude.

**La pastille.** Pendant la dictée, une pilule s'affiche en bas de l'écran : point rouge, vumètre animé sur le niveau du micro, minuterie, et une réplique de cinéma tirée au sort. Le vumètre est là pour une raison précise — il distingue « l'application écoute » de « le micro capte quelque chose », deux états qu'un simple voyant confond. La transcription puis l'insertion s'y affichent ensuite, et la pastille se referme sur le nombre de signes insérés et le nom de l'application destinataire.

**Les répliques.** Trente répliques en version originale, sur le thème de la parole et des machines qui écoutent, de *You talkin' to me?* à *I'm sorry, Dave. I'm afraid I can't do that.* Une nouvelle à chaque dictée, jamais deux fois la même d'affilée. Le format s'y choisit aux flèches du clavier, dans l'onglet Répliques des réglages : réplique seule, réplique et film, ou réplique avec film et année sur deux lignes. Le catalogue est un fichier JSON éditable, `~/Library/Application Support/Goldodict/repliques.json`, complétable depuis les réglages ou à la main.

**Le menu.** Un clic sur l'icône de la barre des menus ouvre un panneau : état, autorisations manquantes, bouton de dictée, choix du moteur, cinq dernières dictées recopiables d'un clic. La dictée lancée depuis ce panneau revient à l'application où vous étiez, et non à Goldodict.

**Importer un fichier audio.** Le bouton *Importer…* du panneau ouvre un sélecteur de fichier, ou glissez-déposez directement un fichier audio sur l'icône de la barre des menus. Le moteur actuellement choisi transcrit le fichier — Apple ou Whisper, jamais un moteur imposé — et une fenêtre affiche le texte obtenu avec deux boutons, *Copier* et *Coller*. Rien ne s'insère automatiquement, contrairement à une dictée live. Refusé pendant une dictée en cours, le moteur ne tenant qu'une session à la fois.

> L'icône de la barre des menus disparaît derrière le chevron `‹` quand la barre est chargée. Pour l'en sortir, maintenez ⌘ et faites-la glisser vers la gauche. Au premier lancement, une fenêtre d'accueil demande les trois autorisations une à une, propose le choix du moteur et offre un champ d'essai.

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

**Le biais est un budget, pas un interrupteur.** Les termes biaisés sont concaténés en un prompt que Whisper plafonne à 223 tokens, en gardant les derniers. Passé la centaine de termes, chaque ajout en évince silencieusement un autre. Le drapeau se réserve donc à ce que le moteur ne peut pas deviner, sigles, noms propres, toponymes composés. Une locution française ordinaire n'en a pas besoin, le moteur l'écrit déjà. Un test de la suite vérifie que le prompt reste sous la limite.

**Une entrée dont l'`entendu` égale le `corrige` n'est pas inutile.** La recherche ignore la casse et les accents : `ratione materiae` capture « ratione matériae » et rétablit la forme latine. C'est ainsi que le lexique livré nettoie les accents parasites sans dépenser un token de biais.

Le lexique livré couvre les juridictions, les codes et sigles du droit public et du droit pénal, les grands noms de la jurisprudence administrative, le latin de procédure, les communes de la Haute-Garonne à trait d'union et les fautes de forme classiques (« conflit d'intérêt », « procès verbal », « au vue de »).

> **Attention aux mots courants.** Une entrée frappe partout, sans égard au contexte : `partant` → `Partant` transforme « en partant de là » en « en Partant de là ». Un `entendu` qui existe aussi comme mot français ordinaire est à éviter.

**Commandes de ponctuation** — « virgule », « point », « à la ligne », « ouvrez les guillemets », « point d'interrogation ». Les espaces insécables de la typographie française sont posées automatiquement devant `; : ! ?` et à l'intérieur des guillemets.

Les marques simples sont désactivables dans les réglages : en droit, « le point de départ du délai » ne doit pas devenir une ponctuation.

## Installation

```bash
./scripts/make_app.sh
```

Le script compile, signe avec l'identité Developer ID et installe dans `/Applications`. Au premier lancement, autoriser le **Microphone**, l'**Accessibilité** puis la **Surveillance de l'entrée** dans Réglages Système > Confidentialité et sécurité.

Sans l'Accessibilité, le texte est copié dans le presse-papiers mais n'est pas collé. Sans la Surveillance de l'entrée, le raccourci global ne répond pas et la dictée ne se lance que depuis la barre des menus. Ces deux défauts sont silencieux par nature : ils sont donc signalés dans le menu, dans les réglages et dans la fenêtre d'accueil.

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
| `Sources/GoldodictCore/` | Logique pure et testable : état, geste de déclenchement, raccourci, lexique, répliques, ponctuation, typographie |
| `Sources/Goldodict/` | Application : raccourci, audio, moteurs, insertion, réglages |
| `sidecar/` | Démon Python pour Whisper MLX |
| `design/` | Icône vectorielle, et sa déclinaison pour les petites tailles |
| `scripts/make_app.sh` | Construction du bundle, signature, installation |
| `scripts/make_icon.sh` | Rendu de `Resources/AppIcon.icns` depuis le vectoriel |
| `docs/ARCHITECTURE.md` | Décisions de conception et pièges rencontrés |
