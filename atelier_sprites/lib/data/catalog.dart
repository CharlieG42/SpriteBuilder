/// Catalogue des personnages de Zimut et conventions de nommage.
///
/// Source de vérité : `prompts_sprites/generer_prompts.py` (NATIONS,
/// FAMILIERS, MECANISMES, SHEETS_BIG, SHEETS_SMALL, file_suffix) et
/// `scripts/EntityView.gd` (V34) pour les noms de fichiers.
library;

import '../models.dart';

/// Racine des sprites dans le dépôt Zimut.
const String racineAssets = 'prototype/zimut/assets/sprites';

// --------------------------------------------------------------------------------------------
// Planches
// --------------------------------------------------------------------------------------------

const List<String> _suffixesGrandRepos = [
  '', '_idle_2', '_idle_3', '_walk', '_walk_2', '_cast', '_cast_2', '_cast_3',
];
const List<String> _libellesGrandRepos = [
  'repos 1', 'repos 2', 'repos 3', 'marche 1', 'marche 2', 'sort 1', 'sort 2', 'sort 3',
];
const List<String> _suffixesGrandAttaques = [
  '_attack', '_attack_2', '_attack_3', '_attack_4',
  '_attack_5', '_attack_6', '_attack_7', '_attack_8',
];
const List<String> _libellesGrandAttaques = [
  'attaque 1', 'attaque 2', 'attaque 3', 'attaque 4',
  'attaque 5', 'attaque 6', 'attaque 7', 'attaque 8',
];
const List<String> _suffixesPetit = [
  '', '_idle_2', '_walk', '_attack', '_attack_2', '_attack_3', '_attack_4', '_cast',
];
const List<String> _libellesPetit = [
  'repos 1', 'repos 2', 'marche 1', 'attaque 1', 'attaque 2', 'attaque 3', 'attaque 4', 'sort 1',
];

const List<PlancheDef> planchesGrand = [
  PlancheDef(
    libelle: 'Face (3/4 avant) · Repos, marche et sorts',
    vue: Vue.face,
    type: TypePlanche.grandRepos,
    suffixes: _suffixesGrandRepos,
    libellesPoses: _libellesGrandRepos,
  ),
  PlancheDef(
    libelle: 'Face (3/4 avant) · Attaques',
    vue: Vue.face,
    type: TypePlanche.grandAttaques,
    suffixes: _suffixesGrandAttaques,
    libellesPoses: _libellesGrandAttaques,
  ),
  PlancheDef(
    libelle: 'Dos (3/4 arrière) · Repos, marche et sorts',
    vue: Vue.dos,
    type: TypePlanche.grandRepos,
    suffixes: _suffixesGrandRepos,
    libellesPoses: _libellesGrandRepos,
  ),
  PlancheDef(
    libelle: 'Dos (3/4 arrière) · Attaques',
    vue: Vue.dos,
    type: TypePlanche.grandAttaques,
    suffixes: _suffixesGrandAttaques,
    libellesPoses: _libellesGrandAttaques,
  ),
];

const List<PlancheDef> planchesPetit = [
  PlancheDef(
    libelle: 'Face (3/4 avant)',
    vue: Vue.face,
    type: TypePlanche.petitTout,
    suffixes: _suffixesPetit,
    libellesPoses: _libellesPetit,
  ),
  PlancheDef(
    libelle: 'Dos (3/4 arrière)',
    vue: Vue.dos,
    type: TypePlanche.petitTout,
    suffixes: _suffixesPetit,
    libellesPoses: _libellesPetit,
  ),
];

const PlancheDef plancheObjets = PlancheDef(
  libelle: 'Objets (une pose par objet)',
  vue: Vue.face,
  type: TypePlanche.objets,
  suffixes: [''],
  libellesPoses: ['objet'],
);

List<PlancheDef> planchesPour(PersonnageCatalogue p) {
  if (p.grand) return planchesGrand;
  if (mecanismes.contains(p)) return const [plancheObjets];
  return planchesPetit;
}

