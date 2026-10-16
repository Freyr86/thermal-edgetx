"""Gestionnaire graphique des cartes du widget THERMAL pour EdgeTX."""

from __future__ import annotations

import math
import shutil
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

from PIL import Image, ImageTk

import generate_thermal_map as engine


DEV_PACKAGE = engine.ROOT / "outputs" / "THERMAL-v0.5-SD"
PACKAGE = DEV_PACKAGE if DEV_PACKAGE.exists() else engine.ROOT / "SD"
LOCAL_MAPS = PACKAGE / "WIDGETS" / "THERMAL" / "MAPS"
PROVIDERS = {
    "Automatique (Suisse / monde ouvert)": "auto",
    "SWISSIMAGE (Suisse)": "swissimage",
    "OpenAerialMap (monde, couverture variable)": "openaerialmap",
    "Copernicus Sentinel-2 (monde, compte requis)": "copernicus",
    "XYZ personnalisé": "custom",
}


def detect_radio() -> Path | None:
    for letter in "DEFGHIJKLMNOPQRSTUVWXYZ":
        drive = Path(f"{letter}:/")
        try:
            if ((drive / "edgetx.sdcard.version").exists()
                    or ((drive / "RADIO").is_dir() and (drive / "MODELS").is_dir())):
                return drive
        except OSError:
            pass
    return None


def read_index(root: Path) -> list[dict]:
    result = []
    index = root / "index.csv"
    if not index.exists():
        return result
    for line in index.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split(",")
        if len(parts) >= 5:
            try:
                result.append({"slug": parts[0], "label": parts[1],
                               "lat": float(parts[2]), "lon": float(parts[3]),
                               "size": int(float(parts[4]))})
            except ValueError:
                continue
    return result


def remove_from_index(root: Path, slug: str) -> None:
    index = root / "index.csv"
    rows = [line for line in index.read_text(encoding="utf-8").splitlines()
            if line and not line.startswith(slug + ",")] if index.exists() else []
    index.parent.mkdir(parents=True, exist_ok=True)
    index.write_text(("\n".join(rows) + "\n") if rows else "", encoding="utf-8")


def delete_pack(pack: Path, progress=None) -> None:
    """Delete one map pack while reporting each removed file."""
    if not pack.exists():
        return
    files = [path for path in pack.rglob("*") if path.is_file()]
    total = len(files)
    for number, path in enumerate(files, 1):
        path.unlink()
        if progress:
            progress(number, total, "Effacement de la carte")
    for folder in sorted((path for path in pack.rglob("*") if path.is_dir()),
                         key=lambda path: len(path.parts), reverse=True):
        folder.rmdir()
    pack.rmdir()


def make_pack_preview(pack: Path) -> Image.Image:
    folder = pack / "Z0"
    canvas = Image.new("RGB", (420, 420), (35, 50, 40))
    found = False
    for row in range(2):
        for col in range(2):
            tile = folder / f"{col}_{row}.png"
            if tile.exists():
                with Image.open(tile) as image:
                    canvas.paste(image.convert("RGB"), (col * 210, row * 210))
                found = True
    if not found:
        raise FileNotFoundError("Aucune tuile Z0 trouvée.")
    return canvas.crop((0, 0, 315, 315))


