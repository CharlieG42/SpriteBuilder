/// Réglages de l'animation procédurale de Zimut (V35, `EntityView.gd`) :
/// respiration, marche, attaque et sort. Exportés à côté du sprite dans
/// `<id>_anim.txt` (JSON) ; les clés et valeurs par défaut sont celles du jeu.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import 'animations.dart';

/// Un paramètre réglable.
class ParamAnim {
  final String cle;
  final String libelle;
  final double defaut;
  final double max;
  final int decimales;
  final String unite;

  /// Famille d'animation où le paramètre se voit.
  final FamilleAnim famille;

  const ParamAnim(this.cle, this.libelle, this.defaut, this.max, this.decimales, this.unite, this.famille);
}

/// Paramètres, dans l'ordre d'affichage. Défauts et bornes = `ANIM_DEFAUT` / `ANIM_MAX` du jeu.
const List<ParamAnim> paramsAnim = [
  ParamAnim('respiration', 'Respiration', 0.014, 0.08, 3, '', FamilleAnim.repos),
  ParamAnim('flottement', 'Flottement', 1.6, 12, 1, 'px', FamilleAnim.repos),
  ParamAnim('vitesse_repos', 'Vitesse du repos', 2.2, 8, 1, 'rad/s', FamilleAnim.repos),
  ParamAnim('balancement', 'Balancement', 0.018, 0.15, 3, 'rad', FamilleAnim.repos),
  ParamAnim('rebond_marche', 'Rebond', 9, 30, 1, 'px', FamilleAnim.marche),
  ParamAnim('ecrasement_marche', 'Écrasement', 0.07, 0.3, 2, '', FamilleAnim.marche),
  ParamAnim('penche_marche', 'Inclinaison', 0.10, 0.4, 2, '', FamilleAnim.marche),
  ParamAnim('elan_attaque', 'Élan de la fente', 26, 80, 0, 'px', FamilleAnim.attaque),
  ParamAnim('recul_attaque', 'Armé (recul)', 8, 30, 0, 'px', FamilleAnim.attaque),
  ParamAnim('etirement_attaque', 'Étirement', 1.0, 3, 1, '×', FamilleAnim.attaque),
  ParamAnim('saut_sort', 'Saut du sort', 12, 40, 0, 'px', FamilleAnim.sort),
];

ParamAnim paramAnim(String cle) => paramsAnim.firstWhere((p) => p.cle == cle);

/// Valeurs de réglage d'un personnage.
class ReglagesAnim {
  final Map<String, double> valeurs;

  ReglagesAnim([Map<String, double>? v])
      : valeurs = {for (final p in paramsAnim) p.cle: (v?[p.cle] ?? p.defaut).clamp(0.0, p.max).toDouble()};

  double operator [](String cle) => valeurs[cle] ?? paramAnim(cle).defaut;

  ReglagesAnim avec(String cle, double v) => ReglagesAnim({...valeurs, cle: v});

  bool get estDefaut => paramsAnim.every((p) => (this[p.cle] - p.defaut).abs() < 1e-9);

  /// JSON lu par `EntityView.anim_params` (valeurs arrondies, clés modifiées seulement).
  String versJson() {
    final m = <String, num>{};
    for (final p in paramsAnim) {
      final v = this[p.cle];
      if ((v - p.defaut).abs() < 1e-9) continue;
      m[p.cle] = double.parse(v.toStringAsFixed(p.decimales + 1));
    }
    return const JsonEncoder.withIndent('  ').convert(m);
  }

  factory ReglagesAnim.depuisJson(Object? json) {
    if (json is! Map) return ReglagesAnim();
    return ReglagesAnim({
      for (final e in json.entries)
        if (e.key is String && e.value is num) e.key as String: (e.value as num).toDouble(),
    });
  }
}

/// Mouvement procédural à un instant : décalage (en px « jeu »), échelles,
/// rotation et inclinaison — même formules que `EntityView._process`.
class PoseProcedurale {
  final double dx;
  final double dy;
  final double sx;
  final double sy;
  final double rotation;
  final double inclinaison;

  const PoseProcedurale({
    this.dx = 0,
    this.dy = 0,
    this.sx = 1,
    this.sy = 1,
    this.rotation = 0,
    this.inclinaison = 0,
  });
}

/// Durée d'un cycle d'attaque ou de sort dans l'aperçu (s).
const double cycleAction = 1.2;

