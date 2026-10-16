# THERMAL pour EdgeTX

Assistant de vol à voile pour RadioMaster TX16S sous EdgeTX 2.11.7. Il affiche une carte satellite hors ligne, la trace GPS, une roue thermique et un triangle à trois points avec chronométrage.

## Matériel et télémétrie

- RadioMaster TX16S sous EdgeTX 2.11.7 ou version compatible.
- Récepteur avec variomètre et GPS.
- Capteurs nommés : `Alt`, `VSpd`, `GPS`, `GSpd`, `Hdg`, `GAlt` et `Sats`.

## Installation rapide sous Windows

1. Connecter la TX16S en USB et choisir le mode **Stockage USB / carte SD**.
2. Lancer `GENERER_CARTE_THERMAL.cmd`.
3. Cliquer sur **Actualiser USB**.
4. Cliquer sur **Installer / mettre à jour le widget THERMAL**.
5. Coller un lien Google Maps, donner un nom à la zone et afficher l’aperçu.
6. Générer la carte en laissant **Copier aussi vers la TX16S** coché.
7. Éjecter proprement la carte SD, puis redémarrer la radio.

## Utilisation sur la radio

1. Ajouter le widget **Thermal** sur une page plein écran.
2. Ouvrir `SYS` → page des outils → **Réglages Triangle**.
3. Toucher **CARTE** pour choisir le terrain.
4. Choisir A, B ou C, puis toucher la carte pour placer le point.
5. Régler le rayon et les altitudes minimale et maximale.
6. Appuyer sur **SAUVER**. Le widget charge automatiquement la carte et le triangle du modèle actif.
7. Utiliser **EFFACER** pour voler sans triangle.

La carte est orientée nord et possède quatre niveaux de zoom. Le widget ne produit aucun son de variomètre : le vario sonore reste géré par le widget VARIO séparé.

## Gestion des cartes

Le gestionnaire Windows permet de prévisualiser, installer, copier et effacer les cartes du PC ou de la TX16S. Une carte standard couvre 5 × 5 km et contient 193 tuiles.

### Cartes hors de Suisse

Le menu **Source** propose SWISSIMAGE, IGN Orthophotos, OpenAerialMap, Copernicus Sentinel-2 et une URL XYZ personnalisée. Le mode automatique utilise SWISSIMAGE en Suisse, IGN en France et recherche une orthophoto OpenAerialMap ailleurs. La couverture OpenAerialMap est vérifiée avant le téléchargement. Si aucune image n'existe pour la zone, sélectionnez Copernicus et indiquez l'identifiant d'instance créé dans votre compte Copernicus Data Space/Sentinel Hub. Copernicus couvre le monde entier, avec une résolution native de 10 m.

Pour un service national ou commercial autorisant l'utilisation hors ligne, choisissez **XYZ personnalisé** et saisissez une URL contenant `{z}`, `{x}` et `{y}`. Il appartient à l'utilisateur de respecter la licence du fournisseur.

