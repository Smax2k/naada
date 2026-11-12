# Notarisation Developer ID — procédure exacte, sans envoi

État au 2026-11-12. Ce document décrit la procédure de notarisation de Naada.
**Aucune commande d'envoi, de notarisation ou d'agrafage n'a été exécutée pour
le produire.** Les commandes marquées INTERDITE exigent un consentement explicite
et écrit de Jonathan à la transmission du fichier à Apple ; ce consentement est
absent à ce jour.

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
| `submit` | `asc notarization submit --file <path> [--wait] [--poll-interval 30s] [--timeout 1h] [--output json]` | envoi du fichier à Apple | INTERDITE sans consentement |
| `status` | `asc notarization status --id "SUBMISSION_ID"` | lecture | non exécutée |
| `log` | `asc notarization log --id "SUBMISSION_ID"` | lecture | non exécutée |
| `list` | `asc notarization list [--limit N]` | lecture | non exécutée |
| `staple` | `asc notarization staple --file <path> --confirm` | mutation locale + ticket | INTERDITE sans consentement |
| `validate` | `asc notarization validate --file <path>` | lecture locale | non exécutée |

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

## 4. Envoi — NON EXÉCUTÉ, INTERDIT

```bash
ASC_PROFILE="<profil>" asc notarization submit \
  --file ./Naada.zip \
  --wait --poll-interval 30s --timeout 1h \
  --output json
```

**NON EXÉCUTÉE — INTERDITE avant consentement explicite de Jonathan à la
transmission (absent).**

- L'aide de `submit` ne montre ni `--dry-run` ni `--confirm` : la commande crée
  la soumission et téléverse le fichier dès son lancement. Il n'existe aucun mode
  « pour voir ».
- Le fichier est transmis à Apple (S3) ; ne pas lancer cette commande pour tester
  un profil, une clé ou un chemin.
- `--wait` est facultatif ; sans lui, conserver l'identifiant de soumission pour
  `status`.
- Aucune clé, aucun accord, aucun fichier n'a été envoyé pour produire ce
  document.

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

## 6. Agrafage — NON EXÉCUTÉ, INTERDIT

```bash
ASC_PROFILE="<profil>" asc notarization staple --file "Naada.app" --confirm
```

**NON EXÉCUTÉE — INTERDITE avant consentement explicite (absent).**

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

Ce document ne remplace pas une preuve d'exécution : il n'y en a aucune.
