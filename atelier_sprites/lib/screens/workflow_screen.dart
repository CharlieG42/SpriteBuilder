/// Workflow complet : importer → grille → détourage → nommage → export zip.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import '../core/animations.dart';
import '../core/decoupe.dart';
import '../core/doublons.dart';
import '../core/intensite.dart';
import '../core/reglages_anim.dart';
import '../core/traitement.dart';
import '../data/catalog.dart';
import '../export/atelier_export.dart';
import '../models.dart';
import '../projet.dart';
import '../widgets/apercu_grille.dart';
import '../widgets/comparateur_detour.dart';
import '../widgets/damier.dart';
import 'animation_screen.dart';
import 'retouche_screen.dart';

/// Préparation d'une planche d'un projet personnage (grille, détourage,
/// poses, export de cette planche seule).
class WorkflowScreen extends StatefulWidget {
  final ProjetPersonnage projet;
  final PlancheProjet planche;

  const WorkflowScreen({super.key, required this.projet, required this.planche});

  @override
  State<WorkflowScreen> createState() => _WorkflowScreenState();
}

class _WorkflowScreenState extends State<WorkflowScreen> {
  // L'état vit dans le projet : on y revient depuis l'écran Personnage.
  PlancheProjet get _p => widget.planche;
  Uint8List? get _octets => _p.octets;
  String get _nomFichier => _p.nomFichier;
  int get _imageW => _p.imageW;
  int get _imageH => _p.imageH;
  Grille get _grille => _p.grille;
  set _grille(Grille g) => _p.grille = g;
  OptionsTraitement get _options => widget.projet.options;
  PersonnageCatalogue? get _perso => widget.projet.perso;
  PlancheDef? get _planche => _p.planche;
  set _planche(PlancheDef? d) => _p.planche = d;
  int get _premiereCase => _p.premiereCase;
  set _premiereCase(int v) => _p.premiereCase = v;
  Set<int> get _exclues => _p.exclues;
  Map<int, String> get _renommages => _p.renommages;
  Map<String, Uint8List> get _vignettes => _p.vignettes;
  set _vignettes(Map<String, Uint8List> v) => _p.vignettes = v;
  int get _pourcentageFond => _p.pourcentageFond;
  set _pourcentageFond(int v) => _p.pourcentageFond = v;
  List<Doublon> get _doublons => _p.doublons;
  set _doublons(List<Doublon> v) => _p.doublons = v;

  String _groupeChoisi = '';
  bool _occupe = false;
  int _etape = 0;

  // Aperçu du détourage en direct (recalculé après chaque réglage).
  ApercuDetour? _apercu;
  bool _calculApercu = false;
  int _seqApercu = 0;
  Timer? _attenteApercu;

  /// Zone de l'aperçu : -1 = planche entière, sinon index de case (zoom).
  int _zoneApercu = -1;

  @override
  void initState() {
    super.initState();
    _groupeChoisi = _perso?.groupe ?? '';
  }

  @override
  void dispose() {
    _attenteApercu?.cancel();
    // Arrivé aux poses : la planche est considérée comme vérifiée.
    if (_etape >= 2) _p.verifiee = true;
    super.dispose();
  }

  // --------------------------------------------------------------------------------------------
  // Import et grille
  // --------------------------------------------------------------------------------------------

