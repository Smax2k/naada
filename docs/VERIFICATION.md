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

## Correctif du tap silencieux — constat humain et cause du 2026-11-13

### Constat humain

Jonathan a accordé l'autorisation audio seule, puis a lancé une vidéo. Naada n'a
rien enregistré : jauge vide, aucun son détecté, aucune capture effective. Le
bundle alors installé contenait bien le chemin tap
(`AudioHardwareCreateProcessTap` présent dans le binaire, aucun lien
`ScreenCaptureKit`) ; ce n'était donc pas l'ancienne version d'enregistrement
d'écran.

### Diagnostic statique : source multiprocessus, cause runtime non confirmée

La source mémorisée dans Naada était **Google Chrome**. Une lecture seule des
métadonnées HAL (`kAudioHardwarePropertyProcessObjectList`,
`kAudioProcessPropertyPID`, `kAudioProcessPropertyBundleID`,
`kAudioProcessPropertyIsRunningOutput`) et des lignes de commande des processus
montre que Chrome expose :

- son processus principal, celui que `NSWorkspace` fournit à Naada ;
- deux processus `Google Chrome Helper`, dont l'un est explicitement
  `--utility-sub-type=audio.mojom.AudioService`.

Le tap de Naada vise uniquement l'objet processus du PID principal, traduit par
`kAudioHardwarePropertyTranslatePIDToProcessObject`. L'existence du service audio
séparé constitue une explication plausible de l'échec avec Chrome : le PID
principal peut ne pas émettre le son de la vidéo. Ces observations au repos ne
prouvent toutefois ni le producteur exact pendant l'essai humain, ni la cause
unique de l'absence de buffers. Un refus TCC et un défaut du pipeline ne sont pas
écartés par ces seules métadonnées. Aucun correctif fonctionnel de Chrome n'est
revendiqué ici.

Aucun tap, aucun périphérique, aucune capture, aucun son et aucune action TCC
n'ont été créés ou déclenchés pour établir ce constat. Le HAL ne permet pas de
prouver au repos lequel des deux helpers produit le son à un instant donné ;
seule la ligne de commande nomme le service audio.

### Corrections apportées

1. **Agrégat conforme au contrat du SDK.** `private`, `stacked` et
   `tapautostart` sont désormais des `NSNumber` entiers, jamais des `Bool`
   bridgés en `CFBoolean` que `CFNumberGetValue` refuse. La compensation de
   dérive du sous-tap est un entier. `tapautostart` reste à 0 : le démarrage ne
   doit jamais attendre le premier son. Le plan pur est dans
   `Sources/NaadaCore/TapAggregateComposition.swift`, et ses clés littérales
   sont confrontées aux constantes Core Audio par les tests.
2. **Format effectif de l'agrégat.** Le moteur lit le format d'entrée de
   l'agrégat après sa création, avec une attente bornée d'une seconde et un
   repli sur le format du tap. La conversion utilise ce format, pas une
   supposition. `AudioBufferLayout` vérifie la disposition réelle des buffers
   (entrelacé ou une voie par buffer) et le nombre de frames ; une incohérence
   lève une erreur visible au lieu de produire du silence.
3. **Réception réelle, pas seulement démarrage.** L'automate
   `CaptureLifecycleState` distingue désormais `waitingForAudio` et
   `receiving`. Un buffer non vide, même de silence numérique, établit la
   réception ; un buffer de silence n'est pas une absence de source. L'arrêt
   reste possible pendant l'attente. Un jeton de capture empêche un premier
   buffer retardé d'un cycle précédent de faire passer le cycle suivant en
   réception.
4. **Interface fidèle et message actionnable.** Tant qu'aucun buffer n'est
   arrivé, la phase affichée reste « Préparation » et la jauge ne s'anime pas.
   Après huit secondes sans buffer, un message explique que le processus choisi
   ne produit pas de son et qu'un navigateur peut jouer son audio dans un
   helper séparé ; la capture n'est pas arrêtée automatiquement et aucun repli
   global ou helper n'est tenté. Aucun texte français n'est codé dans les
   sources : les messages sont dans les tables `en` et `fr`.
5. **Garde-fous statiques.** `scripts/check.sh` refuse un booléen pour les clés
   numériques de l'agrégat, `tapautostart` actif, un agrégat public ou empilé,
   et vérifie la présence du format d'entrée de l'agrégat, de la disposition des
   buffers et des états d'attente/réception.

### Preuves de ce lot

