"""Tests de la collecte et de la préparation (sans torch ni TripoSR).

    python -m unittest sprites_3d/test_sprites_vers_3d.py
"""
import io
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import sprites_vers_3d as s3d  # noqa: E402


def png(largeur=40, hauteur=80, couleur=(200, 30, 30), detoure=True, graine=0) -> bytes:
    """Sprite de test : un rectangle coloré au milieu d'un fond transparent."""
    a = np.zeros((hauteur, largeur, 4), dtype=np.uint8)
    if not detoure:
        a[..., 3] = 255
    a[10:hauteur - 10, 8:largeur - 8] = (*couleur, 255)
    a[10, 8, 0] = graine  # rend le contenu unique
    tampon = io.BytesIO()
    Image.fromarray(a).save(tampon, format="PNG")
    return tampon.getvalue()


class TestPreparation(unittest.TestCase):
    def test_carre_centre_sur_gris(self):
        image = s3d.preparer(png(), marge=0.8)
        self.assertEqual(image.mode, "RGB")
        self.assertEqual(image.width, image.height)
        # sujet de 60 px de haut, marge 0.8 -> carré de 75 px
        self.assertEqual(image.width, 75)
        pixels = np.array(image)
        self.assertTrue(np.all(np.abs(pixels[0, 0].astype(int) - 128) <= 1))  # coin gris
        self.assertEqual(tuple(pixels[37, 37]), (200, 30, 30))  # centre = sprite

    def test_image_non_detouree_refusee(self):
        with self.assertRaises(s3d.ImageNonDetouree):
            s3d.preparer(png(detoure=False))

    def test_image_vide_refusee(self):
        tampon = io.BytesIO()
        Image.new("RGBA", (16, 16), (0, 0, 0, 0)).save(tampon, format="PNG")
        with self.assertRaises(ValueError):
            s3d.preparer(tampon.getvalue())


class TestCollecte(unittest.TestCase):
    def test_fichiers_zip_doublons_et_filtre(self):
        with tempfile.TemporaryDirectory() as d:
            racine = Path(d)
            hero = png(graine=1)
            (racine / "mage.png").write_bytes(png(graine=2))
            (racine / "notes.txt").write_text("pas une image")
            with zipfile.ZipFile(racine / "zimut_sprites_assassin.zip", "w") as z:
                z.writestr("prototype/zimut/assets/sprites/players/assassin.png", hero)
                # même image copiée ailleurs : ne doit compter qu'une fois
                z.writestr("prototype/zimut/assets/sprites/nations/heros/assassin.png", hero)
                z.writestr("prototype/zimut/assets/sprites/players/assassin_idle_2.png",
                           png(graine=3))
                z.writestr("prototype/zimut/assets/sprites/players/assassin_anim.txt", "x")
                # même nom, contenu différent : renommé, pas écrasé
                z.writestr("autre/assassin.png", png(graine=4))

            noms = [e.nom for e in s3d.collecter([racine])]
            self.assertEqual(sorted(noms),
                             ["assassin", "assassin_2", "assassin_idle_2", "mage"])
            filtres = [e.nom for e in s3d.collecter([racine], "assassin_idle*")]
            self.assertEqual(filtres, ["assassin_idle_2"])

    def test_zip_abime_ignore(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "casse.zip").write_bytes(b"pas un zip")
            self.assertEqual(s3d.collecter([Path(d)]), [])


if __name__ == "__main__":
    unittest.main()
