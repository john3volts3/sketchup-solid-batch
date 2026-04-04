# Solid Batch — SketchUp Pro Plugin

**Batch solid boolean operations using native SketchUp Pro tools.**

*[Version francaise ci-dessous](#solid-batch--plugin-sketchup-pro)*

---

## Demo

https://github.com/user-attachments/assets/demo.mp4

> *See [docs/demo.mp4](docs/demo.mp4) if the video doesn't play above.*

## Why Solid Batch?

When designing technical parts for 3D printing in SketchUp, a common workflow is to build up complex shapes from simple volumes — boxes, cylinders, extrusions — then combine them using boolean operations at the end of each design stage or at the very end. Manually running union and subtract on dozens of objects one by one is tedious and time-consuming. Solid Batch automates this: select all your solids, click once, and the plugin unions the bases and subtracts the tools in a single batch operation.

## Features

- **Combine All (Union)** — Select multiple solids, automatically union all base solids then subtract color-marked objects. Single undo step.
- **Combine All (Shell)** — Same workflow using Outer Shell instead of Union (merges overlapping volumes into one shell).
- **Set Subtract Color** — Pick a color from a selected object to mark which solids should be subtracted during Combine All operations.

All operations use SketchUp Pro's native boolean engine for maximum reliability.

## Requirements

- **SketchUp Pro** (2017 or later) — the native boolean methods (`union`, `outer_shell`, `subtract`) are Pro-only features.

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

## Credits

Inspired by the excellent [Eneroth Solid Tools](https://github.com/Eneroth3/eneroth-solid-tools) by **Julia Christina Eneroth** (MIT License, 2017).

## License

MIT License — see [LICENSE.md](LICENSE.md)

---

# Solid Batch — Plugin SketchUp Pro

**Operations booleennes par lot sur les solides, utilisant les outils natifs de SketchUp Pro.**

## Demo

> *Voir la video ci-dessus ou [docs/demo.mp4](docs/demo.mp4)*

## Pourquoi Solid Batch ?

Lors de la conception de pieces techniques pour l'impression 3D dans SketchUp, une methode courante consiste a construire des formes complexes a partir de volumes simples — boites, cylindres, extrusions — puis a les combiner par operations booleennes a la fin de chaque etape ou tout a la fin du design. Executer manuellement les unions et soustractions sur des dizaines d'objets un par un est fastidieux et chronophage. Solid Batch automatise tout cela : selectionnez tous vos solides, un seul clic, et le plugin fusionne les bases et soustrait les outils en une seule operation.

## Fonctionnalites

- **Combine All (Union)** — Selectionnez plusieurs solides, fusionne automatiquement les solides de base puis soustrait les objets marques par couleur. Une seule etape d'annulation.
- **Combine All (Shell)** — Meme principe avec Outer Shell au lieu de Union (fusionne les volumes en une seule coque).
- **Set Subtract Color** — Choisissez une couleur depuis un objet selectionne pour marquer les solides a soustraire.

Toutes les operations utilisent le moteur booleen natif de SketchUp Pro pour une fiabilite maximale.

## Prerequis

- **SketchUp Pro** (2017 ou plus recent) — les methodes booleennes natives (`union`, `outer_shell`, `subtract`) sont exclusives a la version Pro.

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

## Credits

Inspire par l'excellent [Eneroth Solid Tools](https://github.com/Eneroth3/eneroth-solid-tools) de **Julia Christina Eneroth** (licence MIT, 2017).

## Licence

MIT License — voir [LICENSE.md](LICENSE.md)
