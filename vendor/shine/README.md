# Shine — encodeur MP3 vendu

Source récupérée depuis `https://github.com/savonet/shine` (branche `main`),
commit consigné dans `COMMIT`.

Fichiers utilisés : `src/lib/*.c` et `src/lib/*.h`, copiés dans `lib/` pour
traçabilité. La cible SwiftPM `CShine` compile les `.c` et expose seulement
`layer3.h` ; les en-têtes privés sont dans `Sources/CShine/private`.

Licence : GNU Library General Public License version 2. Voir `COPYING`.

Aucune modification fonctionnelle n'a été apportée au code de l'encodeur.
