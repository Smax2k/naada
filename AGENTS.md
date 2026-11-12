# Consignes du projet Naada

## Mise à jour locale de l’application

À chaque nouvelle version ou modification de Naada, reconstruire et signer
l’application avec `./scripts/build.sh`, puis mettre à jour
`/Applications/Naada.app`. Jonathan autorise explicitement ce remplacement
récurrent pour Naada : ne pas redemander confirmation à chaque mise à jour.
Vérifier la signature du bundle construit et du bundle installé, et vérifier que
le bundle installé correspond exactement à celui qui vient d’être construit.

Ne jamais interrompre une application ou une capture en cours. Avant la
construction et avant le remplacement, vérifier que Naada ne tourne pas ; si
elle tourne, arrêter la procédure et demander l’intervention humaine. Si une
invite administrateur, un mot de passe ou une permission macOS est nécessaire,
arrêter la procédure et signaler précisément le blocage sans le contourner.

Ne pas ouvrir l’application, déclencher d’enregistrement ou d’audio, ni accepter
un dialogue macOS à la place de Jonathan. Un blocage Gatekeeper doit être
signalé sans contournement. La signature ne vaut pas autorisation de
notarisation : sans autorisation explicite, ne soumettre aucun fichier à Apple
et n’agrafer aucun ticket. L’horodatage sécurisé prévu par la signature reste
distinct d’une soumission à la notarisation.

Cette autorisation ne concerne que Naada, pas Sandia, et n’autorise aucune
publication. Préserver les changements des autres sessions et ne committer que
ses propres chemins.
