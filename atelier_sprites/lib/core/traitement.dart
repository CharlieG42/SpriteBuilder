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
