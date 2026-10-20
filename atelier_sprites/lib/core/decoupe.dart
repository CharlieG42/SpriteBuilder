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
  int defautCols = 4,
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
  return img.copyCrop(src, x0, y0, x1 - x0, y1 - y0);
}

/// Recadre la case dans un carré [cote] (fond transparent), sans jamais
/// agrandir le sprite. Les planches 4×2 sortent en cases de 512 px.
img.Image normaliserCarre(img.Image cas, int cote) {
  var c = cas;
  if (c.width > cote || c.height > cote) {
    final ratio = cote / math.max(c.width, c.height);
    c = img.copyResize(
      c,
      width: math.max(1, (c.width * ratio).round()),
      height: math.max(1, (c.height * ratio).round()),
    );
  }
  if (c.width == cote && c.height == cote) return c;
  final sortie = img.Image(cote, cote);
  img.drawImage(
    sortie,
    c,
    dstX: (cote - c.width) ~/ 2,
    dstY: (cote - c.height) ~/ 2,
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