/// Nom de fichier pour une pose : `<id><suffixe>.png`, précédé de `_back`
/// pour la vue de dos ; les objets fixes n'ont pas de suffixe.
String nomFichierPour({
  required String id,
  required PlancheDef planche,
  required String suffix,
}) {
  if (planche.type == TypePlanche.objets) return '$id.png';
  if (planche.vue == Vue.dos) return '${id}_back$suffix.png';
  return '$id$suffix.png';
}

// --------------------------------------------------------------------------------------------
// Nations (scripts/Nations.gd) : héros, 4 ennemis, boss
// --------------------------------------------------------------------------------------------

class _Nation {
  final String id;
  final String nom;
  final PersonnageCatalogue heros;
  final List<PersonnageCatalogue> ennemis;
  final PersonnageCatalogue boss;

  const _Nation(this.id, this.nom, this.heros, this.ennemis, this.boss);
}

const List<_Nation> nations = [
  _Nation('sylvestre', 'Sylvestre',
    PersonnageCatalogue(groupe: 'Nation Sylvestre', libelle: 'Druide (héros)', id: 'druide', grand: true, dossier: 'players'),
    [
      PersonnageCatalogue(groupe: 'Nation Sylvestre', libelle: 'Araknéa', id: 'araknea', grand: false, dossier: 'nations/ennemis/sylvestre'),
      PersonnageCatalogue(groupe: 'Nation Sylvestre', libelle: 'Loup forestier', id: 'loup_forestier', grand: false, dossier: 'nations/ennemis/sylvestre'),
      PersonnageCatalogue(groupe: 'Nation Sylvestre', libelle: 'Dryade', id: 'dryade', grand: false, dossier: 'nations/ennemis/sylvestre'),
      PersonnageCatalogue(groupe: 'Nation Sylvestre', libelle: 'Tréant', id: 'treant', grand: false, dossier: 'nations/ennemis/sylvestre'),
    ],
    PersonnageCatalogue(groupe: 'Nation Sylvestre', libelle: 'Tharok le Végétal (boss)', id: 'sylvestre', grand: true, dossier: 'nations/boss'),
  ),
  _Nation('cimes', 'Cimes',
    PersonnageCatalogue(groupe: 'Nation Cimes', libelle: 'Tank (héros)', id: 'tank', grand: true, dossier: 'players'),
    [
      PersonnageCatalogue(groupe: 'Nation Cimes', libelle: 'Guerrier des monts', id: 'guerrier_des_monts', grand: false, dossier: 'nations/ennemis/cimes'),
      PersonnageCatalogue(groupe: 'Nation Cimes', libelle: 'Griffon des cimes', id: 'griffon_des_cimes', grand: false, dossier: 'nations/ennemis/cimes'),
      PersonnageCatalogue(groupe: 'Nation Cimes', libelle: 'Garde des pics', id: 'garde_des_pics', grand: false, dossier: 'nations/ennemis/cimes'),
      PersonnageCatalogue(groupe: 'Nation Cimes', libelle: 'Rochebrute', id: 'rochebrute', grand: false, dossier: 'nations/ennemis/cimes'),
    ],
    PersonnageCatalogue(groupe: 'Nation Cimes', libelle: 'Vorkann le Givre (boss)', id: 'cimes', grand: true, dossier: 'nations/boss'),
  ),
  _Nation('sables', 'Sables',
    PersonnageCatalogue(groupe: 'Nation Sables', libelle: 'Géomancien (héros)', id: 'geomancien', grand: true, dossier: 'players'),
    [
      PersonnageCatalogue(groupe: 'Nation Sables', libelle: 'Bandit des dunes', id: 'bandit_des_dunes', grand: false, dossier: 'nations/ennemis/sables'),
      PersonnageCatalogue(groupe: 'Nation Sables', libelle: 'Scarabée géant', id: 'scarabee_geant', grand: false, dossier: 'nations/ennemis/sables'),
      PersonnageCatalogue(groupe: 'Nation Sables', libelle: 'Génie du désert', id: 'genie_du_desert', grand: false, dossier: 'nations/ennemis/sables'),
      PersonnageCatalogue(groupe: 'Nation Sables', libelle: 'Sphinx', id: 'sphinx', grand: false, dossier: 'nations/ennemis/sables'),
    ],
    PersonnageCatalogue(groupe: 'Nation Sables', libelle: 'Zahor le Sableux (boss)', id: 'sables', grand: true, dossier: 'nations/boss'),
  ),
  _Nation('cristaux', 'Cristaux',
    PersonnageCatalogue(groupe: 'Nation Cristaux', libelle: 'Mage (héros)', id: 'mage', grand: true, dossier: 'players'),
    [
      PersonnageCatalogue(groupe: 'Nation Cristaux', libelle: 'Araignée de cristal', id: 'araignee_de_cristal', grand: false, dossier: 'nations/ennemis/cristaux'),
      PersonnageCatalogue(groupe: 'Nation Cristaux', libelle: 'Mage cristallin', id: 'mage_cristallin', grand: false, dossier: 'nations/ennemis/cristaux'),
      PersonnageCatalogue(groupe: 'Nation Cristaux', libelle: 'Golem de cristal', id: 'golem_de_cristal', grand: false, dossier: 'nations/ennemis/cristaux'),
      PersonnageCatalogue(groupe: 'Nation Cristaux', libelle: 'Élémentaire de cristal', id: 'elementaire_de_cristal', grand: false, dossier: 'nations/ennemis/cristaux'),
    ],
    PersonnageCatalogue(groupe: 'Nation Cristaux', libelle: 'Zyphéron le Cristallin (boss)', id: 'cristaux', grand: true, dossier: 'nations/boss'),
  ),
  _Nation('marees', 'Marées',
    PersonnageCatalogue(groupe: 'Nation Marées', libelle: 'Heal (héros)', id: 'heal', grand: true, dossier: 'players'),
    [
      PersonnageCatalogue(groupe: 'Nation Marées', libelle: 'Pirate des mers', id: 'pirate_des_mers', grand: false, dossier: 'nations/ennemis/marees'),
      PersonnageCatalogue(groupe: 'Nation Marées', libelle: 'Requin', id: 'requin', grand: false, dossier: 'nations/ennemis/marees'),
      PersonnageCatalogue(groupe: 'Nation Marées', libelle: 'Néréide', id: 'nereide', grand: false, dossier: 'nations/ennemis/marees'),
      PersonnageCatalogue(groupe: 'Nation Marées', libelle: 'Crabe géant', id: 'crabe_geant', grand: false, dossier: 'nations/ennemis/marees'),
    ],
    PersonnageCatalogue(groupe: 'Nation Marées', libelle: 'Néréa la Tempête (boss)', id: 'marees', grand: true, dossier: 'nations/boss'),
  ),
  _Nation('vents', 'Vents',
    PersonnageCatalogue(groupe: 'Nation Vents', libelle: 'Sylvain (héros)', id: 'sylvain', grand: true, dossier: 'players'),
    [
      PersonnageCatalogue(groupe: 'Nation Vents', libelle: 'Garde aérien', id: 'garde_aerien', grand: false, dossier: 'nations/ennemis/vents'),
      PersonnageCatalogue(groupe: 'Nation Vents', libelle: 'Aigle céleste', id: 'aigle_celeste', grand: false, dossier: 'nations/ennemis/vents'),
      PersonnageCatalogue(groupe: 'Nation Vents', libelle: 'Harpie', id: 'harpie', grand: false, dossier: 'nations/ennemis/vents'),
      PersonnageCatalogue(groupe: 'Nation Vents', libelle: 'Élémentaire de vent', id: 'elementaire_de_vent', grand: false, dossier: 'nations/ennemis/vents'),
    ],
    PersonnageCatalogue(groupe: 'Nation Vents', libelle: 'Aéron le Céleste (boss)', id: 'vents', grand: true, dossier: 'nations/boss'),
  ),
  _Nation('brasier', 'Brasier',
    PersonnageCatalogue(groupe: 'Nation Brasier', libelle: 'Chasseur (héros)', id: 'chasseur', grand: true, dossier: 'players'),
    [
      PersonnageCatalogue(groupe: 'Nation Brasier', libelle: 'Lieutenant', id: 'lieutenant', grand: false, dossier: 'nations/ennemis/brasier'),
      PersonnageCatalogue(groupe: 'Nation Brasier', libelle: 'Salamandre', id: 'salamandre', grand: false, dossier: 'nations/ennemis/brasier'),
      PersonnageCatalogue(groupe: 'Nation Brasier', libelle: 'Dévoreur de flammes', id: 'devoreur_de_flammes', grand: false, dossier: 'nations/ennemis/brasier'),
      PersonnageCatalogue(groupe: 'Nation Brasier', libelle: 'Golem de lave', id: 'golem_de_lave', grand: false, dossier: 'nations/ennemis/brasier'),
    ],
    PersonnageCatalogue(groupe: 'Nation Brasier', libelle: 'Kharaz le Flamboyant (boss)', id: 'brasier', grand: true, dossier: 'nations/boss'),
  ),
  _Nation('brumes', 'Brumes',
    PersonnageCatalogue(groupe: 'Nation Brumes', libelle: 'Invocateur (héros)', id: 'invocateur', grand: true, dossier: 'players'),
    [
      PersonnageCatalogue(groupe: 'Nation Brumes', libelle: 'Brumeux', id: 'brumeux', grand: false, dossier: 'nations/ennemis/brumes'),
      PersonnageCatalogue(groupe: 'Nation Brumes', libelle: 'Gargouille', id: 'gargouille', grand: false, dossier: 'nations/ennemis/brumes'),
      PersonnageCatalogue(groupe: 'Nation Brumes', libelle: 'Liche des brumes', id: 'liche_des_brumes', grand: false, dossier: 'nations/ennemis/brumes'),
      PersonnageCatalogue(groupe: 'Nation Brumes', libelle: 'Fantôme', id: 'fantome', grand: false, dossier: 'nations/ennemis/brumes'),
    ],
    PersonnageCatalogue(groupe: 'Nation Brumes', libelle: 'Ombrelis le Brumeux (boss)', id: 'brumes', grand: true, dossier: 'nations/boss'),
  ),
  _Nation('ombres', 'Ombres',
    PersonnageCatalogue(groupe: 'Nation Ombres', libelle: 'Assassin (héros)', id: 'assassin', grand: true, dossier: 'players'),
    [
      PersonnageCatalogue(groupe: 'Nation Ombres', libelle: 'Assassin des ombres', id: 'assassin_des_ombres', grand: false, dossier: 'nations/ennemis/ombres'),
      PersonnageCatalogue(groupe: 'Nation Ombres', libelle: 'Ombre infernale', id: 'ombre_infernale', grand: false, dossier: 'nations/ennemis/ombres'),
      PersonnageCatalogue(groupe: 'Nation Ombres', libelle: 'Spectre', id: 'spectre', grand: false, dossier: 'nations/ennemis/ombres'),
      PersonnageCatalogue(groupe: 'Nation Ombres', libelle: 'Liche', id: 'liche', grand: false, dossier: 'nations/ennemis/ombres'),
    ],
    PersonnageCatalogue(groupe: 'Nation Ombres', libelle: 'Nébulia l\'Illusionniste (boss)', id: 'ombres', grand: true, dossier: 'nations/boss'),
  ),
  _Nation('rouages', 'Rouages',
    PersonnageCatalogue(groupe: 'Nation Rouages', libelle: 'Artificier (héros)', id: 'artificier', grand: true, dossier: 'players'),
    [
      PersonnageCatalogue(groupe: 'Nation Rouages', libelle: 'Drone aérien', id: 'drone_aerien', grand: false, dossier: 'nations/ennemis/rouages'),
      PersonnageCatalogue(groupe: 'Nation Rouages', libelle: 'Araignée mécanique', id: 'araignee_mecanique', grand: false, dossier: 'nations/ennemis/rouages'),
      PersonnageCatalogue(groupe: 'Nation Rouages', libelle: 'Roue engrenée', id: 'roue_engrenee', grand: false, dossier: 'nations/ennemis/rouages'),
      PersonnageCatalogue(groupe: 'Nation Rouages', libelle: 'Automate de combat', id: 'automate_de_combat', grand: false, dossier: 'nations/ennemis/rouages'),
    ],
    PersonnageCatalogue(groupe: 'Nation Rouages', libelle: 'Mécanoptère (boss)', id: 'rouages', grand: true, dossier: 'nations/boss'),
  ),
];

