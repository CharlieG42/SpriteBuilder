"""Modèle 3D construit directement à partir des dessins, sans IA.

Principe : la silhouette de face est « gonflée » comme un coussin. Chaque point
de son squelette porte une boule dont le rayon est la demi-largeur locale du
dessin : un bras devient un cylindre, une tête une boule, un torse un volume
arrondi. Le dessin de face est ensuite plaqué tel quel sur l'avant, et le dessin
de dos (ou, à défaut, le dessin de face) sur l'arrière.

Tout tourne sur processeur en quelques secondes.

    python silhouettes.py face.png --dos dos.png --sorties sorties_3d

Repère de sortie : personnage face à +Z, y vers le haut, pieds à y = 0.
"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

import postraitement as pp

SEUIL_ALPHA = 8


def charger(chemin: Path, nettoyer: bool = True) -> np.ndarray:
    """PNG détouré -> RGBA recadré sur le personnage."""
    rgba = np.array(Image.open(chemin).convert("RGBA"))
    if nettoyer:
        from sprites_vers_3d import nettoyer_sprite
        rgba = nettoyer_sprite(rgba)
    ys, xs = np.nonzero(rgba[..., 3] > SEUIL_ALPHA)
    if len(ys) == 0:
        raise ValueError(f"{chemin} : image entièrement transparente")
    return rgba[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]


def charger_tableau(rgba: np.ndarray) -> np.ndarray:
    """RGBA déjà en mémoire -> recadré sur le personnage."""
    ys, xs = np.nonzero(rgba[..., 3] > SEUIL_ALPHA)
    return rgba[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]


def masque_propre(rgba: np.ndarray) -> np.ndarray:
    """Pixels opaques : plus grand morceau, trous bouchés."""
    m = rgba[..., 3] > 127
    etiquettes, n = ndi.label(m)
    if n > 1:
        tailles = ndi.sum(m, etiquettes, range(1, n + 1))
        m = etiquettes == (1 + int(np.argmax(tailles)))
    return ndi.binary_fill_holes(m)


def gonfler(masque: np.ndarray) -> np.ndarray:
    """Demi-épaisseur (en pixels) en chaque pixel de la silhouette.

    Union des boules posées sur le squelette : h(p) = max sqrt(r² - |p - q|²).
    """
    from skimage.morphology import medial_axis

    m = np.pad(masque, 1)
    squelette, dist = medial_axis(m, return_distance=True)
    h2 = np.zeros(m.shape, dtype=np.float32)
    ys, xs = np.nonzero(squelette)
    for y, x, r in zip(ys, xs, dist[ys, xs]):
        k = int(np.ceil(r))
        y0, y1 = max(y - k, 0), min(y + k + 1, m.shape[0])
        x0, x1 = max(x - k, 0), min(x + k + 1, m.shape[1])
        yy, xx = np.ogrid[y0 - y: y1 - y, x0 - x: x1 - x]
        np.maximum(h2[y0:y1, x0:x1], r * r - yy * yy - xx * xx, out=h2[y0:y1, x0:x1])
    h = np.sqrt(np.maximum(h2, 0.0)) * m
    return h[1:-1, 1:-1]


def sculpter(masque: np.ndarray, epaisseur: float = 0.8, plafond: float = 0.0,
             lissage: float = 1.0):
    """Silhouette -> (sommets, faces) en pixels de la grille : x droite, y haut, z avant."""
    import mcubes

    h = gonfler(masque) * epaisseur
    if plafond > 0:                       # écrase doucement les parties trop épaisses
        h = plafond * np.tanh(h / plafond)
    dehors = ndi.distance_transform_edt(~masque).astype(np.float32)
    h = np.where(masque, h, -dehors)
    marge = 3
    h = np.pad(h, marge, constant_values=-marge)
    nz = int(np.ceil(h.max())) + marge
    z = np.arange(-nz, nz + 1, dtype=np.float32)
    champ = h[:, :, None] - np.abs(z)[None, None, :]
    if lissage > 0:
        champ = ndi.gaussian_filter(champ, lissage)
    sommets, faces = mcubes.marching_cubes(champ, 0.0)
    haut = masque.shape[0]
    x = sommets[:, 1] - marge
    y = haut - (sommets[:, 0] - marge)
    zz = sommets[:, 2] - nz
    # mcubes oriente les faces vers les valeurs croissantes : on les retourne
    return np.stack([x, y, zz], axis=1).astype(np.float32), faces[:, ::-1].astype(np.int64)


def _remplie(rgba: np.ndarray, marge: int = 6) -> np.ndarray:
    """Couleurs du dessin étendues hors de la silhouette (évite les liserés)."""
    sur = ndi.binary_erosion(rgba[..., 3] > 200, iterations=marge)
    if not sur.any():
        sur = rgba[..., 3] > SEUIL_ALPHA
    idx = ndi.distance_transform_edt(~sur, return_distances=False, return_indices=True)
    return rgba[..., :3][idx[0], idx[1]].astype(np.float32)


@dataclass
class Peintre:
    """Donne la couleur d'un point de la surface à partir des dessins."""
    face: np.ndarray                 # (H, W, 3) dessin de face, couleurs étendues
    dos: np.ndarray                  # (H, W, 3) dessin de dos, déjà remis dans le sens du modèle
    px_par_m: float                  # pixels du dessin par mètre
    x0: float                        # colonne du dessin correspondant à x = 0
    fondu: float = 0.25              # largeur du fondu face/dos sur les flancs

    def peindre(self, pos: np.ndarray, normales: np.ndarray) -> np.ndarray:
        h = self.face.shape[0]
        col = pos[:, 0] * self.px_par_m + self.x0 - 0.5
        lig = h - pos[:, 1] * self.px_par_m - 0.5
        coords = np.stack([lig, col])
        lire = lambda img: np.stack(
            [ndi.map_coordinates(img[..., c], coords, order=1, mode="nearest")
             for c in range(3)], axis=1)
        t = np.clip(normales[:, 2] / self.fondu * 0.5 + 0.5, 0.0, 1.0)[:, None]
        t = t * t * (3 - 2 * t)
        return lire(self.face) * t + lire(self.dos) * (1 - t)


