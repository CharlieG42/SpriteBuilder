"""Tests de la collecte, de la préparation et du post-traitement (sans torch ni TripoSR).

    python -m unittest sprites_3d/test_sprites_vers_3d.py
"""
import io
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import postraitement as pp  # noqa: E402
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


class TestNettoyage(unittest.TestCase):
    def sprite(self):
        """Disque vert, entouré d'un liseré blanc, traversé d'une fente fine."""
        h = w = 200
        yy, xx = np.mgrid[:h, :w]
        r = np.hypot(xx - 100, yy - 100)
        a = np.zeros((h, w, 4), np.uint8)
        a[r < 70] = (255, 255, 255, 255)           # liseré blanc
        a[r < 64] = (30, 150, 40, 255)             # corps vert
        a[:, 98:102][r[:, 98:102] < 64] = (0, 0, 0, 0)   # fente de 4 px
        return a

    def test_liseré_et_fente(self):
        propre = s3d.nettoyer_sprite(self.sprite())
        opaque = propre[..., 3] > 8
        blanc = opaque & (propre[..., :3].min(axis=2) >= 215)
        self.assertEqual(blanc.sum(), 0, "il reste du blanc")
        self.assertTrue(propre[100, 100, 3] == 255, "la fente n'est pas comblée")
        vert = propre[100, 100, :3].astype(int)
        self.assertGreater(vert[1], vert[0] + 50, "la fente doit prendre la couleur voisine")

    def test_grand_vide_conserve(self):
        a = np.zeros((120, 200, 4), np.uint8)
        a[:, :70] = (200, 50, 50, 255)
        a[:, 130:] = (200, 50, 50, 255)           # 60 px de vide entre deux jambes
        propre = s3d.nettoyer_sprite(a)
        self.assertEqual(propre[60, 100, 3], 0)


