# Accélération de `repair_holes` (reconstruction des cercles natifs)

> Document de référence, écrit le 2026-10-24 dans le projet **Solid for Maker** (dépôt `sketchup-solid-for-maker`, commit `ee7a296`, fichier `solid_for_maker/circle_restore/volume.rb`). Il est copié dans chaque plugin qui contient la même méthode, pour pouvoir y demander l'optimisation le moment venu. Il se suffit à lui-même : tout le code nécessaire est ci-dessous.
>
> **Décision de l'utilisateur (2026-10-24)** : ne reporter cette optimisation dans un plugin que lorsqu'il le demande, dans une session de ce plugin, et **après s'être assuré qu'elle ne casse rien** (voir § 7) : la réparation des trous a été difficile à obtenir.

## 1. Résumé

`repair_holes` (moteur Push/Pull des cylindres, issu de Re-Cercle v2.0.0) retrouvait l'arête de chaque ancien trou en **parcourant toutes les arêtes de la pièce pour chaque trou**. Sur une face percée de nombreux trous, ce travail devient quadratique. La nouvelle version range une fois les sommets et les points des trous dans des **grilles** de cases de la taille de la tolérance, et n'interroge que les cases voisines. Mêmes tolérances, même ordre des opérations, mêmes faces effacées.

| Plaque de 30 trous (60 cercles), SketchUp Make 2017 | Avant | Après |
|---|---|---|
| Union (120 cercles) | 87 s | 7,5 s |
| Subtract (60 cercles) | 34 s | 5,2 s |
| Trim (60 cercles) | 38 s | 5,2 s |
| Outer Shell (120 cercles) | 64 s | 8,9 s |
| 30 cylindres séparés (60 cercles, pas d'« autres trous ») | 1,4 s | 1,7 s |

## 2. Le problème

**Profil** (Solid for Maker, plaque de 100 × 100 mm percée de 30 trous de 4 mm) : `Volume.repair_holes` = **85 à 89 %** du temps de la reconstruction des cercles, ≈ 1 s par cylindre reconstruit ; tout le reste négligeable.

**Cause.** Pour chaque cylindre reconstruit, `snapshot_holes` mémorise les **autres trous** des faces qui touchent ses cercles (ici les 29 autres trous de la plaque, 24 points chacun). Après le Push/Pull, `repair_holes` fait, **pour chacun de ces trous** :

```ruby
edge = entities.grep(Sketchup::Edge).find do |ed|
  near.call(ed.start.position, h) && near.call(ed.end.position, h)
end
```

soit ≈ 2 000 arêtes × 2 extrémités × 24 distances, multiplié par 29 trous : **≈ 2,8 millions de calculs de distance par cylindre**, puis 30 à 60 cylindres. Le contrôle final des « faces qui bouchent un ancien trou » compare aussi chaque point à tous les points de tous les trous.

Le temps ne dépend donc pas du nombre de cercles mais de la **face qui les porte** : 60 cercles sur 30 cylindres séparés (sans autres trous) prennent 1,4 s.

## 3. Principe de la correction

1. Les **sommets** de la pièce (extrémités des arêtes) sont rangés **une fois** dans une grille : `Hash` de case `[i, j, k]` → sommets, avec des cases de la taille de la tolérance (`tol = BASE_TOL * 10`).
2. Les **points de chaque trou** sont rangés dans leur propre grille.
3. Pour retrouver une arête d'un trou : pour chaque point du trou (dans l'ordre), on prend les sommets proches dans la grille, puis parmi leurs arêtes une arête dont **l'autre extrémité** est aussi sur le trou. En pratique, le premier point suffit.
4. « Proche » = distance < `tol`. Avec des cases de côté `tol`, tout point à moins de `tol` est dans l'une des **27 cases** autour de la case du point : la recherche est exacte, pas approchée.
5. Le contrôle des faces qui bouchent un ancien trou utilise la grille du trou au lieu de comparer à tous ses points.

## 4. Code d'origine (identique dans les 5 plugins, à l'indentation près)

