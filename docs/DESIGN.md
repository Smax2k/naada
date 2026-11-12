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

## Autorisation audio seule : constat du 12 novembre 2026

Constat établi sur macOS 27.2.1 (26B131), SDK macOS 27.2, sans build, sans
lancement, sans capture et sans modification de TCC. Les preuves retenues sont
les pages Apple et les en-têtes du SDK ; aucun réglage système ni aucune case
cochée n'est invoqué. Les pages ont été lues via leur représentation JSON Apple
(le HTML est rendu en JavaScript).

### Limite du chemin actuel

Le chemin actuel reste ScreenCaptureKit, même si seule la sortie audio est
consommée :

- `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)`
  (`Sources/Naada/AudioCaptureEngine.swift`) énumère les écrans, applications et
  fenêtres, puis le flux `SCStream` est créé. C'est l'ensemble de ce chemin
  ScreenCaptureKit qui relève de l'autorisation d'enregistrement de l'écran.
- `SCContentFilter(display:including:exceptingWindows:)` rattache le flux à un
  écran ; `configuration.width` et `height` ne servent qu'à la vidéo, et seule
  une sortie `.audio` est ajoutée. Ces réglages ne changent pas la classe de
  permission demandée par l'API. Le code échoue aussi avec `noDisplayAvailable`
  si aucun écran n'est disponible, alors que l'audio seul n'en a pas besoin.
- `NSScreenCaptureUsageDescription` (`packaging/Info.plist`) est la description
  de cette autorisation. Son texte actuel décrit l'audio, mais la clé et l'API
  restent celles de l'écran. La clé ne déclenche rien par elle-même : la demande
  TCC vient des appels ScreenCaptureKit. La retirer sans retirer ces appels ne
  rend pas la capture audio seule.
- La documentation ScreenCaptureKit demande l'autorisation d'enregistrement de
  l'écran avant de capturer du contenu, et l'échantillon Apple indique que le
  système la demande au premier lancement. Le fait que Naada ne consomme aucune
  image ne change pas cette exigence.

Références lues :

- <https://developer.apple.com/documentation/screencapturekit>
- <https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos>
- <https://developer.apple.com/documentation/screencapturekit/scshareablecontent>

Conséquence : un refus d'enregistrement de l'écran bloque ce chemin. Pour une
autorisation audio seule, il faut sortir de ScreenCaptureKit.

### Voie officielle audio seule : taps de processus Core Audio

Apple documente les taps de processus et leur agrégat :

- API : `AudioHardwareCreateProcessTap(_:_:)` avec un `CATapDescription`, puis
  `AudioHardwareCreateAggregateDevice(_:_:)` et
  `kAudioAggregateDevicePropertyTapList` pour lire le tap comme une entrée.
- Version : `AudioHardwareTapping.h` déclare
  `API_AVAILABLE(macos(14.2)) API_UNAVAILABLE(ios, watchos, tvos)` ; la page
  Apple demande macOS 14.2 ou ultérieur.
- Clé : `NSAudioCaptureUsageDescription`, documentée à partir de macOS 14.2.
  La page Apple l'exige dans `Info.plist` et précise que le système demande
  l'autorisation « system audio recording » au premier enregistrement depuis un
  agrégat contenant un tap. C'est une autorisation audio, distincte de
  l'enregistrement de l'écran. Cette voie ne dépend donc pas de l'autorisation
  d'enregistrement de l'écran, mais elle ne supprime pas toute autorisation :
  elle demande l'autorisation audio.
- Non-reroutage : `CATapMuteBehavior` vaut `CATapUnmuted` par défaut, décrit
  comme « Audio is captured by the tap and also sent to the audio hardware ».
  Un tap passif non muet est donc possible. `CATapMuted` et
  `CATapMutedWhenTapped` couperaient la sortie et ne doivent pas être utilisés.
- Agrégat privé : `kAudioAggregateDeviceIsPrivateKey` rend l'agrégat visible
  seulement au processus qui l'a créé ; le tap lui-même peut être privé avec
  `CATapDescription.isPrivate`. L'agrégat ne change pas à lui seul la sortie par
  défaut : celle-ci est une propriété distincte
  (`kAudioHardwarePropertyDefaultOutputDevice`). C'est un conteneur d'entrée,
  « just like a microphone ».
