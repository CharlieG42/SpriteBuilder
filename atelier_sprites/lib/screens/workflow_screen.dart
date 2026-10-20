/// Workflow complet : importer → grille → détourage → nommage → export zip.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import '../core/decoupe.dart';
import '../core/traitement.dart';
import '../data/catalog.dart';
import '../export/atelier_export.dart';
import '../models.dart';
import '../widgets/apercu_grille.dart';

class WorkflowScreen extends StatefulWidget {
  const WorkflowScreen({super.key});

  @override
  State<WorkflowScreen> createState() => _WorkflowScreenState();
}

class _WorkflowScreenState extends State<WorkflowScreen> {
  Uint8List? _octets;
  String _nomFichier = '';
  int _imageW = 0;
  int _imageH = 0;
  Grille _grille = Grille.uniforme(4, 2);
  final OptionsTraitement _options = OptionsTraitement();

  PersonnageCatalogue? _perso;
  PlancheDef? _planche;
  String _groupeChoisi = '';
  int _premiereCase = 1;

  final Set<int> _exclues = <int>{};
  final Map<int, String> _renommages = <int, String>{};
  Map<String, Uint8List> _vignettes = <String, Uint8List>{};
  Uint8List? _apercuDetour;
  int _pourcentageFond = -1;

  bool _occupe = false;
  int _etape = 0;

  // --------------------------------------------------------------------------------------------
  // Import et grille
  // --------------------------------------------------------------------------------------------

  Future<void> _importer() async {
    final resultat = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (resultat == null || resultat.files.isEmpty) return;
    final fichier = resultat.files.single;
    final octets = fichier.bytes;
    if (octets == null) return;
    final source = img.decodeImage(octets);
    if (source == null) {
      _message('Image illisible.');
      return;
    }
    setState(() {
      _octets = octets;
      _nomFichier = fichier.name;
      _imageW = source.width;
      _imageH = source.height;
      _exclues.clear();
      _renommages.clear();
      _vignettes = <String, Uint8List>{};
      _apercuDetour = null;
      _pourcentageFond = -1;
      _premiereCase = 1;
      _grille = detecterGrille(source, tolerance: _options.tolerance);
      final presel = preselDepuisNomFichier(fichier.name);
      _perso = presel.perso;
      _planche = presel.planche;
      _groupeChoisi = _perso?.groupe ?? '';
      if (_planche?.type == TypePlanche.objets) {
        _prefillerObjets();
      }
    });
  }

  void _prefillerObjets() {
    for (var i = 0; i < _grille.nbCases && i < mecanismes.length; i++) {
      _renommages[i] = mecanismes[i].id;
    }
  }

  void _majGrille(Grille g) {
    setState(() {
      _grille = g;
      _vignettes = <String, Uint8List>{};
      _exclues.clear();
      _renommages.clear();
      if (_planche?.type == TypePlanche.objets) {
        _prefillerObjets();
      }
    });
  }

  void _majDimensions(int cols, int rows) {
    setState(() {
      _grille = Grille.uniforme(cols, rows);
      _vignettes = <String, Uint8List>{};
      _exclues.clear();
      _renommages.clear();
      if (_planche?.type == TypePlanche.objets) {
        _prefillerObjets();
      }
    });
  }

  // --------------------------------------------------------------------------------------------
  // Nommage
  // --------------------------------------------------------------------------------------------

  List<int> get _indicesInclus => <int>[
        for (var i = 0; i < _grille.nbCases; i++)
          if (!_exclues.contains(i)) i,
      ];

  String _nomPrevu(int index) {
    final pl = _planche!;
    if (pl.type == TypePlanche.objets) {
      final renom = _renommages[index] ?? '';
      return renom.isEmpty ? 'objet_${index + 1}' : renom;
    }
    final rang = _indicesInclus.indexOf(index);
    final position = _premiereCase - 1 + rang;
    if (position < 0 || position >= pl.suffixes.length) {
      return nomFichierPour(
        id: _perso!.id,
        planche: pl,
        suffix: '_${index + 1}',
      );
    }
    return nomFichierPour(id: _perso!.id, planche: pl, suffix: pl.suffixes[position]);
  }

