/// Conversions couleur RVB ↔ TSL (teinte, saturation, luminosité) et palette de
/// base de l'atelier — le sélecteur de couleur de l'éditeur, façon Krita.
library;

import 'dart:math' as math;

/// [h] en degrés (0..360, ramenée dans l'intervalle), [s] et [l] en 0..1.
({int r, int g, int b}) tslVersRgb(double h, double s, double l) {
  h = ((h % 360) + 360) % 360;
  s = s.clamp(0.0, 1.0);
  l = l.clamp(0.0, 1.0);
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = l - c / 2;
  double r, g, b;
  if (h < 60) {
    r = c;
    g = x;
    b = 0;
  } else if (h < 120) {
    r = x;
    g = c;
    b = 0;
  } else if (h < 180) {
    r = 0;
    g = c;
    b = x;
  } else if (h < 240) {
    r = 0;
    g = x;
    b = c;
  } else if (h < 300) {
    r = x;
    g = 0;
    b = c;
  } else {
    r = c;
    g = 0;
    b = x;
  }
  return (
    r: ((r + m) * 255).round().clamp(0, 255),
    g: ((g + m) * 255).round().clamp(0, 255),
    b: ((b + m) * 255).round().clamp(0, 255),
  );
}

/// Teinte en degrés (0..360), saturation et luminosité en 0..1.
({double h, double s, double l}) rgbVersTsl(int r, int g, int b) {
  final rn = r / 255;
  final gn = g / 255;
  final bn = b / 255;
  final max = math.max(rn, math.max(gn, bn));
  final min = math.min(rn, math.min(gn, bn));
  final l = (max + min) / 2;
  if (max == min) return (h: 0, s: 0, l: l);
  final d = max - min;
  final s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  double h;
  if (max == rn) {
    h = (gn - bn) / d + (gn < bn ? 6 : 0);
  } else if (max == gn) {
    h = (bn - rn) / d + 2;
  } else {
    h = (rn - gn) / d + 4;
  }
  return (h: h * 60, s: s, l: l);
}

/// Palette de base (ARGB) affichée dans l'éditeur, avec les couleurs récentes
/// en tête de liste.
const List<int> paletteBase = <int>[
  0xFFFFFFFF,
  0xFF000000,
  0xFF9E9E9E,
  0xFFD32F2F,
  0xFFF57C00,
  0xFFFBC02D,
  0xFF388E3C,
  0xFF1976D2,
  0xFF7B1FA2,
  0xFF795548,
  0xFFE91E63,
  0xFF00BCD4,
  0xFF8BC34A,
  0xFFFFEB3B,
  0xFF3F51B5,
  0xFF607D8B,
];
