# SpriteBuilder

**Atelier Sprites** — utilitaire Android (Flutter) rapatrié depuis [CharlieG42/Zimut](https://github.com/CharlieG42/Zimut) (PR #117, branche `vibe/atelier-sprites`).

Il transforme les **planches de sprites générées par IA** en PNG individuels prêts pour le jeu Zimut :
import → détourage → découpe → nommage des poses → export zip.

## Structure

- `atelier_sprites/` — le code Dart de l'atelier (la coque Android est générée par `flutter create`, voir `atelier_sprites/README.md`)
- `.github/workflows/build-apk.yml` — workflow GitHub Actions qui génère le scaffolding Android, lance les tests et construit l'APK debug, publié en artifact.

## APK

L'APK est construit automatiquement par GitHub Actions à chaque push sur `main` (ou via *Run workflow*).
Récupère-le dans l'onglet **Actions** de la run → artifact `atelier-sprites-debug-apk`.

En local :

```bash
cd atelier_sprites
flutter create --org wildzimut --platforms android --project-name atelier_sprites .
flutter pub get
flutter test
flutter build apk --debug
```
