# Solid Batch — instructions de projet

Plugin SketchUp (Ruby API) : **Combine All** (Union ou Shell des solides de base, puis Subtract des solides de la couleur de soustraction) avec les booléens natifs de SketchUp Pro, puis reconstruction des cercles et arcs en cercles natifs. Version publiée : 2.3.0.

## Au démarrage de chaque session

1. Lire **`TACHES.md`** (état, décisions à prendre, plan), puis `JOURNAL.md` (le plus récent en haut) et `docs/FSD_FR.md`.
2. Charger les skills `/sketchup-plugin` et `/sketchup-native-circles`.
3. Commencer par les **décisions à prendre** de `TACHES.md` (une question à la fois si besoin), puis reprendre à la première tâche non cochée.

## Règles propres au projet

- Nom affiché **Solid Batch**, strictement identique partout (extension, menu, barre d'outils, registre `SolidBatch`, logs `[Solid Batch]`) ; module `SolidBatch`, dossier `solid_batch/`.
- **Dépôt GitHub public** (`sketchup-solid-batch`) : aucun chemin local, nom d'utilisateur, adresse ou chemin réseau dans les fichiers suivis (chercher avant chaque commit). Les notes propres au PC vont dans un fichier exclu (`.git/info/exclude`).
- Plugin **autonome** : le code repris d'un autre plugin (Solid Procedural, Solid for Maker, Re-Cercle) est **copié** dans `solid_batch/` sous le module `SolidBatch`, jamais chargé depuis un autre plugin.
- Sous SketchUp Pro, le comportement des booléens natifs ne change pas. Rappel de l'API native : `outil.subtract(base)` (le receveur est l'outil, effacé ; l'argument est la base, modifiée et renvoyée) ; `model.selection.clear` entre deux opérations natives.
- Si le support de SketchUp Make 2017 est retenu : code compatible **Ruby 2.2** (aucune syntaxe ni méthode Ruby 2.3+), garde `respond_to?` pour toute API postérieure à 2017, Make détecté par `Sketchup.is_pro?` (et non par `respond_to?(:union)`, défini aussi sous Make).
- Fiabilité avant vitesse : une optimisation n'est acceptée que si elle donne **le même résultat**, vérifié par la batterie de tests sur la même géométrie.
- Tests : batterie automatique (à créer, voir `TACHES.md`) plutôt que des tests à la main ; ne demander à la main que ce qu'aucune API ne peut automatiser.
- Tenir à jour `TACHES.md`, `JOURNAL.md`, `PRD.md` (à créer à la première livraison), `docs/FSD_FR.md` / `docs/FSD_EN.md`, les manuels `docs/USER_MANUAL_FR.md` / `docs/USER_MANUAL_EN.md` et le `README.md`.
