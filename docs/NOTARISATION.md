# Notarisation Developer ID — procédure et journal d'exécution

**Exécutée le 2026-11-13** : le `Naada.app` et le DMG de la version 1.0.0 sont
notarisés par Apple, agrafés et validés, et le ticket est présent dans les deux.
Le journal en fin de document donne les identifiants de soumission, les empreintes
et les contrôles. Le blocage Gatekeeper décrit auparavant dans le README ne
concerne plus la version publiée ; il reste vrai d'un bundle assemblé localement.

Les sections suivantes décrivent la procédure préparée le 2026-11-12. Leurs
mentions « non exécutée » et « INTERDITE sans consentement » sont conservées comme
historique de préparation ; le consentement écrit de Jonathan à l'envoi a été
donné le 2026-11-13.

## Périmètre

| Élément | Valeur |
|---|---|
| Produit | Naada, application macOS |
| Bundle | `com.naada.recorder` |
| Signature | `Developer ID Application: Jonathan Bahu (BG55CF653X)` |
| Équipe | `BG55CF653X` |
| Runtime | durci, `flags=0x10000(runtime)` |
| Horodatage | sécurisé (`--timestamp`) |
| Exigence désignée (extrait) | `identifier "com.naada.recorder" and certificate leaf[subject.OU] = "BG55CF653X"` |
| Base | lot3 accepté, commit `ac05ecc` |

L'exigence désignée est volontairement citée en **extrait** : elle omet
`anchor apple generic` et les contraintes de certificat Apple. Ce n'est pas la
sortie complète attendue de `codesign -d -r-`.

Le lot3 a vérifié `scripts/check.sh` (27 tests) et deux builds indépendants avec
une exigence identique, sans capture ni lancement ; `/Applications` et le bundle
partagé sont restés inchangés. La notarisation ne modifie ni cette signature ni
cette exigence.

Hors périmètre : App Store, TestFlight, distribution publique, création de clés,
acceptation d'accords, `notarytool`, `altool`, remplacement de
`/Applications/Naada.app`, lancement de l'application.

## Source de vérité

- `asc notarization --help` et chaque `asc notarization <subcommand> --help`,
  asc 6.2.0, lus le 2026-11-12.
- `asc search notarization` (10 résultats).
- `references/capacites.md` : le domaine `notarization` est rangé dans Signature ;
  l'aide réelle prime sur le tableau.
- `references/comptes.md` : une clé API d'**équipe** est nécessaire ; une clé
  individuelle ne couvre pas `notaryTool`.
- `references/recettes.md` : **aucune recette de notarisation**. Les commandes
  `asc` ci-dessous viennent uniquement de l'aide réelle, jamais d'une supposition ;
  les contrôles locaux (`codesign`, `ditto`, `spctl`) sont des outils macOS
  standard, pas des sous-commandes `asc`.

## Prérequis

| Prérequis | Détail |
|---|---|
| Profil `asc` | `ASC_PROFILE="<profil>"` sur chaque commande, profil de l'équipe `BG55CF653X` |
| Clé | clé API d'équipe `.p8`, hors dépôt, permissions `0600` |
| Outil | `asc` 6.2.0 (`asc version`) |
| Réseau | les sous-commandes `asc notarization` hors `--help` ; toute aide `asc … --help` est locale. `codesign --timestamp` (signature) contacte le service d'horodatage ; les vérifications `codesign -d`/`--verify` et `ditto` sont locales. |
| Consentement | explicite et écrit, avant `submit` et `staple` |

Ne jamais lire, afficher, copier ni committer le `.p8`, `~/.asc/config.json` ou
une session web. Ne pas changer le profil par défaut : passer `ASC_PROFILE` sur
la commande.

## Commandes — vue d'ensemble

| Sous-commande | Usage (aide asc 6.2.0) | Nature | Statut |
|---|---|---|---|
| `submit` | `asc notarization submit --file <path> [--wait] [--poll-interval 30s] [--timeout 1h] [--output json]` | envoi du fichier à Apple | exécutée le 2026-11-13 (zip du bundle, puis DMG) |
| `status` | `asc notarization status --id "SUBMISSION_ID"` | lecture | non exécutée |
| `log` | `asc notarization log --id "SUBMISSION_ID"` | lecture | non exécutée |
| `list` | `asc notarization list [--limit N]` | lecture | non exécutée |
| `staple` | `asc notarization staple --file <path> --confirm` | mutation locale + ticket | exécutée le 2026-11-13 (app et DMG) |
| `validate` | `asc notarization validate --file <path>` | lecture locale | exécutée le 2026-11-13 (app et DMG) |

`submit` accepte `.zip`, `.dmg` ou `.pkg`. `staple` et `validate` acceptent
`.app`, `.dmg` ou `.pkg`, jamais un `.zip` directement.

## 1. Vérifier l'état local (lecture seule)

```bash
asc version
ASC_PROFILE="<profil>" asc --read-only auth status --output json
ASC_PROFILE="<profil>" asc --read-only notarization list --limit 5
```

