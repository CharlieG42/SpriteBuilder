/// Regroupement des cases d'une planche en animations jouables
/// (repos, marche, sort, attaque) d'après les suffixes EntityView.gd.
library;

/// Famille d'animation déduite d'un suffixe de fichier.
enum FamilleAnim { repos, marche, sort, attaque, autre }

/// Famille d'un suffixe (`''`, `_idle_2` → repos ; `_walk*` → marche ;
/// `_cast*` → sort ; `_attack*` → attaque).
FamilleAnim familleDuSuffixe(String suffixe) {
  if (suffixe.isEmpty || suffixe.startsWith('_idle')) return FamilleAnim.repos;
  if (suffixe.startsWith('_walk')) return FamilleAnim.marche;
  if (suffixe.startsWith('_cast')) return FamilleAnim.sort;
  if (suffixe.startsWith('_attack')) return FamilleAnim.attaque;
  return FamilleAnim.autre;
}

/// Libellé affiché d'une famille.
String libelleFamille(FamilleAnim f) => switch (f) {
      FamilleAnim.repos => 'Repos',
      FamilleAnim.marche => 'Marche',
      FamilleAnim.sort => 'Sort',
      FamilleAnim.attaque => 'Attaque',
      FamilleAnim.autre => 'Autres',
    };

/// Cadence par défaut (images/s) d'une famille : repos lent, attaque nerveuse.
int fpsParDefaut(FamilleAnim f) => switch (f) {
      FamilleAnim.repos => 4,
      FamilleAnim.marche => 6,
      FamilleAnim.sort => 8,
      FamilleAnim.attaque => 10,
      FamilleAnim.autre => 6,
    };

/// Une animation : liste ordonnée d'index de cases de la planche.
class AnimationDef {
  final String libelle;
  final FamilleAnim? famille;
  final List<int> cases;
  final int fps;
  final bool allerRetour;

  const AnimationDef({
    required this.libelle,
    required this.famille,
    required this.cases,
    required this.fps,
    this.allerRetour = false,
  });
}

/// Construit les animations d'une planche.
///
/// [suffixeParCase] associe chaque case incluse (dans l'ordre de la planche)
/// à son suffixe ; `null` si la case n'a pas de pose connue. Une animation
/// « Toutes les cases » est toujours ajoutée en dernier.
List<AnimationDef> animationsPour(Map<int, String?> suffixeParCase) {
  final parFamille = <FamilleAnim, List<int>>{};
  for (final e in suffixeParCase.entries) {
    final s = e.value;
    if (s == null) continue;
    parFamille.putIfAbsent(familleDuSuffixe(s), () => <int>[]).add(e.key);
  }
  final sortie = <AnimationDef>[];
  for (final f in FamilleAnim.values) {
    final cases = parFamille[f];
    if (cases == null || cases.isEmpty) continue;
    sortie.add(AnimationDef(
      libelle: libelleFamille(f),
      famille: f,
      cases: cases,
      fps: fpsParDefaut(f),
      allerRetour: f == FamilleAnim.repos && cases.length > 2,
    ));
  }
  sortie.add(AnimationDef(
    libelle: 'Toutes les cases',
    famille: null,
    cases: suffixeParCase.keys.toList(),
    fps: 4,
  ));
  return sortie;
}

/// Séquence jouée : les cases, puis en aller-retour les cases intérieures à
/// rebours (1 2 3 4 → 1 2 3 4 3 2) pour éviter de doubler les extrémités.
List<int> sequenceLecture(List<int> cases, {required bool allerRetour}) {
  if (!allerRetour || cases.length < 3) return List<int>.of(cases);
  return <int>[
    ...cases,
    for (var i = cases.length - 2; i >= 1; i--) cases[i],
  ];
}

/// Animations d'un personnage à plusieurs planches : les cases d'une même vue
/// (ex. « Face ») sont fusionnées puis regroupées par famille (« Face · Repos »,
/// « Dos · Attaque »…). [groupes] associe un libellé de vue aux suffixes de ses
/// cases (clés globales, uniques entre planches).
List<AnimationDef> animationsProjet(Map<String, Map<int, String?>> groupes) {
  final sortie = <AnimationDef>[];
  final toutes = <int>[];
  for (final g in groupes.entries) {
    toutes.addAll(g.value.keys);
    for (final a in animationsPour(g.value)) {
      if (a.famille == null) continue;
      sortie.add(AnimationDef(
        libelle: '${g.key} · ${a.libelle}',
        famille: a.famille,
        cases: a.cases,
        fps: a.fps,
        allerRetour: a.allerRetour,
      ));
    }
  }
  if (sortie.isEmpty) {
    sortie.add(AnimationDef(libelle: 'Toutes les cases', famille: null, cases: toutes, fps: 4));
  }
  return sortie;
}