- Ciblage : `CATapDescription.processes` attend des `AudioObjectID` de
  processus. `kAudioHardwarePropertyTranslatePIDToProcessObject` traduit le PID
  en objet processus. `bundleIDs` n'est disponible qu'à partir de macOS 26.0 et
  ne peut donc pas servir pour la cible 14.x.

Références lues :

- <https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps>
- <https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription>
- En-têtes lus sous
  `$(xcrun --show-sdk-path)/System/Library/Frameworks/CoreAudio.framework/Headers/` :
  `AudioHardwareTapping.h`, `CATapDescription.h`, `AudioHardware.h`.
- En-têtes lus sous
  `$(xcrun --show-sdk-path)/System/Library/Frameworks/ScreenCaptureKit.framework/Headers/` :
  `SCStream.h`, `SCShareableContent.h`.

### Ce qui n'est pas prouvé

- Aucune capture n'a été lancée : le libellé exact de la demande TCC sur
  macOS 27.2.1, le comportement en cas de refus, la reprise après redémarrage de
  l'application source et la capture d'applications à processus audio séparés
  (par exemple Chrome) restent à vérifier en runtime.
- La page de l'échantillon Core Audio taps affiche macOS 26.0 (et Xcode 26.0)
  dans ses métadonnées, alors que son corps et les en-têtes confirment 14.2. La
  version 14.2 est retenue sur la base des en-têtes et de la page de la clé.
- Le projet cible macOS 14.0 (`Package.swift`, `LSMinimumSystemVersion`), alors
  que l'API demande 14.2. `PackageDescription.MacOSVersion` n'a pas de cas
  14.2, mais `SupportedPlatform.macOS(_ versionString: String)` existe dans
  l'interface du toolchain (Swift 6.4.2) : `.macOS("14.2")` permet donc
  d'exprimer 14.2. Si la cible de déploiement reste 14.0 (`.macOS(.v14)`),
  l'appel doit être entouré d'une garde `#available(macOS 14.2, *)` avec un
  message explicite sur 14.0–14.1 ; relever `LSMinimumSystemVersion` à 14.2
  peut refuser le lancement sur 14.0–14.1, mais ne dispense pas de la garde si
  la cible de déploiement reste 14.0.
- Le catalogue d'applications n'a pas été lu dans ce lot. S'il utilise encore
  ScreenCaptureKit pour énumérer les applications, il doit être traité dans le
  même changement, sinon la promesse « audio seul » ne tient pas.
- La signature Developer ID stable reste nécessaire pour que la nouvelle
  autorisation TCC soit attachée à une identité stable ; ce point n'a pas été
  rejoué.

### Recommandation

Retenir les taps de processus Core Audio pour supprimer la dépendance à
l'autorisation d'enregistrement de l'écran, sous réserve de la vérification
runtime ci-dessus.
Aucun code n'est modifié dans ce lot ; les fichiers à changer sont :

1. `Sources/Naada/AudioCaptureEngine.swift` : remplacer l'énumération
   `SCShareableContent`, le filtre écran et le `SCStream` audio par un
   `CATapDescription` ciblé sur le PID, `AudioHardwareCreateProcessTap`, un
   agrégat privé et une lecture d'entrée, sans définir l'agrégat comme sortie
   par défaut. Conserver le pipeline MP3, le convertisseur et la jauge ; fixer
   explicitement `CATapUnmuted`.
2. `packaging/Info.plist` : ajouter `NSAudioCaptureUsageDescription` avec un
   message français ; retirer `NSScreenCaptureUsageDescription` seulement après
   disparition de tout appel ScreenCaptureKit. Relever
   `LSMinimumSystemVersion` à 14.2 si l'application doit refuser 14.0–14.1, ou
   documenter le message explicite sur ces versions.
3. `Package.swift` : lier `CoreAudio` ; retirer `ScreenCaptureKit` si plus aucun
   appel ne subsiste ; exprimer la cible avec `.macOS("14.2")` (surcharge
   `SupportedPlatform.macOS(_ versionString: String)`), ou garder
   `.macOS(.v14)` et la garde `#available(macOS 14.2, *)` si la cible de
   déploiement reste 14.0.

Cette recommandation repose sur les pages et en-têtes ci-dessus, pas sur un
réglage système, une capture d'écran ou un essai runtime.
