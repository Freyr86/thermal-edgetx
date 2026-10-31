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

### Sons et tours du triangle

Les options du widget permettent de sélectionner trois fichiers sonores indépendants dans le dossier `SOUNDS` :

- **Start** : première sortie valide de la zone A et démarrage du chrono.
- **Next** : validation de B, de C et de A entre deux tours.
- **Finish** : retour dans A après le dernier tour demandé.

**ToursMax** définit le nombre de tours à effectuer. La valeur `0` active le mode illimité : chaque triangle complet augmente le compteur et le chrono continue sans jouer **Finish**. Avec une valeur supérieure à zéro, le widget affiche les tours effectués et le nombre restant, puis arrête le chrono et joue **Finish** lorsque le compte est atteint. La commande **ResetSw** remet le chrono et le compteur de tours à zéro et efface tous les marqueurs thermiques posés avec **MarkSw**. Elle ne supprime ni la trace GPS ni la roue thermique.

Le nombre de tours possède sa propre marge à gauche des cases de chronométrage. L'option **CarteSw** accepte un interrupteur physique ou logique EdgeTX. Lorsqu'il est actif, toute l'interface est masquée et la carte occupe l'écran complet avec la trace, le modèle et les points A/B/C. Le calcul du triangle, les sons et les chronos continuent de fonctionner en arrière-plan.

### Marqueurs thermiques et enregistrement du vol

- **MarkSw** : chaque activation pose un marqueur orange numéroté à la position GPS actuelle. Les 30 derniers marqueurs de la session sont conservés afin de retrouver les thermiques.
- **LogSw** : l'enregistrement démarre lorsque l'interrupteur devient actif et s'arrête lorsqu'il devient inactif. Un indicateur rouge **REC** confirme l'enregistrement.
- **MotorSrc** : sortie ou source EdgeTX qui représente la commande moteur (par exemple `CH3`).
- **MotorOn** : seuil d'allumage du moteur, en pourcentage. Avec une commande allant de -100 à +100 %, la valeur par défaut `-80` considère le moteur actif dès que la commande dépasse -80 %.
- **MotInv** : inverse la lecture si la voie moteur fonctionne dans l'autre sens.

L'état moteur n'est pas affiché à l'écran. Il est uniquement ajouté à chaque point du fichier dans l'extension IGC `MOP` (`000` arrêté, `999` allumé). Les traces sont enregistrées une fois par seconde dans `/LOGS/THM-AAAAMMJJ-HHMMSS.igc`. Le format IGC peut être ouvert dans XCSoar et dans les logiciels courants d'analyse de vol à voile. Ces fichiers produits par un script Lua ne sont pas signés et ne constituent pas un enregistreur homologué pour une compétition ou un record officiel.

`LogSw` peut être activé avant l'obtention du fix GPS : le fichier est créé immédiatement, puis les points sont ajoutés automatiquement dès que le GPS devient valide. La position doit être valide et le nombre de satellites doit atteindre **MinSats**. `MarkSw` ignore une activation sans GPS valide ; il faut l'actionner de nouveau après le fix. Chaque nouvelle activation de `LogSw` crée un nouveau fichier. À un point par seconde, une heure de vol occupe seulement environ 150 Ko.

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

