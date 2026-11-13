# Naada — maquette de fenêtre native au repos

Date : 13 novembre 2026
Baseline : HEAD `3206f9f19e9a3aa3d0cc7d4ba395f521be3c2f57`, arbre propre.
Nature : proposition de design uniquement. Aucun code, aucun build, aucun lancement,
aucune capture, aucune intégration, aucun commit.

## Objet

UNE seule maquette IMGEN montrant la fenêtre native Naada au repos, en une image :
la même fenêtre en apparence claire à gauche et en apparence sombre à droite. Même
composition, mêmes dimensions, mêmes contrôles ; seule l'apparence change. Une seule
direction artistique, pas deux maquettes concurrentes.

L'image s'arrête à la proposition visuelle. Elle attend l'approbation explicite de
Jonathan avant toute suite. Une absence de réponse ne vaut pas validation.

## Périmètre

Autorisé, nouveau dossier uniquement :

- `design-work/naada-fenetre-20261113/brief.md`
- `design-work/naada-fenetre-20261113/prompt.txt`
- `design-work/naada-fenetre-20261113/manifest.json`
- `design-work/naada-fenetre-20261113/mockup.png`
- `design-work/naada-fenetre-20261113/estimate-request.json`
- `design-work/naada-fenetre-20261113/estimate-response.json`
- `design-work/naada-fenetre-20261113/generate-response.json`
- `design-work/naada-fenetre-20261113/references/naada-light-full.png`
- `design-work/naada-fenetre-20261113/references/naada-dark-full.png`

Hors périmètre strict : `Sources/`, `Tests/`, `Package.swift`, `packaging/`,
`scripts/`, `docs/`, `.gitignore`, `README`, build, test, `check.sh`, lancement de
Naada, installation, screenshot, capture audio, TCC, permission, commit, push,
publication. `/Applications/Naada.app` n'est pas modifié. Aucun Swift n'est écrit.

## Références

Les deux PNG sont copiés à l'identique depuis
`packaging/AppIcon.icon/Assets/naada-light-full.png` et
`naada-dark-full.png` (cmp identique). Rôle : **marque isolée uniquement**. Ce ne
sont pas des captures de fenêtre, ni des références de composition. Ils fournissent
le dessin exact de l'icône et les deux déclinaisons de couleur.

- `references/naada-light-full.png` : icône claire, fond sable chaud, anneaux
  sarcelle profonde.
- `references/naada-dark-full.png` : icône sombre, fond nuit bleu-vert, anneaux
  menthe.

Contenu lu pour les fonctions, les libellés et le design system :
`Sources/Naada/ContentView.swift` et `packaging/fr.lproj/Localizable.strings`.
Aucune capture de l'application n'est utilisée, ni comme référence, ni comme
ancrage de composition.

## État représenté

- Fenêtre au repos, minuterie `00:00`.
- Aucune application source : valeur `Aucune application`.
- Aucun microphone : valeur `Aucun`.
- Aucun dossier : `Aucun dossier choisi`.
- Titre de session vide, placeholder `Réunion, cours, appel…`.
- Pastille de phase `Repos`.
- `Presets` fermé, sans popover.
- Bouton `Enregistrer` visiblement inactif, seul bouton inactif.
- Aucun menu ouvert, aucun popover, aucune erreur, aucun dernier fichier.
- Aucune invite système, aucune permission accordée, aucun dialogue macOS.
- Aucun nom réel d'application, d'appareil, de personne ou de chemin.

## Trois directions explorées (réflexion, pas trois générations)

1. **Inspecteur macOS** — rail latéral de sections, panneau de détail et bouton
   d'enregistrement fixe. Native, mais elle place les réglages avant la capture et
   glisse facilement vers un tableau de bord ou une page de préférences.
2. **Console à deux entrées** — fenêtre paysage compacte, hiérarchie asymétrique :
   le temps et l'action d'enregistrement dominent ; les deux entrées, application
   et microphone, se lisent comme un petit mélangeur qui alimente l'enregistreur ;
   les détails de session restent calmes, en retrait. Native, propre à un utilitaire
   audio, et elle rend visible la combinaison application seule / micro seul / les
   deux.
3. **Magnétophone vertical épuré** — grande minuterie, entrées empilées dessous,
   session en pied. Trop proche d'un simple VStack recollé : risque de wireframe
   calqué sur l'existant.

Direction retenue : **2, la console à deux entrées**. Elle conserve SF Pro, les
contrôles et la fenêtre macOS, mais repense la composition et la hiérarchie. Elle
n'est pas un wireframe du `VStack` actuel.

## Invariants

### Marque et design system

- Icône Naada existante réutilisée en haut à gauche, petite icône macOS arrondie :
  variante claire dans la fenêtre claire, variante sombre dans la fenêtre sombre.
  Dessin, proportions et deux coloris conservés ; pas de redessin, de simplification,
  de recoloration ni de remplacement.
- L'aplat de l'icône ne devient pas le fond de la fenêtre. Pas de fond sable ni de
  fond sarcelle plein cadre.
- SF Pro / police système macOS, poids et tailles natifs, accents français corrects.
- Surfaces macOS adaptatives : fenêtre claire gris chaud neutre, fenêtre sombre
  graphite neutre ; contrôles natifs, séparateurs fins, coins arrondis, barre de
  titre et feux de circulation.
