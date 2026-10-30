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
2. Open `SYS` → Tools → **Réglages Triangle**. This screen also adapts automatically to the radio display resolution.
3. Tap **CARTE** to select the flying area.
4. Select A, B, or C and tap the map to place the point.
5. Set its radius and minimum/maximum altitude.
6. Tap **SAUVER**. The widget automatically loads the map and triangle saved for the active model.
7. Use **EFFACER** to fly without a triangle.

The map is north-up and has three zoom levels. The layout automatically adapts to the radio display resolution, including 480 × 272 screens and the TX16S MK3 800 × 480 display.

Use **ZoomPot** in the widget options to select an EdgeTX potentiometer or slider. Its three positions select Z1, Z2, and Z3. The direction is reversed: slider up selects Z1 and slider down selects Z3. If **ZoomPot** is left unset, the map stays at Z1. The former touch `ZOOM` button and rotary-wheel mode have been removed.

This widget produces no variometer audio; vario sound is handled separately.

## Managing maps

The Windows manager can preview, install, copy, and delete maps stored on the computer or TX16S. A standard map covers 5 × 5 km. Each newly generated map contains two tile pyramids: a 480 profile for TX16S MK1/MK2 radios and an 800 profile for the TX16S MK3. The widget automatically selects the profile matching its display.

Legacy 315-pixel maps remain readable in compatibility mode, but cannot properly fill an 800 × 480 display. Regenerate them with this manager version to remove margins and missing areas on the MK3.

### Maps outside Switzerland

The **Source** menu provides national orthophotos for Switzerland, France, Italy, Spain, Austria and the Netherlands, plus worldwide Sentinel-2 Cloudless, OpenAerialMap, Copernicus Sentinel-2, and a custom XYZ URL. Automatic mode detects the country, selects the best known national source, and falls back to Sentinel-2 when needed. OpenAerialMap remains available manually where local coverage offers more detailed imagery. Worldwide source attribution: EOxCloudless by EOX IT Services GmbH, contains modified Copernicus Sentinel data 2025.

For a national or commercial service that permits offline use, choose **Custom XYZ** and enter a URL containing `{z}`, `{x}`, and `{y}`. Users are responsible for complying with their provider's licence.

### Request more detailed imagery

If the automatic imagery is not detailed enough in your country or region, [open a request on GitHub](https://github.com/Freyr86/thermal-edgetx/issues/new). Include the country, region, a Google Maps link to a test location and, when known, the official imagery source URL. A source can only be integrated when it works without a mandatory account and its licence permits this use.

