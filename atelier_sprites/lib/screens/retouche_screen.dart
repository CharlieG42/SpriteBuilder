/// Retouche à la main d'une planche, façon logiciel de dessin : **calques** et
/// **sélection** (rectangle, ellipse, lasso, baguette), pinceau (opacité, dureté,
/// lissage, miroir), gomme, dégradé, remplissage, formes, protection, restauration,
/// pipette, zoom au doigt, annuler / rétablir, et contrôle du résultat du
/// détourage automatique.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/couleur.dart';
import '../core/retouche.dart';
import '../models.dart';
import '../widgets/comparateur_detour.dart';
import '../widgets/damier.dart';

/// Résultat de l'éditeur : image retouchée (PNG) et carte des pixels forcés.
class ResultatRetouche {
  final Uint8List octets;
  final Uint8List forces;

  /// Plus aucune retouche (tout a été restauré) : revenir à l'image importée.
  final bool vide;

  const ResultatRetouche(this.octets, this.forces, this.vide);
}

enum Outil { pinceau, gomme, degrade, remplissage, ligne, rectangle, ellipse, lasso, baguette, pipette, proteger, restaurer, main, selRect, selEllipse, selLasso, selBaguette }

/// Axes de symétrie du dessin (miroir façon multibrush de Krita), centrés sur l'image.
enum Symetrie { aucune, horizontale, verticale, lesDeux }

extension SymetrieX on Symetrie {
  String get libelle => switch (this) {
        Symetrie.aucune => 'Aucune',
        Symetrie.horizontale => 'Miroir H',
        Symetrie.verticale => 'Miroir V',
        Symetrie.lesDeux => 'Miroir H+V',
      };
}

/// Groupes affichés dans la toolbox verticale (séparés par un filet).
const List<List<Outil>> groupesOutils = <List<Outil>>[
  <Outil>[Outil.pinceau, Outil.gomme, Outil.degrade, Outil.remplissage],
  <Outil>[Outil.ligne, Outil.rectangle, Outil.ellipse],
  <Outil>[Outil.lasso, Outil.baguette],
  <Outil>[Outil.selRect, Outil.selEllipse, Outil.selLasso, Outil.selBaguette],
  <Outil>[Outil.pipette, Outil.proteger, Outil.restaurer, Outil.main],
];

extension OutilX on Outil {
  String get libelle => switch (this) {
        Outil.pinceau => 'Pinceau',
        Outil.gomme => 'Gomme',
        Outil.degrade => 'Dégradé',
        Outil.remplissage => 'Remplissage',
        Outil.proteger => 'Protéger',
        Outil.restaurer => 'Restaurer',
        Outil.ligne => 'Ligne',
        Outil.rectangle => 'Rectangle',
        Outil.ellipse => 'Ellipse',
        Outil.baguette => 'Baguette',
        Outil.lasso => 'Lasso',
        Outil.selRect => 'Sélection rect.',
        Outil.selEllipse => 'Sélection ellipse',
        Outil.selLasso => 'Sélection lasso',
        Outil.selBaguette => 'Sélection magique',
        Outil.pipette => 'Pipette',
        Outil.main => 'Déplacer',
      };

  IconData get icone => switch (this) {
        Outil.pinceau => Icons.brush,
        Outil.gomme => Icons.auto_fix_normal,
        Outil.degrade => Icons.gradient,
        Outil.remplissage => Icons.format_color_fill,
        Outil.proteger => Icons.shield_outlined,
        Outil.restaurer => Icons.settings_backup_restore,
        Outil.ligne => Icons.horizontal_rule,
        Outil.rectangle => Icons.crop_square,
        Outil.ellipse => Icons.circle_outlined,
        Outil.baguette => Icons.auto_fix_high,
        Outil.lasso => Icons.gesture,
        Outil.selRect => Icons.crop_free,
        Outil.selEllipse => Icons.radio_button_unchecked,
        Outil.selLasso => Icons.polyline_outlined,
        Outil.selBaguette => Icons.filter_center_focus,
        Outil.pipette => Icons.colorize,
        Outil.main => Icons.pan_tool_alt_outlined,
      };

  String get aide => switch (this) {
        Outil.pinceau => 'Peint en couleur ; ce qui est peint est protégé du détourage.',
        Outil.gomme => 'Supprime à la main (devient transparent), même si le détourage l\'aurait gardé.',
        Outil.proteger => 'Empêche le détourage de retirer ces pixels (cheveux blancs, reflets…).',
        Outil.restaurer => 'Rend l\'image d\'origine et repasse en détourage automatique.',
        Outil.ligne => 'Glisse du début à la fin du trait ; l\'épaisseur est la taille.',
        Outil.rectangle => 'Glisse d\'un coin à l\'autre ; plein ou contour.',
        Outil.ellipse => 'Glisse d\'un coin à l\'autre du cadre ; pleine ou contour.',
        Outil.baguette => 'Touche une couleur : applique l\'action à toute la zone de couleur proche.',
        Outil.lasso => 'Dessine le contour d\'une zone au doigt : l\'action s\'applique à son intérieur.',
        Outil.degrade => 'Glisse du début à la fin : dégradé de la couleur principale vers la secondaire (bouton d\'échange). Transparente = fondu effaçant.',
        Outil.remplissage => 'Touche une zone : la remplit de la couleur principale (tolérance réglable, zone contiguë).',
        Outil.selRect => 'Glisse d\'un coin à l\'autre : sélectionne le rectangle. La sélection ne limite que les outils de dessin.',
        Outil.selEllipse => 'Glisse d\'un coin à l\'autre du cadre : sélectionne l\'ellipse.',
        Outil.selLasso => 'Dessine le contour au doigt : sélectionne l\'intérieur.',
        Outil.selBaguette => 'Touche une couleur du composite : sélectionne la zone de couleur proche (tolérance réglable, contigu ou non).',
        Outil.pipette => 'Touche un pixel pour prendre sa couleur (revient au pinceau).',
        Outil.main => 'Déplace la vue au doigt. Pince à deux doigts pour zoomer avec n\'importe quel outil.',
      };

  ModeRetouche? get mode => switch (this) {
        Outil.pinceau => ModeRetouche.peindre,
        Outil.gomme => ModeRetouche.effacer,
        Outil.proteger => ModeRetouche.proteger,
        Outil.restaurer => ModeRetouche.restaurer,
        _ => null,
      };
}

class EcranRetouche extends StatefulWidget {
  final Uint8List octets;
  final Uint8List? octetsOrigine;
  final Uint8List? forces;
  final OptionsTraitement options;
  final String titre;

  /// Mode « logiciel de retouche » : pas de planche de sprites derrière, on
  /// travaille sur l'image et on l'exporte en PNG ou JPG.
  final bool autonome;

  /// Case « détourer automatiquement » cochée par défaut à l'export.
  final bool detourageParDefaut;

  const EcranRetouche({
    super.key,
    required this.octets,
    required this.options,
    required this.titre,
    this.octetsOrigine,
    this.forces,
    this.autonome = false,
    this.detourageParDefaut = true,
  });

  @override
  State<EcranRetouche> createState() => _EcranRetoucheState();
}

