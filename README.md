# Solid Batch — SketchUp Pro Plugin

**Batch solid boolean operations using native SketchUp Pro tools.**

*[Version francaise ci-dessous](#solid-batch--plugin-sketchup-pro)*

---

## Demo

[![Solid Batch Demo](https://img.youtube.com/vi/Zmjdbe_O_Cc/0.jpg)](https://youtu.be/y5_-0-7OkBw)

## Why Solid Batch?

When designing technical parts for 3D printing in SketchUp, a common workflow is to build up complex shapes from simple volumes — boxes, cylinders, extrusions — then combine them using boolean operations at the end of each design stage or at the very end. Manually running union and subtract on dozens of objects one by one is tedious and time-consuming. Solid Batch automates this: select all your solids, click once, and the plugin unions the bases and subtracts the tools in a single batch operation.

## Features

- **Combine All (Union)** — Select multiple solids, automatically union all base solids then subtract color-marked objects. Single undo step.
- **Combine All (Shell)** — Same workflow using Outer Shell instead of Union (merges overlapping volumes into one shell).
- **Automatic circle and arc restoration** — Native boolean operations break circles and arcs into individual segments. At the end of every Combine All, Solid Batch rebuilds them as **native SketchUp circles and arcs** (center inference, radius and segments in Entity Info): holes, pins, cylinders and truncated cones get native end circles. When a native rebuild is not possible (e.g. arcs of a rounded edge), the segments are welded into a single-click selectable curve.
- **Set Subtract Color** — Pick a color from a selected object to mark which solids should be subtracted during Combine All operations.
- **Set Repair Options** — Configure the circle/arc restoration behavior: auto-repair toggle, "large object" edge threshold (above which restoration can be skipped for performance), and minimum segments for arc detection (tradeoff between catching short arcs and avoiding false positives).

All operations use SketchUp Pro's native boolean engine for maximum reliability.

## Requirements

- **SketchUp Pro** (2017 or later) — the native boolean methods (`union`, `outer_shell`, `subtract`) are Pro-only features. In SketchUp Make or Free, Combine All shows a "PRO Only" message.
- Circle and arc restoration works in every version (native circles). Only the weld fallback (a single curve when a native rebuild is not possible) needs **SketchUp 2020.1+** (`Entities#weld`).

## Installation

1. Download `solid_batch.rbz` from the [Releases](../../releases) page
2. In SketchUp: **Window > Extension Manager > Install Extension**
3. Select the `.rbz` file
4. The toolbar and menu appear under **Extensions > Solid Batch**

## Quick Start

1. Paint the objects you want to subtract with a specific color (e.g. red)
2. Use **Set Subtract Color** to register that color
3. Select all your solids (bases + tools)
4. Click **Combine All (Union)** or **Combine All (Shell)**
5. Done — one solid, one undo step

## Documentation

- [User Manual (English)](docs/USER_MANUAL_EN.md)
- [Manuel utilisateur (Francais)](docs/USER_MANUAL_FR.md)
- [Functional Specification (English)](docs/FSD_EN.md)
- [Specification fonctionnelle (Francais)](docs/FSD_FR.md)

## Tests (developers)

An automatic test battery is in `tools/tests` (not shipped in the `.rbz`). With SketchUp closed, `powershell -File tools\tests\run_tests.ps1` installs the plugin of the project into SketchUp 2021 and SketchUp 2017, runs the tests in a new model of each, closes them and prints the report (`-Versions 2021` for one version). SketchUp is found through the registry.

## Credits

Uses the native boolean operations built into SketchUp Pro.

`solid_batch/solid_operations.rb` is a Ruby boolean engine from Solid for Maker 1.0.1, based on [Eneroth Solid Tools](https://github.com/Eneroth3/eneroth-solid-tools) 3.0.0 by Julia Christina Eneroth (MIT license, see [solid_batch/LICENSE-solid-operations.txt](solid_batch/LICENSE-solid-operations.txt)).

## License

MIT License — see [LICENSE.md](LICENSE.md)

---

# Solid Batch — Plugin SketchUp Pro

**Operations booleennes par lot sur les solides, utilisant les outils natifs de SketchUp Pro.**

## Demo

[![Solid Batch Demo](https://img.youtube.com/vi/Zmjdbe_O_Cc/0.jpg)](https://youtu.be/y5_-0-7OkBw)

## Pourquoi Solid Batch ?

Lors de la conception de pieces techniques pour l'impression 3D dans SketchUp, une methode courante consiste a construire des formes complexes a partir de volumes simples — boites, cylindres, extrusions — puis a les combiner par operations booleennes a la fin de chaque etape ou tout a la fin du design. Executer manuellement les unions et soustractions sur des dizaines d'objets un par un est fastidieux et chronophage. Solid Batch automatise tout cela : selectionnez tous vos solides, un seul clic, et le plugin fusionne les bases et soustrait les outils en une seule operation.

## Fonctionnalites

- **Combine All (Union)** — Selectionnez plusieurs solides, fusionne automatiquement les solides de base puis soustrait les objets marques par couleur. Une seule etape d'annulation.
- **Combine All (Shell)** — Meme principe avec Outer Shell au lieu de Union (fusionne les volumes en une seule coque).
- **Restauration automatique des cercles et des arcs** — Les opérations booléennes natives cassent les cercles et les arcs en segments individuels. À la fin de chaque Combine All, Solid Batch les reconstruit en **vrais cercles et arcs natifs** de SketchUp (inférence du centre, rayon et segments dans *Infos sur l'entité*) : trous, tenons, cylindres et troncs de cône retrouvent des cercles natifs à leurs extrémités. Quand la reconstruction native est impossible (ex. arcs d'une arête arrondie), les segments sont soudés en une courbe sélectionnable en un clic.
- **Set Subtract Color** — Choisissez une couleur depuis un objet selectionne pour marquer les solides a soustraire.
- **Set Repair Options** — Configurer la restauration des cercles et arcs : toggle auto-repair, seuil "gros objet" en edges (au-dessus duquel la restauration peut être ignorée pour la performance), et nombre minimum de segments pour la détection des arcs (compromis entre détection des arcs courts et évitement des faux positifs).

Toutes les operations utilisent le moteur booleen natif de SketchUp Pro pour une fiabilite maximale.

## Prerequis

- **SketchUp Pro** (2017 ou plus recent) — les methodes booleennes natives (`union`, `outer_shell`, `subtract`) sont exclusives a la version Pro. Sous SketchUp Make ou Free, Combine All affiche le message « PRO Only ».
- La restauration des cercles et arcs fonctionne dans toutes les versions (cercles natifs). Seule la soudure de secours (une courbe unique quand la reconstruction native est impossible) nécessite **SketchUp 2020.1+** (`Entities#weld`).

## Installation

1. Telecharger `solid_batch.rbz` depuis la page [Releases](../../releases)
2. Dans SketchUp : **Window > Extension Manager > Install Extension**
3. Selectionner le fichier `.rbz`
4. La barre d'outils et le menu apparaissent sous **Extensions > Solid Batch**

## Demarrage rapide

1. Peindre les objets a soustraire avec une couleur specifique (ex. rouge)
2. Utiliser **Set Subtract Color** pour enregistrer cette couleur
3. Selectionner tous vos solides (bases + outils)
4. Cliquer sur **Combine All (Union)** ou **Combine All (Shell)**
5. Termine — un seul solide, un seul Ctrl+Z

## Documentation

- [User Manual (English)](docs/USER_MANUAL_EN.md)
- [Manuel utilisateur (Francais)](docs/USER_MANUAL_FR.md)
- [Functional Specification (English)](docs/FSD_EN.md)
- [Specification fonctionnelle (Francais)](docs/FSD_FR.md)

## Tests (developpeurs)

Une batterie de tests automatique se trouve dans `tools/tests` (non livrée dans le `.rbz`). SketchUp fermé, `powershell -File tools\tests\run_tests.ps1` installe le plugin du projet dans SketchUp 2021 et SketchUp 2017, lance les tests dans un modèle neuf de chacun, les ferme et affiche le rapport (`-Versions 2021` pour une seule version). SketchUp est trouvé par le registre.

## Credits

Utilise les operations booleennes natives de SketchUp Pro.

`solid_batch/solid_operations.rb` est un moteur booléen Ruby issu de Solid for Maker 1.0.1, basé sur [Eneroth Solid Tools](https://github.com/Eneroth3/eneroth-solid-tools) 3.0.0 de Julia Christina Eneroth (licence MIT, voir [solid_batch/LICENSE-solid-operations.txt](solid_batch/LICENSE-solid-operations.txt)).

## Licence

MIT License — voir [LICENSE.md](LICENSE.md)
