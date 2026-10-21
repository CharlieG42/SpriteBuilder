/// Grille de découpe : détection automatique, ajustement manuel, extraction des cases.
library;

import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Grille sur l'image. Les positions sont des fractions (0-1) de la largeur/hauteur.
class Grille {
  final int cols;
  final int rows;

  /// Separateurs verticaux, `cols + 1` valeurs croissantes de 0 à 1.
  final List<double> colX;

  /// Separateurs horizontaux, `rows + 1` valeurs croissantes de 0 à 1.
  final List<double> rowY;

  Grille.uniforme(this.cols, this.rows)
      : colX = List<double>.generate(cols + 1, (i) => i / cols),
        rowY = List<double>.generate(rows + 1, (i) => i / rows);

  Grille.personnalisee({
    required this.cols,
    required this.rows,
    required this.colX,
    required this.rowY,
  });

  int get nbCases => cols * rows;
}

/// Détecte le nombre de colonnes et de lignes en projetant les pixels de
/// contenu (loins de la couleur du fond). Repli sur [defautCols]×[defautRows]
/// si la détection sort des bornes plausibles.
Grille detecterGrille(
  img.Image src, {
  required int tolerance,
  int defautCols = 2,
  int defautRows = 2,
}) {
  final w = src.width;
  final h = src.height;

  var sr = 0;
  var sg = 0;
  var sb = 0;
  final coins = <List<int>>[
    [0, 0],
    [w - 1, 0],
    [0, h - 1],
    [w - 1, h - 1],
  ];
  for (final c in coins) {
    final p = src.getPixel(c[0], c[1]);
    sr += p.r.toInt();
    sg += p.g.toInt();
    sb += p.b.toInt();
  }
  final br = sr ~/ 4;
  final bg = sg ~/ 4;
  final bb = sb ~/ 4;
  final t2 = tolerance * tolerance * 3;

  final colContent = List<int>.filled(w, 0);
  final rowContent = List<int>.filled(h, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      final dr = p.r.toInt() - br;
      final dg = p.g.toInt() - bg;
      final db = p.b.toInt() - bb;
      if (dr * dr + dg * dg + db * db > t2) {
        colContent[x]++;
        rowContent[y]++;
      }
    }
  }

  int compterSegments(List<int> valeurs, int seuil) {
    var n = 0;
    var dansSegment = false;
    for (final v in valeurs) {
      if (v > seuil) {
        if (!dansSegment) {
          n++;
          dansSegment = true;
        }
      } else {
        dansSegment = false;
      }
    }
    return n;
  }

  final seuilCol = math.max(1, h ~/ 200);
  final seuilRow = math.max(1, w ~/ 200);
  final cols = compterSegments(colContent, seuilCol);
  final rows = compterSegments(rowContent, seuilRow);

  if (cols < 1 || cols > 6 || rows < 1 || rows > 6) {
    return Grille.uniforme(defautCols, defautRows);
  }
  return Grille.uniforme(cols, rows);
}

/// Extrait la case ([col], [row]) de [src] selon la grille [g].
img.Image extraireCase(img.Image src, Grille g, int col, int row) {
  var x0 = (g.colX[col] * src.width).round();
  var x1 = (g.colX[col + 1] * src.width).round();
  var y0 = (g.rowY[row] * src.height).round();
  var y1 = (g.rowY[row + 1] * src.height).round();
  x0 = x0.clamp(0, src.width - 1);
  x1 = x1.clamp(x0 + 1, src.width);
  y0 = y0.clamp(0, src.height - 1);
  y1 = y1.clamp(y0 + 1, src.height);
  return img.copyCrop(src, x: x0, y: y0, width: x1 - x0, height: y1 - y0);
}

/// Côté des cases exportées.
const int coteCarre = 512;

/// Placement du sprite dans le carré normalisé.
enum Ancrage {
  /// La case est centrée (comportement historique).
  centre,

