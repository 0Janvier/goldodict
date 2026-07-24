# Abracadabra

Dictée vocale **entièrement locale** pour macOS. Le texte dicté arrive dans le presse-papiers et se colle automatiquement dans l'application active, quelle qu'elle soit.

Rien ne quitte l'ordinateur : ni l'audio, ni la transcription. Aucun fichier n'est écrit sur disque, l'historique reste en mémoire vive.

## Fonctionnement

Un raccourci global déclenche la dictée selon deux gestes :

- **appui bref** : bascule marche/arrêt, pour les longues dictées ;
- **appui maintenu** : push-to-talk, la dictée s'arrête au relâchement.

La capture démarre dès l'enfoncement de la touche, aucun début de phrase n'est perdu.

## Moteurs de transcription

| Moteur | Caractéristiques |
|---|---|
| **Apple `SpeechTranscriber`** (défaut) | Natif macOS 26, transcription au fil de l'eau, aucune dépendance |
| **Whisper MLX** | Modèles `large-v3-turbo`, `large-v3`, `base`, `tiny` — meilleure ponctuation française, transcription par lots |

## Vocabulaire personnalisé

Deux mécanismes, cumulables.

**Lexique de correction** — un fichier JSON associe ce qui est entendu à ce qu'il faut écrire, pour les noms propres et le vocabulaire du contentieux.

```json
[
  { "entendu": "cage de baisse", "corrige": "CAA de Bordeaux" },
  { "entendu": "ces jaïna", "corrige": "CE, Sect." }
]
```

Emplacement : `~/Library/Application Support/Abracadabra/lexique.json`.

**Commandes de ponctuation** — « virgule », « point », « à la ligne », « ouvrez les guillemets » sont interprétées comme des actions de mise en forme, avec les espaces insécables de la typographie française.

## Installation

```bash
./scripts/make_app.sh
```

Le script compile, signe avec l'identité Developer ID et installe dans `/Applications`. Au premier lancement, autoriser le **Microphone** puis l'**Accessibilité** dans Réglages Système > Confidentialité et sécurité.

## Développement

```bash
swift build --scratch-path ~/.cache/abracadabra-build
swift test  --scratch-path ~/.cache/abracadabra-build
```

Le `--scratch-path` hors de `~/Documents` est nécessaire : iCloud évince le contenu de `.build` et casse les compilations.

## Structure

| Chemin | Rôle |
|---|---|
| `Sources/AbracadabraCore/` | Logique pure et testable (état, lexique, ponctuation) |
| `Sources/Abracadabra/` | Application : raccourci, audio, moteurs, insertion, réglages |
| `sidecar/` | Démon Python pour Whisper MLX |
| `scripts/make_app.sh` | Construction du bundle et installation |
