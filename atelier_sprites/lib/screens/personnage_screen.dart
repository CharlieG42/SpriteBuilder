/// Écran « Personnage » : toutes les planches d'un personnage (grilles
/// différentes possibles), contrôles avant export et zip unique.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/animations.dart';
import '../core/decoupe.dart';
import '../core/reglages_anim.dart';
import '../core/traitement.dart';
import '../data/catalog.dart';
import '../export/atelier_export.dart';
import '../models.dart';
import '../projet.dart';
import 'animation_screen.dart';
import 'workflow_screen.dart';

class PersonnageScreen extends StatefulWidget {
  final ProjetPersonnage projet;

  const PersonnageScreen({super.key, required this.projet});

  /// Ouvre le sélecteur (une ou plusieurs images) puis l'écran Personnage.
  static Future<void> importerEtOuvrir(BuildContext context) async {
    final projet = ProjetPersonnage();
    final ajoutees = await ajouterPlanches(context, projet);
    if (ajoutees == 0 || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PersonnageScreen(projet: projet)),
    );
  }

  /// Importe des images dans [projet] : grille détectée, personnage et type
  /// de planche présélectionnés depuis le nom de fichier. Retourne le nombre ajouté.
  static Future<int> ajouterPlanches(BuildContext context, ProjetPersonnage projet) async {
    final resultat = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );
    if (resultat == null || resultat.files.isEmpty) return 0;
    final messager = ScaffoldMessenger.maybeOf(context);
    var ajoutees = 0;
    final illisibles = <String>[];
    for (final f in resultat.files) {
      final octets = f.bytes;
      if (octets == null) continue;
      final analyse = await compute(analyserPlanche, octets);
      if (analyse == null) {
        illisibles.add(f.name);
        continue;
      }
      final presel = preselDepuisNomFichier(f.name);
      if (projet.perso == null && presel.perso != null) projet.changerPerso(presel.perso!);
      final def = (presel.perso != null && presel.perso == projet.perso) ? presel.planche : null;
      final pl = PlancheProjet(
        octets: octets,
        nomFichier: f.name,
        imageW: analyse.largeur,
        imageH: analyse.hauteur,
        grille: Grille.uniforme(analyse.cols, analyse.rows),
        planche: def,
      );
      if (def != null) {
        pl.premiereCase = projet.premiereCaseSuggeree(def);
        if (def.type == TypePlanche.objets) pl.prefillerObjets();
      }
      projet.planches.add(pl);
      ajoutees++;
    }
    if (illisibles.isNotEmpty) {
      messager?.showSnackBar(SnackBar(content: Text('Images illisibles : ${illisibles.join(', ')}')));
    }
    return ajoutees;
  }

  @override
  State<PersonnageScreen> createState() => _PersonnageScreenState();
}

class _PersonnageScreenState extends State<PersonnageScreen> {
  ProjetPersonnage get _projet => widget.projet;
  bool _occupe = false;
  String _progression = '';
  ReglagesAnim _reglages = ReglagesAnim();

  @override
  void initState() {
    super.initState();
    _chargerReglages();
  }

