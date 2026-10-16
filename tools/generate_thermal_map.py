"""Generate an offline SWISSIMAGE map pack for the EdgeTX THERMAL widget.

Run without arguments for an interactive prompt, or use:
  python generate_thermal_map.py --name SITE --url GOOGLE_MAPS_URL
  python generate_thermal_map.py --name SITE --lat 46.2 --lon 7.0
"""

from __future__ import annotations

import argparse
import datetime
import io
import math
import re
import shutil
import ssl
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image


SOURCE_ZOOM = 16
SOURCE_TILE = 256
EDGE_TILE = 210
LEVEL_BASE = 315
LEVELS = 4
SWISSIMAGE = (
    "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.swissimage/"
    "default/current/3857/{z}/{x}/{y}.jpeg"
)
SSL_CONTEXT = ssl._create_unverified_context()
ROOT = Path(__file__).resolve().parents[1]
DEV_PACKAGE = ROOT / "outputs" / "THERMAL-v0.5-SD"
PACKAGE = DEV_PACKAGE if DEV_PACKAGE.exists() else ROOT / "SD"
DEFAULT_TARGET = PACKAGE / "WIDGETS" / "THERMAL" / "MAPS"
CACHE = ROOT / ".cache" / "map-tiles"


def find_edgetx_radios() -> list[Path]:
    """Return mounted EdgeTX SD-card roots that already contain THERMAL."""
    if sys.platform != "win32":
        return []
    radios = []
    for letter in "DEFGHIJKLMNOPQRSTUVWXYZ":
        drive = Path(f"{letter}:/")
        try:
            thermal = drive / "WIDGETS" / "THERMAL"
            if (drive / "WIDGETS").is_dir() and (drive / "SCRIPTS").is_dir() and thermal.is_dir():
                radios.append(drive)
        except OSError:
            pass
    return radios


def safe_slug(value: str) -> str:
    value = value.upper().strip()
    value = re.sub(r"[^A-Z0-9_-]+", "_", value).strip("_")
    if not value:
        raise ValueError("Le nom de la carte est vide.")
    return value[:12]


def resolve_google_url(url: str) -> tuple[float, float]:
    parsed = urllib.parse.urlparse(url.strip())
    allowed = ("maps.app.goo.gl", "goo.gl", "google.com", "www.google.com")
    if parsed.hostname not in allowed:
        raise ValueError("Seuls les liens Google Maps sont acceptes.")
    request = urllib.request.Request(url.strip(), headers={"User-Agent": "TX16S-ThermalMap/0.5"})
    with urllib.request.urlopen(request, timeout=30, context=SSL_CONTEXT) as response:
        final_url = urllib.parse.unquote(response.geturl())
    # The consent redirect stores the real URL in its continue parameter.
    query = urllib.parse.parse_qs(urllib.parse.urlparse(final_url).query)
    if "continue" in query:
        final_url = urllib.parse.unquote(query["continue"][0])
    patterns = (
        r"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)",
        r"/search/(-?\d+(?:\.\d+)?),\s*\+?(-?\d+(?:\.\d+)?)",
        r"/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)",
    )
    for pattern in patterns:
        match = re.search(pattern, final_url)
        if match:
            return float(match.group(1)), float(match.group(2))
    raise ValueError("Coordonnees introuvables dans ce lien Google Maps.")


def world_pixel(lat: float, lon: float, zoom: int) -> tuple[float, float]:
    scale = SOURCE_TILE * (2**zoom)
    x = (lon + 180.0) / 360.0 * scale
    sin_lat = math.sin(math.radians(lat))
    y = (0.5 - math.log((1 + sin_lat) / (1 - sin_lat)) / (4 * math.pi)) * scale
    return x, y


def geographic_bounds(lat: float, lon: float, size_m: float) -> tuple[float, float, float, float]:
    # Reference position is centred horizontally and one third above the south edge.
    north_m, south_m = size_m * 2 / 3, size_m / 3
    north = lat + north_m / 111_320.0
    south = lat - south_m / 111_320.0
    dlon = (size_m / 2) / (111_320.0 * math.cos(math.radians(lat)))
    return south, lon - dlon, north, lon + dlon


def automatic_provider(lat: float, lon: float) -> str:
    if 45.7 <= lat <= 47.9 and 5.7 <= lon <= 10.7:
        return "swissimage"
    return "openaerialmap"