`--read-only` refuse toute requête mutante avant de l'envoyer (aide globale).
`auth status` ne valide le réseau qu'avec `--validate` ; ne pas l'ajouter sans
besoin.

## 2. Vérifier la signature (local, lecture seule)

```bash
codesign --verify --deep --strict --verbose=2 "Naada.app"
codesign -dvvv "Naada.app" 2>&1 | grep -E 'Identifier|TeamIdentifier|Runtime|Timestamp'
codesign -d -r- "Naada.app" 2>&1
```

Attendu : `Identifier=com.naada.recorder`, `TeamIdentifier=BG55CF653X`,
`flags=0x10000(runtime)`, `Timestamp=...`.

Pour l'exigence, `codesign -d -r-` affiche une ligne complète. **Extrait**
seulement, et non sortie complète attendue :
`designated => identifier "com.naada.recorder" and certificate leaf[subject.OU] = "BG55CF653X"`.
L'exigence complète inclut aussi `anchor apple generic` et les contraintes de
certificat Apple, omises ici. Ne pas valider une sortie qui s'arrêterait à cet
extrait.

Aucun de ces contrôles ne transmet de fichier.

## 3. Préparer l'archive (local, sans réseau)

```bash
ditto -c -k --keepParent "Naada.app" "Naada.zip"
```

`submit` n'accepte pas un `.app` nu : il faut un `.zip`, `.dmg` ou `.pkg`. Le zip
doit préserver le bundle signé. Un zip ne peut pas être agrafé : on agrafe le
`.app`, puis on recrée le zip.

## 4. Envoi

```bash
ASC_PROFILE="<profil>" asc notarization submit \
  --file ./Naada.zip \
  --wait --poll-interval 30s --timeout 1h \
  --output json
```

**Exécutée le 2026-11-13** avec le consentement écrit de Jonathan, profil
`jbahu` (équipe `BG55CF653X`), sur le zip du bundle puis sur le DMG.

- L'aide de `submit` ne montre ni `--dry-run` ni `--confirm` : la commande crée
  la soumission et téléverse le fichier dès son lancement. Il n'existe aucun mode
  « pour voir ».
- Le fichier est transmis à Apple (S3) ; ne pas lancer cette commande pour tester
  un profil, une clé ou un chemin.
- `--wait` est facultatif ; sans lui, conserver l'identifiant de soumission pour
  `status`.
- Les envois du 2026-11-13 ont été faits avec ce seul consentement, sur les
  deux fichiers décrits au journal.

Consentement requis : Jonathan doit confirmer explicitement, par écrit, la
transmission de **ce fichier précis** (chemin et empreinte SHA-256) avec le
profil `ASC_PROFILE` nommé. Un accord de publication, de commit ou d'installation
n'est pas un accord de notarisation.

## 5. Suivi — lecture seule

```bash
ASC_PROFILE="<profil>" asc notarization status --id "<SUBMISSION_ID>" --output json
ASC_PROFILE="<profil>" asc notarization log --id "<SUBMISSION_ID>" --output json
```

Statuts : `Accepted`, `In Progress`, `Invalid`, `Rejected`. Attendre `Accepted`
avant d'agrafer. Le log donne les motifs d'un refus.

## 6. Agrafage

```bash
ASC_PROFILE="<profil>" asc notarization staple --file "Naada.app" --confirm
```

**Exécutée le 2026-11-13** sur `Naada.app` puis sur `dist/Naada.dmg`.

- `--confirm` est obligatoire ; la commande modifie l'artefact en place et peut
  nécessiter le réseau pour récupérer le ticket.
- Agrafer le `.app` (ou le `.dmg`/`.pkg`), jamais le `.zip` ; recréer le zip
  ensuite.
- Ne pas agrafer `/Applications/Naada.app` : travailler sur une copie de
  distribution, puis installer selon la procédure d'installation.

## 7. Vérification après agrafage

```bash
ASC_PROFILE="<profil>" asc notarization validate --file "Naada.app" --output json
spctl -a -vvv -t execute "Naada.app"
```

`validate` ne mute jamais la cible ; il vérifie un ticket déjà agrafé et peut
nécessiter le réseau. `spctl` est le contrôle Gatekeeper local. Ces commandes
n'ont pas été exécutées ici.

## Ce qui n'est pas utilisé

- `xcrun notarytool submit`, `xcrun notarytool log`, `xcrun stapler staple`,
  `xcrun altool` : aucune recette dans `references/recettes.md` ; non exécutés et
  non documentés comme voie pour Naada.
- `asc notarization` est la voie documentée ; le domaine figure dans Signature du
  tableau `capacites.md`, mais les arguments viennent uniquement de l'aide réelle.
- Pas d'App Store, pas de TestFlight, pas de `asc publish`, pas de
  `asc review submit`.

## Feu vert avant toute commande INTERDITE

Sans ces points, s'arrêter :

