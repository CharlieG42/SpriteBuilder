/// Fond en damier pour visualiser la transparence d'un sprite.
library;

import 'package:flutter/material.dart';

class Damier extends StatelessWidget {
  /// Côté d'une case du damier (px logiques).
  final double taille;

  const Damier({super.key, this.taille = 12});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _DamierPainter(taille));
}

class _DamierPainter extends CustomPainter {
  final double taille;

  _DamierPainter(this.taille);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF2F2F2));
    final fonce = Paint()..color = const Color(0xFFD9D9D9);
    var ligne = 0;
    for (var y = 0.0; y < s.height; y += taille, ligne++) {
      for (var x = (ligne.isOdd ? taille : 0.0); x < s.width; x += taille * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, taille, taille), fonce);
      }
    }
  }

  @override
  bool shouldRepaint(_DamierPainter old) => old.taille != taille;
}
