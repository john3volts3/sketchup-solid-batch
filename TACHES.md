# Solid Batch — Tâches et état (reprise de session)

Préparé le 2026-10-26, à la fin de la session Solid Procedural / Solid for Maker. But : faire dans Solid Batch **le même travail de correction et d'optimisation** que dans Solid Procedural (1.1.0 à 1.1.2), avec les mêmes garanties (batterie de tests automatiques, résultat identique pour l'optimisation, rien ne change sous SketchUp Pro).

Chemins relatifs à la racine de ce dépôt ; les dépôts voisins sont dans le même dossier parent (`../sketchup-solid-procedural`, `../sketchup-solid-for-maker`).

## État au 2026-10-26

- **Version 2.4.0 livrée le 2026-10-26** (lots A à E ci-dessous), puis **2.4.1** le même jour (échec d'une étape de Combine All : message clair, solide sélectionné, modèle inchangé), puis **2.5.0** (Make débloqué par défaut, une seule ligne pour réserver à Pro, notice MIT d'Eneroth exacte ; tests du moteur rendus publics, `tools/tests/local/` supprimé). Ce qui suit décrit l'état de départ de la session.
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
- `main.rb`, `do_combine_all_pro` : le contrôle `solids[0].respond_to?(mode)` ne détecte pas SketchUp Make (`Group#union` y est défini) : sous Make, le message « This function requires SketchUp Pro » n'apparaît pas. **Confirmé par la batterie (T10, Make 2017)** : `union` / `subtract` lèvent une exception, d'où le message « Combine All error: 'union' is a Pro only feature. » ; aucun solide perdu.
- ~~`main.rb`, `do_combine_all_pro` : si une étape booléenne échoue au milieu, `abort_operation` n'annule que cette étape.~~ **Constat faux** (tiré de la lecture du code) : la batterie (T14, 2021 et Make 2017) montre que SketchUp, en annulant une opération enchaînée (transparente), annule toute la chaîne ; le modèle revenait déjà comme avant. La 2.4.1 rend le message clair (étape, solide, raison ; solide sélectionné) et couvre l'erreur survenue entre deux étapes (T13, L05).
- Batterie (T04, 2021) : après Subtract, les 48 faces des parois des trous portent la couleur de soustraction (comportement natif, inchangé depuis la 2.0).

## Décisions prises le 2026-10-26

Les notes propres à ce PC sont dans `TACHES.local.md` (exclu de git) : à lire aussi au démarrage.

