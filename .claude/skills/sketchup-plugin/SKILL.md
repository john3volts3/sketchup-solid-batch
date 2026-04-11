---
name: sketchup-plugin
description: Directives de developpement obligatoires pour plugins SketchUp (Ruby API) — structure, API, workflow, livraison, FSD
user-invocable: true
---

# Directives de developpement — Plugins SketchUp (Ruby API)

## 1. Structure d'un plugin SketchUp

```
nom_plugin.rb                    # Loader principal (point d'entree)
nom_plugin/
  main.rb                        # Logique principale
  version.rb                     # Constante VERSION
  icons/
    nom_16.png                   # Icone toolbar 16x16
    nom_24.png                   # Icone toolbar 24x24
```

- Module Ruby : `NomPlugin` en CamelCase (ex: `MonPlugin`, `ToolBox`)
- Fichiers/dossiers : `nom_plugin.rb`, `nom_plugin/` en snake_case (ex: `mon_plugin.rb`, `tool_box/`)
- Le loader `.rb` utilise `SketchupExtension` + `Sketchup.register_extension`
- Le `main.rb` contient la logique, les menus et la toolbar
- Guard `unless @loaded` pour eviter les doublons de menu/toolbar au reload

## 2. Coherence de nommage

- Le **nom affiche** du plugin (ex: `Mon Plugin`) doit etre **strictement identique** dans :
  - Le champ `name` du `SketchupExtension.new` (Extension Manager)
  - Le sous-menu dans `Extensions` (`UI.menu('Extensions').add_submenu('Mon Plugin')`)
  - Le titre de la toolbar (`UI::Toolbar.new('Mon Plugin')`)
  - Le namespace du registre SketchUp (`Sketchup.read_default('MonPlugin', ...)`)
  - Les logs console (`puts "[Mon Plugin] ..."`)
- **Ne JAMAIS** utiliser des variantes (abrege, casse differente, traduction) entre ces emplacements.

## 3. Recherche API obligatoire avant implementation

**Avant d'ecrire du code**, surtout pour des operations geometriques complexes :

1. **Rechercher les methodes API disponibles** dans la documentation SketchUp Ruby API.
2. Lister 2-3 approches possibles avec avantages/inconvenients.
3. **Privilegier les algorithmes eprouves** (ex: pattern Eneroth Solid Tools pour les booleennes) plutot que des approches custom.
4. Ne commencer a coder qu'apres validation de l'approche par l'utilisateur.

**Ne PAS** tenter des approches booleennes geometriques personnalisees — elles echouent presque toujours. Utiliser des algorithmes deja valides comme reference.

## 4. API SketchUp — Points critiques

### Creation de geometrie

- `entities.add_line(pt1, pt2)` : cree un edge mais ne declenche PAS la detection de faces
- `entities.add_face(points)` : cree une face explicitement
- **`edge.find_faces`** : INDISPENSABLE apres `add_line` pour la detection/creation de faces
- `edge.split(0.5)` : coupe un edge en deux au milieu

### Detection de geometrie sur une face

- **`face.classify_point(point)`** : 1=PointInside, 2=PointOnVertex, 4=PointOnEdge, 8=PointOutside, 16=PointNotOnPlane

### Pattern fiable pour forcer la re-detection de faces

```ruby
pt1 = edge.start.position.clone
pt2 = edge.end.position.clone
edge.erase!
new_edge = entities.add_line(pt1, pt2)
new_edge.find_faces if new_edge
```

### Operations undoable

```ruby
model.start_operation('NomOperation', true)
begin
  # ... modifications ...
  model.commit_operation
rescue => e
  model.abort_operation
  UI.messagebox("Error: #{e.message}", MB_OK)
end
```

### Operations transparentes — batch rapide avec undo unique

```ruby
first_op = true
items.each do |item|
  model.start_operation('Batch Op', true, false, !first_op)
  first_op = false
  # ... operation sur item ...
  model.commit_operation
end
```

### Barre de statut — progression

