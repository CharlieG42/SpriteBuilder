/// Aperçu interactif d'une planche avec la grille par-dessus.
///
/// Les séparateurs se déplacent au doigt pour « ajuster » deux poses qui se
/// seraient touchées, comme décrit dans `prompts_sprites/README.md`.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/decoupe.dart';

class ApercuGrille extends StatefulWidget {
  final Uint8List octets;
  final int imageW;
  final int imageH;
  final Grille grille;
  final ValueChanged<Grille> onChanged;

  /// Index des cases exclues (affichées barrées).
  final Set<int> exclues;

  const ApercuGrille({
    super.key,
    required this.octets,
    required this.imageW,
    required this.imageH,
    required this.grille,
    required this.onChanged,
    this.exclues = const <int>{},
  });

  @override
  State<ApercuGrille> createState() => _ApercuGrilleState();
}

class _ApercuGrilleState extends State<ApercuGrille> {
  int? _sepCol;
  int? _sepRow;

  void _chercherSeparateur(Offset local, Size taille) {
    var meilleure = 0.04;
    int? col;
    int? row;
    for (var i = 1; i < widget.grille.colX.length - 1; i++) {
      final d = (widget.grille.colX[i] * taille.width - local.dx).abs() / taille.width;
      if (d < meilleure) {
        meilleure = d;
        col = i;
        row = null;
      }
    }
    for (var i = 1; i < widget.grille.rowY.length - 1; i++) {
      final d = (widget.grille.rowY[i] * taille.height - local.dy).abs() / taille.height;
      if (d < meilleure) {
        meilleure = d;
        row = i;
        col = null;
      }
    }
    setState(() {
      _sepCol = col;
      _sepRow = row;
    });
  }

  void _deplacer(Offset local, Size taille) {
    final g = widget.grille;
    if (_sepCol != null) {
      final min = g.colX[_sepCol! - 1] + 0.02;
      final max = g.colX[_sepCol! + 1] - 0.02;
      final nx = (local.dx / taille.width).clamp(min, max);
      final colX = List<double>.of(g.colX);
      colX[_sepCol!] = nx;
      widget.onChanged(
        Grille.personnalisee(cols: g.cols, rows: g.rows, colX: colX, rowY: g.rowY),
      );
    } else if (_sepRow != null) {
      final min = g.rowY[_sepRow! - 1] + 0.02;
      final max = g.rowY[_sepRow! + 1] - 0.02;
      final ny = (local.dy / taille.height).clamp(min, max);
      final rowY = List<double>.of(g.rowY);
      rowY[_sepRow!] = ny;
      widget.onChanged(
        Grille.personnalisee(cols: g.cols, rows: g.rows, colX: g.colX, rowY: rowY),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageW <= 0 || widget.imageH <= 0) {
      return const SizedBox.shrink();
    }
    return AspectRatio(
      aspectRatio: widget.imageW / widget.imageH,
      child: LayoutBuilder(
        builder: (context, contraintes) {
          final taille = contraintes.biggest;
          return GestureDetector(
            onPanStart: (d) => _chercherSeparateur(d.localPosition, taille),
            onPanUpdate: (d) => _deplacer(d.localPosition, taille),
            onPanEnd: (_) => setState(() {
              _sepCol = null;
              _sepRow = null;
            }),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(widget.octets, fit: BoxFit.fill, gaplessPlayback: true),
                CustomPaint(
                  painter: _GrillePainter(
                    grille: widget.grille,
                    exclues: widget.exclues,
                    sepCol: _sepCol,
                    sepRow: _sepRow,
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

class _GrillePainter extends CustomPainter {
  final Grille grille;
  final Set<int> exclues;
  final int? sepCol;
  final int? sepRow;

  _GrillePainter({
    required this.grille,
    required this.exclues,
    this.sepCol,
    this.sepRow,
  });

  @override
  void paint(Canvas canvas, Size taille) {
    final lignes = Paint()
      ..color = Colors.deepOrange
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final actif = Paint()
      ..color = Colors.orange
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < grille.colX.length; i++) {
      final x = grille.colX[i] * taille.width;
      canvas.drawLine(Offset(x, 0), Offset(x, taille.height),
          i == sepCol ? actif : lignes);
    }
    for (var i = 0; i < grille.rowY.length; i++) {
      final y = grille.rowY[i] * taille.height;
      canvas.drawLine(Offset(0, y), Offset(taille.width, y),
          i == sepRow ? actif : lignes);
    }

    // Numéros de case + cases exclues.
    final texte = TextPainter(textDirection: TextDirection.ltr);
    for (var row = 0; row < grille.rows; row++) {
      for (var col = 0; col < grille.cols; col++) {
        final index = row * grille.cols + col;
        final gauche = grille.colX[col] * taille.width;
        final haut = grille.rowY[row] * taille.height;
        if (exclues.contains(index)) {
          canvas.drawRect(
            Rect.fromLTWH(gauche, haut,
                grille.colX[col + 1] * taille.width - gauche,
                grille.rowY[row + 1] * taille.height - haut),
            Paint()..color = Colors.red.withOpacity(0.35),
          );
        }
        texte.text = TextSpan(
          text: '${index + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            backgroundColor: Color(0x99000000),
          ),
        );
        texte.layout();
        texte.paint(canvas, Offset(gauche + 4, haut + 2));
      }
    }
  }

  @override
  bool shouldRepaint(_GrillePainter old) =>
      old.grille != grille ||
      old.exclues != exclues ||
      old.sepCol != sepCol ||
      old.sepRow != sepRow;
}
