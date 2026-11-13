# Sprites vers 3D

Transforme les sprites détourés par Atelier Sprites en modèles 3D avec
[TripoSR](https://github.com/VAST-AI-Research/TripoSR) (licence MIT, code et poids),
prêts pour un moteur de jeu ou pour [Mixamo](https://www.mixamo.com).
Tout tourne sur les machines de GitHub Actions, en CPU : aucun PC ni carte
graphique à la maison.

## Utilisation depuis GitHub (téléphone ou navigateur)

1. Ouvre le dossier `sprites_3d/entrees/` du dépôt.
2. **Add file → Upload files** : dépose des PNG détourés (fond transparent), ou
   directement un zip d'export d'Atelier Sprites (`zimut_sprites_<id>.zip`).
3. Valide le commit sur `main`. Le workflow **Sprites vers 3D (TripoSR)** démarre
   tout seul et ne traite que les fichiers ajoutés ou modifiés par ce dépôt.
4. Onglet **Actions** → ouvre l'exécution → télécharge l'artifact
   `sprites-3d-<numéro>`. Un dossier par sprite :

   | Fichier | Usage |
   |---|---|
   | `<nom>.glb` | modèle texturé, léger : Godot, Blender, visionneuses |
   | `<nom>.fbx` | FBX avec texture intégrée |
   | `<nom>_mixamo_obj.zip` | OBJ + MTL + texture, à déposer tel quel sur Mixamo |
   | `<nom>_texture.png` | la texture seule |

   À la racine : `preparees/<nom>.png` (l'image réellement donnée au modèle, pour
   comprendre un résultat raté) et `resume.md` (le tableau récapitulatif, aussi
   affiché sur la page de l'exécution).

Les artifacts sont gardés 7 jours.

### Relancer avec d'autres réglages

Onglet **Actions** → **Sprites vers 3D (TripoSR)** → **Run workflow**. Tout le
dossier `entrees/` est alors retraité, avec quatre réglages :

| Réglage | Effet |
|---|---|
| `filtre` | ne traiter que certains noms, ex. `assassin*` ou `*_idle_*` |
| `resolution` | finesse du maillage brut : 128 (léger) à 320 (détaillé), 256 par défaut |
| `marge` | part du cadre occupée par le sprite, 0.85 par défaut. C'est le « Foreground Ratio » de la démo : à modifier si le modèle sort déformé |
| `nettoyage_sprite` | réparation du détourage avant TripoSR (actif par défaut) ; à décocher pour comparer avec et sans |

## Mixamo

Mixamo accepte les fichiers FBX, OBJ et ZIP. Le plus sûr : dépose
`<nom>_mixamo_obj.zip` (OBJ, MTL et texture ensemble, c'est ce qui conserve les
couleurs), puis place les repères de l'auto-rigger. Le personnage regarde vers +Z,
mesure 1,8 m, pieds à l'origine, et ne porte que 25 000 triangles. Le `.fbx` est
fourni avec sa texture intégrée ; si Mixamo le refuse, utilise le zip.

Un T-pose, comme celui du sprite d'origine, est la pose à privilégier pour
l'auto-rigger.

## Ce que fait la chaîne pour améliorer le rendu

1. **Réparation du sprite** avant TripoSR : liseré blanc retiré, fentes laissées
   par le détourage comblées avec les couleurs voisines. Sans cela, le modèle voit
   du vide autour des poches et des ceintures et fait une surface bruitée.
2. **Maillage allégé** : fragments flottants retirés, surface lissée, réduite de
   90 000 à 25 000 triangles.
3. **Vraie texture** de 2048 px (au lieu de couleurs portées par les sommets),
   lue sur le maillage dense : le détail est conservé.
4. **Recalage des couleurs** : TripoSR sort des couleurs ternes. Saturation et
   luminosité sont ramenées à celles du sprite, sans toucher aux teintes.
5. **Sprite plaqué sur la face avant** : la caméra est retrouvée en superposant
   le modèle au sprite, puis les pixels nets du sprite (visage, ceinture, poches)
   sont peints sur toutes les surfaces vues de face, avec un fondu vers les côtés.
   Le dos et les flancs gardent la couleur devinée par TripoSR.

## Limites

- **Le dos est inventé** : TripoSR ne reçoit qu'une image. Le dos et les côtés
  sont donc approximatifs, surtout la cape. Un vrai gain demanderait un modèle à
  plusieurs vues (face + dos), qui exige un GPU.
- **Un sprite = un modèle statique**, sans squelette ni animation : c'est Mixamo
  qui apporte le squelette.
- **Images détourées uniquement** : une image sans transparence est refusée avec
  un message, le reste du lot continue.
- **Doublons** : une même image présente plusieurs fois (zip d'export d'un héros)
  n'est convertie qu'une fois.
- **Durée** : 2 à 3 min par exécution, installation comprise. La première
  exécution télécharge le modèle (1,7 Go), ensuite gardé en cache.
- **Dépôt public** : les sprites déposés dans `entrees/` et les modèles publiés
  en artifact sont visibles de tous. Les minutes Actions sont gratuites ; si le
  dépôt repasse en privé, chaque exécution consomme le quota mensuel.
- Pour ne pas garder les sprites dans le dépôt, supprime-les de `entrees/` une
  fois les modèles récupérés (une suppression ne déclenche aucune conversion).

## En local (facultatif)

```bash
git clone https://github.com/VAST-AI-Research/TripoSR ../TripoSR
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install -r sprites_3d/requirements.txt
python sprites_3d/sprites_vers_3d.py sprites_3d/entrees --sorties sorties_3d --triposr ../TripoSR
python -m unittest sprites_3d/test_sprites_vers_3d.py
```

Options utiles : `--faces 40000`, `--texture 4096`, `--sans-fbx`, `--brut` (maillage
brut seulement), `--sans-nettoyage`, `--sans-calage-couleurs`, `--sans-projection`. Le FBX demande Blender
(`pip install bpy` dans un environnement à part, désigné par la variable
`PYTHON_BLENDER`) ; sans lui, les autres formats sont produits normalement.

### Retraiter un GLB déjà produit

Pour un modèle venu de la démo Hugging Face, dont le personnage regarde vers -Z :

```bash
python sprites_3d/postraitement.py Zimut.glb --sorties sorties_3d --tourner 180 \
    --palette sprites_3d/entrees/Zimut.png
```

Pour repeindre un GLB déjà généré avec un sprite plus propre, sans relancer TripoSR :
`python postraitement.py Zimut.glb --sprite Zimut.png`.

## Sans IA : modèle construit à partir des dessins

`silhouettes.py` n'utilise pas TripoSR : il gonfle la silhouette de face en volume
(bras en cylindres, tête en boule) puis plaque le dessin de face sur l'avant et le
dessin de dos sur l'arrière. Quelques secondes sur processeur.

    python silhouettes.py Zimut.png --dos Zimut_dos.png --sorties sorties_3d

Sans `--dos`, la face est reprise à l'arrière. `--epaisseur` (0.8) et `--plafond`
(0.18 m) règlent le volume. Les dessins doivent avoir la même pose et les mêmes
proportions. Les sorties sont les mêmes : GLB, FBX, zip OBJ pour Mixamo.

## Détails techniques

- `sprites_vers_3d.py` répare, recadre et centre chaque sprite dans un carré sur
  fond gris (ce qu'attend TripoSR), génère le maillage puis appelle
  `postraitement.py`.
- `postraitement.py` fait le nettoyage du maillage, le dépliage UV (xatlas), la
  cuisson de texture et les exports. `convertir_fbx_blender.py` écrit le FBX avec
  Blender, dans un processus séparé.
- TripoSR dépend de `torchmcubes`, une extension C++ à compiler. Le script la
  remplace par `PyMCubes`, installable tel quel, qui produit le même maillage.
- Les versions de TripoSR, PyTorch et des dépendances sont figées dans le workflow
  et `requirements.txt`.
