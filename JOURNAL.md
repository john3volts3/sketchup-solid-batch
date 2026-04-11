# Journal des modifications — Solid Batch

## Roadmap

- **v1.0** (livrée 2026-04-03) — Port fidèle d'Eneroth Solid Tools. Union, Subtract (multi-clic), Split. Ruby pur, fonctionne sans SketchUp Pro. Performances O(n²) sur le ray casting.
- **v2.0** (planifiée) — Optimisation Ruby : index spatial (bounding box pre-check, octree) pour `within?`, hash des plans pour `find_corresponding_faces`. Cible : 10-50x plus rapide sur modèles complexes (1000+ faces).
- **v3.0** (planifiée) — Backend Python avec trimesh/CGAL pour les opérations booléennes. Le plugin Ruby exporte la géométrie, appelle un script Python, réimporte le résultat. Vitesse C++ native pour le calcul booléen.

---

## Session du 2026-04-11

### Livraison v2.2.0

- **solid_batch/version.rb** — Version `2.1.0` → `2.2.0`
- **solid_batch.rb** — `ext.version = '2.2.0'`
- **docs/FSD_FR.md** — Mise à jour EF-04 (nouveau champ min_arc_segments), EF-05 (Phase 3 traite arcs + cercles), section 6 persistance, section 9 history, structure module
- **docs/FSD_EN.md** — Idem en anglais
- **docs/USER_MANUAL_FR.md** — Mise à jour Set Repair Options (3e champ), section Phase 3 mentionne arcs
- **docs/USER_MANUAL_EN.md** — Idem
- **README.md** — Mise à jour fonctionnalités EN+FR avec arc restoration
- **build/solid_batch.rbz** — Reconstruit
- **Plugins SketchUp 2021** — Fichiers copiés (loader, main, version, circle_restore)
- **Tests utilisateur** — Tous les tests du plan validés (cercles, arcs, mixte, gros objets, undo, faux positifs)

### Restauration automatique des arcs (en plus des cercles) — vers v2.2.0

- **solid_batch/circle_restore.rb** — Extension du module pour gérer aussi les arcs :
  - Nouvelle constante `DEFAULT_MIN_ARC_SEGMENTS = 8`
  - `restore_in_solid` accepte maintenant un kwarg `min_arc_segments:` et retourne un hash `{circles:, arcs:, total:}` au lieu d'un entier
  - Nouveau Stage 1b après le Stage 1a (cercles) : appelle `find_arcs_by_geometry` puis `entities.weld()` chaque arc trouvé
  - Re-collection des entities entre les stages pour éviter les références obsolètes après les welds
  - Nouvelle méthode `find_arcs_by_geometry(edges, min_segments)` — miroir de `find_circles_by_geometry`, mais matche les chaînes ouvertes via `open_chain?`
  - Nouvelle méthode `open_chain?(edges)` — vérifie qu'exactement 2 vertices ont degré 1 (extrémités) et tous les autres ont degré 2 (intermédiaires), refuse les branchements (degré > 2)
  - Commentaire d'en-tête mis à jour pour mentionner les arcs
  - Algorithme entièrement basé sur Re-Cercle + API SketchUp publique, aucune dépendance externe
- **solid_batch/main.rb** — Modifications :
  - Nouvelle constante `DEFAULT_MIN_ARC_SEGMENTS = 8`
  - Nouveaux helpers `min_arc_segments` et `save_min_arc_segments` (persistance via `Sketchup.write_default('SolidBatch', 'min_arc_segments', ...)`)
  - `do_set_repair_options` étendu avec un 3e champ `Min segments for arc detection` dans l'`UI.inputbox` (valeurs < 3 ramenées à `DEFAULT_MIN_ARC_SEGMENTS`)
  - Messagebox récapitulatif mis à jour avec une brève explication du tradeoff bas/haut
  - Phase 3 dans `do_combine_all_pro` passe `min_arc_segments:` à `restore_in_solid` et adapte le log/status bar pour mentionner « circles and arcs »
  - Le hash retourné par `restore_in_solid` est utilisé pour logger `N circle(s), M arc(s) restored`
