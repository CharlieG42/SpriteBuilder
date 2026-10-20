/// Modèles de données de l'Atelier Sprites.
library;

import 'dart:typed_data';

/// Vue d'une planche. Le jeu retourne l'image horizontalement pour les
/// directions vers la gauche : face + dos couvrent la grille entière.
enum Vue { face, dos }

/// Type de planche (convention de `prompts_sprites/generer_prompts.py`).
enum TypePlanche { grandRepos, grandAttaques, petitTout, objets }

/// Entrée du catalogue : héros, ennemi, boss, familier ou objet de mécanisme.
class PersonnageCatalogue {
  final String groupe;
  final String libelle;
  final String id;

  /// Héros ou boss : planches « repos/sorts » et « attaques » séparées (4 planches).
  final bool grand;

  /// Dossier relatif sous `prototype/zimut/assets/sprites/`.
  final String dossier;

  const PersonnageCatalogue({
    required this.groupe,
    required this.libelle,
    required this.id,
    required this.grand,
    required this.dossier,
  });

  @override
  String toString() => '$groupe — $libelle';
}

/// Définition d'une planche : vue + suffixes de fichiers dans l'ordre des cases.
class PlancheDef {
  final String libelle;
  final Vue vue;
  final TypePlanche type;
  final List<String> suffixes;
  final List<String> libellesPoses;

  const PlancheDef({
    required this.libelle,
    required this.vue,
    required this.type,
    required this.suffixes,
    required this.libellesPoses,
  }) : assert(suffixes.length == libellesPoses.length);

  int get nbCases => suffixes.length;
}

/// Options de traitement d'une planche.
class OptionsTraitement {
  bool detourer = true;

  /// Tolérance de couleur pour distinguer le fond du sprite (distance 0-255).
  int tolerance = 45;

  /// Largeur de la rampe d'alpha doux au bord du sprite (en pixels équivalents).
  double douceur = 1.0;

  /// Re-pousse la couleur du halo hors de la couleur du fond.
  bool decontaminer = true;

  /// Recadre chaque case dans un carré de 512 px (transparent).
  bool case512 = true;
}

/// Résultat d'un traitement de planche.
class ResultatCases {
  /// PNG par case, clé = index de case en chaîne (« 0 », « 1 », …).
  final Map<String, Uint8List> vignettes;

  /// Part de pixels considérés comme fond, en pourcentage (0-100).
  final int pourcentageFond;

  const ResultatCases(this.vignettes, this.pourcentageFond);
}

/// Demande de traitement envoyée à l'isolate (objets simples uniquement).
class DemandeCases {
  final Uint8List octets;
  final int cols;
  final int rows;
  final List<double> colX;
  final List<double> rowY;
  final List<int> indices;
  final bool detourer;
  final int tolerance;
  final double douceur;
  final bool decontaminer;
  final bool case512;

  /// Si > 0, la case est réduite pour tenir dans ce carré (aperçus rapides).
  final int tailleVignette;

  const DemandeCases({
    required this.octets,
    required this.cols,
    required this.rows,
    required this.colX,
    required this.rowY,
    required this.indices,
    required this.detourer,
    required this.tolerance,
    required this.douceur,
    required this.decontaminer,
    required this.case512,
    this.tailleVignette = 0,
  });
}
