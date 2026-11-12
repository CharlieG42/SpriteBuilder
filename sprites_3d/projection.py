"""Plaquage du sprite d'origine sur la face avant du modèle.

TripoSR reconstruit une couleur floue, y compris sur la face que l'on voit sur
le sprite. Or le sprite, lui, est net : visage, ceinture, poches, coutures.
Comme le modèle est reconstruit pour redonner l'image d'entrée vue de face, on
peut retrouver la caméra (position, échelle, perspective) en superposant la
silhouette du maillage à celle du sprite, puis peindre sur la texture les
couleurs du sprite partout où la surface est vue de face. Le reste (côtés,
dos) garde la couleur reconstruite par TripoSR, avec un fondu progressif.

Repère : personnage face à +Z, y vers le haut, caméra sur l'axe +Z qui regarde
vers -Z. Les coordonnées image sont celles du sprite, en pixels, y vers le bas.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

# Distances de caméra essayées, en hauteurs de modèle. 0 = projection orthographique.
DISTANCES = (1.6, 1.8, 2.0, 2.25, 2.6, 3.2)
COTE_AJUSTEMENT = 360     # pixels du plus grand côté pour comparer les silhouettes
COTE_VISIBILITE = 1400    # pixels du plus grand côté pour la carte de visibilité


@dataclass
class Camera:
    s: float          # pixels du sprite par mètre, dans le plan de référence
    tx: float         # position de l'axe optique dans l'image
    ty: float
    d: float          # distance de la caméra, en hauteurs du modèle (0 = orthographique)
    z0: float         # profondeur du plan de référence
    yc: float         # hauteur de l'axe optique
    hauteur: float    # hauteur du modèle

    def projeter(self, p: np.ndarray):
        """Points (N, 3) -> (x image, y image)."""
        z = p[:, 2]
        if self.d > 0:
            dist = self.d * self.hauteur
            k = dist / np.maximum(dist - (z - self.z0), 1e-6)
        else:
            k = 1.0
        return (self.s * p[:, 0] * k + self.tx,
                -self.s * (p[:, 1] - self.yc) * k + self.ty)

    def vers_camera(self, p: np.ndarray) -> np.ndarray:
        """Direction unitaire du point vers la caméra, (N, 3)."""
        if self.d > 0:
            pos = np.array([0.0, self.yc, self.z0 + self.d * self.hauteur])
            v = pos - p
            return v / np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-9)
        return np.tile(np.array([0.0, 0.0, 1.0]), (len(p), 1))


def _masque_reduit(masque: np.ndarray, cote: int):
    h, w = masque.shape
    r = min(1.0, cote / max(h, w))
    if r == 1.0:
        return masque, 1.0
    img = Image.fromarray((masque * 255).astype(np.uint8)).resize(
        (max(1, int(w * r)), max(1, int(h * r))), Image.BILINEAR)
    return np.asarray(img) > 127, r


def _silhouette(px: np.ndarray, py: np.ndarray, faces: np.ndarray, hw) -> np.ndarray:
    h, w = hw
    img = Image.new("L", (w, h), 0)
    dessin = ImageDraw.Draw(img)
    tri = np.stack([px, py], axis=1)[faces]
    for t in tri:
        dessin.polygon([tuple(q) for q in t], fill=1)
    return np.asarray(img) > 0


def ajuster_camera(sommets: np.ndarray, faces: np.ndarray, masque: np.ndarray):
    """Trouve la caméra qui superpose au mieux le maillage au sprite.

    `masque` : (H, W) booléen, pixels opaques du sprite. Retourne (Camera, IoU),
    l'IoU mesurant le recouvrement des deux silhouettes (1 = identiques).
    """
    petit, r = _masque_reduit(masque, COTE_AJUSTEMENT)
    ys, xs = np.nonzero(petit)
    cible_cx, cible_cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    hauteur_sprite = ys.max() - ys.min()
    hauteur = float(sommets[:, 1].max() - sommets[:, 1].min())
    z0 = float((sommets[:, 2].max() + sommets[:, 2].min()) / 2)
    yc = hauteur / 2

    def cam_de(s, tx, ty, d):
        return Camera(s, tx, ty, d, z0, yc, hauteur)

    def iou(c: Camera) -> float:
        px, py = c.projeter(sommets)
        s = _silhouette(px, py, faces, petit.shape)
        return (s & petit).sum() / max((s | petit).sum(), 1)

    meilleur = (-1.0, None)
    for d in (0,) + DISTANCES:
        c0 = cam_de(1.0, 0.0, 0.0, d)
        px, py = c0.projeter(sommets)
        s = hauteur_sprite / max(py.max() - py.min(), 1e-9)
        tx = cible_cx - s * (px.min() + px.max()) / 2
        ty = cible_cy - s * (py.min() + py.max()) / 2
        courant = [s, tx, ty]
        score = iou(cam_de(*courant, d))
        pas = [0.02 * s, 6.0, 6.0]
        for _ in range(60):
            mieux = False
            for i in range(3):
                for signe in (1, -1):
                    essai = list(courant)
                    essai[i] += signe * pas[i]
                    v = iou(cam_de(*essai, d))
                    if v > score + 1e-5:
                        score, courant, mieux = v, essai, True
            if not mieux:
                pas = [p / 2 for p in pas]
                if pas[1] < 0.3:
                    break
        if score > meilleur[0]:
            meilleur = (score, cam_de(*courant, d))
    score, cam = meilleur
    # retour aux pixels du sprite d'origine
    cam = Camera(cam.s / r, cam.tx / r, cam.ty / r, cam.d, cam.z0, cam.yc, cam.hauteur)
    return cam, float(score)


def faces_visibles(cam: Camera, sommets: np.ndarray, faces: np.ndarray,
                   hw) -> np.ndarray:
    """Booléen par face : la face est vue par la caméra (algorithme du peintre)."""
    h, w = hw
    r = min(1.0, COTE_VISIBILITE / max(h, w))
    px, py = cam.projeter(sommets)
    px, py = px * r, py * r
    tri3 = sommets[faces]
    centre = tri3.mean(axis=1)
    normale = np.cross(tri3[:, 1] - tri3[:, 0], tri3[:, 2] - tri3[:, 0])
    face_avant = (normale * cam.vers_camera(centre)).sum(axis=1) > 0
    ordre = np.argsort(centre[:, 2])                    # le plus loin d'abord
    carte = Image.new("I", (max(1, int(w * r)), max(1, int(h * r))), 0)
    dessin = ImageDraw.Draw(carte)
    pts = np.stack([px, py], axis=1)
    for i in ordre:
        if face_avant[i]:
            dessin.polygon([tuple(q) for q in pts[faces[i]]], fill=int(i) + 1)
    presentes = np.bincount(np.asarray(carte).ravel(), minlength=len(faces) + 1)[1:]
    return presentes > 0


@dataclass
class Projection:
    camera: Camera
    rgb: np.ndarray            # (H, W, 3) couleurs du sprite
    masque: np.ndarray         # (H, W) pixels sûrs : opaques et loin du bord
    visibles: np.ndarray       # (nombre de faces,) bool
    iou: float


def preparer_projection(sommets: np.ndarray, faces: np.ndarray,
                        sprite_rgba: np.ndarray, marge_bord: int = 3) -> Projection:
    opaque = sprite_rgba[..., 3] > 8
    cam, iou = ajuster_camera(sommets, faces, opaque)
    sur = ndi.binary_erosion(opaque, iterations=marge_bord)
    visibles = faces_visibles(cam, sommets, faces, opaque.shape)
    return Projection(cam, sprite_rgba[..., :3].astype(np.float32), sur, visibles, iou)


def appliquer(proj: Projection, couleurs: np.ndarray, positions: np.ndarray,
              normales: np.ndarray, face_ids: np.ndarray,
              cos_min: float = 0.2, cos_plein: float = 0.65) -> np.ndarray:
    """Mélange, texel par texel, la couleur du sprite et celle de TripoSR.

    `positions`, `normales` : (N, 3) par texel ; `face_ids` : face de chaque texel.
    Le poids est maximal pour une surface qui fait face à la caméra, nul de profil
    ou hors de la vue, avec un fondu entre `cos_min` et `cos_plein`.
    """
    h, w = proj.masque.shape
    px, py = proj.camera.projeter(positions)
    cos = (normales * proj.camera.vers_camera(positions)).sum(axis=1)
    poids = np.clip((cos - cos_min) / (cos_plein - cos_min), 0.0, 1.0)
    poids *= proj.visibles[face_ids]
    dedans = (px >= 0) & (px <= w - 1) & (py >= 0) & (py <= h - 1)
    ix = np.clip(np.rint(px).astype(int), 0, w - 1)
    iy = np.clip(np.rint(py).astype(int), 0, h - 1)
    poids *= dedans & proj.masque[iy, ix]
    actifs = np.nonzero(poids > 0)[0]
    if actifs.size == 0:
        return couleurs
    coords = np.stack([py[actifs], px[actifs]])
    sprite = np.stack([ndi.map_coordinates(proj.rgb[..., c], coords, order=1, mode="nearest")
                       for c in range(3)], axis=1)
    sortie = couleurs.astype(np.float32).copy()
    p = poids[actifs, None]
    sortie[actifs] = sortie[actifs] * (1 - p) + sprite * p
    return sortie