def aligner_dos(dos: np.ndarray, forme) -> np.ndarray:
    """Dessin de dos -> même cadre que la face, retourné gauche-droite."""
    h, w = forme
    img = Image.fromarray(dos).resize((w, h), Image.LANCZOS)
    return np.array(img)[:, ::-1]


def construire(face: np.ndarray, dos: np.ndarray | None, nom: str, dossier: Path,
               opt: pp.Options | None = None, epaisseur: float = 0.8,
               plafond_m: float = 0.18, grille: int = 320) -> pp.Resultat:
    import trimesh
    from trimesh.visual.material import PBRMaterial
    from trimesh.visual.texture import TextureVisuals

    opt = opt or pp.Options()
    nom = pp.nom_sur(nom)
    dossier.mkdir(parents=True, exist_ok=True)
    res = pp.Resultat()

    haut, large = face.shape[:2]
    r = min(1.0, grille / haut)
    petit = np.array(Image.fromarray(face).resize(
        (max(1, round(large * r)), max(1, round(haut * r))), Image.LANCZOS))
    masque = masque_propre(petit)
    m_par_px = opt.hauteur / masque.shape[0]            # mètre par pixel de grille
    sommets, faces = sculpter(masque, epaisseur, plafond_m / m_par_px)
    sommets[:, 0] -= masque.shape[1] / 2
    sommets *= m_par_px

    maillage = trimesh.Trimesh(sommets, faces, process=False)
    pp.lisser(maillage, opt.lissage)
    s2, f2 = pp.decimer(np.asarray(maillage.vertices, dtype=np.float32),
                        np.asarray(maillage.faces), opt.faces)
    s2, f2 = pp.retirer_triangles_plats(s2, f2)
    n2 = pp.normales_sommets(s2, f2)
    vmap, f3, uvs = pp.deplier(s2, f2, opt.texture)
    s3, n3 = s2[vmap], n2[vmap]

    if dos is None:
        res.avertissements.append("pas de dessin de dos : la face est reprise à l'arrière")
        dos_aligne = face
    else:
        dos_aligne = aligner_dos(dos, (haut, large))
    peintre = Peintre(_remplie(face), _remplie(dos_aligne),
                      px_par_m=haut / opt.hauteur, x0=large / 2)
    texture = pp.cuire_texture(s3, f3, uvs, None, None, opt.texture, None, peintre, n3)

    # recalage final : hauteur exacte, pieds au sol
    facteur, decalage = pp.calage_echelle(s3, opt.hauteur)
    s3 = (s3 * facteur + decalage).astype(np.float32)
    res.sommets, res.faces = len(s3), len(f3)

    chemin_tex = dossier / f"{nom}_texture.png"
    texture.save(chemin_tex)
    res.fichiers.append(chemin_tex.name)
    final = trimesh.Trimesh(
        vertices=s3, faces=f3, vertex_normals=n3, process=False,
        visual=TextureVisuals(uv=uvs, material=PBRMaterial(
            baseColorTexture=texture, metallicFactor=0.0, roughnessFactor=1.0)))
    chemin_glb = dossier / f"{nom}.glb"
    final.export(str(chemin_glb))
    res.fichiers.append(chemin_glb.name)
    res.fichiers.append(pp.ecrire_obj_zip(dossier, nom, s3, n3, uvs, f3, texture).name)
    if opt.fbx:
        erreur = pp.ecrire_fbx(chemin_glb, dossier / f"{nom}.fbx", nom)
        if erreur:
            res.avertissements.append(erreur)
        else:
            res.fichiers.append(f"{nom}.fbx")
    return res


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Dessins de face (et de dos) -> modèle 3D, sans IA.")
    p.add_argument("face", type=Path, help="dessin de face détouré (PNG transparent)")
    p.add_argument("--dos", type=Path, help="dessin de dos détouré, même pose")
    p.add_argument("--sorties", type=Path, default=Path("sorties_3d"))
    p.add_argument("--nom", help="nom du modèle (défaut : nom du fichier de face)")
    p.add_argument("--epaisseur", type=float, default=0.8,
                   help="1 = aussi épais que large, 0.5 = deux fois plus plat")
    p.add_argument("--plafond", type=float, default=0.18,
                   help="demi-épaisseur maximale en mètres (0 = sans limite)")
    p.add_argument("--faces", type=int, default=25000)
    p.add_argument("--texture", type=int, default=2048)
    p.add_argument("--hauteur", type=float, default=1.8)
    p.add_argument("--sans-nettoyage", action="store_true")
    p.add_argument("--sans-fbx", action="store_true")
    a = p.parse_args(argv)
    face = charger(a.face, not a.sans_nettoyage)
    dos = charger(a.dos, not a.sans_nettoyage) if a.dos else None
    nom = a.nom or a.face.stem
    opt = pp.Options(faces=a.faces, texture=a.texture, hauteur=a.hauteur, fbx=not a.sans_fbx)
    res = construire(face, dos, nom, a.sorties / pp.nom_sur(nom), opt, a.epaisseur, a.plafond)
    print(f"{res.sommets} sommets, {res.faces} faces ; fichiers : {', '.join(res.fichiers)}")
    for av in res.avertissements:
        print(f"  ! {av}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