class _EcranRetoucheState extends State<EcranRetouche> {
  CalqueRetouche? _c;
  ui.Image? _image;
  bool _decodage = false;
  bool _decodageEncore = false;
  String? _erreur;
  bool _occupe = false;

  Outil _outil = Outil.pinceau;
  int _taille = 8;
  double _opacite = 1.0;
  double _durete = 0.85;
  bool _lissage = true;
  Symetrie _symetrie = Symetrie.aucune;
  ModeSelection _modeSelection = ModeSelection.remplacer;
  int _tolerance = 30;
  bool _contigu = true;
  bool _interieur = true;
  ModeRetouche _actionZone = ModeRetouche.effacer;
  ModeRetouche _actionForme = ModeRetouche.peindre;
  bool _rempli = false;
  Offset? _formeA;
  Offset? _formeB;
  Color _couleur = const Color(0xFFFFFFFF);
  Color _couleurSecondaire = const Color(0x00FFFFFF);
  final List<Color> _recentes = <Color>[];

  late FondControle _fond = widget.autonome ? FondControle.damier : FondControle.magenta;

  // Export.
  FormatExport _formatExport = FormatExport.png;
  int _qualiteJpg = 92;
  late bool _detourerExport = widget.detourageParDefaut;
  FondControle _fondJpg = FondControle.blanc;
  int _versionExportee = 0;

  // Contrôle : résultat du détourage automatique (retouches comprises).
  bool _controle = false;
  bool _calculControle = false;
  ui.Image? _imageControle;
  int _seqControle = 0;

  // Vue : échelle (px écran par px image) et position du coin haut-gauche de l'image.
  double _echelle = 1;
  Offset _decalage = Offset.zero;
  Size _zone = Size.zero;
  bool _vueInitialisee = false;

  // Gestes.
  final Map<int, Offset> _doigts = <int, Offset>{};
  bool _multi = false;
  double _pinchD0 = 1;
  double _pinchEchelle0 = 1;
  Offset _pinchFocalImage = Offset.zero;
  Offset? _depart;
  bool _aBouge = false;
  Offset? _dernierTrace;
  Offset? _lisse;
  Offset? _curseur;
  final List<Offset> _lasso = <Offset>[];
  bool _actionOuverte = false;
  List<double> _contour = const <double>[];

  @override
  void initState() {
    super.initState();
    _ouvrir();
  }

  @override
  void dispose() {
    _image?.dispose();
    _imageControle?.dispose();
    super.dispose();
  }

  Future<void> _ouvrir() async {
    try {
      final o = await compute(
        ouvrirRetouche,
        DemandeOuverture(widget.octets, octetsOrigine: widget.octetsOrigine, forces: widget.forces),
      );
      if (!mounted) return;
      final c = CalqueRetouche.depuis(o);
      setState(() => _c = c);
      _rafraichir();
    } catch (e) {
      if (mounted) setState(() => _erreur = '$e');
    }
  }

  // --------------------------------------------------------------------------------------------
  // Image affichée
  // --------------------------------------------------------------------------------------------

  /// Reconstruit l'image affichée (au plus une reconstruction à la fois).
  void _rafraichir() {
    final c = _c;
    if (c == null) return;
    if (_decodage) {
      _decodageEncore = true;
      return;
    }
    _decodage = true;
    ui.decodeImageFromPixels(c.affichage, c.largeur, c.hauteur, ui.PixelFormat.rgba8888, (nouvelle) {
      _decodage = false;
      if (!mounted) {
        nouvelle.dispose();
        return;
      }
      final ancienne = _image;
      setState(() => _image = nouvelle);
      ancienne?.dispose();
      if (_decodageEncore) {
        _decodageEncore = false;
        _rafraichir();
      }
    });
  }

  void _ajusterVue() {
    final c = _c;
    if (c == null || _zone.isEmpty) return;
    final e = _zone.width / c.largeur;
    final f = _zone.height / c.hauteur;
    _echelle = e < f ? e : f;
    _decalage = Offset((_zone.width - c.largeur * _echelle) / 2, (_zone.height - c.hauteur * _echelle) / 2);
    _vueInitialisee = true;
  }

  Offset _versImage(Offset p) => (p - _decalage) / _echelle;

  /// Zoom d'un [facteur] autour du centre de la zone de dessin (boutons + / −).
  void _zoom(double facteur) {
    if (_zone.isEmpty) return;
    final focal = _zone.center(Offset.zero);
    final imageFocal = _versImage(focal);
    setState(() {
      _echelle = (_echelle * facteur).clamp(0.05, 60.0).toDouble();
      _decalage = focal - imageFocal * _echelle;
    });
  }

  /// Recalcule le contour affiché de la sélection courante.
  void _majContour() {
    _contour = _c?.contourSelection() ?? const <double>[];
  }

  // --------------------------------------------------------------------------------------------
  // Gestes
  // --------------------------------------------------------------------------------------------

  bool get _outilActif => _c != null && !_controle && _outil != Outil.main;

  void _pointeurBas(PointerDownEvent e) {
    _doigts[e.pointer] = e.localPosition;
    if (_doigts.length >= 2) {
      _terminerOutil(annule: false);
      _multi = true;
      _initPinch();
      return;
    }
    if (_multi) return;
    _depart = e.localPosition;
    _aBouge = false;
    if (_outilActif) _debutOutil(e.localPosition);
  }

  void _pointeurBouge(PointerMoveEvent e) {
    if (!_doigts.containsKey(e.pointer)) return;
    _doigts[e.pointer] = e.localPosition;
    if (_doigts.length >= 2) {
      _majPinch();
      return;
    }
    if (_multi) return;
    if (_depart != null && (e.localPosition - _depart!).distance > 12) _aBouge = true;
    if (_outil == Outil.main || _controle) {
      setState(() => _decalage += e.delta);
    } else if (_outilActif) {
      _moveOutil(e.localPosition);
    }
  }

  void _pointeurHaut(PointerUpEvent e) {
    final etaitSeul = _doigts.length == 1 && !_multi;
    _doigts.remove(e.pointer);
    if (etaitSeul && _outilActif) _finOutil(e.localPosition);
    if (_doigts.isEmpty) {
      _multi = false;
      _depart = null;
      setState(() => _curseur = null);
    } else if (_doigts.length == 1) {
      _multi = true; // le doigt restant ne dessine pas
    }
  }

  void _pointeurAnnule(PointerCancelEvent e) {
    _doigts.remove(e.pointer);
    _terminerOutil(annule: false);
    if (_doigts.isEmpty) {
      _multi = false;
      _depart = null;
      setState(() => _curseur = null);
    }
  }

