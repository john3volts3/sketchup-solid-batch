# Journal des modifications — Solid Ops

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
