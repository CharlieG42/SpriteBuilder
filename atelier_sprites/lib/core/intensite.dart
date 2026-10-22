/// Intensité du détourage : un seul curseur (léger → très fort) qui règle
/// ensemble la tolérance, le rognage du bord et la douceur.
library;

import '../models.dart';

class NiveauDetourage {
  final String libelle;
  final String aide;
  final int tolerance;
  final int rognage;
  final double douceur;
  final bool interieurs;

  const NiveauDetourage(this.libelle, this.aide, this.tolerance, this.rognage, this.douceur,
      {this.interieurs = true});
}

const List<NiveauDetourage> niveauxDetourage = [
  NiveauDetourage('Très doux', 'Persos très clairs (cheveux, tenue blancs) : ne retire que le fond évident, rend du bord.', 10, -2, 2.0,
      interieurs: false),
  NiveauDetourage('Doux', 'Persos clairs : garde les zones pâles et les contours fins.', 20, -1, 1.5),
  NiveauDetourage('Normal', 'Réglage par défaut.', 45, 0, 1.0),
  NiveauDetourage('Fort', 'Retire le liseré clair autour du sprite.', 65, 1, 0.75),
  NiveauDetourage('Très fort', 'Halo épais ou fond irrégulier ; vérifie les zones claires.', 85, 2, 0.5),
];

/// Niveau correspondant exactement aux options, ou -1 (réglage personnalisé).
int niveauDe(OptionsTraitement o) {
  for (var i = 0; i < niveauxDetourage.length; i++) {
    final n = niveauxDetourage[i];
    if (o.tolerance == n.tolerance && o.rognage == n.rognage && o.interieurs == n.interieurs && (o.douceur - n.douceur).abs() < 1e-9) {
      return i;
    }
  }
  return -1;
}

void appliquerNiveau(OptionsTraitement o, int i) {
  final n = niveauxDetourage[i];
  o
    ..tolerance = n.tolerance
    ..rognage = n.rognage
    ..douceur = n.douceur
    ..interieurs = n.interieurs;
}
