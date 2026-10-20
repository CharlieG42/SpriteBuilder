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
   - indicateur de contrôle : pourcentage de fond retiré, alerte si < 5 % ou > 92 %.
3. **Personnage & poses** — catalogue complet embarqué (10 nations : héros, 4 ennemis, boss ;
   12 familiers ; 10 mécanismes), **présélection automatique depuis le nom du fichier**
   (`assassin_dos_attaques.png` → Assassin + Dos · Attaques). Les noms de poses s'appliquent
   dans l'ordre des cases selon la convention `EntityView.gd` (V34) :
   - héros/boss, repos et sorts : `<id>`, `_idle_2`, `_idle_3`, `_walk`, `_walk_2`, `_cast`, `_cast_2`, `_cast_3` ;
   - héros/boss, attaques : `_attack` … `_attack_8` ;
   - ennemis/familiers : `<id>`, `_idle_2`, `_walk`, `_attack` … `_attack_4`, `_cast` ;
   - vue de dos : suffixe `_back` (`<id>_back.png`, `<id>_back_attack_3.png`…) ;
   - planches découpées en deux moitiés 2×2 : règlage « première case de la planche ».
4. **Export** — cases normalisées en carrés de 512 px (optionnel) et rangées dans un zip
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
├── data/catalog.dart            nations, familiers, mécanismes, planches, noms de fichiers, présélection
├── core/
│   ├── detourage.dart           flood fill bord, alpha doux, décontamination
│   ├── decoupe.dart             Grille, détection auto, extraction des cases, carré 512
│   └── traitement.dart          worker isolate (décodage → détour → cases → PNG)
├── export/atelier_export.dart   chemins du dépôt + écriture du zip (archive)
├── widgets/apercu_grille.dart   aperçu interactif, séparateurs déplaçables au doigt
└── screens/                     accueil + workflow en 4 étapes
test/atelier_test.dart           noms de fichiers, catalogue, détourage, découpe
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