  /// Remplace l'image de cette planche (les autres planches ne bougent pas).
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
      _p.octets = octets;
      _p.octetsOrigine = null;
      _p.forces = null;
      _apercu = null;
      _p.nomFichier = fichier.name;
      _p.imageW = source.width;
      _p.imageH = source.height;
      _p.verifiee = false;
      _exclues.clear();
      _renommages.clear();
      _invaliderApercus();
      _pourcentageFond = -1;
      _premiereCase = 1;
      _grille = detecterGrille(source, tolerance: _options.tolerance);
      final presel = preselDepuisNomFichier(fichier.name);
      if (_perso == null && presel.perso != null) {
        widget.projet.changerPerso(presel.perso!);
        _groupeChoisi = presel.perso!.groupe;
      }
      if (presel.planche != null && presel.perso == _perso) _planche = presel.planche;
      if (_planche?.type == TypePlanche.objets) {
        _prefillerObjets();
      }
    });
  }

  void _prefillerObjets() => _p.prefillerObjets();

  /// Les aperçus de cette planche ne correspondent plus aux réglages. Le
  /// détourage est commun : les aperçus des autres planches sont aussi périmés.
  void _invaliderApercus() {
    for (final pl in widget.projet.planches) {
      if (!identical(pl, _p)) pl.invaliderApercus();
    }
    final detour = _p.apercuDetour;
    _p.invaliderApercus();
    _p.apercuDetour = detour;
  }

  void _majGrille(Grille g) {
    setState(() {
      _grille = g;
      _apercu = null;
      _invaliderApercus();
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
      _apercu = null;
      _invaliderApercus();
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

  List<int> get _indicesInclus => _p.indicesInclus;
  String _nomPrevu(int index) => _p.nomPrevu(index, _perso!);
  String _libellePose(int index) => _p.libellePose(index);
  String? _suffixeCase(int index) => _p.suffixeCase(index);
  String _nomFinal(int index) => _p.nomFinal(index, _perso!);

  String _nomZip() {
    final id = _perso?.id ?? 'planche';
    final pl = _planche;
    final cle = pl?.cle ?? 'planche';
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
    widget.projet.changerPerso(p);
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
    setState(() => _renommages[index] = nom as String);
  }

  // --------------------------------------------------------------------------------------------
  // Traitement (isolates)
  // --------------------------------------------------------------------------------------------

  OptionsTraitement get _optionsApercu => _options.copie()..case512 = false;

  /// Relance l'aperçu du détourage après une courte pause (les curseurs
  /// envoient beaucoup de valeurs) ; seul le dernier calcul est affiché.
  void _planifierApercu({bool immediat = false}) {
    if (_octets == null) return;
    _attenteApercu?.cancel();
    _attenteApercu = Timer(Duration(milliseconds: immediat ? 0 : 450), _calculerApercu);
  }

  Future<void> _calculerApercu() async {
    if (_octets == null || !mounted) return;
    final seq = ++_seqApercu;
    setState(() => _calculApercu = true);
    try {
      final zone = _zoneApercu < _grille.nbCases ? _zoneApercu : -1;
      final demande = DemandeApercuDetour(
        construireDemande(_octets!, _grille, _optionsApercu, const <int>[], forces: _p.forces),
        caseIndex: zone,
        tailleMax: zone < 0 ? 1100 : 700,
      );
      final resultat = await compute(apercuDetourage, demande);
      if (!mounted || seq != _seqApercu) return;
      setState(() {
        _apercu = resultat;
        _pourcentageFond = resultat.pourcentageFond;
      });
    } catch (e) {
      if (seq == _seqApercu) _message('Échec du détourage : $e');
    } finally {
      if (mounted && seq == _seqApercu) setState(() => _calculApercu = false);
    }
  }

  /// Modifie un réglage de détourage : aperçus périmés, nouvel aperçu en direct.
  void _majDetourage(VoidCallback changement) {
    setState(() {
      changement();
      _invaliderApercus();
    });
    _planifierApercu();
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
        forces: _p.forces,
      );
      final resultat = await compute(traiterCases, demande);
      final doublons = await compute(detecterDoublons, <int, Uint8List>{
        for (final e in resultat.vignettes.entries) int.parse(e.key): e.value,
      });
      if (!mounted) return;
      setState(() {
        _vignettes = resultat.vignettes;
        _pourcentageFond = resultat.pourcentageFond;
        _doublons = doublons;
      });
    } catch (e) {
      _message('Échec de la découpe : $e');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<Map<int, Uint8List>> _imagesAnimation(bool ancrageSol) async {
    if (_p.cacheAnim != null && _p.cacheAnimSol == ancrageSol) return _p.cacheAnim!;
    final options = _options.copie()
      ..case512 = true
      ..ancrageSol = ancrageSol;
    final indices = <int>[for (var i = 0; i < _grille.nbCases; i++) i];
    final demande = construireDemande(
      _octets!,
      _grille,
      options,
      indices,
      tailleVignette: 320,
      ratioForce: widget.projet.ratioCommun,
      forces: _p.forces,
    );
    final resultat = await compute(traiterCases, demande);
    final images = <int, Uint8List>{
      for (final e in resultat.vignettes.entries) int.parse(e.key): e.value,
    };
    _p.cacheAnim = images;
    _p.cacheAnimSol = ancrageSol;
    return images;
  }

  Future<void> _ouvrirAnimations() async {
    if (_octets == null) return;
    final perso = _perso;
    final reglages = perso == null ? ReglagesAnim() : await MagasinReglages.lire(perso.id);
    if (!mounted) return;
    final inclus = _indicesInclus;
    if (inclus.isEmpty) {
      _message('Toutes les cases sont exclues.');
      return;
    }
    final suffixes = <int, String?>{for (final i in inclus) i: _suffixeCase(i)};
    final noms = <int, String>{
      for (final i in inclus) i: _planche == null || _perso == null ? 'case ${i + 1}' : _nomFinal(i),
    };
    final base = _perso == null
        ? 'planche'
        : (_planche?.vue == Vue.dos ? '${_perso!.id}_back' : _perso!.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnimationScreen(
          titre: _perso == null ? 'Aperçu des animations' : '${_perso!.libelle} — animations',
          nomBase: base,
          animations: animationsPour(suffixes),
          nomsCases: noms,
          ancrageSol: _options.ancrageSol,
          margeSol: _options.margeSol,
          charger: _imagesAnimation,
          onAncrageChange: (v) => setState(() => _options.ancrageSol = v),
          reglages: reglages,
          onReglagesChange: (r) {
            if (perso != null) MagasinReglages.ecrire(perso.id, r);
          },
        ),
      ),
    );
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
      final demande = construireDemande(
        _octets!,
        _grille,
        _options,
        inclus,
        ratioForce: widget.projet.ratioCommun,
        forces: _p.forces,
      );
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
      final reglages = await MagasinReglages.lire(_perso!.id);
      if (!reglages.estDefaut) {
        final json = Uint8List.fromList(utf8.encode(reglages.versJson()));
        for (final chemin in cheminsReglages(_perso!)) {
          fichiers.add(FichierExport(chemin, json));
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
        if (_apercu == null) _planifierApercu(immediat: true);
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
      appBar: AppBar(title: Text(_nomFichier, overflow: TextOverflow.ellipsis)),
      body: AbsorbPointer(
        absorbing: _occupe,
        child: Stack(
          children: [
            Stepper(
              currentStep: _etape,
              onStepTapped: (i) {
                setState(() => _etape = i);
                if (i == 1 && _apercu == null) _planifierApercu(immediat: true);
              },
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
    final theme = Theme.of(context);
    final niveau = niveauDe(_options);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Détourer le fond'),
          subtitle: const Text('Supprime le fond blanc/gris ; les zones claires enfermées dans le sprite sont conservées.'),
          value: _options.detourer,
          onChanged: (v) => _majDetourage(() => _options.detourer = v),
        ),
        if (_options.detourer) ...[
          Text('Intensité', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < niveauxDetourage.length; i++)
                ChoiceChip(
                  label: Text(niveauxDetourage[i].libelle),
                  selected: i == niveau,
                  onSelected: (_) => _majDetourage(() => appliquerNiveau(_options, i)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            niveau < 0 ? 'Réglage personnalisé (réglages fins ci-dessous).' : niveauxDetourage[niveau].aide,
            style: theme.textTheme.bodySmall,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Rognage du bord : ${_options.rognage > 0 ? '+' : ''}${_options.rognage} px'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: _options.rognage.toDouble(),
                  min: -3,
                  max: 6,
                  divisions: 9,
                  label: '${_options.rognage}',
                  onChanged: (v) => _majDetourage(() => _options.rognage = v.round()),
                ),
                Text('+ : grignote le liseré clair autour du sprite · − : rend du bord trop mangé',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Réglages fins'),
            subtitle: Text(
              'Tolérance ${_options.tolerance} · bord doux ${_options.douceur.toStringAsFixed(1)}'
              '${_options.decontaminer ? ' · anti-halo' : ''}${_options.interieurs ? ' · intérieurs' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            children: [
              ListTile(
                title: Text('Tolérance : ${_options.tolerance}'),
                subtitle: Slider(
                  value: _options.tolerance.toDouble(),
                  min: 5,
                  max: 140,
                  divisions: 27,
                  label: '${_options.tolerance}',
                  onChanged: (v) => _majDetourage(() => _options.tolerance = v.round()),
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
                  onChanged: (v) => _majDetourage(() => _options.douceur = v),
                ),
              ),
              SwitchListTile(
                title: const Text('Décontaminer le halo'),
                subtitle: const Text('Re-pousse la couleur du bord hors du blanc du fond.'),
                value: _options.decontaminer,
                onChanged: (v) => _majDetourage(() => _options.decontaminer = v),
              ),
              SwitchListTile(
                title: const Text('Détourer aussi les intérieurs'),
                subtitle: const Text('Retire le fond enfermé entre les membres (bras, jambes) ; les petites zones claires (yeux, reflets) sont conservées.'),
                value: _options.interieurs,
                onChanged: (v) => _majDetourage(() => _options.interieurs = v),
              ),
              if (_options.interieurs)
                ListTile(
                  title: Text('Aire min. d’une poche : ${_options.aireMinInterieur} px'),
                  subtitle: Slider(
                    value: _options.aireMinInterieur.toDouble(),
                    min: 4,
                    max: 400,
                    divisions: 99,
                    label: '${_options.aireMinInterieur}',
                    onChanged: (v) => _majDetourage(() => _options.aireMinInterieur = v.round()),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Aperçu', style: theme.textTheme.titleSmall),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: _zoneApercu < _grille.nbCases ? _zoneApercu : -1,
                items: [
                  const DropdownMenuItem(value: -1, child: Text('Planche entière')),
                  for (var i = 0; i < _grille.nbCases; i++)
                    DropdownMenuItem(value: i, child: Text('Case ${i + 1} (zoom)')),
                ],
                onChanged: (v) {
                  setState(() => _zoneApercu = v ?? -1);
                  _planifierApercu(immediat: true);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_apercu == null)
          SizedBox(
            height: 120,
            child: Center(
              child: _calculApercu
                  ? const CircularProgressIndicator()
                  : TextButton.icon(
                      onPressed: _octets == null ? null : () => _planifierApercu(immediat: true),
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Calculer l\'aperçu'),
                    ),
            ),
          )
        else
          ComparateurDetour(apercu: _apercu!, calcul: _calculApercu),
        if (_options.detourer && _pourcentageFond >= 0) ...[
          const SizedBox(height: 8),
          Text('Fond retiré : $_pourcentageFond % de l\'image.'),
          if (_pourcentageFond < 5)
            const Text('⚠ Fond à peine détecté : augmente l\'intensité ou vérifie le fond de la planche.',
                style: TextStyle(color: Colors.orange))
          else if (_pourcentageFond > 92)
            const Text('⚠ Presque tout a été supprimé : baisse l\'intensité.',
                style: TextStyle(color: Colors.orange)),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _octets == null ? null : _retoucher,
          icon: const Icon(Icons.brush),
          label: Text(_p.retouchee ? 'Retoucher à la main (retouches actives)' : 'Retoucher à la main…'),
        ),
        if (_p.retouchee)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _annulerRetouches,
              icon: const Icon(Icons.restore),
              label: const Text('Annuler toutes les retouches'),
            ),
          ),
        Text(
          'Pinceau, gomme, baguette magique, lasso : corrige à la main ce que le détourage automatique rate '
          '(zones claires mangées, fond resté).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Ouvre l'éditeur de retouche à la main sur la planche entière.
  Future<void> _retoucher() async {
    if (_octets == null) return;
    final r = await Navigator.of(context).push<ResultatRetouche>(
      MaterialPageRoute(
        builder: (_) => EcranRetouche(
          octets: _octets!,
          octetsOrigine: _p.octetsOrigine,
          forces: _p.forces,
          options: _optionsApercu,
          titre: _nomFichier,
        ),
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      if (r.vide) {
        _p.annulerRetouche();
      } else {
        _p.appliquerRetouche(r.octets, r.forces);
      }
      _apercu = null;
      _p.apercuDetour = null;
      _invaliderApercus();
      _pourcentageFond = -1;
    });
    _planifierApercu(immediat: true);
  }

  Future<void> _annulerRetouches() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler les retouches ?'),
        content: const Text('Retour à l\'image importée : pinceau, gomme et protections seront perdus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler les retouches')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _p.annulerRetouche();
      _apercu = null;
      _p.apercuDetour = null;
      _invaliderApercus();
      _pourcentageFond = -1;
    });
    _planifierApercu(immediat: true);
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
              helperText: 'Si la planche a été coupée en deux, numéro de la première pose importée.',
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
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _octets == null ? null : _ouvrirAnimations,
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('Aperçu des animations'),
        ),
        if (_vignettes.isEmpty && _octets != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aperçus pas encore générés…'),
          ),
        if (_doublons.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 8),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _doublons.any((d) => d.identique) ? 'Poses en double détectées' : 'Poses très proches',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  for (final d in _doublons.take(8))
                    Text('• Cases ${d.a + 1} et ${d.b + 1} : ${d.identique ? 'identiques' : 'très proches'} '
                        '(écart ${(d.distance * 100).toStringAsFixed(1)} %)'),
                  if (_doublons.length > 8) Text('… et ${_doublons.length - 8} autres paires'),
                  const SizedBox(height: 4),
                  const Text('Le mieux : régénérer la planche en insistant sur des poses différentes.'),
                  if (_doublons.any((d) => d.identique))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.filter_alt_off),
                        label: const Text('Exclure les doublons'),
                        onPressed: () => setState(() => _exclues.addAll(casesAExclure(_doublons))),
                      ),
                    ),
                ],
              ),
            ),
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
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  const Damier(taille: 6),
                                  Image.memory(
                                    _vignettes[index.toString()]!,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ],
                              ),
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
        SwitchListTile(
          title: const Text('Pieds alignés (ancrage au sol)'),
          subtitle: const Text('Pose le bas de chaque sprite sur la même ligne du carré : '
              'le personnage ne « saute » plus d\'une pose à l\'autre en jeu.'),
          value: _options.ancrageSol,
          onChanged: _options.case512 ? (v) => setState(() => _options.ancrageSol = v) : null,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _octets == null ? null : _ouvrirAnimations,
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Vérifier les animations avant l\'export'),
          ),
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
                  FutureBuilder<ReglagesAnim>(
                    future: MagasinReglages.lire(_perso!.id),
                    builder: (context, snap) {
                      final r = snap.data;
                      if (r == null || r.estDefaut || cheminsReglages(_perso!).isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Mouvement personnalisé : ${_perso!.id}_anim.txt ajouté au zip.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    },
                  ),
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
          label: const Text('Exporter cette planche seule (.zip)'),
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
