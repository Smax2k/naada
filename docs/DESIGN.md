# Architecture

## Cibles Swift Package

| Cible | Rôle |
|---|---|
| `CShine` | Encodeur MP3 Shine (C), compilé statiquement dans le binaire. |
| `NaadaCore` | Logique pure et testable : nommage, création exclusive, horloge, écrivain MP3. |
| `Naada` | Application SwiftUI, catalogue des applications, capture audio par tap de processus Core Audio. |
| `NaadaCoreTests` | Tests XCTest sans capture ni périphérique. |

## Capture

```text
Application choisie (SourceApplication.pid)
        │
        ▼
kAudioHardwarePropertyTranslatePIDToProcessObject
        │  AudioObjectID du processus, et lui seul
        ▼
CATapDescription(stereoMixdownOfProcesses:)
        │  tap privé, CATapUnmuted
        ▼
AudioHardwareCreateProcessTap → tap
        │
        ▼
AudioHardwareCreateAggregateDevice
        │  agrégat privé, kAudioAggregateDeviceTapListKey + kAudioSubTapUIDKey
        ▼
AudioDeviceCreateIOProcIDWithBlock → AudioBufferList (format du tap)
        │
        ▼
AVAudioConverter → PCM 16 bits entrelacé 48 kHz
        │
        ▼
MP3FileWriter (Shine) → fichier créé en O_EXCL
```

Pourquoi ce choix :

- le tap cible un unique `AudioObjectID` de processus, traduit depuis le PID
  choisi ; aucun tap global et aucun ciblage par bundle ID ;
- le tap est privé et non muet : le son continue d'aller vers la sortie
  système, sans coupure ni redirection ;
- l'agrégat est privé et n'est jamais défini comme sortie par défaut ; seule
  son entrée est lue par l'IOProc, comme un microphone ;
- aucun écran, aucune fenêtre et aucune image ne sont demandés : la permission
  attendue est l'enregistrement de l'audio du système
  (`NSAudioCaptureUsageDescription`), distincte de l'enregistrement de l'écran ;
- aucun micro n'est demandé : aucune clé `NSMicrophoneUsageDescription` n'est
  déclarée ;
- la cible de déploiement reste 14.0 dans `Package.swift`, mais les API de tap
  sont gardées par `#available(macOS 14.2, *)` ; `LSMinimumSystemVersion` vaut
  14.2, donc 14.0–14.1 ne lance pas l'application et le moteur signale
  explicitement l'indisponibilité.

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

- `preparing` : le fichier MP3 et le tap de processus sont créés ; l'autorisation
  système peut apparaître ici.
- `recording` : `AudioDeviceStart` a réussi, le moteur est encore actif et aucun
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
- **`lifecycleQueue`** possède `tapID`, `aggregateID`, `ioProcID`, `isStarting`,
  `isStopping` et l'erreur d'arrêt inattendu. Les transitions de démarrage et
  d'arrêt s'y sérialisent.

À l'arrêt, le moteur arrête et détruit l'IOProc, puis l'agrégat et le tap ; il
exécute le drainage des callbacks déjà en attente **et** `writer.finish()` dans
le même bloc `audioQueue.sync`. Un démarrage qui échoue détruit les mêmes
ressources dans l'ordre inverse de leur création, puis annule le fichier après
avoir marqué la capture comme non démarrable.

La vue conserve un jeton de session : après `AudioDeviceStart`, elle ne passe à
« Enregistrement » que si le moteur est encore actif, que le jeton est le sien
et que l'état est toujours `preparing`. Un arrêt inattendu survenu pendant le
démarrage ne peut donc pas être écrasé par l'état `recording`.

Un IOProc Core Audio n'a pas de callback d'erreur : ce lot ne détecte pas la
disparition de l'application source. Si elle quitte pendant la capture, le
moteur peut écrire du silence jusqu'à l'arrêt ; `onUnexpectedStop` reste déclaré
pour l'API, mais n'est pas alimenté par ce chemin.

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
- Si l'application source n'expose pas de processus audio (aucune lecture
  audio depuis son lancement, ou processus déjà quitté), la traduction
  PID → objet échoue et le démarrage est refusé avec un message ; aucun repli
  global n'est tenté.