1. Jonathan confirme par écrit la transmission de ce fichier précis à Apple.
2. Le profil `asc` et l'équipe `BG55CF653X` sont nommés.
3. La signature et l'exigence ont été relues (section 2).
4. L'archive et son empreinte SHA-256 sont notées.
5. La personne sait que le fichier part chez Apple et qu'un refus est possible.

## Journal des preuves (lecture seule)

| Vérification | Résultat |
|---|---|
| `asc version` | `6.2.0` |
| `asc notarization --help` | sous-commandes `submit`, `staple`, `validate`, `status`, `log`, `list` |
| `asc notarization submit --help` | `.zip`/`.dmg`/`.pkg`, SHA-256, upload S3, ni `--confirm` ni `--dry-run` |
| `asc notarization staple --help` | `--confirm` requis, zip non agrafable |
| `asc search notarization` | 10 résultats, mêmes sous-commandes |
| `git log -1 ac05ecc` | `Stabilise Naada Developer ID signature across builds` |

Les preuves d'exécution du 2026-11-13 sont dans le journal ci-dessous.

## Journal d'exécution — 2026-11-13

Consentement : Jonathan a autorisé explicitement l'envoi à Apple. Profil `asc` :
`jbahu` (clé d'équipe, identifiant `D27XSLV3NQ`), équipe `BG55CF653X`, `asc`
6.2.0. Aucun secret lu ni affiché, aucun fichier de credential modifié.

### Version publiée

Avant toute opération, le DMG de la release `v1.0.0` et le bundle du dépôt étaient
identiques : app extraite de `dist/Naada.dmg` identique à `Naada.app`
(`diff -rq` vide), CDHash `bbeb3ef3e516c0c25b3b1b19c485fa41835a6d2e`. Aucun code
n'a été reconstruit : la version notarisée est exactement celle publiée.

### 1. Bundle

| Étape | Commande | Résultat |
|---|---|---|
| Archive | `ditto -c -k --keepParent --sequesterRsrc Naada.app Naada.zip` | SHA-256 `191f1f78a81d36e554783a511667f84681730d741f396dfbbd59ea2367bb97cd` |
| Envoi | `asc notarization submit --file Naada.zip --wait` | `Accepted`, id `be39e34d-76db-4553-a3ec-bb8634357d78` |
| Agrafage | `asc notarization staple --file Naada.app --confirm` | `stapled: true`, `validated: true` |
| Contrôles | `stapler validate`, `codesign --verify --strict` | ticket présent, signature valide, CDHash inchangé (`bbeb3ef3…`) |

### 2. DMG

`./scripts/dmg.sh --no-build` a réempaqueté le bundle agrafé ; `/Applications`
n'a pas été touché et Naada ne tournait pas. Le DMG lui-même a été signé avant
l'envoi.

| Étape | Commande | Résultat |
|---|---|---|
| Signature | `codesign --sign "Developer ID Application: Jonathan Bahu (BG55CF653X)" --timestamp dist/Naada.dmg` | horodatage 2026-11-13 07:07:52 ; `codesign --verify --strict` OK |
| Envoi | `asc notarization submit --file dist/Naada.dmg --wait` | `Accepted`, id `78e83cf1-1908-4985-8cc2-1dbc13e6c648` |
| Agrafage | `asc notarization staple --file dist/Naada.dmg --confirm` | « The staple and validate action worked! » |
| Validation | `asc notarization validate --file dist/Naada.dmg` | `validated: true` |
| Gatekeeper | `spctl -a -vvv -t open --context context:primary-signature dist/Naada.dmg` | `accepted`, `source=Notarized Developer ID` |

L'agrafage d'un DMG signé fait afficher à `asc` un avertissement : « artifact
target changed after stapling ». C'est attendu, le ticket modifie l'image signée ;
les contrôles qui font foi passent tous : `codesign --verify --strict` OK,
`asc notarization validate` OK, `spctl` accepte en `Notarized Developer ID`.

### 3. Contrôle de la copie téléchargée

Le bundle agrafé a été extrait du DMG, marqué `com.apple.quarantine`, puis évalué
sans être lancé : `stapler validate` OK, `spctl -a -t exec` → `accepted`,
`source=Notarized Developer ID`, CDHash `bbeb3ef3…`.

### 4. Asset de la release

`gh release upload v1.0.0 dist/Naada.dmg --clobber`, puis retéléchargement :
SHA-256 identique, `86f8131b01a269ecebdbf0daf0f575565f1b2eeb6028a0f71b46f2a620d9a93f`
(6 064 975 octets) ; ticket valide et `spctl` accepte sur la copie retéléchargée.

### Ce qui n'est pas vérifié

- Téléchargement réel dans Safari ou Chrome puis premier lancement par
  double-clic : non fait ici (aucun lancement de l'application, aucun dialogue
  Gatekeeper observé).
- `TCC` et la capture audio : hors périmètre, inchangés.
- `/Applications/Naada.app` n'a pas été remplacé : c'est le même code sans ticket
  agrafé, ce qui ne gêne pas un lancement local (aucune quarantaine).
