/// Projet « personnage » : plusieurs planches (grilles différentes possibles)
/// préparées ensemble et exportées dans un seul zip.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'core/decoupe.dart';
import 'core/doublons.dart';
import 'data/catalog.dart';
import 'models.dart';

/// Une planche importée et ses réglages propres (grille, cases, nommage).
class PlancheProjet {
  Uint8List octets;
  String nomFichier;
  int imageW;
  int imageH;
  Grille grille;

  /// Type de planche attribué (`null` : à attribuer).
  PlancheDef? planche;

  /// Position de la première case dans la planche (planche coupée en deux images).
  int premiereCase = 1;

  final Set<int> exclues = <int>{};
  final Map<int, String> renommages = <int, String>{};

  /// L'utilisateur a ouvert la planche et vérifié ses cases.
  bool verifiee = false;

  // Aperçus (non persistants, invalidés par les réglages).
  Map<String, Uint8List> vignettes = <String, Uint8List>{};
  Uint8List? apercuDetour;
  int pourcentageFond = -1;
  Map<int, Uint8List>? cacheAnim;
  bool? cacheAnimSol;

  /// Poses en double détectées sur les vignettes (index de case de cette planche).
  List<Doublon> doublons = const <Doublon>[];

  PlancheProjet({
    required this.octets,
    required this.nomFichier,
    required this.imageW,
    required this.imageH,
    required this.grille,
    this.planche,
  });

  void invaliderApercus() {
    vignettes = <String, Uint8List>{};
    apercuDetour = null;
    doublons = const <Doublon>[];
    cacheAnim = null;
    cacheAnimSol = null;
  }

  /// Cases incluses, dans l'ordre de la planche.
  List<int> get indicesInclus => <int>[
        for (var i = 0; i < grille.nbCases; i++)
          if (!exclues.contains(i)) i,
      ];

  /// Position (0-based) de la case dans la convention de la planche, ou -1.
  int _position(int index) {
    final rang = indicesInclus.indexOf(index);
    if (rang < 0) return -1;
    return premiereCase - 1 + rang;
  }

  /// Suffixe de pose de la case, `null` si inconnu (objets, hors planche).
  String? suffixeCase(int index) {
    final pl = planche;
    if (pl == null || pl.type == TypePlanche.objets) return null;
    final p = _position(index);
    if (p < 0 || p >= pl.suffixes.length) return null;
    return pl.suffixes[p];
  }

  String libellePose(int index) {
    final pl = planche;
    if (pl == null) return 'case ${index + 1}';
    if (pl.type == TypePlanche.objets) return 'objet';
    final p = _position(index);
    if (p < 0 || p >= pl.libellesPoses.length) return 'case ${index + 1}';
    return pl.libellesPoses[p];
  }

  /// Nom de fichier par défaut d'une case (convention EntityView.gd).
  String nomPrevu(int index, PersonnageCatalogue perso) {
    final pl = planche!;
    if (pl.type == TypePlanche.objets) {
      final renom = renommages[index] ?? '';
      return renom.isEmpty ? 'objet_${index + 1}' : renom;
    }
    final p = _position(index);
    if (p < 0 || p >= pl.suffixes.length) {
      return nomFichierPour(id: perso.id, planche: pl, suffix: '_${index + 1}');
    }
    return nomFichierPour(id: perso.id, planche: pl, suffix: pl.suffixes[p]);
  }

  /// Nom final (renommage manuel prioritaire), toujours en `.png`.
  String nomFinal(int index, PersonnageCatalogue perso) {
    final renom = renommages[index] ?? '';
    if (renom.isNotEmpty) return renom.endsWith('.png') ? renom : '$renom.png';
    return nomPrevu(index, perso);
  }

  void prefillerObjets() {
    renommages.clear();
    for (var i = 0; i < grille.nbCases && i < mecanismes.length; i++) {
      renommages[i] = mecanismes[i].id;
    }
  }

  /// Plus grand côté d'une case incluse, en pixels de l'image.
  double get plusGrandeCase {
    var m = 1.0;
    for (final i in indicesInclus) {
      final col = i % grille.cols;
      final row = i ~/ grille.cols;
      final w = (grille.colX[col + 1] - grille.colX[col]) * imageW;
      final h = (grille.rowY[row + 1] - grille.rowY[row]) * imageH;
      m = math.max(m, math.max(w, h));
    }
    return m;
  }
}

/// Un personnage et toutes ses planches.
class ProjetPersonnage {
  PersonnageCatalogue? perso;
  final List<PlancheProjet> planches = <PlancheProjet>[];