| Élément | Méthode | Résultat observé |
|---|---|---|
| Compilation et tests | `./scripts/check.sh` | exit 0 ; release compilée ; **81 tests, 0 échec** |
| Agrégat CFNumber | 6 tests `TapAggregateCompositionTests` | `private`, `stacked`, `tapautostart` et dérive sont des `CFNumber` entiers, jamais des `CFBoolean` ; un seul tap ; clés égales aux constantes du SDK |
| Buffers | 10 tests `AudioBufferLayoutTests` | entrelacé, non entrelacé, tailles inégales, buffer vide, silence d'une frame, canaux incohérents, format invalide |
| Cycle de vie | 10 tests `CaptureLifecycleStateTests` | attente, réception au premier buffer, buffer pendant `.starting`, arrêt en attente, aucun report entre cycles |
| Signature | `codesign --verify --strict Naada.app` | exit 0 ; équipe `BG55CF653X`, runtime durci, horodatage sécurisé |
| Processus | `pgrep -x Naada` avant chaque build | aucun processus (exit 1) |
| Application installée | `/Applications/Naada.app` | non modifiée par ce lot ; installation à la charge du lead |

### Non observé / limites

- Aucun lancement de Naada, aucune création de tap, aucun périphérique, aucune
  capture, aucun son et aucune action TCC n'ont été effectués par l'agent. Le
  contenu réellement capturé, le format réel des buffers, la jauge vivante et
  la continuité du son restent à vérifier par un essai humain.
- Avec la règle « un seul PID choisi, aucun repli helper », Chrome ne peut pas
  être enregistré en sélectionnant l'application : son audio appartient au
  service audio séparé. Le message des huit secondes doit le dire, mais ce
  comportement n'a pas été observé en exécution.
- Le HAL ne prouve pas au repos quel processus produit le son ; le diagnostic ne
  peut donc pas nommer le helper avec certitude avant la lecture.
- Les chemins macOS 14.0–14.1 et un refus TCC puis une reprise ne sont pas
  exercés.

### Essai humain proposé (non exécuté par l'agent)

1. Ouvrir Naada et choisir une application native dont le processus principal
   joue le son (par exemple QuickTime Player, VLC ou Musique).
2. Démarrer l'enregistrement, puis lancer la lecture. Attendre que la phase
   passe de « Préparation » à « Enregistrement » et que la jauge bouge.
3. Arrêter : le MP3 doit être audible.
4. Recommencer avec Chrome. Après huit secondes sans son, le message doit
   expliquer que le processus choisi n'envoie pas d'audio ; le son de Chrome doit
   rester audible et aucun repli global ou helper ne doit démarrer.

## Capture Chrome par descendants audio — 13 novembre 2026 (lot bloqué, non construit)

### État du lot

- `/Applications/Naada.app` pid 5574 est resté actif pendant tout le lot.
  Aucun `scripts/build.sh`, `scripts/check.sh`, tap, capture, son, invite
  macOS, TCC, installation ou commit n'a été exécuté.
- `./scripts/test.sh` (pur) : **106 tests, 0 échec** (81 avant le lot, 25
  ajoutés : 13 plan, 6 sélection traduction/tapés, 6 contraintes). SwiftPM
  compile aussi la cible app dans `.build`, sans produire ni signer de bundle
  `.app` ; aucun `build.sh` ni remplacement n'a été lancé.
- Typecheck des sources de l'application contre le module `NaadaCore` déjà
  construit par les tests : exit 0. Ce n'est ni un link, ni une signature.
- `zsh -n scripts/check.sh` : exit 0. Les nouveaux garde-fous statiques et la
  parité des tables `en`/`fr` (103 clés chacune) ont été vérifiés à la main ;
  `scripts/check.sh` complet n'a pas été lancé car il construit le bundle.
- `git diff --check` : exit 0.

### Preuve lecture seule du plan

- Table `ps` du 13 novembre 2026 03:09 UTC, racine Chrome 721.
- Plan : `selected=721,1626`, helper unique 1626
  (`audio.mojom.AudioService`, `--service-sandbox-type=audio`, ppid 721).
- Traduction HAL lecture seule : 721 → objet 230, 1626 → objet 228 ; la
  racine est donc traduite, le helper aussi. Le diagnostic de la sonde
  distingue malgré tout `requestedRootPID`, `rootIsTranslated`, `tappedPIDs`
  et `untranslatedPIDs` (tests purs).
- Rejetés : 951 GPU, 952 réseau, 1080/1082/… renderers, 1627
  `video_capture`, 942 crashpad (ppid 1, hors arbre), 1026 stockage, 1097
  gestionnaire de mots de passe, processus `defunct`.
- Journal : `.orchestrator/chrome-tap-pids.txt`.

### Blocages précis

1. **Naada pid 5574 active** : la consigne interdit `build.sh`, `check.sh`,
   tap et installation tant qu'elle tourne. Aucun bundle n'a été construit,
   signé ni installé.