/// Familiers (invocations) — dossier `summons/`.
const List<PersonnageCatalogue> familiers = [
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Golem de pierre', id: 'golem_de_pierre', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Loup spectral', id: 'loup_spectral', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Requin des marées', id: 'requin_des_marees', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Élémentaire de cristal', id: 'elementaire_de_cristal', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Ombre', id: 'ombre', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Esprit de la forêt', id: 'esprit_de_la_foret', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Archer sylvestre', id: 'archer_sylvestre', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Ent de combat', id: 'ent_de_combat', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Tronc', id: 'tronc', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Sarriette', id: 'sarriette', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Ronce agressive', id: 'ronce_agressive', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Familiers', libelle: 'Sentinelle de grès', id: 'sentinelle_de_gres', grand: false, dossier: 'summons'),
];

/// Mécanismes (objets fixes, une seule pose) — dossier `summons/`.
const List<PersonnageCatalogue> mecanismes = [
  PersonnageCatalogue(groupe: 'Mécanismes', libelle: 'Arbre', id: 'arbre', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Mécanismes', libelle: 'Racines', id: 'racines', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Mécanismes', libelle: 'Pilier', id: 'pilier', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Mécanismes', libelle: 'Muraille', id: 'muraille', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Mécanismes', libelle: 'Faille', id: 'faille', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Mécanismes', libelle: 'Cristal d\'ambre', id: 'cristal_ambre', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Mécanismes', libelle: 'Balise', id: 'balise', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Mécanismes', libelle: 'Bombe', id: 'bombe', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Mécanismes', libelle: 'Tourelle', id: 'tourelle', grand: false, dossier: 'summons'),
  PersonnageCatalogue(groupe: 'Mécanismes', libelle: 'Balise de transposition', id: 'balise_de_transposition', grand: false, dossier: 'summons'),
];

/// Catalogue complet : 10 nations × (1 héros + 4 ennemis + 1 boss) + 12 familiers + 10 mécanismes.
List<PersonnageCatalogue> catalogueComplet() {
  final out = <PersonnageCatalogue>[];
  for (final n in nations) {
    out.add(n.heros);
    out.addAll(n.ennemis);
    out.add(n.boss);
  }
  out.addAll(familiers);
  out.addAll(mecanismes);
  return out;
}

/// Regroupe le catalogue par `groupe` pour les listes déroulantes.
Map<String, List<PersonnageCatalogue>> catalogueParGroupe() {
  final map = <String, List<PersonnageCatalogue>>{};
  for (final p in catalogueComplet()) {
    map.putIfAbsent(p.groupe, () => <PersonnageCatalogue>[]).add(p);
  }
  return map;
}

// --------------------------------------------------------------------------------------------
// Présélection depuis le nom du fichier importé
// --------------------------------------------------------------------------------------------

/// Présélection déduite du nom du fichier (ex. `assassin_dos_attaques.png`).
class Presel {
  final PersonnageCatalogue? perso;
  final PlancheDef? planche;

  const Presel(this.perso, this.planche);
}

/// Devine le personnage et la planche depuis un nom de fichier.
///
/// Conventions supportées : identifiant du personnage (`assassin`, `liche`…),
/// `dos`/`back` pour la vue arrière, `attaque(s)`/`attack(s)` pour les planches
/// d'attaques des héros et boss.
Presel preselDepuisNomFichier(String nom) {
  final n = nom.toLowerCase();
  PersonnageCatalogue? perso;
  var longueur = 0;
  for (final p in catalogueComplet()) {
    if (n.contains(p.id) && p.id.length > longueur) {
      perso = p;
      longueur = p.id.length;
    }
  }
  if (perso == null) return const Presel(null, null);

  if (mecanismes.contains(perso)) return Presel(perso, plancheObjets);

  final dos = n.contains('dos') || n.contains('back');
  final att = n.contains('attaque') || n.contains('attack');
  if (perso.grand) {
    final index = (dos ? 2 : 0) + (att ? 1 : 0);
    return Presel(perso, planchesGrand[index]);
  }
  return Presel(perso, planchesPetit[dos ? 1 : 0]);
}
