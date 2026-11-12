#!/usr/bin/env python3
"""Sprites détourés -> modèles 3D (GLB) avec TripoSR, sur CPU.

Entrées acceptées (fichiers ou dossiers, parcourus récursivement) :
  - des images PNG / WebP **déjà détourées** (fond transparent), telles
    qu'exportées par Atelier Sprites ;
  - des zips d'export d'Atelier Sprites (`zimut_sprites_<id>.zip`) : toutes
    les images qu'ils contiennent sont traitées.

Les images strictement identiques (un héros est copié dans `players/` et dans
`nations/heros/`) ne sont converties qu'une fois.

Sorties, dans le dossier `--sorties`, un sous-dossier par sprite :
  - `<nom>/<nom>.glb`             modèle texturé, léger (Godot, Blender…) ;
  - `<nom>/<nom>.fbx`             FBX avec texture intégrée ;
  - `<nom>/<nom>_mixamo_obj.zip`  OBJ + MTL + PNG, à déposer tel quel sur Mixamo ;
  - `<nom>/<nom>_texture.png`     la texture seule ;
  - `preparees/<nom>.png`         l'image réellement donnée au modèle (diagnostic) ;
  - `resume.md`                   le tableau récapitulatif.
Le personnage regarde vers +Z, pieds sur y = 0, 1,8 m de haut.

Exemple :
    python sprites_vers_3d.py sprites_3d/entrees --sorties sorties_3d \
        --triposr /chemin/vers/TripoSR
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import io
import os
import sys
import time
import traceback
import types
import zipfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import postraitement  # noqa: E402

EXTENSIONS_IMAGE = {".png", ".webp"}
# Gris neutre attendu par TripoSR derrière le sujet.
FOND_GRIS = 0.5
# Garde-fou : une image de zip plus grosse que ça n'est pas un sprite.
TAILLE_MAX_OCTETS = 40 * 1024 * 1024


@dataclass
class Entree:
    """Une image à convertir."""

    nom: str  # nom de sortie, sans extension
    origine: str  # chemin lisible (fichier, ou zip!chemin interne)
    octets: bytes


@dataclass
class Resultat:
    nom: str
    origine: str
    ok: bool
    detail: str
    secondes: float = 0.0


# --------------------------------------------------------------------------
# Collecte des entrées
# --------------------------------------------------------------------------

def _est_image(nom: str) -> bool:
    return Path(nom).suffix.lower() in EXTENSIONS_IMAGE


def _lire_zip(chemin: Path) -> list[tuple[str, str, bytes]]:
    """Retourne (nom de base, origine, octets) pour chaque image du zip."""
    trouves = []
    with zipfile.ZipFile(chemin) as z:
        for info in sorted(z.infolist(), key=lambda i: i.filename):
            if info.is_dir() or not _est_image(info.filename):
                continue
            if info.file_size > TAILLE_MAX_OCTETS:
                print(f"  ! ignoré (trop gros) : {chemin.name}!{info.filename}")
                continue
            # On ne garde que le nom de base : rien n'est extrait sur le disque.
            base = Path(info.filename.replace("\\", "/")).stem
            trouves.append((base, f"{chemin.name}!{info.filename}", z.read(info)))
    return trouves


def collecter(chemins: list[Path], filtre: str = "*") -> list[Entree]:
    """Rassemble les images, sans doublons de contenu, avec des noms uniques."""
    bruts: list[tuple[str, str, bytes]] = []
    fichiers: list[Path] = []
    for chemin in chemins:
        if chemin.is_dir():
            fichiers.extend(sorted(p for p in chemin.rglob("*") if p.is_file()))
        elif chemin.is_file():
            fichiers.append(chemin)
        else:
            print(f"  ! introuvable : {chemin}")

    for fichier in fichiers:
        if fichier.suffix.lower() == ".zip":
            try:
                bruts.extend(_lire_zip(fichier))
            except zipfile.BadZipFile:
                print(f"  ! zip illisible : {fichier}")
        elif _est_image(fichier.name):
            bruts.append((fichier.stem, str(fichier), fichier.read_bytes()))

    entrees: list[Entree] = []
    vus: set[str] = set()
    noms: dict[str, int] = {}
    for base, origine, octets in bruts:
        if not fnmatch.fnmatch(base, filtre):
            continue
        empreinte = hashlib.sha256(octets).hexdigest()
        if empreinte in vus:
            continue
        vus.add(empreinte)
        n = noms.get(base, 0) + 1
        noms[base] = n
        nom = base if n == 1 else f"{base}_{n}"
        entrees.append(Entree(nom=nom, origine=origine, octets=octets))
    return entrees


# --------------------------------------------------------------------------
# Préparation de l'image (équivalent du prétraitement de la démo TripoSR)
# --------------------------------------------------------------------------

class ImageNonDetouree(ValueError):
    pass


def _disque(rayon: int) -> np.ndarray:
    y, x = np.ogrid[-rayon: rayon + 1, -rayon: rayon + 1]
    return x * x + y * y <= rayon * rayon


def nettoyer_sprite(rgba: np.ndarray, rayon: int = 8, seuil_blanc: int = 215,
                    trou_max: int = 2500) -> np.ndarray:
    """Répare les défauts de détourage qui gênent TripoSR.

    Le détourage laisse (1) un liseré blanc opaque le long des bords et (2) de
    fines fentes transparentes autour des poches, ceintures et plis, que le
    modèle prend pour du vide. On retire le blanc relié à la transparence, puis
    on comble les fentes de moins de 2 x `rayon` pixels et les petits trous
    enfermés, avec la moyenne pondérée des couleurs voisines.
    """
    from scipy import ndimage as ndi

    a = rgba.copy()
    opaque = a[..., 3] > 8
    # 1. liseré blanc : pixels très clairs reliés, par du clair, à la transparence
    blanc = opaque & (a[..., :3].min(axis=2) >= seuil_blanc)
    etiquettes, _ = ndi.label(~opaque | blanc)
    touche = np.unique(etiquettes[~opaque])
    a[np.isin(etiquettes, touche[touche > 0]) & blanc, 3] = 0
    # un dernier pixel clair en bordure
    opaque = a[..., 3] > 8
    a[opaque & (a[..., :3].min(axis=2) >= 190)
      & ndi.binary_dilation(~opaque, iterations=2), 3] = 0
    opaque = a[..., 3] > 8

    # 2. fentes (fermeture morphologique) + petits trous enfermés
    p = rayon + 2
    ferme = ndi.binary_closing(np.pad(opaque, p), structure=_disque(rayon))[p:-p, p:-p]
    a_combler = ferme & ~opaque
    etiquettes, n = ndi.label(~opaque)
    if n:
        bord = set(np.unique(np.r_[etiquettes[0], etiquettes[-1],
                                   etiquettes[:, 0], etiquettes[:, -1]]))
        aires = ndi.sum(np.ones_like(etiquettes), etiquettes, index=np.arange(1, n + 1))
        petits = [i + 1 for i in range(n) if (i + 1) not in bord and aires[i] <= trou_max]
        if petits:
            a_combler |= np.isin(etiquettes, petits)
    if a_combler.any():
        masque = opaque.astype(float)
        sigma = max(2.0, rayon / 2)
        poids = np.maximum(ndi.gaussian_filter(masque, sigma), 1e-6)
        for c in range(3):
            lisse = ndi.gaussian_filter(a[..., c].astype(float) * masque, sigma) / poids
            a[..., c] = np.where(a_combler, lisse, a[..., c]).clip(0, 255).astype(np.uint8)
        a[a_combler, 3] = 255
    return a


def preparer_avec_reference(octets: bytes, marge: float = 0.85, seuil_alpha: int = 8,
                            nettoyer: bool = True):
    """Prépare l'image pour TripoSR. Retourne (image, pixels RGB opaques du sprite).

    Le sprite est nettoyé, recadré, centré dans un carré et posé sur fond gris.
    `marge` : part du carré occupée par le sprite (0.3 à 1.0), le « Foreground
    Ratio » de la démo Hugging Face. Les pixels opaques servent ensuite de
    référence pour recaler les couleurs du modèle.
    """
    if not 0.3 <= marge <= 1.0:
        raise ValueError("--marge doit être entre 0.3 et 1.0")
    image = Image.open(io.BytesIO(octets))
    image.load()
    rgba = np.array(image.convert("RGBA"))
    if rgba[..., 3].min() == 255:
        raise ImageNonDetouree(
            "pas de transparence : détoure d'abord l'image dans Atelier Sprites"
        )
    if nettoyer:
        rgba = nettoyer_sprite(rgba)
    alpha = rgba[..., 3]
    ys, xs = np.where(alpha > seuil_alpha)
    if ys.size == 0:
        raise ValueError("image entièrement transparente")
    sujet = rgba[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]
    reference = sujet[sujet[..., 3] > seuil_alpha][:, :3]

    h, w = sujet.shape[:2]
    cote = max(h, w)
    total = max(cote, int(round(cote / marge)))
    carre = np.zeros((total, total, 4), dtype=np.uint8)
    y0 = (total - h) // 2
    x0 = (total - w) // 2
    carre[y0: y0 + h, x0: x0 + w] = sujet

    flottant = carre.astype(np.float32) / 255.0
    a = flottant[..., 3:4]
    rgb = flottant[..., :3] * a + (1.0 - a) * FOND_GRIS
    return Image.fromarray((rgb * 255.0 + 0.5).astype(np.uint8)), reference


def sprite_nettoye(octets: bytes, seuil_alpha: int = 8, nettoyer: bool = True) -> np.ndarray:
    """Sprite RGBA nettoyé et recadré, pour être plaqué sur la face avant."""
    image = Image.open(io.BytesIO(octets))
    image.load()
    rgba = np.array(image.convert("RGBA"))
    if nettoyer:
        rgba = nettoyer_sprite(rgba)
    ys, xs = np.where(rgba[..., 3] > seuil_alpha)
    return rgba[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]


def preparer(octets: bytes, marge: float = 0.85, seuil_alpha: int = 8,
             nettoyer: bool = True) -> Image.Image:
    return preparer_avec_reference(octets, marge, seuil_alpha, nettoyer)[0]


# --------------------------------------------------------------------------
# Modèle
# --------------------------------------------------------------------------

def _installer_marching_cubes() -> None:
    """Fournit `torchmcubes.marching_cubes` à TripoSR à partir de PyMCubes.

    TripoSR dépend de torchmcubes, une extension C++ à compiler contre la
    version exacte de PyTorch installée. PyMCubes (dont torchmcubes est dérivé)
    s'installe tout prêt et donne le même maillage : mêmes faces, même sens
    des normales, sommets à moins de 0,05 voxel (vérifié contre torchmcubes).
    Si le vrai torchmcubes est installé, c'est lui qui est utilisé.
    """
    try:
        import torchmcubes  # noqa: F401
        return
    except ImportError:
        pass
    import mcubes
    import torch

    def marching_cubes(volume, seuil):
        sommets, faces = mcubes.marching_cubes(
            volume.detach().cpu().numpy().astype(np.float32), float(seuil)
        )
        # torchmcubes rend les sommets dans l'ordre (x, y, z) pour un volume
        # indexé [z, y, x] : on inverse donc l'ordre des axes de PyMCubes.
        sommets = np.ascontiguousarray(sommets[:, ::-1], dtype=np.float32)
        return torch.from_numpy(sommets), torch.from_numpy(faces.astype(np.int64))

    module = types.ModuleType("torchmcubes")
    module.marching_cubes = marching_cubes
    sys.modules["torchmcubes"] = module


def charger_modele(dossier_triposr: Path | None, modele: str, taille_lot: int):
    """Charge TripoSR sur CPU. Les imports lourds sont faits ici seulement."""
    if dossier_triposr is not None:
        sys.path.insert(0, str(dossier_triposr))
    # tsr.utils importe rembg (détourage automatique) dès le chargement, alors
    # que nos sprites sont déjà détourés : un module vide évite d'installer
    # rembg et onnxruntime pour rien.
    sys.modules.setdefault("rembg", types.ModuleType("rembg"))
    _installer_marching_cubes()

    import torch
    from tsr.system import TSR

    torch.set_num_threads(max(1, os.cpu_count() or 1))
    modele_tsr = TSR.from_pretrained(
        modele, config_name="config.yaml", weight_name="model.ckpt"
    )
    modele_tsr.renderer.set_chunk_size(taille_lot)
    modele_tsr.to("cpu")
    modele_tsr.eval()
    return modele_tsr


def generer_maillage(modele_tsr, image: Image.Image, resolution: int, seuil_densite: float):
    """Génère le maillage (couleurs de sommets), personnage face à +Z, axe Y vers le haut."""
    import torch
    import trimesh
    from tsr.utils import to_gradio_3d_orientation

    with torch.no_grad():
        codes = modele_tsr([image], device="cpu")
    maillage = modele_tsr.extract_mesh(
        codes, True, resolution=resolution, threshold=seuil_densite
    )[0]
    if len(maillage.faces) == 0:
        raise RuntimeError("le modèle n'a produit aucune surface")
    maillage = to_gradio_3d_orientation(maillage)
    # La démo orientée pour son visionneur regarde vers -Z ; glTF et Mixamo attendent +Z.
    maillage.apply_transform(trimesh.transformations.rotation_matrix(np.pi, [0, 1, 0]))
    return maillage


# --------------------------------------------------------------------------
# Programme principal
# --------------------------------------------------------------------------

def ecrire_resume(resultats: list[Resultat], dossier: Path) -> str:
    reussis = sum(1 for r in resultats if r.ok)
    lignes = [
        f"## Sprites vers 3D : {reussis}/{len(resultats)} convertis",
        "",
        "| Sprite | État | Détail | Durée |",
        "|---|---|---|---|",
    ]
    for r in resultats:
        etat = "OK" if r.ok else "ÉCHEC"
        duree = f"{r.secondes:.0f} s" if r.secondes else ""
        lignes.append(f"| `{r.nom}` | {etat} | {r.detail} | {duree} |")
    texte = "\n".join(lignes) + "\n"
    (dossier / "resume.md").write_text(texte, encoding="utf-8")
    resume_github = os.environ.get("GITHUB_STEP_SUMMARY")
    if resume_github:
        with open(resume_github, "a", encoding="utf-8") as f:
            f.write(texte)
    return texte


def lire_arguments(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Sprites détourés -> modèles 3D GLB / FBX / OBJ (TripoSR, CPU)")
    p.add_argument("entrees", nargs="*", type=Path,
                   help="images, zips ou dossiers (défaut : sprites_3d/entrees)")
    p.add_argument("--liste", type=Path,
                   help="fichier texte : un chemin d'entrée par ligne")
    p.add_argument("--sorties", type=Path, default=Path("sorties_3d"))
    p.add_argument("--filtre", default="*",
                   help="ne traiter que les noms correspondants, ex. 'assassin*'")
    p.add_argument("--resolution", type=int, default=256,
                   help="finesse du maillage, 32 à 320 (défaut 256)")
    p.add_argument("--marge", type=float, default=0.85,
                   help="part du cadre occupée par le sprite (défaut 0.85)")
    p.add_argument("--seuil-densite", type=float, default=25.0,
                   help="seuil de surface de TripoSR (défaut 25 ; plus bas = plus épais)")
    p.add_argument("--limite", type=int, default=0,
                   help="nombre maximal de sprites à traiter (0 = tous)")
    p.add_argument("--triposr", type=Path, default=None,
                   help="dossier du dépôt TripoSR (s'il n'est pas déjà importable)")
    p.add_argument("--modele", default="stabilityai/TripoSR",
                   help="identifiant Hugging Face ou dossier local des poids")
    p.add_argument("--taille-lot", type=int, default=8192,
                   help="taille des lots d'évaluation (plus petit = moins de mémoire)")
    p.add_argument("--faces", type=int, default=postraitement.Options.faces,
                   help="triangles du modèle final (défaut 25000)")
    p.add_argument("--texture", type=int, default=postraitement.Options.texture,
                   help="côté de la texture en pixels (défaut 2048)")
    p.add_argument("--brut", action="store_true",
                   help="ne pas post-traiter : écrit seulement le maillage brut de TripoSR")
    p.add_argument("--garder-brut", action="store_true",
                   help="écrire aussi le maillage brut (<nom>_brut.glb)")
    p.add_argument("--sans-fbx", action="store_true", help="ne pas écrire de FBX")
    p.add_argument("--sans-nettoyage", action="store_true",
                   help="ne pas réparer le détourage (liseré blanc, fentes) avant TripoSR")
    p.add_argument("--sans-projection", action="store_true",
                   help="ne pas plaquer le sprite net sur la face avant du modèle")
    p.add_argument("--sans-calage-couleurs", action="store_true",
                   help="ne pas recaler saturation et luminosité sur celles du sprite")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = lire_arguments(argv)
    if not 32 <= args.resolution <= 320:
        print("--resolution doit être entre 32 et 320")
        return 2

    chemins = list(args.entrees)
    if args.liste:
        chemins += [Path(l.strip()) for l in args.liste.read_text(encoding="utf-8").splitlines()
                    if l.strip()]
    if not chemins:
        chemins = [Path("sprites_3d/entrees")]

    entrees = collecter(chemins, args.filtre)
    if args.limite > 0:
        entrees = entrees[: args.limite]
    if not entrees:
        print("Aucun sprite à convertir (dossier vide ou filtre trop strict).")
        return 1
    print(f"{len(entrees)} sprite(s) à convertir.")

    args.sorties.mkdir(parents=True, exist_ok=True)
    dossier_preparees = args.sorties / "preparees"
    dossier_preparees.mkdir(exist_ok=True)

    # Préparation d'abord : une image non détourée est signalée sans charger le modèle.
    resultats: list[Resultat] = []
    pretes: list[tuple[Entree, str, Image.Image, np.ndarray]] = []
    noms_pris: set[str] = set()
    for e in entrees:
        try:
            image, reference = preparer_avec_reference(
                e.octets, args.marge, nettoyer=not args.sans_nettoyage)
            nom = postraitement.nom_sur(e.nom)
            base, n = nom, 1
            while nom in noms_pris:  # deux noms différents peuvent donner le même nom sûr
                n += 1
                nom = f"{base}_{n}"
            noms_pris.add(nom)
            image.save(dossier_preparees / f"{nom}.png")
            pretes.append((e, nom, image, reference))
        except Exception as erreur:  # noqa: BLE001 - une image ratée ne bloque pas les autres
            print(f"  ! {e.nom} : {erreur}")
            resultats.append(Resultat(e.nom, e.origine, False, str(erreur)))

    options = postraitement.Options(faces=args.faces, texture=args.texture,
                                    fbx=not args.sans_fbx)
    if pretes:
        debut = time.time()
        print("Chargement de TripoSR…")
        modele_tsr = charger_modele(args.triposr, args.modele, args.taille_lot)
        print(f"Modèle prêt en {time.time() - debut:.0f} s.")
        for i, (e, nom, image, reference) in enumerate(pretes, 1):
            debut = time.time()
            print(f"[{i}/{len(pretes)}] {nom}…", flush=True)
            try:
                maillage = generer_maillage(modele_tsr, image, args.resolution,
                                            args.seuil_densite)
                dossier = args.sorties / nom
                dossier.mkdir(parents=True, exist_ok=True)
                if args.brut or args.garder_brut:
                    maillage.export(str(dossier / f"{nom}_brut.glb"))
                if args.brut:
                    detail = (f"brut : {len(maillage.vertices)} sommets, "
                              f"{len(maillage.faces)} faces")
                else:
                    sprite = None if args.sans_projection else sprite_nettoye(
                        e.octets, nettoyer=not args.sans_nettoyage)
                    res = postraitement.postraiter(
                        maillage, nom, dossier, options,
                        None if args.sans_calage_couleurs else reference, sprite)
                    detail = f"{res.faces} faces ; {', '.join(res.fichiers)}"
                    for a in res.avertissements:
                        detail += f" ; ⚠ {a}"
                        print(f"  ! {a}")
                resultats.append(Resultat(nom, e.origine, True, detail, time.time() - debut))
                print(f"    {detail} en {time.time() - debut:.0f} s")
            except Exception as erreur:  # noqa: BLE001
                traceback.print_exc()
                print(f"  ! {nom} : {erreur}")
                resultats.append(Resultat(nom, e.origine, False, str(erreur),
                                          time.time() - debut))

    print()
    print(ecrire_resume(resultats, args.sorties))
    return 0 if all(r.ok for r in resultats) else 1


if __name__ == "__main__":
    sys.exit(main())
