# THERMAL pour EdgeTX

Assistant de vol à voile pour RadioMaster TX16S sous EdgeTX 2.11.7 ou version ultérieure. Il affiche une carte satellite hors ligne, la trace GPS, une roue thermique et un triangle à trois points avec chronométrage.

## Matériel et télémétrie

- RadioMaster TX16S sous EdgeTX 2.11.7 ou version ultérieure compatible, notamment EdgeTX 2.12 sur la TX16S MK3.
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
2. Ouvrir `SYS` → page des outils → **Réglages Triangle**. Cet écran s'adapte lui aussi automatiquement à la résolution de la radio.
3. Toucher **CARTE** pour choisir le terrain.
4. Choisir A, B ou C, puis toucher la carte pour placer le point.
5. Régler le rayon et les altitudes minimale et maximale.
6. Appuyer sur **SAUVER**. Le widget charge automatiquement la carte et le triangle du modèle actif.
7. Utiliser **EFFACER** pour voler sans triangle.

La carte est orientée nord et possède trois niveaux de zoom. Le widget adapte automatiquement sa mise en page à la résolution de la radio, notamment aux écrans 480 × 272 et 800 × 480 de la TX16S MK3.

Dans les options du widget, **ZoomPot** permet de choisir un potentiomètre ou un slider EdgeTX. Ses trois positions correspondent aux niveaux Z1, Z2 et Z3. Le sens est inversé : glisseur vers le haut pour Z1, vers le bas pour Z3. Si **ZoomPot** reste vide, la carte reste au niveau Z1. L'ancien bouton tactile `ZOOM` et le mode molette ont été retirés.

L'option **Recentre** définit à quelle distance du centre la carte doit suivre de nouveau le planeur. La valeur recommandée `70` laisse la carte fixe jusqu'à 70 % de la distance entre le centre et le bord, puis recentre le modèle. La valeur `0` rétablit le suivi continu.

Le widget ne produit aucun son de variomètre : le vario sonore reste géré séparément.

### Activer le variomètre sonore EdgeTX

1. Allumer le modèle et vérifier que le capteur `VSpd` reçoit bien une valeur.
2. Ouvrir **Réglages du modèle** → **Télémétrie** → **Variomètre**.
3. Sélectionner `VSpd` comme **Source**, puis régler la plage de montée/descente et la zone neutre **Centre**. Choisir **Silencieux** pour ne produire aucun son dans cette zone.
4. Dans **Fonctions spéciales**, créer une fonction commandée par l'interrupteur souhaité, sélectionner **Vario**, puis cocher son activation.
5. Régler le volume, les fréquences et la répétition dans **Réglages radio** → **Sons/Vibrations** → **Variomètre**.

Cette fonction sonore est entièrement gérée par EdgeTX et peut fonctionner en même temps que le widget THERMAL. Ne pas sélectionner `Alt`, `GAlt` ou une moyenne calculée à la place de `VSpd`.

## Gestion des cartes

Le gestionnaire Windows permet de prévisualiser, installer, copier et effacer les cartes du PC ou de la TX16S. Une carte standard couvre 5 × 5 km. Chaque nouvelle carte contient deux pyramides de tuiles : un profil 480 pour les TX16S MK1/MK2 et un profil 800 pour la TX16S MK3. Le widget choisit automatiquement le profil correspondant à son écran.

Les anciennes cartes au format 315 pixels restent lisibles en mode de compatibilité, mais elles ne peuvent pas remplir correctement l'écran 800 × 480. Elles doivent être régénérées avec cette version du gestionnaire pour supprimer les marges et les zones manquantes sur la MK3.

### Cartes hors de Suisse

Le menu **Source** propose les orthophotos nationales de Suisse, France, Italie, Espagne, Autriche et Pays-Bas, ainsi que Sentinel-2 Cloudless mondial, OpenAerialMap, Copernicus Sentinel-2 et une URL XYZ personnalisée. Le mode automatique détecte le pays, sélectionne la meilleure source nationale connue puis revient à Sentinel-2 lorsque nécessaire. OpenAerialMap reste disponible manuellement lorsque sa couverture locale offre une image plus détaillée. Attribution de la source mondiale : EOxCloudless par EOX IT Services GmbH, contient des données Copernicus Sentinel modifiées 2025.

Pour un service national ou commercial autorisant l'utilisation hors ligne, choisissez **XYZ personnalisé** et saisissez une URL contenant `{z}`, `{x}` et `{y}`. Il appartient à l'utilisateur de respecter la licence du fournisseur.

### Demander une carte plus précise

Si les images automatiques ne sont pas assez précises dans votre pays ou votre région, [ouvrez une demande sur GitHub](https://github.com/Freyr86/thermal-edgetx/issues/new). Indiquez le pays, la région, un lien Google Maps vers un lieu de test et, si vous en connaissez une, l’adresse de la source cartographique officielle. Une source ne pourra être intégrée que si son service fonctionne sans compte obligatoire et si sa licence autorise cet usage.

