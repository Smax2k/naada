# Vérification

État au **2026-11-13**. La session d'enregistrement de la personne qui utilise la
machine est **terminée** (confirmé par Jonathan). Ce document sépare :

- la **passe UI historique** du 2026-11-12, faite sur un bundle isolé construit
  depuis `dba658c` (23 tests à l'époque) ;
- le **témoignage utilisateur** de Jonathan du 2026-11-12, qui porte sur
  l'enregistrement en général ;
- la **vague de vérification** du 2026-11-12 sur `7f50042` : alignement, jauge,
  icône, build et installation ;
- la **vérification de signature** du 2026-11-12 (lot 3) : identité Developer ID
  stable pour TCC, sans lancement ni capture ;
- la **vérification d'identité TCC** du 2026-11-12 (lot 1) : signature, processus
  installé et journaux `tccd`, sans lancement ni capture ;
- la **vérification statique du chemin audio seul** du 2026-11-13 (lot 1) :
  tap de processus Core Audio, absence d'API écran, bundle et signature, sans
  lancement, capture ni action TCC ;
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

## Vérification de signature du 2026-11-12 (lot 3)

Constats de l'agent en lecture seule sur les bundles réels ; aucun lancement
d'application, aucune capture et aucune invite de permission.

| Élément | Méthode | Résultat observé par l'agent |
|---|---|---|
| Identité disponible | `security find-identity -v -p codesigning` | `Developer ID Application: Jonathan Bahu (BG55CF653X)` présente |
| Bundle du dépôt | `codesign -dv --verbose=4 Naada.app` | ad hoc, `TeamIdentifier` absent, exigence désignée `cdhash H"069b49c1…"` |
| Bundle installé | `codesign -dv --verbose=4 /Applications/Naada.app` | Developer ID, Team `BG55CF653X`, flags `0` sans runtime, pas de `Timestamp`, CDHash `988b6333…`, exigence stable (identifiant + équipe) |
| Instabilité ad hoc | deux builds isolés du même `HEAD` | CDHash `6d785e67…` et `f078c6c2…` ; les exigences désignées sont ces CDHash, donc différentes |
| Stabilité Developer ID | ces deux builds signés Developer ID + runtime + horodatage | CDHash `131fbba0…` et `e6024dbf…` ; exigence désignée identique (identifiant + `BG55CF653X`) |
| Build et tests | `./scripts/test.sh` puis `./scripts/check.sh` en copie isolée | exit 0, **27 tests, 0 échec** ; signature Team `BG55CF653X`, runtime, horodatage ; exigence sans CDHash |
| Rebuild indépendant | `./scripts/build.sh release` dans une autre copie | CDHash `7c25a29b…`, même exigence désignée |
| Certificat absent | copie du script avec une identité factice | exit 1 avant compilation, message explicite, aucun bundle |
| Point d'appel TCC | lecture seule de `Sources` | `SCShareableContent` uniquement dans `AudioCaptureEngine.start` (ligne 91), atteint par le seul bouton **Enregistrer** (`ContentView` → `startRecording`) ; aucun appel au lancement |

`./scripts/build.sh` signe désormais avec Developer ID, `--options runtime` et
`--timestamp` ; `./scripts/check.sh` contrôle l'équipe, le runtime, l'horodatage
et l'absence de CDHash dans l'exigence, sans exiger de ticket de notarisation.
Aucune entitlement n'a été ajoutée : la signature avec runtime durci et
horodatage réussit sans elle ; le comportement à l'exécution n'a pas été lancé.

La stabilité de l'identité de signature ne prouve pas le comportement de TCC :
aucune invite n'a été observée par l'agent. Selon l'attestation de Jonathan
(utilisateur, non observée par l'agent), l'application apparaissait cochée dans
les autorisations, une nouvelle demande est survenue, puis un texte système a
évoqué un refus du protocole TCC. Aucune action de refus de l'invite par
Jonathan n'est attestée. Le texte affiché vient du système via
`error.localizedDescription` (`Sources/Naada/RecorderViewModel.swift`) ;
aucun message d'erreur TCC n'est écrit en dur dans le dépôt. La capture
correspondante n'a pas été observée.

## Vérification d'identité TCC du 2026-11-12 (lot 1)

Mesures de l'agent en **lecture seule**, sur `HEAD` `027f5b3` et sur les deux
bundles présents, sans build, installation, lancement, capture, son ni réponse à
une invite. L'application installée tournait déjà (pid 21812) ; l'agent ne l'a ni
lancée ni arrêtée.

| Élément | Méthode | Résultat observé par l'agent |
|---|---|---|
| Bundle installé | `PlistBuddy` sur `Info.plist` | `CFBundleIdentifier` = `com.naada.recorder`, version `1.0.0` |
| Bundle du dépôt | même lecture | `CFBundleIdentifier` = `com.naada.recorder` |
| Identité de signature | `codesign -dv --verbose=4` sur les deux bundles | `Authority=Developer ID Application: Jonathan Bahu (BG55CF653X)`, `TeamIdentifier=BG55CF653X`, `flags=0x10000(runtime)`, `Timestamp=12 Nov 2026 at 23:07:00`, `CDHash=a14d06237adc0ae70ff4be338b2f01a5f1c3b670` |
| Exigence désignée | `codesign -d -r-` sur les deux bundles | identifiant + équipe `BG55CF653X`, sans CDHash |
| Entitlements | `codesign -d --entitlements :-` | sortie stdout vide (0 octet) : aucune entitlement |
| Validité | `codesign --verify --strict` | exit 0 sur les deux bundles |
| Égalité des bundles | `diff -qr`, `cmp`, SHA-256 | aucune différence ; binaires identiques, SHA-256 `cab42db1…`, 1 249 008 octets |
| Gatekeeper | `spctl --assess --verbose=4 /Applications/Naada.app` | `rejected`, `source=Unnotarized Developer ID`, exit 3 ; même résultat sur le bundle du dépôt |
| Processus | `ps -p 21812 -o pid=,lstart=,command=` ; `lsof -p 21812 -a -d txt` | pid 21812, démarré `Thu Nov 12 23:21:19 2026`, chemin réel `/Applications/Naada.app/Contents/MacOS/Naada` ; un seul processus Naada |
| Ancien build installé | ce document, vague `7f50042` | CDHash `988b6333…` — différent du build courant |
| Bundle du dépôt avant ce lot | ce document, lot 3 | ad hoc `069b49c1…` ; il est maintenant identique au bundle installé |

### Journal TCC des trois dernières heures

Commande : `log show --last 3h --style compact --predicate 'subsystem == "com.apple.TCC" AND eventMessage CONTAINS[c] "naada"'`
— exit 0, 396 lignes. Le journal mêle des harnais de test, d'autres services et
des demandes antérieures à 23:21 ; seules les lignes du build installé sont
retenues ici.

À partir de 23:21:49, `tccd` journalise pour le processus 21812 (chemin
`/Applications/Naada.app`) :

- huit fois `Failed to match existing code requirement for subject
  com.naada.recorder and service kTCCServiceScreenCapture` ; le bloc imprime
  `cdhash H"4af24d79022ba95fbfdc3dfbd888d37e17ac8a65"` (CDHash du bundle isolé
  historique de la passe UI) et l'exigence Developer ID stable, mais la
  correspondance échoue ;
- deux fois `Notifying for access kTCCServiceScreenCapture ... responsiblePath:
  /Applications/Naada.app` (23:23:42 et 23:23:52) : une nouvelle invite est
  notifiée ;
- aucune ligne `AUTHREQ_RESULT` (grant/deny) dans les 396 lignes collectées ;
- deux événements `type=Modify` pour ScreenCapture à 23:23:46 et 23:23:48, sans
  corps exploitable ; leur origine n'est pas déterminée et ils ne sont pas
  suivis d'une correspondance réussie.

Le CDHash `988b6333…` de l'ancien build installé n'apparaît pas dans ces lignes ;
celui de l'exigence existante imprimée est `4af24d79…`. Le journal ne dit pas
quelle action a déclenché la demande, ni si l'invite a été affichée, acceptée ou
refusée. Aucun résultat d'autorisation n'y est lisible.

### Conclusion

**Verdict** : identité de signature valide et stable ; identité TCC **différente**
de l'autorisation enregistrée ; consentement **non prouvé**.

- **Identité de signature** : Developer ID `BG55CF653X`, runtime durci,
  horodatage, exigence sans CDHash, aucune entitlement ;
  `codesign --verify --strict` OK. Les deux bundles sont identiques au bit près.
- **Identité TCC** : le journal imprime, sous l'échec de correspondance de
  l'exigence existante, `cdhash H"4af24d79…"` (ancien bundle isolé) et non le
  CDHash courant `a14d0623…` ; `tccd` notifie une nouvelle demande. Le build
  installé n'est donc pas reconnu comme déjà autorisé.
- **Consentement** : l'invite est notifiée mais aucun choix n'est journalisé,
  l'agent ne l'a pas observée et l'état de la case dans les Réglages n'a pas été
  lu. Une signature valide ne prouve pas le consentement.

L'attestation utilisateur du 2026-11-12 consignée plus haut (application cochée,
nouvelle demande, texte système évoquant un refus TCC, sans refus volontaire
attesté) porte sur l'état antérieur ; elle ne prouve pas le consentement du build
courant. `spctl` rejette le bundle non notarisé, ce qui est distinct du
consentement TCC. Aucun remède n'a été appliqué ni proposé dans cette section.

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
4. **Application installée** : `/Applications/Naada.app` tournait déjà pendant
   les mesures d'identité (pid 21812), sans lancement par l'agent ; Gatekeeper la
   rejette (non notarisée) ; son état repos n'est pas observé.
5. **Réponse à l'invite TCC** : les journaux `tccd` montrent l'échec de
   correspondance de l'exigence enregistrée et une nouvelle notification d'accès
   pour le build installé (section « Vérification d'identité TCC ») ; l'affichage
   de l'invite, le choix de la personne et l'état de la case dans les Réglages ne
   sont pas observés.
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
13. **Autorisation d'enregistrer l'audio du système** : le libellé de l'invite,
    un refus, une reprise après autorisation et la non-répétition ne sont pas
    observés.
14. **Capture par tap de processus** : aucun tap n'a été créé à l'exécution ; le
    contenu réellement capturé, le format des buffers, la continuité du son et
    l'arrêt de l'application source ne sont pas vérifiés.

## Commandes de vérification autorisées maintenant

```bash
cd /Volumes/NVME1To/Projets/naada
./scripts/test.sh
./scripts/check.sh
```

`scripts/check.sh` ne lance pas l'application, n'appelle pas ScreenCaptureKit
et n'ouvre aucun périphérique audio ; il échoue si un symbole ou une clé
d'enregistrement d'écran réapparaît.

Dernière exécution de la vague : **2026-11-12** sur `7f50042` —
`./scripts/check.sh` : compilation release OK, **27 tests, 0 échec**, artefacts
d'icône contrôlés, application installée signée Developer ID et rejetée par
Gatekeeper. Aucun lancement de l'application installée. La passe UI historique
ci-dessus a été faite sur un bundle isolé, pas sur ce build.

Exécution du **2026-11-13** (lot 1, état de travail non commité sur `0a1e9f5`) :
`./scripts/check.sh` exit 0, **61 tests, 0 échec**, chemin audio seul contrôlé,
signature Developer ID stable. Aucun lancement, aucune capture, aucune action
TCC. Voir la section datée en fin de document.

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
- Pas de tap Core Audio créé à l'exécution, pas de mute, pas de changement de
  volume ou de routage.
- Pas de son provoqué, coupé, muté ou rerouté.
- Pas de lecture du MP3, ni avec QuickTime, ni avec Musique, ni avec `afplay`.
- Pas de suppression ni de modification du fichier produit par Jonathan.
- Pas de lancement de l'application installée dans `/Applications`.
- Pas de notarisation ni de publication.
- Le bundle partagé `Naada.app` n'a pas été lancé ni supprimé.

## Vérification statique du chemin audio seul du 2026-11-13 (lot 1)

Mesures de l'agent : `./scripts/check.sh` reconstruit et signe le bundle du
dépôt, puis lit les sources, l'`Info.plist` et le binaire. Aucun lancement de
Naada, aucune création de tap, aucune capture, aucun son et aucune action TCC.
Les fichiers du lot ne sont pas commités. `/Applications/Naada.app` n'a reçu
aucune commande d'installation et n'a pas été modifiée par ce lot.

| Élément | Méthode | Résultat observé |
|---|---|---|
| Compilation et tests | `./scripts/check.sh` | exit 0 ; release compilée ; **61 tests, 0 échec** |
| Invariants du tap | 10 tests `ProcessTapConstraintsTests` | tap muet, muet à la première lecture, non privé, ciblage bundle ID, sortie par défaut, système entier, liste vide ou multiple : tous rejetés |
| Cycle de vie | 6 tests `CaptureLifecycleStateTests` | arrêt et échec ne redeviennent `idle` qu'après teardown ; cycles répétés démarrables, sans audio |
| Cible Core Audio | `grep` dans `AudioCaptureEngine.swift` | `kAudioHardwarePropertyTranslatePIDToProcessObject`, `AudioHardwareCreateProcessTap`, `kAudioAggregateDeviceTapListKey`, `kAudioSubTapUIDKey`, `kAudioTapPropertyFormat` présents ; `muteBehavior = .unmuted` présent |
| Absence d'écran | grep des symboles ScreenCaptureKit, SCStream, SCShareableContent et SCContentFilter dans `Sources` | aucun résultat ; `NSScreenCaptureUsageDescription` absent des sources et du bundle |
| Liaisons | `otool -L Naada.app/Contents/MacOS/Naada` | `CoreAudio.framework` présent ; `ScreenCaptureKit.framework` absent |
| Autorisation audio | `plutil -extract NSAudioCaptureUsageDescription raw -o - Naada.app/Contents/Info.plist` | clé présente ; texte « aucune image », « le son reste audible », « avant votre clic » |
| Version minimale | `plutil -extract LSMinimumSystemVersion raw -o - Naada.app/Contents/Info.plist` | `14.2` |
| Signature | `codesign --verify --strict Naada.app` | exit 0 |
| Identité | `codesign -dv --verbose=4 Naada.app` | `TeamIdentifier=BG55CF653X`, runtime durci, horodatage sécurisé |
| Exigence désignée | `codesign -d -r- Naada.app` | identifiant `com.naada.recorder` + équipe `BG55CF653X`, sans CDHash |
| Processus | `pgrep -x Naada` avant chaque build | aucun processus (exit 1) ; aucune application lancée par l'agent |

### Ce qui est prouvé, et ce qui ne l'est pas

Prouvé statiquement : le code ne dépend plus de ScreenCaptureKit, le tap vise un
unique objet processus, il est privé et non muet, l'agrégat est privé, aucune
sortie par défaut n'est définie, la clé d'autorisation est celle de l'audio du
système et le minimum est 14.2. La compilation, les tests et la signature
passent.

Non prouvé à cette date : le libellé et le comportement de l'invite TCC audio,
un refus puis une reprise, la non-répétition de l'invite, le contenu réellement
capturé, le format réel des buffers, la continuité du son pendant la capture,
l'arrêt de l'application source, l'exécution sur macOS 14.0–14.1 et tout appel
à `onUnexpectedStop`. Aucun de ces points n'a été simulé ni corrigé par ce lot.

La signature est vérifiée ; l'installation reste à la charge du lead après
intégration.
