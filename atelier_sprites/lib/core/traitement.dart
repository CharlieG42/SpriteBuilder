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
  if (d.detourer) {
    final stats = detourer(
      planche,
      tolerance: d.tolerance,
      douceur: d.douceur,
      decontaminer: d.decontaminer,
    );
    pourcentageFond = stats.pourcentageFond;
  }

  final grille = Grille.personnalisee(
    cols: d.cols,
    rows: d.rows,
    colX: d.colX,
    rowY: d.rowY,
  );

  final vignettes = <String, Uint8List>{};
  for (final i in d.indices) {
    final col = i % grille.cols;
    final row = i ~/ grille.cols;
    var cas = extraireCase(planche, grille, col, row);
    if (d.case512) {
      cas = normaliserCarre(cas, 512);
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
    case512: options.case512,
    tailleVignette: tailleVignette,
  );
}