/// Mouvement du jeu pour la famille [f] au temps [t] (s). [sens] = +1 vers
/// la droite, -1 vers la gauche (miroir).
PoseProcedurale poseProcedurale(ReglagesAnim r, FamilleAnim? f, double t, {double sens = 1}) {
  final vr = r['vitesse_repos'];
  final bob = math.sin(t * vr) * r['flottement'];
  final respire = math.sin(t * vr) * r['respiration'];
  final rot = math.sin(t * 1.3) * r['balancement'];
  switch (f) {
    case FamilleAnim.marche:
      final hop = math.sin(t * 13).abs();
      final ecrase = (1 - hop) * r['ecrasement_marche'];
      return PoseProcedurale(
        dy: -bob - hop * r['rebond_marche'],
        sx: 1 + ecrase * 0.6,
        sy: 1 + respire - ecrase,
        rotation: rot,
        inclinaison: sens * r['penche_marche'],
      );
    case FamilleAnim.attaque:
      final p = t % cycleAction;
      double x;
      if (p < 0.07) {
        x = -r['recul_attaque'] * (p / 0.07);
      } else if (p < 0.14) {
        final k = (p - 0.07) / 0.07;
        final e = 1 - (1 - k) * (1 - k); // quad, sortie douce
        x = -r['recul_attaque'] + (r['elan_attaque'] + r['recul_attaque']) * e;
      } else if (p < 0.28) {
        x = r['elan_attaque'] * (1 - (p - 0.14) / 0.14);
      } else {
        x = 0;
      }
      final etir = (1 - p * 2.5).clamp(0.0, 1.0) * r['etirement_attaque'];
      return PoseProcedurale(
        dx: sens * x,
        dy: -bob,
        sx: 1 + etir * 0.10,
        sy: 1 + respire - etir * 0.07,
        rotation: rot,
      );
    case FamilleAnim.sort:
      final p = t % cycleAction;
      double y;
      if (p < 0.12) {
        final k = p / 0.12;
        y = r['saut_sort'] * (1 - (1 - k) * (1 - k));
      } else if (p < 0.28) {
        y = r['saut_sort'] * _rebondSortie(1 - (p - 0.12) / 0.16);
      } else {
        y = 0;
      }
      return PoseProcedurale(dy: -bob - y, sy: 1 + respire, rotation: rot);
    default:
      return PoseProcedurale(dy: -bob, sy: 1 + respire, rotation: rot);
  }
}

/// Inverse d'un « bounce out » : hauteur restante (1 → 0) avec petits rebonds.
double _rebondSortie(double h) {
  final k = 1 - h; // progression de la descente
  double b;
  if (k < 1 / 2.75) {
    b = 7.5625 * k * k;
  } else if (k < 2 / 2.75) {
    final q = k - 1.5 / 2.75;
    b = 7.5625 * q * q + 0.75;
  } else if (k < 2.5 / 2.75) {
    final q = k - 2.25 / 2.75;
    b = 7.5625 * q * q + 0.9375;
  } else {
    final q = k - 2.625 / 2.75;
    b = 7.5625 * q * q + 0.984375;
  }
  return 1 - b;
}

// --------------------------------------------------------------------------------------------
// Persistance par personnage (documents de l'application)
// --------------------------------------------------------------------------------------------

/// Réglages enregistrés sur l'appareil, par identifiant de personnage : on les
/// retrouve d'une planche à l'autre (face, dos, attaques…) et d'une session à l'autre.
class MagasinReglages {
  static Map<String, ReglagesAnim>? _cache;

  static Future<File> _fichier() async {
    final dossier = await getApplicationDocumentsDirectory();
    return File('${dossier.path}/reglages_anim.json');
  }

  static Future<Map<String, ReglagesAnim>> _tout() async {
    if (_cache != null) return _cache!;
    final out = <String, ReglagesAnim>{};
    try {
      final f = await _fichier();
      if (await f.exists()) {
        final json = jsonDecode(await f.readAsString());
        if (json is Map) {
          for (final e in json.entries) {
            if (e.key is String) out[e.key as String] = ReglagesAnim.depuisJson(e.value);
          }
        }
      }
    } catch (_) {
      // Fichier corrompu : on repart des valeurs par défaut.
    }
    return _cache = out;
  }

  static Future<ReglagesAnim> lire(String id) async => (await _tout())[id] ?? ReglagesAnim();

  static Future<void> ecrire(String id, ReglagesAnim r) async {
    final tout = await _tout();
    if (r.estDefaut) {
      tout.remove(id);
    } else {
      tout[id] = r;
    }
    try {
      final f = await _fichier();
      await f.writeAsString(jsonEncode({for (final e in tout.entries) e.key: e.value.valeurs}));
    } catch (_) {
      // Stockage indisponible : les réglages restent en mémoire pour la session.
    }
  }
}
