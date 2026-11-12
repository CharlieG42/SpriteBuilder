#!/usr/bin/env python3
"""Post-traitement d'un maillage TripoSR : modèle propre, léger et texturé.

Le maillage brut de TripoSR a trois défauts pour un usage en jeu ou dans
Mixamo : des fragments flottants, trop de triangles (90 000 et plus) et des
couleurs portées par les sommets, que les logiciels interprètent
différemment et que Mixamo ignore. Ce module :

  1. garde la pièce principale et retire les fragments ;
  2. lisse légèrement la surface (filtre de Taubin, sans rétrécir le modèle) ;
  3. oriente le personnage face à +Z, pieds sur y = 0, à l'échelle de 1,8 m ;
  4. réduit le nombre de triangles ;
  5. déplie le maillage (UV) et « cuit » les couleurs dans une vraie texture,
     en les lisant sur le maillage dense d'origine : le détail est conservé ;
  6. écrit :
       <nom>.glb              modèle texturé (Godot, Blender, visionneuses) ;
       <nom>.fbx              FBX avec texture intégrée (si Blender est là) ;
       <nom>_mixamo_obj.zip   OBJ + MTL + PNG, à déposer tel quel sur Mixamo ;
       <nom>_texture.png      la texture seule.

Utilisation seule, sur un GLB déjà produit (ex. issu de la démo Hugging Face,
dont le personnage regarde vers -Z, d'où --tourner 180) :

    python postraitement.py Zimut.glb --sorties sorties_3d --tourner 180
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import unicodedata
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HAUTEUR_M = 1.8


@dataclass
class Options:
    faces: int = 25000          # triangles du modèle final
    texture: int = 2048         # côté de la texture, en pixels
    lissage: int = 10           # passes du filtre de Taubin (0 = aucun)
    hauteur: float = HAUTEUR_M  # hauteur du personnage, en mètres
    fbx: bool = True            # écrire aussi un FBX (nécessite Blender / bpy)
    tourner: float = 0.0        # rotation préalable autour de Y, en degrés


@dataclass
class Resultat:
    sommets: int = 0
    faces: int = 0
    fichiers: list[str] = field(default_factory=list)
    avertissements: list[str] = field(default_factory=list)


def nom_sur(nom: str) -> str:
    """Nom de fichier sans accent ni espace (Mixamo n'aime pas les deux)."""
    ascii_ = unicodedata.normalize("NFKD", nom).encode("ascii", "ignore").decode()
    propre = re.sub(r"[^A-Za-z0-9_-]+", "_", ascii_).strip("_")
    return propre or "sprite"


# --------------------------------------------------------------------------
# Géométrie
# --------------------------------------------------------------------------

def garder_pieces_principales(maillage, part_min: float = 0.02):
    """Retire les fragments : pièces de moins de `part_min` des triangles."""
    import trimesh

    pieces = maillage.split(only_watertight=False)
    if len(pieces) <= 1:
        return maillage
    total = sum(len(p.faces) for p in pieces)
    gardees = [p for p in pieces if len(p.faces) >= part_min * total]
    if not gardees:  # aucune pièce dominante : on garde au moins la plus grosse
        gardees = [max(pieces, key=lambda p: len(p.faces))]
    return trimesh.util.concatenate(gardees)


def lisser(maillage, passes: int) -> None:
    """Lissage de Taubin sur place : atténue les stries sans rétrécir."""
    if passes <= 0:
        return
    import trimesh

    couleurs = maillage.visual.vertex_colors.copy()
    trimesh.smoothing.filter_taubin(maillage, lamb=0.5, nu=-0.53, iterations=passes)
    maillage.visual.vertex_colors = couleurs


def tourner_y(sommets: np.ndarray, degres: float) -> np.ndarray:
    a = np.radians(degres)
    r = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
    return sommets @ r.T


def calage_echelle(sommets: np.ndarray, hauteur: float):
    """Facteur et décalage tels que `sommets * facteur + decalage` ait ses pieds sur
    y = 0, soit centré en x et z, et fasse `hauteur` mètres de haut."""
    bas, haut = sommets.min(axis=0), sommets.max(axis=0)
    facteur = hauteur / max(haut[1] - bas[1], 1e-9)
    centre = (bas + haut) / 2
    decalage = -np.array([centre[0], bas[1], centre[2]]) * facteur
    return facteur, decalage


def decimer(sommets: np.ndarray, faces: np.ndarray, cible: int):
    if len(faces) <= cible:
        return sommets, faces
    import fast_simplification

    reduction = 1.0 - cible / len(faces)
    s, f = fast_simplification.simplify(
        sommets.astype(np.float32), faces.astype(np.int32), target_reduction=reduction
    )
    return np.asarray(s, dtype=np.float32), np.asarray(f, dtype=np.int64)


def normales_sommets(sommets: np.ndarray, faces: np.ndarray) -> np.ndarray:
    """Normales lisses (pondérées par l'aire), sans NaN même sur des triangles dégénérés."""
    tri = sommets[faces].astype(np.float64)
    nf = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])  # longueur = 2 x aire
    n = np.zeros((len(sommets), 3))
    for k in range(3):
        np.add.at(n, faces[:, k], nf)
    longueur = np.linalg.norm(n, axis=1, keepdims=True)
    n = np.where(longueur > 1e-12, n / np.maximum(longueur, 1e-12), np.array([0.0, 1.0, 0.0]))
    return n.astype(np.float32)