2. **Chrome ne produit aucun son à cet instant** :
   `kAudioProcessPropertyIsRunningOutput` vaut `false` pour 721 (objet 230) et
   1626 (objet 228), relevé en lecture seule. Jouer un son est interdit ;
   sans signal existant, aucune preuve RMS ou MP3 n'est possible.
3. **Conséquence** : aucun tap réel, aucune jauge vivante, aucun MP3, aucune
   comparaison de sortie audio, aucune installation. Ces points restent non
   observés et ne sont pas validés.

### À faire quand les blocages sont levés

1. Arrêter Naada (action humaine), vérifier que `pgrep -x Naada` est vide.
2. Construire et signer avec `./scripts/build.sh`, comparer le bundle construit
   au dépôt. **Ne pas installer encore.**
3. Faire jouer un son par Chrome (action humaine), puis lancer la preuve
   depuis le bundle construit seulement :
   `Naada.app/Contents/MacOS/Naada --capture-probe 721 .orchestrator 10`.
   Le dossier `.orchestrator` reçoit `chrome-capture-proof.json` et le MP3 ;
   il ne doit jamais être le dossier d'enregistrements de la personne.
4. Exiger `callbackRMSMax > 0.02`, `mp3RMS > 0.02`,
   `mp3SampleRate == 48000`, `mp3Channels == 2` et
   `defaultOutputUnchanged == true`. Si une invite TCC ou Gatekeeper bloque,
   arrêter et signaler : ne pas contourner.
5. Installer `/Applications/Naada.app` **seulement après** cette preuve, si le
   bundle construit est identique et si Naada est toujours arrêtée.

## Preuve autonome réelle — 13 novembre 2026 (bloquée avant le premier buffer)

### Objet et état

Objectif : prouver sans interface, avec une source synthétique isolée, que le
moteur de Naada reçoit réellement de l'audio (RMS callback), l'encode en MP3
48 kHz / 2 canaux et le décode (RMS MP3), sans son audible et sans modifier la
sortie système. Le lot s'arrête **bloqué** : aucun buffer n'a été reçu, aucun
`chrome-capture-proof.json` n'a été écrit, aucun RMS réel n'existe. Aucune
validation n'est revendiquée.

- Dépôt : `cbd127fada2776624ff787bc23a0b8891f61ed88`, arbre propre.
- Machine : macOS 27.2.1 (26B131), Apple Silicon.
- Construction : `./scripts/build.sh`, exit 0.
- Bundle construit : `CDHash=86dbed6d46dc99bde27671472c7bb0beb063b996`,
  `TeamIdentifier=BG55CF653X`, runtime durci, horodatage sécurisé,
  `codesign --verify --strict` exit 0, exigence stable
  `identifier "com.naada.recorder" ... certificate leaf[subject.OU] = BG55CF653X`
  sans CDHash. `spctl -a -vv` : refusé « Unnotarized Developer ID » (attendu,
  aucun contournement).
- Installation : `/Applications/Naada.app` remplacé par ce bundle après
  vérification `pgrep -x Naada` vide. `diff -qr` entre le bundle construit et
  l'installé : aucun écart ; SHA-256 du binaire
  `725abd985142353df84f790af23a67a84e62e15b3c3f659b4da718ae6a7dfcd1` identique ;
  `codesign --verify --strict` exit 0 sur les deux ; même CDHash et même
  exigence. Aucun lancement GUI volontaire ; l'incident involontaire de
  l'ancien bundle est consigné en conclusion ; `pgrep -x Naada` vide après.

### Source synthétique et non-audibilité

- Sinus 440 Hz, 48 kHz, 2 canaux, amplitude 0,5 (RMS généré
  `0,35355339059326846`), produit par un processus CLI isolé.
- Sortie dirigée vers **BlackHole 2ch** (`BlackHole2ch_UID`), périphérique
  virtuel sans haut-parleur ; gain numérique testé à 0 puis 1. Aucun son
  audible, aucun routage ni volume système modifié.
- Sortie par défaut avant/après : « Écouteurs externes »
  (`BuiltInHeadphoneOutputDevice`), volume `0,5625`, mute `0` ; `osascript`
  « output volume:56, output muted:false » inchangé. BlackHole : volume `1,0`,
  mute `0`, inchangé. Aucun processus du HAL avec `runningInput=1` ; aucun
  moniteur BlackHole (Loopback, Audio Hijack, OBS, SoundSource) actif.
- Lecteur BlackHole indépendant pendant la lecture : format 48 000 Hz /
  2 canaux / 32 bits flottants, **RMS max 0,35912928, 286 callbacks**. La
  source produit donc réellement l'audio dans le puits virtuel ; ce n'est ni
  du silence ni une source absente. Ce lecteur ne prouve pas que le tap de
  processus reçoit ce signal.

