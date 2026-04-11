# Solid Batch — Specification Fonctionnelle Detaillee

**Version :** 2.1.0
**Date :** 2026-04-11
**Auteur :** DRO

---

## 1. Objectif

Solid Batch est un plugin SketchUp Pro qui permet d'effectuer des operations booleennes par lot sur plusieurs solides en une seule action. Il cible les utilisateurs qui ont besoin de combiner et soustraire de nombreux objets solides efficacement (ex. modelisation architecturale, preparation pour impression 3D, assemblages mecaniques).

## 2. Perimetre

### Inclus
- Fusion par lot de plusieurs objets solides via l'API native SketchUp Pro
- Outer shell par lot de plusieurs objets solides via l'API native SketchUp Pro
- Soustraction par lot des objets solides marques par couleur depuis le resultat fusionne
- Identification persistante par couleur des objets a soustraire
- Etape d'annulation unique pour toute l'operation par lot
- Restauration automatique des cercles cassés sur le résultat (les opérations booléennes natives détruisent les `ArcCurve` ; le plugin reweld les segments en cercles sélectionnables en un clic)
- Seuil configurable pour désactiver la restauration sur les très gros objets (performance)

### Exclu
- Moteur booleen custom (supprime en v2.0 — le plugin repose entierement sur les methodes natives Pro)
- Operations individuelles union/subtract/split (disponibles nativement dans SketchUp Pro)
- Compatibilite SketchUp Make / Free

## 3. Utilisateurs cibles

- Architectes et designers travaillant avec des modeles multi-solides complexes dans SketchUp Pro
- Utilisateurs qui fusionnent frequemment de nombreux solides en un seul (murs + ouvertures, assemblages, moules)
- Utilisateurs preparant des modeles pour l'impression 3D ou le calcul de volume

## 4. Exigences

### 4.1 Exigences systeme

| Exigence | Valeur |
|----------|--------|
| Version SketchUp | Pro 2017 ou plus recent |
| Systeme d'exploitation | Windows / macOS (tout OS supporte par SketchUp) |
| Methodes Ruby API | `Group#union`, `Group#outer_shell`, `Group#subtract`, `Group#manifold?` |

### 4.2 Exigences fonctionnelles

#### EF-01 : Combine All (Union)

| Champ | Description |
|-------|-------------|
| **Entree** | Selection de 2+ groupes/composants solides |
| **Precondition** | Au moins un solide ne doit PAS avoir la couleur de soustraction |
| **Traitement** | 1. Separer la selection en solides de base et solides-outils par couleur de soustraction. 2. Fusionner sequentiellement tous les solides de base avec `Group#union`. 3. Soustraire sequentiellement tous les solides-outils avec `Group#subtract`. |
| **Sortie** | Un seul groupe/composant solide contenant le resultat |
| **Annulation** | L'operation entiere est annulee par un seul Ctrl+Z |
| **Gestion d'erreur** | Si une etape echoue, abandonner et annuler ; afficher un message d'erreur avec le numero d'etape |

#### EF-02 : Combine All (Shell)

| Champ | Description |
|-------|-------------|
| **Entree** | Selection de 2+ groupes/composants solides |
| **Precondition** | Au moins un solide ne doit PAS avoir la couleur de soustraction |
| **Traitement** | Identique a EF-01 mais la Phase 1 utilise `Group#outer_shell` au lieu de `Group#union` |
| **Sortie** | Un seul groupe/composant solide (enveloppe exterieure uniquement) |
| **Annulation** | L'operation entiere est annulee par un seul Ctrl+Z |
| **Gestion d'erreur** | Identique a EF-01 |

#### EF-03 : Set Subtract Color

| Champ | Description |
|-------|-------------|
| **Entree** | Selection contenant au moins un groupe/composant avec un materiau applique |
| **Traitement** | Lire la couleur du materiau de la premiere entite correspondante ; persister les valeurs RGB dans le registre SketchUp |
| **Sortie** | Message de confirmation affichant la couleur RGB enregistree |
| **Persistance** | La couleur est stockee dans le registre SketchUp sous le namespace `SolidBatch` ; survit au redemarrage de l'application |
| **Defaut** | Rouge (255, 0, 0) si aucune couleur n'a ete definie |

#### EF-04 : Set Repair Options

| Champ | Description |
|-------|-------------|
| **Entree** | Aucune sélection requise |
| **Traitement** | Ouvre une `UI.inputbox` avec deux champs : `Auto-repair circles on large objects` (Yes/No) et `Large object threshold (edges)` (entier). Persiste les deux valeurs dans le registre SketchUp. |
| **Sortie** | Messagebox récapitulatif des deux valeurs sauvegardées |
| **Persistance** | Stockage sous `SolidBatch/auto_repair_large` (string Yes/No) et `SolidBatch/large_threshold` (entier) |
| **Defauts** | `Yes` et `10000` edges |

#### EF-05 : Restauration automatique des cercles (Phase 3 de Combine All)