- La durée du MP3 dépend des buffers audio réellement fournis par le système ;
  le chronomètre, lui, mesure le temps réel de la session. La continuité
  audio/temps doit être vérifiée sur une vraie capture après la session.
- Un bundle signé ad hoc (hors `./scripts/build.sh`, qui utilise Developer ID)
  change d'exigence désignée à chaque reconstruction : macOS peut alors
  redemander l'autorisation d'enregistrer l'audio du système. La signature
  Developer ID garde l'identifiant et l'équipe stables, mais son runtime durci et
  son horodatage ne valent pas notarisation.
- Un IOProc Core Audio n'a pas de callback d'erreur : si l'application source
  quitte pendant la capture, le moteur n'en est pas notifié et peut écrire du
  silence jusqu'à l'arrêt. `onUnexpectedStop` reste déclaré pour l'API, mais ce
  lot ne l'alimente pas.
- Le libellé exact de l'invite d'autorisation audio, son refus, la reprise, la
  continuité du son et le contenu réellement capturé n'ont pas été observés :
  aucun lancement ni capture n'ont été faits par l'agent.
- Pas de reprise, pause, édition, tags ID3, planification ni envoi réseau.

## Autorisation audio seule : constat du 12 novembre 2026

> **Constat historique.** Cette section décrit le chemin ScreenCaptureKit alors
> en place et la voie recommandée. Elle est conservée telle quelle ; le lot du
> 13 novembre 2026 l'a mise en œuvre (voir la section « Capture audio seule par
> tap de processus » en fin de document).

Constat établi sur macOS 27.2.1 (26B131), SDK macOS 27.2, sans build, sans
lancement, sans capture et sans modification de TCC. Les preuves retenues sont
les pages Apple et les en-têtes du SDK ; aucun réglage système ni aucune case
cochée n'est invoqué. Les pages ont été lues via leur représentation JSON Apple
(le HTML est rendu en JavaScript).

### Limite du chemin ScreenCaptureKit (avant le 13 novembre 2026)

Le chemin alors en place était ScreenCaptureKit, même si seule la sortie audio
était consommée :

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

### Suite donnée le 13 novembre 2026

Le lot 1 a mis en œuvre cette voie dans `Sources/Naada/AudioCaptureEngine.swift` :
traduction du PID choisi en objet processus, tap stéréo privé et non muet,
agrégat privé portant `kAudioAggregateDeviceTapListKey` et `kAudioSubTapUIDKey`,
puis lecture par IOProc et conversion vers le writer MP3 inchangé. L'invariant
correspondant est isolé dans `Sources/NaadaCore/ProcessTapConstraints.swift` et
testé. `packaging/Info.plist` déclare `NSAudioCaptureUsageDescription` et
`LSMinimumSystemVersion` 14.2 ; `ScreenCaptureKit` n'est plus importé ni lié.

## Capture audio seule par tap de processus — 13 novembre 2026

Le chemin ScreenCaptureKit est remplacé par un tap de processus Core Audio.
Aucune image, aucune fenêtre et aucun écran ne sont demandés.

### Fonctionnement

- `SourceApplication.pid` est traduit par
  `kAudioHardwarePropertyTranslatePIDToProcessObject`. Un PID absent, inconnu du
  HAL ou sans objet processus donne `sourceApplicationNotFound` ; aucun repli
  global n'est tenté.
- Le `CATapDescription` est construit en stéréo pour ce seul objet processus,
  avec `isPrivate = true`, `isExclusive = false` et `muteBehavior = .unmuted`.