  void _molette(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || _c == null) return;
    final facteur = e.scrollDelta.dy > 0 ? 0.9 : 1.1;
    final focal = e.localPosition;
    final imageFocal = _versImage(focal);
    setState(() {
      _echelle = (_echelle * facteur).clamp(0.05, 60.0).toDouble();
      _decalage = focal - imageFocal * _echelle;
    });
  }

  void _initPinch() {
    final pts = _doigts.values.toList();
    _pinchD0 = math.max(1.0, (pts[0] - pts[1]).distance);
    _pinchEchelle0 = _echelle;
    _pinchFocalImage = _versImage((pts[0] + pts[1]) / 2);
  }

  void _majPinch() {
    final pts = _doigts.values.toList();
    final d = (pts[0] - pts[1]).distance;
    final focal = (pts[0] + pts[1]) / 2;
    setState(() {
      _echelle = (_pinchEchelle0 * d / _pinchD0).clamp(0.05, 60.0).toDouble();
      _decalage = focal - _pinchFocalImage * _echelle;
    });
  }

  // --------------------------------------------------------------------------------------------
  // Outils
  // --------------------------------------------------------------------------------------------

  int get _cr => _couleur.red;
  int get _cg => _couleur.green;
  int get _cb => _couleur.blue;

  bool get _estBrosse =>
      _outil == Outil.pinceau || _outil == Outil.gomme || _outil == Outil.proteger || _outil == Outil.restaurer;
  bool get _estForme =>
      _outil == Outil.ligne || _outil == Outil.rectangle || _outil == Outil.ellipse || _outil == Outil.degrade;
  bool get _aTaille => _estBrosse || _estForme;
  bool get _peint => _outil == Outil.pinceau ||
      _outil == Outil.degrade ||
      _outil == Outil.remplissage ||
      (_estForme && _outil != Outil.degrade && _actionForme == ModeRetouche.peindre) ||
      ((_outil == Outil.baguette || _outil == Outil.lasso) && _actionZone == ModeRetouche.peindre);
  bool get _aOpacite => _outil == Outil.pinceau ||
      _outil == Outil.gomme ||
      _outil == Outil.ligne ||
      _outil == Outil.degrade ||
      (_estForme && _actionForme == ModeRetouche.peindre);
  bool get _aDurete => _estBrosse || _outil == Outil.ligne || _outil == Outil.degrade;
  bool get _estSelection =>
      _outil == Outil.selRect || _outil == Outil.selEllipse || _outil == Outil.selLasso || _outil == Outil.selBaguette;

  /// Points miroirs de [p] (coordonnées image) selon la symétrie choisie.
  List<Offset> _pointsSymetrie(Offset p) {
    final c = _c!;
    final pts = <Offset>[p];
    switch (_symetrie) {
      case Symetrie.aucune:
        break;
      case Symetrie.horizontale:
        pts.add(Offset(c.largeur - 1 - p.dx, p.dy));
      case Symetrie.verticale:
        pts.add(Offset(p.dx, c.hauteur - 1 - p.dy));
      case Symetrie.lesDeux:
        pts
          ..add(Offset(c.largeur - 1 - p.dx, p.dy))
          ..add(Offset(p.dx, c.hauteur - 1 - p.dy))
          ..add(Offset(c.largeur - 1 - p.dx, c.hauteur - 1 - p.dy));
    }
    return pts;
  }

  void _tamponOutil(Offset pi) {
    final c = _c!;
    for (final q in _pointsSymetrie(pi)) {
      c.tampon(_outil.mode!, q.dx.floor(), q.dy.floor(), _taille,
          r: _cr, g: _cg, b: _cb, opacite: _opacite, durete: _durete);
    }
  }

  void _traitOutil(Offset a, Offset b) {
    final c = _c!;
    final pa = _pointsSymetrie(a);
    final pb = _pointsSymetrie(b);
    for (var k = 0; k < pa.length; k++) {
      c.trait(_outil.mode!, pa[k].dx.floor(), pa[k].dy.floor(), pb[k].dx.floor(), pb[k].dy.floor(), _taille,
          r: _cr, g: _cg, b: _cb, opacite: _opacite, durete: _durete);
    }
  }

  void _debutOutil(Offset p) {
    final c = _c!;
    final pi = _versImage(p);
    switch (_outil) {
      case Outil.pinceau || Outil.gomme || Outil.proteger || Outil.restaurer:
        c.commencer();
        _actionOuverte = true;
        _lisse = pi;
        _dernierTrace = pi;
        _tamponOutil(pi);
        setState(() => _curseur = p);
        _rafraichir();
      case Outil.lasso || Outil.selLasso:
        _lasso
          ..clear()
          ..add(p);
        setState(() {});
      case Outil.ligne || Outil.rectangle || Outil.ellipse || Outil.degrade || Outil.selRect || Outil.selEllipse:
        setState(() {
          _formeA = p;
          _formeB = p;
        });
      case Outil.baguette || Outil.remplissage || Outil.pipette || Outil.main || Outil.selBaguette:
        break;
    }
  }

  void _moveOutil(Offset p) {
    final pi = _versImage(p);
    switch (_outil) {
      case Outil.pinceau || Outil.gomme || Outil.proteger || Outil.restaurer:
        if (!_actionOuverte) return;
        Offset cible = pi;
        if (_lissage && (_outil == Outil.pinceau || _outil == Outil.gomme)) {
          // Stabilisateur : moyenne exponentielle du point brut, le trait dessiné
          // rejoint le point lissé (façon stabilisateur de Krita).
          _lisse = _lisse == null ? pi : _lisse! * 0.72 + pi * 0.28;
          cible = _lisse!;
        }
        final d = _dernierTrace ?? cible;
        _traitOutil(d, cible);
        _dernierTrace = cible;
        setState(() => _curseur = p);
        _rafraichir();
      case Outil.lasso || Outil.selLasso:
        if (_lasso.isEmpty || (p - _lasso.last).distance >= 3) {
          setState(() => _lasso.add(p));
        }
      case Outil.ligne || Outil.rectangle || Outil.ellipse || Outil.degrade || Outil.selRect || Outil.selEllipse:
        if (_formeA != null) setState(() => _formeB = p);
      case Outil.baguette || Outil.remplissage || Outil.pipette || Outil.main || Outil.selBaguette:
        break;
    }
  }

  void _finOutil(Offset p) {
    final c = _c!;
    final pi = _versImage(p);
    switch (_outil) {
      case Outil.pinceau || Outil.gomme || Outil.proteger || Outil.restaurer:
        if (_dernierTrace != null && (_outil == Outil.pinceau || _outil == Outil.gomme)) {
          _traitOutil(_dernierTrace!, pi); // rejoindre le point réel en fin de geste
        }
        _lisse = null;
        _dernierTrace = null;
        _terminerOutil(annule: false);
      case Outil.baguette:
        if (_aBouge) return;
        c.commencer();
        c.baguette(_actionZone, pi.dx.floor(), pi.dy.floor(),
            tolerance: _tolerance, contigu: _contigu, r: _cr, g: _cg, b: _cb);
        c.terminer();
        setState(() {});
        _rafraichir();
      case Outil.remplissage:
        if (_aBouge) return;
        c.commencer();
        c.baguette(ModeRetouche.peindre, pi.dx.floor(), pi.dy.floor(),
            tolerance: _tolerance, contigu: true, r: _cr, g: _cg, b: _cb);
        c.terminer();
        setState(() {});
        _rafraichir();
      case Outil.pipette:
        if (_aBouge) return;
        final v = c.couleurEn(pi.dx.floor(), pi.dy.floor());
        if (v != null) {
          _choisirCouleur(Color.fromARGB(255, v.r, v.g, v.b));
          setState(() => _outil = Outil.pinceau);
        }
      case Outil.selBaguette:
        if (_aBouge) return;
        c.appliquerSelection(
          c.masqueBaguette(pi.dx.floor(), pi.dy.floor(), tolerance: _tolerance, contigu: _contigu),
          mode: _modeSelection,
        );
        _majContour();
        setState(() {});
      case Outil.lasso || Outil.selLasso:
        final pts = <double>[
          for (final q in _lasso) ...[_versImage(q).dx, _versImage(q).dy],
        ];
        _lasso.clear();
        if (pts.length >= 6) {
          if (_outil == Outil.selLasso) {
            c.appliquerSelection(c.masquePolygone(pts), mode: _modeSelection);
            _majContour();
          } else {
            c.commencer();
            c.polygone(_actionZone, pts, interieur: _interieur, r: _cr, g: _cg, b: _cb);
            c.terminer();
            _rafraichir();
          }
        }
        setState(() {});
      case Outil.ligne || Outil.rectangle || Outil.ellipse || Outil.degrade || Outil.selRect || Outil.selEllipse:
        final a = _formeA;
        _formeA = null;
        _formeB = null;
        if (a != null) {
          final ia = _versImage(a);
          final x0 = ia.dx.floor();
          final y0 = ia.dy.floor();
          final x1 = pi.dx.floor();
          final y1 = pi.dy.floor();
          if (_outil == Outil.selRect || _outil == Outil.selEllipse) {
            final m = _outil == Outil.selRect
                ? c.masqueRectangle(x0, y0, x1, y1)
                : c.masqueEllipse(x0, y0, x1, y1);
            c.appliquerSelection(m, mode: _modeSelection);
            _majContour();
          } else {
            c.commencer();
            if (_outil == Outil.ligne) {
            c.trait(_actionForme, x0, y0, x1, y1, _taille,
                r: _cr, g: _cg, b: _cb, opacite: _opacite, durete: _durete);
          } else if (_outil == Outil.rectangle) {
            c.rectangle(_actionForme, x0, y0, x1, y1,
                epaisseur: _taille, rempli: _rempli, r: _cr, g: _cg, b: _cb, opacite: _opacite);
          } else if (_outil == Outil.ellipse) {
            c.ellipse(_actionForme, x0, y0, x1, y1,
                epaisseur: _taille, rempli: _rempli, r: _cr, g: _cg, b: _cb, opacite: _opacite);
          } else {
            c.traitDegrade(x0, y0, x1, y1, _taille,
                c0: (r: _cr, g: _cg, b: _cb, a: 255),
                c1: (
                  r: _couleurSecondaire.red,
                  g: _couleurSecondaire.green,
                  b: _couleurSecondaire.blue,
                  a: _couleurSecondaire.alpha,
                ),
                opacite: _opacite,
                durete: _durete);
            }
            c.terminer();
            _rafraichir();
          }
        }
        setState(() {});
      case Outil.main:
        break;
    }
  }

  void _terminerOutil({required bool annule}) {
    if (_actionOuverte) {
      _c?.terminer();
      _actionOuverte = false;
      setState(() {});
    }
    if (_lasso.isNotEmpty || _formeA != null) {
      _lasso.clear();
      _formeA = null;
      _formeB = null;
      setState(() {});
    }
  }

  void _choisirCouleur(Color c) {
    setState(() {
      _couleur = c;
      _recentes.remove(c);
      _recentes.insert(0, c);
      if (_recentes.length > 8) _recentes.removeLast();
    });
  }

  // --------------------------------------------------------------------------------------------
  // Actions
  // --------------------------------------------------------------------------------------------

  void _annuler() {
    final c = _c;
    if (c == null) return;
    if (c.annuler()) {
      setState(() {});
      _rafraichir();
    }
  }

  void _retablir() {
    final c = _c;
    if (c == null) return;
    if (c.retablir()) {
      setState(() {});
      _rafraichir();
    }
  }

  Future<void> _basculerControle() async {
    final c = _c;
    if (c == null) return;
    if (_controle) {
      setState(() => _controle = false);
      return;
    }
    _terminerOutil(annule: false);
    setState(() {
      _controle = true;
      _calculControle = true;
    });
    final seq = ++_seqControle;
    try {
      final o = widget.options;
      final brut = await compute(
        controleDetourage,
        DemandeControle(
          largeur: c.largeur,
          hauteur: c.hauteur,
          pixels: c.pixelsComposite,
          forces: c.forcesComposite,
          tolerance: o.tolerance,
          douceur: o.douceur,
          decontaminer: o.decontaminer,
          interieurs: o.interieurs,
          aireMinInterieur: o.aireMinInterieur,
          rognage: o.rognage,
        ),
      );
      if (!mounted || seq != _seqControle || !_controle) return;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(brut, c.largeur, c.hauteur, ui.PixelFormat.rgba8888, completer.complete);
      final nouvelle = await completer.future;
      if (!mounted) {
        nouvelle.dispose();
        return;
      }
      final ancienne = _imageControle;
      setState(() {
        _imageControle = nouvelle;
        _calculControle = false;
      });
      ancienne?.dispose();
    } catch (e) {
      if (mounted) {
        setState(() {
          _controle = false;
          _calculControle = false;
        });
        _message('Contrôle impossible : $e');
      }
    }
  }

  Future<void> _restaurerTout() async {
    final c = _c;
    if (c == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tout restaurer ?'),
        content: const Text('Toutes les retouches de cette planche seront annulées (tu peux encore annuler cette action).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tout restaurer')),
        ],
      ),
    );
    if (ok != true) return;
    c.toutRestaurer();
    setState(() {});
    _rafraichir();
  }

  Future<void> _terminer() async {
    final c = _c;
    if (c == null) return;
    c.terminer();
    if (!c.modifie) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _occupe = true);
    try {
      final vide = !c.aDesForces;
      final png = await compute(encoderRetouche, DemandeEncodage(c.largeur, c.hauteur, c.pixelsComposite));
      if (!mounted) return;
      Navigator.of(context).pop(ResultatRetouche(png, Uint8List.fromList(c.forcesComposite), vide));
    } catch (e) {
      if (mounted) {
        setState(() => _occupe = false);
        _message('Enregistrement impossible : $e');
      }
    }
  }

  Future<bool> _confirmerSortie() async {
    final c = _c;
    if (c == null || !(c.modifie || c.peutAnnuler)) return true;
    if (widget.autonome && c.version == _versionExportee) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.autonome ? 'Quitter sans exporter ?' : 'Quitter sans enregistrer ?'),
        content: Text(widget.autonome
            ? 'Les modifications depuis le dernier export seront perdues.'
            : 'Les retouches de cette session seront perdues.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuer')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitter')),
        ],
      ),
    );
    return ok == true;
  }

  void _message(String texte) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  String get _nomBase {
    final sansExt = widget.titre.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
    final propre = sansExt.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
    return propre.isEmpty ? 'image' : propre;
  }

  /// Fenêtre d'export : format, détourage, qualité JPG, puis enregistrer ou partager.
  Future<void> _dialogueExport() async {
    final c = _c;
    if (c == null) return;
    _terminerOutil(annule: false);
    c.terminer();
    final choix = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final theme = Theme.of(ctx);
          final jpg = _formatExport == FormatExport.jpg;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Exporter l\'image', style: theme.textTheme.titleMedium),
                  Text('${c.largeur} × ${c.hauteur} px', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 10),
                  SegmentedButton<FormatExport>(
                    segments: const [
                      ButtonSegment(value: FormatExport.png, label: Text('PNG'), icon: Icon(Icons.layers_outlined)),
                      ButtonSegment(value: FormatExport.jpg, label: Text('JPG'), icon: Icon(Icons.photo_outlined)),
                    ],
                    selected: {_formatExport},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setS(() => _formatExport = s.first),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    jpg
                        ? 'Pas de transparence : l\'image est posée sur le fond choisi.'
                        : 'Garde la transparence (sans perte).',
                    style: theme.textTheme.bodySmall,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Détourer le fond automatiquement'),
                    subtitle: const Text('Avec les réglages de détourage et tes retouches. '
                        'Désactivé : seuls les pixels gommés à la main sont transparents.'),
                    value: _detourerExport,
                    onChanged: (v) => setS(() => _detourerExport = v),
                  ),
                  if (jpg) ...[
                    Row(
                      children: [
                        SizedBox(width: 84, child: Text('Qualité $_qualiteJpg')),
                        Expanded(
                          child: Slider(
                            value: _qualiteJpg.toDouble(),
                            min: 50,
                            max: 100,
                            divisions: 50,
                            label: '$_qualiteJpg',
                            onChanged: (v) => setS(() => _qualiteJpg = v.round()),
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Fond'),
                        for (final f in const [
                          FondControle.blanc,
                          FondControle.noir,
                          FondControle.magenta,
                          FondControle.herbe,
                        ])
                          ChoiceChip(
                            label: Text(f.libelle),
                            selected: f == _fondJpg,
                            onSelected: (_) => setS(() => _fondJpg = f),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.share),
                          label: const Text('Partager'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.save_alt),
                          label: const Text('Enregistrer'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (choix == null || !mounted) return;
    await _exporter(enregistrer: choix);
  }

  Future<void> _exporter({required bool enregistrer}) async {
    final c = _c;
    if (c == null) return;
    setState(() => _occupe = true);
    try {
      final o = widget.options;
      final fond = _fondJpg.couleur;
      final png = _formatExport == FormatExport.png;
      final octets = await compute(
        exporterImage,
        DemandeExport(
          largeur: c.largeur,
          hauteur: c.hauteur,
          pixels: c.pixelsComposite,
          forces: c.forcesComposite,
          format: _formatExport,
          detourer: _detourerExport,
          tolerance: o.tolerance,
          douceur: o.douceur,
          decontaminer: o.decontaminer,
          interieurs: o.interieurs,
          aireMinInterieur: o.aireMinInterieur,
          rognage: o.rognage,
          qualite: _qualiteJpg,
          fondR: fond.red,
          fondG: fond.green,
          fondB: fond.blue,
        ),
      );
      final nom = '${_nomBase}_retouche.${png ? 'png' : 'jpg'}';
      if (enregistrer) {
        final chemin = await FilePicker.platform.saveFile(
          dialogTitle: 'Enregistrer l\'image',
          fileName: nom,
          bytes: octets,
        );
        if (chemin != null) {
          _versionExportee = c.version;
          if (mounted) _message('Image enregistrée ($nom).');
        }
      } else {
        final dossier = await getTemporaryDirectory();
        final fichier = File('${dossier.path}/$nom');
        await fichier.writeAsBytes(octets, flush: true);
        await Share.shareXFiles(
          <XFile>[XFile(fichier.path, mimeType: png ? 'image/png' : 'image/jpeg')],
        );
        _versionExportee = c.version;
      }
    } catch (e) {
      if (mounted) _message('Export impossible : $e');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  /// Sélecteur de couleur façon Krita : aperçu sur damier, TSL (teinte, saturation,
  /// luminosité), RVB et alpha. [secondaire] édite la couleur de fin du dégradé.
  Future<void> _editerCouleur({bool secondaire = false}) async {
    final init = secondaire ? _couleurSecondaire : _couleur;
    var r = init.red.toDouble();
    var g = init.green.toDouble();
    var b = init.blue.toDouble();
    var a = init.alpha.toDouble();
    final t0 = rgbVersTsl(init.red, init.green, init.blue);
    var h = t0.h;
    var s = t0.s;
    var l = t0.l;
    final choisie = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          void depuisTsl(double nh, double ns, double nl) {
            h = nh;
            s = ns;
            l = nl;
            final c = tslVersRgb(h, s, l);
            r = c.r.toDouble();
            g = c.g.toDouble();
            b = c.b.toDouble();
          }

          void depuisRgb() {
            final t = rgbVersTsl(r.round(), g.round(), b.round());
            h = t.h;
            s = t.s;
            l = t.l;
          }

          return AlertDialog(
            title: Text(secondaire ? 'Couleur de fin du dégradé' : 'Couleur principale'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    const SizedBox(height: 40, width: double.infinity, child: Damier(taille: 10)),
                    Container(
                      height: 40,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Color.fromARGB(a.round(), r.round(), g.round(), b.round()),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final (nom, valeur, min, max, div, maj) in <(String, double, double, double, int, void Function(double))>[
                  ('Teinte', h, 0, 360, 72, (v) => depuisTsl(v, s, l)),
                  ('Saturation', s * 100, 0, 100, 20, (v) => depuisTsl(h, v / 100, l)),
                  ('Luminosité', l * 100, 0, 100, 20, (v) => depuisTsl(h, s, v / 100)),
                  ('Rouge', r, 0, 255, 51, (v) { r = v; depuisRgb(); }),
                  ('Vert', g, 0, 255, 51, (v) { g = v; depuisRgb(); }),
                  ('Bleu', b, 0, 255, 51, (v) { b = v; depuisRgb(); }),
                  ('Alpha', a, 0, 255, 51, (v) => a = v),
                ])
                  Row(
                    children: [
                      SizedBox(width: 72, child: Text(nom)),
                      Expanded(
                        child: Slider(
                          value: valeur.clamp(min, max),
                          min: min,
                          max: max,
                          divisions: div,
                          label: valeur.toStringAsFixed(0),
                          onChanged: (v) => setD(() => maj(v)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, Color.fromARGB(a.round(), r.round(), g.round(), b.round())),
                child: const Text('Choisir'),
              ),
            ],
          );
        },
      ),
    );
    if (choisie == null) return;
    if (secondaire) {
      setState(() => _couleurSecondaire = choisie);
    } else {
      _choisirCouleur(choisie);
    }
  }

  // --------------------------------------------------------------------------------------------
  // Interface
  // --------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmerSortie() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Retouche · ${widget.titre}', overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Annuler',
              icon: const Icon(Icons.undo),
              onPressed: c != null && c.peutAnnuler && !_controle ? _annuler : null,
            ),
            IconButton(
              tooltip: 'Rétablir',
              icon: const Icon(Icons.redo),
              onPressed: c != null && c.peutRetablir && !_controle ? _retablir : null,
            ),
            IconButton(
              tooltip: 'Calques',
              icon: const Icon(Icons.layers_outlined),
              onPressed: c == null || _occupe ? null : _panneauCalques,
            ),
            IconButton(
              tooltip: 'Exporter en PNG ou JPG',
              icon: const Icon(Icons.ios_share),
              onPressed: c == null || _occupe ? null : _dialogueExport,
            ),
            if (!widget.autonome)
              IconButton(
                tooltip: 'Terminer et appliquer',
                icon: const Icon(Icons.check),
                onPressed: c == null || _occupe ? null : _terminer,
              ),
          ],
        ),
        body: _erreur != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Image illisible : $_erreur')))
            : c == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            _toolbox(c),
                            Expanded(child: _zoneDessin(c)),
                          ],
                        ),
                      ),
                      _panneau(c),
                    ],
                  ),
      ),
    );
  }

  Widget _zoneDessin(CalqueRetouche c) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final taille = Size(contraintes.maxWidth, contraintes.maxHeight);
        _zone = taille;
        if (!_vueInitialisee) _ajusterVue();
        final image = _controle ? _imageControle : _image;
        return Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _pointeurBas,
              onPointerMove: _pointeurBouge,
              onPointerUp: _pointeurHaut,
              onPointerCancel: _pointeurAnnule,
              onPointerSignal: _molette,
              child: ClipRect(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _PeintreRetouche(
                    image: image,
                    largeur: c.largeur,
                    hauteur: c.hauteur,
                    echelle: _echelle,
                    decalage: _decalage,
                    fond: _fond,
                    lasso: List<Offset>.of(_lasso),
                    curseur: _controle ? null : _curseur,
                    rayonCurseur: _taille / 2 * _echelle,
                    interieurLasso: _interieur,
                    formeOutil: _formeA != null ? _outil : null,
                    formeA: _formeA,
                    formeB: _formeB,
                    formeRempli: _rempli,
                    formeCouleur: switch (_actionForme) {
                      ModeRetouche.peindre => _couleur,
                      ModeRetouche.effacer => const Color(0xAAFF1744),
                      ModeRetouche.proteger => const Color(0xAA00C853),
                      ModeRetouche.restaurer => const Color(0xAA2979FF),
                    },
                    formeCouleurSecondaire: _couleurSecondaire,
                    formeEpaisseur: _taille * _echelle,
                    grille: _echelle >= 8,
                    contour: _contour,
                  ),
                ),
              ),
            ),
            if (_calculControle)
              const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator()),
            if (_occupe) const ColoredBox(color: Color(0x55000000), child: Center(child: CircularProgressIndicator())),
            Positioned(
              right: 8,
              top: 8,
              child: Column(
                children: [
                  _boutonRond(Icons.zoom_out_map, 'Ajuster la vue (tout voir)', () => setState(_ajusterVue)),
                  const SizedBox(height: 6),
                  _boutonRond(Icons.zoom_in, 'Zoom avant', () => _zoom(1.25)),
                  const SizedBox(height: 6),
                  _boutonRond(Icons.zoom_out, 'Zoom arrière', () => _zoom(0.8)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${(_echelle * 100).round()} %', style: Theme.of(context).textTheme.bodySmall),
                  ),
                  const SizedBox(height: 6),
                  _boutonRond(
                    _controle ? Icons.visibility_off : Icons.visibility,
                    _controle ? 'Revenir à la retouche' : 'Voir le détourage automatique',
                    _basculerControle,
                    actif: _controle,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _boutonRond(IconData icone, String info, VoidCallback onTap, {bool actif = false}) {
    final theme = Theme.of(context);
    return Material(
      color: actif ? theme.colorScheme.primary : theme.colorScheme.surface.withOpacity(0.9),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: info,
        icon: Icon(icone, color: actif ? theme.colorScheme.onPrimary : null),
        onPressed: onTap,
      ),
    );
  }

  /// Toolbox verticale façon Krita : icônes groupées par famille, l'outil actif
  /// est rempli ; l'infobulle donne le nom et l'aide de l'outil.
  /// Panneau des calques (bottom sheet) : liste de la couche du haut vers le bas,
  /// visibilité, activation (toucher), renommage (appui long), et les actions
  /// ajouter / dupliquer / supprimer / monter / descendre.
  Future<void> _panneauCalques() async {
    final c = _c;
    if (c == null) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text('Calques', style: Theme.of(ctx).textTheme.titleMedium),
                    const Spacer(),
                    Text('${c.nbCouches} couche(s) — ${c.couche(c.actif).nom} active',
                        style: Theme.of(ctx).textTheme.bodySmall),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: c.nbCouches,
                  itemBuilder: (ctx, index) {
                    final rev = c.nbCouches - 1 - index; // le haut de la liste est la couche du dessus
                    final couche = c.couche(rev);
                    final active = rev == c.actif;
                    return ListTile(
                      dense: true,
                      selected: active,
                      leading: IconButton(
                        tooltip: couche.visible ? 'Masquer' : 'Afficher',
                        icon: Icon(couche.visible ? Icons.visibility : Icons.visibility_off),
                        onPressed: () {
                          c.basculerVisibilite(rev);
                          _rafraichir();
                          setS(() {});
                        },
                      ),
                      title: Text(
                        couche.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: active ? const TextStyle(fontWeight: FontWeight.bold) : null,
                      ),
                      onTap: () {
                        c.activerCouche(rev);
                        setS(() {});
                      },
                      onLongPress: () => _renommerCouche(rev),
                      trailing: active ? const Icon(Icons.brush, size: 16) : null,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Ajouter une couche',
                      icon: const Icon(Icons.add_box_outlined),
                      onPressed: () {
                        c.ajouterCouche();
                        _rafraichir();
                        setS(() {});
                      },
                    ),
                    IconButton(
                      tooltip: 'Dupliquer la couche active',
                      icon: const Icon(Icons.content_copy_outlined),
                      onPressed: () {
                        c.dupliquerCouche();
                        _rafraichir();
                        setS(() {});
                      },
                    ),
                    IconButton(
                      tooltip: 'Supprimer la couche active',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        if (!c.supprimerCouche()) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Il faut toujours au moins une couche.')),
                          );
                          return;
                        }
                        _rafraichir();
                        setS(() {});
                      },
                    ),
                    IconButton(
                      tooltip: 'Monter la couche',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: () {
                        c.deplacerCouche(1);
                        _rafraichir();
                        setS(() {});
                      },
                    ),
                    IconButton(
                      tooltip: 'Descendre la couche',
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: () {
                        c.deplacerCouche(-1);
                        _rafraichir();
                        setS(() {});
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Renomme une couche (appui long dans le panneau des calques).
  Future<void> _renommerCouche(int i) async {
    final c = _c;
    if (c == null) return;
    final ctrl = TextEditingController(text: c.couche(i).nom);
    final nom = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer la couche'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Nom')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nom == null || nom.isEmpty || !mounted) return;
    setState(() {
      c.renommerCouche(i, nom);
    });
  }

  Widget _toolbox(CalqueRetouche c) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      elevation: 4,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: 56,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              for (var g = 0; g < groupesOutils.length; g++) ...[
                if (g > 0) const Divider(height: 10, indent: 12, endIndent: 12),
                for (final o in groupesOutils[g])
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                    child: Tooltip(
                      message: '${o.libelle} — ${o.aide}',
                      waitDuration: const Duration(milliseconds: 400),
                      child: Material(
                        color: o == _outil ? theme.colorScheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            if (o == _outil) return;
                            _terminerOutil(annule: false);
                            setState(() {
                              _outil = o;
                              c.teinterProteges = o == Outil.proteger;
                            });
                            _rafraichir();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(
                              o.icone,
                              size: 22,
                              color: o == _outil ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Ligne « nom + valeur + curseur » du panneau de réglages.
  Widget _ligneReglage(
    String nom,
    String valeur,
    double v,
    double min,
    double max,
    int divisions,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 104, child: Text('$nom $valeur')),
        Expanded(child: Slider(value: v, min: min, max: max, divisions: divisions, onChanged: onChanged)),
      ],
    );
  }

  Widget _panneau(CalqueRetouche c) {
    final theme = Theme.of(context);
    final forme = _estForme && _outil != Outil.degrade;
    final peint = _peint;
    final tailleOutil = _aTaille;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_controle) ...[
                Text(
                  'Résultat du détourage automatique avec tes retouches. Ferme l\'œil pour continuer à retoucher.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                _puces(),
              ] else ...[
                Text(_outil.libelle, style: theme.textTheme.titleSmall),
                Text(_outil.aide, style: theme.textTheme.bodySmall),
                if (tailleOutil)
                  _ligneReglage('Taille', '$_taille px', _taille.toDouble(), 1, 80, 79,
                      (v) => setState(() => _taille = v.round())),
                if (_aOpacite)
                  _ligneReglage('Opacité', '${(_opacite * 100).round()} %', _opacite, 0.05, 1, 19,
                      (v) => setState(() => _opacite = v)),
                if (_aDurete)
                  _ligneReglage('Dureté', '${(_durete * 100).round()} %', _durete, 0, 1, 20,
                      (v) => setState(() => _durete = v)),
                if (_estBrosse)
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_outil == Outil.pinceau || _outil == Outil.gomme)
                        FilterChip(
                          label: const Text('Lissage'),
                          selected: _lissage,
                          visualDensity: VisualDensity.compact,
                          onSelected: (v) => setState(() => _lissage = v),
                        ),
                      for (final s in Symetrie.values)
                        ChoiceChip(
                          label: Text(s.libelle),
                          selected: _symetrie == s,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _symetrie = s),
                        ),
                    ],
                  ),
                if (_estSelection)
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (m, nom) in <(ModeSelection, String)>[
                        (ModeSelection.remplacer, 'Remplacer'),
                        (ModeSelection.ajouter, 'Ajouter'),
                        (ModeSelection.soustraire, 'Soustraire'),
                        (ModeSelection.intersecter, 'Intersecter'),
                      ])
                        ChoiceChip(
                          label: Text(nom),
                          selected: _modeSelection == m,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _modeSelection = m),
                        ),
                    ],
                  ),
                if (_outil == Outil.baguette || _outil == Outil.remplissage || _outil == Outil.selBaguette)
                  Row(
                    children: [
                      SizedBox(width: 72, child: Text('Tolér. $_tolerance')),
                      Expanded(
                        child: Slider(
                          value: _tolerance.toDouble(),
                          min: 0,
                          max: 120,
                          divisions: 24,
                          label: '$_tolerance',
                          onChanged: (v) => setState(() => _tolerance = v.round()),
                        ),
                      ),
                      if (_outil == Outil.baguette || _outil == Outil.selBaguette)
                        FilterChip(
                          label: const Text('Contigu'),
                          selected: _contigu,
                          onSelected: (v) => setState(() => _contigu = v),
                        ),
                    ],
                  ),
                if (forme)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final (m, nom) in <(ModeRetouche, String)>[
                        (ModeRetouche.peindre, 'Peindre'),
                        (ModeRetouche.effacer, 'Supprimer'),
                        (ModeRetouche.proteger, 'Protéger'),
                        (ModeRetouche.restaurer, 'Restaurer'),
                      ])
                        ChoiceChip(
                          label: Text(nom),
                          selected: _actionForme == m,
                          onSelected: (_) => setState(() => _actionForme = m),
                        ),
                      if (_outil != Outil.ligne)
                        FilterChip(
                          label: Text(_rempli ? 'Plein' : 'Contour'),
                          selected: _rempli,
                          onSelected: (v) => setState(() => _rempli = v),
                        ),
                    ],
                  ),
                if (_outil == Outil.baguette || _outil == Outil.lasso) ...[
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final (m, nom) in <(ModeRetouche, String)>[
                        (ModeRetouche.effacer, 'Supprimer'),
                        (ModeRetouche.proteger, 'Protéger'),
                        (ModeRetouche.peindre, 'Remplir'),
                        (ModeRetouche.restaurer, 'Restaurer'),
                      ])
                        ChoiceChip(
                          label: Text(nom),
                          selected: _actionZone == m,
                          onSelected: (_) => setState(() => _actionZone = m),
                        ),
                      if (_outil == Outil.lasso)
                        FilterChip(
                          label: Text(_interieur ? 'Intérieur' : 'Extérieur'),
                          selected: true,
                          onSelected: (_) => setState(() => _interieur = !_interieur),
                        ),
                    ],
                  ),
                ],
                if (c.aSelection)
                  Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Sélection active :', style: theme.textTheme.bodySmall),
                      TextButton(
                        onPressed: () {
                          c.selectionTout();
                          _majContour();
                          setState(() {});
                        },
                        child: const Text('Tout'),
                      ),
                      TextButton(
                        onPressed: () {
                          c.selectionInverser();
                          _majContour();
                          setState(() {});
                        },
                        child: const Text('Inverser'),
                      ),
                      TextButton(
                        onPressed: () {
                          c.selectionRien();
                          _majContour();
                          setState(() {});
                        },
                        child: const Text('Aucune'),
                      ),
                    ],
                  ),
                if (peint) _paletteCouleurs(),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: _puces()),
                    TextButton(onPressed: _restaurerTout, child: const Text('Tout restaurer')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _puces() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          const Padding(padding: EdgeInsets.only(right: 6), child: Center(child: Text('Fond'))),
          for (final f in FondControle.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(f.libelle),
                selected: f == _fond,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _fond = f),
              ),
            ),
        ],
      ),
    );
  }

  /// Pastille de couleur (posée sur un damier si elle est semi-transparente).
  Widget _pastille(Color col, {required bool active, required VoidCallback onTap}) {
    final disque = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: col,
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? Theme.of(context).colorScheme.primary : Colors.black26,
          width: active ? 3 : 1,
        ),
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: col.alpha < 255
          ? Stack(
              alignment: Alignment.center,
              children: [const SizedBox(width: 32, height: 32, child: Damier(taille: 8)), disque],
            )
          : disque,
    );
  }

  Widget _paletteCouleurs() {
    final couleurs = <Color>[
      ..._recentes,
      for (final b in paletteBase) if (!_recentes.contains(Color(b))) Color(b),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _pastille(_couleur, active: true, onTap: () => _editerCouleur(secondaire: false)),
          ),
          if (_outil == Outil.degrade) ...[
            IconButton(
              tooltip: 'Échanger les deux couleurs',
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.swap_horiz),
              onPressed: () => setState(() {
                final t = _couleur;
                _couleur = _couleurSecondaire;
                _couleurSecondaire = t;
              }),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _pastille(_couleurSecondaire, active: false, onTap: () => _editerCouleur(secondaire: true)),
            ),
          ],
          for (final col in couleurs)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _pastille(col, active: col == _couleur, onTap: () => _choisirCouleur(col)),
            ),
          IconButton(
            tooltip: 'Sélecteur de couleur (TSL + RVB + alpha)',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => _editerCouleur(secondaire: false),
          ),
        ],
      ),
    );
  }
}

