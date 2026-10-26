# Solid Batch — Tâches et état (reprise de session)

Préparé le 2026-10-26, à la fin de la session Solid Procedural / Solid for Maker. But : faire dans Solid Batch **le même travail de correction et d'optimisation** que dans Solid Procedural (1.1.0 à 1.1.2), avec les mêmes garanties (batterie de tests automatiques, résultat identique pour l'optimisation, rien ne change sous SketchUp Pro).

Chemins relatifs à la racine de ce dépôt ; les dépôts voisins sont dans le même dossier parent (`../sketchup-solid-procedural`, `../sketchup-solid-for-maker`).

## État au 2026-10-26

- **Version 2.3.0** (commit `13748c4`, 2026-10-11) : Combine All (Union / Shell) avec les booléens natifs, Set Subtract Color, Set Repair Options, reconstruction des cercles et arcs (méthode Re-Cercle v2.0.0, `solid_batch/circle_restore/`). Installée dans les plugins de SketchUp 2021 **et** de SketchUp Make 2017.
- Dépôt GitHub **public**, aucun tag ni release GitHub (diffusion prévue : SketchUcation, notes privées dans `docs/SKETCHUCATION.md`, exclu de git).
- Pas de `PRD.md` (exigé par les règles générales : à créer à la première livraison, à partir du FSD, du README et du JOURNAL), pas de batterie de tests.
- Fichiers non suivis : `OPTIMISATION_REPAIR_HOLES.md` (copié le 2026-10-24 : description et code de l'accélération de `repair_holes`, à commiter avec le lot B) ; `todo.txt` (note de la session Solid for Maker du 2026-10-24, ne pas commiter).
- `docs/FSD_FR.md` § 2 **exclut** « Compatibilité SketchUp Make / Free » et ENF-01 impose de « reposer exclusivement sur les méthodes natives SketchUp Pro ».

### Constats (vérifiés le 2026-10-26 par `diff` avec Solid Procedural, module renommé)

- `solid_batch/circle_restore/` est identique à celui de Solid Procedural **sauf deux points**, tous deux corrigés dans Solid Procedural :
  1. `circle_restore.rb` (≈ l. 61) : `return result unless entities.respond_to?(:weld)` → **avant SketchUp 2020.1, aucune reconstruction n'a lieu** (Pro 2017 à 2020.0, Make 2017), alors que seule la soudure de secours a besoin de `Entities#weld`. Solid Procedural M1 (commit `084a488`) : la garde ne bloque plus que la soudure de secours.
  2. `circle_restore/volume.rb` : `repair_holes` parcourt toutes les arêtes pour chaque trou (≈ 1 s par cylindre reconstruit dans une plaque à 30 trous). Solid Procedural 1.1.1 (commit `7285e84`) : grilles de cases de la taille de la tolérance, résultat identique (T15).
- `main.rb` : *Set Repair Options* n'est proposé qu'à partir de 2020.1 (`Sketchup.version.to_f >= 20.1`, menu et barre d'outils).
- `main.rb`, `do_combine_all_pro` : le contrôle `solids[0].respond_to?(mode)` ne détecte pas SketchUp Make (`Group#union` y est défini mais ne fait rien) : sous Make, le message « This function requires SketchUp Pro » n'apparaît pas et l'opération échoue autrement (à confirmer par la batterie).

## Décisions à prendre en début de session

1. **SketchUp Make** — Deux choix :
   - (a) comme Solid Procedural 1.1.0 à 1.1.2 : sous Make (`Sketchup.is_pro?` faux), Combine All utilise le **moteur Ruby de Solid for Maker 1.0.1** (copié dans `solid_batch/`, licence MIT d'Eneroth conservée) ; sous Pro, booléens natifs inchangés (consigne du 2026-10-24 : le moteur seulement sans Pro). Change le périmètre du FSD (§ 2 « Exclu », ENF-01) et une décision plus ancienne (« version publique destinée à l'Extension Warehouse, code 100 % original, sans moteur d'Eneroth »). Un interrupteur `PRO_ONLY` comme celui de Solid Procedural (`main.rb`) permettrait de remettre une version Pro seulement si une diffusion l'exige (règle de l'Extension Warehouse non vérifiée, voir le PRD de Solid for Maker § 7).
   - (b) pas de moteur : sous Make, message clair « requires SketchUp Pro » (détection par `Sketchup.is_pro?`).
   - Recommandation : (a) avec `PRO_ONLY`, c'est le « même travail » que dans Solid Procedural ; (b) si Solid Batch doit rester sans code d'Eneroth.
2. **Version** : 2.4.0 si Make est ajouté (fonction nouvelle), sinon 2.3.1.
3. **Installation pendant le développement** : plugins de SketchUp 2021 et de Make 2017 (2.3.0 est dans les deux) ?
4. **Outils de test dans le dépôt public** : oui, sans chemin local (SketchUp trouvé par le registre, comme `../sketchup-solid-for-maker/tools/regression/run_kit.ps1`) ?
5. **Release GitHub** avec le `.rbz` à la livraison (aucune jusqu'ici) ?

## Plan

### Lot A — Batterie de tests automatiques (d'abord, sur le code 2.3.0)
- [ ] `tools/tests/run_tests.ps1` : repris de `../sketchup-solid-procedural/tools/tests/run_tests.ps1` (déploiement dans les plugins, `-RubyStartup`, attente du rapport, écran d'accueil de 2021 coupé puis remis ; Make 2017 : un clic de l'utilisateur), mais : SketchUp trouvé par le registre (`HKLM:\SOFTWARE\SketchUp\SketchUp <version>\InstallLocation`, valeur par défaut) au lieu de chemins en dur ; arrêt du seul SketchUp lancé (par son numéro de processus) ; refus de démarrer si SketchUp est ouvert ; **ASCII seulement** (Windows PowerShell 5.1 lit un `.ps1` sans BOM en ANSI : un tiret long y casse une chaîne).
- [ ] `tools/tests/run_tests.rb` : cadre de `../sketchup-solid-procedural/tools/tests/run_tests.rb` (tests, rapport `results/latest-<version>.txt` terminé par `DONE`, aides `pt`, `box`, `cylinders`, `add_cylinder`, `cones`, `shape_signature`, `signature_diff`, `force_auto_repair` / `restore_auto_repair`, `force_repair` / `restore_repair`, `repair_holes_scan`). `UI.messagebox` remplacé pendant les tests (messages enregistrés, jamais affichés : une boîte bloquerait le lancement).
- [ ] Tests : Combine All (Union, Shell, Subtract par la couleur) à volume calculé d'avance ; une seule étape d'annulation ; reconstruction des cercles (nombre de cercles natifs) ; Set Repair Options (seuil, Yes / No) ; sous Make : comportement actuel enregistré. Les réglages *Set Repair Options* du PC (registre `SolidBatch`) ne doivent pas changer le résultat des tests (forcer, puis rétablir).
- [ ] Premier passage sous 2021 et Make 2017 : référence du comportement 2.3.0.

### Lot B — Optimisation de `repair_holes` (résultat identique)
- [ ] Copier de `../sketchup-solid-procedural/solid_procedural/circle_restore/volume.rb` la note d'en-tête, `repair_holes` et `hole_edge`, `point_grid`, `cell_of`, `near_items`, `near_grid?` (module `SolidBatch`). L'ancienne méthode va dans les tests seulement (`repair_holes_scan`).
- [ ] **T15** repris de Solid Procedural : grilles = parcours complet (2 200 requêtes), puis 14 cas, ancienne et nouvelle méthode sur la même géométrie (opération annulée entre les deux), faces, arêtes et cercles identiques, plaque à 20 trous au moins 2 fois plus rapide. Cas : plaque à 20 trous, trous près d'un bord, faces colorées recto / verso, trous à cheval sur deux faces coplanaires, très petits (1 mm) et très grands trous, chambrages, fraisurages à épaulement, chambrages après les trous, trous dessus et sur un côté, troncs de cône, tétons par Union, trous borgnes. Résultats de Solid Procedural : identique partout ; plaque à 20 trous 9,2 → 2,1 s (2021), 6,6 → 1,4 s (Make 2017).
- [ ] `OPTIMISATION_REPAIR_HOLES.md` : ligne Solid Batch du tableau § 8 (« fait »), puis commit.

### Lot C — Versions antérieures à 2020.1 et SketchUp Make (sans risque sous Pro 2021)
- [ ] `circle_restore.rb` : garde `weld` comme dans `../sketchup-solid-procedural/solid_procedural/circle_restore.rb` (la soudure de secours seule est sautée) → cercles natifs sous 2017.
- [ ] *Set Repair Options* dans toutes les versions (menu et barre d'outils).
- [ ] Détection de Make par `Sketchup.is_pro?` dans `do_combine_all_pro`.

### Lot D — Moteur de Solid for Maker sous Make (seulement si la décision 1 est (a))
- [ ] Copier `../sketchup-solid-for-maker/solid_for_maker/solid_operations.rb` (version 1.0.1, commit `2b2a596`, qui corrige le chambrage après son trou) dans `solid_batch/solid_operations.rb`, module `SolidForMaker` → `SolidBatch`, corps identique (vérifier par `diff`) ; en-tête et notice MIT comme `../sketchup-solid-procedural/solid_procedural/solid_operations.rb` et `LICENSE-solid-operations.txt`.
- [ ] `do_combine_all_pro` : sous Make, `SolidOperations.union(base, autre)`, `.outer_shell(base, autre)`, `.subtract(base, outil)` — **base en premier**, à l'inverse du `outil.subtract(base)` natif ; la base est modifiée sur place, l'outil effacé ; retour `true` (succès), `false` (conteneur refusé) ou `nil` (résultat non solide) → `abort_operation` (le moteur modifie la base avant de savoir si le résultat est un solide). Modèle : `ruby_engine?` et `ruby_boolean` dans `../sketchup-solid-procedural/solid_procedural/procedural.rb`, `PRO_ONLY` dans son `main.rb`.
- [ ] Tests : Combine All avec le moteur Ruby forcé sous 2021 et sous Make 2017, mêmes volumes ; différence connue : un solide enfermé dans un autre est effacé par le Shell du moteur Ruby, gardé par l'Outer Shell natif.

### Lot E — Documentation et livraison
- [ ] `PRD.md` (créé), `docs/FSD_FR.md` / `docs/FSD_EN.md` (périmètre, moteurs, `repair_holes`, versions), `docs/USER_MANUAL_FR.md` / `docs/USER_MANUAL_EN.md`, `README.md` (exigences : « SketchUp Pro » ; restauration « 2020.1+ » à revoir), `JOURNAL.md`, version (`solid_batch.rb`, `solid_batch/version.rb`), `.rbz`, installation, commit, push ; recherche de chemins locaux avant chaque commit (dépôt public).

## Pièges connus (venus de Solid Procedural et de Solid for Maker)

- Make 2017 (17.2.2555, Ruby 2.2.4) : pas de `DefinitionList#remove` (2018), `Model#active_path=` (2020.0), `Entities#weld` (2020.1), `Sketchup.focus` (2021.1), ni de booléens natifs ; SketchUp 2021 installé = 21.0.391.
- L'écran d'accueil bloque `-RubyStartup` jusqu'à sa fermeture : sous 2021, `WelcomeDialog.ShowOnStartup` dans `%LOCALAPPDATA%\SketchUp\SketchUp 2021\SketchUp\PrivatePreferences.json` ; sous Make 2017, l'utilisateur clique.
- `Group#copy` ne garde ni la matière ni les attributs de l'instance ; `Group#name=` rend la définition unique.
- Booléens natifs avec un outil fait de plusieurs solides : SketchUp laisse des définitions inutilisées `TempInstance#n`.
- Limites du moteur des cercles (communes à tous ces plugins) : cercle partagé par deux surfaces courbes (fraisurage dont le cône rejoint le trou : « cylinder end with a line attached ») et trou à cheval sur une ligne entre deux faces coplanaires, non reconstruits en natif.
- Ne jamais fermer une session SketchUp ouverte par l'utilisateur ; les lanceurs refusent de démarrer si SketchUp tourne.
