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

  const NiveauDetourage(this.libelle, this.aide, this.tolerance, this.rognage, this.douceur);
}

const List<NiveauDetourage> niveauxDetourage = [
  NiveauDetourage('Léger', 'Garde un peu de bord : sprites clairs, contours fins.', 30, -1, 1.5),
  NiveauDetourage('Normal', 'Réglage par défaut.', 45, 0, 1.0),
  NiveauDetourage('Fort', 'Retire le liseré clair autour du sprite.', 65, 1, 0.75),
  NiveauDetourage('Très fort', 'Halo épais ou fond irrégulier ; vérifie les zones claires.', 85, 2, 0.5),
];

/// Niveau correspondant exactement aux options, ou -1 (réglage personnalisé).
int niveauDe(OptionsTraitement o) {
  for (var i = 0; i < niveauxDetourage.length; i++) {
    final n = niveauxDetourage[i];
    if (o.tolerance == n.tolerance && o.rognage == n.rognage && (o.douceur - n.douceur).abs() < 1e-9) {
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
    ..douceur = n.douceur;
}