class TestPostraitement(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import trimesh
        cls.trimesh = trimesh
        m = trimesh.creation.icosphere(subdivisions=4)
        m.apply_scale([0.4, 1.0, 0.3])               # un « personnage » allongé
        m.apply_translation([5.0, 3.0, -2.0])        # décentré, loin de l'origine
        h = (m.vertices[:, 1] - m.vertices[:, 1].min()) / np.ptp(m.vertices[:, 1])
        m.visual.vertex_colors = np.stack(
            [h * 255, np.full(len(h), 80.0), (1 - h) * 255, np.full(len(h), 255.0)],
            axis=1).astype(np.uint8)
        cls.maillage = m
        cls.dossier = tempfile.TemporaryDirectory()
        cls.res = pp.postraiter(m, "mon héros", Path(cls.dossier.name),
                                pp.Options(faces=700, texture=256, fbx=False))

    @classmethod
    def tearDownClass(cls):
        cls.dossier.cleanup()

    def test_fichiers_et_nom_sur(self):
        self.assertEqual(pp.nom_sur("mon héros"), "mon_heros")
        self.assertEqual(sorted(self.res.fichiers),
                         ["mon_heros.glb", "mon_heros_mixamo_obj.zip", "mon_heros_texture.png"])

    def test_glb_texture_echelle_et_pieds(self):
        g = self.trimesh.load(str(Path(self.dossier.name) / "mon_heros.glb"), force="mesh")
        self.assertEqual(g.visual.kind, "texture")
        self.assertAlmostEqual(g.bounds[1][1] - g.bounds[0][1], 1.8, places=3)
        self.assertAlmostEqual(g.bounds[0][1], 0.0, places=3)
        self.assertAlmostEqual((g.bounds[0][0] + g.bounds[1][0]) / 2, 0.0, places=3)
        self.assertLessEqual(len(g.faces), 700 * 1.05)
        self.assertTrue(np.isfinite(g.vertices).all())

    def test_couleurs_fideles_dans_la_texture(self):
        g = self.trimesh.load(str(Path(self.dossier.name) / "mon_heros.glb"), force="mesh")
        tex = np.asarray(g.visual.material.baseColorTexture.convert("RGB"))
        uv = g.visual.uv
        x = np.clip((uv[:, 0] * tex.shape[1]).astype(int), 0, tex.shape[1] - 1)
        y = np.clip(((1 - uv[:, 1]) * tex.shape[0]).astype(int), 0, tex.shape[0] - 1)
        rouge_attendu = g.vertices[:, 1] / 1.8 * 255          # rouge = hauteur
        ecart = np.abs(tex[y, x, 0].astype(float) - rouge_attendu)
        self.assertLess(np.median(ecart), 12)
        self.assertLess(np.percentile(ecart, 95), 40)

    def test_zip_mixamo(self):
        with zipfile.ZipFile(Path(self.dossier.name) / "mon_heros_mixamo_obj.zip") as z:
            self.assertEqual(sorted(z.namelist()),
                             ["mon_heros.mtl", "mon_heros.obj", "mon_heros_texture.png"])
            self.assertIn("map_Kd mon_heros_texture.png", z.read("mon_heros.mtl").decode())
            obj = z.read("mon_heros.obj").decode().splitlines()
            self.assertEqual(sum(l.startswith("f ") for l in obj), self.res.faces)
            self.assertEqual(sum(l.startswith("v ") for l in obj),
                             sum(l.startswith("vt ") for l in obj))

    def test_rotation_vers_zplus(self):
        p = pp.tourner_y(np.array([[0.0, 1.0, -1.0]]), 180)
        np.testing.assert_allclose(p, [[0.0, 1.0, 1.0]], atol=1e-9)

    def test_recalage_couleurs_ne_ternit_jamais(self):
        terne = np.full((50, 3), 80.0)
        vif = np.full((50, 3), (200.0, 120.0, 60.0))
        self.assertGreater(pp.caler_couleurs(terne, vif).mean(), terne.mean())
        np.testing.assert_allclose(pp.caler_couleurs(vif, terne), vif, atol=2)

    def test_fragments_retires(self):
        grand = self.trimesh.creation.icosphere(subdivisions=3)
        petit = self.trimesh.creation.box(extents=[0.01] * 3)
        petit.apply_translation([5, 0, 0])
        for m in (grand, petit):
            m.visual.vertex_colors = np.full((len(m.vertices), 4), 255, np.uint8)
        garde = pp.garder_pieces_principales(self.trimesh.util.concatenate([grand, petit]))
        self.assertEqual(len(garde.faces), len(grand.faces))


class TestProjection(unittest.TestCase):
    def test_sprite_plaque_sur_la_face_avant(self):
        import trimesh
        m = trimesh.creation.icosphere(subdivisions=4)
        m.apply_scale([0.4, 1.0, 0.3])
        m.visual.vertex_colors = np.tile(np.array([200, 30, 30, 255], np.uint8), (len(m.vertices), 1))
        h, w = 400, 200
        yy, xx = np.mgrid[0:h, 0:w]
        ellipse = ((xx - 100) / 80.0) ** 2 + ((yy - 200) / 190.0) ** 2 <= 1
        sprite = np.zeros((h, w, 4), np.uint8)
        sprite[ellipse] = (30, 30, 220, 255)
        with tempfile.TemporaryDirectory() as d:
            res = pp.postraiter(m, "x", Path(d), pp.Options(faces=700, texture=256, fbx=False),
                                None, sprite)
            tex = np.asarray(Image.open(Path(d) / "x_texture.png").convert("RGB")).astype(int)
        self.assertTrue(any("projection" in a for a in res.avertissements))
        bleus = ((tex[..., 2] > tex[..., 0] + 80)).mean()
        rouges = ((tex[..., 0] > tex[..., 2] + 80)).mean()
        self.assertGreater(bleus, 0.15)      # la face avant prend le sprite
        self.assertGreater(rouges, 0.15)     # le dos garde la couleur du modèle


class TestSilhouettes(unittest.TestCase):
    def test_face_et_dos_donnent_un_modele(self):
        import silhouettes as sil
        import trimesh
        h, w = 300, 160
        yy, xx = np.mgrid[0:h, 0:w]
        ellipse = ((xx - 80) / 70.0) ** 2 + ((yy - 150) / 145.0) ** 2 <= 1
        face = np.zeros((h, w, 4), np.uint8)
        face[ellipse] = (30, 30, 220, 255)
        dos = np.zeros((h, w, 4), np.uint8)
        dos[ellipse] = (220, 30, 30, 255)
        with tempfile.TemporaryDirectory() as d:
            res = sil.construire(sil.charger_tableau(face), sil.charger_tableau(dos), "x", Path(d),
                                 pp.Options(faces=1500, texture=256, fbx=False), grille=120)
            m = trimesh.load(Path(d) / "x.glb", force="mesh")
            tex = np.asarray(Image.open(Path(d) / "x_texture.png").convert("RGB")).astype(int)
        self.assertIn("x_mixamo_obj.zip", res.fichiers)
        self.assertAlmostEqual(m.bounds[1][1] - m.bounds[0][1], 1.8, places=2)
        self.assertAlmostEqual(m.bounds[0][1], 0.0, places=3)
        self.assertGreater(m.bounds[1][2], 0.05)                 # il y a du volume
        self.assertGreater((tex[..., 2] > tex[..., 0] + 80).mean(), 0.1)   # face bleue
        self.assertGreater((tex[..., 0] > tex[..., 2] + 80).mean(), 0.1)   # dos rouge


class TestFbx(unittest.TestCase):
    def test_fbx_si_blender_disponible(self):
        interp = pp.interpreteur_blender()
        if subprocess.run([interp, "-c", "import bpy"], capture_output=True).returncode != 0:
            self.skipTest("bpy indisponible")
        import trimesh
        m = trimesh.creation.icosphere(subdivisions=3)
        m.visual.vertex_colors = np.full((len(m.vertices), 4), (200, 100, 50, 255), np.uint8)
        with tempfile.TemporaryDirectory() as d:
            res = pp.postraiter(m, "boule", Path(d), pp.Options(faces=300, texture=128))
            self.assertEqual(res.avertissements, [])
            fbx = Path(d) / "boule.fbx"
            self.assertGreater(fbx.stat().st_size, 10_000)
            self.assertEqual(fbx.read_bytes()[:20], b"Kaydara FBX Binary  ")


if __name__ == "__main__":
    unittest.main()
