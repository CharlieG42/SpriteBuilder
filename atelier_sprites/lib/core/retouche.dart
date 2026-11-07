/// Retouche à la main d'une planche, façon logiciel de dessin : pinceau (taille,
/// opacité, dureté du bord), gomme, protection, restauration, dégradé, formes,
/// baguette magique et lasso, avec annuler/rétablir.
///
/// Le calque travaille sur les pixels bruts (RGBA) de la planche entière et sur
/// une carte de « forces » (un octet par pixel) que le détourage automatique
/// respecte : 0 = automatique, 1 = supprimé à la main, 2 = protégé (jamais retiré).
/// Peindre colore le pixel **et** le protège ; effacer le supprime (ou réduit son
/// alpha si le poids est partiel) ; restaurer rend la couleur d'origine et repasse
/// en automatique.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'detourage.dart';

const int forceAuto = 0;
const int forceSupprime = 1;
const int forceProtege = 2;

/// Ce que fait un outil sur les pixels qu'il touche.
enum ModeRetouche { peindre, effacer, proteger, restaurer }

/// Poids de la brosse à la distance relative [q] du centre du tampon (0 = centre,
/// 1 = bord) pour une dureté [durete] : 1 = bord net (poids 1 partout dans le
/// disque), 0 = fondu le plus doux (décroissance lissée vers le bord).
double poidsBrosse(double q, double durete) {
  if (q <= 0) return 1;
  if (q >= 1) return 0;
  final h = durete.clamp(0.0, 1.0);
  if (q <= h) return 1;
  final w = 1 - (q - h) / (1 - h);
  return w * w * (3 - 2 * w); // lissage smoothstep
}

/// Pixels bruts RGBA d'une planche, avec la carte de forces.
class OuvertureRetouche {
  final int largeur;
  final int hauteur;
  final Uint8List pixels;
  final Uint8List forces;

  /// Pixels de l'image d'origine (pour « restaurer »).
  final Uint8List origine;

  const OuvertureRetouche(this.largeur, this.hauteur, this.pixels, this.forces, this.origine);
}

/// Décode une image en RGBA brut, en mémoire alignée sur 4 octets.
({int largeur, int hauteur, Uint8List pixels}) decoderRgba(Uint8List octets) {
  final decodee = img.decodeImage(octets);
  if (decodee == null) throw const FormatException('Image illisible.');
  final rgba = decodee.convert(format: img.Format.uint8, numChannels: 4);
  final brut = rgba.getBytes(order: img.ChannelOrder.rgba);
  final pixels = Uint8List(rgba.width * rgba.height * 4)..setAll(0, brut);
  return (largeur: rgba.width, hauteur: rgba.height, pixels: pixels);
}

/// Prépare l'ouverture dans l'éditeur (prévu pour `compute()`).
///
/// [octetsOrigine] : image avant la première retouche (même taille), sinon
/// [octets] sert aussi d'origine. [forces] : carte existante, sinon vierge.
OuvertureRetouche ouvrirRetouche(DemandeOuverture d) {
  final courant = decoderRgba(d.octets);
  var origine = courant.pixels;
  if (d.octetsOrigine != null) {
    final o = decoderRgba(d.octetsOrigine!);
    if (o.largeur == courant.largeur && o.hauteur == courant.hauteur) origine = o.pixels;
  }
  if (identical(origine, courant.pixels)) origine = Uint8List.fromList(courant.pixels);
  final n = courant.largeur * courant.hauteur;
  final forces = d.forces != null && d.forces!.length == n ? Uint8List.fromList(d.forces!) : Uint8List(n);
  return OuvertureRetouche(courant.largeur, courant.hauteur, courant.pixels, forces, origine);
}

class DemandeOuverture {
  final Uint8List octets;
  final Uint8List? octetsOrigine;
  final Uint8List? forces;

  const DemandeOuverture(this.octets, {this.octetsOrigine, this.forces});
}

/// PNG des pixels retouchés (prévu pour `compute()`).
class DemandeEncodage {
  final int largeur;
  final int hauteur;
  final Uint8List pixels;

  const DemandeEncodage(this.largeur, this.hauteur, this.pixels);
}

