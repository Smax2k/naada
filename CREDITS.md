# Crédits et licences

## Naada

Application locale construite dans ce dépôt. Aucune publication, aucun service
réseau.

## Encodeur MP3 Shine

- Projet : [savonet/shine](https://github.com/savonet/shine)
- Commit vendu : voir `vendor/shine/COMMIT`
- Source : `vendor/shine/lib`, compilée par la cible `CShine`
- Licence : GNU Library General Public License, version 2 (LGPL-2). Le texte
  complet est dans `vendor/shine/COPYING` et il est copié dans le bundle sous
  `Contents/Resources/Shine-COPYING.txt`.

Shine est lié statiquement dans `Naada.app`. Toute redistribution du bundle
doit respecter la LGPL-2 : fournir la source correspondante (elle est dans ce
dépôt) et permettre le remplacement/relinkage de la bibliothèque. Pour un usage
local, le bundle produit ici n'est pas distribué.

## Polices et icônes

Les icônes sont des symboles SF Symbols fournis par macOS. Aucune ressource
d'image tierce n'est incluse.