### Sonde réelle et blocage

Sonde exécutée sans `open`, exactement
`Naada.app/Contents/MacOS/Naada --capture-probe <pid source> <dossier> 10`.
Tentatives : source gain 0 et gain 1 sur BlackHole ; source gain 0 sur la
sortie par défaut (silencieuse). Toutes se bloquent **avant le premier
buffer** : aucun `NAADA_CAPTURE_PROBE` sur stdout, aucun
`chrome-capture-proof.json`, MP3 vide (0 octet) ou absent.

Pile relevée par `sample` sur le processus de la sonde (processus propre
uniquement) :

```
AudioCaptureEngine.createResources  AudioCaptureEngine.swift:383
  AudioDeviceCreateIOProcIDWithBlock
    HAL_HardwarePlugIn_DeviceCreateIOProcIDWithBlock
      HALC_ShellDevice::CreateIOProcIDWithBlock
        HALC_ProxyIOContext::_TellServerAboutStreamUsage
          HALC_ProxyObject::SetPropertyData
            mach_msg2_trap
```

L'attente est donc dans le HAL, à la création de l'IOProc de l'agrégat, pas
dans la source ni dans le décodage MP3. Cette pile établit **où** l'attente se
produit ; elle ne démontre pas **pourquoi** (permission, comportement HAL ou
autre cause).

### Reproduction minimale (hors code Naada)