- L'agrégat est privé, non empilé, et contient le tap via
  `kAudioAggregateDeviceTapListKey` avec l'UUID du tap dans `kAudioSubTapUIDKey`.
  Il n'est jamais défini comme périphérique de sortie par défaut.
- Un `AudioDeviceIOProcID` lit l'entrée de l'agrégat sur `audioQueue`. Le format
  est lu sur le tap (`kAudioTapPropertyFormat`) et converti par
  `AVAudioConverter` vers PCM 16 bits entrelacé 48 kHz, puis écrit par
  `MP3FileWriter`.
- À l'arrêt ou après un démarrage échoué, l'IOProc est arrêté et détruit, puis
  l'agrégat et le tap ; le writer est drainé et fermé. L'automate
  `CaptureLifecycleState` ne revient à `idle` qu'après ces étapes, ce qui rend
  le moteur réutilisable pour un démarrage suivant.
- `ProcessTapConstraints` refuse en test un tap muet, non privé, ciblant
  plusieurs processus, un bundle ID, la sortie par défaut ou le système entier.

### Version et autorisation

- `Package.swift` garde `.macOS(.v14)` et lie `CoreAudio` ; le code de tap est
  sous `#available(macOS 14.2, *)` avec une erreur explicite sur 14.0–14.1.
- `LSMinimumSystemVersion` vaut `14.2`, donc l'application ne se lance pas sur
  14.0–14.1.
- `NSAudioCaptureUsageDescription` remplace `NSScreenCaptureUsageDescription` :
  « aucune image », « le son reste audible », « aucune capture ne démarre avant
  votre clic ».
- L'autorisation attendue est celle de l'audio du système, pas celle de
  l'enregistrement de l'écran.

### Preuves statiques du 13 novembre 2026

Aucun lancement de Naada, aucune création de tap, aucune capture, aucun son et
aucune action TCC n'ont été effectués. Les fichiers de ce lot ne sont pas
commités.

| Élément | Méthode | Résultat |
|---|---|---|
| Compilation et tests | `./scripts/check.sh` | exit 0, release compilée, **61 tests, 0 échec** |
| Absence d'API écran | grep des symboles ScreenCaptureKit, SCStream, SCShareableContent et SCContentFilter dans `Sources` | aucun résultat ; `NSScreenCaptureUsageDescription` absent |
| Absence de clé écran | `plutil -extract NSScreenCaptureUsageDescription raw Naada.app/Contents/Info.plist` | clé absente |
| Autorisation audio | `plutil -extract NSAudioCaptureUsageDescription raw …` | clé présente, texte français attendu |
| Version minimale | `plutil -extract LSMinimumSystemVersion raw …` | `14.2` |
| Liaisons | `otool -L Naada.app/Contents/MacOS/Naada` | `CoreAudio.framework` présent, `ScreenCaptureKit.framework` absent |
| Signature | `codesign --verify --strict` ; `codesign -dv --verbose=4` ; `codesign -d -r-` | OK ; équipe `BG55CF653X`, runtime durci, horodatage ; exigence identifiant + équipe, sans CDHash |
| Installation | `/Applications/Naada.app` | non modifiée par ce lot |

### Non observé / non corrigé

- L'invite d'autorisation audio, son libellé exact, un refus, une reprise après
  autorisation et la non-répétition de l'invite n'ont **pas** été observés.
- Aucun tap n'a été créé à l'exécution : le contenu réellement capturé, le
  format réel des buffers, la continuité du son pendant la capture et le
  comportement à l'arrêt de l'application source ne sont **pas** vérifiés.
- Le chemin 14.0–14.1 n'a pas été exécuté (machine en macOS 27.2.1) ; seule la
  garde statique est vérifiée.
- `onUnexpectedStop` reste dans l'API, mais aucun callback Core Audio ne
  l'alimente : la disparition de la source n'est pas détectée et le moteur peut
  enregistrer du silence jusqu'à l'arrêt.
- Ces points ne sont ni prouvés ni corrigés par ce lot ; ils restent à vérifier
  au runtime.