- **Plugins SketchUp 2021** — `main.rb` et `circle_restore.rb` copiés vers le dossier Plugins
- **Pas de bump version ni de livraison** — tests utilisateur en cours avant publication v2.2.0

### Livraison v2.1.0

- **solid_batch/version.rb** — Version `2.0.0` → `2.1.0`
- **solid_batch.rb** — `ext.version = '2.1.0'`
- **docs/FSD_FR.md** — Ajout EF-04 (circle restoration), EF-05 (Set Repair Options), ENF-08, mise à jour flow + version history
- **docs/FSD_EN.md** — Idem en anglais
- **docs/USER_MANUAL_FR.md** — Ajout commande `Set Repair Options`, section circle restoration, nouvelle icône
- **docs/USER_MANUAL_EN.md** — Idem
- **README.md** — Mise à jour fonctionnalités EN+FR avec circle restoration
- **build/solid_batch.rbz** — Reconstruit
- **Plugins SketchUp 2021** — Fichiers copiés (loader, main, version, circle_restore, icônes)
- **.claude/skills/sketchup-plugin/SKILL.md** — Copie du skill global dans le repo

### Restauration automatique des cercles après opérations booléennes

- **solid_batch/circle_restore.rb** — **Création** — Module `SolidBatch::CircleRestore` adapté du plugin Re-Cercle :
  - `count_edges(solid)` — compte récursif des edges dans un Group/ComponentInstance (entre dans les groupes/composants imbriqués)
  - `restore_in_solid(solid)` — point d'entrée principal, applique l'algorithme en 2 étapes (edges libres via circumcircle + fragments de Curves regroupés) et retourne le nombre de cercles restaurés
  - Utilise `entities.weld()` (SketchUp 2020.1+)
  - Constantes : `TOLERANCE = 0.1`, `MIN_SEGMENTS = 8`
  - Pas de menu/toolbar, pas de start_operation interne, pas de UI.messagebox interne — méthodes utilitaires pures pour usage par le caller
- **solid_batch/main.rb** — Modifications :
  - Ajout `require_relative 'circle_restore'`
  - `do_set_subtract_color` conservé tel quel (capture la couleur depuis la sélection — comportement initial inchangé)
  - **Nouveau** menu item `'Set Repair Options'` + nouveau bouton toolbar (icône `setcolor` réutilisée temporairement)
  - **Nouvelle** méthode `do_set_repair_options` : ouvre `UI.inputbox` avec 2 champs (`Auto-repair circles on large objects` Yes/No, `Large object threshold (edges)` entier), persistance via `Sketchup.write_default` sous `SolidBatch/auto_repair_large` et `SolidBatch/large_threshold`, messagebox récapitulatif
  - Nouveaux helpers : `auto_repair_large`, `save_auto_repair_large`, `large_threshold`, `save_large_threshold`
  - Nouvelles constantes : `DEFAULT_AUTO_REPAIR_LARGE = 'Yes'`, `DEFAULT_LARGE_THRESHOLD = 10000`
  - **Phase 3** ajoutée à `do_combine_all_pro`, après la phase 2 de soustraction :
    - Compte les edges du résultat via `CircleRestore.count_edges`
    - Si `edge_count <= threshold` OU `auto_repair_large == 'Yes'` → exécute `CircleRestore.restore_in_solid` dans une opération transparente chaînée à l'undo unique
    - Sinon → affiche une `UI.messagebox` modale expliquant que la réparation a été ignorée et comment l'activer
    - Status bar : `Solid Batch — Restoring circles...`
    - Logs console : `[Solid Batch]   Phase 3: N circle(s) restored` ou `Skipped`

---

## Session du 2026-04-04 (5)

### Livraison — mise à jour documentation