def retirer_triangles_plats(sommets: np.ndarray, faces: np.ndarray):
    """Retire les triangles d'aire nulle et les sommets devenus inutiles."""
    tri = sommets[faces].astype(np.float64)
    aire = np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1) / 2
    faces = faces[aire > 1e-10]
    utiles, nouveaux = np.unique(faces, return_inverse=True)
    return sommets[utiles], nouveaux.reshape(-1, 3).astype(np.int64)


def deplier(sommets: np.ndarray, faces: np.ndarray, taille_texture: int):
    """Dépliage UV avec xatlas. Retourne (indices des sommets d'origine, faces, uv)."""
    import xatlas

    atlas = xatlas.Atlas()
    atlas.add_mesh(sommets.astype(np.float32), faces.astype(np.uint32))
    chart = xatlas.ChartOptions()
    pack = xatlas.PackOptions()
    pack.resolution = taille_texture
    pack.padding = 4
    pack.bilinear = True
    atlas.generate(chart, pack, verbose=False)
    vmap, indices, uvs = atlas[0]
    return vmap.astype(np.int64), indices.astype(np.int64), uvs.astype(np.float32)


# --------------------------------------------------------------------------
# Texture
# --------------------------------------------------------------------------

def _rgb_vers_hsv(rgb: np.ndarray) -> np.ndarray:
    """(N, 3) RGB 0-255 -> (N, 3) HSV 0-255 (via Pillow)."""
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8).reshape(-1, 1, 3), "RGB")
    return np.asarray(img.convert("HSV")).reshape(-1, 3).astype(np.float32)


def _hsv_vers_rgb(hsv: np.ndarray) -> np.ndarray:
    img = Image.fromarray(np.clip(hsv, 0, 255).astype(np.uint8).reshape(-1, 1, 3), "HSV")
    return np.asarray(img.convert("RGB")).reshape(-1, 3).astype(np.float32)


def caler_couleurs(couleurs: np.ndarray, reference: np.ndarray,
                   gain_max: float = 1.6) -> np.ndarray:
    """Rend au modèle la saturation et la luminosité du sprite d'origine.

    TripoSR sort des couleurs ternes et sombres par rapport à l'image fournie.
    Seules la saturation et la luminosité moyennes sont recalées, par un gain
    unique : les teintes ne bougent pas (un recalage canal par canal les déforme).
    `couleurs` : (N, 3) pixels de la texture ; `reference` : (M, 3) pixels
    opaques du sprite. Le gain est borné entre 1 et `gain_max` : on ne
    ternit jamais.
    """
    hsv = _rgb_vers_hsv(couleurs)
    ref = _rgb_vers_hsv(reference)
    gain_s = np.clip(ref[:, 1].mean() / max(hsv[:, 1].mean(), 1.0), 1.0, gain_max)
    gain_v = np.clip(ref[:, 2].mean() / max(hsv[:, 2].mean(), 1.0), 1.0, gain_max)
    hsv[:, 1] *= gain_s
    hsv[:, 2] *= gain_v
    return _hsv_vers_rgb(hsv)


