# Atelier Sprites — Zimut

Utilitaire Android (Flutter) pour transformer les **planches de sprites générées par IA** en
PNG individuels prêts pour le jeu, en bouclant sur téléphone toute la chaîne décrite dans
`prompts_sprites/README.md` : import → détourage → découpe → nommage des poses → export zip.

## Installation

Le dossier ne contient que la partie Dart du projet (pas de scaffolding Android, volontairement).
Génère la coque plateforme puis lance :

```bash
cd atelier_sprites
flutter create --org wildzimut --platforms android .
flutter pub get
flutter test
flutter run
```

## Pipeline

0. **Personnage (plusieurs planches)** — on importe d'un coup une ou plusieurs planches d'un
   même personnage, **chacune avec sa propre grille** (fiche de référence 2×1, planches de
   poses 2×2, ou toute autre grille produite par le générateur). Le personnage et le type de
   chaque planche sont présélectionnés depuis les noms de fichiers (`<id>_ref`, `<id>_face_2`,
   `<id>_dos_1`…) ; une planche coupée en deux images reprend automatiquement à la bonne case.
   L'écran Personnage liste les
   planches (grille, cases exclues, état *à attribuer / à vérifier / prête*) et vérifie avant
   export :
   - **noms en double** : deux cases qui produiraient le même fichier (bloquant) ;
   - **poses en double** détectées sur une planche et encore incluses ;
   - **poses manquantes** dans une planche (ex. `assassin_back_cast_2.png`) ;
   - planches sans type (bloquant).
   L'export produit **un seul zip** `zimut_sprites_<id>.zip` avec une **échelle commune** à
   toutes les planches (la plus grande case fixe la réduction) et la même ligne de sol : le
   personnage garde la même taille entre repos, attaques, face et dos. L'aperçu des
   animations combine toutes les planches et range chaque pose selon sa vue réelle et son
   numéro (« Face · Repos » = `<id>` de la fiche de référence + `_idle_2` de Face 1).
   Touche une planche pour ouvrir son parcours en 4 étapes ci-dessous ; le détourage et les
   options d'export sont communs au personnage.

1. **Planche & grille** — importe l'image (fond blanc ou gris uni, jamais vert ou rose).
   Le nombre de colonnes/lignes est **détecté automatiquement** (projection des pixels de
   contenu) ; les séparateurs se **déplacent au doigt** quand deux poses se touchent
   (piège observé sur les planches précédentes), et les cases peuvent être exclues
   (texte collé, pose ratée).