1. **SketchUp Make** : le moteur Ruby de Solid for Maker 1.0.1 est copié dans `solid_batch/solid_operations.rb` (licence MIT d'Eneroth conservée) ; sous Make (`Sketchup.is_pro?` faux), Combine All affiche « PRO Only » ; sous Pro, booléens natifs inchangés. **Révisée le 2026-10-26 (2.5.0)** : pas d'Extension Warehouse ; Make débloqué par défaut (moteur Ruby) dans Solid Batch, Solid Procedural et Solid for Maker ; une seule ligne, commentée par défaut, réserve Combine All à Pro (« PRO Only vs. main.rb:<ligne> ») ; un seul contrôle de l'édition ; mécanisme documenté publiquement.
2. **Version** : 2.4.0.
3. **Installation pendant le développement** : plugins de SketchUp 2021 et de Make 2017.
4. **Outils de test** dans le dépôt public, sans chemin local (SketchUp trouvé par le registre, comme `../sketchup-solid-for-maker/tools/regression/run_kit.ps1`) ; les tests du moteur Ruby restent dans un fichier local exclu de git.
5. **Release GitHub** v2.4.0 avec le `.rbz` à la livraison.
6. **Documentation publique** (README, FSD, manuels) : SketchUp Pro requis ; « PRO Only » sous Make ; `solid_operations.rb` listé avec le crédit Eneroth (MIT), sans plus de détail. **Révisée le 2026-10-26 (2.5.0)** : SketchUp Pro et Make ; la ligne « Pro seulement » est décrite (README, FSD EF-07) ; notice MIT d'Eneroth exacte, « not an official Eneroth extension ».

## Plan

### Lot A — Batterie de tests automatiques (d'abord, sur le code 2.3.0)
- [x] `tools/tests/run_tests.ps1` : repris de `../sketchup-solid-procedural/tools/tests/run_tests.ps1` (déploiement dans les plugins, `-RubyStartup`, attente du rapport, écran d'accueil de 2021 coupé puis remis ; Make 2017 : un clic de l'utilisateur), mais : SketchUp trouvé par le registre (`HKLM:\SOFTWARE\SketchUp\SketchUp <version>\InstallLocation`, valeur par défaut) au lieu de chemins en dur ; arrêt du seul SketchUp lancé (par son numéro de processus) ; refus de démarrer si SketchUp est ouvert ; **ASCII seulement** (Windows PowerShell 5.1 lit un `.ps1` sans BOM en ANSI : un tiret long y casse une chaîne).
- [x] `tools/tests/run_tests.rb` : cadre de `../sketchup-solid-procedural/tools/tests/run_tests.rb` (tests, rapport `results/latest-<version>.txt` terminé par `DONE`, aides `pt`, `box`, `cylinders`, `add_cylinder`, `cones`, `shape_signature`, `signature_diff`, `force_auto_repair` / `restore_auto_repair`, `force_repair` / `restore_repair`, `repair_holes_scan`). `UI.messagebox` remplacé pendant les tests (messages enregistrés, jamais affichés : une boîte bloquerait le lancement).
- [x] Tests T01 à T10 : Combine All (Union, Shell, Subtract par la couleur) à volume calculé d'avance ; une seule étape d'annulation ; reconstruction des cercles (nombre de cercles natifs) ; seuil « gros objet » (Yes / No) ; Set Repair Options ; sous Make : comportement actuel enregistré. Options du plugin forcées pendant les tests, `Sketchup.write_default` enregistré : aucune écriture dans le registre du PC.
- [x] Premier passage (2026-10-26), référence du comportement 2.3.0 : **2021** passed=9 failed=0 skipped=1 (T10, Make seulement) ; **Make 2017** passed=5 failed=0 skipped=5 (booléens natifs absents), T07 : aucun cercle natif avant 2020.1 (garde `weld`), T10 : « 'union' / 'subtract' is a Pro only feature ».

### Lot B — Optimisation de `repair_holes` (résultat identique)
- [x] Copier de `../sketchup-solid-procedural/solid_procedural/circle_restore/volume.rb` la note d'en-tête, `repair_holes` et `hole_edge`, `point_grid`, `cell_of`, `near_items`, `near_grid?` (module `SolidBatch`). L'ancienne méthode va dans les tests seulement (`repair_holes_scan`). Fait par copie du fichier de Solid Procedural, noms remplacés : le `diff` avec l'ancien fichier ne montre que la note d'en-tête et `repair_holes`.
- [x] **T15** de Solid Procedural repris en **T11** (grilles = parcours complet) et **T12** (13 cas). Résultats du 2026-10-26 : référence sur le code 2.3.0 (ancienne méthode contre elle-même) identique partout ; puis ancienne contre nouvelle sous **2021** : 13 cas identiques (faces, arêtes, cercles, compteurs, appels), T11 sans écart, plaque à 20 trous 9,6 → 2,2 s ; **Make 2017** : T11 sans écart, T12 sauté (pas de booléens natifs, à reprendre avec le moteur). Texte d'origine : grilles = parcours complet (2 200 requêtes), puis 14 cas, ancienne et nouvelle méthode sur la même géométrie (opération annulée entre les deux), faces, arêtes et cercles identiques, plaque à 20 trous au moins 2 fois plus rapide. Cas : plaque à 20 trous, trous près d'un bord, faces colorées recto / verso, trous à cheval sur deux faces coplanaires, très petits (1 mm) et très grands trous, chambrages, fraisurages à épaulement, chambrages après les trous, trous dessus et sur un côté, troncs de cône, tétons par Union, trous borgnes. Résultats de Solid Procedural : identique partout ; plaque à 20 trous 9,2 → 2,1 s (2021), 6,6 → 1,4 s (Make 2017).
- [ ] `OPTIMISATION_REPAIR_HOLES.md` : ligne Solid Batch du tableau § 8 (« fait »), puis commit.

### Lot C — Versions antérieures à 2020.1 et SketchUp Make (sans risque sous Pro 2021)
- [x] `circle_restore.rb` : garde `weld` comme dans `../sketchup-solid-procedural/solid_procedural/circle_restore.rb` (la soudure de secours seule est sautée) → cercles natifs sous 2017.
- [x] *Set Repair Options* dans toutes les versions (menu et barre d'outils).
- [x] Détection de Make par `Sketchup.is_pro?` dans `do_combine_all_pro` : message « PRO Only » (voir `TACHES.local.md`).
- [x] Tests (2026-10-26) : T04, T07, T08 vérifient les cercles natifs dans toutes les versions ; T10 vérifie « PRO Only » sous Make (et sous Pro, Make simulé) ; T06 sauté sous Make. **2021** : 25 réussis, 0 échec, 0 sauté ; **Make 2017** : 6 réussis, 0 échec, 19 sautés (booléens), T07 : cercles natifs sous 2017.

### Lot D — Moteur Ruby `solid_operations.rb` (détails dans `TACHES.local.md`)
- [x] Copier `../sketchup-solid-for-maker/solid_for_maker/solid_operations.rb` (version 1.0.1, commit `2b2a596`, qui corrige le chambrage après son trou) dans `solid_batch/solid_operations.rb`, module `SolidForMaker` → `SolidBatch`, corps identique (vérifié par `diff`) ; en-tête et notice MIT comme `../sketchup-solid-procedural/solid_procedural/solid_operations.rb` et `LICENSE-solid-operations.txt`.
- [x] `do_combine_all_pro` : intégration du moteur, voir `TACHES.local.md` ; un seul contrôle de l'édition de SketchUp dans tout le plugin ; contrôle `respond_to?(mode)` (« requires SketchUp Pro ») retiré.
- [x] Tests du moteur : fichier local exclu de git (voir `TACHES.local.md`). Batterie (2026-10-26) : **2021** 40 réussis, 0 échec ; **Make 2017** 21 réussis, 0 échec, 19 sautés (booléens natifs).

### Lot E — Documentation et livraison
- [x] `PRD.md` (créé), `docs/FSD_FR.md` / `docs/FSD_EN.md` (périmètre, moteurs, `repair_holes`, versions), `docs/USER_MANUAL_FR.md` / `docs/USER_MANUAL_EN.md`, `README.md` (exigences : « SketchUp Pro » ; restauration « 2020.1+ » à revoir), `JOURNAL.md`, version (`solid_batch.rb`, `solid_batch/version.rb`), `.rbz`, installation, commit, push ; recherche de chemins locaux avant chaque commit (dépôt public). Livraison 2.4.0 le 2026-10-26 (tag `v2.4.0`, release GitHub avec le `.rbz`).

## Suite possible (non planifiée)

- ~~Échec d'une étape au milieu d'un lot : tout annuler automatiquement ?~~ Fait en 2.4.1 (le modèle revenait déjà comme avant ; message clair, solide sélectionné).
- ~~Règles de l'Extension Warehouse sur le code tiers MIT~~ : Extension Warehouse non visée (décision 2.5.0, PRD § 9).
- Solid Procedural et Solid for Maker : même schéma (Make débloqué, une seule ligne, un seul test Pro) et mêmes points de licence, à faire dans leurs sessions (notes déposées dans leurs listes de tâches le 2026-10-26).

## Pièges connus (venus de Solid Procedural et de Solid for Maker)

- Make 2017 (17.2.2555, Ruby 2.2.4) : pas de `DefinitionList#remove` (2018), `Model#active_path=` (2020.0), `Entities#weld` (2020.1), `Sketchup.focus` (2021.1), ni de booléens natifs ; SketchUp 2021 installé = 21.0.391.
- L'écran d'accueil bloque `-RubyStartup` jusqu'à sa fermeture : sous 2021, `WelcomeDialog.ShowOnStartup` dans `%LOCALAPPDATA%\SketchUp\SketchUp 2021\SketchUp\PrivatePreferences.json` ; sous Make 2017, l'utilisateur clique.
- `Group#copy` ne garde ni la matière ni les attributs de l'instance ; `Group#name=` rend la définition unique.
- Booléens natifs avec un outil fait de plusieurs solides : SketchUp laisse des définitions inutilisées `TempInstance#n`.
- Limites du moteur des cercles (communes à tous ces plugins) : cercle partagé par deux surfaces courbes (fraisurage dont le cône rejoint le trou : « cylinder end with a line attached ») et trou à cheval sur une ligne entre deux faces coplanaires, non reconstruits en natif.
- Ne jamais fermer une session SketchUp ouverte par l'utilisateur ; les lanceurs refusent de démarrer si SketchUp tourne.
- `PrivatePreferences.json` de SketchUp est en UTF-8 sans BOM : ne jamais le lire avec `Get-Content -Raw` sous Windows PowerShell 5.1 (lu en ANSI, réécrit en UTF-8 : il a grossi jusqu'à 1,96 Go le 2026-10-26 et SketchUp 2021 ne démarrait plus). `[IO.File]::ReadAllText` / `WriteAllText` avec `UTF8Encoding($false)`, et ne pas toucher un fichier de plus de 20 Mo (corrigé dans `tools/tests/run_tests.ps1`).
