# Sprites vers 3D

Transforme les sprites détourés par Atelier Sprites en modèles 3D (`.glb`) avec
[TripoSR](https://github.com/VAST-AI-Research/TripoSR) (licence MIT, code et poids).
Tout tourne sur les machines de GitHub Actions, en CPU : aucun PC ni carte
graphique à la maison.

## Utilisation depuis GitHub (téléphone ou navigateur)

1. Ouvre le dossier `sprites_3d/entrees/` du dépôt.
2. **Add file → Upload files** : dépose des PNG détourés (fond transparent), ou
   directement un zip d'export d'Atelier Sprites (`zimut_sprites_<id>.zip`).
3. Valide le commit sur `main`. Le workflow **Sprites vers 3D (TripoSR)** démarre
   tout seul et ne traite que les fichiers ajoutés ou modifiés par ce dépôt.
4. Onglet **Actions** → ouvre l'exécution → télécharge l'artifact
   `sprites-3d-<numéro>`. Il contient :
   - `<nom>.glb` : un modèle par sprite ;
   - `preparees/<nom>.png` : l'image réellement donnée au modèle (pour comprendre
     un résultat raté) ;
   - `resume.md` : le tableau récapitulatif, aussi affiché sur la page de l'exécution.

Les artifacts sont gardés 7 jours.

### Relancer avec d'autres réglages

Onglet **Actions** → **Sprites vers 3D (TripoSR)** → **Run workflow**. Tout le
dossier `entrees/` est alors retraité, avec trois réglages :

| Réglage | Effet |
|---|---|
| `filtre` | ne traiter que certains noms, ex. `assassin*` ou `*_idle_*` |
| `resolution` | finesse du maillage : 128 (léger) à 320 (détaillé), 256 par défaut |
| `marge` | part du cadre occupée par le sprite, 0.85 par défaut. C'est le « Foreground Ratio » de la démo : à modifier si le modèle sort déformé |

## Bon à savoir

- **Un sprite = un modèle statique**, sans squelette ni animation.
- **Images détourées uniquement** : une image sans transparence est refusée avec
  un message, le reste du lot continue.
- **Doublons** : une même image présente plusieurs fois (zip d'export d'un héros)
  n'est convertie qu'une fois.
- **Couleurs** : elles sont portées par les sommets du maillage, il n'y a pas de
  fichier de texture. Si le modèle apparaît blanc dans Godot, active
  *Vertex Color → Use as Albedo* sur son matériau.
- **Durée** : compter environ 45 s par sprite, plus 1 à 3 min d'installation. La
  première exécution télécharge le modèle (1,7 Go), ensuite gardé en cache.
- **Minutes GitHub Actions** : gratuites tant que le dépôt est public ; s'il
  repasse en privé, chaque exécution consomme le quota mensuel du compte.
  Déposer des sprites ne relance pas le build de l'APK.
- **Dépôt public** : les sprites déposés dans `entrees/` et les modèles publiés
  en artifact sont visibles de tous.
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

## Détails techniques

- `sprites_vers_3d.py` recadre chaque sprite, le centre dans un carré sur fond
  gris (ce qu'attend TripoSR), génère le maillage et l'exporte en GLB, axe Y vers
  le haut.
- TripoSR dépend de `torchmcubes`, une extension C++ à compiler. Le script la
  remplace par `PyMCubes`, installable tel quel, qui produit le même maillage.
- Les versions de TripoSR, PyTorch et des dépendances sont figées dans le workflow
  et `requirements.txt`.