Un programme de tap minimal dans `.orchestrator/` (aucune modification du
code de l'application) a reproduit le blocage pendant le relevé. Ses sources,
binaires et journaux ont été supprimés après relevé : la reproduction exacte
de cette trace n'est plus possible en l'état ; le tableau ci-dessous est un
relevé d'observations, pas un banc d'essai conservé :

| Composition de l'agrégat | IOProc | `AudioDeviceStart` | Callbacks / RMS |
|---|---|---|---|
| privé + `taps: [{uid, drift:1}]` (forme du moteur, documentée SDK) | **bloqué** | — | — |
| privé + `taps: [{uid}]`, `drift:0`, `stacked:1`, `tapautostart:1`, `subdevices:[]`, `clock:<uid>` | **bloqué** | — | — |
| privé + `taps: [uid]` (chaînes) | OK | `1852797029` (`'nope'`) | 0 / 0 |
| public + `taps: [{uid, drift:1}]`, sans horloge | OK | `1852797029` (`'nope'`) | 0 / 0 |
| public + dictionnaire + horloge (sortie par défaut ou BlackHole) | OK | `0` | **0 callback / RMS 0** |
| public + tap lié à BlackHole (`andDeviceUID`) + horloge | OK | `0` | **0 callback / RMS 0** |
| tap public (toutes agrégations testées) | **bloqué** | — | — |

La forme « chaînes » évite le blocage mais ne délivre aucun callback : ce
n'est pas un correctif démontré. Aucune variante testée ne délivre de
callback. Le lecteur BlackHole prouve que la source produit de l'audio dans
BlackHole ; il ne prouve pas que le tap de processus reçoit ce signal. Ces
observations ne permettent donc pas de conclure à une cause liée à la version
de macOS ni à un refus TCC : la cause racine de l'attente HAL reste
**indéterminée**.

### TCC / permissions

- Aucun dialogue TCC visible pendant les essais : la seule fenêtre
  `UserNotificationCenter` relevée mesure 6×4 px, alpha 0 (pas un prompt).
- `log show` unifié inaccessible depuis cette session (une seule ligne) ;
  la base TCC utilisateur est illisible sans Full Disk Access ; la base TCC
  système ne contient que l'ancienne autorisation
  `kTCCServiceScreenCapture|com.naada.recorder|0|2`, pas d'entrée audio.
- L'état exact de l'autorisation d'enregistrement audio n'est donc pas
  prouvable ici ; aucune conclusion de refus TCC n'est tirée. Aucun clic,
  aucune réinitialisation TCC, aucun contournement.

### Conclusion et prochaine action

La preuve demandée **n'est pas atteinte** : aucun RMS callback, aucun RMS MP3,
aucune jauge réelle, aucun MP3 décodé. Ne pas présenter ce lot comme validé.
Le blocage a été observé de façon répétée et survient avant le premier buffer.
L'ancien bundle installé — antérieur à la sonde — a lancé l'interface lors
d'une exécution directe, arrêtée immédiatement ; aucun enregistrement, aucun
clic, aucun son.

**Cause racine indéterminée ; état de la permission non prouvé.** Prochaine
investigation ciblée, avant tout changement de code ou de composition :

1. Établir si une demande de permission audio est visible ou requise pour la
   sonde, et laquelle, sans la contourner ni la réaccorder à l'aveugle.
2. Vérifier la composition de l'agrégat et la création de l'IOProc avec une
   trace conservée, pour distinguer une attente HAL d'un refus de permission.

Ne pas demander génériquement de réaccorder la permission, ne pas modifier
`TapAggregateComposition` ni le code avant cette investigation. Ne pas relever
le volume, le gain ou le routage.

Les journaux temporaires de ce lot (`.orchestrator/autonomous-capture-20261113`)
sont supprimés après relevé ; les métriques et la pile ci-dessus en sont la
trace conservée. La reproduction exacte du diagnostic minimal n'est donc plus
possible ; les variantes du tableau sont des observations, pas un banc d'essai
conservé.

## Preuve réelle de capture audio — 13 novembre 2026 (PASS)

### Résultat

La preuve demandée est atteinte sur l'état courant : la sonde de Naada reçoit
réellement le signal d'une source synthétique isolée, le callback produit un
RMS mesurable, le MP3 est encodé puis décodé en 48 kHz / 2 canaux, et la sortie
par défaut n'est pas modifiée. Aucune interface n'a été lancée, aucun son n'a
été émis, aucun réglage de volume ou de routage n'a été écrit.

- Dépôt : `63fdc28`, arbre initial propre.
- Machine : macOS 27.2.1 (26B131), Apple Silicon.
- Sonde exécutée directement depuis le bundle, jamais avec `open` :
  `Naada.app/Contents/MacOS/Naada --capture-probe <pid source> <dossier> 10`.
- Source : sinus 440 Hz, 48 kHz, 2 canaux, amplitude 0,5 (RMS généré
  `0,35355339059327373`), dirigée vers **BlackHole 2ch** (`BlackHole2ch_UID`)
  uniquement. Le harnais refuse de démarrer si BlackHole est la sortie par
  défaut ; il ne vise jamais les haut-parleurs ni les écouteurs.
- Harnais conservé et reproductible : `scripts/audio-capture-smoke.swift`
  (mode source, et mode `--readback` pour prouver le signal dans le puits
  virtuel). Compilation :
  `xcrun swiftc -O scripts/audio-capture-smoke.swift -o .orchestrator/.../audio-capture-smoke`.
- Quatre exécutions réelles : bundle existant, relevé d'identité, puis deux
  bundles reconstruits. Les quatre passent ; les métriques du bundle final
  installé sont ci-dessous.

### Métriques de la sonde finale

Preuve JSON :
`.orchestrator/naada-capture-proof-20261113/attempt4-final2/chrome-capture-proof.json`.

| Mesure | Valeur | Seuil |
|---|---|---|
| `callbackRMSMax` | `0,35905939340591431` | `> 0,02` |
| `mp3RMS` | `0,39729663729667664` | `> 0,02` |
| `mp3Frames` | `497664` | `> 0` |
| `mp3SampleRate` | `48000` | `== 48000` |
| `mp3Channels` | `2` | `== 2` |
| `bytes` | `248832` | — |
| `defaultOutputUnchanged` | `true` | `true` |
| code de sortie | `0` | `0` |

Exécutions précédentes, même protocole :

| Exécution | `callbackRMSMax` | `mp3RMS` | `mp3Frames` | `bytes` |
|---|---|---|---|---|
| bundle existant `86dbed6d` | `0,35907784104347229` | `0,39721763134002686` | `502272` | `251136` |
| relevé d'identité | `0,35904902219772339` | `0,39688235521316528` | `249984` | `124992` |
| bundle final1 `428103be` | `0,35913783311843872` | `0,39727157354354858` | `512640` | `256320` |
| bundle final2 `f3deaf26` | `0,35905939340591431` | `0,39729663729667664` | `497664` | `248832` |

La source a produit `963584` frames en 20 s (auto-test) et `1443328` frames en
30 s (exécution finale). Le lecteur BlackHole indépendant, en mode `--readback`,
mesure `maxRMS 0,35913050174713135`, `469` callbacks, `240128` frames,
`0` échec : le signal existe réellement dans le puits virtuel. Ce lecteur ne
prouve pas que le tap de processus le reçoit ; c'est la sonde qui le prouve.

### Non-audibilité et système inchangé

- BlackHole 2ch : volume `1`, mute `0`, `runningSomewhere` `0` avant, `1`
  pendant la source, `0` après.
- Sortie par défaut : « Écouteurs externes »
  (`BuiltInHeadphoneOutputDevice`), volume `0,5625`, mute `0` avant, pendant et
  après. `osascript` : `output volume:56, output muted:false`, identique avant
  et après. Relevé final :
  `.orchestrator/naada-capture-proof-20261113/system-final.json`.
- Aucun moniteur de BlackHole actif (Loopback, Audio Hijack, SoundSource, OBS) ;
  aucun processus ne lit BlackHole en dehors du `--readback` explicite.
- Le helper audio de Chrome (`pid 1626`, `audio.mojom.AudioService`) a lu une
  entrée par intermittence pendant le lot (micro Shure MV7+), sans rapport avec
  BlackHole ; il n'a pas été tapé et n'a pas été interrompu. Son état a fluctué
  seul (`runningInput` `1` ou `0` selon les relevés), sans action de Naada.
- Aucune lecture audible du MP3 : le fichier a été décodé par `AVAudioFile` et
  mesuré, jamais lu par un périphérique de sortie.

### Identité effective et attribution de permission

Arbre relevé pendant une sonde courte (seuls les PID pertinents) :

```
  PID  PPID COMM
 3268  3219 .../opencode/cli-darwin-arm64/bin/opencode serve --hostname 127.0.0.1 --port 57905
60710  3268 /bin/zsh
60719 60710 Naada.app/Contents/MacOS/Naada --capture-probe 60714 ... 5
```

La source synthétique était le PID `60714`, processus distinct.

- Bundle Naada : `Identifier=com.naada.recorder`,
  `TeamIdentifier=BG55CF653X`, runtime durci, horodatage sécurisé, exigence
  désignée stable `identifier "com.naada.recorder" ... certificate
  leaf[subject.OU] = BG55CF653X`, sans CDHash.
- Processus responsable Node/OpenCode : `Identifier=opencode`,
  `TeamIdentifier=5NZ4Q7NXJ4`, signé Developer ID Anomaly Innovations, Inc.
- Journal TCC (`tccd`, 13 novembre 2026 04:34:18) : la demande
  `kTCCServiceAudioCapture` a pour sujet
  `/opt/homebrew/Cellar/node/26.5.0/bin/node`
  (`AUTHREQ_SUBJECT`), avec `authValue=2`, `authReason=2`, et une attribution
  `responsible={node...}` / `accessing={com.naada.recorder...}`. Une préflight
  `kTCCServiceScreenCapture` est également attribuée à Node
  (`authValue=2`, `authReason=4`) ; elle vient du contrôle du HAL, pas d'un
  chemin d'enregistrement d'écran dans Naada.
- La même attribution est relevée pour l'exécution final2 (PID `64025`) :
  `tcc-final2.log`, `kTCCServiceAudioCapture`, sujet
  `/opt/homebrew/Cellar/node/26.5.0/bin/node`, `authValue=2`, `authReason=2`,
  `accessing={com.naada.recorder...}`.
- **Conséquence à ne pas déformer** : l'accord observé est porté par le
  processus responsable Node. Il ne prouve pas que l'identité de bundle
  `com.naada.recorder` possède sa propre autorisation audio. La base TCC
  utilisateur n'est pas lisible depuis cette session (Full Disk Access absent) ;
  aucune entrée propre à Naada n'est prouvée. La sonde réussit sous
  l'attribution Node, pas sous une autorisation Naada démontrée.

### Signature et installation

- Bundle final construit par `./scripts/check.sh` :
  `CDHash=f3deaf26198cacc40980e449e0a2d8af467d8909`,
  horodatage `13 Nov 2026 at 04:41:00`, équipe `BG55CF653X`, runtime durci,
  exigence stable sans CDHash.
- `codesign --verify --strict` : exit `0` sur le bundle construit et sur
  `/Applications/Naada.app`.
- Installation après PASS, Naada arrêtée (`pgrep -x Naada` vide avant et après) :
  `/Applications/Naada.app` remplacé par le bundle construit.
- `diff -qr Naada.app /Applications/Naada.app` : aucun écart. Même CDHash
  `f3deaf26…`, même exigence, même SHA-256 du binaire
  `1a34fb5c80865fab835ad1b997b14877df77546d964ff6d7254d82f624a3111f`.
  Aucune quarantaine ; `spctl -a -vv` répond « rejected / Unnotarized Developer
  ID », attendu sans notarisation et sans contournement.
- `./scripts/test.sh` : **106 tests, 0 échec**. `./scripts/check.sh` : exit `0`
  (tests, reconstruction signée, garde-fous statiques, signature, icône,
  liaisons système). Journaux : `.orchestrator/naada-capture-proof-20261113/test.log`
  et `check.log`.
- `scripts/check.sh` a été corrigé d'un faux positif : le motif interdisait
  globalement `kAudioHardwarePropertyDefaultOutputDevice`, alors que la sonde ne
  fait que **lire** la sortie par défaut pour comparer avant/après. Le motif
  reste interdit partout ; seule la ligne de `CaptureProbe.swift` est exclue,
  et la sonde ne doit jamais écrire (`AudioObjectSetPropertyData` contrôlé).

### Limites et état laissé

- La preuve porte sur une source synthétique et sur une sonde lancée depuis
  l'arbre `node` de l'agent. Elle ne prouve pas le parcours d'une Naada lancée
  normalement par la personne, ni une autorisation TCC propre à Naada.
- Aucun lancement GUI, aucune capture d'écran, aucun clic sur une invite, aucun
  changement de volume, de mute, de sortie par défaut ou de routage.
- Aucun commit, push, publication ni notarisation.
- Quatre taps privés nommés « Naada minimal diagnostic tap » préexistent à ce
  lot (diagnostic minimal d'un lot antérieur). Ils n'ont pas été créés ici et
  n'ont pas été détruits ; aucun agrégat ni périphérique « Naada » ne subsiste.
  Les taps créés par cette sonde ont été détruits par le moteur à l'arrêt.

## Tests, garde-fous et installation — 13 novembre 2026

### Résultat

Les tests unitaires et les contrôles statiques passent sur l'état courant, et le
bundle signé construit par `./scripts/check.sh` est installé dans
`/Applications`, identique au bundle du dépôt. **Aucune capture micro réelle n'a
été faite** : aucune entrée audio n'a été ouverte, aucune invite TCC n'a été
affichée ni acceptée à la place de Jonathan, et le mélange application + micro
n'a jamais été produit, décodé ni écouté. Les tests ci-dessous ne remplacent pas
cette preuve.

- Dépôt : `32166ff`, arbre initial propre hors `design-work/` non suivi
  préexistant.
- Machine : macOS 27.2.1 (26B131), Apple Silicon.
- Naada arrêtée avant, pendant et après : `pgrep -x Naada` sans sortie, exit
  `1`.
- Aucun lancement de l'application, aucun son émis, aucun clic sur une invite,
  aucun appel à `tccutil`, aucune lecture de `TCC.db`, aucune notarisation.

### Tests et garde-fous

`./scripts/check.sh` : exit `0`. Il enchaîne `./scripts/test.sh`, la
reconstruction release signée et les contrôles statiques ci-dessous.

- **137 tests unitaires, 0 échec** (14 suites) : plan des descendants audio
  (19), disposition des tampons (10), sélection des sources (13), contraintes
  du tap (16), présets (16), réglages de session (13), noms de fichier (11),
  cycle de capture (10), mélange PCM (7), composition d'agrégat (6), session
  (5), niveau (4), horloge (4), écriture MP3 (3).
- Ces tests sont **purs** : ils n'ouvrent ni périphérique audio, ni tap, ni
  entrée micro, et ne demandent aucune autorisation. Ils valident des types et
  des transitions, pas le chemin Core Audio réel.
- Garde-fous statiques vérifiés : absence de tout symbole ou clé
  ScreenCaptureKit ; tap privé et non muet, sans changement de sortie par
  défaut, sans ciblage par bundle entier ni tap global ; clés d'agrégat en
  CFNumber entiers ; symboles requis du tap de processus ; `requestAccess`
  confiné à `AudioCaptureEngine.swift` ; catalogue micro sans
  `AVCaptureDevice` ni `requestAccess` ; parité EN/FR des tables et des
  descriptions ; `LSMinimumSystemVersion` 14.2 ; icône clair/sombre ; absence
  de dylib externe et de ScreenCaptureKit dans les liaisons, CoreAudio lié.

| Commande | Résultat |
|---|---|
| `pgrep -x Naada` (avant `check.sh`, avant et après installation) | aucune sortie, exit `1` |
| `./scripts/check.sh` | exit `0` ; 137 tests, 0 échec ; release signée ; contrôles statiques OK |
| `codesign --verify --strict --verbose=2 Naada.app` | exit `0` |
| `codesign --verify --strict --verbose=2 /Applications/Naada.app` | exit `0` |
| `codesign -d --entitlements -` (les deux bundles) | `com.apple.security.device.audio-input` = `true` |
| `diff -qr /Applications/Naada.app Naada.app` | aucun écart, exit `0` |
| `shasum -a 256` du binaire (les deux bundles) | `634050e6…` identique |
| `spctl -a -vv /Applications/Naada.app` | `rejected` « Unnotarized Developer ID », exit `3`, attendu |

### Entitlement microphone

`packaging/Naada.entitlements` déclare `com.apple.security.device.audio-input`,
et `./scripts/build.sh` l'applique à la signature. Sous runtime durci, sans cet
entitlement, macOS ne présente pas la demande d'accès micro : l'appel
`AVCaptureDevice.requestAccess(for: .audio)` échouerait sans invite. Le bundle
construit et le bundle installé portent tous deux l'entitlement (`true`), et
`scripts/check.sh` échoue si la clé manque. L'entitlement rend la demande
possible ; il ne l'accorde pas. Aucune invite n'a été observée dans ce lot.

### État de /Applications

- Ancien bundle : CDHash `100f23a7…`, signé le 13 Nov 2026 à 05:40:49.
- Bundle construit par `./scripts/check.sh` :
  `CDHash=43490ddc1ac05becb56df1a14b264d34e9251a49`, horodatage
  `13 Nov 2026 at 05:44:18`, équipe `BG55CF653X`, runtime durci, exigence
  stable sans CDHash.
- `/Applications/Naada.app` remplacé par `ditto` après `pgrep -x Naada` vide.
  Même CDHash, même horodatage et même binaire
  (`634050e64854c48ef77ac922f67b109e16f22af09382f8caddb2be7993d5b7d9`) que le
  bundle du dépôt ; `diff -qr` sans écart ; `codesign --verify --strict` exit
  `0` des deux côtés. Aucune quarantaine. `spctl -a -vv` : refusé
  « Unnotarized Developer ID », attendu sans notarisation et sans
  contournement.

### Ce qui reste non prouvé

- **Capture micro réelle** : aucune entrée audio ouverte, aucun tampon micro
  observé, aucun MP3 issu d'un micro. Le chemin
  `AVCaptureDevice` → tampons → mélange n'est couvert par aucune exécution.
- **Mélange** : les trois modes (application seule, micro seul, les deux) sont
  couverts par des types purs et des tests unitaires, pas par une capture
  réelle ; un enregistrement application + micro n'a jamais été produit,
  décodé ni écouté.
- **TCC** : aucune invite affichée ni acceptée ; aucun accord propre à
  `com.naada.recorder` n'est prouvé. La preuve antérieure sur source synthétique
  était attribuée au processus `node` responsable, pas au bundle.
- **Alignement des flux** : le mélange additionne les tampons dans leur ordre
  d'arrivée ; aucun test ne prouve un alignement temporel entre le tap de
  l'application et l'entrée micro.
- **Débranchement du micro** : non observé ; le comportement en cours de capture
  (erreur, silence, reprise) n'est pas établi.
- **Parcours réel** : aucun lancement GUI, aucun clic sur **Enregistrer**,
  aucune vérification de la liste des micros ni du rendu de la fenêtre.
- Aucun commit, push, publication ni notarisation.

## Consolidation finale — 13 novembre 2026

Passe de consolidation après `71c12b7`. Objectif : ne laisser aucun changement
non commité et vérifier que l'application installée correspond au commit.

| Élément | Méthode | Résultat observé |
|---|---|---|
| Arbre de travail | `git status --short` avant la passe | seul `design-work/` non suivi ; conservé comme trace de la maquette validée et commité (`16eb0b9`), après vérification qu'il ne contient ni secret, ni jeton, ni donnée personnelle (briefs, images, manifeste, réponses de coût) |
| Naada arrêtée | `pgrep -fl Naada` avant chaque build et avant remplacement | aucune sortie |
| Build et tests | `./scripts/check.sh` sur `16eb0b9` | exit `0` ; release signée Developer ID, runtime durci, horodatage ; **137 tests, 0 échec** |
| Ancien bundle installé | `codesign -dv` puis comparaison des segments Mach-O et des ressources | CDHash `43490ddc…` ; `__TEXT` et `Assets.car` différents du build du commit : écart non explicable par la seule signature |
| Remplacement | `ditto` vers une copie neuve puis bascule | `/Applications/Naada.app` remplacé par le bundle construit depuis `16eb0b9` |
| Correspondance | `diff -qr Naada.app /Applications/Naada.app` | aucun écart : bundles identiques octet pour octet |
| Signature installée | `codesign --verify --strict --verbose=2` | exit `0`, valid on disk, satisfies its Designated Requirement |
| Identité | `codesign -dv --verbose=4` | Authority `Developer ID Application: Jonathan Bahu (BG55CF653X)`, Team `BG55CF653X`, `flags=0x10000(runtime)`, CDHash `9bdebe2b1ce97f09e32f69e788f29614db7414b2` |
| Entitlement | `codesign -d --entitlements :-` | `com.apple.security.device.audio-input` = `true`, identique au bundle construit |
| Gatekeeper | `spctl --assess --type execute --verbose=4` | `rejected`, `source=Unnotarized Developer ID`, exit `3` ; attendu sans notarisation, aucun contournement |
| Notarisation, publication | — | aucune |

Non observé après cette consolidation : le comportement de TCC pour le nouveau
CDHash `9bdebe2b…`, le lancement de l'application installée, la jauge en signal,
la continuité du son et la lecture audible du MP3. Aucun son, aucune capture et
aucune invite n'ont été déclenchés par cette passe.
