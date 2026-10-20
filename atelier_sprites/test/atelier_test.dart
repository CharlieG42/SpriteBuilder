import 'package:atelier_sprites/core/animations.dart';
import 'package:atelier_sprites/core/decoupe.dart';
import 'package:atelier_sprites/core/detourage.dart';
import 'package:atelier_sprites/core/gif.dart';
import 'package:atelier_sprites/core/traitement.dart';
import 'package:atelier_sprites/data/catalog.dart';
import 'package:atelier_sprites/export/atelier_export.dart';
import 'package:atelier_sprites/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('noms de fichiers (EntityView.gd V34)', () {
    test('héros/boss — repos et sorts, face', () {
      final pl = planchesGrand[0];
      expect(nomFichierPour(id: 'assassin', planche: pl, suffix: ''), 'assassin.png');
      expect(nomFichierPour(id: 'assassin', planche: pl, suffix: '_idle_2'), 'assassin_idle_2.png');
      expect(nomFichierPour(id: 'assassin', planche: pl, suffix: '_cast_3'), 'assassin_cast_3.png');
    });

    test('héros/boss — attaques, dos', () {
      final pl = planchesGrand[3];
      expect(nomFichierPour(id: 'assassin', planche: pl, suffix: '_attack'), 'assassin_back_attack.png');
      expect(nomFichierPour(id: 'assassin', planche: pl, suffix: '_attack_8'), 'assassin_back_attack_8.png');
    });

    test('ennemis/familiers — dos', () {
      final pl = planchesPetit[1];
      expect(nomFichierPour(id: 'liche', planche: pl, suffix: ''), 'liche_back.png');
      expect(nomFichierPour(id: 'liche', planche: pl, suffix: '_cast'), 'liche_back_cast.png');
    });

    test('objets — une seule pose', () {
      expect(nomFichierPour(id: 'balise', planche: plancheObjets, suffix: ''), 'balise.png');
    });
  });

  group('catalogue', () {
    test('complétude : 10 nations × 6 + 12 familiers + 10 mécanismes', () {
      expect(catalogueComplet().length, 82);
    });

    test('planches : 4 pour un héros, 2 pour un ennemi, 1 pour un objet', () {
      final heros = catalogueComplet().firstWhere((p) => p.id == 'tank');
      expect(planchesPour(heros).length, 4);
      final ennemi = catalogueComplet().firstWhere((p) => p.id == 'liche');
      expect(planchesPour(ennemi).length, 2);
      final objet = catalogueComplet().firstWhere((p) => p.id == 'bombe');
      expect(planchesPour(objet).length, 1);
      expect(planchesPour(objet).first.type, TypePlanche.objets);
    });

    test('présélection complète', () {
      final presel = preselDepuisNomFichier('assassin_dos_attaques.png');
      expect(presel.perso?.id, 'assassin');
      expect(presel.planche?.vue, Vue.dos);
      expect(presel.planche?.type, TypePlanche.grandAttaques);

      final preselFace = preselDepuisNomFichier('liche_back.png');
      expect(preselFace.perso?.id, 'liche');
      expect(preselFace.planche?.vue, Vue.dos);
      expect(preselFace.planche?.type, TypePlanche.petitTout);

      final preselObjet = preselDepuisNomFichier('tourelle.png');
      expect(preselObjet.planche?.type, TypePlanche.objets);
    });
  });

  group('chemins d\'export', () {
    final heros = catalogueComplet().firstWhere((p) => p.id == 'assassin');

    test('repos de face : miroir vers nations/heros', () {
      final chemins = cheminsPour(perso: heros, planche: planchesGrand[0], nomFichier: 'assassin.png');
      expect(chemins, contains('prototype/zimut/assets/sprites/nations/heros/assassin.png'));
      expect(chemins.first, 'prototype/zimut/assets/sprites/players/assassin.png');
    });

    test('autre pose : miroir vers nations/heros/poses', () {
      final chemins = cheminsPour(perso: heros, planche: planchesGrand[0], nomFichier: 'assassin_walk.png');
      expect(chemins, contains('prototype/zimut/assets/sprites/nations/heros/poses/assassin_walk.png'));
    });

    test('ennemis : un seul chemin', () {
      final ennemi = catalogueComplet().firstWhere((p) => p.id == 'liche');
      final chemins = cheminsPour(perso: ennemi, planche: planchesPetit[0], nomFichier: 'liche.png');
      expect(chemins.length, 1);
      expect(chemins.single, 'prototype/zimut/assets/sprites/nations/ennemis/ombres/liche.png');
    });
  });

  group('détourage', () {
    test('fond blanc supprimé, sprite conservé, zones enfermées gardées', () {
      final im = img.Image(width: 32, height: 32, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(im, x1: 8, y1: 8, x2: 23, y2: 23, color: img.ColorRgb8(180, 30, 30));
      // zone claire enfermée dans le sprite : doit être conservée
      img.fillRect(im, x1: 14, y1: 14, x2: 17, y2: 17, color: img.ColorRgb8(250, 250, 250));

      final stats = detourer(im, tolerance: 30, douceur: 1.0, decontaminer: true);

      expect(im.getPixel(0, 0).a.toInt(), 0, reason: 'coin = fond');
      expect(im.getPixel(15, 15).a.toInt(), 255, reason: 'zone claire enfermée conservée');
      expect(im.getPixel(10, 10).a.toInt(), 255, reason: 'corps du sprite conservé');
      expect(stats.pourcentageFond, greaterThan(70));
    });

    test('deux sprites séparés : le fond entre eux est retiré', () {
      final im = img.Image(width: 64, height: 32, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(im, x1: 4, y1: 8, x2: 20, y2: 24, color: img.ColorRgb8(30, 30, 200));
      img.fillRect(im, x1: 40, y1: 8, x2: 56, y2: 24, color: img.ColorRgb8(30, 30, 200));

      detourer(im, tolerance: 30, douceur: 1.0, decontaminer: true);

      expect(im.getPixel(32, 16).a.toInt(), 0, reason: 'gouttière entre les deux sprites');
      expect(im.getPixel(10, 16).a.toInt(), 255);
      expect(im.getPixel(48, 16).a.toInt(), 255);
    });

    test('poche de fond entre les membres retirée selon l’aire minimale', () {
      final im = img.Image(width: 48, height: 48, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      // torse/bras : deux bandes verticales avec une poche de fond enfermée
      img.fillRect(im, x1: 10, y1: 6, x2: 16, y2: 42, color: img.ColorRgb8(30, 30, 200));
      img.fillRect(im, x1: 30, y1: 6, x2: 36, y2: 42, color: img.ColorRgb8(30, 30, 200));
      img.fillRect(im, x1: 8, y1: 4, x2: 38, y2: 6, color: img.ColorRgb8(30, 30, 200));
      img.fillRect(im, x1: 8, y1: 42, x2: 38, y2: 44, color: img.ColorRgb8(30, 30, 200));

      detourer(im, tolerance: 30, douceur: 1.0, decontaminer: true);

      expect(im.getPixel(23, 23).a.toInt(), 0, reason: 'poche entre les membres retirée');
      expect(im.getPixel(13, 23).a.toInt(), 255, reason: 'bras conservé');
    });

    test('petite poche sous l’aire minimale conservée, intérieurs désactivables', () {
      final im = img.Image(width: 32, height: 32, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(im, x1: 8, y1: 8, x2: 23, y2: 23, color: img.ColorRgb8(180, 30, 30));
      img.fillRect(im, x1: 15, y1: 15, x2: 16, y2: 16, color: img.ColorRgb8(255, 255, 255));

      detourer(im, tolerance: 30, douceur: 1.0, decontaminer: true);
      expect(im.getPixel(15, 15).a.toInt(), 255, reason: 'poche < aire minimale conservée');

      detourer(im, tolerance: 30, douceur: 1.0, decontaminer: true, interieurs: false);
      expect(im.getPixel(15, 15).a.toInt(), 255, reason: 'intérieurs désactivés : poche conservée');
    });
  });

  group('découpe', () {
    test('extraction des cases d\'une grille 4×2', () {
      final im = img.Image(width: 40, height: 20, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      final grille = Grille.uniforme(4, 2);
      final c00 = extraireCase(im, grille, 0, 0);
      final c31 = extraireCase(im, grille, 3, 1);
      expect(c00.width, 10);
      expect(c00.height, 10);
      expect(c31.width, 10);
      expect(c31.height, 10);
    });

    test('détection automatique d\'une grille 4×2', () {
      final im = img.Image(width: 40, height: 20, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      // quatre colonnes de contenu séparées par des gouttières
      for (var k = 0; k < 4; k++) {
        img.fillRect(im, x1: k * 10 + 1, y1: 1, x2: k * 10 + 8, y2: 18, color: img.ColorRgb8(200, 40, 40));
      }
      final g = detecterGrille(im, tolerance: 30);
      expect(g.cols, 4);
      expect(g.rows, 1);
    });

    test('normalisation en carré 512', () {
      final im = img.Image(width: 100, height: 60, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(200, 40, 40));
      final carre = normaliserCarre(im, 512);
      expect(carre.width, 512);
      expect(carre.height, 512);
      // le sprite ne doit pas être agrandi
      final petit = img.Image(width: 100, height: 60, numChannels: 4);
      img.fill(petit, color: img.ColorRgb8(10, 10, 10));
      final carrePetit = normaliserCarre(petit, 512);
      expect(carrePetit.width, 512);
      expect(carrePetit.height, 512);
    });

    test('ancrage au sol : le bas du contenu tombe sur la ligne de sol', () {
      // Deux poses : l'une « flotte » haut dans sa case, l'autre est en bas.
      img.Image pose(int haut) {
        final c = img.Image(width: 100, height: 100, numChannels: 4);
        img.fillRect(c, x1: 40, y1: haut, x2: 59, y2: haut + 29, color: img.ColorRgba8(200, 40, 40, 255));
        return c;
      }

      int basContenu(img.Image c) => boiteContenu(c)!.y1;

      final a = normaliserCarre(pose(10), 200, ancrage: Ancrage.sol, margeSol: 0.1);
      final b = normaliserCarre(pose(60), 200, ancrage: Ancrage.sol, margeSol: 0.1);
      expect(basContenu(a), 180);
      expect(basContenu(b), 180);
      // centré : les deux poses restent décalées
      final ac = normaliserCarre(pose(10), 200);
      final bc = normaliserCarre(pose(60), 200);
      expect(basContenu(ac), isNot(basContenu(bc)));
    });

    test('boîte de contenu vide et échelle commune', () {
      final vide = img.Image(width: 10, height: 10, numChannels: 4);
      expect(boiteContenu(vide), isNull);

      final planche = img.Image(width: 2048, height: 1024, numChannels: 4);
      expect(ratioCommun(planche, Grille.uniforme(4, 2), [0, 1, 2], 512), 1.0);
      expect(ratioCommun(planche, Grille.uniforme(2, 1), [0, 1], 512), closeTo(0.5, 1e-9));
    });

    test('traitement complet avec ancrage : cases de 512 réduites pour l\'aperçu', () {
      final planche = img.Image(width: 400, height: 200, numChannels: 4);
      img.fill(planche, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(planche, x1: 60, y1: 20, x2: 140, y2: 100, color: img.ColorRgb8(30, 30, 200));
      img.fillRect(planche, x1: 260, y1: 90, x2: 340, y2: 170, color: img.ColorRgb8(30, 30, 200));
      final options = OptionsTraitement()..ancrageSol = true;
      final demande = construireDemande(
        img.encodePng(planche),
        Grille.uniforme(2, 1),
        options,
        const [0, 1],
        tailleVignette: 128,
      );
      final res = traiterCases(demande);
      final a = img.decodePng(res.vignettes['0']!)!;
      final b = img.decodePng(res.vignettes['1']!)!;
      expect(a.width, 128);
      expect(b.width, 128);
      expect((boiteContenu(a)!.y1 - boiteContenu(b)!.y1).abs(), lessThanOrEqualTo(1));
    });
  });

  group('animations', () {
    test('familles déduites des suffixes', () {
      expect(familleDuSuffixe(''), FamilleAnim.repos);
      expect(familleDuSuffixe('_idle_3'), FamilleAnim.repos);
      expect(familleDuSuffixe('_walk_2'), FamilleAnim.marche);
      expect(familleDuSuffixe('_cast'), FamilleAnim.sort);
      expect(familleDuSuffixe('_attack_8'), FamilleAnim.attaque);
    });

    test('planche héros repos : repos, marche, sort + toutes les cases', () {
      final pl = planchesGrand[0];
      final anims = animationsPour({
        for (var i = 0; i < pl.suffixes.length; i++) i: pl.suffixes[i],
      });
      expect(anims.map((a) => a.libelle).toList(), ['Repos', 'Marche', 'Sort', 'Toutes les cases']);
      expect(anims[0].cases, [0, 1, 2]);
      expect(anims[0].allerRetour, isTrue);
      expect(anims[1].cases, [3, 4]);
      expect(anims[2].cases, [5, 6, 7]);
      expect(anims.last.cases.length, 8);
    });

    test('objets : seulement « toutes les cases »', () {
      final anims = animationsPour({0: null, 1: null});
      expect(anims.length, 1);
      expect(anims.single.cases, [0, 1]);
    });

    test('séquence aller-retour sans doubler les extrémités', () {
      expect(sequenceLecture([1, 2, 3, 4], allerRetour: true), [1, 2, 3, 4, 3, 2]);
      expect(sequenceLecture([1, 2], allerRetour: true), [1, 2]);
      expect(sequenceLecture([1, 2, 3], allerRetour: false), [1, 2, 3]);
    });

    test('encodage GIF', () {
      final c = img.Image(width: 64, height: 64, numChannels: 4);
      img.fillRect(c, x1: 10, y1: 10, x2: 50, y2: 50, color: img.ColorRgba8(200, 40, 40, 255));
      final png = img.encodePng(c);
      final gif = encoderGif(DemandeGif(images: [png, png, png], dureeMs: 125, miroir: true));
      expect(String.fromCharCodes(gif.sublist(0, 3)), 'GIF');
      final relu = img.decodeGif(gif)!;
      expect(relu.numFrames, 3);
    });
  });
}