| Champ | Description |
|-------|-------------|
| **Entree** | Le solide résultant des phases 1 et 2 de Combine All |
| **Precondition** | `result.valid?` |
| **Traitement** | 1. Compter les edges du résultat (`CircleRestore.count_edges`). 2. Si `edge_count <= threshold` OU `auto_repair_large == 'Yes'` → exécuter `CircleRestore.restore_in_solid` qui détecte les cercles par circumcircle et `entities.weld()` les segments en Curve. 3. Sinon → afficher une messagebox modale expliquant que la réparation est ignorée et comment l'activer. |
| **Sortie** | Cercles reconstitués comme `Sketchup::Curve` sélectionnables en un clic, OU messagebox modale si skippé |
| **Algorithme** | Adapté du plugin Re-Cercle (Claude Code, 2026) — détection en 2 étapes : (1) edges libres groupés par circumcircle puis weld, (2) fragments de Curves regroupés par centre/rayon/normale puis weld |
| **Constantes** | `MIN_SEGMENTS = 8`, `TOLERANCE = 0.1` (adaptative selon le rayon) |
| **Annulation** | Phase 3 chaînée à l'undo unique des phases 1/2 via opération transparente |

#### EF-06 : Validation des solides

| Champ | Description |
|-------|-------------|
| **Entree** | Selection courante |
| **Traitement** | Filtrer les entites en Groupes et ComposantInstances qui passent le test `manifold?` |
| **Sortie** | Tableau de solides valides, ou message d'erreur si moins que le minimum requis |

### 4.3 Exigences non fonctionnelles

| ID | Exigence |
|----|----------|
| ENF-01 | Pas de moteur booleen custom — reposer exclusivement sur les methodes natives SketchUp Pro |
| ENF-02 | Etape d'annulation unique pour toutes les operations par lot |
| ENF-03 | La couleur de soustraction persiste entre les sessions via le registre SketchUp |
| ENF-04 | Journalisation console (`puts`) pour chaque etape d'operation pour le debogage |
| ENF-05 | Gestion d'erreur gracieuse avec abandon + annulation en cas d'echec |
| ENF-06 | Affichage de la progression dans la barre de statut pendant les operations batch (`Solid Batch — Subtract 7/13 (54%)`) |
| ENF-07 | Operations transparentes : chaque etape booleenne a son propre start/commit (petits deltas rapides) chainees via `transparent = true` pour un seul undo |
| ENF-08 | Restauration des cercles applicable uniquement à la fin (Phase 3), jamais à chaque étape intermédiaire — performance et fiabilité |
| ENF-09 | Le seuil `large_threshold` et le toggle `auto_repair_large` persistent dans le registre SketchUp |

## 5. Architecture

### 5.1 Structure des fichiers

```
solid_batch.rb                # Point d'entree — enregistrement de l'extension
solid_batch/
  version.rb                  # Constante VERSION
  main.rb                     # Menu, toolbar, commandes, logique metier
  circle_restore.rb           # Module CircleRestore — restauration des cercles
  icons/
    combine_pro_union_16.png  # Icones toolbar (16px et 24px)
    combine_pro_union_24.png
    combine_pro_shell_16.png
    combine_pro_shell_24.png
    setcolor_16.png
    setcolor_24.png
    repair_circles_16.png     # Nouvelle icône Set Repair Options
    repair_circles_24.png
```

### 5.2 Structure du module

```
SolidBatch                  # Namespace principal
  PLUGIN_DIR                  # Chemin du repertoire du plugin
  PLUGIN_NAME                 # "Solid Batch"
  VERSION                     # "2.1.0"

  # Gestion des couleurs
  subtract_color()            # Lire la couleur persistee
  save_subtract_color(color)  # Ecrire la couleur dans le registre
  color_match?(c1, c2)        # Comparer deux couleurs par RGB
  is_subtract_solid?(entity)  # Verifier si l'entite a la couleur de soustraction

  # Options de réparation des cercles
  auto_repair_large()         # Lire le toggle Yes/No persisté
  save_auto_repair_large(v)   # Écrire le toggle dans le registre
  large_threshold()           # Lire le seuil edges persisté
  save_large_threshold(v)     # Écrire le seuil dans le registre

  # Validation
  get_solids(min_count)        # Filtrer la selection aux solides valides

  # Commandes
  do_combine_all_pro(mode)    # Union/shell + soustraction par lot + restauration cercles
  do_set_subtract_color()     # Enregistrer la couleur de soustraction
  do_set_repair_options()     # Configurer auto-repair + seuil

SolidBatch::CircleRestore   # Module de restauration des cercles
  TOLERANCE                   # 0.1
  MIN_SEGMENTS                # 8
  count_edges(solid)          # Compte récursif des edges
  restore_in_solid(solid)     # Restauration en 2 étapes, retourne nb cercles welded
  # + helpers internes : circumcircle, closed_chain?, group_by_circle_geometry, etc.
```

### 5.3 Flux d'operation

