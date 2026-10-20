/// Export : construit les chemins du dépôt Zimut et écrit le zip.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../data/catalog.dart';
import '../models.dart';

class FichierExport {
  /// Chemin relatif dans le zip (ex. `prototype/zimut/assets/sprites/players/assassin.png`).
  final String chemin;

  /// Contenu PNG.
  final Uint8List octets;

  const FichierExport(this.chemin, this.octets);
}

/// Chemins de sortie d'un fichier dans le dépôt Zimut.
///
/// Héros : en plus du dossier `players/`, le repos de face est copié vers
/// `nations/heros/<id>.png` et les autres poses vers `nations/heros/poses/`
/// (miroir de la note d'export de `prompts_sprites`).
List<String> cheminsPour({
  required PersonnageCatalogue perso,
  required PlancheDef planche,
  required String nomFichier,
}) {
  final chemins = <String>['$racineAssets/${perso.dossier}/$nomFichier'];
  if (perso.grand && perso.dossier == 'players') {
    final reposFace = planche.type == TypePlanche.grandRepos &&
        nomFichier == '${perso.id}.png';
    if (reposFace) {
      chemins.add('$racineAssets/nations/heros/${perso.id}.png');
    } else {
      chemins.add('$racineAssets/nations/heros/poses/$nomFichier');
    }
  }
  return chemins;
}

/// Écrit le zip sur le stockage temporaire de l'appareil et retourne le fichier.
Future<File> ecrireZip(List<FichierExport> fichiers, String nomZip) async {
  final archive = Archive();
  for (final f in fichiers) {
    archive.addFile(ArchiveFile(f.chemin, f.octets.length, f.octets));
  }
  final octets = ZipEncoder().encode(archive);
  final dossier = await getTemporaryDirectory();
  final fichier = File('${dossier.path}/$nomZip');
  await fichier.writeAsBytes(octets, flush: true);
  return fichier;
}
