# Vérification

État au **2026-11-12**. La session d'enregistrement de la personne qui utilise la
machine est **terminée** (confirmé par Jonathan). Une passe d'interface réelle a
été faite sur un bundle **isolé** construit depuis `HEAD` (`dba658c`) ; l'agent
n'a ni démarré ni arrêté de capture, n'a pas déclenché de son et n'a pas accepté
d'invite de permission. Jonathan a testé lui-même l'enregistrement et rapporte
qu'il fonctionne parfaitement : c'est un **témoignage utilisateur**, pas une
observation de l'agent.

## Passe UI du 2026-11-12 (bundle isolé)

Build : copie propre de `HEAD` par `git archive`, puis
`./scripts/build.sh release` dans
`/private/var/folders/…/opencode/naada-proof-20261112-202104` — exit 0. Bundle
ad hoc `com.naada.recorder`, CDHash `4af24d79…` (différent du bundle partagé
`bfff3033…`).

| Élément | Méthode | Résultat observé par l'agent |
|---|---|---|
| Lancement du bundle isolé | `cua-driver launch_app`, snapshot de la fenêtre | Fenêtre 620×496, état **Prêt**, chrono `00:00` |
| Aucun démarrage automatique | premier snapshot | Aucune capture ; bouton Enregistrer inactif sans dossier |
| Applications ouvertes proposées | sélecteur : Chrome au lancement, puis Finder | au moins deux applications ouvertes proposées et sélectionnables |
| Choix d'une application déjà ouverte | sélection de **Finder** | Finder affiché ; titre de session passé à « Finder » |
| Dossier de sortie | champ affiché après le test de Jonathan | dossier Google Drive de l'utilisateur, **hors dépôt** |
| Carte de sortie | après l'arrêt du test utilisateur | « Dernier fichier enregistré » : `2026 11 12 Google Chrome.mp3` |
| Nom du fichier | observation de la carte | conforme à `AAAA MM JJ <titre>.mp3` |
| Chronomètre après arrêt | observation répétée | `00:18` figé, phase **Prêt** |
| MP3, métadonnées seulement | `afinfo`, aucune lecture | MP3, 2 canaux, 48 000 Hz, 18,984 s, 192 kbit/s |

États vus directement par l'agent : **Prêt** avant et après le test, puis la
carte du dernier fichier. Les états **Préparation**, **Enregistrement** et
**Finalisation** n'ont pas été observés en direct par l'agent.

L'agent n'a **pas** cliqué sur **Enregistrer** ni sur **Arrêter** : le fichier
ci-dessus provient du test de Jonathan. Il n'a été ni modifié ni supprimé. La
sélection de Finder, faite après ce test, n'a servi à aucune capture.

### Témoignage utilisateur

> Jonathan a confirmé le 2026-11-12 avoir testé lui-même l'enregistrement : il
> fonctionne parfaitement.

Ce test a eu lieu dans l'instance isolée lancée par l'agent (pid 62173) ; le
fichier observé ci-dessus en est issu. Le bundle partagé n'a pas été lancé.

Ce retour porte sur le fonctionnement général, pas sur chacune des vérifications
ci-dessous. Il ne prouve pas l'écoute du contenu.

### Permission

Aucune invite n'a été acceptée ni contournée par l'agent. Les journaux `tccd`
montrent une modification de l'autorisation « Enregistrement de l'écran » pour
`com.naada.recorder` à 20:25:39, pendant le test de Jonathan, suivie des accès de
capture. L'agent n'a pas observé l'invite elle-même et n'a pas testé le refus.
Le bundle isolé ayant un CDHash différent du bundle partagé, la question d'une
nouvelle autorisation après reconstruction **reste non tranchée par l'agent**.

## Prouvé avant la passe UI, sans capture

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

## Non exercé par l'agent

Ces points restent hors de la preuve de l'agent. Le témoignage de Jonathan couvre
le fonctionnement général de l'enregistrement, pas ces détails :

1. **Invite de permission** : affichage, refus puis nouvelle tentative — non
   observés par l'agent.
2. **Capture réelle** : l'agent n'a pas cliqué Enregistrer/Arrêter ; les états
   Préparation → Enregistrement → Finalisation n'ont pas été vus en direct.
3. **Continuité du son système** pendant la capture : non vérifiée.
4. **Lecture audible** du MP3 : non faite ; `afinfo` ne prouve que le conteneur
   et les métadonnées, jamais le contenu audible.
5. **Collision** `Titre (2).mp3` avec le même titre : non exercée.
6. **Quitter pendant une capture** : non exercé.
7. **Accessibilité** clavier : non exercée.
8. **Nouvelle autorisation après reconstruction** : non tranchée par l'agent.

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
Homebrew). La passe UI ci-dessus a été faite sur un bundle isolé, pas sur le
bundle partagé.

## Ce qui n'a pas été fait

- Pas de `Enregistrer` ni d'`Arrêter` cliqué par l'agent.
- Pas d'invite d'autorisation acceptée ni de refus provoqué par l'agent.
- Pas de `SCStream.startCapture` déclenché par l'agent.
- Pas de tap Core Audio, pas de mute, pas de changement de volume ou de routage.
- Pas de son provoqué, coupé, muté ou rerouté.
- Pas de lecture du MP3, ni avec QuickTime, ni avec Musique, ni avec `afplay`.
- Pas de suppression ni de modification du fichier produit par Jonathan.
- Le bundle partagé `Naada.app` n'a pas été lancé ni supprimé.