def provider_template(provider: str, parameter: str = "") -> str:
    if provider == "swissimage":
        return SWISSIMAGE
    if provider == "openaerialmap":
        return "https://global.imagery.hotosm.org/{z}/{x}/{y}.png"
    if provider == "custom":
        if not all(token in parameter for token in ("{z}", "{x}", "{y}")):
            raise ValueError("L'URL XYZ doit contenir {z}, {x} et {y}.")
        return parameter
    raise ValueError(f"Fournisseur inconnu : {provider}")


def download_tile(x: int, y: int, provider: str, parameter: str = "") -> tuple[Image.Image, bool]:
    cache = CACHE / re.sub(r"[^a-z0-9]+", "_", provider.lower())
    cache.mkdir(parents=True, exist_ok=True)
    cached = cache / f"{SOURCE_ZOOM}-{x}-{y}.img"
    if not cached.exists():
        url = provider_template(provider, parameter).format(z=SOURCE_ZOOM, x=x, y=y)
        request = urllib.request.Request(url, headers={"User-Agent": "TX16S-ThermalMap/0.5"})
        with urllib.request.urlopen(request, timeout=30, context=SSL_CONTEXT) as response:
            cached.write_bytes(response.read())
        time.sleep(0.02)
    if cached.stat().st_size == 0:
        return Image.new("RGB", (256, 256), (35, 50, 40)), False
    try:
        return Image.open(cached).convert("RGB"), True
    except Exception:
        cached.unlink(missing_ok=True)
        return Image.new("RGB", (256, 256), (35, 50, 40)), False


def build_copernicus(lat: float, lon: float, size_m: float, instance: str,
                     progress=None) -> Image.Image:
    if not instance.strip():
        raise ValueError("Indiquez l'identifiant d'instance Copernicus Sentinel Hub.")
    south, west, north, east = geographic_bounds(lat, lon, size_m)
    today = datetime.date.today()
    params = urllib.parse.urlencode({
        "SERVICE": "WMS", "REQUEST": "GetMap", "VERSION": "1.1.1",
        "LAYERS": "TRUE-COLOR", "FORMAT": "image/jpeg", "SRS": "EPSG:4326",
        "BBOX": f"{west},{south},{east},{north}", "WIDTH": 2500, "HEIGHT": 2500,
        "MAXCC": 30, "TIME": f"{today.year - 1}-01-01/{today.isoformat()}",
        "SHOWLOGO": "false",
    })
    url = f"https://sh.dataspace.copernicus.eu/ogc/wms/{instance.strip()}?{params}"
    request = urllib.request.Request(url, headers={"User-Agent": "TX16S-ThermalMap/0.5"})
    if progress:
        progress(0, 1, "Téléchargement Copernicus")
    with urllib.request.urlopen(request, timeout=90, context=SSL_CONTEXT) as response:
        image = Image.open(io.BytesIO(response.read())).convert("RGB")
    if progress:
        progress(1, 1, "Téléchargement Copernicus")
    return image


