import 'dart:typed_data';

import 'package:atelier_sprites/core/animations.dart';
import 'package:atelier_sprites/core/couleur.dart';
import 'package:atelier_sprites/core/decoupe.dart';
import 'package:atelier_sprites/core/detourage.dart';
import 'package:atelier_sprites/core/doublons.dart';
import 'package:atelier_sprites/core/gif.dart';
import 'package:atelier_sprites/core/intensite.dart';
import 'package:atelier_sprites/core/reglages_anim.dart';
import 'package:atelier_sprites/core/retouche.dart';
import 'package:atelier_sprites/core/traitement.dart';
import 'package:atelier_sprites/data/catalog.dart';
import 'package:atelier_sprites/export/atelier_export.dart';
import 'package:atelier_sprites/models.dart';
import 'package:atelier_sprites/projet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('noms de fichiers (EntityView.gd V34, planches V36)', () {
    test('fiche de référence : repos de face et de dos', () {
      final pl = planchesGrand[0];
      expect(pl.type, TypePlanche.reference);
      expect(nomFichierPour(id: 'assassin', planche: pl, suffix: pl.suffixes[0]), 'assassin.png');
      expect(nomFichierPour(id: 'assassin', planche: pl, suffix: pl.suffixes[1]), 'assassin_back.png');
    });

    test('héros/boss — face 3 : attaques 5-6 et sorts', () {
      final pl = planchesGrand[3];
      expect(pl.cle, 'face_3');
      expect(nomFichierPour(id: 'assassin', planche: pl, suffix: pl.suffixes[1]), 'assassin_attack_6.png');
      expect(nomFichierPour(id: 'assassin', planche: pl, suffix: pl.suffixes[3]), 'assassin_cast_3.png');
    });

    test('héros/boss — dos 2', () {
      final pl = planchesGrand[5];
      expect(pl.vue, Vue.dos);
      expect(nomFichierPour(id: 'assassin', planche: pl, suffix: pl.suffixes[0]), 'assassin_back_attack_2.png');
      expect(nomFichierPour(id: 'assassin', planche: pl, suffix: pl.suffixes[3]), 'assassin_back_idle_2.png');
    });

    test('ennemis/familiers — dos', () {
      final pl = planchesPetit[2];
      expect(nomFichierPour(id: 'liche', planche: pl, suffix: '_walk'), 'liche_back_walk.png');
      expect(nomFichierPour(id: 'liche', planche: pl, suffix: '_cast'), 'liche_back_cast.png');
    });

    test('objets — une seule pose', () {
      expect(nomFichierPour(id: 'balise', planche: plancheObjets, suffix: ''), 'balise.png');
    });

    test('aucune pose en double dans les planches d\'un personnage', () {
      for (final planches in [planchesGrand, planchesPetit]) {
        final noms = <String>{};
        for (final pl in planches) {
          expect(pl.suffixes.length, pl.type == TypePlanche.reference ? 2 : 4);
          for (final s in pl.suffixes) {
            expect(noms.add(nomFichierPour(id: 'x', planche: pl, suffix: s)), isTrue);
          }
        }
      }
    });
  });

  group('catalogue', () {
    test('complétude : 10 nations × 6 + 12 familiers + 10 mécanismes', () {
      expect(catalogueComplet().length, 82);
    });

    test('planches : 6 pour un héros, 3 pour un ennemi, 1 pour un objet', () {
      final heros = catalogueComplet().firstWhere((p) => p.id == 'tank');
      expect(planchesPour(heros).length, 6);
      final ennemi = catalogueComplet().firstWhere((p) => p.id == 'liche');
      expect(planchesPour(ennemi).length, 3);
      final objet = catalogueComplet().firstWhere((p) => p.id == 'bombe');
      expect(planchesPour(objet).length, 1);
      expect(planchesPour(objet).first.type, TypePlanche.objets);
    });

    test('présélection depuis le nom du fichier', () {
      expect(preselDepuisNomFichier('assassin_dos_2.png').planche?.cle, 'dos_2');
      expect(preselDepuisNomFichier('assassin_face3.png').planche?.cle, 'face_3');
      expect(preselDepuisNomFichier('assassin_attaques.png').planche?.cle, 'face_2');
      expect(preselDepuisNomFichier('assassin_ref.png').planche?.type, TypePlanche.reference);
      expect(preselDepuisNomFichier('assassin.png').planche?.type, TypePlanche.reference);
      final liche = preselDepuisNomFichier('liche_back.png');
      expect(liche.perso?.id, 'liche');
      expect(liche.planche?.cle, 'dos_1');
      expect(preselDepuisNomFichier('tourelle.png').planche?.type, TypePlanche.objets);
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

  group('détourage doux', () {
    test('une zone claire enfermée (cheveux blancs) n\'est plus prise pour du fond', () {
      final im = img.Image(width: 40, height: 40, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(im, x1: 5, y1: 5, x2: 34, y2: 34, color: img.ColorRgb8(60, 90, 160));
      // Zone claire (≈ 12 de l'écart au blanc par canal... 226 vs 255 : écart 29) de 6×6 px.
      img.fillRect(im, x1: 15, y1: 15, x2: 20, y2: 20, color: img.ColorRgb8(226, 226, 226));
      final doux = im.clone();
      detourer(doux, tolerance: 40, douceur: 1.0, decontaminer: false, aireMinInterieur: 4);
      expect(doux.getPixel(17, 17).a.toInt(), 255, reason: 'zone claire conservée');
      // Un vrai fond enfermé part toujours.
      img.fillRect(im, x1: 25, y1: 25, x2: 30, y2: 30, color: img.ColorRgb8(255, 255, 255));
      detourer(im, tolerance: 40, douceur: 1.0, decontaminer: false, aireMinInterieur: 4);
      expect(im.getPixel(27, 27).a.toInt(), 0, reason: 'fond enfermé retiré');
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

    test('planche héros face 1 : repos, marche, sort + toutes les cases', () {
      final pl = planchesGrand[1];
      final anims = animationsPour({
        for (var i = 0; i < pl.suffixes.length; i++) i: pl.suffixes[i],
      });
      expect(anims.map((a) => a.libelle).toList(), ['Repos', 'Marche', 'Sort', 'Toutes les cases']);
      expect(anims[0].cases, [0]);
      expect(anims[1].cases, [1, 2]);
      expect(anims[2].cases, [3]);
      expect(anims.last.cases.length, 4);
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

  group('mouvement procédural (EntityView.gd V35)', () {
    test('défauts : JSON vide, aucune personnalisation', () {
      final r = ReglagesAnim();
      expect(r.estDefaut, isTrue);
      expect(r.versJson(), '{}');
      expect(r['rebond_marche'], 9);
    });

    test('JSON : seules les clés modifiées, bornes appliquées à la relecture', () {
      final r = ReglagesAnim().avec('rebond_marche', 4).avec('elan_attaque', 40);
      expect(r.estDefaut, isFalse);
      expect(r.versJson(), contains('"rebond_marche": 4'));
      expect(r.versJson(), isNot(contains('respiration')));
      final relu = ReglagesAnim.depuisJson({'respiration': 5, 'inconnu': 1, 'saut_sort': 20});
      expect(relu['respiration'], 0.08);
      expect(relu['saut_sort'], 20);
    });

    test('pose : marche qui saute, fente vers l\'avant, repos immobile horizontalement', () {
      final r = ReglagesAnim();
      // marche : à t = π/26, |sin(13 t)| = 1 → saut maximal
      final marche = poseProcedurale(r, FamilleAnim.marche, 3.14159265 / 26);
      expect(marche.dy, lessThan(-8));
      expect(marche.inclinaison, closeTo(0.10, 1e-9));
      // attaque : à 0,14 s la fente est au plus loin, dans le sens du regard
      final droite = poseProcedurale(r, FamilleAnim.attaque, 0.1399);
      final gauche = poseProcedurale(r, FamilleAnim.attaque, 0.1399, sens: -1);
      expect(droite.dx, closeTo(26, 0.5));
      expect(gauche.dx, closeTo(-26, 0.5));
      // sort : saut à 0,12 s
      expect(poseProcedurale(r, FamilleAnim.sort, 0.12).dy, lessThan(-10));
      expect(poseProcedurale(r, FamilleAnim.repos, 1.0).dx, 0);
    });
  });

  group('doublons (V36)', () {
    img.Image pose(int bras) {
      final c = img.Image(width: 120, height: 160, numChannels: 4);
      img.fillRect(c, x1: 45, y1: 20, x2: 75, y2: 150, color: img.ColorRgba8(60, 90, 200, 255));
      img.fillRect(c, x1: 75, y1: 60 - bras, x2: 110, y2: 75 - bras, color: img.ColorRgba8(200, 60, 60, 255));
      return c;
    }

    test('deux poses identiques sont signalées, deux poses différentes non', () {
      final a = img.encodePng(pose(0));
      final b = img.encodePng(pose(0));
      final c = img.encodePng(pose(45));
      final d = detecterDoublons({0: a, 1: b, 2: c});
      expect(d.length, 1);
      expect(d.single.a, 0);
      expect(d.single.b, 1);
      expect(d.single.identique, isTrue);
      expect(casesAExclure(d), {1});
    });

    test('décalage dans la case : toujours un doublon (recadrage sur le sprite)', () {
      final decale = img.Image(width: 160, height: 200, numChannels: 4);
      img.compositeImage(decale, pose(0), dstX: 30, dstY: 25);
      final d = detecterDoublons({0: img.encodePng(pose(0)), 1: img.encodePng(decale)});
      expect(d.single.identique, isTrue);
    });
  });

  group('projet multi-planches (V36)', () {
    final heros = catalogueComplet().firstWhere((p) => p.id == 'assassin');

    PlancheProjet planche(int cols, int rows, PlancheDef? def, {int w = 2048, int h = 2048, String nom = 'p.png'}) =>
        PlancheProjet(
          octets: Uint8List(0),
          nomFichier: nom,
          imageW: w,
          imageH: h,
          grille: Grille.uniforme(cols, rows),
          planche: def,
        );

    test('planche coupée en deux images : la seconde reprend à la case 3', () {
      final face2 = planchesGrand.firstWhere((d) => d.cle == 'face_2');
      final projet = ProjetPersonnage(perso: heros);
      final a = planche(2, 1, face2, nom: 'haut.png');
      projet.planches.add(a);
      final b = planche(2, 1, face2, nom: 'bas.png');
      b.premiereCase = projet.premiereCaseSuggeree(face2);
      projet.planches.add(b);
      expect(b.premiereCase, 3);
      expect(a.nomFinal(0, heros), 'assassin_attack.png');
      expect(b.nomFinal(1, heros), 'assassin_attack_4.png');
      expect(controlerProjet(projet), isEmpty);
    });

    test('grilles différentes : noms en double bloquants, poses manquantes signalées', () {
      final face1 = planchesGrand.firstWhere((d) => d.cle == 'face_1');
      final projet = ProjetPersonnage(perso: heros);
      projet.planches.add(planche(2, 2, face1, nom: 'face_1.png'));
      projet.planches.add(planche(3, 1, face1, nom: 'face_1_bis.png'));
      final alertes = controlerProjet(projet);
      expect(alertes.where((a) => a.bloquante && a.texte.contains('en double')), isNotEmpty);

      final dos2 = planchesGrand.firstWhere((d) => d.cle == 'dos_2');
      final p2 = ProjetPersonnage(perso: heros);
      p2.planches.add(planche(3, 1, dos2, nom: 'dos_2.png'));
      final manques = controlerProjet(p2);
      expect(manques.single.bloquante, isFalse);
      expect(manques.single.texte, contains('assassin_back_idle_2.png'));
    });

    test('poses en double détectées : alerte tant qu\'elles restent incluses', () {
      final face3 = planchesGrand.firstWhere((d) => d.cle == 'face_3');
      final projet = ProjetPersonnage(perso: heros);
      final pl = planche(2, 2, face3);
      pl.doublons = const [Doublon(0, 1, 0.01)];
      projet.planches.add(pl);
      expect(controlerProjet(projet).single.texte, contains('poses en double'));
      pl.exclues.add(1);
      expect(controlerProjet(projet).where((a) => a.texte.contains('poses en double')), isEmpty);
    });

    test('planche sans type bloquante ; changement de personnage', () {
      final projet = ProjetPersonnage(perso: heros);
      final ref = planche(2, 1, planchesGrand.first);
      projet.planches.add(ref);
      projet.planches.add(planche(2, 2, planchesGrand.firstWhere((d) => d.cle == 'face_3')));
      projet.planches.add(planche(2, 2, null));
      expect(controlerProjet(projet).any((a) => a.bloquante && a.texte.contains('attribuer')), isTrue);
      final liche = catalogueComplet().firstWhere((p) => p.id == 'liche');
      projet.changerPerso(liche);
      expect(projet.planches[0].planche?.type, TypePlanche.reference, reason: 'la référence vaut pour tous');
      expect(projet.planches[1].planche, isNull, reason: 'face 3 n\'existe pas pour un ennemi');
    });

    test('échelle commune : la plus grande case de toutes les planches', () {
      final projet = ProjetPersonnage(perso: heros);
      projet.planches.add(planche(2, 2, planchesGrand[1], w: 1024, h: 1024)); // cases 512
      projet.planches.add(planche(2, 2, planchesGrand[2], w: 2048, h: 2048)); // cases 1024
      expect(projet.ratioCommun, closeTo(0.5, 1e-9));
    });

    test('poses réparties sur plusieurs planches : vue réelle et ordre', () {
      expect(vueDeLaPose(plancheDos: false, suffixe: '_back'), (dos: true, suffixe: ''));
      expect(vueDeLaPose(plancheDos: true, suffixe: '_walk'), (dos: true, suffixe: '_walk'));
      expect(rangDePose(''), lessThan(rangDePose('_idle_2')));
      expect(rangDePose('_attack'), lessThan(rangDePose('_attack_2')));
      expect(rangDePose('_attack_6'), greaterThan(rangDePose('_attack_5')));
    });

    test('animations combinées : vues et familles', () {
      final anims = animationsProjet({
        'Face': {0: '', 1: '_idle_2', 2: '_walk', 100: '_attack', 101: '_attack_2'},
        'Dos': {200: '', 201: '_walk'},
      });
      expect(anims.map((a) => a.libelle).toList(),
          ['Face · Repos', 'Face · Marche', 'Face · Attaque', 'Dos · Repos', 'Dos · Marche']);
      expect(anims[2].cases, [100, 101]);
    });
  });

  group('intensité et aperçu du détourage', () {
    img.Image planche() {
      final im = img.Image(width: 60, height: 40, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(im, x1: 10, y1: 10, x2: 29, y2: 29, color: img.ColorRgb8(30, 30, 200));
      return im;
    }

    int largeurSprite(img.Image im, int y) {
      var n = 0;
      for (var x = 0; x < im.width; x++) {
        if (im.getPixel(x, y).a.toInt() > 128) n++;
      }
      return n;
    }

    test('rognage : + grignote le bord, − le rend sans anneau de fond', () {
      final normal = planche();
      detourer(normal, tolerance: 30, douceur: 1.0, decontaminer: true);
      final rogne = planche();
      detourer(rogne, tolerance: 30, douceur: 1.0, decontaminer: true, rognage: 2);
      final rendu = planche();
      detourer(rendu, tolerance: 30, douceur: 1.0, decontaminer: true, rognage: -2);
      expect(largeurSprite(normal, 20), 20);
      expect(largeurSprite(rogne, 20), 16, reason: '2 px retirés de chaque côté');
      // Fond blanc pur autour du sprite : rien de visible n'est rendu.
      expect(largeurSprite(rendu, 20), 20);
      expect(rendu.getPixel(9, 20).a.toInt(), 0);
    });

    test('rognage − : un bord clair mangé par la tolérance est rendu', () {
      final im = planche();
      // liseré gris très clair autour du sprite (partie du dessin)
      img.drawRect(im, x1: 9, y1: 9, x2: 30, y2: 30, color: img.ColorRgb8(215, 215, 215));
      final mange = im.clone();
      detourer(mange, tolerance: 60, douceur: 1.0, decontaminer: false);
      expect(mange.getPixel(9, 20).a.toInt(), 0, reason: 'liseré pris pour du fond');
      detourer(im, tolerance: 60, douceur: 1.0, decontaminer: false, rognage: -1);
      expect(im.getPixel(9, 20).a.toInt(), greaterThan(0), reason: 'liseré rendu');
    });

    test('niveaux d\'intensité : Normal = défauts, reconnaissance du niveau', () {
      final o = OptionsTraitement();
      expect(niveauDe(o), 2);
      appliquerNiveau(o, 4);
      expect(o.tolerance, 85);
      expect(o.rognage, 2);
      expect(niveauDe(o), 4);
      appliquerNiveau(o, 0);
      expect(o.interieurs, isFalse);
      expect(niveauDe(o), 0);
      appliquerNiveau(o, 4);
      o.tolerance = 50;
      expect(niveauDe(o), -1);
      expect(o.copie().rognage, 2);
    });

    test('aperçu : original, détouré et zones retirées de même taille ; zoom sur une case', () {
      final octets = img.encodePng(planche());
      final demande = construireDemande(octets, Grille.uniforme(2, 1), OptionsTraitement(), const <int>[]);
      final entier = apercuDetourage(DemandeApercuDetour(demande));
      expect(entier.largeur, 60);
      expect(entier.pourcentageFond, greaterThan(50));
      final retrait = img.decodePng(entier.retrait)!;
      expect(retrait.getPixel(2, 2).a.toInt(), greaterThan(0), reason: 'fond retiré en rouge');
      expect(retrait.getPixel(20, 20).a.toInt(), 0, reason: 'sprite intact');
      final zoom = apercuDetourage(DemandeApercuDetour(demande, caseIndex: 1));
      expect(zoom.largeur, 30);
      expect(img.decodePng(zoom.original)!.width, 30);
    });

    test('libellés des nations : biome précisé, Sylvain chez les Vents', () {
      final sylvain = catalogueComplet().firstWhere((p) => p.id == 'sylvain');
      final druide = catalogueComplet().firstWhere((p) => p.id == 'druide');
      expect(sylvain.groupe, 'Nation Vents');
      expect(druide.groupe, 'Nation Sylvestre · Forêt');
    });
  });

  group('retouche à la main', () {
    // Planche 12×12 : fond blanc, carré rouge 2..9, canal blanc de 2 px de large du bord au centre.
    img.Image planche12() {
      final im = img.Image(width: 12, height: 12, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(im, x1: 2, y1: 2, x2: 9, y2: 9, color: img.ColorRgb8(200, 30, 30));
      return im;
    }

    CalqueRetouche calque(img.Image im, {Uint8List? forces}) {
      final brut = Uint8List(im.width * im.height * 4)..setAll(0, im.getBytes(order: img.ChannelOrder.rgba));
      return CalqueRetouche.depuis(OuvertureRetouche(
        im.width,
        im.height,
        brut,
        forces ?? Uint8List(im.width * im.height),
        Uint8List.fromList(brut),
      ));
    }

    test('détourage : pixel supprimé à la main même isolé, pixel protégé jamais retiré', () {
      final im = planche12();
      // Canal blanc relié au bord : sans protection, le fond y pénètre.
      img.fillRect(im, x1: 5, y1: 0, x2: 6, y2: 5, color: img.ColorRgb8(255, 255, 255));
      final forces = Uint8List(144);
      forces[7 * 12 + 7] = 1; // dans le rouge, isolé
      forces[4 * 12 + 5] = 2; // dans le canal blanc
      final copie = im.clone();
      detourer(copie, tolerance: 30, douceur: 1.0, decontaminer: false, forces: forces);
      expect(copie.getPixel(7, 7).a.toInt(), 0, reason: 'supprimé à la main');
      expect(copie.getPixel(5, 4).a.toInt(), 255, reason: 'protégé');
      expect(copie.getPixel(5, 5).a.toInt(), 0, reason: 'canal non protégé retiré');
      expect(copie.getPixel(3, 3).a.toInt(), 255, reason: 'le reste du sprite est conservé');
      expect(copie.getPixel(0, 0).a.toInt(), 0);
    });

    test('rognage : un pixel protégé n\'est pas grignoté, un pixel supprimé n\'est pas rendu', () {
      final im = planche12();
      final forces = Uint8List(144);
      forces[5 * 12 + 2] = 2; // bord gauche du carré
      final e = im.clone();
      detourer(e, tolerance: 30, douceur: 1.0, decontaminer: false, rognage: 1, forces: forces);
      expect(e.getPixel(2, 5).a.toInt(), 255, reason: 'protégé malgré l\'érosion');
      expect(e.getPixel(2, 6).a.toInt(), 0, reason: 'voisin non protégé grignoté');

      final f2 = Uint8List(144);
      f2[5 * 12 + 1] = 1; // fond supprimé à la main, collé au sprite
      final d = im.clone();
      detourer(d, tolerance: 30, douceur: 1.0, decontaminer: false, rognage: -1, forces: f2);
      expect(d.getPixel(1, 5).a.toInt(), 0, reason: 'supprimé à la main : jamais rendu');
    });

    test('pinceau : peint, protège, annule et rétablit', () {
      final c = calque(planche12());
      c.commencer();
      c.tampon(ModeRetouche.peindre, 0, 0, 1, r: 10, g: 20, b: 30);
      c.terminer();
      expect(c.couleurEn(0, 0), (r: 10, g: 20, b: 30));
      expect(c.forces[0], forceProtege);
      expect(c.modifie, isTrue);
      expect(c.annuler(), isTrue);
      expect(c.couleurEn(0, 0), (r: 255, g: 255, b: 255));
      expect(c.forces[0], forceAuto);
      expect(c.modifie, isFalse);
      expect(c.retablir(), isTrue);
      expect(c.couleurEn(0, 0), (r: 10, g: 20, b: 30));
    });

    test('gomme : un trait repassé deux fois s\'annule d\'un bloc', () {
      final c = calque(planche12());
      c.commencer();
      c.trait(ModeRetouche.effacer, 3, 3, 8, 3, 2);
      c.trait(ModeRetouche.effacer, 8, 3, 3, 3, 2);
      c.terminer();
      expect(c.forces[3 * 12 + 5], forceSupprime);
      expect(c.affichage[(3 * 12 + 5) * 4 + 3], 0, reason: 'affichage transparent');
      c.annuler();
      expect(c.forces.every((f) => f == forceAuto), isTrue);
      expect(c.affichage[(3 * 12 + 5) * 4 + 3], 255);
      expect(c.annuler(), isFalse);
    });

    test('restaurer rend la couleur d\'origine et repasse en automatique', () {
      final c = calque(planche12());
      c.commencer();
      c.tampon(ModeRetouche.peindre, 4, 4, 3, r: 0, g: 0, b: 255);
      c.terminer();
      c.commencer();
      c.tampon(ModeRetouche.restaurer, 4, 4, 5);
      c.terminer();
      expect(c.couleurEn(4, 4), (r: 200, g: 30, b: 30));
      expect(c.forces.every((f) => f == forceAuto), isTrue);
      expect(c.aDesForces, isFalse);
    });

    test('baguette : zone contiguë ou globale selon l\'option', () {
      final im = planche12();
      img.fillRect(im, x1: 11, y1: 11, x2: 11, y2: 11, color: img.ColorRgb8(200, 30, 30)); // rouge isolé
      final c = calque(im);
      c.commencer();
      final n = c.baguette(ModeRetouche.effacer, 4, 4, tolerance: 10, contigu: true);
      c.terminer();
      expect(n, 64, reason: 'carré rouge 8×8');
      expect(c.forces[11 * 12 + 11], forceAuto, reason: 'rouge isolé non contigu');
      c.annuler();
      c.commencer();
      final m = c.baguette(ModeRetouche.effacer, 4, 4, tolerance: 10, contigu: false);
      c.terminer();
      expect(m, 65);
      expect(c.forces[11 * 12 + 11], forceSupprime);
    });

    test('lasso : intérieur ou extérieur d\'un polygone', () {
      final c = calque(planche12());
      final carre = <double>[2, 2, 6, 2, 6, 6, 2, 6];
      c.commencer();
      final dedans = c.polygone(ModeRetouche.effacer, carre);
      c.terminer();
      expect(dedans, 16);
      expect(c.forces[3 * 12 + 3], forceSupprime);
      expect(c.forces[7 * 12 + 7], forceAuto);
      c.annuler();
      c.commencer();
      final dehors = c.polygone(ModeRetouche.proteger, carre, interieur: false);
      c.terminer();
      expect(dehors, 144 - 16);
      expect(c.forces[3 * 12 + 3], forceAuto);
      expect(c.forces[0], forceProtege);
    });

    test('teinte des zones protégées et contrôle du détourage', () {
      final im = planche12();
      final c = calque(im);
      c.commencer();
      c.tampon(ModeRetouche.proteger, 4, 4, 1);
      c.terminer();
      final avant = c.affichage[(4 * 12 + 4) * 4 + 1];
      c.teinterProteges = true;
      expect(c.affichage[(4 * 12 + 4) * 4 + 1], isNot(avant));
      c.teinterProteges = false;
      expect(c.affichage[(4 * 12 + 4) * 4 + 1], avant);

      c.commencer();
      c.tampon(ModeRetouche.effacer, 5, 5, 1);
      c.terminer();
      final brut = controleDetourage(DemandeControle(
        largeur: 12,
        hauteur: 12,
        pixels: c.pixels,
        forces: c.forces,
        tolerance: 30,
        douceur: 1.0,
        decontaminer: false,
        interieurs: true,
        aireMinInterieur: 24,
        rognage: 0,
      ));
      expect(brut.length, 12 * 12 * 4);
      expect(brut[(0) * 4 + 3], 0, reason: 'fond retiré');
      expect(brut[(5 * 12 + 5) * 4 + 3], 0, reason: 'pixel gommé à la main');
      expect(brut[(7 * 12 + 7) * 4 + 3], 255, reason: 'sprite conservé');
    });

    test('ouverture et encodage : aller-retour PNG sans perte', () {
      final im = planche12();
      final png = Uint8List.fromList(img.encodePng(im));
      final o = ouvrirRetouche(DemandeOuverture(png));
      expect(o.largeur, 12);
      expect(o.forces.length, 144);
      final retour = img.decodePng(encoderRetouche(DemandeEncodage(o.largeur, o.hauteur, o.pixels)))!;
      expect(retour.width, 12);
      final p = retour.getPixel(5, 5);
      expect([p.r.toInt(), p.g.toInt(), p.b.toInt()], [200, 30, 30]);
    });

    test('formes : rectangle plein ou contour, ellipse, ligne', () {
      final c = calque(planche12());
      c.commencer();
      expect(c.rectangle(ModeRetouche.proteger, 1, 1, 6, 6, epaisseur: 1, rempli: false), 20, reason: '6×6 moins 4×4');
      c.terminer();
      expect(c.forces[1 * 12 + 1], forceProtege);
      expect(c.forces[3 * 12 + 3], forceAuto, reason: 'intérieur du contour intact');
      c.annuler();

      c.commencer();
      expect(c.rectangle(ModeRetouche.effacer, 6, 6, 1, 1, epaisseur: 1, rempli: true), 36, reason: 'coins dans le désordre');
      c.terminer();
      c.annuler();

      c.commencer();
      final disque = c.ellipse(ModeRetouche.effacer, 2, 2, 9, 9, epaisseur: 1, rempli: true);
      c.terminer();
      expect(disque, inInclusiveRange(48, 64));
      expect(c.forces[5 * 12 + 5], forceSupprime);
      expect(c.forces[2 * 12 + 2], forceAuto, reason: 'coin du cadre hors de l\'ellipse');
      c.annuler();

      c.commencer();
      c.ellipse(ModeRetouche.effacer, 2, 2, 9, 9, epaisseur: 1, rempli: false);
      c.terminer();
      expect(c.forces[5 * 12 + 5], forceAuto, reason: 'centre de l\'ellipse creuse intact');
      expect(c.forces[2 * 12 + 5], forceSupprime, reason: 'bord haut de l\'ellipse');
      c.annuler();

      c.commencer();
      c.trait(ModeRetouche.peindre, 0, 11, 11, 11, 1, r: 9, g: 9, b: 9);
      c.terminer();
      expect(c.couleurEn(6, 11), (r: 9, g: 9, b: 9));
      expect(c.couleurEn(6, 10), isNot((r: 9, g: 9, b: 9)));
    });

    test('export PNG et JPG sans passer par les sprites', () {
      final c = calque(planche12());
      c.commencer();
      c.polygone(ModeRetouche.effacer, <double>[3, 3, 8, 3, 8, 8, 3, 8]); // bloc 5×5 gommé
      c.tampon(ModeRetouche.peindre, 0, 0, 1, r: 0, g: 0, b: 255);
      c.terminer();
      expect(c.version, greaterThan(0));

      DemandeExport demande(FormatExport f, {bool detourer = false}) => DemandeExport(
            largeur: 12,
            hauteur: 12,
            pixels: c.pixels,
            forces: c.forces,
            format: f,
            detourer: detourer,
            tolerance: 30,
            decontaminer: false,
          );

      final png = exporterImage(demande(FormatExport.png));
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final im = img.decodePng(png)!;
      expect(im.getPixel(5, 5).a.toInt(), 0, reason: 'pixel gommé transparent');
      expect(im.getPixel(9, 9).a.toInt(), 255);
      expect(im.getPixel(1, 1).a.toInt(), 255, reason: 'sans détourage, le fond reste');
      expect(im.getPixel(0, 0).b.toInt(), 255, reason: 'pixel peint');

      final detoure = img.decodePng(exporterImage(demande(FormatExport.png, detourer: true)))!;
      expect(detoure.getPixel(1, 1).a.toInt(), 0, reason: 'fond détouré');
      expect(detoure.getPixel(0, 0).a.toInt(), 255, reason: 'pixel peint protégé');

      final jpg = exporterImage(DemandeExport(
        largeur: 12,
        hauteur: 12,
        pixels: c.pixels,
        forces: c.forces,
        format: FormatExport.jpg,
        fondR: 0,
        fondG: 255,
        fondB: 0,
        qualite: 95,
      ));
      expect(jpg.sublist(0, 2), [0xFF, 0xD8]);
      final j = img.decodeJpg(jpg)!;
      expect(j.width, 12);
      final p = j.getPixel(5, 5);
      expect(p.g.toInt(), greaterThan(150), reason: 'transparent posé sur le fond vert');
      expect(p.r.toInt(), lessThan(110));
    });

    test('image vierge : transparente ou colorée', () {
      final t = img.decodePng(imageVierge((largeur: 16, hauteur: 8, fond: null)))!;
      expect([t.width, t.height], [16, 8]);
      expect(t.getPixel(3, 3).a.toInt(), 0);
      final b = img.decodePng(imageVierge((largeur: 4, hauteur: 4, fond: 0xFFFFFF)))!;
      expect(b.getPixel(1, 1).a.toInt(), 255);
      expect(b.getPixel(1, 1).r.toInt(), 255);
    });

    test('projet : appliquer puis annuler les retouches', () {
      final octets = Uint8List.fromList(img.encodePng(planche12()));
      final pl = PlancheProjet(octets: octets, nomFichier: 'a.png', imageW: 12, imageH: 12, grille: Grille.uniforme(1, 1));
      expect(pl.retouchee, isFalse);
      final retouche = Uint8List.fromList(img.encodePng(planche12()..setPixelRgba(0, 0, 1, 2, 3, 255)));
      pl.appliquerRetouche(retouche, Uint8List(144)..[0] = 2);
      expect(pl.retouchee, isTrue);
      expect(pl.octetsOrigine, octets);
      pl.appliquerRetouche(octets, Uint8List(144)..[1] = 1);
      expect(pl.octetsOrigine, octets, reason: 'l\'origine reste la première image');
      pl.annulerRetouche();
      expect(pl.retouchee, isFalse);
      expect(pl.octets, octets);
    });

    test('traiterCases : la retouche à la main se retrouve dans les cases exportées', () {
      final octets = Uint8List.fromList(img.encodePng(planche12()));
      final forces = Uint8List(144)..[7 * 12 + 7] = 1;
      final opt = OptionsTraitement()
        ..case512 = false
        ..tolerance = 30;
      final demande = construireDemande(octets, Grille.uniforme(1, 1), opt, const <int>[0], forces: forces);
      final r = traiterCases(demande);
      final sortie = img.decodePng(r.vignettes['0']!)!;
      expect(sortie.getPixel(7, 7).a.toInt(), 0);
      expect(sortie.getPixel(3, 3).a.toInt(), 255);
    });
  });

  group('pinceau avancé : opacité, dureté, dégradé, TSL', () {
    CalqueRetouche calqueVide(int w, int h) {
      final brut = Uint8List(w * h * 4);
      return CalqueRetouche.depuis(OuvertureRetouche(w, h, brut, Uint8List(w * h), Uint8List.fromList(brut)));
    }

    CalqueRetouche calqueBlanc(int w, int h) {
      final im = img.Image(width: w, height: h, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      final brut = Uint8List(w * h * 4)..setAll(0, im.getBytes(order: img.ChannelOrder.rgba));
      return CalqueRetouche.depuis(OuvertureRetouche(w, h, brut, Uint8List(w * h), Uint8List.fromList(brut)));
    }

    test('poidsBrosse : bord net à dureté 1, fondu doux à 0', () {
      expect(poidsBrosse(0, 1), 1);
      expect(poidsBrosse(0.999, 1), 1);
      expect(poidsBrosse(1, 1), 0);
      expect(poidsBrosse(1.2, 0), 0);
      expect(poidsBrosse(0.5, 0), closeTo(0.5, 0.01)); // smoothstep(0.5) = 0.5
      expect(poidsBrosse(0.5, 0.8), 1, reason: 'dans la zone dure');
      expect(poidsBrosse(0.9, 0), lessThan(0.2), reason: 'presque au bord, fondu faible');
    });

    test('tampon doux : plein au centre, fondu au bord', () {
      final c = calqueVide(9, 9);
      c.commencer();
      c.tampon(ModeRetouche.peindre, 4, 4, 9, r: 200, g: 0, b: 0, durete: 0);
      c.terminer();
      const centre = (4 * 9 + 4) * 4;
      expect(c.pixels[centre + 3], 255, reason: 'centre opaque');
      expect(c.pixels[centre], 200);
      const bord = (4 * 9 + 8) * 4; // q = 4/4.5 ≈ 0.89
      expect(c.pixels[bord + 3], inInclusiveRange(1, 120), reason: 'bord en fondu');
      expect(c.forces[4 * 9 + 4], forceProtege);
    });

    test('opacité : deux passages à 50 % ne rendent pas opaque', () {
      final c = calqueVide(4, 4);
      c.commencer();
      c.tampon(ModeRetouche.peindre, 1, 1, 1, r: 10, g: 20, b: 30, opacite: 0.5);
      c.terminer();
      const o = (1 * 4 + 1) * 4;
      final a1 = c.pixels[o + 3];
      expect(a1, inInclusiveRange(120, 135));
      c.commencer();
      c.tampon(ModeRetouche.peindre, 1, 1, 1, r: 10, g: 20, b: 30, opacite: 0.5);
      c.terminer();
      final a2 = c.pixels[o + 3];
      expect(a2, greaterThan(a1));
      expect(a2, lessThan(255));
    });

    test('peindre à 50 % sur blanc opaque : mélange de couleur, alpha à 255', () {
      final c = calqueBlanc(4, 4);
      c.commencer();
      c.tampon(ModeRetouche.peindre, 1, 1, 1, r: 200, g: 0, b: 0, opacite: 0.5);
      c.terminer();
      const o = (1 * 4 + 1) * 4;
      expect(c.pixels[o + 3], 255, reason: 'sur opaque, l\'alpha reste à 255');
      expect(c.pixels[o], inInclusiveRange(224, 232), reason: 'mélange 50 % : (255+200)/2 ≈ 227');
      expect(c.pixels[o + 1], inInclusiveRange(120, 135));
    });

    test('gomme douce : alpha réduit et pixel protégé ; à fond, supprimé', () {
      final c = calqueBlanc(4, 4);
      c.commencer();
      c.tampon(ModeRetouche.effacer, 1, 1, 1, opacite: 0.5);
      c.terminer();
      const o = (1 * 4 + 1) * 4;
      expect(c.pixels[o + 3], inInclusiveRange(120, 135));
      expect(c.forces[1 * 4 + 1], forceProtege, reason: 'effacement partiel = protégé du détourage');
      c.commencer();
      c.tampon(ModeRetouche.effacer, 1, 1, 1);
      c.terminer();
      expect(c.pixels[o + 3], 0);
      expect(c.forces[1 * 4 + 1], forceSupprime);
    });

    test('dégradé : couleur interpolée du début à la fin', () {
      final c = calqueVide(10, 1);
      c.commencer();
      c.traitDegrade(0, 0, 9, 0, 1, c0: (r: 255, g: 0, b: 0, a: 255), c1: (r: 0, g: 0, b: 255, a: 255));
      c.terminer();
      expect(c.couleurEn(0, 0)!.r, greaterThan(240));
      expect(c.couleurEn(0, 0)!.b, lessThan(20));
      expect(c.couleurEn(9, 0)!.b, greaterThan(240));
      expect(c.couleurEn(9, 0)!.r, lessThan(20));
      final milieu = c.couleurEn(4, 0)!; // t = 4/9
      expect(milieu.r, inInclusiveRange(120, 160));
      expect(milieu.b, inInclusiveRange(90, 140));
      expect(c.couleurEn(0, 0)!.r, isNot(c.couleurEn(9, 0)!.r));
    });

    test('dégradé vers transparent : fondu effaçant (alpha décroissant)', () {
      final c = calqueBlanc(10, 1);
      c.commencer();
      c.traitDegrade(0, 0, 9, 0, 1, c0: (r: 255, g: 0, b: 0, a: 255), c1: (r: 0, g: 0, b: 0, a: 0));
      c.terminer();
      expect(c.pixels[0 * 4 + 3], 255, reason: 'début opaque');
      expect(c.pixels[9 * 4 + 3], 0, reason: 'fin transparente');
      expect(c.pixels[4 * 4 + 3], inInclusiveRange(80, 170), reason: 'milieu à moitié fondu');
    });

    test('annuler / rétablir avec une brosse douce et semi-transparente', () {
      final c = calqueBlanc(6, 6);
      c.commencer();
      c.tampon(ModeRetouche.peindre, 3, 3, 5, r: 0, g: 0, b: 255, durete: 0, opacite: 0.7);
      c.terminer();
      expect(c.modifie, isTrue);
      expect(c.couleurEn(3, 3)!.b, 255);
      expect(c.couleurEn(3, 3)!.r, lessThan(100), reason: 'mélangé à 70 % avec le blanc');
      c.annuler();
      expect(c.couleurEn(3, 3), (r: 255, g: 255, b: 255));
      expect(c.forces.every((f) => f == forceAuto), isTrue);
      c.retablir();
      expect(c.couleurEn(3, 3)!.b, 255);
      expect(c.couleurEn(3, 3)!.r, lessThan(100));
    });

    test('TSL : couleurs primaires et aller-retour RVB -> TSL -> RVB', () {
      expect(tslVersRgb(0, 1, 0.5), (r: 255, g: 0, b: 0));
      expect(tslVersRgb(120, 1, 0.5), (r: 0, g: 255, b: 0));
      expect(tslVersRgb(240, 1, 0.5), (r: 0, g: 0, b: 255));
      final t = rgbVersTsl(255, 0, 0);
      expect(t.h, 0);
      expect(t.s, 1);
      expect(t.l, 0.5);
      for (final (r, g, b) in <(int, int, int)>[(200, 30, 30), (10, 20, 30), (255, 255, 255), (0, 0, 0), (1, 128, 250)]) {
        final t2 = rgbVersTsl(r, g, b);
        final c = tslVersRgb(t2.h, t2.s, t2.l);
        expect((c.r - r).abs(), lessThanOrEqualTo(2), reason: 'r de ($r, $g, $b)');
        expect((c.g - g).abs(), lessThanOrEqualTo(2), reason: 'g de ($r, $g, $b)');
        expect((c.b - b).abs(), lessThanOrEqualTo(2), reason: 'b de ($r, $g, $b)');
      }
    });

    test('palette de base : ARGB valides', () {
      expect(paletteBase.length, greaterThanOrEqualTo(10));
      for (final c in paletteBase) {
        expect((c >> 24) & 0xFF, 255, reason: 'opaque');
      }
    });
  });

  group('calques', () {
    CalqueRetouche docBlanc(int w, int h) {
      final im = img.Image(width: w, height: h, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      final brut = Uint8List(w * h * 4)..setAll(0, im.getBytes(order: img.ChannelOrder.rgba));
      return CalqueRetouche.depuis(OuvertureRetouche(w, h, brut, Uint8List(w * h), Uint8List.fromList(brut)));
    }

    test('une couche = rétrocompatible : pixels/forces/composite = la couche', () {
      final c = docBlanc(4, 4);
      expect(c.nbCouches, 1);
      c.commencer();
      c.tampon(ModeRetouche.peindre, 1, 1, 1, r: 9, g: 8, b: 7);
      c.terminer();
      expect(c.pixels[(1 * 4 + 1) * 4], 9);
      expect(c.forces[1 * 4 + 1], forceProtege);
      expect(c.pixelsComposite[(1 * 4 + 1) * 4], 9, reason: 'composite = la seule couche');
    });

    test('peindre sur la couche du dessus : composite mélangé, base intacte', () {
      final c = docBlanc(4, 4);
      c.ajouterCouche(nom: 'dessus');
      expect(c.nbCouches, 2);
      expect(c.actif, 1);
      c.commencer();
      c.tampon(ModeRetouche.peindre, 1, 1, 1, r: 200, g: 0, b: 0, opacite: 0.5);
      c.terminer();
      const o = (1 * 4 + 1) * 4;
      expect(c.couche(0).pixels[o], 255, reason: 'base inchangée');
      expect(c.pixelsComposite[o], inInclusiveRange(224, 232), reason: 'composite = 50 % de rouge sur blanc');
      expect(c.pixelsComposite[o + 3], 255);
      expect(c.couleurEn(1, 1)!.r, inInclusiveRange(224, 232), reason: 'la pipette lit le composite');
    });

    test('masquer la couche du dessus : le composite redevient la base', () {
      final c = docBlanc(4, 4);
      c.ajouterCouche();
      c.commencer();
      c.tampon(ModeRetouche.peindre, 0, 0, 1, r: 0, g: 0, b: 0);
      c.terminer();
      expect(c.pixelsComposite[0], 0, reason: 'couche du dessus noire opaque');
      c.basculerVisibilite(1);
      expect(c.pixelsComposite[0], 255, reason: 'couche masquée : composite = base blanche');
      c.basculerVisibilite(1);
      expect(c.pixelsComposite[0], 0);
    });

    test('forces au composite : la couche visible la plus haute gagne', () {
      final c = docBlanc(4, 4);
      c.activerCouche(0);
      c.commencer();
      c.tampon(ModeRetouche.proteger, 0, 0, 1);
      c.terminer();
      expect(c.forcesComposite[0], forceProtege);
      c.ajouterCouche();
      c.commencer();
      c.tampon(ModeRetouche.peindre, 0, 0, 1, r: 10, g: 10, b: 10);
      c.terminer();
      expect(c.forcesComposite[0], forceProtege, reason: 'peindre sur le dessus = protégé');
      c.commencer();
      c.tampon(ModeRetouche.effacer, 0, 0, 1);
      c.terminer();
      expect(c.forcesComposite[0], forceSupprime, reason: 'gomme sur le dessus = supprimé au composite');
      expect(c.couche(1).pixels[3], 0);
      c.basculerVisibilite(1);
      expect(c.forcesComposite[0], forceProtege, reason: 'couche du dessus masquée : force de la base');
      expect(c.pixelsComposite[0], 255, reason: 'composite = base blanche');
    });

    test('annuler / rétablir traverse les couches', () {
      final c = docBlanc(4, 4);
      c.ajouterCouche();
      c.commencer();
      c.tampon(ModeRetouche.peindre, 2, 2, 1, r: 1, g: 2, b: 3);
      c.terminer();
      const o = (2 * 4 + 2) * 4;
      expect(c.couche(1).pixels[o], 1);
      c.annuler();
      expect(c.couche(1).pixels[o + 3], 0, reason: 'couche du dessus revenue transparente');
      expect(c.pixelsComposite[o], 255, reason: 'composite = base');
      c.retablir();
      expect(c.couche(1).pixels[o], 1);
      expect(c.pixelsComposite[o], 1);
    });

    test('ajouter / dupliquer / déplacer / supprimer / renommer des couches', () {
      final c = docBlanc(4, 4);
      c.ajouterCouche(nom: 'A');
      c.ajouterCouche(nom: 'B');
      expect(c.nbCouches, 3);
      expect(c.actif, 2);
      c.renommerCouche(2, 'C');
      expect(c.couche(2).nom, 'C');
      c.deplacerCouche(-1);
      expect(c.actif, 1);
      expect(c.couche(1).nom, 'C');
      final dup = c.dupliquerCouche();
      expect(c.nbCouches, 4);
      expect(c.couche(dup).nom, 'C copie');
      expect(c.supprimerCouche(), isTrue);
      expect(c.nbCouches, 3);
      c.activerCouche(0);
      expect(c.supprimerCouche(), isTrue);
      expect(c.supprimerCouche(), isTrue);
      expect(c.supprimerCouche(), isFalse, reason: 'la dernière couche est intouchable');
      expect(c.nbCouches, 1);
    });

    test('toutRestaurer remet toutes les couches à l\'origine (une action annulable)', () {
      final c = docBlanc(4, 4);
      c.ajouterCouche();
      c.commencer();
      c.tampon(ModeRetouche.peindre, 1, 1, 1, r: 5, g: 5, b: 5);
      c.terminer();
      c.activerCouche(0);
      c.commencer();
      c.tampon(ModeRetouche.effacer, 2, 2, 1);
      c.terminer();
      expect(c.aDesForces, isTrue);
      c.toutRestaurer();
      expect(c.aDesForces, isFalse);
      expect(c.couche(1).pixels[(1 * 4 + 1) * 4 + 3], 0, reason: 'couche ajoutée : origine = transparent');
      expect(c.couche(0).pixels[(2 * 4 + 2) * 4 + 3], 255, reason: 'base : origine = blanc');
      expect(c.modifie, isTrue, reason: 'restaurable en une annulation');
      c.annuler();
      expect(c.aDesForces, isTrue);
    });

    test('le contrôle du détourage voit le composite aplati', () {
      final c = docBlanc(6, 6); // fond blanc
      c.ajouterCouche();
      c.commencer();
      c.rectangle(ModeRetouche.peindre, 2, 2, 3, 3, epaisseur: 1, rempli: true, r: 200, g: 30, b: 30);
      c.terminer();
      final brut = controleDetourage(DemandeControle(
        largeur: 6,
        hauteur: 6,
        pixels: c.pixelsComposite,
        forces: c.forcesComposite,
        tolerance: 30,
        douceur: 1.0,
        decontaminer: false,
        interieurs: true,
        aireMinInterieur: 24,
        rognage: 0,
      ));
      expect(brut[0 * 4 + 3], 0, reason: 'fond blanc retiré');
      expect(brut[(2 * 6 + 2) * 4 + 3], 255, reason: 'carré rouge de la couche du dessus conservé');
    });
  });

  group('sélection', () {
    CalqueRetouche docSel({bool isole = false}) {
      final im = img.Image(width: 12, height: 12, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(im, x1: 2, y1: 2, x2: 9, y2: 9, color: img.ColorRgb8(200, 30, 30));
      if (isole) img.fillRect(im, x1: 11, y1: 11, x2: 11, y2: 11, color: img.ColorRgb8(200, 30, 30));
      final brut = Uint8List(12 * 12 * 4)..setAll(0, im.getBytes(order: img.ChannelOrder.rgba));
      return CalqueRetouche.depuis(OuvertureRetouche(12, 12, brut, Uint8List(144), Uint8List.fromList(brut)));
    }

    test('masques rectangle / ellipse / polygone', () {
      final c = docSel();
      expect(c.masqueRectangle(1, 1, 4, 4).where((v) => v == 1).length, 16);
      final e = c.masqueEllipse(2, 2, 9, 9);
      expect(e[5 * 12 + 5], 1, reason: 'centre de l\'ellipse');
      expect(e[2 * 12 + 2], 0, reason: 'coin du cadre hors de l\'ellipse');
      expect(c.masquePolygone(<double>[2, 2, 6, 2, 6, 6, 2, 6]).where((v) => v == 1).length, 16);
      final dehors = c.masquePolygone(<double>[2, 2, 6, 2, 6, 6, 2, 6], interieur: false);
      expect(dehors[3 * 12 + 3], 0);
      expect(dehors[0], 1);
    });

    test('masqueBaguette sur le composite (contigu ou non)', () {
      final c = docSel(isole: true);
      expect(c.masqueBaguette(4, 4, tolerance: 10, contigu: true).where((v) => v == 1).length, 64);
      final m = c.masqueBaguette(4, 4, tolerance: 10, contigu: true);
      expect(m[11 * 12 + 11], 0, reason: 'rouge isolé non contigu');
      expect(c.masqueBaguette(4, 4, tolerance: 10, contigu: false)[11 * 12 + 11], 1);
    });

    test('appliquerSelection : remplacer / ajouter / soustraire / intersecter / inverser', () {
      final c = docSel();
      c.appliquerSelection(c.masqueRectangle(0, 0, 3, 3));
      expect(c.selection!.where((v) => v == 1).length, 16);
      c.appliquerSelection(c.masqueRectangle(2, 2, 5, 5), mode: ModeSelection.ajouter);
      expect(c.selection!.where((v) => v == 1).length, 28, reason: '16 + 16 − 4 de chevauchement');
      c.appliquerSelection(c.masqueRectangle(0, 0, 1, 1), mode: ModeSelection.soustraire);
      expect(c.selection!.where((v) => v == 1).length, 24);
      c.appliquerSelection(c.masqueRectangle(0, 0, 3, 3), mode: ModeSelection.intersecter);
      expect(c.selection!.where((v) => v == 1).length, 12, reason: '4×4 moins le 2×2 soustrait');
      c.selectionInverser();
      expect(c.selection!.where((v) => v == 1).length, 144 - 12);
      c.selectionTout();
      expect(c.selection!.where((v) => v == 1).length, 144);
      c.selectionRien();
      expect(c.aSelection, isFalse);
    });

    test('les outils ne touchent que la sélection', () {
      final c = docSel();
      c.appliquerSelection(c.masqueRectangle(2, 2, 5, 5));
      c.commencer();
      c.tampon(ModeRetouche.peindre, 0, 0, 3, r: 0, g: 0, b: 255); // hors sélection
      c.terminer();
      expect(c.couleurEn(0, 0), (r: 255, g: 255, b: 255), reason: 'hors sélection, inchangé');
      c.commencer();
      c.tampon(ModeRetouche.peindre, 3, 3, 3, r: 0, g: 0, b: 255); // dedans
      c.terminer();
      expect(c.couleurEn(3, 3), (r: 0, g: 0, b: 255), reason: 'dans la sélection, peint');
      expect(c.couleurEn(6, 6), (r: 200, g: 30, b: 30), reason: '(6,6) hors sélection : rouge d\'origine');
      c.commencer();
      c.tampon(ModeRetouche.effacer, 8, 8, 1); // hors sélection
      c.terminer();
      expect(c.forces[8 * 12 + 8], forceAuto, reason: 'gomme ignorée hors sélection');
    });

    test('contourSelection : segments du bord de la sélection', () {
      final c = docSel();
      c.appliquerSelection(c.masqueRectangle(2, 2, 5, 5));
      final seg = c.contourSelection();
      expect(seg.length % 4, 0);
      expect(seg.length ~/ 4, 16, reason: 'périmètre d\'un bloc 4×4 = 16 segments');
      c.selectionRien();
      expect(c.contourSelection(), isEmpty);
    });

    test('baguette lit le composite multi-couches', () {
      final c = docSel();
      c.ajouterCouche();
      c.commencer();
      c.tampon(ModeRetouche.peindre, 4, 4, 1, r: 200, g: 30, b: 30); // même rouge sur le dessus
      c.terminer();
      expect(c.masqueBaguette(4, 4, tolerance: 10, contigu: false).where((v) => v == 1).length, 64,
          reason: 'tout le carré rouge du composite');
    });

    test('annuler après une peinture sous sélection (la sélection survit)', () {
      final c = docSel();
      c.appliquerSelection(c.masqueRectangle(2, 2, 5, 5));
      c.commencer();
      c.tampon(ModeRetouche.peindre, 3, 3, 1, r: 0, g: 255, b: 0);
      c.terminer();
      expect(c.couleurEn(3, 3)!.g, 255);
      c.annuler();
      expect(c.couleurEn(3, 3), (r: 200, g: 30, b: 30));
      expect(c.aSelection, isTrue, reason: 'la sélection n\'est pas dans le journal pixels');
    });
  });

  group('aplatir et déplacer la sélection', () {
    CalqueRetouche doc12() {
      final im = img.Image(width: 12, height: 12, numChannels: 4);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(im, x1: 2, y1: 2, x2: 9, y2: 9, color: img.ColorRgb8(200, 30, 30));
      final brut = Uint8List(12 * 12 * 4)..setAll(0, im.getBytes(order: img.ChannelOrder.rgba));
      return CalqueRetouche.depuis(OuvertureRetouche(12, 12, brut, Uint8List(144), Uint8List.fromList(brut)));
    }

    test('aplatir : une seule couche = composite + forces fusionnées, origine conservée', () {
      final c = doc12();
      c.ajouterCouche();
      c.commencer();
      c.tampon(ModeRetouche.peindre, 0, 0, 1, r: 0, g: 0, b: 255);
      c.terminer();
      c.activerCouche(0);
      c.commencer();
      c.tampon(ModeRetouche.proteger, 11, 11, 1);
      c.terminer();
      expect(c.nbCouches, 2);
      c.aplatir();
      expect(c.nbCouches, 1);
      expect(c.actif, 0);
      expect(c.pixels[0 * 4 + 2], 255, reason: 'pixel peint sur la couche du dessus, aplati');
      expect(c.forces[11 * 12 + 11], forceProtege, reason: 'protection de la base fusionnée');
      expect(c.pixelsComposite[(5 * 12 + 5) * 4], 200, reason: 'composite aplati = carré rouge');
      // restaurer ramène l'image d'origine (origine de la couche de base)
      c.commencer();
      c.tampon(ModeRetouche.restaurer, 0, 0, 1);
      c.terminer();
      expect(c.pixels[0], 255, reason: 'origine conservée après aplatir');
    });

    test('aplatir ignore les couches masquées', () {
      final c = doc12();
      c.ajouterCouche();
      c.commencer();
      c.tampon(ModeRetouche.peindre, 0, 0, 1, r: 0, g: 0, b: 255);
      c.terminer();
      c.basculerVisibilite(1); // masquée
      c.aplatir();
      expect(c.pixels[0], 255, reason: 'couche masquée non aplatie : blanc d\'origine');
    });

    test('selectionBoite et extraireSelection', () {
      final c = doc12();
      expect(c.selectionBoite(), isNull);
      c.appliquerSelection(c.masqueRectangle(2, 2, 5, 5));
      final b = c.selectionBoite()!;
      expect((b.x0, b.y0, b.w, b.h), (2, 2, 4, 4));
      final t = c.extraireSelection()!;
      expect((t.w, t.h), (4, 4));
      expect(t.pixels[0], 200, reason: 'carré rouge extrait');
      expect(t.pixels[3], 255);
    });

    test('deplacerSelectionContenu : source supprimée, destination protégée, annulable', () {
      final c = doc12();
      c.appliquerSelection(c.masqueRectangle(2, 2, 5, 5)); // 4×4 rouge
      final t = c.extraireSelection()!;
      c.deplacerSelectionContenu(t, 8, 0); // déplace de +3 en x
      // source (2..5, 2..5) transparente + supprimée
      expect(c.pixels[(2 * 12 + 2) * 4 + 3], 0, reason: 'source vidée');
      expect(c.forces[2 * 12 + 2], forceSupprime);
      // destination (5..8, 2..5) : rouge déplacé, protégé
      expect(c.pixels[(2 * 12 + 10) * 4], 200, reason: 'destination = contenu déplacé');
      expect(c.pixels[(2 * 12 + 10) * 4 + 3], 255);
      expect(c.forces[2 * 12 + 10], forceProtege);
      // composite reflète le déplacement
      expect(c.pixelsComposite[(2 * 12 + 2) * 4 + 3], 0);
      expect(c.pixelsComposite[(2 * 12 + 10) * 4], 200);
      // une seule action annulable
      expect(c.modifie, isTrue);
      c.annuler();
      expect(c.pixels[(2 * 12 + 2) * 4], 200, reason: 'annulation = contenu revenu');
      expect(c.pixels[(2 * 12 + 2) * 4 + 3], 255);
      expect(c.pixels[(2 * 12 + 10) * 4], 255, reason: 'destination restaur\u00e9e (blanc) \u00e0 l\'annulation');
      expect(c.pixels[(2 * 12 + 10) * 4 + 3], 255);
      expect(c.forces[2 * 12 + 2], forceAuto);
    });

    test('deplacerSelectionContenu rogne aux bords de l\'image', () {
      final c = doc12();
      c.appliquerSelection(c.masqueRectangle(2, 2, 5, 5));
      final t = c.extraireSelection()!;
      c.deplacerSelectionContenu(t, 8, 8); // dépasse à droite/bas
      expect(c.pixels[(2 * 12 + 2) * 4 + 3], 0, reason: 'source vidée');
      // destination rognée : seuls les pixels encore dans l'image sont écrits
      expect(c.pixels[(10 * 12 + 10) * 4], 200, reason: '(10,10) = contenu d\u00e9plac\u00e9 \u00e9crit (blanc avant)');
      expect(c.pixels[(11 * 12 + 11) * 4], 200, reason: '(11,11) aussi \u00e9crit');
      expect(c.pixelsComposite.length, 12 * 12 * 4);
    });

    test('deplacerSelectionContenu sans sélection ne fait rien', () {
      final c = doc12();
      final avant = Uint8List.fromList(c.pixels);
      c.deplacerSelectionContenu((pixels: Uint8List(4), x0: 0, y0: 0, w: 1, h: 1), 2, 2);
      expect(c.pixels, avant);
      expect(c.modifie, isFalse);
    });
  });
}