  String _libellePose(int index) {
    final pl = _planche!;
    if (pl.type == TypePlanche.objets) return 'objet';
    final rang = _indicesInclus.indexOf(index);
    final position = _premiereCase - 1 + rang;
    if (position < 0 || position >= pl.libellesPoses.length) return 'case ${index + 1}';
    return pl.libellesPoses[position];
  }

  String _nomFinal(int index) {
    final renom = _renommages[index] ?? '';
    if (renom.isNotEmpty) return renom.endsWith('.png') ? renom : '$renom.png';
    return _nomPrevu(index);
  }

  String _nomZip() {
    final id = _perso?.id ?? 'planche';
    final pl = _planche;
    final cle = switch (pl?.type) {
      TypePlanche.grandRepos => (pl?.vue == Vue.dos) ? 'dos_repos' : 'face_repos',
      TypePlanche.grandAttaques => (pl?.vue == Vue.dos) ? 'dos_attaques' : 'face_attaques',
      TypePlanche.petitTout => (pl?.vue == Vue.dos) ? 'dos' : 'face',
      TypePlanche.objets => 'objets',
      null => 'planche',
    };
    return 'zimut_sprites_${id}_$cle.zip';
  }

  void _selectionnerGroupe(String? groupe) {
    if (groupe == null) return;
    final catalog = catalogueParGroupe();
    setState(() {
      _groupeChoisi = groupe;
      final liste = catalog[groupe] ?? const <PersonnageCatalogue>[];
      if (liste.isNotEmpty && !liste.contains(_perso)) {
        _selectionnerPersoInterne(liste.first);
      }
    });
  }

  void _selectionnerPersoInterne(PersonnageCatalogue p) {
    final planches = planchesPour(p);
    _perso = p;
    _planche = planches.contains(_planche) ? _planche : planches.first;
    _premiereCase = 1;
    _renommages.clear();
    if (_planche!.type == TypePlanche.objets) {
      _prefillerObjets();
    }
  }

  void _selectionnerPerso(PersonnageCatalogue? p) {
    if (p == null) return;
    setState(() => _selectionnerPersoInterne(p));
  }

  void _selectionnerPlanche(PlancheDef? pl) {
    if (pl == null) return;
    setState(() {
      _planche = pl;
      _premiereCase = 1;
      _renommages.clear();
      if (pl.type == TypePlanche.objets) {
        _prefillerObjets();
      }
    });
  }

