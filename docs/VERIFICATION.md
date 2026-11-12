# Vérification

État au **2026-11-12**. La personne qui utilise la machine avait une session
d'enregistrement en cours pendant le développement. Aucune capture réelle,
aucune activation audio, aucun accès microphone, aucune demande d'autorisation
et aucune lecture de fichier issu d'une capture réelle n'ont été effectués.

## Prouvé maintenant, sans capture

| Élément | Méthode | Résultat |
|---|---|---|
| Le projet compile | `swift build -c debug`, puis `./scripts/build.sh` | OK le 2026-11-12, exit 0 |
| Tests purs | `./scripts/test.sh` | **23 tests, 0 échec** (2026-11-12) |
| Nom `2026 11 12 Réunion.mp3` | `RecordingNameTests.testExampleNameMatchesRequestedFormat` | OK |
| Collision ` (2)` puis ` (3)` | `testCollisionUsesTwoThenThreeBeforeExtension` | OK |
| Octets du fichier existant préservés | `testCreatedFileNeverOverwritesOriginalBytes` | OK |
| Machine d'état simulée jusqu'à idle | `RecordingSessionTests.testMockCaptureStartThenStopEndsIdleWithFrozenElapsed` | OK |
| Échec de démarrage non écrasé par `recording` | `RecordingSessionTests.testCaptureStartedCannotOverwriteStartupFailure` | OK |
| Chronomètre figé à l'arrêt | `RecordingClockTests.testElapsedFreezesAfterStop` | OK |
| MP3 lisible | PCM synthétique → `MP3FileWriter` → `AVAudioFile` | OK, décodage réel |
| Arrêt immédiat | `testEmptyRecordingStillProducesReadableMP3` | OK, MP3 lisible |
| Bundle autonome | `codesign`, `otool -L`, absence de dylib Shine | OK, `Naada.app` 736 Ko, arm64 |
| Aucun démarrage automatique | inspection : aucun appel `SCStream` hors de `startRecording()` | statique, OK |
| Aucun micro | aucun `captureMicrophone`, aucune clé micro dans l'Info.plist | statique, OK |
| Aucune coupure système | aucun changement de volume/routage, capture ScreenCaptureKit passive | statique, OK |

## Différé jusqu'à confirmation que la session est terminée

Ces points **ne doivent pas** être exécutés pendant que la personne enregistre.
Ils exigent une vraie capture et/ou une autorisation macOS.

1. **Autorisation** : premier clic sur Enregistrer, comportement de l'invite
   « Enregistrement de l'écran », refus puis nouvelle tentative.
2. **Capture réelle** : choisir une application qui joue un son, vérifier que le
   son reste audible sur la sortie système, sans coupure ni changement de
   volume.
3. **Démarrage/arrêt** : vérifier que l'état passe réellement par
   `Préparation → Enregistrement → Finalisation → Prêt`.
4. **Chronomètre** : vérifier qu'il avance pendant la capture et qu'il est figé
   après l'arrêt, y compris après plusieurs secondes.
5. **Fichier** : vérifier le nom réel `AAAA MM JJ Titre.mp3`, la date locale, le
   dossier choisi, puis relancer une capture avec le même titre pour obtenir
   `Titre (2).mp3` sans modifier le premier fichier.
6. **Lecture** : ouvrir le MP3 dans QuickTime / Musique / `afplay`, vérifier la
   durée, le contenu et l'absence de coupures.
7. **Continuité du son système** : pendant la capture, vérifier qu'une autre
   application continue de s'entendre normalement.
8. **Quitter pendant une capture** : vérifier l'alerte de refus de fermeture.
9. **Interface** : rendu réel de la fenêtre, sélecteurs, focus du champ titre,
   accessibilité clavier.
10. **Reconstruction** : vérifier si macOS redemande l'autorisation après un
    nouveau build ad hoc.

## Commandes de vérification autorisées maintenant

```bash
cd /Volumes/NVME1To/Projets/naada
./scripts/test.sh
./scripts/check.sh
```

`scripts/check.sh` ne lance pas l'application, n'appelle pas ScreenCaptureKit
et n'ouvre aucun périphérique audio.

Dernière exécution : **2026-11-12**, après `swift package clean` et
`./scripts/check.sh` — compilation release OK, **23 tests, 0 échec**, bundle
`Naada.app` signé ad hoc et contrôlé (aucune dylib Shine ni dépendance
Homebrew).

## Ce qui n'a pas été fait

- Pas de `open Naada.app` (pour éviter toute invite et toute préférence écrite).
- Pas de `SCStream.startCapture`, pas de `SCShareableContent` à l'exécution.
- Pas de tap Core Audio, pas de `AudioHardwareCreateProcessTap`.
- Pas de micro, pas de permission, pas de mute, pas de routage.
- Pas d'enregistrement réel, pas de lecture du MP3 produit.