- **docs/FSD_EN.md** — Ajout NFR-06 (status bar progress), NFR-07 (transparent operations), mise à jour flow diagram et version history
- **docs/FSD_FR.md** — Idem en français (ENF-06, ENF-07)
- **docs/USER_MANUAL_EN.md** — Ajout section "Progress" (status bar pendant les opérations batch)
- **docs/USER_MANUAL_FR.md** — Ajout section "Progression" (idem en français)
- **Copie plugins** — Fichiers copiés vers le dossier plugins SketchUp 2021

---

## Session du 2026-04-04 (4)

### Optimisation performance + barre de statut

- **solid_batch/main.rb** — Optimisation des opérations batch :
  - Chaque étape booléenne a son propre `start_operation`/`commit_operation` (petits deltas = commits rapides)
  - Le paramètre `transparent = true` chaîne toutes les étapes en un seul Ctrl+Z
  - Ajout barre de statut avec progression : `Solid Batch — Subtract 7/13 (54%)`
  - Message final : `Solid Batch — Done (13 operations)`
- **build/solid_batch.rbz** — Reconstruit

---

## Session du 2026-04-04 (3)

### Renommage `dro_solid_ops` → `solid_batch`

- **dro_solid_ops.rb** → **solid_batch.rb** — Renommé fichier, module `DRO_SolidOps` → `SolidBatch`, `PLUGIN_NAME` → `'Solid Batch'`
- **dro_solid_ops/** → **solid_batch/** — Renommé dossier entier
- **solid_batch/main.rb** — Module `SolidBatch`, registre `SolidBatch`, logs `[Solid Batch]`, chemin icônes `solid_batch/icons`
- **solid_batch/version.rb** — Module `SolidBatch`
- **README.md** — Mis à jour : Solid Batch, `solid_batch.rbz`
- **docs/*.md** — Tous les docs EN/FR mis à jour avec les nouveaux noms
- **build/solid_batch.rbz** — Reconstruit avec les fichiers renommés
- **.gitignore** — Retiré `build/` pour l'inclure dans le repo

---

## Session du 2026-04-04 (2)

### Nettoyage — Suppression des fonctions non-Pro

- **dro_solid_ops/main.rb** — Suppression des 4 fonctions non-Pro :
  - Menu items et toolbar buttons : Union, Subtract, Split, Combine All
  - Handlers : `do_union`, `do_subtract`, `SubtractTool` (classe entière), `do_split`, `do_combine_all`
  - Suppression `require_relative 'boolean_ops'`
  - Fonctions conservées : `do_combine_all_pro` (Union/Shell), `do_set_subtract_color`, helpers couleur, `get_solids`
- **dro_solid_ops/boolean_ops.rb** — Fichier supprimé (moteur booléen custom plus utilisé, les fonctions PRO utilisent les méthodes natives SketchUp)
- **dro_solid_ops/icons/** — Suppression icônes : union_16/24, subtract_16/24, split_16/24, combine_16/24. Conservées : combine_pro_union, combine_pro_shell, setcolor
- **dro_solid_ops.rb** — Description mise à jour

---

## Session du 2026-04-04

### v2.0.0 — Optimisation : Bounding Box + Octree spatial

- **dro_solid_ops/boolean_ops.rb** — Ajout classe `FaceOctree` et optimisation de `within?` :
  - Bounding box pre-check : rejet immédiat si le point est hors de la bounding box du container
  - `FaceOctree` : octree spatial qui indexe les faces par leur bounding box, avec traversée par rayon (`query_ray`). Construction récursive (max depth 5, max 8 faces/nœud). Test d'intersection rayon-boîte par slab intersection.
  - Construction lazy : octree créé uniquement pour les containers avec > 50 faces
  - Cache par `definition.entityID`, invalidé si le nombre de faces change
  - `octree_faces_for_ray` : retourne les faces candidates via l'octree ou itération directe (fallback)
  - `clear_octree_cache` appelé en début de `union`, `subtract`, `split` pour invalider le cache
- **dro_solid_ops/version.rb** — Version 2.0.0

### Nouvelles fonctionnalités : Combine All, Combine All PRO, Set Subtract Color

- **dro_solid_ops/main.rb** — Ajout de 4 nouvelles commandes :
  - `do_combine_all` : sélectionner N solides, sépare par couleur (union vs subtract), union d'abord puis subtracts séquentiels via moteur custom BooleanOps.
  - `do_combine_all_pro(:union)` : idem mais utilise les méthodes natives Pro `group.union()` + `group.subtract()`. Détection auto si Pro disponible.
  - `do_combine_all_pro(:outer_shell)` : idem mais utilise `group.outer_shell()` + `group.subtract()` natifs. Opération unique pour Ctrl+Z.
  - `do_set_subtract_color` : capture la couleur du matériau de l'objet sélectionné et la sauvegarde via `Sketchup.write_default` (persistant entre sessions).
  - Helpers : `subtract_color`, `save_subtract_color`, `color_match?`, `is_subtract_solid?`
  - Menu Extensions > Solid Ops : 5 items + séparateur
  - Toolbar : 4 nouveaux boutons avec icônes
- **dro_solid_ops/boolean_ops.rb** — Ajout paramètre `wrap_operation:` (défaut `true`) à `union` et `subtract` pour permettre au caller de gérer l'opération undo lui-même.
- **dro_solid_ops/icons/** — Nouvelles icônes 16+24px : combine, combine_pro_union, combine_pro_shell, setcolor
- **dro_solid_ops/icons/union, subtract, split** — Icônes mises à jour avec symboles +, −, / en noir, alignés bas-gauche

### Corrections Combine All PRO
- Fix subtract natif : `tool.subtract(result)` au lieu de `result.subtract(tool)` — dans l'API native SketchUp, le receveur est l'outil (effacé), l'argument est la base (modifiée et retournée).
- Ajout `model.selection.clear` entre chaque opération native (nécessaire pour le subtract natif).
- Undo unifié : Combine All et Combine All PRO wrappés dans un seul `start_operation`/`commit_operation` → un seul Ctrl+Z annule toute l'opération.

---

## Session du 2026-04-03

- **dro_solid_ops.rb** — Création du loader principal (SketchupExtension, register_extension)
- **dro_solid_ops/version.rb** — Constante VERSION 1.0.0
- **dro_solid_ops/main.rb** — Menu Extensions > Solid Ops (Union, Subtract, Split), toolbar avec 3 commandes, validation de la sélection (solides manifold)
- **dro_solid_ops/boolean_ops.rb** — Première implémentation du moteur booléen (merged group + raytest classification). Nombreuses itérations pour résoudre les problèmes de face splitting et classification.
- **dro_solid_ops/icons/** — Icônes PNG 24x24 pour union, subtract, split
- **C:/Users/danie/.claude/commands/sketchup-plugin.md** — Ajout directive de cohérence de nommage

### Réécriture complète — port fidèle d'Eneroth Solid Tools

- **dro_solid_ops/boolean_ops.rb** — Réécriture complète basée sur l'algorithme d'Eneroth Solid Tools :
  - `add_intersection_edges` : double intersect_with (2 sens) → temp group → merge_into (instance+explode) → interior_hole_hack
  - `within?` : ray casting manuel (234,1343,345) avec Geom.intersect_line_plane + classify_point
  - `point_at_face` : point fiable sur une face via mesh triangles
  - `find_faces` : classification intérieur/extérieur via point_at_face + within?
  - `find_corresponding_faces` : détection faces coplanaires identiques
  - `erase_faces_with_edges` : suppression faces + edges exclusifs
  - `weld_hack` : naked edges → temp group → explode
  - Union, Subtract (trim), Split (A-B, B-A, A∩B)
- **dro_solid_ops/main.rb** — SubtractTool interactif multi-soustraction :
  - Clic 1 = base, clics suivants = outils soustraits en boucle
  - Escape pour terminer
  - Barre de statut pour guider l'utilisateur