```ruby
# A face rebuilt on the plane of a former hole may lie over its edges without
# being split: find_faces on one hole edge splits it (no edge is erased, so the
# hole circle stays native), then new faces filling a former hole are erased.
def self.repair_holes(entities, holes, existing)
  tol = Detector::BASE_TOL * 10
  near = ->(p, h) { h.any? { |q| p.distance(q) < tol } }
  holes.each do |h|
    edge = entities.grep(Sketchup::Edge).find do |ed|
      near.call(ed.start.position, h) && near.call(ed.end.position, h)
    end
    edge.find_faces if edge
  end
  entities.grep(Sketchup::Face).each do |f|
    next if !f.valid? || existing[f.entityID]
    pts = f.outer_loop.vertices.map(&:position)
    filled = holes.any? do |h|
      h.length == pts.length && pts.all? { |p| near.call(p, h) }
    end
    f.erase! if filled
  end
end
```

## 5. Code accéléré (à mettre à la place, dans le même module)

Ruby 2.2 compatible (SketchUp 2017) : aucune syntaxe nouvelle.

```ruby
# A face rebuilt on the plane of a former hole may lie over its edges without
# being split: find_faces on one hole edge splits it (no edge is erased, so the
# hole circle stays native), then new faces filling a former hole are erased.
#
# Hole points and vertices are indexed once in grids of tolerance-sized
# cells: scanning every edge for every hole made a plate with many holes take
# about 1 s per rebuilt cylinder.
def self.repair_holes(entities, holes, existing)
  tol = Detector::BASE_TOL * 10
  hole_grids = holes.map { |h| point_grid(h, tol) }
  vertex_grid = {}
  entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.each do |v|
    (vertex_grid[cell_of(v.position, tol)] ||= []) << v
  end
  holes.each_with_index do |h, i|
    edge = hole_edge(h, hole_grids[i], vertex_grid, tol)
    edge.find_faces if edge
  end
  entities.grep(Sketchup::Face).each do |f|
    next if !f.valid? || existing[f.entityID]
    pts = f.outer_loop.vertices.map(&:position)
    filled = holes.each_with_index.any? do |h, i|
      h.length == pts.length && pts.all? { |p| near_grid?(p, hole_grids[i], tol) }
    end
    f.erase! if filled
  end
end

# An edge whose both ends lie on the hole points (any of them suits
# find_faces), found through the vertices near the hole points.
def self.hole_edge(points, grid, vertex_grid, tol)
  points.each do |q|
    near_items(q, vertex_grid, tol) { |v| v.position }.each do |v|
      v.edges.each do |ed|
        return ed if near_grid?(ed.other_vertex(v).position, grid, tol)
      end
    end
  end
  nil
end

# Grid of points: cell => points of that cell.
def self.point_grid(points, tol)
  grid = {}
  points.each { |p| (grid[cell_of(p, tol)] ||= []) << p }
  grid
end

def self.cell_of(p, tol)
  [(p.x.to_f / tol).floor, (p.y.to_f / tol).floor, (p.z.to_f / tol).floor]
end

# Items of the grid closer than tol to p: with tol-sized cells they lie
# in the 27 cells around p's cell.
def self.near_items(p, grid, tol)
  cx, cy, cz = cell_of(p, tol)
  found = []
  (-1..1).each do |dx|
    (-1..1).each do |dy|
      (-1..1).each do |dz|
        items = grid[[cx + dx, cy + dy, cz + dz]]
        next unless items
        items.each do |item|
          position = block_given? ? yield(item) : item
          found << item if p.distance(position) < tol
        end
      end
    end
  end
  found
end

def self.near_grid?(p, grid, tol)
  !near_items(p, grid, tol).empty?
end
```

## 6. Pourquoi le résultat est le même

- **Même tolérance** (`BASE_TOL * 10`), même test « distance < tol » : la grille ne fait que limiter les candidats ; une case de côté `tol` garantit que tout point à moins de `tol` est dans les 27 cases voisines (vérifié contre le balayage complet : 2 000 points au hasard, coordonnées négatives comprises, **0 écart**).
- **Même ordre** : les trous sont traités dans le même ordre, `find_faces` est appelé une fois par trou, puis le même contrôle des faces.
- **Seule différence** : l'arête choisie pour `find_faces`. L'original prenait la première arête dans l'ordre des entités dont les deux extrémités sont sur le trou ; la nouvelle version prend une arête du même trou trouvée depuis ses points. Toute arête du trou convient à `find_faces` (c'est le même contour). Les deux versions partagent la même ambiguïté théorique (une corde qui relierait deux points du trou), jamais rencontrée.
- Les sommets indexés restent valides pendant la boucle : `find_faces` crée des faces, pas de sommets.

