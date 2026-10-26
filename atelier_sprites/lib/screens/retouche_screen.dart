/// Retouche à la main d'une planche, façon logiciel de dessin : pinceau, gomme,
/// protection, restauration, baguette magique, lasso et pipette, zoom au doigt,
/// annuler / rétablir, et contrôle du résultat du détourage automatique.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/retouche.dart';
import '../models.dart';
import '../widgets/comparateur_detour.dart';

/// Résultat de l'éditeur : image retouchée (PNG) et carte des pixels forcés.
class ResultatRetouche {
  final Uint8List octets;
  final Uint8List forces;

  /// Plus aucune retouche (tout a été restauré) : revenir à l'image importée.
  final bool vide;

  const ResultatRetouche(this.octets, this.forces, this.vide);
}

enum Outil { pinceau, gomme, proteger, restaurer, baguette, lasso, pipette, main }

extension OutilX on Outil {
  String get libelle => switch (this) {
        Outil.pinceau => 'Pinceau',
        Outil.gomme => 'Gomme',
        Outil.proteger => 'Protéger',
        Outil.restaurer => 'Restaurer',
        Outil.baguette => 'Baguette',
        Outil.lasso => 'Lasso',
        Outil.pipette => 'Pipette',
        Outil.main => 'Déplacer',
      };

  IconData get icone => switch (this) {
        Outil.pinceau => Icons.brush,
        Outil.gomme => Icons.auto_fix_normal,
        Outil.proteger => Icons.shield_outlined,
        Outil.restaurer => Icons.settings_backup_restore,
        Outil.baguette => Icons.auto_fix_high,
        Outil.lasso => Icons.gesture,
        Outil.pipette => Icons.colorize,
        Outil.main => Icons.pan_tool_alt_outlined,
      };