  /// Le bas du contenu opaque est posé sur une ligne de sol commune ; la
  /// position horizontale de la case est conservée.
  sol,
}

/// Rectangle `[x0, x1) × [y0, y1)` du contenu dont l'alpha dépasse
/// [seuilAlpha], ou `null` si la case est vide.
({int x0, int y0, int x1, int y1})? boiteContenu(img.Image c, {int seuilAlpha = 16}) {
  var x0 = c.width;
  var y0 = c.height;
  var x1 = -1;
  var y1 = -1;
  final avecAlpha = c.numChannels >= 4;
  for (var y = 0; y < c.height; y++) {
    for (var x = 0; x < c.width; x++) {
      final a = avecAlpha ? c.getPixel(x, y).a.toInt() : 255;
      if (a > seuilAlpha) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return null;
  return (x0: x0, y0: y0, x1: x1 + 1, y1: y1 + 1);
}

/// Échelle commune (≤ 1) pour faire tenir toutes les cases [indices] dans un
/// carré [cote] : calculée sur la plus grande case, appliquée à toutes.
double ratioCommun(img.Image src, Grille g, List<int> indices, int cote) {
  var maxCote = 1.0;
  for (final i in indices) {
    final col = i % g.cols;
    final row = i ~/ g.cols;
    if (row >= g.rows) continue;
    final w = (g.colX[col + 1] - g.colX[col]) * src.width;
    final h = (g.rowY[row + 1] - g.rowY[row]) * src.height;
    maxCote = math.max(maxCote, math.max(w, h));
  }
  return math.min(1.0, cote / maxCote);
}

/// Recadre la case dans un carré [cote] (fond transparent), sans jamais
/// agrandir le sprite. Les cases sortent en carrés de 512 px.
///
/// [ratio] impose l'échelle (sinon calculée sur la case seule). Avec
/// [Ancrage.sol], le bas du contenu est posé à [margeSol] × [cote] du bas.
img.Image normaliserCarre(
  img.Image cas,
  int cote, {
  double? ratio,
  Ancrage ancrage = Ancrage.centre,
  double margeSol = 0.06,
}) {
  var c = cas;
  final r = ratio ?? (c.width > cote || c.height > cote ? cote / math.max(c.width, c.height) : 1.0);
  if (r < 1.0) {
    c = img.copyResize(
      c,
      width: math.min(cote, math.max(1, (c.width * r).round())),
      height: math.min(cote, math.max(1, (c.height * r).round())),
      interpolation: img.Interpolation.linear,
    );
  }
  if (c.numChannels < 4) c = c.convert(numChannels: 4);
  final sortie = img.Image(width: cote, height: cote, numChannels: 4);
  final dx = (cote - c.width) ~/ 2;

  if (ancrage == Ancrage.sol) {
    final boite = boiteContenu(c);
    if (boite != null) {
      // On ne garde que les lignes utiles : le haut ne déborde jamais.
      final bande = img.copyCrop(c, x: 0, y: boite.y0, width: c.width, height: boite.y1 - boite.y0);
      final sol = cote - (margeSol.clamp(0.0, 0.3) * cote).round();
      final dy = math.max(0, sol - bande.height);
      img.compositeImage(sortie, bande, dstX: dx, dstY: dy, blend: img.BlendMode.direct);
      return sortie;
    }
  }

  if (c.width == cote && c.height == cote) return c;
  img.compositeImage(
    sortie,
    c,
    dstX: dx,
    dstY: (cote - c.height) ~/ 2,
    blend: img.BlendMode.direct,
  );
  return sortie;
}

/// Réduit une case pour un aperçu rapide (sans carré forcé).
img.Image reduire(img.Image cas, int coteMax) {
  if (cas.width <= coteMax && cas.height <= coteMax) return cas;
  final ratio = coteMax / math.max(cas.width, cas.height);
  return img.copyResize(
    cas,
    width: math.max(1, (cas.width * ratio).round()),
    height: math.max(1, (cas.height * ratio).round()),
  );
}