## 7. Validation

### Déjà faite dans Solid for Maker (2026-10-24)

- Kit de non-régression sous SketchUp Make 2017 : **270 opérations correctes**, résultats **identiques** à l'ancienne méthode (volume, solide, nombre de faces, nombre de cercles natifs) sur 9 modèles (cas générés et modèles de test d'Eneroth Solid Tools), avec la reconstruction des cercles après chaque opération.
- Tests à la main : Subtract d'un trou traversant → cercle natif (un clic le sélectionne, *Entity Info* : rayon et segments), un seul Ctrl+Z.
- **Limite** : les trous du kit restent simples (traversants, borgnes, plaque à 30 trous).

### À faire avant d'appliquer dans un autre plugin (recommandé)

Comparer l'ancienne et la nouvelle méthode **sur la même géométrie** :

1. Garder temporairement l'ancienne sous un autre nom (`repair_holes_scan`).
2. Sur chaque cas de test, dans une opération **annulée** : reconstruire avec l'ancienne, mémoriser les faces (nombre, aires, matériaux, positions des sommets triées) ; annuler ; reconstruire avec la nouvelle ; comparer.
3. Cas à couvrir, en plus des trous simples : plaque à nombreux trous ; trou près d'un bord ; face colorée (matériau recto / verso) ; cylindre qui traverse plusieurs faces ; très petits et très grands trous ; fraisurage ou chambrage (cercles partagés) ; trous dans plusieurs faces de la même pièce ; tronc de cône ; cylindre dont une seule extrémité est cassée.
4. Mesurer le temps avant / après sur la plaque à nombreux trous.
5. Retirer `repair_holes_scan` quand tout est identique.

## 8. Adaptation par plugin

| Plugin | Fichier | Module | Tolérance | Remarque |
|---|---|---|---|---|
| Re-Cercle 2.0.0 | `re_cercle/volume.rb` (≈ l. 367) | `ReCercle::Volume` | `Detector::BASE_TOL` | — |
| Cylinder Resize 0.3.0 | `cylinder_resize/rebuilder.rb` (≈ l. 279) | `CylinderResize::Rebuilder` | `Detector::BASE_TOL` | `repair_holes` est dans `rebuilder.rb`, pas dans `volume.rb` |
| Solid Procedural 1.0.0 | `solid_procedural/circle_restore/volume.rb` (≈ l. 372) | `SolidProcedural::CircleRestore::Volume` | `Detector::BASE_TOL` | Voulu par l'utilisateur, avec M1 à M3 |
| Solid Batch 2.3.0 | `solid_batch/circle_restore/volume.rb` (≈ l. 372) | `SolidBatch::CircleRestore::Volume` | `Detector::BASE_TOL` | **Fait** (2026-10-26, pour la 2.4.0) : validé par la batterie (`tools/tests`, T11 et T12 : 13 cas identiques sous SketchUp 2021) ; plaque à 20 trous 9,6 → 2,2 s |
| Circle Advanced 1.4.0 | `circle_advanced/volume.rb` (≈ l. 408) | `CircleAdvanced::Volume` | **`BASE_TOL`** (pas `Detector::`) | Écrire `tol = BASE_TOL * 10` ; le style du fichier utilise `lambda { … }` |

Aucun des 5 fichiers n'a déjà de méthodes `hole_edge`, `point_grid`, `cell_of`, `near_items` ou `near_grid?` (vérifié le 2026-10-24).

## 9. Étapes pour appliquer dans un plugin

1. Lire ce document et le code actuel du plugin (vérifier que `repair_holes` est toujours celui du § 4).
2. Plan d'action et accord de l'utilisateur (workflow habituel).
3. Validation ancienne / nouvelle (§ 7).
4. Remplacer `repair_holes` et ajouter les 5 méthodes (§ 5), avec la constante de tolérance du plugin (§ 8) ; noter le changement dans l'en-tête du fichier (« repair_holes finds the hole edges through grids… »).
5. `ruby -c`, déploiement, tests à la main (plaque à nombreux trous, trou traversant, trou borgne).
6. `JOURNAL.md`, `FSD.md` (limitation de performance levée), `PRD.md` si une exigence de performance existe ; commit après « Teste OK ».