  Future<void> _renommer(int index) async {
    final controleur = TextEditingController(text: _renommages[index] ?? _nomPrevu(index));
    String? nom;
    if (_planche?.type == TypePlanche.objets) {
      nom = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('Objet de la case ${index + 1}'),
          children: [
            for (final m in mecanismes)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, m.id),
                child: Text('${m.libelle} (${m.id})'),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: controleur,
                decoration: const InputDecoration(
                  labelText: 'Ou saisir un identifiant libre',
                ),
                onSubmitted: (v) => Navigator.pop(context, v.trim()),
              ),
            ),
          ],
        ),
      );
    } else {
      nom = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Nom de la case ${index + 1}'),
          content: TextField(
            controller: controleur,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nom de fichier (sans .png)',
            ),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            FilledButton(
              onPressed: () => Navigator.pop(context, controleur.text.trim()),
              child: const Text('Valider'),
            ),
          ],
        ),
      );
    }
    if (nom == null) return;
    setState(() => _renommages[index] = nom);
  }

  // --------------------------------------------------------------------------------------------
  // Traitement (isolates)
  // --------------------------------------------------------------------------------------------

  OptionsTraitement get _optionsApercu {
    final o = OptionsTraitement();
    o.detourer = _options.detourer;
    o.tolerance = _options.tolerance;
    o.douceur = _options.douceur;
    o.decontaminer = _options.decontaminer;
    o.case512 = false;
    return o;
  }

  Future<void> _previsualiserDetourage() async {
    if (_octets == null) return;
    setState(() => _occupe = true);
    try {
      final demande = construireDemande(
        _octets!,
        Grille.uniforme(1, 1),
        _optionsApercu,
        <int>[0],
        tailleVignette: 1400,
      );
      final resultat = await compute(traiterCases, demande);
      if (!mounted) return;
      setState(() {
        _apercuDetour = resultat.vignettes['0'];
        _pourcentageFond = resultat.pourcentageFond;
      });
    } catch (e) {
      _message('Échec du détourage : $e');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _genererVignettes() async {
    if (_octets == null) return;
    setState(() => _occupe = true);
    try {
      final indices = <int>[for (var i = 0; i < _grille.nbCases; i++) i];
      final demande = construireDemande(
        _octets!,
        _grille,
        _optionsApercu,
        indices,
        tailleVignette: 160,
      );
      final resultat = await compute(traiterCases, demande);
      if (!mounted) return;
      setState(() {
        _vignettes = resultat.vignettes;
        _pourcentageFond = resultat.pourcentageFond;
      });
    } catch (e) {
      _message('Échec de la découpe : $e');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _exporter() async {
    if (_octets == null || _perso == null || _planche == null) return;
    final inclus = _indicesInclus;
    if (inclus.isEmpty) {
      _message('Toutes les cases sont exclues.');
      return;
    }
    setState(() => _occupe = true);
    try {
      final demande = construireDemande(_octets!, _grille, _options, inclus);
      final resultat = await compute(traiterCases, demande);
      final fichiers = <FichierExport>[];
      for (final index in inclus) {
        final png = resultat.vignettes[index.toString()];
        if (png == null) continue;
        final nom = _nomFinal(index);
        for (final chemin in cheminsPour(
          perso: _perso!,
          planche: _planche!,
          nomFichier: nom,
        )) {
          fichiers.add(FichierExport(chemin, png));
        }
      }
      final nomZip = _nomZip();
      final fichier = await ecrireZip(fichiers, nomZip);
      await Share.shareXFiles(
        <XFile>[XFile(fichier.path, mimeType: 'application/zip')],
        text: 'Sprites Zimut — $nomZip (${fichiers.length} fichiers)',
      );
      if (mounted) {
        _message('${fichiers.length} fichiers exportés dans $nomZip.');
      }
    } catch (e) {
      _message('Échec de l\'export : $e');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  // --------------------------------------------------------------------------------------------
  // Navigation
  // --------------------------------------------------------------------------------------------

  void _continuer() {
    switch (_etape) {
      case 0:
        if (_octets == null) {
          _message('Importe d\'abord une planche.');
          return;
        }
        setState(() => _etape = 1);
      case 1:
        setState(() => _etape = 2);
        _genererVignettes();
      case 2:
        if (_perso == null || _planche == null) {
          _message('Choisis le personnage et la planche.');
          return;
        }
        setState(() => _etape = 3);
      default:
        break;
    }
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  // --------------------------------------------------------------------------------------------
  // Interface
  // --------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Atelier Sprites')),
      body: AbsorbPointer(
        absorbing: _occupe,
        child: Stack(
          children: [
            Stepper(
              currentStep: _etape,
              onStepTapped: (i) => setState(() => _etape = i),
              physics: const ClampingScrollPhysics(),
              controlsBuilder: (context, details) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    if (_etape > 0)
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: const Text('Retour'),
                      ),
                    const Spacer(),
                    if (_etape < 3)
                      FilledButton(
                        onPressed: details.onStepContinue,
                        child: const Text('Suivant'),
                      ),
                  ],
                ),
              ),
              onStepCancel: () => setState(() {
                if (_etape > 0) _etape--;
              }),
              onStepContinue: _continuer,
              steps: [
                Step(
                  title: const Text('Planche & grille'),
                  isActive: _etape >= 0,
                  state: _etape == 0 ? StepState.editing : StepState.complete,
                  content: _etapePlanche(),
                ),
                Step(
                  title: const Text('Détourage'),
                  isActive: _etape >= 1,
                  state: _etape == 1 ? StepState.editing : (_etape > 1 ? StepState.complete : StepState.indexed),
                  content: _etapeDetourage(),
                ),
                Step(
                  title: const Text('Personnage & poses'),
                  isActive: _etape >= 2,
                  state: _etape == 2 ? StepState.editing : (_etape > 2 ? StepState.complete : StepState.indexed),
                  content: _etapePerso(),
                ),
                Step(
                  title: const Text('Export'),
                  isActive: _etape >= 3,
                  state: _etape == 3 ? StepState.editing : StepState.indexed,
                  content: _etapeExport(),
                ),
              ],
            ),
            if (_occupe)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Widget _etapePlanche() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_octets == null)
                  const Text('Importe la planche générée (fond blanc ou gris uni, jamais vert ou rose).')
                else
                  Text(
                    '$_nomFichier — ${_imageW}×${_imageH} px',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _importer,
                  icon: const Icon(Icons.upload_file),
                  label: Text(_octets == null ? 'Importer une planche' : 'Changer de planche'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_octets != null) ...[
          ApercuGrille(
            octets: _octets!,
            imageW: _imageW,
            imageH: _imageH,
            grille: _grille,
            exclues: _exclues,
            onChanged: _majGrille,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _grille.cols,
                  decoration: const InputDecoration(labelText: 'Colonnes'),
                  items: [
                    for (var c = 1; c <= 6; c++) DropdownMenuItem(value: c, child: Text('$c')),
                  ],
                  onChanged: (c) => _majDimensions(c ?? 4, _grille.rows),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _grille.rows,
                  decoration: const InputDecoration(labelText: 'Lignes'),
                  items: [
                    for (var r = 1; r <= 6; r++) DropdownMenuItem(value: r, child: Text('$r')),
                  ],
                  onChanged: (r) => _majDimensions(_grille.cols, r ?? 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Déplace les séparateurs au doigt si deux poses se touchent '
            '(piège observé sur les planches précédentes). La grille a été '
            'détectée automatiquement à l\'import.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _etapeDetourage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('Détourer le fond'),
          subtitle: const Text('Supprime le fond blanc/gris ; les zones claires enfermées dans le sprite sont conservées.'),
          value: _options.detourer,
          onChanged: (v) => setState(() {
            _options.detourer = v;
            _apercuDetour = null;
            _vignettes = <String, Uint8List>{};
          }),
        ),
        if (_options.detourer) ...[
          ListTile(
            title: Text('Tolérance : ${_options.tolerance}'),
            subtitle: Slider(
              value: _options.tolerance.toDouble(),
              min: 10,
              max: 140,
              divisions: 26,
              label: '${_options.tolerance}',
              onChanged: (v) => setState(() {
                _options.tolerance = v.round();
                _apercuDetour = null;
                _vignettes = <String, Uint8List>{};
              }),
            ),
          ),
          ListTile(
            title: Text('Bord doux : ${_options.douceur.toStringAsFixed(1)}'),
            subtitle: Slider(
              value: _options.douceur,
              min: 0,
              max: 3,
              divisions: 12,
              label: _options.douceur.toStringAsFixed(1),
              onChanged: (v) => setState(() {
                _options.douceur = v;
                _apercuDetour = null;
                _vignettes = <String, Uint8List>{};
              }),
            ),
          ),
          SwitchListTile(
            title: const Text('Décontaminer le halo'),
            subtitle: const Text('Re-pousse la couleur du bord hors du blanc du fond.'),
            value: _options.decontaminer,
            onChanged: (v) => setState(() {
              _options.decontaminer = v;
              _apercuDetour = null;
              _vignettes = <String, Uint8List>{};
            }),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _octets == null ? null : _previsualiserDetourage,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Prévisualiser le détourage'),
          ),
          if (_apercuDetour != null) ...[
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: _imageW / _imageH,
              child: Image.memory(_apercuDetour!, fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ],
          if (_pourcentageFond >= 0) ...[
            const SizedBox(height: 8),
            Text('Fond retiré : $_pourcentageFond % de l\'image.'),
            if (_pourcentageFond < 5)
              const Text('⚠ Fond à peine détecté : augmente la tolérance ou vérifie le fond de la planche.',
                  style: TextStyle(color: Colors.orange))
            else if (_pourcentageFond > 92)
              const Text('⚠ Presque tout a été supprimé : baisse la tolérance.',
                  style: TextStyle(color: Colors.orange)),
          ],
        ],
      ],
    );
  }

  Widget _etapePerso() {
    final catalog = catalogueParGroupe();
    final groupes = catalog.keys.toList()..sort();
    final persosDuGroupe = catalog[_groupeChoisi] ?? const <PersonnageCatalogue>[];
    final planches = _perso == null ? const <PlancheDef>[] : planchesPour(_perso!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _groupeChoisi.isEmpty ? groupes.first : _groupeChoisi,
          decoration: const InputDecoration(labelText: 'Groupe'),
          items: [
            for (final g in groupes) DropdownMenuItem(value: g, child: Text(g)),
          ],
          onChanged: _selectionnerGroupe,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<PersonnageCatalogue>(
          value: _perso,
          decoration: const InputDecoration(labelText: 'Personnage'),
          items: [
            for (final p in persosDuGroupe) DropdownMenuItem(value: p, child: Text(p.libelle)),
          ],
          onChanged: _selectionnerPerso,
        ),
        const SizedBox(height: 8),
        if (planches.isNotEmpty)
          DropdownButtonFormField<PlancheDef>(
            value: _planche,
            decoration: const InputDecoration(labelText: 'Planche'),
            items: [
              for (final pl in planches) DropdownMenuItem(value: pl, child: Text(pl.libelle)),
            ],
            onChanged: _selectionnerPlanche,
          ),
        if (_planche != null && _planche!.type != TypePlanche.objets) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _premiereCase,
            decoration: const InputDecoration(
              labelText: 'Première case de la planche',
              helperText: 'Mets 5 si tu importes la moitié droite d\'une planche 4×2.',
            ),
            items: [
              for (var i = 1; i <= _planche!.nbCases; i++) DropdownMenuItem(value: i, child: Text('Case $i')),
            ],
            onChanged: (v) => setState(() => _premiereCase = v ?? 1),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _octets == null ? null : _genererVignettes,
          icon: const Icon(Icons.grid_view),
          label: const Text('Régénérer les aperçus'),
        ),
        if (_vignettes.isEmpty && _octets != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aperçus pas encore générés…'),
          ),
        if (_vignettes.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                for (var index = 0; index < _grille.nbCases; index++)
                  ListTile(
                    dense: true,
                    leading: _vignettes[index.toString()] == null
                        ? const SizedBox(width: 48, height: 48)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.memory(
                              _vignettes[index.toString()]!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ),
                    title: Text('Case ${index + 1} — ${_planche == null ? '' : _libellePose(index)}'),
                    subtitle: Text(_planche == null ? '' : _nomFinal(index)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Renommer',
                          icon: const Icon(Icons.edit),
                          onPressed: _planche == null ? null : () => _renommer(index),
                        ),
                        Switch(
                          value: !_exclues.contains(index),
                          onChanged: (v) => setState(() {
                            if (v) {
                              _exclues.remove(index);
                            } else {
                              _exclues.add(index);
                            }
                          }),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _etapeExport() {
    final inclus = _indicesInclus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('Cases carrées de 512 px'),
          subtitle: const Text('Recommandé : chaque case est recentrée sur un carré transparent de 512 px.'),
          value: _options.case512,
          onChanged: (v) => setState(() => _options.case512 = v),
        ),
        if (_perso != null && _planche != null) ...[
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_perso!.libelle} — ${_planche!.libelle}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Zip : ${_nomZip()}'),
                  const SizedBox(height: 8),
                  for (final index in inclus)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_nomFinal(index), style: const TextStyle(fontWeight: FontWeight.w600)),
                          for (final chemin in cheminsPour(
                            perso: _perso!,
                            planche: _planche!,
                            nomFichier: _nomFinal(index),
                          ))
                            Text(chemin, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        FilledButton.icon(
          onPressed: (_octets == null || _perso == null || _planche == null || inclus.isEmpty)
              ? null
              : _exporter,
          icon: const Icon(Icons.folder_zip),
          label: const Text('Exporter pour Zimut (.zip)'),
        ),
        const SizedBox(height: 8),
        Text(
          'Décompresse le zip à la racine du dépôt Zimut : les PNG se rangent '
          'directement dans prototype/zimut/assets/sprites/. Le jeu les prend '
          'sans changer le code.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
