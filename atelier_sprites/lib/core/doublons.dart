/// Détection des poses en double sur une planche (V36).
///
/// Les générateurs d'images recopient souvent la même pose dans plusieurs cases.
/// Chaque case découpée est réduite à une signature 32 × 32 (silhouette + luminance,
/// recadrée sur le sprite et centrée dans un carré) ; deux cases dont la distance est
/// sous [seuilDoublon] sont des doublons. Même algorithme que
/// `prototype/zimut/tools/doublons_poses.py` dans le dépôt Zimut (seuils calibrés sur
/// des planches réelles : doublons < 0,03, poses distinctes > 0,08).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int _cote = 32;

/// Sous ce seuil : pose identique. Entre les deux : poses très proches.
const double seuilDoublon = 0.05;
const double seuilProche = 0.08;

class Signature {
  final Float32List alpha;
  final Float32List lum;
  final double ratio;

  const Signature(this.alpha, this.lum, this.ratio);
}

class Doublon {
  final int a;
  final int b;
  final double distance;

  const Doublon(this.a, this.b, this.distance);

  bool get identique => distance < seuilDoublon;
}

/// Signature d'une case (image RGBA), `null` si la case est vide.
Signature? signatureDe(img.Image src) {
  var x0 = src.width, y0 = src.height, x1 = -1, y1 = -1;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      if (src.getPixel(x, y).a > 128) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return null;
  final w = x1 - x0 + 1;
  final h = y1 - y0 + 1;
  final s = math.max(w, h);
  final carre = img.Image(width: s, height: s, numChannels: 4);
  img.compositeImage(carre, img.copyCrop(src, x: x0, y: y0, width: w, height: h),
      dstX: (s - w) ~/ 2, dstY: (s - h) ~/ 2);
  final petit = img.copyResize(carre, width: _cote, height: _cote, interpolation: img.Interpolation.linear);
  final alpha = Float32List(_cote * _cote);
  final lum = Float32List(_cote * _cote);
  for (var y = 0; y < _cote; y++) {
    for (var x = 0; x < _cote; x++) {
      final p = petit.getPixel(x, y);
      final a = p.a / 255.0;
      alpha[y * _cote + x] = a;
      lum[y * _cote + x] = (p.r * 0.3 + p.g * 0.59 + p.b * 0.11) / 255.0 * a;
    }
  }
  return Signature(alpha, lum, w / h);
}

/// Distance entre deux signatures (0 = identiques).
double distanceSignatures(Signature s1, Signature s2) {
  var da = 0.0;
  var dl = 0.0;
  for (var i = 0; i < s1.alpha.length; i++) {
    da += (s1.alpha[i] - s2.alpha[i]).abs();
    dl += (s1.lum[i] - s2.lum[i]).abs();
  }
  final n = s1.alpha.length;
  return da / n + dl / n + (math.log(s1.ratio / s2.ratio)).abs() * 0.2;
}

/// Paires de cases trop semblables (distance < [seuilProche]), triées de la plus proche
/// à la moins proche. [pngs] : index de case → PNG détouré. Prévu pour `compute()`.
List<Doublon> detecterDoublons(Map<int, Uint8List> pngs) {
  final sigs = <int, Signature>{};
  for (final e in pngs.entries) {
    final im = img.decodePng(e.value);
    if (im == null) continue;
    final s = signatureDe(im.numChannels < 4 ? im.convert(numChannels: 4) : im);
    if (s != null) sigs[e.key] = s;
  }
  final cles = sigs.keys.toList()..sort();
  final out = <Doublon>[];
  for (var i = 0; i < cles.length; i++) {
    for (var j = i + 1; j < cles.length; j++) {
      final d = distanceSignatures(sigs[cles[i]]!, sigs[cles[j]]!);
      if (d < seuilProche) out.add(Doublon(cles[i], cles[j], d));
    }
  }
  out.sort((x, y) => x.distance.compareTo(y.distance));
  return out;
}

/// Cases à exclure pour ne garder qu'un exemplaire de chaque pose identique
/// (la première case de chaque groupe est conservée).
Set<int> casesAExclure(List<Doublon> doublons) {
  final exclues = <int>{};
  for (final d in doublons) {
    if (d.identique && !exclues.contains(d.a)) exclues.add(d.b);
  }
  return exclues;
}
