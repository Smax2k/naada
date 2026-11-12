# Vérification

État au **2026-11-12**. La session d'enregistrement de la personne qui utilise la
machine est **terminée** (confirmé par Jonathan). Ce document sépare :

- la **passe UI historique** du 2026-11-12, faite sur un bundle isolé construit
  depuis `dba658c` (23 tests à l'époque) ;
- le **témoignage utilisateur** de Jonathan du 2026-11-12, qui porte sur
  l'enregistrement en général ;
- la **vague de vérification** du 2026-11-12 sur `7f50042` : alignement, jauge,
  icône, build et installation ;
- ce qui reste **non observé**.

Aucune capture n'a été démarrée ni arrêtée par les agents, aucun son n'a été
déclenché et aucune invite de permission n'a été acceptée. Jonathan a testé
lui-même l'enregistrement et rapporte qu'il fonctionne parfaitement : c'est un
**témoignage utilisateur**, pas une observation de l'agent.

## Passe UI historique du 2026-11-12 (bundle isolé `dba658c`)

Cette passe précède les changements de jauge, d'alignement et d'icône. Elle est
conservée comme historique et ne décrit pas le build `7f50042`.

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

### Témoignage utilisateur du 2026-11-12

> Jonathan a confirmé le 2026-11-12 avoir testé lui-même l'enregistrement : il
> fonctionne parfaitement.

Ce test a eu lieu dans l'instance isolée lancée par l'agent (pid 62173) ; le
fichier observé ci-dessus en est issu. Le bundle partagé n'a pas été lancé.

Ce retour porte sur le fonctionnement général de l'enregistrement. Il ne couvre
pas la jauge de niveau en signal, l'alignement des réglages, l'icône, la nouvelle
installation ni les points listés plus bas. Il ne prouve pas non plus l'écoute du
contenu.

### Permission

Aucune invite n'a été acceptée ni contournée par l'agent. Les journaux `tccd`
montrent une modification de l'autorisation « Enregistrement de l'écran » pour
`com.naada.recorder` à 20:25:39, pendant le test de Jonathan, suivie des accès de
capture. L'agent n'a pas observé l'invite elle-même et n'a pas testé le refus.
Le bundle isolé ayant un CDHash différent du bundle partagé, la question d'une
nouvelle autorisation après reconstruction **reste non tranchée par l'agent**.
Le build installé ensuite a un autre CDHash (`988b6333…`) : le comportement de
TCC après ce changement de CDHash n'a pas été observé.

## Vague de vérification du 2026-11-12 (`7f50042`)

Build de référence : commit `7f50042c8337b0faaee4f2c681e37cabc7531480`.
`./scripts/check.sh` : release OK, **27 tests, 0 échec**. Aucune capture audio,
aucune invite de permission et aucun lancement de l'application installée n'ont
eu lieu pendant cette vague.

| Élément | Méthode | Résultat |
|---|---|---|
| Alignement des réglages | `Sources/Naada/ContentView.swift`, rendu hors écran `NSHostingView` avec `MockModel`, sans `RecorderViewModel` ni capture | colonnes de contrôles alignées : départ à 214 pt, bord à 582 pt ; un chemin long est tronqué au milieu ; la carte enregistreur reste inchangée |
| Dossiers vide et long | même rendu hors écran | les deux cas sont rendus sans erreur |
| Jauge au repos (historique) | capture hors écran `.orchestrator/naada-jauge-repos.png` | carte enregistreur à l'état repos ; preuve historique, pas une observation en direct |
| Tests et build | `./scripts/check.sh` sur `7f50042` | release OK, 27 tests, 0 échec |
| Icône | artefacts de build | `Assets.car` avec variantes claire et sombre distinctes ; `AppIcon.icns` 1024 contrôlé |
| Installation | nouveau `/Applications/Naada.app` | installé sans remplacement : `/Applications/Naada.app` et `~/Applications/Naada.app` étaient absents avant |
| Signature | `codesign --verify --strict` (revérifié par le lead) | OK ; Authority `Developer ID Application: Jonathan Bahu (BG55CF653X)`, Team `BG55CF653X`, CDHash `988b633361631ddab11c24cbc5ca05e97a989f6b`, flags `0` sans runtime, timestamp `none` |
| Gatekeeper | `spctl` | exit 3, `rejected`, source `Unnotarized Developer ID` |
| Notarisation et publication | — | aucune |

## Prouvé avant la passe UI, sans capture (historique `dba658c`)

Ces preuves datent du build `dba658c` ; le build `7f50042` est couvert par
`./scripts/check.sh` (27 tests) dans la section précédente.

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

## Non exercé / non observé

Ces points restent hors de la preuve. Le témoignage de Jonathan couvre le
fonctionnement général de l'enregistrement, pas ces détails :

1. **Jauge en signal** : aucun enregistrement réel n'a été observé ; le
   mouvement de la jauge, sa montée et sa descente, et son retour à vide à
   l'arrêt ne sont pas prouvés.
2. **Alignement en conditions réelles** : seulement un rendu hors écran ; non
   observé dans l'application lancée.
3. **Icône dans le Dock** : variantes compilées contrôlées, basculement
   clair/sombre dans le Dock non observé.
4. **Application installée** : `/Applications/Naada.app` n'a pas été lancée ;
   Gatekeeper la rejette (non notarisée) ; son état repos n'est pas observé.
5. **TCC après changement de CDHash** : non observé ; on ne sait pas si une
   nouvelle autorisation est demandée après le CDHash `988b6333…`.
6. **Continuité du son système** pendant la capture : non vérifiée.
7. **Lecture audible** du MP3 : non faite ; `afinfo` ne prouve que le conteneur
   et les métadonnées, jamais le contenu audible.
8. **Invite de permission** : affichage, refus puis nouvelle tentative — non
   observés par les agents.
9. **Capture réelle par les agents** : aucun clic Enregistrer/Arrêter ; les
   états Préparation → Enregistrement → Finalisation n'ont pas été vus en
   direct.
10. **Collision** `Titre (2).mp3` avec le même titre : non exercée.
11. **Quitter pendant une capture** : non exercé.
12. **Accessibilité** clavier : non exercée.

## Commandes de vérification autorisées maintenant

```bash
cd /Volumes/NVME1To/Projets/naada
./scripts/test.sh
./scripts/check.sh
```

`scripts/check.sh` ne lance pas l'application, n'appelle pas ScreenCaptureKit
et n'ouvre aucun périphérique audio.

Dernière exécution de la vague : **2026-11-12** sur `7f50042` —
`./scripts/check.sh` : compilation release OK, **27 tests, 0 échec**, artefacts
d'icône contrôlés, application installée signée Developer ID et rejetée par
Gatekeeper. Aucun lancement de l'application installée. La passe UI historique
ci-dessus a été faite sur un bundle isolé, pas sur ce build.

## Test manuel proposé à Jonathan (non exécuté par l'agent)

Avec l'application finalisée `/Applications/Naada.app` (signature Developer ID),
seulement après une ouverture normale autorisée par macOS. Si Gatekeeper ou une
invite empêche l'ouverture, s'arrêter et signaler le message, sans contournement
ni changement de sécurité.

1. Ouvrir une application qui émet déjà du son, puis lancer Naada.
2. Choisir cette application comme source et un dossier **hors du dépôt**.
3. Cliquer sur **Enregistrer** et observer quelques secondes : la jauge doit
   quitter **Repos**, suivre le niveau sonore, puis revenir à vide après
   **Arrêter**.
4. Vérifier que le son de l'application reste audible pendant la capture.

L'agent n'a pas déclenché ce test.

## Ce qui n'a pas été fait

- Pas de `Enregistrer` ni d'`Arrêter` cliqué par les agents.
- Pas d'invite d'autorisation acceptée ni de refus provoqué par les agents.
- Pas de `SCStream.startCapture` déclenché par les agents.
- Pas de tap Core Audio, pas de mute, pas de changement de volume ou de routage.
- Pas de son provoqué, coupé, muté ou rerouté.
- Pas de lecture du MP3, ni avec QuickTime, ni avec Musique, ni avec `afplay`.
- Pas de suppression ni de modification du fichier produit par Jonathan.
- Pas de lancement de l'application installée dans `/Applications`.
- Pas de notarisation ni de publication.
- Le bundle partagé `Naada.app` n'a pas été lancé ni supprimé.