class _PeintreRetouche extends CustomPainter {
  final ui.Image? image;
  final int largeur;
  final int hauteur;
  final double echelle;
  final Offset decalage;
  final FondControle fond;
  final List<Offset> lasso;
  final Offset? curseur;
  final double rayonCurseur;
  final bool interieurLasso;
  final Outil? formeOutil;
  final Offset? formeA;
  final Offset? formeB;
  final bool formeRempli;
  final Color formeCouleur;
  final Color formeCouleurSecondaire;
  final double formeEpaisseur;
  final bool grille;
  final List<double> contour;

  _PeintreRetouche({
    required this.image,
    required this.largeur,
    required this.hauteur,
    required this.echelle,
    required this.decalage,
    required this.fond,
    required this.lasso,
    required this.curseur,
    required this.rayonCurseur,
    required this.interieurLasso,
    required this.formeOutil,
    required this.formeA,
    required this.formeB,
    required this.formeRempli,
    required this.formeCouleur,
    required this.formeCouleurSecondaire,
    required this.formeEpaisseur,
    required this.grille,
    required this.contour,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2B2B2B));
    final dst = Rect.fromLTWH(decalage.dx, decalage.dy, largeur * echelle, hauteur * echelle);
    final visible = dst.intersect(Offset.zero & size);