def build_source(lat: float, lon: float, size_m: float, progress=None,
                 provider: str = "auto", parameter: str = "") -> Image.Image:
    if provider == "auto":
        provider = automatic_provider(lat, lon)
    if provider == "copernicus":
        return build_copernicus(lat, lon, size_m, parameter, progress)
    south, west, north, east = geographic_bounds(lat, lon, size_m)
    left, top = world_pixel(north, west, SOURCE_ZOOM)
    right, bottom = world_pixel(south, east, SOURCE_ZOOM)
    tx0, ty0 = math.floor(left / 256), math.floor(top / 256)
    tx1, ty1 = math.floor((right - 1) / 256), math.floor((bottom - 1) / 256)
    mosaic = Image.new("RGB", ((tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256))
    total = (tx1 - tx0 + 1) * (ty1 - ty0 + 1)
    done = 0
    available = 0
    for ty in range(ty0, ty1 + 1):
        for tx in range(tx0, tx1 + 1):
            tile, present = download_tile(tx, ty, provider, parameter)
            mosaic.paste(tile, ((tx - tx0) * 256, (ty - ty0) * 256))
            if present:
                available += 1
            done += 1
            print(f"Telechargement {provider} : {done}/{total}", flush=True)
            if progress:
                progress(done, total, "Téléchargement satellite")
    if available == 0:
        raise ValueError("Aucune image ouverte disponible ici. Choisissez Copernicus ou un fournisseur XYZ.")
    return mosaic.crop((round(left - tx0 * 256), round(top - ty0 * 256),
                        round(right - tx0 * 256), round(bottom - ty0 * 256)))


def save_pack(source: Image.Image, pack_dir: Path, progress=None) -> None:
    pack_dir.mkdir(parents=True, exist_ok=True)
    total_tiles = sum(math.ceil(LEVEL_BASE * (2**level) / EDGE_TILE) ** 2
                      for level in range(LEVELS))
    completed = 0
    for level in range(LEVELS):
        size = LEVEL_BASE * (2**level)
        folder = pack_dir / f"Z{level}"
        folder.mkdir(exist_ok=True)
        scaled = source.resize((size, size), Image.Resampling.LANCZOS)
        count = math.ceil(size / EDGE_TILE)
        for row in range(count):
            for col in range(count):
                tile = Image.new("RGB", (EDGE_TILE, EDGE_TILE), (30, 45, 35))
                region = scaled.crop((col * EDGE_TILE, row * EDGE_TILE,
                                      min((col + 1) * EDGE_TILE, size),
                                      min((row + 1) * EDGE_TILE, size)))
                tile.paste(region)
                tile.quantize(colors=128).save(folder / f"{col}_{row}.png", optimize=True)
                completed += 1
                if progress:
                    progress(completed, total_tiles, "Création des tuiles")
        print(f"Zoom {level + 1} : {count * count} tuiles", flush=True)


def update_index(target: Path, slug: str, label: str, lat: float, lon: float, size_m: int) -> None:
    target.mkdir(parents=True, exist_ok=True)
    index = target / "index.csv"
    rows = []
    if index.exists():
        rows = [line for line in index.read_text(encoding="utf-8").splitlines()
                if line and not line.startswith(slug + ",")]
    rows.append(f"{slug},{label},{lat:.7f},{lon:.7f},{size_m}")
    index.write_text("\n".join(rows) + "\n", encoding="utf-8")


def install_pack(pack_dir: Path, target: Path, slug: str, label: str,
                 lat: float, lon: float, size_m: int, progress=None) -> None:
    destination = target / slug
    print(f"Copie vers la radio : {destination}", flush=True)
    files = [path for path in pack_dir.rglob("*") if path.is_file()]
    destination.mkdir(parents=True, exist_ok=True)
    for number, source in enumerate(files, 1):
        relative = source.relative_to(pack_dir)
        output = destination / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, output)
        if progress:
            progress(number, len(files), "Copie vers la TX16S")
    update_index(target, slug, label, lat, lon, size_m)


def generate(name: str, lat: float, lon: float, size_km: float, target: Path,
             copy_to_radio: bool = True) -> None:
    slug = safe_slug(name)
    size_m = round(size_km * 1000)
    if size_m < 1000 or size_m > 50000:
        raise ValueError("La dimension doit etre comprise entre 1 et 50 km.")
    print(f"Carte {name} ({slug}) : {lat:.7f}, {lon:.7f}, {size_km:g} km", flush=True)
    source = build_source(lat, lon, size_m)
    save_pack(source, target / slug)
    update_index(target, slug, name[:20], lat, lon, size_m)
    print(f"Carte terminee : {target / slug}")
    if copy_to_radio:
        radios = find_edgetx_radios()
        if not radios:
            print("Aucune TX16S avec le widget THERMAL detectee : carte conservee sur le PC.")
        else:
            for drive in radios:
                radio_maps = drive / "WIDGETS" / "THERMAL" / "MAPS"
                install_pack(target / slug, radio_maps, slug, name[:20], lat, lon, size_m)
                print(f"Carte installee sur la TX16S ({drive})", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generateur de cartes satellite THERMAL")
    parser.add_argument("--name")
    parser.add_argument("--url")
    parser.add_argument("--lat", type=float)
    parser.add_argument("--lon", type=float)
    parser.add_argument("--size", type=float, default=5.0,
                        help="dimension en km (avance, 5 km par defaut)")
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    parser.add_argument("--no-radio", action="store_true",
                        help="ne pas copier automatiquement vers une TX16S connectee")
    args = parser.parse_args()
    if not args.name:
        args.name = input("Nom de la carte : ").strip()
    if args.lat is None or args.lon is None:
        if not args.url:
            args.url = input("Lien Google Maps : ").strip()
        args.lat, args.lon = resolve_google_url(args.url)
        print(f"Coordonnees trouvees : {args.lat:.7f}, {args.lon:.7f}")
    generate(args.name, args.lat, args.lon, args.size, args.target, not args.no_radio)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERREUR : {exc}", file=sys.stderr)
        input("Appuyer sur Entree pour fermer...")
        raise