2. **Détourage** — portage du cœur de `detoure_planche.py` en Dart :
   - remontée (flood fill) **depuis les bords uniquement** → les zones claires enfermées
     dans un sprite (yeux, neige, reflets) sont conservées ;
   - **tolérance de couleur** réglable (fond estimé depuis les quatre coins) ;
   - **bord doux** (rampe d'alpha) et **décontamination du halo** (re-pousse la couleur
     du bord hors du blanc du fond) ;
   - **intensité** en un geste (léger / normal / fort / très fort) : règle ensemble tolérance,
     rognage et bord doux ; réglages fins repliables ;
   - **rognage du bord** (−3 à +6 px) : + grignote le liseré clair laissé autour du sprite,
     − rend un bord clair mangé par la tolérance (les pixels de fond pur restent transparents) ;
   - **aperçu en direct**, recalculé après chaque réglage, sur la planche entière ou une case
     zoomée : *Résultat* sur fond noir / magenta / blanc / herbe / damier (un liseré saute aux
     yeux), *Avant/après* avec curseur de séparation, *Retiré* (zones supprimées en rouge sur
     l'original) ; zoom au doigt avec pixels nets ;
   - **retouche à la main** (bouton sous l'aperçu), façon logiciel de dessin, sur la planche
     entière : *pinceau* (peint et protège), *gomme* (supprime), *protéger* (le détourage ne
     retire jamais ces pixels : cheveux blancs, reflets), *restaurer*, *baguette magique*
     (tolérance, contigu ou non), *lasso* (intérieur ou extérieur), *pipette*, zoom à deux doigts,
     annuler / rétablir, et *contrôle* du détourage automatique avec tes retouches ;
   - indicateur de contrôle : pourcentage de fond retiré, alerte si < 5 % ou > 92 %.
3. **Personnage & poses** — catalogue complet embarqué (10 nations : héros, 4 ennemis, boss ;
   12 familiers ; 10 mécanismes), **présélection automatique depuis le nom du fichier**
   (`assassin_face_2.png` → Assassin + Face 2). Les noms de poses s'appliquent dans l'ordre
   des cases (gauche à droite, haut en bas) selon la convention V36 (`prompts_sprites`) :
   - fiche de référence (tous) : `<id>`, `<id>_back` ;
   - héros/boss — Face 1 : `_idle_2`, `_walk`, `_walk_2`, `_cast` ; Face 2 : `_attack` … `_attack_4` ;
     Face 3 : `_attack_5`, `_attack_6`, `_cast_2`, `_cast_3` ; Dos 1 : `_back_walk`, `_back_walk_2`,
     `_back_attack`, `_back_cast` ; Dos 2 : `_back_attack_2` … `_back_attack_4`, `_back_idle_2` ;
   - ennemis/familiers — Face : `_walk`, `_attack`, `_attack_2`, `_cast` ; Dos : idem avec `_back` ;
   - **poses en double** : signature de chaque case comparée aux autres, bouton pour les exclure ;
   - planche coupée en deux images : réglage « première case de la planche ».
4. **Aperçu des animations** (bouton aux étapes 3 et 4) — les cases sont regroupées en
   animations d'après leurs suffixes (repos, marche, sort, attaque, plus « toutes les cases »)
   et jouées en boucle :
   - cadence réglable (1 à 24 img/s, valeur par défaut adaptée à chaque famille), lecture
     image par image, aller-retour (`1 2 3 2`) ;
   - **miroir** pour simuler les directions vers la gauche (le jeu retourne l'image) ;
   - **pelure d'oignon** (image précédente en transparence) et **ligne de sol** ;
   - fonds damier / clair / sombre / herbe ; une image peut être retirée de la boucle d'un appui ;
   - **partage en GIF** de l'animation (fond uni, miroir appliqué).
   - **mouvement du jeu** : simule l'animation procédurale de Zimut (`EntityView.gd`, V35) —
     respiration au repos, petits sauts de marche, fente d'attaque, saut de sort — et la
     **règle par personnage** (curseurs de la famille affichée). Les réglages sont mémorisés
     sur l'appareil par personnage (on les retrouve d'une planche à l'autre) et, s'ils
     diffèrent des valeurs du jeu, l'export ajoute `<id>_anim.txt` (JSON) à côté du repos
     de face, là où le jeu le lit.
5. **Pieds alignés (ancrage au sol)** — option d'export : dans le carré de 512 px, le bas de
   chaque sprite est posé sur la même ligne de sol (6 % du bas) au lieu de centrer la case,
   avec une échelle commune à toutes les cases. Le personnage ne « saute » plus d'une pose à
   l'autre. Le réglage se teste directement dans l'aperçu des animations.
6. **Export** — cases normalisées en carrés de 512 px (optionnel) et rangées dans un zip
   **calqué sur l'arborescence du dépôt** :

   ```
   prototype/zimut/assets/sprites/players/<id>*.png          héros
   prototype/zimut/assets/sprites/nations/heros/<id>.png     miroir du repos de face du héros
   prototype/zimut/assets/sprites/nations/heros/poses/…      miroir des autres poses du héros
   prototype/zimut/assets/sprites/nations/ennemis/<nation>/…
   prototype/zimut/assets/sprites/nations/boss/…
   prototype/zimut/assets/sprites/summons/…                  familiers et mécanismes
   ```

   Décompresse le zip **à la racine du dépôt** : le jeu prend les sprites sans changer le code.
   Le partage Android (SAF) propose d'enregistrer le zip ou de l'envoyer (Drive, mail…).

## Structure

```
lib/
├── main.dart                    point d'entrée
├── models.dart                  Vue, PlancheDef, PersonnageCatalogue, options, demandes isolate
├── projet.dart                  projet personnage : planches, nommage, échelle commune, contrôles
├── data/catalog.dart            nations, familiers, mécanismes, planches, noms de fichiers, présélection
├── core/
│   ├── detourage.dart           flood fill bord, alpha doux, décontamination
│   ├── decoupe.dart             Grille, détection auto, extraction des cases, carré 512, ancrage au sol
│   ├── animations.dart          regroupement des poses en animations, séquence aller-retour
│   ├── gif.dart                 encodage GIF animé (isolate)
│   ├── retouche.dart            calque de retouche à la main (outils, annuler/rétablir, forces)
│   ├── reglages_anim.dart       mouvement procédural de Zimut : paramètres, formules, mémorisation
│   └── traitement.dart          worker isolate (décodage → détour → cases → PNG)
├── export/atelier_export.dart   chemins du dépôt + écriture du zip (archive)
├── widgets/
│   ├── apercu_grille.dart       aperçu interactif, séparateurs déplaçables au doigt
│   └── damier.dart              fond damier (transparence visible)
└── screens/                     accueil, personnage (multi-planches), workflow en 4 étapes, aperçu des animations
test/atelier_test.dart           noms de fichiers, catalogue, détourage, découpe, ancrage, animations, GIF
```

Dépendances : `image` (décodage/encodage PNG), `file_picker`, `path_provider`, `share_plus`,
`archive` (zip). Le catalogue et les conventions sont alignés sur `prompts_sprites/generer_prompts.py` ;
toute évolution du catalogue se corrige dans `lib/data/catalog.dart`.

## Notes

- Le fond doit être **uni** (blanc `#FFFFFF`, ou gris `#808080` pour les personnages clairs :
  Mage, Heal, Sylvain, boss Cristaux et Vents). Un damier ou un dégradé ne seront pas retirés.
- Le détourage ne remplace pas un contrôle visuel : vérifie les cases une par une
  (une seule vue par planche, pas d'ombre au sol, pas de texte).
- Les traitements lourds tournent dans un isolate : l'interface reste fluide sur téléphone.