def cuire_texture(positions: np.ndarray, faces: np.ndarray, uvs: np.ndarray,
                  denses_pos: np.ndarray, denses_couleurs: np.ndarray,
                  taille: int, reference: np.ndarray | None = None) -> Image.Image:
    """Peint la texture : chaque pixel prend la couleur du maillage dense voisin.

    Convention UV : origine en bas à gauche (v vers le haut), comme trimesh
    et OBJ ; la ligne 0 de l'image est donc en haut (v = 1).
    """
    from scipy import ndimage as ndi
    from scipy.spatial import cKDTree

    pts = np.stack([uvs[:, 0] * taille, (1.0 - uvs[:, 1]) * taille], axis=1)
    carte = Image.new("I", (taille, taille), 0)
    dessin = ImageDraw.Draw(carte)
    for i, tri in enumerate(faces):
        dessin.polygon([tuple(pts[t]) for t in tri], fill=i + 1)
    ids = np.asarray(carte, dtype=np.int64)
    ys, xs = np.nonzero(ids)
    tri = faces[ids[ys, xs] - 1]
    p = np.stack([xs + 0.5, ys + 0.5], axis=1)
    a, b, c = pts[tri[:, 0]], pts[tri[:, 1]], pts[tri[:, 2]]
    v0, v1, v2 = b - a, c - a, p - a
    d = v0[:, 0] * v1[:, 1] - v1[:, 0] * v0[:, 1]
    d = np.where(np.abs(d) < 1e-12, 1e-12, d)
    w1 = (v2[:, 0] * v1[:, 1] - v1[:, 0] * v2[:, 1]) / d
    w2 = (v0[:, 0] * v2[:, 1] - v2[:, 0] * v0[:, 1]) / d
    bary = np.clip(np.stack([1 - w1 - w2, w1, w2], axis=1), 0.0, None)
    bary /= bary.sum(axis=1, keepdims=True)
    pos3d = (positions[tri] * bary[:, :, None]).sum(axis=1)

    k = 4
    dist, voisins = cKDTree(denses_pos).query(pos3d, k=k, workers=-1)
    poids = 1.0 / (dist + 1e-6)
    poids /= poids.sum(axis=1, keepdims=True)
    couleurs = (denses_couleurs[voisins][:, :, :3].astype(np.float32)
                * poids[:, :, None]).sum(axis=1)

    if reference is not None and len(reference):
        couleurs = caler_couleurs(couleurs, reference)
    image = np.zeros((taille, taille, 3), dtype=np.float32)
    image[ys, xs] = couleurs
    # Marge : les pixels hors des morceaux copient le pixel peint le plus proche,
    # pour ne pas voir de lisière noire aux coutures.
    idx = ndi.distance_transform_edt(ids == 0, return_distances=False, return_indices=True)
    image = image[idx[0], idx[1]]
    return Image.fromarray(np.clip(image + 0.5, 0, 255).astype(np.uint8), "RGB")


# --------------------------------------------------------------------------
# Écriture
# --------------------------------------------------------------------------

