/// Traitement d'une planche dans un isolate (décodage, détourage, découpe, PNG).
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models.dart';
import 'decoupe.dart';
import 'detourage.dart';

/// Traite une planche : décode, détour (optionnel), extrait les cases
/// demandées, les normalise et les encode en PNG. Prévu pour `compute()`.
ResultatCases traiterCases(DemandeCases d) {
  final source = img.decodeImage(d.octets);
  if (source == null) {
    throw const FormatException('Image illisible.');
  }
  var pourcentageFond = 0;
  var planche = source;
  if (planche.numChannels < 4) {
    planche = planche.convert(numChannels: 4);
  }
  if (d.detourer) {
    final stats = detourer(
      planche,
      tolerance: d.tolerance,
      douceur: d.douceur,
      decontaminer: d.decontaminer,
      interieurs: d.interieurs,
      aireMinInterieur: d.aireMinInterieur,
      rognage: d.rognage,
    );
    pourcentageFond = stats.pourcentageFond;
  }

  final grille = Grille.personnalisee(
    cols: d.cols,
    rows: d.rows,
    colX: d.colX,
    rowY: d.rowY,
  );

  // Échelle commune à toutes les cases : une pose ne doit pas être réduite
  // davantage que sa voisine (sinon le personnage « pulse » en animation).
  final ratio = !d.case512
      ? 1.0
      : (d.ratioForce > 0 ? d.ratioForce : ratioCommun(planche, grille, d.indices, coteCarre));

  final vignettes = <String, Uint8List>{};
  for (final i in d.indices) {
    final col = i % grille.cols;
    final row = i ~/ grille.cols;
    var cas = extraireCase(planche, grille, col, row);
    if (d.case512) {
      cas = normaliserCarre(
        cas,
        coteCarre,
        ratio: ratio,
        ancrage: d.ancrageSol ? Ancrage.sol : Ancrage.centre,
        margeSol: d.margeSol,
      );
      if (d.tailleVignette > 0) cas = reduire(cas, d.tailleVignette);
    } else if (d.tailleVignette > 0) {
      cas = reduire(cas, d.tailleVignette);
    }
    vignettes[i.toString()] = img.encodePng(cas);
  }

  return ResultatCases(vignettes, pourcentageFond);
}

/// Convertit des options UI en demande pour l'isolate.
DemandeCases construireDemande(
  Uint8List octets,
  Grille grille,
  OptionsTraitement options,
  List<int> indices, {
  int tailleVignette = 0,
  double ratioForce = 0,
}) {
  return DemandeCases(
    octets: octets,
    cols: grille.cols,
    rows: grille.rows,
    colX: grille.colX,
    rowY: grille.rowY,
    indices: indices,
    detourer: options.detourer,
    tolerance: options.tolerance,
    douceur: options.douceur,
    decontaminer: options.decontaminer,
    interieurs: options.interieurs,
    aireMinInterieur: options.aireMinInterieur,
    rognage: options.rognage,
    case512: options.case512,
    ancrageSol: options.ancrageSol,
    margeSol: options.margeSol,
    ratioForce: ratioForce,
    tailleVignette: tailleVignette,
  );
}

/// Dimensions et grille détectée d'une planche importée (prévu pour `compute()`).
class AnalysePlanche {
  final int largeur;
  final int hauteur;
  final int cols;
  final int rows;

  const AnalysePlanche(this.largeur, this.hauteur, this.cols, this.rows);
}

/// Décode [octets] et détecte la grille ; `null` si l'image est illisible.
AnalysePlanche? analyserPlanche(Uint8List octets) {
  final source = img.decodeImage(octets);
  if (source == null) return null;
  final g = detecterGrille(source, tolerance: 45);
  return AnalysePlanche(source.width, source.height, g.cols, g.rows);
}

/// Aperçu du détourage : original, résultat détouré et carte des zones retirées,
/// à la même taille, pour la planche entière ou une seule case (zoom). Prévu pour
/// `compute()` ; [demande] porte les réglages, [caseIndex] < 0 : planche entière.
class DemandeApercuDetour {
  final DemandeCases demande;
  final int caseIndex;
  final int tailleMax;

  const DemandeApercuDetour(this.demande, {this.caseIndex = -1, this.tailleMax = 1100});
}

class ApercuDetour {
  final Uint8List original;
  final Uint8List detoure;

  /// Rouge translucide là où le fond a été retiré (transparent ailleurs).
  final Uint8List retrait;
  final int largeur;
  final int hauteur;
  final int pourcentageFond;

  const ApercuDetour({
    required this.original,
    required this.detoure,
    required this.retrait,
    required this.largeur,
    required this.hauteur,
    required this.pourcentageFond,
  });
}

ApercuDetour apercuDetourage(DemandeApercuDetour a) {
  final d = a.demande;
  final source = img.decodeImage(d.octets);
  if (source == null) throw const FormatException('Image illisible.');
  var original = source.numChannels < 4 ? source.convert(numChannels: 4) : source;
  var planche = original.clone();
  var pourcentage = 0;
  if (d.detourer) {
    pourcentage = detourer(
      planche,
      tolerance: d.tolerance,
      douceur: d.douceur,
      decontaminer: d.decontaminer,
      interieurs: d.interieurs,
      aireMinInterieur: d.aireMinInterieur,
      rognage: d.rognage,
    ).pourcentageFond;
  }
  if (a.caseIndex >= 0) {
    final g = Grille.personnalisee(cols: d.cols, rows: d.rows, colX: d.colX, rowY: d.rowY);
    final col = a.caseIndex % g.cols;
    final row = a.caseIndex ~/ g.cols;
    original = extraireCase(original, g, col, row);
    planche = extraireCase(planche, g, col, row);
  }
  original = reduire(original, a.tailleMax);
  planche = reduire(planche, a.tailleMax);

  final retrait = img.Image(width: planche.width, height: planche.height, numChannels: 4);
  for (var y = 0; y < planche.height; y++) {
    for (var x = 0; x < planche.width; x++) {
      final manque = 255 - planche.getPixel(x, y).a.toInt();
      if (manque > 0) retrait.setPixelRgba(x, y, 235, 30, 50, (manque * 0.6).round());
    }
  }
  return ApercuDetour(
    original: img.encodePng(original),
    detoure: img.encodePng(planche),
    retrait: img.encodePng(retrait),
    largeur: planche.width,
    hauteur: planche.height,
    pourcentageFond: pourcentage,
  );
}
