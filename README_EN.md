# THERMAL for EdgeTX

A soaring assistant for the RadioMaster TX16S running EdgeTX 2.11.7. It displays an offline satellite map, GPS track, thermal wheel, and a timed three-point triangle.

## Hardware and telemetry

- RadioMaster TX16S running EdgeTX 2.11.7 or a compatible release.
- Receiver with a variometer and GPS.
- Sensors named `Alt`, `VSpd`, `GPS`, `GSpd`, `Hdg`, `GAlt`, and `Sats`.

## Quick Windows installation

1. Connect the TX16S through USB and select **USB storage / SD card** mode.
2. Run `GENERER_CARTE_THERMAL.cmd`.
3. Click **Actualiser USB** (refresh USB).
4. Click **Installer / mettre à jour le widget THERMAL** (install/update).
5. Paste a Google Maps link, enter an area name, and display the preview.
6. Generate the map while keeping **Copier aussi vers la TX16S** enabled.
7. Safely eject the SD card and restart the radio.

## Using it on the radio

1. Add the **Thermal** widget to a full-screen page.
2. Open `SYS` → Tools → **Réglages Triangle**.
3. Tap **CARTE** to select the flying area.
4. Select A, B, or C and tap the map to place the point.
5. Set its radius and minimum/maximum altitude.
6. Tap **SAUVER**. The widget automatically loads the map and triangle saved for the active model.
7. Use **EFFACER** to fly without a triangle.

The map is north-up and has four zoom levels. This widget produces no variometer audio; vario sounds remain handled by the separate VARIO widget.

## Managing maps

The Windows manager can preview, install, copy, and delete maps stored on the computer or TX16S. A standard map covers 5 × 5 km and contains 193 tiles.

### Maps outside Switzerland

The **Source** menu provides national orthophotos for Switzerland, France, Italy, Spain, Austria and the Netherlands, plus worldwide Sentinel-2 Cloudless, OpenAerialMap, Copernicus Sentinel-2, and a custom XYZ URL. Automatic mode detects the country, selects the best known national source, and falls back to Sentinel-2 when needed. OpenAerialMap remains available manually where local coverage offers more detailed imagery. Worldwide source attribution: EOxCloudless by EOX IT Services GmbH, contains modified Copernicus Sentinel data 2025.

For a national or commercial service that permits offline use, choose **Custom XYZ** and enter a URL containing `{z}`, `{x}`, and `{y}`. Users are responsible for complying with their provider's licence.

