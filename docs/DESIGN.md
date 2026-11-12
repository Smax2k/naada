# Architecture

## Cibles Swift Package

| Cible | Rôle |
|---|---|
| `CShine` | Encodeur MP3 Shine (C), compilé statiquement dans le binaire. |
| `NaadaCore` | Logique pure et testable : nommage, création exclusive, horloge, écrivain MP3. |
| `Naada` | Application SwiftUI, catalogue des applications, capture ScreenCaptureKit. |
| `NaadaCoreTests` | Tests XCTest sans capture ni périphérique. |

## Capture

```text
Application choisie
        │
        ▼
SCShareableContent.excludingDesktopWindows
        │  filtre : display + includingApplications([app]) + audio seul
        ▼
SCStream(capturesAudio = true, sampleRate = 48 000, channelCount = 2)
        │  aucune sortie écran ; excludesCurrentProcessAudio = true
        ▼
CMSampleBuffer audio (souvent Float32 planaire)
        │
        ▼
AVAudioConverter → PCM 16 bits entrelacé 48 kHz
        │
        ▼
MP3FileWriter (Shine) → fichier créé en O_EXCL
```

Pourquoi ce choix :

- ScreenCaptureKit est l'API macOS prévue pour l'audio d'une application, sans
  installer de pilote ni créer de tap de processus.
- Aucun périphérique audio n'est ouvert ni modifié : la sortie système continue
  normalement, le son reste audible.
- Le filtre inclut une application précise, pas tout le système.
- `excludesCurrentProcessAudio` évite une boucle avec Naada.
- Aucun micro n'est demandé : `captureMicrophone` reste à sa valeur par défaut
  (`false`) et aucune clé `NSMicrophoneUsageDescription` n'est déclarée.

## Machine d'état

```text
idle ──click Enregistrer──▶ preparing ──startCapture OK──▶ recording
  ▲                              │                              │
  │                              │ erreur                       │ click Arrêter
  │                              ▼                              ▼
  └────────────────────────── failed ◀──arrêt inattendu── stopping
                                                               │
                                                               ▼
                                                             idle
```

- `preparing` : le fichier MP3 et le filtre sont créés ; l'autorisation système
  peut apparaître ici.
- `recording` : `startCapture` a réussi, le moteur est encore actif et aucun
  arrêt n'a été signalé ; le chronomètre démarre.
- `stopping` : l'horloge est déjà figée ; le reliquat PCM est complété par du
  silence, la dernière frame est écrite, le fichier est synchronisé et fermé.
- `failed` : le message réel de l'erreur est affiché ; un fichier partiel peut
  être conservé si la capture avait commencé.
- Quitter pendant une capture est refusé par `applicationShouldTerminate` pour
  ne pas tronquer le MP3.

## Sérialisation de la capture

Deux files sérialisées, sans verrou bloquant depuis un contexte async :

- **`audioQueue`** possède exclusivement `writer`, `converter` et
  `reportedAudioError`. Les callbacks d'échantillons y écrivent ; l'installation
  au démarrage, le drainage et la fermeture du MP3 y passent aussi.
- **`lifecycleQueue`** possède `stream`, `isStarting`, `isStopping` et
  l'erreur d'arrêt inattendu. Les transitions de démarrage, d'arrêt et le
  delegate `didStopWithError` s'y sérialisent.

À l'arrêt, le moteur ne retire pas le writer avant de vider la file : il exécute
le drainage des callbacks déjà en attente **et** `writer.finish()` dans le même
bloc `audioQueue.sync`. Un arrêt inattendu fait de même via `audioQueue.async`,
après les buffers déjà en file. Un démarrage qui échoue passe par la même file
pour annuler le fichier, après avoir marqué le flux comme non démarrable.

La vue conserve un jeton de session : après `startCapture`, elle ne passe à
« Enregistrement » que si le moteur est encore actif, que le jeton est le sien
et que l'état est toujours `preparing`. Un arrêt inattendu survenu pendant le
démarrage ne peut donc pas être écrasé par l'état `recording`.

## Nommage et fichiers

`RecordingName` est pur : date + titre + prédicat d'existence. `RecordingFile`
réalise ensuite la création réelle avec `open(O_CREAT | O_EXCL)`, ce qui rend la
non-écrasement atomique même si un fichier apparaît entre la décision et
l'écriture.

La date est celle du démarrage (calendrier grégorien, fuseau local). Le titre
est nettoyé (`/` et `:` → `-`, contrôle → espace, espaces compactés) et borné en
caractères **et** en octets UTF-8 pour rester sous la limite APFS.

## Encodeur MP3

`vendor/shine` contient la source de Shine (savonet/shine, commit indiqué dans
`vendor/shine/COMMIT`) et sa licence LGPL-2. Le code est compilé dans la cible
`CShine`, liée statiquement. Aucun binaire Homebrew, aucun appel réseau,
aucune dépendance externe à l'exécution.

`MP3FileWriter` :

- initialise Shine en 48 kHz / stéréo / 192 kbit/s ;
- accumule les échantillons jusqu'à une frame de 1 152 échantillons par canal ;
- écrit les frames au fil de l'eau ;
- complète le reliquat par du silence, appelle `shine_flush`, synchronise et
  ferme le fichier ;
- est protégé par un verrou, car les échantillons arrivent sur une file audio et
  l'arrêt vient du fil principal.

## Limites connues

- La source Shine vendue produit deux avertissements de conversion d'entiers
  (`-Wshorten-64-to-32`) à la compilation ; le code n'a pas été modifié et les
  tests d'encodage/décodage passent.
- Si l'application source n'a aucune fenêtre, ScreenCaptureKit peut ne rien
  fournir ; l'interface liste les applications « régulières » ouvertes.
- La durée du MP3 dépend des buffers audio réellement fournis par le système ;
  le chronomètre, lui, mesure le temps réel de la session. La continuité
  audio/temps doit être vérifiée sur une vraie capture après la session.
- Un bundle signé ad hoc (hors `./scripts/build.sh`, qui utilise Developer ID)
  change d'exigence désignée à chaque reconstruction : macOS peut alors
  redemander l'autorisation d'enregistrement de l'écran. La signature Developer
  ID garde l'identifiant et l'équipe stables, mais son runtime durci et son
  horodatage ne valent pas notarisation.
- Pas de reprise, pause, édition, tags ID3, planification ni envoi réseau.
