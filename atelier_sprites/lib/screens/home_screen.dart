/// Écran d'accueil : pipeline, rappels de méthode et lancement du workflow.
library;

import 'package:flutter/material.dart';

import '../data/catalog.dart';
import 'workflow_screen.dart';

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
          Text(
            'Transforme une planche de sprites générée par IA en PNG prêts '
            'pour le jeu : détourage, découpe, nommage des poses, export zip.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WorkflowScreen()),
            ),
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Importer une planche'),
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
                  Text('1. Importe la planche (fond blanc ou gris uni, jamais vert ou rose).'),
                  Text('2. La grille est détectée ; ajuste les séparateurs au doigt si besoin.'),
                  Text('3. Détourage : tolérance, bord doux, décontamination du halo.'),
                  Text('4. Choisis le personnage et la planche : les noms de poses '
                      's\'appliquent automatiquement (convention EntityView.gd).'),
                  Text('5. Exporte le zip et décompresse-le à la racine du dépôt Zimut.'),
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
                  Text('• Une seule vue par planche (3/4 avant ou 3/4 arrière).'),
                  Text('• Vérifie à l\'œil la grille produite par l\'IA (parfois 3×3 au lieu de 4×2).'),
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
}
