/// Détourage d'une planche : suppression du fond par remontée depuis les bords,
/// alpha doux et décontamination du halo.
///
/// Portage du cœur de `detoure_planche.py` : le fond est estimé depuis les
/// quatre coins ; les pixels **connectés aux bords** sont retirés. Les poches
/// de fond enfermées dans le sprite (entre les membres) sont retirées si
/// [interieurs] est activé, en respectant [aireMinInterieur] pour préserver
/// les petits détails (yeux, reflets).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class StatsDetourage {
  /// Part de pixels retirés comme fond, en pourcentage (0-100).
  final int pourcentageFond;

  const StatsDetourage(this.pourcentageFond);
}

/// Supprime le fond de [src] (modifiée en place) et retourne des statistiques.
///
/// [tolerance] : distance de couleur (0-255) sous laquelle un pixel est
/// considéré comme fond. [douceur] : largeur de la rampe d'alpha au bord du
/// sprite. [decontaminer] : re-pousse la couleur du halo hors de la couleur
/// du fond.
StatsDetourage detourer(
  img.Image src, {
  required int tolerance,
  required double douceur,
  required bool decontaminer,
  bool interieurs = true,
  int aireMinInterieur = 24,
}) {
  final w = src.width;
  final h = src.height;

  // Couleur de fond estimée : moyenne des quatre coins.
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

  bool estFond(int i) {
    final p = src.getPixel(i % w, i ~/ w);
    final dr = p.r.toInt() - br;
    final dg = p.g.toInt() - bg;
    final db = p.b.toInt() - bb;
    return dr * dr + dg * dg + db * db <= t2;
  }

  // Remontée (flood fill) depuis les bords uniquement.
  final masque = Uint8List(w * h);
  final file = Int32List(w * h);
  var tete = 0;
  var queue = 0;

  void essayer(int i) {
    if (masque[i] == 0 && estFond(i)) {
      masque[i] = 1;
      file[queue++] = i;
    }
  }

  for (var x = 0; x < w; x++) {
    essayer(x);
    essayer((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    essayer(y * w);
    essayer(y * w + w - 1);
  }

  while (tete < queue) {
    final i = file[tete++];
    final x = i % w;
    final y = i ~/ w;
    if (x > 0) essayer(i - 1);
    if (x < w - 1) essayer(i + 1);
    if (y > 0) essayer(i - w);
    if (y < h - 1) essayer(i + w);
  }

  // Poches de fond enfermées dans le sprite (entre les membres).
  if (interieurs) {
    final visites = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      if (masque[i] != 0 || visites[i] == 1) continue;
      if (!estFond(i)) {
        visites[i] = 1;
        continue;
      }
      var pocheTete = 0;
      var pocheQueue = 0;
      file[pocheQueue++] = i;
      visites[i] = 1;
      while (pocheTete < pocheQueue) {
        final j = file[pocheTete++];
        final x = j % w;
        final y = j ~/ w;
        if (x > 0 && visites[j - 1] == 0 && masque[j - 1] == 0 && estFond(j - 1)) {
          visites[j - 1] = 1;
          file[pocheQueue++] = j - 1;
        }
        if (x < w - 1 && visites[j + 1] == 0 && masque[j + 1] == 0 && estFond(j + 1)) {
          visites[j + 1] = 1;
          file[pocheQueue++] = j + 1;
        }
        if (y > 0 && visites[j - w] == 0 && masque[j - w] == 0 && estFond(j - w)) {
          visites[j - w] = 1;
          file[pocheQueue++] = j - w;
        }
        if (y < h - 1 && visites[j + w] == 0 && masque[j + w] == 0 && estFond(j + w)) {
          visites[j + w] = 1;
          file[pocheQueue++] = j + w;
        }
      }
      if (pocheQueue >= aireMinInterieur) {
        for (var k = 0; k < pocheQueue; k++) {
          masque[file[k]] = 2;
        }
      }
    }
  }

  var nbFond = 0;
  for (var i = 0; i < w * h; i++) {
    if (masque[i] != 0) {
      src.setPixelRgba(i % w, i ~/ w, 0, 0, 0, 0);
      nbFond++;
    }
  }

  // Alpha doux + décontamination sur le bord conservé du sprite.
  final marge = math.max(1, (24 * douceur).round());
  final limite = tolerance + marge;
  final l2 = limite * limite * 3;
  final seuilBas2 = (tolerance * 1.0) * (tolerance * 1.0) * 3;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (masque[i] != 0) continue;
      final voisinFond = (x > 0 && masque[i - 1] != 0) ||
          (x < w - 1 && masque[i + 1] != 0) ||
          (y > 0 && masque[i - w] != 0) ||
          (y < h - 1 && masque[i + w] != 0);
      if (!voisinFond) continue;

      final p = src.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final dr = r - br;
      final dg = g - bg;
      final db = b - bb;
      final d2 = dr * dr + dg * dg + db * db;
      if (d2 > l2) continue;

      final d = math.sqrt(d2 / 3.0);
      final rampe = (d * 255 / limite).round();
      // Entre le seuil de fond et la limite : alpha progressif.
      var a = 255;
      if (d2 > seuilBas2) {
        final auDela = d - tolerance;
        a = ((auDela * 255 / marge).round()).clamp(24, 255);
      }
      var rr = r;
      var gg = g;
      var bb2 = b;
      if (decontaminer && a > 24 && a < 255) {
        // Décontamination : re-pousse la couleur hors du fond (anti-halo).
        final k = 255 / a;
        rr = (br + (r - br) * k).round().clamp(0, 255);
        gg = (bg + (g - bg) * k).round().clamp(0, 255);
        bb2 = (bb + (b - bb) * k).round().clamp(0, 255);
      }
      src.setPixelRgba(x, y, rr, gg, bb2, a);
    }
  }

  return StatsDetourage((100 * nbFond) ~/ (w * h));
}