  /// Réglages de détourage et d'export communs à toutes les planches.
  final OptionsTraitement options = OptionsTraitement();

  ProjetPersonnage({this.perso});

  /// Échelle commune (≤ 1) à toutes les planches : le personnage garde la
  /// même taille d'une planche à l'autre dans les carrés exportés.
  double get ratioCommun {
    var m = 1.0;
    for (final p in planches) {
      if (p.planche == null) continue;
      m = math.max(m, p.plusGrandeCase);
    }
    return math.min(1.0, coteCarre / m);
  }

  /// Planches prêtes à l'export (type attribué, au moins une case).
  List<PlancheProjet> get planchesExportables => <PlancheProjet>[
        for (final p in planches)
          if (p.planche != null && p.indicesInclus.isNotEmpty) p,
      ];

  /// Quand le personnage change, les types de planche incompatibles sont retirés.
  void changerPerso(PersonnageCatalogue p) {
    perso = p;
    final valides = planchesPour(p);
    for (final pl in planches) {
      if (pl.planche != null && !valides.contains(pl.planche)) pl.planche = null;
      if (pl.planche?.type == TypePlanche.objets) pl.prefillerObjets();
    }
  }

  /// Première case conseillée pour une nouvelle planche de type [def] : à la
  /// suite des cases déjà couvertes par les autres planches du même type
  /// (planche coupée en deux images).
  int premiereCaseSuggeree(PlancheDef def, {PlancheProjet? sauf}) {
    var couvertes = 0;
    for (final p in planches) {
      if (identical(p, sauf) || p.planche != def) continue;
      couvertes = math.max(couvertes, p.premiereCase - 1 + p.indicesInclus.length);
    }
    return couvertes >= def.nbCases ? 1 : couvertes + 1;
  }

  /// Nom du zip du personnage.
  String get nomZip => 'zimut_sprites_${perso?.id ?? 'planches'}.zip';
}

/// Problème détecté avant l'export.
class Alerte {
  final bool bloquante;
  final String texte;

  const Alerte(this.texte, {this.bloquante = false});

  @override
  String toString() => texte;
}

/// Contrôles du projet : planches sans type, noms en double, poses manquantes.
List<Alerte> controlerProjet(ProjetPersonnage projet) {
  final perso = projet.perso;
  final alertes = <Alerte>[];
  if (perso == null) {
    return const [Alerte('Choisis le personnage.', bloquante: true)];
  }
  for (final p in projet.planches) {
    if (p.planche == null) {
      alertes.add(Alerte('${p.nomFichier} : type de planche à attribuer.', bloquante: true));
    } else if (p.indicesInclus.isEmpty) {
      alertes.add(Alerte('${p.nomFichier} : toutes les cases sont exclues.'));
    }
    // Poses en double (V36) : signalées tant qu'elles restent incluses.
    final identiques = p.doublons.where((d) => d.identique && !p.exclues.contains(d.a) && !p.exclues.contains(d.b));
    if (identiques.isNotEmpty) {
      final paires = identiques.map((d) => '${d.a + 1}/${d.b + 1}').join(', ');
      alertes.add(Alerte('${p.nomFichier} : poses en double (cases $paires) — régénère la planche ou exclus-les.'));
    }
  }

  // Doublons : deux cases (même planche ou non) qui produiraient le même fichier.
  final origines = <String, List<String>>{};
  for (final p in projet.planchesExportables) {
    for (final i in p.indicesInclus) {
      origines.putIfAbsent(p.nomFinal(i, perso), () => <String>[]).add('${p.nomFichier} case ${i + 1}');
    }
  }
  for (final e in origines.entries) {
    if (e.value.length > 1) {
      alertes.add(Alerte('${e.key} en double : ${e.value.join(', ')}.', bloquante: true));
    }
  }

  // Manques : poses attendues par planche présente (les planches jamais
  // importées ne sont pas signalées, on peut exporter en plusieurs fois).
  final types = <PlancheDef>{for (final p in projet.planchesExportables) p.planche!};
  for (final def in types) {
    if (def.type == TypePlanche.objets) continue;
    final manquants = <String>[
      for (final s in def.suffixes)
        if (!origines.containsKey(nomFichierPour(id: perso.id, planche: def, suffix: s)))
          nomFichierPour(id: perso.id, planche: def, suffix: s),
    ];
    if (manquants.isNotEmpty) {
      alertes.add(Alerte('${def.libelle} : manque ${manquants.join(', ')}.'));
    }
  }
  return alertes;
}