    if (!visible.isEmpty) {
      if (fond == FondControle.damier) {
        const cote = 12.0;
        final clair = Paint()..color = const Color(0xFFF2F2F2);
        final fonce = Paint()..color = const Color(0xFFD0D0D0);
        canvas.save();
        canvas.clipRect(visible);
        final j0 = ((visible.top - dst.top) / cote).floor();
        final j1 = ((visible.bottom - dst.top) / cote).ceil();
        final i0 = ((visible.left - dst.left) / cote).floor();
        final i1 = ((visible.right - dst.left) / cote).ceil();
        for (var j = j0; j < j1; j++) {
          for (var i = i0; i < i1; i++) {
            canvas.drawRect(
              Rect.fromLTWH(dst.left + i * cote, dst.top + j * cote, cote, cote),
              (i + j) % 2 == 0 ? clair : fonce,
            );
          }
        }
        canvas.restore();
      } else {
        canvas.drawRect(dst, Paint()..color = fond.couleur);
      }
    }

    final im = image;
    if (im != null) {
      canvas.drawImageRect(
        im,
        Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    canvas.drawRect(
      dst,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF888888),
    );

    // Grille des pixels quand le zoom est fort (pixel art).
    if (grille && !visible.isEmpty) {
      final pFonce = Paint()
        ..color = const Color(0x2E000000)
        ..strokeWidth = 1;
      final pClair = Paint()
        ..color = const Color(0x2EFFFFFF)
        ..strokeWidth = 1;
      final i0 = math.max(0, ((visible.left - dst.left) / echelle).floor());
      final i1 = math.min(largeur, ((visible.right - dst.left) / echelle).ceil());
      final j0 = math.max(0, ((visible.top - dst.top) / echelle).floor());
      final j1 = math.min(hauteur, ((visible.bottom - dst.top) / echelle).ceil());
      for (var i = i0; i <= i1; i++) {
        final x = dst.left + i * echelle;
        canvas.drawLine(Offset(x, visible.top), Offset(x, visible.bottom), pFonce);
        canvas.drawLine(Offset(x, visible.top), Offset(x, visible.bottom), pClair);
      }
      for (var j = j0; j <= j1; j++) {
        final y = dst.top + j * echelle;
        canvas.drawLine(Offset(visible.left, y), Offset(visible.right, y), pFonce);
        canvas.drawLine(Offset(visible.left, y), Offset(visible.right, y), pClair);
      }
    }

    // Contour de la sélection courante (coordonnées image → écran).
    if (contour.length >= 4) {
      final pFonce = Paint()
        ..color = const Color(0xFF000000)
        ..strokeWidth = 2;
      final pClair = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..strokeWidth = 1;
      for (var k = 0; k + 3 < contour.length; k += 4) {
        final a = Offset(decalage.dx + contour[k] * echelle, decalage.dy + contour[k + 1] * echelle);
        final b = Offset(decalage.dx + contour[k + 2] * echelle, decalage.dy + contour[k + 3] * echelle);
        canvas.drawLine(a, b, pFonce);
        canvas.drawLine(a, b, pClair);
      }
    }

    if (lasso.length >= 2) {
      final chemin = Path()..moveTo(lasso.first.dx, lasso.first.dy);
      for (final p in lasso.skip(1)) {
        chemin.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        chemin,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white,
      );
      canvas.drawPath(
        chemin,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = interieurLasso ? const Color(0xFFFF6F00) : const Color(0xFF2962FF),
      );
      canvas.drawLine(
        lasso.last,
        lasso.first,
        Paint()
          ..strokeWidth = 1
          ..color = const Color(0x88FFFFFF),
      );
    }

    final fa = formeA;
    final fb = formeB;
    if (formeOutil != null && fa != null && fb != null) {
      final ep = formeEpaisseur < 1 ? 1.0 : formeEpaisseur;
      final trait = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ep
        ..strokeCap = StrokeCap.round
        ..color = formeCouleur;
      final plein = Paint()..color = formeCouleur;
      final cadre = Rect.fromPoints(fa, fb);
      final creux = cadre.width > ep && cadre.height > ep;
      if (formeOutil == Outil.degrade) {
        // Aperçu du dégradé : trait en dégradé linéaire entre les deux couleurs.
        canvas.drawLine(
          fa,
          fb,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = ep
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(fa, fb, [formeCouleur, formeCouleurSecondaire]),
        );
      } else if (formeOutil == Outil.ligne) {
        canvas.drawLine(fa, fb, trait);
      } else if (formeOutil == Outil.rectangle) {
        canvas.drawRect(formeRempli || !creux ? cadre : cadre.deflate(ep / 2), formeRempli || !creux ? plein : trait);
      } else if (formeOutil == Outil.ellipse) {
        canvas.drawOval(formeRempli || !creux ? cadre : cadre.deflate(ep / 2), formeRempli || !creux ? plein : trait);
      } else if (formeOutil == Outil.selRect || formeOutil == Outil.selEllipse) {
        // Aperçu d'une sélection rectangulaire / elliptique : contour blanc.
        final pSel = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white;
        if (formeOutil == Outil.selRect) {
          canvas.drawRect(cadre, pSel);
        } else {
          canvas.drawOval(cadre, pSel);
        }
      }
      // Contour fin pour repérer le cadre quelle que soit la couleur.
      if (formeOutil != Outil.degrade && formeOutil != Outil.selRect && formeOutil != Outil.selEllipse) {
        canvas.drawRect(
          cadre,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0x99FFFFFF),
        );
      }
    }

    final cur = curseur;
    if (cur != null) {
      final r = rayonCurseur < 3 ? 3.0 : rayonCurseur;
      canvas.drawCircle(
        cur,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.black,
      );
      canvas.drawCircle(
        cur,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PeintreRetouche old) => true;
}