  Future<void> _chargerReglages() async {
    final p = _projet.perso;
    final r = p == null ? ReglagesAnim() : await MagasinReglages.lire(p.id);
    if (mounted) setState(() => _reglages = r);
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  // ------------------------------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------------------------------

  Future<void> _ajouter() async {
    setState(() => _occupe = true);
    try {
      await PersonnageScreen.ajouterPlanches(context, _projet);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
    _chargerReglages();
  }

  Future<void> _ouvrir(PlancheProjet pl) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => WorkflowScreen(projet: _projet, planche: pl)),
    );
    if (!mounted) return;
    setState(() {});
    _chargerReglages();
  }

  void _retirer(PlancheProjet pl) {
    setState(() => _projet.planches.remove(pl));
  }

  void _attribuer(PlancheProjet pl, PlancheDef? def) {
    setState(() {
      pl.planche = def;
      pl.renommages.clear();
      pl.premiereCase = def == null ? 1 : _projet.premiereCaseSuggeree(def, sauf: pl);
      if (def?.type == TypePlanche.objets) pl.prefillerObjets();
      pl.invaliderApercus();
    });
  }

  Future<void> _choisirPerso() async {
    final catalog = catalogueParGroupe();
    final groupes = catalog.keys.toList()..sort();
    final choix = await showDialog<PersonnageCatalogue>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Personnage'),
        children: [
          for (final g in groupes) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(g, style: Theme.of(context).textTheme.labelLarge),
            ),
            for (final p in catalog[g]!)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, p),
                child: Text(p.libelle, style: TextStyle(
                  fontWeight: p == _projet.perso ? FontWeight.bold : null,
                )),
              ),
          ],
        ],
      ),
    );
    if (choix == null) return;
    setState(() => _projet.changerPerso(choix));
    _chargerReglages();
  }

  // ------------------------------------------------------------------------------------------
  // Aperçu combiné
  // ------------------------------------------------------------------------------------------

  /// Clé globale d'une case : unique entre planches.
  static int _cle(int planche, int cas) => planche * 100 + cas;

  void _ouvrirAnimations() {
    final perso = _projet.perso;
    final planches = _projet.planchesExportables;
    if (perso == null || planches.isEmpty) {
      _message('Attribue au moins une planche.');
      return;
    }
    // Vue → cases (clé globale) triées par position dans la convention.
    final parVue = <String, List<(int, int, String?)>>{};
    final noms = <int, String>{};
    for (final pl in planches) {
      final ip = _projet.planches.indexOf(pl);
      for (final i in pl.indicesInclus) {
        final cle = _cle(ip, i);
        noms[cle] = pl.nomFinal(i, perso);
        final brut = pl.suffixeCase(i);
        if (brut == null) {
          // Pose hors convention : visible dans « Toutes les cases » seulement.
          parVue.putIfAbsent(pl.planche!.vue == Vue.dos ? 'Dos' : 'Face', () => []).add((99999 + cle, cle, null));
          continue;
        }
        // Les poses d'une même animation peuvent venir de planches différentes
        // (V36) : on les classe par vue réelle et par numéro de pose.
        final p = vueDeLaPose(plancheDos: pl.planche!.vue == Vue.dos, suffixe: brut);
        parVue.putIfAbsent(p.dos ? 'Dos' : 'Face', () => []).add((rangDePose(p.suffixe), cle, p.suffixe));
      }
    }
    final groupes = <String, Map<int, String?>>{};
    for (final v in const ['Face', 'Dos']) {
      final l = parVue[v];
      if (l == null) continue;
      l.sort((a, b) => a.$1.compareTo(b.$1));
      groupes[v] = {for (final e in l) e.$2: e.$3};
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnimationScreen(
          titre: '${perso.libelle} — animations',
          nomBase: perso.id,
          animations: animationsProjet(groupes),
          nomsCases: noms,
          ancrageSol: _projet.options.ancrageSol,
          margeSol: _projet.options.margeSol,
          charger: _imagesAnimation,
          onAncrageChange: (v) => setState(() => _projet.options.ancrageSol = v),
          reglages: _reglages,
          onReglagesChange: (r) {
            _reglages = r;
            MagasinReglages.ecrire(perso.id, r);
          },
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<Map<int, Uint8List>> _imagesAnimation(bool ancrageSol) async {
    final ratio = _projet.ratioCommun;
    final options = _projet.options.copie()
      ..case512 = true
      ..ancrageSol = ancrageSol;
    final images = <int, Uint8List>{};
    for (final pl in _projet.planchesExportables) {
      final ip = _projet.planches.indexOf(pl);
      if (pl.cacheAnim == null || pl.cacheAnimSol != ancrageSol) {
        final indices = <int>[for (var i = 0; i < pl.grille.nbCases; i++) i];
        final res = await compute(
          traiterCases,
          construireDemande(pl.octets, pl.grille, options, indices, tailleVignette: 320, ratioForce: ratio, forces: pl.forces),
        );
        pl.cacheAnim = {for (final e in res.vignettes.entries) int.parse(e.key): e.value};
        pl.cacheAnimSol = ancrageSol;
      }
      for (final i in pl.indicesInclus) {
        final png = pl.cacheAnim![i];
        if (png != null) images[_cle(ip, i)] = png;
      }
    }
    return images;
  }

  // ------------------------------------------------------------------------------------------
  // Export
  // ------------------------------------------------------------------------------------------

  Future<void> _exporter() async {
    final perso = _projet.perso;
    if (perso == null) return;
    final planches = _projet.planchesExportables;
    if (planches.isEmpty) return;
    setState(() {
      _occupe = true;
      _progression = '';
    });
    try {
      final ratio = _projet.ratioCommun;
      final fichiers = <FichierExport>[];
      for (var k = 0; k < planches.length; k++) {
        final pl = planches[k];
        if (mounted) setState(() => _progression = 'Planche ${k + 1}/${planches.length}…');
        final inclus = pl.indicesInclus;
        final res = await compute(
          traiterCases,
          construireDemande(pl.octets, pl.grille, _projet.options, inclus, ratioForce: ratio, forces: pl.forces),
        );
        for (final i in inclus) {
          final png = res.vignettes[i.toString()];
          if (png == null) continue;
          final nom = pl.nomFinal(i, perso);
          for (final chemin in cheminsPour(perso: perso, planche: pl.planche!, nomFichier: nom)) {
            fichiers.add(FichierExport(chemin, png));
          }
        }
      }
      final reglages = await MagasinReglages.lire(perso.id);
      if (!reglages.estDefaut) {
        final json = Uint8List.fromList(utf8.encode(reglages.versJson()));
        for (final chemin in cheminsReglages(perso)) {
          fichiers.add(FichierExport(chemin, json));
        }
      }
      final nomZip = _projet.nomZip;
      final fichier = await ecrireZip(fichiers, nomZip);
      await Share.shareXFiles(
        <XFile>[XFile(fichier.path, mimeType: 'application/zip')],
        text: 'Sprites Zimut — $nomZip (${fichiers.length} fichiers)',
      );
      _message('${fichiers.length} fichiers exportés dans $nomZip.');
    } catch (e) {
      _message('Échec de l\'export : $e');
    } finally {
      if (mounted) {
        setState(() {
          _occupe = false;
          _progression = '';
        });
      }
    }
  }

  // ------------------------------------------------------------------------------------------
  // Interface
  // ------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perso = _projet.perso;
    final alertes = controlerProjet(_projet);
    final bloque = alertes.any((a) => a.bloquante) || _projet.planchesExportables.isEmpty;
    final nbFichiers = perso == null
        ? 0
        : _projet.planchesExportables.fold<int>(
            0,
            (n, pl) => n +
                pl.indicesInclus.fold<int>(
                    0,
                    (m, i) =>
                        m + cheminsPour(perso: perso, planche: pl.planche!, nomFichier: pl.nomFinal(i, perso)).length),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(perso?.libelle ?? 'Personnage'),
        actions: [
          IconButton(
            tooltip: 'Ajouter des planches',
            onPressed: _occupe ? null : _ajouter,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _occupe,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(perso == null ? 'Personnage à choisir' : perso.libelle),
                    subtitle: Text(perso == null
                        ? 'Non reconnu dans les noms de fichiers'
                        : '${perso.groupe} · ${perso.id} · ${planchesPour(perso).length} planche(s) prévue(s)'),
                    trailing: const Icon(Icons.edit),
                    onTap: _choisirPerso,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Planches (${_projet.planches.length})', style: theme.textTheme.titleMedium),
                Text(
                  'Touche une planche pour régler sa grille, ses cases et ses poses. '
                  'Le détourage et l\'export (carré 512, pieds alignés) sont communs.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                for (final pl in _projet.planches) _carte(theme, pl),
                OutlinedButton.icon(
                  onPressed: _ajouter,
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter des planches'),
                ),
                const SizedBox(height: 12),
                _options(theme),
                const SizedBox(height: 12),
                _controles(theme, alertes),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _projet.planchesExportables.isEmpty || perso == null ? null : _ouvrirAnimations,
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Aperçu des animations (toutes les planches)'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: bloque ? null : _exporter,
                  icon: const Icon(Icons.folder_zip),
                  label: Text(bloque ? 'Exporter (corrige les points bloquants)' : 'Exporter le personnage ($nbFichiers PNG)'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Un seul zip, à décompresser à la racine du dépôt Zimut. Toutes les planches '
                  'partagent la même échelle et la même ligne de sol : le personnage garde '
                  'la même taille d\'une pose à l\'autre.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (_occupe)
              Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        if (_progression.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(_progression),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _carte(ThemeData theme, PlancheProjet pl) {
    final perso = _projet.perso;
    final defs = perso == null ? const <PlancheDef>[] : planchesPour(perso);
    final (String etat, Color couleur) = pl.planche == null
        ? ('À attribuer', theme.colorScheme.error)
        : pl.verifiee
            ? ('Prête', Colors.green.shade700)
            : ('À vérifier', Colors.orange.shade800);
    final exclues = pl.exclues.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _ouvrir(pl),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      pl.octets,
                      width: 96,
                      height: 64,
                      fit: BoxFit.cover,
                      cacheWidth: 240,
                      gaplessPlayback: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pl.nomFichier, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          'Grille ${pl.grille.cols}×${pl.grille.rows} · ${pl.grille.nbCases} cases'
                          '${exclues > 0 ? ' ($exclues exclue${exclues > 1 ? 's' : ''})' : ''}'
                          '${pl.premiereCase > 1 ? ' · dès la case ${pl.premiereCase}' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(etat, style: theme.textTheme.labelMedium?.copyWith(color: couleur)),
                        if (pl.doublons.any((d) => d.identique && !pl.exclues.contains(d.a) && !pl.exclues.contains(d.b)))
                          Text('Poses en double',
                              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.error)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'retirer') _retirer(pl);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'retirer', child: Text('Retirer cette planche')),
                    ],
                  ),
                ],
              ),
              if (defs.isNotEmpty)
                DropdownButtonFormField<PlancheDef>(
                  value: defs.contains(pl.planche) ? pl.planche : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type de planche', isDense: true),
                  items: [
                    for (final d in defs)
                      DropdownMenuItem(value: d, child: Text(d.libelle, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (d) => _attribuer(pl, d),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _options(ThemeData theme) {
    final o = _projet.options;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Détourer le fond'),
            subtitle: const Text('Tolérance et bord doux se règlent dans une planche (communs à toutes).'),
            value: o.detourer,
            onChanged: (v) => setState(() {
              o.detourer = v;
              for (final pl in _projet.planches) {
                pl.invaliderApercus();
              }
            }),
          ),
          SwitchListTile(
            title: const Text('Cases carrées de 512 px'),
            value: o.case512,
            onChanged: (v) => setState(() => o.case512 = v),
          ),
          SwitchListTile(
            title: const Text('Pieds alignés (ancrage au sol)'),
            value: o.ancrageSol,
            onChanged: o.case512 ? (v) => setState(() => o.ancrageSol = v) : null,
          ),
          if (!_reglages.estDefaut)
            ListTile(
              dense: true,
              leading: const Icon(Icons.tune),
              title: const Text('Mouvement personnalisé'),
              subtitle: Text('${_projet.perso?.id}_anim.txt sera ajouté au zip.'),
            ),
        ],
      ),
    );
  }

  Widget _controles(ThemeData theme, List<Alerte> alertes) {
    if (alertes.isEmpty) {
      return Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade700),
          const SizedBox(width: 8),
          const Expanded(child: Text('Aucun doublon ni pose manquante.')),
        ],
      );
    }
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contrôles avant export', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final a in alertes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      a.bloquante ? Icons.error_outline : Icons.warning_amber,
                      size: 18,
                      color: a.bloquante ? theme.colorScheme.error : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(a.texte, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