class ZoomPreview(ttk.Frame):
    def __init__(self, parent, initial_text: str):
        super().__init__(parent)
        self.original: Image.Image | None = None
        self.photo: ImageTk.PhotoImage | None = None
        self.scale = 1.0
        toolbar = ttk.Frame(self)
        toolbar.pack(fill="x", pady=(0, 4))
        ttk.Button(toolbar, text="−", width=3, command=lambda: self.change_zoom(0.8)).pack(side="left")
        ttk.Button(toolbar, text="+", width=3, command=lambda: self.change_zoom(1.25)).pack(side="left", padx=3)
        ttk.Button(toolbar, text="Ajuster", command=self.fit).pack(side="left")
        self.zoom_label = ttk.Label(toolbar, text="100 %")
        self.zoom_label.pack(side="left", padx=8)
        area = ttk.Frame(self)
        area.pack(fill="both", expand=True)
        self.canvas = tk.Canvas(area, background="#233228", highlightthickness=0)
        xbar = ttk.Scrollbar(area, orient="horizontal", command=self.canvas.xview)
        ybar = ttk.Scrollbar(area, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(xscrollcommand=xbar.set, yscrollcommand=ybar.set)
        self.canvas.grid(row=0, column=0, sticky="nsew")
        ybar.grid(row=0, column=1, sticky="ns")
        xbar.grid(row=1, column=0, sticky="ew")
        area.rowconfigure(0, weight=1)
        area.columnconfigure(0, weight=1)
        self.canvas.bind("<MouseWheel>", self._wheel)
        self.set_message(initial_text)

    def set_message(self, text: str) -> None:
        self.original = None
        self.photo = None
        self.canvas.delete("all")
        self.canvas.create_text(10, 10, text=text, fill="white", anchor="nw", width=340)
        self.canvas.configure(scrollregion=(0, 0, 1, 1))
        self.zoom_label.configure(text="—")

    def set_image(self, image: Image.Image) -> None:
        self.original = image.copy().convert("RGB")
        self.after_idle(self.fit)

    def fit(self) -> None:
        if not self.original:
            return
        self.update_idletasks()
        width = max(50, self.canvas.winfo_width() - 12)
        height = max(50, self.canvas.winfo_height() - 12)
        self.scale = min(width / self.original.width, height / self.original.height, 1.0)
        self._draw()

    def change_zoom(self, factor: float) -> None:
        if not self.original:
            return
        self.scale = max(0.1, min(4.0, self.scale * factor))
        self._draw()

    def _wheel(self, event) -> str:
        self.change_zoom(1.25 if event.delta > 0 else 0.8)
        return "break"

    def _draw(self) -> None:
        if not self.original:
            return
        width = max(1, round(self.original.width * self.scale))
        height = max(1, round(self.original.height * self.scale))
        resized = self.original.resize((width, height), Image.Resampling.LANCZOS)
        self.photo = ImageTk.PhotoImage(resized)
        self.canvas.delete("all")
        canvas_w, canvas_h = self.canvas.winfo_width(), self.canvas.winfo_height()
        x, y = max(0, (canvas_w - width) // 2), max(0, (canvas_h - height) // 2)
        self.canvas.create_image(x, y, image=self.photo, anchor="nw")
        self.canvas.configure(scrollregion=(0, 0, max(width, canvas_w), max(height, canvas_h)))
        self.zoom_label.configure(text=f"{self.scale * 100:.0f} %")


class Manager(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("THERMAL - Gestionnaire de cartes TX16S")
        self._set_window_icon()
        self.geometry("1120x720")
        self.minsize(980, 650)
        self.radio: Path | None = None
        self.entries: list[dict] = []
        self.preview_photo: ImageTk.PhotoImage | None = None
        self.pending: tuple[str, float, float, Image.Image] | None = None
        self.busy = False
        self._build_ui()
        self.refresh_all()

    def _set_window_icon(self) -> None:
        ico = engine.ROOT / "assets" / "thermal-logo.ico"
        png = engine.ROOT / "assets" / "thermal-logo-128.png"
        try:
            if ico.exists():
                self.iconbitmap(default=str(ico))
            if png.exists():
                self.window_icon = tk.PhotoImage(file=str(png))
                self.iconphoto(True, self.window_icon)
        except tk.TclError:
            pass

    def _build_ui(self) -> None:
        top = ttk.Frame(self, padding=10)
        top.pack(fill="x")
        ttk.Label(top, text="Gestionnaire THERMAL", font=("Segoe UI", 18, "bold")).pack(side="left")
        self.radio_label = ttk.Label(top, text="TX16S : recherche…")
        self.radio_label.pack(side="left", padx=30)
        ttk.Button(top, text="Actualiser USB", command=self.refresh_all).pack(side="right")

        body = ttk.Panedwindow(self, orient="horizontal")
        body.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        left = ttk.Labelframe(body, text="Ajouter une carte satellite", padding=10)
        right = ttk.Labelframe(body, text="Cartes disponibles", padding=10)
        body.add(left, weight=3)
        body.add(right, weight=2)

        form = ttk.Frame(left)
        form.pack(fill="x")
        ttk.Label(form, text="Nom").grid(row=0, column=0, sticky="w")
        self.name_var = tk.StringVar()
        ttk.Entry(form, textvariable=self.name_var, width=24).grid(row=0, column=1, sticky="ew", padx=7)
        ttk.Label(form, text="Lien Google Maps").grid(row=1, column=0, sticky="w", pady=6)
        self.url_var = tk.StringVar()
        ttk.Entry(form, textvariable=self.url_var).grid(row=1, column=1, sticky="ew", padx=7, pady=6)
        ttk.Label(form, text="Source").grid(row=2, column=0, sticky="w")
        self.provider = ttk.Combobox(form, state="readonly", values=list(PROVIDERS), width=42)
        self.provider.grid(row=2, column=1, sticky="ew", padx=7)
        self.provider.current(0)
        self.provider.bind("<<ComboboxSelected>>", lambda _e: self.update_provider_help())
        ttk.Label(form, text="Paramètre").grid(row=3, column=0, sticky="w", pady=6)
        self.provider_parameter = tk.StringVar()
        ttk.Entry(form, textvariable=self.provider_parameter).grid(row=3, column=1, sticky="ew", padx=7, pady=6)
        self.provider_help = ttk.Label(form, text="Choix automatique : SWISSIMAGE en Suisse, OpenAerialMap ailleurs.")
        self.provider_help.grid(row=4, column=1, sticky="w", padx=7, pady=(0, 6))
        form.columnconfigure(1, weight=1)

        actions = ttk.Frame(left)
        actions.pack(fill="x", pady=(0, 8))
        ttk.Button(actions, text="1. Afficher l’aperçu", command=self.preview_new).pack(side="left")
        self.auto_copy = tk.BooleanVar(value=True)
        ttk.Checkbutton(actions, text="Copier aussi vers la TX16S", variable=self.auto_copy).pack(side="left", padx=14)
        self.generate_button = ttk.Button(actions, text="2. Générer la carte", command=self.generate_new)
        self.generate_button.pack(side="right")

        self.preview = ZoomPreview(left, "Collez un lien Google Maps puis affichez l’aperçu.")
        self.preview.pack(fill="both", expand=True)
        self.status = ttk.Label(left, text="Prêt", anchor="w")
        self.status.pack(fill="x", pady=(8, 0))
        self.progress = ttk.Progressbar(left, mode="determinate", maximum=100)
        self.progress.pack(fill="x", pady=(4, 0))

        source_line = ttk.Frame(right)
        source_line.pack(fill="x")
        ttk.Label(source_line, text="Emplacement :").pack(side="left")
        self.source = ttk.Combobox(source_line, state="readonly", width=24)
        self.source.pack(side="left", padx=6, fill="x", expand=True)
        self.source.bind("<<ComboboxSelected>>", lambda _e: self.refresh_list())

        self.listbox = tk.Listbox(right, height=12, exportselection=False)
        self.listbox.pack(fill="x", pady=8)
        self.listbox.bind("<<ListboxSelect>>", lambda _e: self.preview_selected())
        self.installed_preview = ZoomPreview(right, "Sélectionnez une carte.")
        self.installed_preview.pack(fill="both", expand=True)

        buttons = ttk.Frame(right)
        buttons.pack(fill="x", pady=(8, 0))
        ttk.Button(buttons, text="Copier vers TX16S", command=self.copy_selected).pack(side="left")
        ttk.Button(buttons, text="Effacer", command=self.delete_selected).pack(side="right")

        ttk.Separator(right).pack(fill="x", pady=10)
        self.widget_status = ttk.Label(right, text="Widget : —")
        self.widget_status.pack(anchor="w")
        ttk.Button(right, text="Installer / mettre à jour le widget THERMAL",
                   command=self.install_widget).pack(fill="x", pady=(5, 0))

    def update_provider_help(self) -> None:
        provider = PROVIDERS[self.provider.get()]
        messages = {
            "auto": "Aucun paramètre nécessaire.",
            "swissimage": "Couverture haute résolution de la Suisse.",
            "openaerialmap": "Imagerie ouverte CC BY ; certaines zones peuvent être absentes.",
            "copernicus": "Entrez votre identifiant d’instance Sentinel Hub (résolution 10 m).",
            "custom": "Entrez une URL XYZ contenant {z}, {x} et {y}.",
        }
        self.provider_help.configure(text=messages[provider])

    def set_busy(self, busy: bool, text: str = "") -> None:
        self.busy = busy
        self.generate_button.configure(state="disabled" if busy else "normal")
        self.status.configure(text=text or ("Traitement…" if busy else "Prêt"))
        self.progress["value"] = 0 if busy else 100

    def report_progress(self, done: int, total: int, stage: str) -> None:
        percent = 0 if total <= 0 else max(0, min(100, done * 100 / total))
        self.after(0, lambda: self._show_progress(percent, stage, done, total))

    def _show_progress(self, percent: float, stage: str, done: int, total: int) -> None:
        self.progress["value"] = percent
        self.status.configure(text=f"{stage} : {done}/{total} ({percent:.0f} %)")
        self.update_idletasks()

    def run_task(self, job, done, text: str) -> None:
        if self.busy:
            return
        self.set_busy(True, text)

        def worker():
            try:
                value = job()
                self.after(0, lambda: self._task_done(done, value, None))
            except Exception as exc:
                self.after(0, lambda exc=exc: self._task_done(done, None, exc))

        threading.Thread(target=worker, daemon=True).start()

    def _task_done(self, done, value, error) -> None:
        self.set_busy(False)
        if error:
            messagebox.showerror("THERMAL", str(error))
            self.status.configure(text=f"Erreur : {error}")
        else:
            done(value)

    def show_image(self, widget: ZoomPreview, image: Image.Image, maximum=None) -> None:
        widget.set_image(image)

    def refresh_all(self) -> None:
        self.radio = detect_radio()
        if self.radio:
            self.radio_label.configure(text=f"TX16S détectée : {self.radio}")
            widget_ok = (self.radio / "WIDGETS" / "THERMAL" / "main.lua").exists()
            self.widget_status.configure(text="Widget : installé" if widget_ok else "Widget : non installé")
            values = ["Bibliothèque du PC", f"TX16S ({self.radio})"]
        else:
            self.radio_label.configure(text="TX16S : non connectée")
            self.widget_status.configure(text="Widget : radio non connectée")
            values = ["Bibliothèque du PC"]
        previous = self.source.current()
        self.source["values"] = values
        self.source.current(previous if 0 <= previous < len(values) else 0)
        self.refresh_list()

    def current_root(self) -> Path:
        if self.source.current() == 1 and self.radio:
            return self.radio / "WIDGETS" / "THERMAL" / "MAPS"
        return LOCAL_MAPS

    def refresh_list(self) -> None:
        self.entries = read_index(self.current_root())
        self.listbox.delete(0, "end")
        for entry in self.entries:
            self.listbox.insert("end", f"{entry['label']}   ({entry['size'] // 1000} × {entry['size'] // 1000} km)")
        self.installed_preview.set_message("Aucune carte." if not self.entries else "Sélectionnez une carte.")

    def selected_entry(self) -> dict | None:
        selection = self.listbox.curselection()
        return self.entries[selection[0]] if selection else None

    def preview_selected(self) -> None:
        entry = self.selected_entry()
        if not entry:
            return
        try:
            image = make_pack_preview(self.current_root() / entry["slug"])
            self.show_image(self.installed_preview, image, (390, 300))
        except Exception as exc:
            self.installed_preview.set_message(str(exc))

    def preview_new(self) -> None:
        name, url = self.name_var.get().strip(), self.url_var.get().strip()
        provider = PROVIDERS[self.provider.get()]
        parameter = self.provider_parameter.get().strip()
        if not name or not url:
            messagebox.showwarning("THERMAL", "Indiquez le nom et le lien Google Maps.")
            return

        def job():
            lat, lon = engine.resolve_google_url(url)
            image = engine.build_source(lat, lon, 5000, self.report_progress,
                                        provider, parameter)
            return name, lat, lon, image, provider, parameter

        def done(value):
            self.pending = value
            _, lat, lon, image, selected_provider, _ = value
            self.show_image(self.preview, image)
            actual = engine.automatic_provider(lat, lon) if selected_provider == "auto" else selected_provider
            self.status.configure(text=f"Aperçu {actual} : {lat:.6f}, {lon:.6f} — zone 5 × 5 km")

        self.run_task(job, done, "Téléchargement de l’aperçu satellite…")

    def generate_new(self) -> None:
        current_provider = PROVIDERS[self.provider.get()]
        current_parameter = self.provider_parameter.get().strip()
        if (not self.pending or self.pending[0] != self.name_var.get().strip()
                or self.pending[4] != current_provider or self.pending[5] != current_parameter):
            messagebox.showinfo("THERMAL", "Affichez d’abord l’aperçu de cette carte.")
            return
        name, lat, lon, source, provider, parameter = self.pending
        slug = engine.safe_slug(name)
        copy_to_radio = self.auto_copy.get()
        radio = self.radio

        def job():
            engine.save_pack(source, LOCAL_MAPS / slug, self.report_progress)
            engine.update_index(LOCAL_MAPS, slug, name[:20], lat, lon, 5000)
            copied = False
            if copy_to_radio and radio:
                if not (radio / "WIDGETS" / "THERMAL" / "main.lua").exists():
                    raise RuntimeError("Le widget THERMAL n’est pas installé. Utilisez le bouton d’installation.")
                target = radio / "WIDGETS" / "THERMAL" / "MAPS"
                engine.install_pack(LOCAL_MAPS / slug, target, slug, name[:20], lat, lon, 5000,
                                    self.report_progress)
                copied = True
            return copied

        def done(copied):
            self.refresh_all()
            destination = "PC et TX16S" if copied else "bibliothèque du PC"
            self.status.configure(text=f"Carte {name} créée dans : {destination}")
            messagebox.showinfo("THERMAL", f"Carte « {name} » créée avec 4 zooms.\nDestination : {destination}.")

        self.run_task(job, done, "Création des 4 niveaux de zoom…")

    def install_widget(self) -> None:
        self.refresh_all()
        if not self.radio:
            messagebox.showwarning("THERMAL", "Connectez la TX16S en mode stockage USB.")
            return
        if not messagebox.askyesno("THERMAL", "Installer ou mettre à jour le widget THERMAL sur la TX16S ?\n\nLes triangles et cartes présents seront conservés."):
            return
        widget = self.radio / "WIDGETS" / "THERMAL"
        tools = self.radio / "SCRIPTS" / "TOOLS"
        widget.mkdir(parents=True, exist_ok=True)
        tools.mkdir(parents=True, exist_ok=True)
        shutil.copy2(PACKAGE / "WIDGETS" / "THERMAL" / "main.lua", widget / "main.lua")
        logo = PACKAGE / "WIDGETS" / "THERMAL" / "logo.png"
        if logo.exists():
            shutil.copy2(logo, widget / "logo.png")
        shutil.copy2(PACKAGE / "SCRIPTS" / "TOOLS" / "THMCFG.lua", tools / "THMCFG.lua")
        for stale in (widget / "main.luac", tools / "THMCFG.luac"):
            if stale.exists():
                stale.rename(stale.with_suffix(stale.suffix + ".ancienne"))
        (widget / "MAPS").mkdir(exist_ok=True)
        self.refresh_all()
        messagebox.showinfo("THERMAL", "Widget THERMAL installé ou mis à jour.")

    def copy_selected(self) -> None:
        entry = self.selected_entry()
        if not entry:
            messagebox.showwarning("THERMAL", "Sélectionnez une carte du PC.")
            return
        if self.source.current() != 0:
            messagebox.showinfo("THERMAL", "Cette carte est déjà sur la TX16S.")
            return
        self.refresh_all()
        if not self.radio:
            messagebox.showwarning("THERMAL", "TX16S non connectée.")
            return
        if not (self.radio / "WIDGETS" / "THERMAL" / "main.lua").exists():
            if messagebox.askyesno("THERMAL", "Le widget manque sur la TX16S. L’installer maintenant ?"):
                self.install_widget()
            else:
                return
        target = self.radio / "WIDGETS" / "THERMAL" / "MAPS"

        def job():
            engine.install_pack(LOCAL_MAPS / entry["slug"], target, entry["slug"], entry["label"],
                                entry["lat"], entry["lon"], entry["size"], self.report_progress)
            return entry["label"]

        def done(label):
            self.refresh_all()
            self.status.configure(text=f"Carte {label} copiée sur la TX16S.")
            messagebox.showinfo("THERMAL", f"Carte « {label} » copiée sur la TX16S.")

        self.run_task(job, done, "Préparation de la copie vers la TX16S…")

    def delete_selected(self) -> None:
        entry = self.selected_entry()
        if not entry:
            messagebox.showwarning("THERMAL", "Sélectionnez une carte à effacer.")
            return
        root = self.current_root()
        place = "la TX16S" if self.source.current() == 1 else "le PC"
        if not messagebox.askyesno("Confirmer la suppression",
                                   f"Effacer définitivement « {entry['label']} » de {place} ?"):
            return
        folder = root / entry["slug"]

        def job():
            delete_pack(folder, self.report_progress)
            remove_from_index(root, entry["slug"])
            return entry["label"]

        def done(label):
            self.refresh_list()
            self.status.configure(text=f"Carte {label} effacée de {place}.")
            messagebox.showinfo("THERMAL", f"Carte « {label} » effacée de {place}.")

        self.run_task(job, done, f"Préparation de l’effacement de {entry['label']}…")


if __name__ == "__main__":
    Manager().mainloop()
