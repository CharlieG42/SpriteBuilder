#!/usr/bin/env python3
"""configurer_android.py — ajuste la coque Android générée par `flutter create`.

Le dépôt ne versionne pas le dossier android/ (il est régénéré en CI). Ce script,
lancé juste après `flutter create`, applique :

- la **signature release** : lit `android/key.properties` (storeFile, storePassword,
  keyAlias, keyPassword) s'il existe ; sinon la release reste signée avec la clé de
  debug (build local sans secrets) ;
- le **nom affiché** de l'application (`android:label`).

Idempotent ; gère `app/build.gradle` (Groovy) et `app/build.gradle.kts` (Kotlin DSL).
Usage : python3 tool/configurer_android.py [dossier_projet] (défaut : dossier courant).
"""
import pathlib
import re
import sys

LIBELLE = "Atelier Sprites"
MARQUE = "// atelier-sprites: signature release"

GROOVY_PROPS = f"""{MARQUE}
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {{
    keystorePropertiesFile.withReader("UTF-8") {{ reader -> keystoreProperties.load(reader) }}
}}

"""
GROOVY_SIGNING = """    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"])
                storePassword = keystoreProperties["storePassword"]
                keyAlias = keystoreProperties["keyAlias"]
                keyPassword = keystoreProperties["keyPassword"]
            }
        }
    }

"""
GROOVY_RELEASE = "signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug"

KTS_PROPS = f"""{MARQUE}
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {{
    keystorePropertiesFile.reader(Charsets.UTF_8).use {{ keystoreProperties.load(it) }}
}}

"""
KTS_SIGNING = """    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

"""
KTS_RELEASE = ('signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") '
               'else signingConfigs.getByName("debug")')


def configurer_gradle(chemin: pathlib.Path) -> None:
    texte = chemin.read_text(encoding="utf-8")
    if MARQUE in texte:
        print(f"{chemin} : déjà configuré")
        return
    kts = chemin.suffix == ".kts"
    props, signing, release = (KTS_PROPS, KTS_SIGNING, KTS_RELEASE) if kts else (GROOVY_PROPS, GROOVY_SIGNING, GROOVY_RELEASE)

    # Propriétés lues avant le bloc android { } (le bloc plugins { } doit rester en tête).
    m = re.search(r"^android\s*\{", texte, re.M)
    if not m:
        sys.exit(f"{chemin} : bloc android {{ }} introuvable")
    texte = texte[: m.start()] + props + texte[m.start():]

    # signingConfigs juste avant buildTypes.
    m = re.search(r"^(\s*)buildTypes\s*\{", texte, re.M)
    if not m:
        sys.exit(f"{chemin} : bloc buildTypes {{ }} introuvable")
    texte = texte[: m.start()] + signing + texte[m.start():]

    # La release utilise la clé de release quand key.properties existe.
    texte, n = re.subn(r"signingConfig\s*=\s*signingConfigs(\.debug|\.getByName\(\"debug\"\))", release, texte)
    if n != 1:
        sys.exit(f"{chemin} : signingConfig de release introuvable ({n} occurrence(s))")
    chemin.write_text(texte, encoding="utf-8")
    print(f"{chemin} : signature release configurée")


def configurer_manifeste(chemin: pathlib.Path) -> None:
    texte = chemin.read_text(encoding="utf-8")
    nouveau, n = re.subn(r'android:label="[^"]*"', f'android:label="{LIBELLE}"', texte, count=1)
    if n != 1:
        sys.exit(f"{chemin} : android:label introuvable")
    chemin.write_text(nouveau, encoding="utf-8")
    print(f"{chemin} : nom affiché « {LIBELLE} »")


def main() -> None:
    racine = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    app = racine / "android" / "app"
    gradle = next((p for p in (app / "build.gradle.kts", app / "build.gradle") if p.exists()), None)
    if gradle is None:
        sys.exit(f"{app} : build.gradle introuvable — lance d'abord `flutter create`.")
    configurer_gradle(gradle)
    configurer_manifeste(app / "src" / "main" / "AndroidManifest.xml")


if __name__ == "__main__":
    main()
