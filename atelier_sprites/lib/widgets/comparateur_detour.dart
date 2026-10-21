/// Contrôle visuel du détourage : résultat sur fond contrasté, comparaison
/// avant/après (curseur de séparation), zones retirées en rouge ; zoom au doigt.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/traitement.dart';
import 'damier.dart';

enum ModeComparaison { resultat, avantApres, retrait }

enum FondControle { damier, noir, blanc, magenta, herbe }

extension FondControleX on FondControle {
  String get libelle => switch (this) {
        FondControle.damier => 'Damier',
        FondControle.noir => 'Noir',
        FondControle.blanc => 'Blanc',
        FondControle.magenta => 'Magenta',
        FondControle.herbe => 'Herbe',
      };

  Color get couleur => switch (this) {
        FondControle.damier => Colors.transparent,
        FondControle.noir => const Color(0xFF111111),
        FondControle.blanc => Colors.white,
        FondControle.magenta => const Color(0xFFE91E63),
        FondControle.herbe => const Color(0xFF5D8A3A),
      };
}

class ComparateurDetour extends StatefulWidget {
  final ApercuDetour apercu;

  /// Calcul en cours : l'ancien aperçu reste affiché, légèrement voilé.
  final bool calcul;

  const ComparateurDetour({super.key, required this.apercu, this.calcul = false});

  @override
  State<ComparateurDetour> createState() => _ComparateurDetourState();
}

class _ComparateurDetourState extends State<ComparateurDetour> {
  ModeComparaison _mode = ModeComparaison.resultat;
  FondControle _fond = FondControle.noir;
  double _separation = 0.5;
  final TransformationController _zoom = TransformationController();

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  Widget _image(Uint8List octets) => Image.memory(
        octets,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.none, // pixels nets au zoom : on voit le liseré
      );

  Widget _fondWidget() =>
      _fond == FondControle.damier ? const Damier() : ColoredBox(color: _fond.couleur);

  @override
  Widget build(BuildContext context) {
    final a = widget.apercu;
    final theme = Theme.of(context);
    final scene = switch (_mode) {
      ModeComparaison.resultat => Stack(fit: StackFit.expand, children: [_fondWidget(), _image(a.detoure)]),
      ModeComparaison.retrait => Stack(fit: StackFit.expand, children: [_image(a.original), _image(a.retrait)]),
      ModeComparaison.avantApres => Stack(
          fit: StackFit.expand,
          children: [
            _fondWidget(),
            _image(a.detoure),
            ClipRect(clipper: _Gauche(_separation), child: _image(a.original)),
            LayoutBuilder(
              builder: (context, c) => Stack(children: [
                Positioned(
                  left: c.maxWidth * _separation - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.orangeAccent),
                ),
              ]),
            ),
          ],
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ModeComparaison>(
          segments: const [
            ButtonSegment(value: ModeComparaison.resultat, label: Text('Résultat'), icon: Icon(Icons.auto_fix_high)),
            ButtonSegment(value: ModeComparaison.avantApres, label: Text('Avant/après'), icon: Icon(Icons.compare)),
            ButtonSegment(value: ModeComparaison.retrait, label: Text('Retiré'), icon: Icon(Icons.layers_clear)),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: a.largeur / a.hauteur,
            child: Stack(
              fit: StackFit.expand,
              children: [
                InteractiveViewer(
                  transformationController: _zoom,
                  minScale: 1,
                  maxScale: 10,
                  child: scene,
                ),
                if (widget.calcul) const ColoredBox(color: Color(0x33000000)),
                if (widget.calcul) const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator()),
              ],
            ),
          ),
        ),
        if (_mode == ModeComparaison.avantApres)
          Row(
            children: [
              const Text('Avant'),
              Expanded(
                child: Slider(value: _separation, onChanged: (v) => setState(() => _separation = v)),
              ),
              const Text('Après'),
            ],
          ),
        if (_mode != ModeComparaison.retrait) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (final f in FondControle.values)
                ChoiceChip(
                  label: Text(f.libelle),
                  selected: f == _fond,
                  onSelected: (_) => setState(() => _fond = f),
                ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                switch (_mode) {
                  ModeComparaison.resultat =>
                    'Fond noir ou magenta : un liseré blanc saute aux yeux. Pince pour zoomer.',
                  ModeComparaison.avantApres => 'Fais glisser le curseur pour comparer. Pince pour zoomer.',
                  ModeComparaison.retrait =>
                    'En rouge : ce qui sera retiré. Aucun rouge ne doit mordre sur le personnage.',
                },
                style: theme.textTheme.bodySmall,
              ),
            ),
            IconButton(
              tooltip: 'Recentrer',
              icon: const Icon(Icons.zoom_out_map),
              onPressed: () => _zoom.value = Matrix4.identity(),
            ),
          ],
        ),
      ],
    );
  }
}

class _Gauche extends CustomClipper<Rect> {
  final double fraction;

  _Gauche(this.fraction);

  @override
  Rect getClip(Size s) => Rect.fromLTWH(0, 0, s.width * fraction, s.height);

  @override
  bool shouldReclip(_Gauche old) => old.fraction != fraction;
}