- Accent inspiré de l'icône : sarcelle profonde en clair, menthe en sombre, utilisé
  avec parcimonie (jauge, point d'état, détails de sélection). Pas d'accent rouge
  actuel.
- SF Symbols réels à intégration, pas d'icônes inventées : `app`, `mic`, `folder`,
  `textformat`, `bookmark`, `record.circle`, `speaker.wave.2`. Rendu monochrome
  natif, pas d'illustration.
- Fenêtre native crédible, pas un site : pas de hero, pas de grille de cartes
  marketing, pas de navigation de site, pas de dégradés gratuits, pas de glassmorphism.
- Les deux apparences ont la même composition au pixel près ; ce ne sont pas deux
  designs.

### Textes existants repris exactement

| Emplacement | Texte |
|---|---|
| Nom | `Naada` |
| Sous-titre | `Enregistreur de session audio` |
| Phase | `Repos` |
| Libellé d'entrée | `Application source` |
| Libellé de sortie | `Dossier de sortie` |
| Valeur vide dossier | `Aucun dossier choisi` |
| Bouton dossier | `Choisir…` |
| Libellé titre | `Titre de session` |
| Placeholder titre | `Réunion, cours, appel…` |
| Bouton principal | `Enregistrer` |
| Aide au repos | `Aucun démarrage automatique.` |
| Presets fermé | `Presets` |

### Contenus et fonctions proposés (nouveaux, à distinguer)

Ces éléments ne sont **pas** existants dans Naada aujourd'hui. La maquette les
montre comme proposition, et la légende hors fenêtre le rappelle.

- Ligne `Microphone` avec état `Aucun`.
- Options proposées, non sélectionnées et expliquées **hors fenêtre** :
  `Aucun`, `Microphone système par défaut`, `Microphone spécifique`.
- État d'application `Aucune application` (et non le placeholder actuel
  `Choisir une application…`).
- Compréhension des trois modes : application seule, microphone seul, application +
  microphone.
- Mémorisation du microphone choisi dans les presets.
- Détail proposé exact :
  `Aucune application ni microphone. Choisissez l'un, l'autre, ou les deux.`
- Pied de fenêtre proposé exact :
  `Audio uniquement · aucune image · aucun démarrage automatique.`
- Note proposée exacte :
  `macOS peut demander l'accès au microphone seulement si un microphone est choisi. Aucune image n'est capturée, le son reste audible, et aucune capture ne démarre avant votre clic.`
- Légende hors fenêtre, commune aux deux apparences, marquée `Proposition` :
  `Microphone : Aucun, Microphone système par défaut, Microphone spécifique. Application seule, microphone seul, ou les deux ; le microphone choisi est mémorisé dans les presets.`

### Textes et états interdits

- Ancien pied `Application audio only · no microphone · no images · sound stays audible.`
  et sa traduction avec `aucun micro`.
- Ancienne formulation `Capture audio de l'application uniquement`.
- `Choisir une application…` comme état affiché.
- `Aucune source sélectionnée`.
- `Choisissez une application source`.
- Tout menu de microphone ouvert, tout popover, toute liste déroulante visible.
- Toute erreur, tout dernier fichier, tout chemin, tout nom réel d'application ou
  d'appareil, tout nom d'utilisateur.
- Toute invite système, tout dialogue de permission, toute notification.
- Tout autre horaire que `00:00`.
- Toute seconde maquette ou seconde direction artistique.

## Contrôle avant estimation (relu le 13 novembre 2026)

- **Périmètre** : une seule image, deux occurrences de la même fenêtre et une
  légende hors fenêtre. Aucune autre zone, aucun écran supplémentaire, aucun asset.
- **Composition** : trois directions explorées, une retenue ; la direction retenue
  n'est pas une transcription du `VStack` actuel. Aucune capture de fenêtre jointe.
- **Contenu** : tous les textes existants sont repris de `Localizable.strings` ;
  les ajouts sont marqués comme propositions ; les textes interdits sont absents.
- **Confidentialité** : les deux références sont uniquement les icônes de marque
  1024 × 1024, sans capture, sans bureau, sans texte, sans nom d'application,
  d'appareil, de personne ou de chemin. Aucune donnée privée n'est nécessaire au
  fournisseur d'images.
- **Marque** : icône réutilisée, non redessinée ; palette dérivée des références ;
  pas d'aplat de l'icône en fond de fenêtre.
- **Clair/sombre** : même composition, deux apparences ; pas deux maquettes.
- **Native** : SF Pro, contrôles macOS, fenêtre isolée, pas de site.
- **Arrêt** : si l'abonnement est indisponible, aucun fichier de génération factice ;
  si le rendu est illisible, redessine la marque, ressemble à un site ou produit deux
  directions, arrêt et signalement, sans régénération.

## Coût

À consigner dans le manifeste après estimation et génération : requête et réponse
complètes, champs bruts `*Micros`, conversion en euros, source du coût et provider.
Aucun montant n'est annoncé avant d'avoir été reçu.

## Limites

- Maquette visuelle uniquement : aucune capture réelle, aucune vérification de
  fonctionnement, aucun test de la future fonctionnalité microphone.
- L'image peut comporter des écarts typographiques cosmétiques ; ils sont signalés
  sans retry et sans régénération.
- L'approbation de Jonathan reste requise ; ce document n'est pas une validation.