```
L'utilisateur clique "Combine All (Union)" ou "(Shell)"
  |
  v
get_solids(2) — valider la selection
  |
  v
Verifier la disponibilite de la methode native (respond_to?)
  |
  v
Separer les solides par couleur de soustraction
  |
  v
Phase 1 : union/outer_shell sequentiel des solides de base
  |   Pour chaque etape :
  |     start_operation(transparent = !first_op)
  |     base[0].union(base[1]) -> commit
  |     start_operation(transparent = true)
  |     result.union(base[2]) -> commit -> ...
  |
  +---> Phase 2 : soustraction sequentielle des solides-outils
  |   Pour chaque etape :
  |     start_operation(transparent = true)
  |     tool[0].subtract(result) -> commit
  |     tool[1].subtract(result) -> commit -> ...
  |
  +---> Barre de statut : "Solid Batch — Subtract 7/13 (54%)"
  |
  +---> Phase 3 : restauration des cercles sur le résultat final
  |   edge_count = CircleRestore.count_edges(result)
  |   si edge_count <= threshold OU auto_repair_large == 'Yes' :
  |     start_operation(transparent = true)
  |     CircleRestore.restore_in_solid(result) -> commit
  |   sinon :
  |     UI.messagebox modale "Repair skipped"
  |
  v
Toutes les etapes chainees via operations transparentes → un seul Ctrl+Z
  |
  v
Selectionner le resultat
```

### 5.4 Utilisation de l'API native

Le plugin utilise les methodes suivantes de l'API Ruby SketchUp Pro :

| Methode | Receveur | Argument | Retour | Effet de bord |
|---------|----------|----------|--------|---------------|
| `union(other)` | Solide A | Solide B | Solide fusionne | Efface B |
| `outer_shell(other)` | Solide A | Solide B | Solide coque | Efface B |
| `subtract(base)` | Outil (efface) | Base (conservee) | Base modifiee | Efface l'outil |
| `manifold?` | Groupe/Composant | — | Booleen | Aucun |

**Important :** Pour `subtract`, le receveur est l'outil (qui est efface) et l'argument est la base (qui est modifiee et retournee). C'est l'inverse de ce que le nom de la methode pourrait suggerer.

## 6. Persistance des donnees

| Donnee | Stockage | Cle | Defaut |
|--------|----------|-----|--------|
| Couleur de soustraction (R) | Registre SketchUp | `SolidBatch/subtract_color_r` | 255 |
| Couleur de soustraction (G) | Registre SketchUp | `SolidBatch/subtract_color_g` | 0 |
| Couleur de soustraction (B) | Registre SketchUp | `SolidBatch/subtract_color_b` | 0 |
| Auto-repair circles on large objects | Registre SketchUp | `SolidBatch/auto_repair_large` | `Yes` |
| Seuil "gros objet" en edges | Registre SketchUp | `SolidBatch/large_threshold` | `10000` |

## 7. Interface utilisateur

### 7.1 Menu

Situe dans **Extensions > Solid Batch** :
1. Combine All (Union)
2. Combine All (Shell)
3. *(separateur)*
4. Set Subtract Color
5. Set Repair Options

### 7.2 Barre d'outils

Nommee "Solid Batch", contient 4 boutons avec des variantes d'icones 16px et 24px :
1. Combine All (Union)
2. Combine All (Shell)
3. Set Subtract Color
4. Set Repair Options

### 7.3 Messages

Tous les messages utilisateur utilisent `UI.messagebox` avec `MB_OK`. Les messages d'erreur incluent le numero d'etape ou l'echec s'est produit.

## 8. Gestion des erreurs

| Scenario | Comportement |
|----------|-------------|
| Moins de 2 solides selectionnes | Afficher le decompte, abandonner |
| SketchUp non Pro (methode manquante) | Afficher "necessite SketchUp Pro", abandonner |
| Tous les solides ont la couleur de soustraction | Afficher "aucun objet de base", abandonner |
| Etape booleenne echoue (resultat nil/invalide) | Abandonner l'operation (annuler tous les changements), afficher le numero d'etape |
| Exception inattendue | Abandonner l'operation, journaliser la backtrace (10 premieres lignes), afficher le message d'erreur |

## 9. Historique des versions

| Version | Date | Changements |
|---------|------|-------------|
| 1.0.0 | 2026-04-03 | Version initiale — moteur booleen custom (union, subtract, split) |
| 2.0.0 | 2026-04-04 | Suppression du moteur custom. Ajout Combine All (Union/Shell) utilisant les methodes natives Pro. Ajout Set Subtract Color. Suppression des operations individuelles Union, Subtract, Split. Operations transparentes pour commits rapides + undo unique. Affichage progression dans la barre de statut. |
| 2.1.0 | 2026-04-11 | Ajout Phase 3 : restauration automatique des cercles cassés sur le résultat (module `CircleRestore` adapté de Re-Cercle). Ajout commande `Set Repair Options` pour configurer le seuil et le toggle auto-repair. Persistance des nouvelles options. Nouvelle icône `repair_circles_*.png`. |
