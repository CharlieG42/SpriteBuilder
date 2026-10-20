/// Encodage d'une animation en GIF (à lancer dans un isolate via `compute`).
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Demande d'encodage : images PNG dans l'ordre de lecture.
class DemandeGif {
  final List<Uint8List> images;

  /// Durée d'une image en millisecondes.
  final int dureeMs;

  /// Retourne horizontalement (directions vers la gauche dans le jeu).
  final bool miroir;

  /// Couleur de fond 0xRRGGBB (le GIF gère mal la transparence partielle).
  final int fond;

  /// Côté maximal du GIF (px).
  final int cote;

  const DemandeGif({
    required this.images,
    required this.dureeMs,
    this.miroir = false,
    this.fond = 0xFFFFFF,
    this.cote = 256,
  });
}

/// Encode [d] en GIF animé qui boucle à l'infini.
Uint8List encoderGif(DemandeGif d) {
  if (d.images.isEmpty) throw ArgumentError('Aucune image à encoder.');
  final centiemes = (d.dureeMs / 10).round().clamp(2, 1000);
  final encodeur = img.GifEncoder(delay: centiemes, repeat: 0);
  final couleur = img.ColorRgb8((d.fond >> 16) & 0xFF, (d.fond >> 8) & 0xFF, d.fond & 0xFF);
  for (final png in d.images) {
    var sprite = img.decodeImage(png);
    if (sprite == null) continue;
    if (sprite.width > d.cote || sprite.height > d.cote) {
      final ratio = d.cote / (sprite.width > sprite.height ? sprite.width : sprite.height);
      sprite = img.copyResize(
        sprite,
        width: (sprite.width * ratio).round().clamp(1, d.cote),
        height: (sprite.height * ratio).round().clamp(1, d.cote),
        interpolation: img.Interpolation.linear,
      );
    }
    if (d.miroir) sprite = img.flipHorizontal(sprite);
    final cadre = img.Image(width: sprite.width, height: sprite.height, numChannels: 3);
    img.fill(cadre, color: couleur);
    img.compositeImage(cadre, sprite);
    encodeur.addFrame(cadre, duration: centiemes);
  }
  final octets = encodeur.finish();
  if (octets == null) throw StateError('Échec de l\'encodage du GIF.');
  return octets;
}