Uint8List encoderRetouche(DemandeEncodage d) {
  final image = img.Image.fromBytes(
    width: d.largeur,
    height: d.hauteur,
    bytes: d.pixels.buffer,
    bytesOffset: d.pixels.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(image));
}

/// Contrôle : détourage automatique de la planche entière, retouches comprises
/// (prévu pour `compute()`). Retourne les pixels RGBA détourés.
class DemandeControle {
  final int largeur;
  final int hauteur;
  final Uint8List pixels;
  final Uint8List forces;
  final int tolerance;
  final double douceur;
  final bool decontaminer;
  final bool interieurs;
  final int aireMinInterieur;
  final int rognage;

  const DemandeControle({
    required this.largeur,
    required this.hauteur,
    required this.pixels,
    required this.forces,
    required this.tolerance,
    required this.douceur,
    required this.decontaminer,
    required this.interieurs,
    required this.aireMinInterieur,
    required this.rognage,
  });
}

Uint8List controleDetourage(DemandeControle d) {
  final copie = Uint8List.fromList(d.pixels);
  final image = img.Image.fromBytes(
    width: d.largeur,
    height: d.hauteur,
    bytes: copie.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  detourer(
    image,
    tolerance: d.tolerance,
    douceur: d.douceur,
    decontaminer: d.decontaminer,
    interieurs: d.interieurs,
    aireMinInterieur: d.aireMinInterieur,
    rognage: d.rognage,
    forces: d.forces,
  );
  final sortie = image.getBytes(order: img.ChannelOrder.rgba);
  return Uint8List.fromList(sortie);
}

enum FormatExport { png, jpg }

/// Export de l'image de travail en PNG ou JPG, sans passer par le découpage en
/// sprites (prévu pour `compute()`).
///
/// [detourer] : applique le détourage automatique (avec les retouches) ; sinon
/// seuls les pixels supprimés à la main deviennent transparents. Le JPG n'a pas
/// de transparence : l'image est posée sur la couleur de fond [fondR]/[fondG]/[fondB].
class DemandeExport {
  final int largeur;
  final int hauteur;
  final Uint8List pixels;
  final Uint8List forces;
  final bool detourer;
  final int tolerance;
  final double douceur;
  final bool decontaminer;
  final bool interieurs;
  final int aireMinInterieur;
  final int rognage;
  final FormatExport format;
  final int qualite;
  final int fondR;
  final int fondG;
  final int fondB;

  const DemandeExport({
    required this.largeur,
    required this.hauteur,
    required this.pixels,
    required this.forces,
    required this.format,
    this.detourer = false,
    this.tolerance = 45,
    this.douceur = 1.0,
    this.decontaminer = true,
    this.interieurs = true,
    this.aireMinInterieur = 24,
    this.rognage = 0,
    this.qualite = 92,
    this.fondR = 255,
    this.fondG = 255,
    this.fondB = 255,
  });
}

Uint8List exporterImage(DemandeExport d) {
  Uint8List rgba;
  if (d.detourer) {
    rgba = controleDetourage(DemandeControle(
      largeur: d.largeur,
      hauteur: d.hauteur,
      pixels: d.pixels,
      forces: d.forces,
      tolerance: d.tolerance,
      douceur: d.douceur,
      decontaminer: d.decontaminer,
      interieurs: d.interieurs,
      aireMinInterieur: d.aireMinInterieur,
      rognage: d.rognage,
    ));
  } else {
    rgba = Uint8List.fromList(d.pixels);
    for (var i = 0; i < d.forces.length; i++) {
      if (d.forces[i] == forceSupprime) {
        final o = i * 4;
        rgba[o] = 0;
        rgba[o + 1] = 0;
        rgba[o + 2] = 0;
        rgba[o + 3] = 0;
      }
    }
  }
  if (d.format == FormatExport.png) {
    return encoderRetouche(DemandeEncodage(d.largeur, d.hauteur, rgba));
  }
  // JPG : pas de transparence, l'image est posée sur le fond choisi.
  final n = d.largeur * d.hauteur;
  final rgb = Uint8List(n * 3);
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    final a = rgba[o + 3];
    final k = i * 3;
    if (a == 255) {
      rgb[k] = rgba[o];
      rgb[k + 1] = rgba[o + 1];
      rgb[k + 2] = rgba[o + 2];
    } else {
      rgb[k] = (rgba[o] * a + d.fondR * (255 - a)) ~/ 255;
      rgb[k + 1] = (rgba[o + 1] * a + d.fondG * (255 - a)) ~/ 255;
      rgb[k + 2] = (rgba[o + 2] * a + d.fondB * (255 - a)) ~/ 255;
    }
  }
  final image = img.Image.fromBytes(
    width: d.largeur,
    height: d.hauteur,
    bytes: rgb.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: d.qualite.clamp(1, 100).toInt()));
}