def ecrire_obj_zip(dossier: Path, nom: str, sommets, normales, uvs, faces,
                   texture: Image.Image) -> Path:
    """OBJ + MTL + PNG dans un zip, au format attendu par Mixamo."""
    png = f"{nom}_texture.png"
    lignes = [f"mtllib {nom}.mtl", f"o {nom}"]
    lignes += [f"v {x:.6f} {y:.6f} {z:.6f}" for x, y, z in sommets]
    lignes += [f"vt {u:.6f} {v:.6f}" for u, v in uvs]
    lignes += [f"vn {x:.5f} {y:.5f} {z:.5f}" for x, y, z in normales]
    lignes += ["usemtl materiau", "s 1"]
    lignes += [f"f {a + 1}/{a + 1}/{a + 1} {b + 1}/{b + 1}/{b + 1} {c + 1}/{c + 1}/{c + 1}"
               for a, b, c in faces]
    mtl = (f"newmtl materiau\nKa 1.0 1.0 1.0\nKd 1.0 1.0 1.0\nKs 0.0 0.0 0.0\n"
           f"d 1.0\nillum 1\nmap_Kd {png}\n")
    chemin = dossier / f"{nom}_mixamo_obj.zip"
    import io
    tampon = io.BytesIO()
    texture.save(tampon, format="PNG")
    with zipfile.ZipFile(chemin, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(f"{nom}.obj", "\n".join(lignes) + "\n")
        z.writestr(f"{nom}.mtl", mtl)
        z.writestr(png, tampon.getvalue())
    return chemin


def interpreteur_blender() -> str:
    """Python qui sait importer bpy : variable PYTHON_BLENDER, sinon l'interpréteur courant."""
    return os.environ.get("PYTHON_BLENDER") or sys.executable


def ecrire_fbx(glb: Path, fbx: Path, nom: str) -> str | None:
    """Retourne None si tout va bien, sinon la raison de l'échec."""
    script = Path(__file__).resolve().with_name("convertir_fbx_blender.py")
    try:
        r = subprocess.run([interpreteur_blender(), str(script), str(glb), str(fbx), nom],
                           capture_output=True, text=True, timeout=600)
    except (subprocess.TimeoutExpired, OSError) as erreur:
        return f"FBX non écrit : {type(erreur).__name__}"
    if r.returncode != 0 or not fbx.exists():
        fin = (r.stderr or r.stdout).strip().splitlines()[-1:] or ["erreur inconnue"]
        return f"FBX non écrit : {fin[0][:160]}"
    return None


# --------------------------------------------------------------------------
# Chaîne complète
# --------------------------------------------------------------------------

def postraiter(maillage, nom: str, dossier: Path, opt: Options | None = None,
               reference: np.ndarray | None = None) -> Resultat:
    """Maillage TripoSR (couleurs de sommets) -> fichiers prêts à l'emploi.

    `reference` : pixels RGB opaques (M, 3) du sprite d'origine, pour recaler les
    couleurs ; None pour garder celles du modèle telles quelles.
    """
    import trimesh
    from trimesh.visual.material import PBRMaterial
    from trimesh.visual.texture import TextureVisuals

    opt = opt or Options()
    nom = nom_sur(nom)
    dossier.mkdir(parents=True, exist_ok=True)
    res = Resultat()

    if maillage.visual.kind != "vertex":
        raise ValueError("le maillage doit porter des couleurs de sommets")
    dense = garder_pieces_principales(maillage)
    lisser(dense, opt.lissage)
    pos = dense.vertices.astype(np.float64)
    if opt.tourner:
        pos = tourner_y(pos, opt.tourner)
    facteur, decalage = calage_echelle(pos, opt.hauteur)
    pos = pos * facteur + decalage
    couleurs = np.asarray(dense.visual.vertex_colors)

    s2, f2 = decimer(pos.astype(np.float32), np.asarray(dense.faces), opt.faces)
    s2, f2 = retirer_triangles_plats(s2, f2)
    # La décimation déplace un peu les extrémités : on recale pour que la hauteur soit
    # exacte, et on applique le même recalage au maillage dense qui fournit les couleurs.
    facteur, decalage = calage_echelle(s2, opt.hauteur)
    s2 = (s2 * facteur + decalage).astype(np.float32)
    pos = pos * facteur + decalage
    normales_lisses = normales_sommets(s2, f2)
    vmap, f3, uvs = deplier(s2, f2, opt.texture)
    s3 = s2[vmap]
    n3 = normales_lisses[vmap]
    res.sommets, res.faces = len(s3), len(f3)

    texture = cuire_texture(s3, f3, uvs, pos, couleurs, opt.texture, reference)
    chemin_tex = dossier / f"{nom}_texture.png"
    texture.save(chemin_tex)
    res.fichiers.append(chemin_tex.name)

    final = trimesh.Trimesh(
        vertices=s3, faces=f3, vertex_normals=n3, process=False,
        visual=TextureVisuals(
            uv=uvs,
            material=PBRMaterial(baseColorTexture=texture, metallicFactor=0.0,
                                 roughnessFactor=1.0),
        ),
    )
    chemin_glb = dossier / f"{nom}.glb"
    final.export(str(chemin_glb))
    res.fichiers.append(chemin_glb.name)

    chemin_zip = ecrire_obj_zip(dossier, nom, s3, n3, uvs, f3, texture)
    res.fichiers.append(chemin_zip.name)

    if opt.fbx:
        erreur = ecrire_fbx(chemin_glb, dossier / f"{nom}.fbx", nom)
        if erreur:
            res.avertissements.append(erreur)
        else:
            res.fichiers.append(f"{nom}.fbx")
    return res


def lire_arguments(argv=None):
    p = argparse.ArgumentParser(description="Post-traitement d'un maillage TripoSR")
    p.add_argument("entree", type=Path, nargs="?", help="GLB / OBJ / PLY avec couleurs de sommets")
    p.add_argument("--sorties", type=Path, default=Path("sorties_3d"))
    p.add_argument("--faces", type=int, default=Options.faces)
    p.add_argument("--texture", type=int, default=Options.texture)
    p.add_argument("--lissage", type=int, default=Options.lissage)
    p.add_argument("--tourner", type=float, default=0.0,
                   help="rotation autour de Y en degrés (180 pour un modèle qui regarde vers -Z)")
    p.add_argument("--palette", type=Path,
                   help="sprite PNG détouré d'origine : recale les couleurs du modèle sur les siennes")
    p.add_argument("--sans-fbx", action="store_true")
    return p.parse_args(argv)


def main(argv=None) -> int:
    args = lire_arguments(argv)
    if args.entree is None:
        print("Indique le fichier à traiter.")
        return 2
    import trimesh

    charge = trimesh.load(str(args.entree))
    maillage = charge.dump(concatenate=True) if hasattr(charge, "dump") else charge
    opt = Options(faces=args.faces, texture=args.texture, lissage=args.lissage,
                  fbx=not args.sans_fbx, tourner=args.tourner)
    reference = None
    if args.palette:
        rgba = np.array(Image.open(args.palette).convert("RGBA"))
        reference = rgba[rgba[..., 3] > 8][:, :3]
    res = postraiter(maillage, args.entree.stem, args.sorties / nom_sur(args.entree.stem), opt,
                     reference)
    print(f"{res.sommets} sommets, {res.faces} faces ; fichiers : {', '.join(res.fichiers)}")
    for a in res.avertissements:
        print(f"  ! {a}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