```ruby
Sketchup.status_text = "Mon Plugin — Etape #{current}/#{total} (#{pct}%)"
```

### Contexte actif

- Toujours utiliser `model.active_entities` (pas `model.entities`) pour travailler dans le contexte d'edition actuel

## 5. Tolerances geometriques

- Les tolerances pour les checks geometriques (coplanarite, distance) doivent etre **proportionnelles au rayon/taille** de l'objet, pas absolues.
- Coplanarite : normaliser les vecteurs avant le dot product (`v.normalize!` puis `v.dot(normal).abs < 0.01`)
- Distance : `[tolerance_base, rayon * 0.005].max`
- Une tolerance absolue de 0.1 echoue pour les grands objets (r>300).

## 6. Workflow de developpement

### Copie directe dans les plugins

```bash
cp nom_plugin/main.rb "%APPDATA%/SketchUp/SketchUp <version>/SketchUp/Plugins/nom_plugin/main.rb"
```

**Toujours copier les fichiers modifies vers le dossier plugins** apres chaque modification.

### Rechargement sans redemarrer SketchUp

```ruby
load 'nom_plugin/main.rb'
```

**Quand le reload suffit** : modification de logique, methodes, algorithmes.
**Quand il FAUT redemarrer** : icones, nouveaux boutons/menus, loader, version.rb.

### Construction du .RBZ

```powershell
Compress-Archive -Path 'nom_plugin.rb','nom_plugin' -DestinationPath 'build/nom_plugin.zip' -Force
Rename-Item 'build/nom_plugin.zip' 'nom_plugin.rbz' -Force
```

### Chemin plugins SketchUp

```
Windows : %APPDATA%/SketchUp/SketchUp <version>/SketchUp/Plugins/
macOS   : ~/Library/Application Support/SketchUp <version>/SketchUp/Plugins/
```

## 7. Cercles et ArcCurve

- Les cercles/arcs sont des objets `Sketchup::ArcCurve` — si on `erase!` leurs edges et qu'on les retrace avec `add_line`, l'objet ArcCurve est detruit.
- Pour preserver les cercles/arcs, sauvegarder les parametres AVANT d'effacer, puis recreer avec `entities.add_arc(...)`.
- `entities.weld(edges)` regroupe des edges libres en Curve (disponible depuis SketchUp 2020.1).

## 8. Erreurs courantes a eviter

1. Ne JAMAIS compter sur `add_line` pour declencher la creation de faces → toujours appeler `find_faces`
2. Ne JAMAIS supprimer des edges de trous en pensant les retracer — les faces du trou disparaissent aussi
3. `entityID` change quand une entite est detruite/recree par `find_faces`
4. `face.plane` retourne `[a, b, c, d]` — utiliser pour tester la coplanarite entre faces

## 9. Specification fonctionnelle (FSD)

- Maintenir un fichier `FSD.md` a la racine de chaque projet plugin SketchUp.
- Le FSD decrit les fonctionnalites du plugin, son algorithme, ses entrees/sorties et ses limitations.
- Mettre a jour le FSD a chaque changement fonctionnel.

## 10. Livraison

**AVANT de livrer**, verifier CLAUDE.md et .claude/skills/ pour s'assurer de suivre le processus de livraison complet du projet.

Quand l'utilisateur demande une **livraison** (ou dit "livraison"), executer systematiquement ces etapes :

1. Mettre a jour `JOURNAL.md` avec les modifications de la session
2. Mettre a jour `FSD.md` pour refleter les changements fonctionnels
3. Mettre a jour la documentation utilisateur si applicable
4. Reconstruire le `.rbz` dans `build/`
5. Copier les fichiers modifies dans le dossier plugins SketchUp (`%APPDATA%/SketchUp/SketchUp <version>/SketchUp/Plugins/` sur Windows)
6. Copier ce skill dans le repository (`.claude/skills/sketchup-plugin/SKILL.md`) et le mettre a jour si des directives ont evolue durant la session
7. Commit et push (en utilisant la methode PowerShell pour le git sur NAS)
