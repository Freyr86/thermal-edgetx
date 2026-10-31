# THERMAL for EdgeTX

A soaring assistant for the RadioMaster TX16S running EdgeTX 2.11.7 or later. It displays an offline satellite map, GPS track, thermal wheel, and a timed three-point triangle.

## Hardware and telemetry

- RadioMaster TX16S running EdgeTX 2.11.7 or a later compatible release, including EdgeTX 2.12 on the TX16S MK3.
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

The **Recentre** option controls how far the aircraft may move from the map centre before the view follows it again. The recommended value `70` keeps the map fixed until the aircraft reaches 70% of the centre-to-edge distance, then recentres it. Set it to `0` for continuous following.

### Triangle sounds and laps

The widget options provide three independent sound files from the `SOUNDS` folder:

- **Start**: first valid exit from zone A and timer start.
- **Next**: validation of B, C, and A between consecutive laps.
- **Finish**: return to A after the requested final lap.

**ToursMax** selects the number of laps. Set it to `0` for unlimited mode: every completed triangle increments the lap counter, the timer keeps running, and **Finish** is never played. With a value above zero, the widget displays completed and remaining laps, then stops the timer and plays **Finish** when the requested count is reached. **ResetSw** resets the timer and lap counter and removes all thermal markers placed with **MarkSw**. It does not clear the GPS track or thermal wheel.

The lap count has its own margin to the left of the timing tiles. **CarteSw** accepts an EdgeTX physical or logical switch. While active, it hides the complete interface and expands the map to the full screen, retaining the track, aircraft and A/B/C points. Triangle processing, sounds and timers continue in the background.

### Thermal markers and flight recording

- **MarkSw**: each activation places a numbered orange marker at the current GPS position. The latest 30 markers in the session are retained to help locate thermals again.
- **LogSw**: recording starts while the selected switch is active and stops when it becomes inactive. A red **REC** indicator confirms recording.
- **MotorSrc**: EdgeTX output or source representing the motor command (for example `CH3`).
- **MotorOn**: motor-on threshold in percent. For a command ranging from -100 to +100%, the default `-80` treats the motor as active as soon as the command rises above -80%.
- **MotInv**: reverses detection when the motor channel operates in the opposite direction.

Motor state is not displayed on screen. It is only stored with each recorded point in the IGC `MOP` extension (`000` off, `999` on). Tracks are recorded once per second as `/LOGS/THM-YYYYMMDD-HHMMSS.igc`. IGC files can be opened by XCSoar and common soaring-flight analysis applications. Files produced by this Lua script are unsigned and are not an approved flight recorder for official competitions or records.

`LogSw` may be enabled before GPS lock: the file is created immediately, then fixes are appended automatically as soon as GPS becomes valid. Position must be valid and the satellite count must reach **MinSats**. `MarkSw` ignores an activation without valid GPS; activate it again after lock. Every new activation of `LogSw` creates a new file. At one fix per second, one flight hour uses only about 150 KB.

This widget produces no variometer audio; vario sound is handled separately.

### Enabling the EdgeTX audio variometer

1. Power on the model and verify that the `VSpd` sensor is receiving data.
2. Open **Model settings** → **Telemetry** → **Variometer**.
3. Select `VSpd` as the **Source**, then configure the climb/sink range and the neutral **Center** range. Select **Silent** to produce no sound inside that neutral range.
4. In **Special Functions**, add a function controlled by the desired switch, select **Vario**, and enable its checkbox.
5. Configure its volume, frequencies, and repetition under **Radio settings** → **Sounds/Vibration** → **Variometer**.

EdgeTX handles this audio function directly, and it can run at the same time as the THERMAL widget. Do not select `Alt`, `GAlt`, or a calculated average instead of `VSpd`.

## Managing maps

The Windows manager can preview, install, copy, and delete maps stored on the computer or TX16S. A standard map covers 5 × 5 km. Each newly generated map contains two tile pyramids: a 480 profile for TX16S MK1/MK2 radios and an 800 profile for the TX16S MK3. The widget automatically selects the profile matching its display.

Legacy 315-pixel maps remain readable in compatibility mode, but cannot properly fill an 800 × 480 display. Regenerate them with this manager version to remove margins and missing areas on the MK3.

### Maps outside Switzerland

The **Source** menu provides national orthophotos for Switzerland, France, Italy, Spain, Austria and the Netherlands, plus worldwide Sentinel-2 Cloudless, OpenAerialMap, Copernicus Sentinel-2, and a custom XYZ URL. Automatic mode detects the country, selects the best known national source, and falls back to Sentinel-2 when needed. OpenAerialMap remains available manually where local coverage offers more detailed imagery. Worldwide source attribution: EOxCloudless by EOX IT Services GmbH, contains modified Copernicus Sentinel data 2025.

For a national or commercial service that permits offline use, choose **Custom XYZ** and enter a URL containing `{z}`, `{x}`, and `{y}`. Users are responsible for complying with their provider's licence.

### Request more detailed imagery

If the automatic imagery is not detailed enough in your country or region, [open a request on GitHub](https://github.com/Freyr86/thermal-edgetx/issues/new). Include the country, region, a Google Maps link to a test location and, when known, the official imagery source URL. A source can only be integrated when it works without a mandatory account and its licence permits this use.

