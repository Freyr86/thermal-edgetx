# THERMAL EdgeTX

Widget de vol à voile pour RadioMaster TX16S : carte satellite hors ligne, trace GPS, roue thermique et triangle chronométré.

![Logo THERMAL](assets/thermal-logo-128.png)

- [Guide rapide en français](README_FR.md)
- [Quick guide in English](README_EN.md)

## Installation

Sous Windows, lancez `GENERER_CARTE_THERMAL.cmd`. Le gestionnaire détecte la carte SD EdgeTX, installe ou met à jour le widget et permet de créer des cartes locales 5 × 5 km à partir d’un lien Google Maps.

Les sources disponibles couvrent la Suisse et le monde : SWISSIMAGE, OpenAerialMap, Copernicus Sentinel-2 et fournisseurs XYZ personnalisés.

Le widget attend les capteurs `Alt`, `VSpd`, `GPS`, `GSpd`, `Hdg`, `GAlt` et `Sats`.

Compatible et testé avec EdgeTX 2.11.7 sur RadioMaster TX16S.

## Contenu

- `SD/` : fichiers à copier sur la carte SD de la radio.
- `tools/` : gestionnaire et générateur de cartes Windows.
- `GENERER_CARTE_THERMAL.cmd` : lancement du gestionnaire graphique.

Les cartes satellite personnelles ne sont pas incluses dans le dépôt. Elles sont générées localement par l’utilisateur.

## Licence

Le code du projet est distribué sous licence MIT. Les images cartographiques restent soumises aux conditions de leur fournisseur.