/// Image vierge : [fond] null = transparente, sinon couleur opaque (PNG).
Uint8List imageVierge(({int largeur, int hauteur, int? fond}) p) {
  final image = img.Image(width: p.largeur, height: p.hauteur, numChannels: 4);
  final f = p.fond;
  if (f != null) {
    img.fill(image, color: img.ColorRgba8((f >> 16) & 255, (f >> 8) & 255, f & 255, 255));
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Pixels modifiés par une action : valeurs avant, pour annuler / rétablir.
class _Journal {
  final List<int> idx = <int>[];
  final List<int> mots = <int>[];
  final List<int> forces = <int>[];
}

class CalqueRetouche {
  final int largeur;
  final int hauteur;

  /// RGBA courant (couleurs d'origine + pixels peints).
  final Uint8List pixels;

  /// 0 auto, 1 supprimé, 2 protégé.
  final Uint8List forces;

  /// RGBA de l'image d'origine.
  final Uint8List origine;

  /// RGBA à afficher : pixels supprimés transparents, protégés teintés si demandé.
  final Uint8List affichage;

  final Uint32List _mots;
  final Uint8List _vu;
  _Journal? _courant;
  final List<_Journal> _annuler = <_Journal>[];
  final List<_Journal> _retablir = <_Journal>[];
  bool _teinterProteges = false;
  int _version = 0;

  CalqueRetouche._(this.largeur, this.hauteur, this.pixels, this.forces, this.origine)
      : affichage = Uint8List(largeur * hauteur * 4),
        _mots = pixels.buffer.asUint32List(pixels.offsetInBytes, largeur * hauteur),
        _vu = Uint8List(largeur * hauteur) {
    for (var i = 0; i < largeur * hauteur; i++) {
      _majAffichage(i);
    }
  }

  /// [pixels] doit être aligné sur 4 octets (voir [decoderRgba]).
  factory CalqueRetouche.depuis(OuvertureRetouche o) =>
      CalqueRetouche._(o.largeur, o.hauteur, o.pixels, o.forces, o.origine);

  int get nbPixels => largeur * hauteur;

  bool get modifie => _annuler.isNotEmpty;

  /// Compteur incrémenté à chaque changement validé (pour savoir si l'on a exporté
  /// l'état courant).
  int get version => _version;
  bool get peutAnnuler => _annuler.isNotEmpty || (_courant?.idx.isNotEmpty ?? false);
  bool get peutRetablir => _retablir.isNotEmpty;

  bool get teinterProteges => _teinterProteges;

  set teinterProteges(bool v) {
    if (v == _teinterProteges) return;
    _teinterProteges = v;
    for (var i = 0; i < nbPixels; i++) {
      if (forces[i] == forceProtege) _majAffichage(i);
    }
  }

  void _majAffichage(int i) {
    final o = i * 4;
    if (forces[i] == forceSupprime) {
      affichage[o] = 0;
      affichage[o + 1] = 0;
      affichage[o + 2] = 0;
      affichage[o + 3] = 0;
      return;
    }
    var r = pixels[o];
    var g = pixels[o + 1];
    var b = pixels[o + 2];
    if (_teinterProteges && forces[i] == forceProtege) {
      r = (r * 0.6 + 40 * 0.4).round();
      g = (g * 0.6 + 200 * 0.4).round();
      b = (b * 0.6 + 90 * 0.4).round();
    }
    affichage[o] = r;
    affichage[o + 1] = g;
    affichage[o + 2] = b;
    affichage[o + 3] = pixels[o + 3];
  }

  // ------------------------------------------------------------------------------------------
  // Actions (annuler / rétablir)
  // ------------------------------------------------------------------------------------------

  /// Ouvre une action : tout ce qui est modifié jusqu'à [terminer] s'annule d'un bloc.
  void commencer() {
    if (_courant != null) terminer();
    _courant = _Journal();
  }

  /// Ferme l'action ; `true` si elle a modifié quelque chose.
  bool terminer() {
    final j = _courant;
    _courant = null;
    if (j == null) return false;
    for (final i in j.idx) {
      _vu[i] = 0;
    }
    if (j.idx.isEmpty) return false;
    _annuler.add(j);
    _retablir.clear();
    _version++;
    return true;
  }

  bool annuler() {
    terminer();
    if (_annuler.isEmpty) return false;
    final j = _annuler.removeLast();
    _echanger(j);
    _retablir.add(j);
    _version++;
    return true;
  }

  bool retablir() {
    terminer();
    if (_retablir.isEmpty) return false;
    final j = _retablir.removeLast();
    _echanger(j);
    _annuler.add(j);
    _version++;
    return true;
  }

  /// Échange l'état courant des pixels du journal avec celui qu'il garde.
  void _echanger(_Journal j) {
    for (var k = 0; k < j.idx.length; k++) {
      final i = j.idx[k];
      final mot = _mots[i];
      _mots[i] = j.mots[k];
      j.mots[k] = mot;
      final f = forces[i];
      forces[i] = j.forces[k];
      j.forces[k] = f;
      _majAffichage(i);
    }
  }

  void _noter(int i) {
    final j = _courant;
    if (j == null || _vu[i] == 1) return;
    _vu[i] = 1;
    j.idx.add(i);
    j.mots.add(_mots[i]);
    j.forces.add(forces[i]);
  }

  // ------------------------------------------------------------------------------------------
  // Pixels
  // ------------------------------------------------------------------------------------------

  /// Applique [mode] au pixel [i] avec le poids [poids] (0..1 = opacité × fondu du
  /// bord de la brosse) ; [r], [g], [b], [a] : couleur pour [ModeRetouche.peindre]
  /// (un alpha [a] < 255 peint en semi-transparent, 0 = fondu vers la transparence).
  void _appliquer(ModeRetouche mode, int i, int r, int g, int b, {int a = 255, double poids = 1.0}) {
    final o = i * 4;
    final k = poids.clamp(0.0, 1.0);
    switch (mode) {
      case ModeRetouche.peindre:
        if (k <= 0) return;
        // Mélange en « premultiplied lerp » : couleur et alpha fondent ensemble,
        // ce qui permet aussi de peindre vers la transparence (a = 0).
        final sa = (a.clamp(0, 255) / 255) * k;
        final da = pixels[o + 3] / 255;
        final fa = da * (1 - k) + sa;
        final nr = fa > 0 ? ((pixels[o] * da * (1 - k) + r * sa) / fa).round() : 0;
        final ng = fa > 0 ? ((pixels[o + 1] * da * (1 - k) + g * sa) / fa).round() : 0;
        final nb = fa > 0 ? ((pixels[o + 2] * da * (1 - k) + b * sa) / fa).round() : 0;
        final na = (fa * 255).round().clamp(0, 255);
        if (forces[i] == forceProtege && pixels[o] == nr && pixels[o + 1] == ng && pixels[o + 2] == nb && pixels[o + 3] == na) {
          return;
        }
        _noter(i);
        pixels[o] = nr;
        pixels[o + 1] = ng;
        pixels[o + 2] = nb;
        pixels[o + 3] = na;
        forces[i] = forceProtege;
      case ModeRetouche.effacer:
        if (k <= 0 || forces[i] == forceSupprime) return;
        final na = (pixels[o + 3] * (1 - k)).round();
        if (na == pixels[o + 3]) return;
        _noter(i);
        pixels[o + 3] = na;
        // Effacement partiel : alpha réduit mais pixel gardé (protégé du détourage) ;
        // à fond, le pixel est supprimé.
        forces[i] = na == 0 ? forceSupprime : forceProtege;
      case ModeRetouche.proteger:
        if (k < 0.5 || forces[i] == forceProtege) return;
        _noter(i);
        forces[i] = forceProtege;
      case ModeRetouche.restaurer:
        if (k < 0.5) return;
        final dejaOrigine = forces[i] == forceAuto &&
            pixels[o] == origine[o] &&
            pixels[o + 1] == origine[o + 1] &&
            pixels[o + 2] == origine[o + 2] &&
            pixels[o + 3] == origine[o + 3];
        if (dejaOrigine) return;
        _noter(i);
        pixels[o] = origine[o];
        pixels[o + 1] = origine[o + 1];
        pixels[o + 2] = origine[o + 2];
        pixels[o + 3] = origine[o + 3];
        forces[i] = forceAuto;
    }
    _majAffichage(i);
  }

  /// Couleur (r, g, b) du pixel d'origine de la planche courante, pour la pipette.
  ({int r, int g, int b})? couleurEn(int x, int y) {
    if (x < 0 || y < 0 || x >= largeur || y >= hauteur) return null;
    final o = (y * largeur + x) * 4;
    return (r: pixels[o], g: pixels[o + 1], b: pixels[o + 2]);
  }

  // ------------------------------------------------------------------------------------------
  // Outils
  // ------------------------------------------------------------------------------------------

  /// Tampon rond de [diametre] px centré en ([cx], [cy]) : [opacite] 0..1 et
  /// [durete] 0..1 (1 = bord net) donnent un pinceau doux ; [a] est l'alpha de la
  /// couleur peinte (255 par défaut, 0 = transparent).
  void tampon(
    ModeRetouche mode,
    int cx,
    int cy,
    int diametre, {
    int r = 0,
    int g = 0,
    int b = 0,
    int a = 255,
    double opacite = 1.0,
    double durete = 1.0,
  }) {
    _tampon(mode, cx, cy, diametre, r, g, b, a, opacite, durete);
  }

  void _tampon(ModeRetouche mode, int cx, int cy, int diametre, int r, int g, int b, int a, double opacite, double durete) {
    final rayon = math.max(0.5, diametre / 2);
    final lim = rayon.ceil();
    final r2 = rayon * rayon;
    for (var dy = -lim; dy <= lim; dy++) {
      final y = cy + dy;
      if (y < 0 || y >= hauteur) continue;
      for (var dx = -lim; dx <= lim; dx++) {
        final x = cx + dx;
        if (x < 0 || x >= largeur) continue;
        final d2 = dx * dx + dy * dy;
        if (d2 > r2) continue;
        final poids = poidsBrosse(math.sqrt(d2) / rayon, durete) * opacite;
        _appliquer(mode, y * largeur + x, r, g, b, a: a, poids: poids);
      }
    }
  }

  /// Trait continu du point (x0, y0) au point (x1, y1), au pas d'un pixel.
  void trait(
    ModeRetouche mode,
    int x0,
    int y0,
    int x1,
    int y1,
    int diametre, {
    int r = 0,
    int g = 0,
    int b = 0,
    int a = 255,
    double opacite = 1.0,
    double durete = 1.0,
  }) {
    final pas = math.max((x1 - x0).abs(), (y1 - y0).abs());
    if (pas == 0) {
      _tampon(mode, x0, y0, diametre, r, g, b, a, opacite, durete);
      return;
    }
    // Pour un gros pinceau, un tampon tous les quarts de diamètre suffit.
    final saut = math.max(1, diametre ~/ 4);
    for (var s = 0; s <= pas; s += saut) {
      final t = s / pas;
      _tampon(mode, (x0 + (x1 - x0) * t).round(), (y0 + (y1 - y0) * t).round(), diametre, r, g, b, a, opacite, durete);
    }
    _tampon(mode, x1, y1, diametre, r, g, b, a, opacite, durete);
  }

  /// Dégradé du point (x0, y0) au point (x1, y1) au tampon de [diametre] px : la
  /// couleur **et** l'alpha passent linéairement de [c0] à [c1] le long du trait
  /// (c1 transparent = fondu vers la transparence, façon outil dégradé de Krita).
  void traitDegrade(
    int x0,
    int y0,
    int x1,
    int y1,
    int diametre, {
    required ({int r, int g, int b, int a}) c0,
    required ({int r, int g, int b, int a}) c1,
    double opacite = 1.0,
    double durete = 1.0,
  }) {
    int lerp(int v0, int v1, double t) => (v0 + (v1 - v0) * t).round();
    final pas = math.max((x1 - x0).abs(), (y1 - y0).abs());
    if (pas == 0) {
      _tampon(ModeRetouche.peindre, x0, y0, diametre, c0.r, c0.g, c0.b, c0.a, opacite, durete);
      return;
    }
    final saut = math.max(1, diametre ~/ 4);
    for (var s = 0; s <= pas; s += saut) {
      final t = s / pas;
      _tampon(
        ModeRetouche.peindre,
        (x0 + (x1 - x0) * t).round(),
        (y0 + (y1 - y0) * t).round(),
        diametre,
        lerp(c0.r, c1.r, t),
        lerp(c0.g, c1.g, t),
        lerp(c0.b, c1.b, t),
        lerp(c0.a, c1.a, t),
        opacite,
        durete,
      );
    }
    _tampon(ModeRetouche.peindre, x1, y1, diametre, c1.r, c1.g, c1.b, c1.a, opacite, durete);
  }

  /// Rectangle de coins opposés (x0, y0) et (x1, y1), inclus : plein, ou contour de
  /// [epaisseur] px vers l'intérieur. Retourne le nombre de pixels touchés.
  int rectangle(
    ModeRetouche mode,
    int x0,
    int y0,
    int x1,
    int y1, {
    required int epaisseur,
    required bool rempli,
    int r = 0,
    int g = 0,
    int b = 0,
    double opacite = 1.0,
  }) {
    final ax = math.min(x0, x1);
    final bx = math.max(x0, x1);
    final ay = math.min(y0, y1);
    final by = math.max(y0, y1);
    var n = 0;
    for (var y = math.max(0, ay); y <= math.min(hauteur - 1, by); y++) {
      for (var x = math.max(0, ax); x <= math.min(largeur - 1, bx); x++) {
        if (!rempli && x - ax >= epaisseur && bx - x >= epaisseur && y - ay >= epaisseur && by - y >= epaisseur) {
          continue;
        }
        _appliquer(mode, y * largeur + x, r, g, b, poids: opacite);
        n++;
      }
    }
    return n;
  }

  /// Ellipse inscrite dans le rectangle de coins (x0, y0) et (x1, y1), inclus :
  /// pleine, ou contour de [epaisseur] px vers l'intérieur.
  int ellipse(
    ModeRetouche mode,
    int x0,
    int y0,
    int x1,
    int y1, {
    required int epaisseur,
    required bool rempli,
    int r = 0,
    int g = 0,
    int b = 0,
    double opacite = 1.0,
  }) {
    final ax = math.min(x0, x1);
    final bx = math.max(x0, x1);
    final ay = math.min(y0, y1);
    final by = math.max(y0, y1);
    final cx = (ax + bx + 1) / 2;
    final cy = (ay + by + 1) / 2;
    final rx = (bx - ax + 1) / 2;
    final ry = (by - ay + 1) / 2;
    final irx = rx - epaisseur;
    final iry = ry - epaisseur;
    final creuse = !rempli && irx > 0 && iry > 0;
    var n = 0;
    for (var y = math.max(0, ay); y <= math.min(hauteur - 1, by); y++) {
      final dy = y + 0.5 - cy;
      for (var x = math.max(0, ax); x <= math.min(largeur - 1, bx); x++) {
        final dx = x + 0.5 - cx;
        if (dx * dx / (rx * rx) + dy * dy / (ry * ry) > 1) continue;
        if (creuse && dx * dx / (irx * irx) + dy * dy / (iry * iry) < 1) continue;
        _appliquer(mode, y * largeur + x, r, g, b, poids: opacite);
        n++;
      }
    }
    return n;
  }

  /// Baguette magique : applique [mode] aux pixels de couleur proche de celle du
  /// pixel (x, y) — voisins de proche en proche si [contigu], sinon toute la
  /// planche. Retourne le nombre de pixels sélectionnés.
  int baguette(
    ModeRetouche mode,
    int x,
    int y, {
    required int tolerance,
    required bool contigu,
    int r = 0,
    int g = 0,
    int b = 0,
  }) {
    if (x < 0 || y < 0 || x >= largeur || y >= hauteur) return 0;
    final graine = (y * largeur + x) * 4;
    final gr = pixels[graine];
    final gg = pixels[graine + 1];
    final gb = pixels[graine + 2];
    final t2 = tolerance * tolerance * 3;

    bool proche(int i) {
      final o = i * 4;
      final dr = pixels[o] - gr;
      final dg = pixels[o + 1] - gg;
      final db = pixels[o + 2] - gb;
      return dr * dr + dg * dg + db * db <= t2;
    }

    var n = 0;
    if (!contigu) {
      for (var i = 0; i < nbPixels; i++) {
        if (proche(i)) {
          _appliquer(mode, i, r, g, b);
          n++;
        }
      }
      return n;
    }

    final visite = Uint8List(nbPixels);
    final file = Int32List(nbPixels);
    var tete = 0;
    var queue = 0;
    final depart = y * largeur + x;
    visite[depart] = 1;
    file[queue++] = depart;
    while (tete < queue) {
      final i = file[tete++];
      _appliquer(mode, i, r, g, b);
      n++;
      final px = i % largeur;
      final py = i ~/ largeur;
      void voisin(int j) {
        if (visite[j] == 0 && proche(j)) {
          visite[j] = 1;
          file[queue++] = j;
        }
      }

      if (px > 0) voisin(i - 1);
      if (px < largeur - 1) voisin(i + 1);
      if (py > 0) voisin(i - largeur);
      if (py < hauteur - 1) voisin(i + largeur);
    }
    return n;
  }

  /// Lasso : applique [mode] à l'intérieur (ou à l'extérieur si [interieur] est
  /// faux) du polygone fermé [points] (suite x, y, x, y… en pixels de la planche).
  int polygone(ModeRetouche mode, List<double> points, {bool interieur = true, int r = 0, int g = 0, int b = 0}) {
    final nb = points.length ~/ 2;
    if (nb < 3) return 0;
    final dedans = Uint8List(nbPixels);
    var minY = hauteur;
    var maxY = -1;
    for (var k = 0; k < nb; k++) {
      final y = points[2 * k + 1];
      minY = math.min(minY, y.floor());
      maxY = math.max(maxY, y.ceil());
    }
    minY = math.max(0, minY);
    maxY = math.min(hauteur - 1, maxY);

    for (var y = minY; y <= maxY; y++) {
      final yc = y + 0.5;
      final xs = <double>[];
      for (var k = 0; k < nb; k++) {
        final x1 = points[2 * k];
        final y1 = points[2 * k + 1];
        final x2 = points[2 * ((k + 1) % nb)];
        final y2 = points[2 * ((k + 1) % nb) + 1];
        if ((y1 <= yc && y2 > yc) || (y2 <= yc && y1 > yc)) {
          xs.add(x1 + (yc - y1) * (x2 - x1) / (y2 - y1));
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        final debut = math.max(0, (xs[k] - 0.5).ceil());
        final fin = math.min(largeur - 1, (xs[k + 1] - 0.5).ceil() - 1);
        for (var x = debut; x <= fin; x++) {
          dedans[y * largeur + x] = 1;
        }
      }
    }

    var n = 0;
    final cible = interieur ? 1 : 0;
    for (var i = 0; i < nbPixels; i++) {
      if (dedans[i] == cible) {
        _appliquer(mode, i, r, g, b);
        n++;
      }
    }
    return n;
  }

  /// Rend toute la planche à l'état d'origine (une action annulable).
  void toutRestaurer() {
    commencer();
    for (var i = 0; i < nbPixels; i++) {
      _appliquer(ModeRetouche.restaurer, i, 0, 0, 0);
    }
    terminer();
  }

  /// Pixels forcés à la main (supprimés ou protégés) : la planche est-elle retouchée ?
  bool get aDesForces {
    for (var i = 0; i < nbPixels; i++) {
      if (forces[i] != forceAuto) return true;
    }
    return false;
  }
}
