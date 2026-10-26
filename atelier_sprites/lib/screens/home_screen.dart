/// Écran d'accueil : pipeline, rappels de méthode et lancement du workflow.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/retouche.dart';
import '../data/catalog.dart';
import '../models.dart';
import 'personnage_screen.dart';
import 'retouche_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = catalogueParGroupe();
    return Scaffold(
      appBar: AppBar(title: const Text('Atelier Sprites — Zimut')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset('assets/icone/icone.png', width: 96, height: 96, filterQuality: FilterQuality.medium),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Transforme une planche de sprites générée par IA en PNG prêts '
            'pour le jeu : détourage, découpe, nommage des poses, export zip.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => PersonnageScreen.importerEtOuvrir(context),
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Importer des planches'),
          ),
          const SizedBox(height: 6),
          Text(
            'Sélectionne une ou plusieurs planches d\'un même personnage (face, dos, '
            'référence, planches de poses…) : elles sont exportées ensemble, '
            'à la même échelle, dans un seul zip.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Retouche et dessin', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Sans passer par les sprites : ouvre une image (ou pars d\'une page vierge), '
                    'dessine, détoure à la main, puis exporte en PNG ou JPG.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _ouvrirImage(context),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Ouvrir une image'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _nouvelleImage(context),
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('Nouvelle image'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Pipeline', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('1. Importe les planches du personnage (fond blanc ou gris uni, jamais vert ou rose).'),
                  Text('2. La grille est détectée ; ajuste les séparateurs au doigt si besoin.'),
                  Text('3. Détourage : tolérance, bord doux, décontamination du halo.'),
                  Text('4. Choisis le personnage et la planche : les noms de poses '
                      's\'appliquent automatiquement (convention EntityView.gd).'),
                  Text('5. Vérifie les contrôles (doublons, poses manquantes) et l\'aperçu des animations.'),
                  Text('6. Exporte le zip du personnage et décompresse-le à la racine du dépôt Zimut.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Rappels des pièges (prompts_sprites/README.md)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('• Jamais « transparent background » dans le générateur : faux damier garanti.'),
                  Text('• Fond gris #808080 pour les personnages clairs (Mage, Heal, Sylvain, boss Cristaux et Vents).'),
                  Text('• Pas d\'ombre au sol : le jeu dessine l\'ombre lui-même.'),
                  Text('• D\'abord la fiche de référence (repos face + dos), jointe ensuite à chaque planche.'),
                  Text('• Planches de 4 poses (2 × 2), une seule vue (3/4 avant ou 3/4 arrière).'),
                  Text('• Ni cadres, ni grille au sol : les poses doivent flotter sur le fond.'),
                  Text('• L\'Atelier signale les poses en double : régénère la planche plutôt que de les garder.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Catalogue embarqué', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final entree in catalog.entries)
            ListTile(
              dense: true,
              leading: const Icon(Icons.groups),
              title: Text(entree.key),
              trailing: Text('${entree.value.length} personnages'),
            ),
        ],
      ),
    );
  }

  /// Ouvre une image du téléphone dans l'éditeur (sans planche de sprites).
  static Future<void> _ouvrirImage(BuildContext context) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.single;
    final octets = f.bytes;
    if (octets == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EcranRetouche(octets: octets, options: OptionsTraitement(), titre: f.name, autonome: true),
      ),
    );
  }

  /// Page vierge : taille et fond au choix.
  static Future<void> _nouvelleImage(BuildContext context) async {
    final largeur = TextEditingController(text: '512');
    final hauteur = TextEditingController(text: '512');
    var fond = 0; // 0 transparent, 1 blanc, 2 noir
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nouvelle image'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: largeur,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Largeur (px)'),
                    ),
                  ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('×')),
                  Expanded(
                    child: TextField(
                      controller: hauteur,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Hauteur (px)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (final t in const [64, 128, 256, 512, 1024])
                    ActionChip(
                      label: Text('$t'),
                      onPressed: () {
                        largeur.text = '$t';
                        hauteur.text = '$t';
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Fond'),
              Wrap(
                spacing: 6,
                children: [
                  for (final (i, nom) in const [(0, 'Transparent'), (1, 'Blanc'), (2, 'Noir')])
                    ChoiceChip(
                      label: Text(nom),
                      selected: fond == i,
                      onSelected: (_) => setD(() => fond = i),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    final w = (int.tryParse(largeur.text) ?? 512).clamp(8, 4096).toInt();
    final h = (int.tryParse(hauteur.text) ?? 512).clamp(8, 4096).toInt();
    largeur.dispose();
    hauteur.dispose();
    if (ok != true || !context.mounted) return;
    final octets = await compute(
      imageVierge,
      (largeur: w, hauteur: h, fond: fond == 0 ? null : (fond == 1 ? 0xFFFFFF : 0x000000)),
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EcranRetouche(
          octets: octets,
          options: OptionsTraitement(),
          titre: 'image_${w}x$h',
          autonome: true,
          detourageParDefaut: false,
        ),
      ),
    );
  }
}
