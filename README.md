# Naada

Application Mac autonome pour enregistrer l'audio d'une application ouverte
dans un fichier MP3, sans couper ni rediriger le son du système.

Naada ne démarre **aucune capture au lancement**. Il faut choisir une
application source et un dossier, puis cliquer sur **Enregistrer**.

## Construire et lancer

Prérequis : macOS 14 ou ultérieur, Xcode / Swift 5.9 ou ultérieur.

```bash
cd /Volumes/NVME1To/Projets/naada
./scripts/build.sh            # produit ./Naada.app
open ./Naada.app
```

Le bundle est signé ad hoc (`codesign --sign -`). Il n'est ni notarisé ni
publié. La première capture réelle peut déclencher l'autorisation macOS
« Enregistrement de l'écran » : ScreenCaptureKit sert aussi à capter l'audio
d'une application. Naada ne capture aucune image, n'ouvre aucun microphone et
ne modifie pas la sortie audio.

## Utilisation

1. Choisir l'**application source** dans la liste des applications ouvertes.
2. Choisir le **dossier de sortie** (bouton `Choisir…`). Le dernier dossier est
   mémorisé dans les préférences de l'application.
3. Ajuster le **titre de session** (il reprend le nom de l'application par
   défaut).
4. Cliquer sur **Enregistrer**, puis sur **Arrêter**.

L'état affiché vient du moteur de capture : `Prêt`, `Préparation`,
`Enregistrement`, `Finalisation`, `Erreur`. Le chronomètre ne tourne que pendant
la capture et se fige à l'arrêt.

## Fichiers produits

Nom : `AAAA MM JJ <titre de session>.mp3`

Exemples :

```text
2026 11 12 Réunion.mp3
2026 11 12 Réunion (2).mp3
2026 11 12 Atelier - Q&A - épisode 2.mp3
```

- `/` et `:` du titre deviennent `-` ; les caractères de contrôle et les espaces
  multiples sont normalisés.
- Une collision utilise ` (2)`, ` (3)`, etc. **avant** l'extension. Un fichier
  existant n'est jamais écrasé : la création utilise `O_CREAT | O_EXCL`.
- L'audio est encodé en MPEG-1 Layer III, 48 kHz, stéréo, 192 kbit/s, par
  l'encodeur Shine compilé dans l'application.
- Le MP3 ne contient pas de tag ID3 : le nom du fichier porte la date et le
  titre de session.

## Choix de capture

- **ScreenCaptureKit**, filtre `display + includingApplications` sur
  l'application choisie, avec une sortie audio et aucune sortie écran.
- Aucun tap de processus Core Audio, aucun périphérique audio ouvert, aucun
  agrégat, aucun changement de volume ou de routage.
- `excludesCurrentProcessAudio = true` pour ne pas capturer Naada lui-même.
- Le son système reste audible : la capture est passive.

## Tests

```bash
./scripts/test.sh     # tests purs
./scripts/check.sh    # tests + build release + contrôles du bundle
```

Les tests couvrent :

- le nommage demandé et les collisions ` (2)` / ` (3)` sans écrasement ;
- la préservation des octets d'un fichier existant ;
- la machine d'état simulée : préparation → enregistrement → arrêt → idle,
  chronomètre figé après l'arrêt ;
- l'horloge et son formatage ;
- l'encodage d'un PCM synthétique en MP3, puis son **décodage réel par
  Core Audio** (`AVAudioFile`), sans aucune capture audio ;
- l'arrêt immédiat avant tout buffer, qui produit tout de même un MP3 lisible.

## Vérifications différées

La session utilisateur était en cours pendant le développement. **Aucune
capture réelle, aucun accès microphone, aucune demande d'autorisation, aucune
lecture de fichier issu d'une capture réelle et aucun test de continuité du son
système n'ont été effectués.** Le nommage réel, le choix de dossier, les états
affichés en conditions réelles, l'arrêt et la lecture du MP3 sont également
différés. Ces vérifications sont décrites dans [`docs/VERIFICATION.md`](docs/VERIFICATION.md)
et doivent attendre la confirmation explicite que la session est terminée.

## Documentation

- [`docs/DESIGN.md`](docs/DESIGN.md) — architecture, machine d'état, limites.
- [`docs/VERIFICATION.md`](docs/VERIFICATION.md) — ce qui est prouvé, ce qui
  reste à vérifier.
- [`CREDITS.md`](CREDITS.md) — encodeur MP3 et licence.

## Hors périmètre

Planification, édition audio, publication, réseau, comptes, synchronisation.
Naada enregistre et s'arrête ; il ne fait rien d'autre.
