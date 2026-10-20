/// Aperçu des animations : joue les poses d'une planche en boucle pour
/// contrôler l'enchaînement avant l'export (cadence, aller-retour, miroir,
/// pelure d'oignon, ligne de sol) et partager un GIF.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/animations.dart';
import '../core/gif.dart';
import '../widgets/damier.dart';

/// Charge les images normalisées (carré, clé = index de case) selon l'ancrage.
typedef ChargeurImages = Future<Map<int, Uint8List>> Function(bool ancrageSol);

enum _Fond { damier, clair, sombre, herbe }

extension on _Fond {
  String get libelle => switch (this) {
        _Fond.damier => 'Damier',
        _Fond.clair => 'Clair',
        _Fond.sombre => 'Sombre',
        _Fond.herbe => 'Herbe',
      };

  /// Couleur unie (le damier est approché par un gris clair dans le GIF).
  int get rgb => switch (this) {
        _Fond.damier => 0xE6E6E6,
        _Fond.clair => 0xF5F5F5,
        _Fond.sombre => 0x263238,
        _Fond.herbe => 0x6B8E4E,
      };
}

class AnimationScreen extends StatefulWidget {
  final String titre;

  /// Base du nom du GIF partagé (ex. `assassin_back`).
  final String nomBase;
  final List<AnimationDef> animations;

  /// Nom de fichier final de chaque case (affiché sous l'aperçu).
  final Map<int, String> nomsCases;
  final bool ancrageSol;
  final double margeSol;
  final ChargeurImages charger;

  /// Appelé quand l'utilisateur change l'ancrage : le choix s'applique à l'export.
  final ValueChanged<bool> onAncrageChange;

  const AnimationScreen({
    super.key,
    required this.titre,
    required this.nomBase,
    required this.animations,
    required this.nomsCases,
    required this.ancrageSol,
    required this.margeSol,
    required this.charger,
    required this.onAncrageChange,
  });

  @override
  State<AnimationScreen> createState() => _AnimationScreenState();
}

class _AnimationScreenState extends State<AnimationScreen> {
  Map<int, MemoryImage> _images = <int, MemoryImage>{};
  Map<int, Uint8List> _octets = <int, Uint8List>{};
  bool _chargement = true;
  String? _erreur;

  int _anim = 0;
  final Map<int, Set<int>> _exclues = <int, Set<int>>{};
  late int _fps;
  late bool _allerRetour;
  bool _miroir = false;
  bool _pelure = false;
  bool _ligneSol = true;
  late bool _ancrageSol;
  _Fond _fond = _Fond.damier;

  bool _lecture = true;
  int _pos = 0;
  Timer? _minuterie;
  bool _exportGif = false;

