#!/usr/bin/env python3
"""generer_icone.py — dessine l'icône de l'Atelier Sprites (Pillow).

Un petit héros en pixel art posé sur un damier de transparence, encadré de
repères de découpe orange (la grille de l'atelier), sur fond vert forêt.

Produit dans assets/icone/ :
- icone.png          1024 px, icône complète (Android < 8, aperçu) ;
- icone_avant.png    1024 px, premier plan transparent de l'icône adaptative
                     (motif dans le disque sûr central de 66 %) ;
- icone_fond.png     1024 px, arrière-plan de l'icône adaptative.

Usage : python3 tool/generer_icone.py (depuis atelier_sprites/).
"""
import pathlib

from PIL import Image, ImageDraw, ImageFilter

TAILLE = 1024
VERT_HAUT = (0x2E, 0x7D, 0x32)
VERT_BAS = (0x1B, 0x5E, 0x20)
ORANGE = (0xFF, 0x8F, 0x00)
DAMIER_CLAIR = (0xF4, 0xF4, 0xF0)
DAMIER_FONCE = (0xD6, 0xDB, 0xD2)

# Héros chibi 16 × 16 : K contour, H cheveux, S peau, W reflet d'œil, P joues,
# C tunique, B ceinture, L jambes, A épée.
SPRITE = [
    "......KKKK......",
    "....KKHHHHKK....",
    "...KHHHHHHHHK...",
    "..KHHHHHHHHHHK..",
    "..KHHSSSSSSHHK..",
    "..KHSWKSSWKSHK.A",
    "..KHSKKSSKKSHKAK",
    "..KSSSSSSSSSSKAK",
    "...KSPSSSSPSKAK.",
    "....KKSSSSKKAK..",
    "...KCCKKKKCCKK..",
    "..KSKCCCCCCKSK..",
    "..KKKBBBBBBKKK..",
    "....KCCCCCCK....",
    "....KLLKKLLK....",
    "....KKK..KKK....",
]
COULEURS = {
    "K": (0x1A, 0x1A, 0x2E),
    "H": (0xE6, 0x51, 0x00),
    "S": (0xFF, 0xD3, 0xA8),
    "W": (0xFF, 0xFF, 0xFF),
    "P": (0xFF, 0x9E, 0x9E),
    "C": (0x15, 0x65, 0xC0),
    "B": (0x8D, 0x6E, 0x63),
    "L": (0x37, 0x47, 0x4F),
    "A": (0xCF, 0xD8, 0xDC),
}


def degrade(taille: int) -> Image.Image:
    im = Image.new("RGB", (taille, taille))
    d = ImageDraw.Draw(im)
    for y in range(taille):
        t = y / (taille - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(VERT_HAUT, VERT_BAS))
        d.line([(0, y), (taille, y)], fill=c)
    return im


def motif(taille: int, echelle: float) -> Image.Image:
    """Damier + héros + repères de découpe, centré, sur fond transparent.

    [echelle] : côté du motif rapporté à [taille] (0,62 pour la zone sûre adaptative).
    """
    im = Image.new("RGBA", (taille, taille), (0, 0, 0, 0))
    cote = round(taille * echelle)
    x0 = (taille - cote) // 2
    y0 = (taille - cote) // 2

    # Ombre portée douce sous la carte damier.
    ombre = Image.new("RGBA", (taille, taille), (0, 0, 0, 0))
    ImageDraw.Draw(ombre).rounded_rectangle(
        [x0 + cote * 0.03, y0 + cote * 0.05, x0 + cote * 1.03, y0 + cote * 1.05],
        radius=cote * 0.08, fill=(0, 0, 0, 90))
    im.alpha_composite(ombre.filter(ImageFilter.GaussianBlur(cote * 0.03)))

    # Carte damier (la transparence d'un sprite détouré).
    carte = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
    dc = ImageDraw.Draw(carte)
    n = 8
    pas = cote / n
    for j in range(n):
        for i in range(n):
            coul = DAMIER_CLAIR if (i + j) % 2 == 0 else DAMIER_FONCE
            dc.rectangle([i * pas, j * pas, (i + 1) * pas, (j + 1) * pas], fill=coul)
    masque = Image.new("L", (cote, cote), 0)
    ImageDraw.Draw(masque).rounded_rectangle([0, 0, cote - 1, cote - 1], radius=cote * 0.08, fill=255)
    im.paste(carte, (x0, y0), masque)

    # Héros en pixel art, pixels nets.
    px = cote * 0.78 / 16
    sx = x0 + (cote - px * 16) / 2
    sy = y0 + (cote - px * 16) / 2 + px * 0.3
    d = ImageDraw.Draw(im)
    for j, ligne in enumerate(SPRITE):
        for i, c in enumerate(ligne):
            if c == ".":
                continue
            d.rectangle([sx + i * px, sy + j * px, sx + (i + 1) * px - 1, sy + (j + 1) * px - 1],
                        fill=COULEURS[c] + (255,))

    # Repères de découpe orange aux quatre coins (débordent légèrement de la carte).
    ep = max(4, round(cote * 0.045))
    lg = cote * 0.24
    m = cote * 0.06
    for cx, cy, dx, dy in [(x0 - m, y0 - m, 1, 1), (x0 + cote + m, y0 - m, -1, 1),
                           (x0 - m, y0 + cote + m, 1, -1), (x0 + cote + m, y0 + cote + m, -1, -1)]:
        d.rectangle(sorted_box(cx, cy, cx + dx * lg, cy + dy * ep), fill=ORANGE + (255,))
        d.rectangle(sorted_box(cx, cy, cx + dx * ep, cy + dy * lg), fill=ORANGE + (255,))
    return im


def sorted_box(xa, ya, xb, yb):
    return [min(xa, xb), min(ya, yb), max(xa, xb), max(ya, yb)]


def main() -> None:
    sortie = pathlib.Path(__file__).resolve().parent.parent / "assets" / "icone"
    sortie.mkdir(parents=True, exist_ok=True)

    fond = degrade(TAILLE)
    fond.save(sortie / "icone_fond.png")

    # Premier plan adaptatif : seul le disque central de 66 % est garanti visible ;
    # coins du motif (repères compris) à moins de 0,33 du centre.
    motif(TAILLE, 0.41).save(sortie / "icone_avant.png")

    # Icône complète : coins arrondis, motif plus grand.
    complete = fond.convert("RGBA")
    complete.alpha_composite(motif(TAILLE, 0.64))
    masque = Image.new("L", (TAILLE, TAILLE), 0)
    ImageDraw.Draw(masque).rounded_rectangle([0, 0, TAILLE - 1, TAILLE - 1], radius=TAILLE * 0.22, fill=255)
    arrondie = Image.new("RGBA", (TAILLE, TAILLE), (0, 0, 0, 0))
    arrondie.paste(complete, (0, 0), masque)
    arrondie.save(sortie / "icone.png")
    print("Icônes écrites dans", sortie)


if __name__ == "__main__":
    main()