  String get aide => switch (this) {
        Outil.pinceau => 'Peint en couleur ; ce qui est peint est protégé du détourage.',
        Outil.gomme => 'Supprime à la main (devient transparent), même si le détourage l\'aurait gardé.',
        Outil.proteger => 'Empêche le détourage de retirer ces pixels (cheveux blancs, reflets…).',
        Outil.restaurer => 'Rend l\'image d\'origine et repasse en détourage automatique.',
        Outil.baguette => 'Touche une couleur : applique l\'action à toute la zone de couleur proche.',
        Outil.lasso => 'Dessine le contour d\'une zone au doigt : l\'action s\'applique à son intérieur.',
        Outil.pipette => 'Touche un pixel pour prendre sa couleur.',
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

  const EcranRetouche({
    super.key,
    required this.octets,
    required this.options,
    required this.titre,
    this.octetsOrigine,
    this.forces,
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
  int _tolerance = 30;
  bool _contigu = true;
  bool _interieur = true;
  ModeRetouche _actionZone = ModeRetouche.effacer;
  Color _couleur = const Color(0xFFFFFFFF);
  final List<Color> _recentes = <Color>[];

  FondControle _fond = FondControle.magenta;

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
  Offset? _dernierImage;
  Offset? _curseur;
  final List<Offset> _lasso = <Offset>[];
  bool _actionOuverte = false;

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

  void _debutOutil(Offset p) {
    final c = _c!;
    final pi = _versImage(p);
    switch (_outil) {
      case Outil.pinceau || Outil.gomme || Outil.proteger || Outil.restaurer:
        c.commencer();
        _actionOuverte = true;
        _dernierImage = pi;
        c.tampon(_outil.mode!, pi.dx.floor(), pi.dy.floor(), _taille, r: _cr, g: _cg, b: _cb);
        setState(() => _curseur = p);
        _rafraichir();
      case Outil.lasso:
        _lasso
          ..clear()
          ..add(p);
        setState(() {});
      case Outil.baguette || Outil.pipette || Outil.main:
        break;
    }
  }

  void _moveOutil(Offset p) {
    final c = _c!;
    final pi = _versImage(p);
    switch (_outil) {
      case Outil.pinceau || Outil.gomme || Outil.proteger || Outil.restaurer:
        if (!_actionOuverte) return;
        final d = _dernierImage ?? pi;
        c.trait(_outil.mode!, d.dx.floor(), d.dy.floor(), pi.dx.floor(), pi.dy.floor(), _taille,
            r: _cr, g: _cg, b: _cb);
        _dernierImage = pi;
        setState(() => _curseur = p);
        _rafraichir();
      case Outil.lasso:
        if (_lasso.isEmpty || (p - _lasso.last).distance >= 3) {
          setState(() => _lasso.add(p));
        }
      case Outil.baguette || Outil.pipette || Outil.main:
        break;
    }
  }

  void _finOutil(Offset p) {
    final c = _c!;
    final pi = _versImage(p);
    switch (_outil) {
      case Outil.pinceau || Outil.gomme || Outil.proteger || Outil.restaurer:
        _terminerOutil(annule: false);
      case Outil.baguette:
        if (_aBouge) return;
        c.commencer();
        c.baguette(_actionZone, pi.dx.floor(), pi.dy.floor(),
            tolerance: _tolerance, contigu: _contigu, r: _cr, g: _cg, b: _cb);
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
      case Outil.lasso:
        final pts = <double>[
          for (final q in _lasso) ...[_versImage(q).dx, _versImage(q).dy],
        ];
        _lasso.clear();
        if (pts.length >= 6) {
          c.commencer();
          c.polygone(_actionZone, pts, interieur: _interieur, r: _cr, g: _cg, b: _cb);
          c.terminer();
          _rafraichir();
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
    if (_lasso.isNotEmpty) {
      _lasso.clear();
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
          pixels: c.pixels,
          forces: c.forces,
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
      final png = await compute(encoderRetouche, DemandeEncodage(c.largeur, c.hauteur, c.pixels));
      if (!mounted) return;
      Navigator.of(context).pop(ResultatRetouche(png, Uint8List.fromList(c.forces), vide));
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter sans enregistrer ?'),
        content: const Text('Les retouches de cette session seront perdues.'),
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

  Future<void> _editerCouleur() async {
    var r = _cr.toDouble();
    var g = _cg.toDouble();
    var b = _cb.toDouble();
    final choisie = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Couleur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, r.round(), g.round(), b.round()),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                ),
              ),
              for (final (nom, valeur, maj) in <(String, double, void Function(double))>[
                ('Rouge', r, (v) => r = v),
                ('Vert', g, (v) => g = v),
                ('Bleu', b, (v) => b = v),
              ])
                Row(
                  children: [
                    SizedBox(width: 48, child: Text(nom)),
                    Expanded(
                      child: Slider(
                        value: valeur,
                        min: 0,
                        max: 255,
                        divisions: 255,
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
              onPressed: () => Navigator.pop(ctx, Color.fromARGB(255, r.round(), g.round(), b.round())),
              child: const Text('Choisir'),
            ),
          ],
        ),
      ),
    );
    if (choisie != null) _choisirCouleur(choisie);
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
                      Expanded(child: _zoneDessin(c)),
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
                  _boutonRond(Icons.zoom_out_map, 'Ajuster la vue', () => setState(_ajusterVue)),
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

  Widget _panneau(CalqueRetouche c) {
    final theme = Theme.of(context);
    final peint = _outil == Outil.pinceau || (_actionZone == ModeRetouche.peindre && (_outil == Outil.baguette || _outil == Outil.lasso));
    final tailleOutil = _outil.mode != null;
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
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final o in Outil.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            avatar: Icon(o.icone, size: 18),
                            label: Text(o.libelle),
                            selected: o == _outil,
                            onSelected: (_) {
                              _terminerOutil(annule: false);
                              setState(() {
                                _outil = o;
                                c.teinterProteges = o == Outil.proteger;
                              });
                              _rafraichir();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                Text(_outil.aide, style: theme.textTheme.bodySmall),
                if (tailleOutil)
                  Row(
                    children: [
                      SizedBox(width: 72, child: Text('Taille $_taille')),
                      Expanded(
                        child: Slider(
                          value: _taille.toDouble(),
                          min: 1,
                          max: 80,
                          divisions: 79,
                          label: '$_taille px',
                          onChanged: (v) => setState(() => _taille = v.round()),
                        ),
                      ),
                    ],
                  ),
                if (_outil == Outil.baguette)
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
                      FilterChip(
                        label: const Text('Contigu'),
                        selected: _contigu,
                        onSelected: (v) => setState(() => _contigu = v),
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

  Widget _paletteCouleurs() {
    const base = <Color>[
      Color(0xFFFFFFFF),
      Color(0xFF000000),
      Color(0xFF9E9E9E),
      Color(0xFFD32F2F),
      Color(0xFFF57C00),
      Color(0xFFFBC02D),
      Color(0xFF388E3C),
      Color(0xFF1976D2),
      Color(0xFF7B1FA2),
      Color(0xFF795548),
    ];
    final couleurs = <Color>[..._recentes, for (final b in base) if (!_recentes.contains(b)) b];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final col in couleurs)
            GestureDetector(
              onTap: () => _choisirCouleur(col),
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
                decoration: BoxDecoration(
                  color: col,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: col == _couleur ? Theme.of(context).colorScheme.primary : Colors.black26,
                    width: col == _couleur ? 3 : 1,
                  ),
                ),
              ),
            ),
          IconButton(tooltip: 'Autre couleur', icon: const Icon(Icons.palette_outlined), onPressed: _editerCouleur),
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
