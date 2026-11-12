# SpriteBuilder

**Atelier Sprites** — utilitaire Android (Flutter) rapatrié depuis [CharlieG42/Zimut](https://github.com/CharlieG42/Zimut) (PR #117, branche `vibe/atelier-sprites`).

Il transforme les **planches de sprites générées par IA** en PNG individuels prêts pour le jeu Zimut :
import → détourage → découpe → nommage des poses → export zip.

## Structure

- `atelier_sprites/` — le code Dart de l'atelier (la coque Android est générée par `flutter create`, voir `atelier_sprites/README.md`)
- `.github/workflows/build-apk.yml` — workflow GitHub Actions qui génère le scaffolding Android, lance les tests et construit l'APK debug, publié en artifact.
- `sprites_3d/` — conversion des sprites détourés en modèles 3D (`.glb`) avec TripoSR, via le workflow `.github/workflows/sprites-3d.yml` (voir `sprites_3d/README.md`).

## APK

Deux APK sont construits par GitHub Actions à chaque push sur `main`, sur chaque PR, ou via *Run workflow*
(onglet **Actions** de la run) :

- `atelier-sprites-release-apk-<version>-<run>` : **release signée**, optimisée — celle à installer ;
- `atelier-sprites-debug-apk` : debug, pour diagnostiquer.

Le `versionCode` de la release vaut le numéro de run : chaque APK s'installe par-dessus le précédent.

### Signature (secrets GitHub)

*Settings → Secrets and variables → Actions*, mêmes noms que pour Zimut :

| Secret | Contenu |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | le fichier `.jks` encodé en base64 (`base64 -w0 cle.jks`) |
| `ANDROID_KEY_ALIAS` | alias de la clé |
| `ANDROID_KEY_PASSWORD` | mot de passe (magasin et clé identiques, format PKCS12) |

Sans ces secrets (fork, dépôt non configuré), la release est signée avec la clé de debug et la run
l'indique par un avertissement. Le résumé de chaque run affiche le certificat utilisé.
`tool/configurer_android.py` branche la signature (et le nom « Atelier Sprites ») dans la coque
Android générée par `flutter create`. La clé ne doit jamais être versionnée (`.gitignore`).

### Icône

`tool/generer_icone.py` dessine l'icône (héros en pixel art sur damier de transparence, repères de
découpe) dans `atelier_sprites/assets/icone/` : icône complète + premier plan / fond de l'icône
adaptative. La CI l'installe avec `dart run flutter_launcher_icons`.

En local :

```bash
cd atelier_sprites
flutter create --org wildzimut --platforms android --project-name atelier_sprites .
python3 tool/configurer_android.py
flutter pub get
dart run flutter_launcher_icons
flutter test
flutter build apk --debug
```
