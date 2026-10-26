/// Modèles de données de l'Atelier Sprites.
library;

import 'dart:typed_data';

/// Vue d'une planche. Le jeu retourne l'image horizontalement pour les
/// directions vers la gauche : face + dos couvrent la grille entière.
enum Vue { face, dos }

/// Type de planche (convention de `prompts_sprites/generer_prompts.py`, V36) :
/// fiche de référence (repos de face + repos de dos), planche de 4 poses
/// (grille 2 × 2, une seule vue), objets fixes.
enum TypePlanche { reference, poses, objets }

/// Entrée du catalogue : héros, ennemi, boss, familier ou objet de mécanisme.
class PersonnageCatalogue {
  final String groupe;
  final String libelle;
  final String id;

  /// Héros ou boss : 6 planches (référence + 5 planches de 4 poses) ;
  /// sinon 3 planches (référence + face + dos).
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
  /// Clé courte (nom du zip, présélection) : `ref`, `face_1`, `dos_2`, `objets`…
  final String cle;
  final String libelle;
  final Vue vue;
  final TypePlanche type;
  final List<String> suffixes;
  final List<String> libellesPoses;

  const PlancheDef({
    required this.cle,
    required this.libelle,
    required this.vue,
    required this.type,
    required this.suffixes,
    required this.libellesPoses,
  });

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

  /// Déroute aussi les poches de fond enfermées dans le sprite (entre les membres).
  bool interieurs = true;

  /// Aire minimale (pixels) d'une poche intérieure pour être retirée.
  int aireMinInterieur = 24;

  /// Rognage du bord en pixels : > 0 grignote le liseré, < 0 rend du bord.
  int rognage = 0;

  /// Recadre chaque case dans un carré de 512 px (transparent).
  bool case512 = true;

  /// Dans le carré 512 : aligne le bas du sprite sur une ligne de sol commune
  /// (les pieds ne « sautent » plus d'une pose à l'autre) au lieu de centrer la case.
  bool ancrageSol = false;

  /// Hauteur de la ligne de sol au-dessus du bas du carré (fraction 0-0.3).
  double margeSol = 0.06;

  OptionsTraitement copie() => OptionsTraitement()
    ..detourer = detourer
    ..tolerance = tolerance
    ..douceur = douceur
    ..decontaminer = decontaminer
    ..interieurs = interieurs
    ..aireMinInterieur = aireMinInterieur
    ..rognage = rognage
    ..case512 = case512
    ..ancrageSol = ancrageSol
    ..margeSol = margeSol;
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
  final bool interieurs;
  final int aireMinInterieur;
  final int rognage;
  final bool case512;
  final bool ancrageSol;
  final double margeSol;

  /// Échelle imposée dans le carré 512 (> 0), commune à plusieurs planches ;
  /// 0 : calculée sur les cases de cette planche.
  final double ratioForce;

  /// Si > 0, la case est réduite pour tenir dans ce carré (aperçus rapides) ;
  /// avec [case512], c'est le carré normalisé qui est réduit à cette taille.
  final int tailleVignette;

  /// Retouche à la main (un octet par pixel de la planche) : 0 auto, 1 supprimé,
  /// 2 protégé ; `null` : planche non retouchée.
  final Uint8List? forces;

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
    required this.interieurs,
    required this.aireMinInterieur,
    this.rognage = 0,
    required this.case512,
    this.ancrageSol = false,
    this.margeSol = 0.06,
    this.ratioForce = 0,
    this.tailleVignette = 0,
    this.forces,
  });
}