  @override
  void initState() {
    super.initState();
    _ancrageSol = widget.ancrageSol;
    _appliquerAnimation(0);
    _charger();
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------------------------------
  // Données
  // ------------------------------------------------------------------------------------------

  Future<void> _charger() async {
    _minuterie?.cancel();
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final octets = await widget.charger(_ancrageSol);
      final images = <int, MemoryImage>{
        for (final e in octets.entries) e.key: MemoryImage(e.value),
      };
      if (!mounted) return;
      // Pré-décodage : pas de clignotement au premier tour de boucle.
      await Future.wait(images.values.map((i) => precacheImage(i, context)));
      if (!mounted) return;
      setState(() {
        _octets = octets;
        _images = images;
        _chargement = false;
        _pos = 0;
      });
      _relancer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = '$e';
      });
    }
  }

  AnimationDef get _def => widget.animations[_anim];

  List<int> get _casesActives {
    final exclues = _exclues[_anim] ?? const <int>{};
    return <int>[
      for (final c in _def.cases)
        if (!exclues.contains(c) && _images.containsKey(c)) c,
    ];
  }

  List<int> get _sequence => sequenceLecture(_casesActives, allerRetour: _allerRetour);

  int? get _caseCourante {
    final seq = _sequence;
    if (seq.isEmpty) return null;
    return seq[_pos % seq.length];
  }

  int? get _casePrecedente {
    final seq = _sequence;
    if (seq.length < 2) return null;
    return seq[(_pos - 1 + seq.length) % seq.length];
  }

  // ------------------------------------------------------------------------------------------
  // Lecture
  // ------------------------------------------------------------------------------------------

  void _appliquerAnimation(int index) {
    _anim = index;
    _fps = widget.animations[index].fps;
    _allerRetour = widget.animations[index].allerRetour;
    _pos = 0;
  }

  void _relancer() {
    _minuterie?.cancel();
    if (!_lecture || _chargement) return;
    _minuterie = Timer.periodic(Duration(milliseconds: (1000 / _fps).round()), (_) {
      final n = _sequence.length;
      if (n < 2 || !mounted) return;
      setState(() => _pos = (_pos + 1) % n);
    });
  }

  void _basculerLecture() {
    setState(() => _lecture = !_lecture);
    _relancer();
  }

  void _pas(int delta) {
    final n = _sequence.length;
    if (n == 0) return;
    _minuterie?.cancel();
    setState(() {
      _lecture = false;
      _pos = (_pos + delta + n) % n;
    });
  }

  void _choisirAnimation(int index) {
    setState(() => _appliquerAnimation(index));
    _relancer();
  }

  void _basculerCase(int c) {
    setState(() {
      final exclues = _exclues.putIfAbsent(_anim, () => <int>{});
      if (!exclues.remove(c)) exclues.add(c);
      _pos = 0;
    });
  }

  void _allerA(int c) {
    final seq = _sequence;
    final i = seq.indexOf(c);
    if (i < 0) return;
    _minuterie?.cancel();
    setState(() {
      _lecture = false;
      _pos = i;
    });
  }

  // ------------------------------------------------------------------------------------------
  // GIF
  // ------------------------------------------------------------------------------------------

  Future<void> _partagerGif() async {
    final seq = _sequence;
    if (seq.isEmpty) return;
    setState(() => _exportGif = true);
    try {
      final demande = DemandeGif(
        images: <Uint8List>[for (final c in seq) _octets[c]!],
        dureeMs: (1000 / _fps).round(),
        miroir: _miroir,
        fond: _fond.rgb,
      );
      final gif = await compute(encoderGif, demande);
      final dossier = await getTemporaryDirectory();
      final suffixe = _def.famille == null ? 'planche' : _def.libelle.toLowerCase();
      final fichier = File('${dossier.path}/${widget.nomBase}_$suffixe${_miroir ? '_miroir' : ''}.gif');
      await fichier.writeAsBytes(gif, flush: true);
      await Share.shareXFiles(
        <XFile>[XFile(fichier.path, mimeType: 'image/gif')],
        text: '${widget.titre} — ${_def.libelle} (${seq.length} images, $_fps img/s)',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec du GIF : $e')));
      }
    } finally {
      if (mounted) setState(() => _exportGif = false);
    }
  }

  // ------------------------------------------------------------------------------------------
  // Interface
  // ------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titre),
        actions: [
          IconButton(
            tooltip: 'Partager en GIF',
            onPressed: (_chargement || _exportGif || _sequence.isEmpty) ? null : _partagerGif,
            icon: _exportGif
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.gif_box_outlined),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Impossible de préparer l\'aperçu : $_erreur'),
                  ),
                )
              : _contenu(context),
    );
  }

  Widget _contenu(BuildContext context) {
    final theme = Theme.of(context);
    final seq = _sequence;
    final courante = _caseCourante;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var i = 0; i < widget.animations.length; i++)
              ChoiceChip(
                label: Text('${widget.animations[i].libelle} · ${widget.animations[i].cases.length}'),
                selected: i == _anim,
                onSelected: (_) => _choisirAnimation(i),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _scene(theme),
        const SizedBox(height: 6),
        Text(
          courante == null
              ? 'Aucune image active dans cette animation.'
              : '${(_pos % seq.length) + 1}/${seq.length} · ${widget.nomsCases[courante] ?? 'case ${courante + 1}'}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Image précédente',
              onPressed: seq.isEmpty ? null : () => _pas(-1),
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton.filled(
              tooltip: _lecture ? 'Pause' : 'Lecture',
              onPressed: seq.length < 2 ? null : _basculerLecture,
              icon: Icon(_lecture ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: 'Image suivante',
              onPressed: seq.isEmpty ? null : () => _pas(1),
              icon: const Icon(Icons.skip_next),
            ),
          ],
        ),
        Text('Cadence : $_fps img/s (${(1000 / _fps).round()} ms par image)'),
        Slider(
          value: _fps.toDouble(),
          min: 1,
          max: 24,
          divisions: 23,
          label: '$_fps',
          onChanged: (v) {
            setState(() => _fps = v.round());
            _relancer();
          },
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: const Text('Aller-retour'),
              selected: _allerRetour,
              onSelected: (v) => setState(() {
                _allerRetour = v;
                _pos = 0;
              }),
            ),
            FilterChip(
              label: const Text('Miroir (vers la gauche)'),
              selected: _miroir,
              onSelected: (v) => setState(() => _miroir = v),
            ),
            FilterChip(
              label: const Text('Pelure d\'oignon'),
              selected: _pelure,
              onSelected: (v) => setState(() => _pelure = v),
            ),
            FilterChip(
              label: const Text('Ligne de sol'),
              selected: _ligneSol,
              onSelected: (v) => setState(() => _ligneSol = v),
            ),
            FilterChip(
              label: const Text('Pieds alignés'),
              tooltip: 'Ancrage au sol des cases exportées',
              selected: _ancrageSol,
              onSelected: (v) {
                setState(() => _ancrageSol = v);
                widget.onAncrageChange(v);
                _charger();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<_Fond>(
          segments: [
            for (final f in _Fond.values) ButtonSegment(value: f, label: Text(f.libelle)),
          ],
          selected: <_Fond>{_fond},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _fond = s.first),
        ),
        const SizedBox(height: 12),
        Text('Images de l\'animation', style: theme.textTheme.titleSmall),
        Text(
          'Touche une image pour l\'inclure ou l\'exclure de la boucle ; '
          'appui long pour s\'y arrêter.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        _pellicule(theme, courante),
        const SizedBox(height: 12),
        Text(
          _ancrageSol
              ? 'Pieds alignés : le bas de chaque sprite est posé sur la même ligne de sol à l\'export.'
              : 'Cases centrées : si le personnage « saute » pendant la boucle, active « Pieds alignés » '
                  '(le réglage s\'applique aussi à l\'export).',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _scene(ThemeData theme) {
    final courante = _caseCourante;
    final precedente = _pelure ? _casePrecedente : null;
    Widget sprite(int c, {double opacite = 1}) {
      Widget w = Image(
        image: _images[c]!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
      if (opacite < 1) w = Opacity(opacity: opacite, child: w);
      if (_miroir) {
        w = Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(-1, 1, 1),
          child: w,
        );
      }
      return Positioned.fill(child: w);
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
              onTap: _sequence.length < 2 ? null : _basculerLecture,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _fond == _Fond.damier
                        ? const Damier()
                        : ColoredBox(color: Color(0xFF000000 | _fond.rgb)),
                  ),
                  if (precedente != null && precedente != courante) sprite(precedente, opacite: 0.3),
                  if (courante != null) sprite(courante),
                  if (_ligneSol)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RepereSol(
                          margeSol: widget.margeSol,
                          couleur: _fond == _Fond.sombre ? Colors.amberAccent : Colors.deepOrange,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pellicule(ThemeData theme, int? courante) {
    final exclues = _exclues[_anim] ?? const <int>{};
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _def.cases.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = _def.cases[i];
          final image = _images[c];
          final active = !exclues.contains(c);
          return GestureDetector(
            onTap: () => _basculerCase(c),
            onLongPress: active ? () => _allerA(c) : null,
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      width: c == courante ? 3 : 1,
                      color: c == courante ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Opacity(
                      opacity: active ? 1 : 0.3,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const Damier(taille: 6),
                          if (image != null) Image(image: image, fit: BoxFit.contain, gaplessPlayback: true),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'case ${c + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    decoration: active ? null : TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Ligne de sol (où l'export ancre les pieds) et axe central.
class _RepereSol extends CustomPainter {
  final double margeSol;
  final Color couleur;

  _RepereSol({required this.margeSol, required this.couleur});

  @override
  void paint(Canvas canvas, Size taille) {
    final y = taille.height * (1 - margeSol);
    final trait = Paint()
      ..color = couleur.withOpacity(0.8)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, y), Offset(taille.width, y), trait);
    final axe = Paint()
      ..color = couleur.withOpacity(0.25)
      ..strokeWidth = 1;
    final x = taille.width / 2;
    for (var yy = 0.0; yy < taille.height; yy += 10) {
      canvas.drawLine(Offset(x, yy), Offset(x, yy + 5), axe);
    }
  }

  @override
  bool shouldRepaint(_RepereSol old) => old.margeSol != margeSol || old.couleur != couleur;
}
