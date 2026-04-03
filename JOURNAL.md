# Journal des modifications — Solid Ops

## Session du 2026-04-03

- **dro_solid_ops.rb** — Création du loader principal (SketchupExtension, register_extension)
- **dro_solid_ops/version.rb** — Constante VERSION 1.0.0
- **dro_solid_ops/main.rb** — Menu Extensions > Solid Ops (Union, Subtract, Split), toolbar avec 3 commandes, validation de la sélection (solides manifold)
- **dro_solid_ops/boolean_ops.rb** — Moteur booléen complet :
  - Union : fusion de N solides avec préservation des vides internes, suppression des faces internes via raycast
  - Subtract : soustraction base - outil, inversion des normales des faces conservées de l'outil
  - Split : découpe en 3 pièces max (A-B, B-A, A∩B) via make_subtraction et make_intersection
  - Utilitaires : raycast inside/outside, intersection via intersect_with, nettoyage edges orphelins
