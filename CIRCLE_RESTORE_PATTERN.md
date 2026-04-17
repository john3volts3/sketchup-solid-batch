---
name: Pattern de restauration des cercles après opérations géométriques
description: Algorithme en 3 phases pour préserver les cercles (ArcCurve/Curve) lors d'opérations qui cassent les associations de courbes dans SketchUp
type: reference
---

# Restauration des cercles après opérations géométriques SketchUp

## Problème

Les opérations qui détruisent/recréent des edges (`edge.erase!` + `entities.add_line` + `edge.find_faces`, ou `subtract`, `union`, etc.) cassent les associations `ArcCurve` et `Curve` des cercles. Les cercles deviennent des suites de segments individuels — un clic ne sélectionne plus qu'un seul segment.

## Solution : algorithme en 3 phases

### Phase 1 — Inventaire des cercles AVANT toute modification

Doit s'exécuter **avant** toute opération qui modifie la géométrie (y compris `find_faces`).

```ruby
all_saved_circles = []
seen_curves = {}
entities.grep(Sketchup::Edge).each do |edge|
  next unless edge.valid?
  curve = edge.curve
  next unless curve && curve.valid?
  next if seen_curves[curve.entityID]
  seen_curves[curve.entityID] = true

  if curve.is_a?(Sketchup::ArcCurve)
    all_saved_circles << {
      center: curve.center.clone,
      normal: curve.normal.clone,
      radius: curve.radius,
      num_segments: curve.count_edges
    }
  else
    # Plain Curve: check if it's geometrically a circle
    points = curve.vertices.map(&:position)
    # IMPORTANT: Remove duplicate vertex if curve is a closed loop
    # (curve.vertices returns N+1 vertices for a closed N-edge curve)
    if points.length > 3 && points.first.distance(points.last) < 0.1
      points.pop
    end
    next if points.length < 3
    n = points.length.to_f
    cx = points.inject(0.0) { |s, p| s + p.x.to_f } / n
    cy = points.inject(0.0) { |s, p| s + p.y.to_f } / n
    cz = points.inject(0.0) { |s, p| s + p.z.to_f } / n
    center = Geom::Point3d.new(cx, cy, cz)

    dists = points.map { |p| p.distance(center).to_f }
    avg_r = dists.inject(0.0, :+) / dists.length
    max_dev = dists.map { |d| (d - avg_r).abs }.max
    next unless max_dev < 0.1

    v1 = center.vector_to(points[0])
    v2 = center.vector_to(points[points.length / 4])  # point at ~90°
    normal = v1.cross(v2)
    next if normal.length == 0
    normal.normalize!

    all_saved_circles << {
      center: center,
      normal: normal,
      radius: avg_r,
      num_segments: curve.count_edges
    }
  end
end
```

### Phase 2 — Opérations géométriques

Exécuter les opérations normalement (retrace, subtract, union, etc.). Les cercles seront cassés.

### Phase 3 — Restauration des cercles par weld

Après toutes les opérations, avant `commit_operation`.

```ruby
circles_welded = 0
all_saved_circles.each do |ci|
  # Find ALL edges matching this circle's geometry
  all_matching = []
  entities.grep(Sketchup::Edge).each do |e|
    next unless e.valid?
    p1 = e.start.position
    p2 = e.end.position
    d1 = (p1.distance(ci[:center]) - ci[:radius]).abs
    d2 = (p2.distance(ci[:center]) - ci[:radius]).abs
    next unless d1 < 0.1 && d2 < 0.1
    v1 = ci[:center].vector_to(p1)
    v2 = ci[:center].vector_to(p2)
    next unless v1.dot(ci[:normal]).abs < 0.1 && v2.dot(ci[:normal]).abs < 0.1
    all_matching << e
  end

  next if all_matching.length != ci[:num_segments]

  # Skip if all edges are already in the same Curve (circle intact)
  first_curve = all_matching.first.curve
  if first_curve && all_matching.all? { |e| e.curve == first_curve }
    next
  end

  # Weld only edges that lost their curve
  to_weld = all_matching.reject { |e| e.curve }
  if to_weld.length > 0
    entities.weld(to_weld)
    circles_welded += 1
  end
end
```

## Points critiques

- **Phase 1 DOIT être la première chose exécutée** — avant `find_faces`, `subtract`, `union`, ou toute opération modifiant la géométrie
- **Détecter les deux types** : `Sketchup::ArcCurve` (cercles natifs) ET `Sketchup::Curve` (cercles précédemment weldés)
- **Vertex dupliqué** : `curve.vertices` retourne N+1 vertices pour une Curve fermée de N edges — il faut retirer le doublon sinon le centroïde est décalé et la détection échoue
- **`entities.weld(edges)`** regroupe des edges libres en Curve (disponible depuis SketchUp 2020.1) — pas besoin d'effacer/recréer les edges
- **Matching géométrique** : tolérance de 0.1 pour la distance au rayon et la coplanarité (dot product avec la normale)
- **Ne pas filtrer par face** : scanner TOUTES les entities, pas seulement celles d'une face spécifique
- **Cercles intacts** : vérifier que tous les edges matchés sont dans la même Curve avant de skipper — ne pas comparer par centre/rayon seul (faux positifs entre cercles de même rayon)

## Plugins utilisant ce pattern

- `sketchup-retrace` (dro_retrace) — implémenté et testé
- `sketchup-solid-batch` — à implémenter
- `sketchup-solid-batch-ruby` — à implémenter
