# Solid Ops — Specification Fonctionnelle Detaillee

**Version :** 2.0.0
**Date :** 2026-04-04
**Auteur :** DRO

---

## 1. Objectif

Solid Ops est un plugin SketchUp Pro qui permet d'effectuer des operations booleennes par lot sur plusieurs solides en une seule action. Il cible les utilisateurs qui ont besoin de combiner et soustraire de nombreux objets solides efficacement (ex. modelisation architecturale, preparation pour impression 3D, assemblages mecaniques).

## 2. Perimetre

### Inclus
- Fusion par lot de plusieurs objets solides via l'API native SketchUp Pro
- Outer shell par lot de plusieurs objets solides via l'API native SketchUp Pro
- Soustraction par lot des objets solides marques par couleur depuis le resultat fusionne
- Identification persistante par couleur des objets a soustraire
- Etape d'annulation unique pour toute l'operation par lot

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

#### EF-01 : Combine All PRO (Union)

| Champ | Description |
|-------|-------------|
| **Entree** | Selection de 2+ groupes/composants solides |
| **Precondition** | Au moins un solide ne doit PAS avoir la couleur de soustraction |
| **Traitement** | 1. Separer la selection en solides de base et solides-outils par couleur de soustraction. 2. Fusionner sequentiellement tous les solides de base avec `Group#union`. 3. Soustraire sequentiellement tous les solides-outils avec `Group#subtract`. |
| **Sortie** | Un seul groupe/composant solide contenant le resultat |
| **Annulation** | L'operation entiere est annulee par un seul Ctrl+Z |
| **Gestion d'erreur** | Si une etape echoue, abandonner et annuler ; afficher un message d'erreur avec le numero d'etape |

#### EF-02 : Combine All PRO (Shell)

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
| **Persistance** | La couleur est stockee dans le registre SketchUp sous le namespace `DRO_SolidOps` ; survit au redemarrage de l'application |
| **Defaut** | Rouge (255, 0, 0) si aucune couleur n'a ete definie |

#### EF-04 : Validation des solides

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

## 5. Architecture

### 5.1 Structure des fichiers

```
dro_solid_ops.rb              # Point d'entree — enregistrement de l'extension
dro_solid_ops/
  version.rb                  # Constante VERSION
  main.rb                     # Menu, toolbar, commandes, logique metier
  icons/
    combine_pro_union_16.png  # Icones toolbar (16px et 24px)
    combine_pro_union_24.png
    combine_pro_shell_16.png
    combine_pro_shell_24.png
    setcolor_16.png
    setcolor_24.png
```

### 5.2 Structure du module

```
DRO_SolidOps                  # Namespace principal
  PLUGIN_DIR                  # Chemin du repertoire du plugin
  PLUGIN_NAME                 # "Solid Ops"
  VERSION                     # "2.0.0"

  # Gestion des couleurs
  subtract_color()            # Lire la couleur persistee
  save_subtract_color(color)  # Ecrire la couleur dans le registre
  color_match?(c1, c2)        # Comparer deux couleurs par RGB
  is_subtract_solid?(entity)  # Verifier si l'entite a la couleur de soustraction

  # Validation
  get_solids(min_count)        # Filtrer la selection aux solides valides

  # Commandes
  do_combine_all_pro(mode)    # Union/shell + soustraction par lot
  do_set_subtract_color()     # Enregistrer la couleur de soustraction
```

### 5.3 Flux d'operation

```
L'utilisateur clique "Combine All PRO (Union)" ou "(Shell)"
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
start_operation (etape d'annulation unique)
  |
  +---> Phase 1 : union/outer_shell sequentiel des solides de base
  |       base[0].union(base[1]) -> result.union(base[2]) -> ...
  |
  +---> Phase 2 : soustraction sequentielle des solides-outils
  |       tool[0].subtract(result) -> tool[1].subtract(result) -> ...
  |
  v
commit_operation
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
| Couleur de soustraction (R) | Registre SketchUp | `DRO_SolidOps/subtract_color_r` | 255 |
| Couleur de soustraction (G) | Registre SketchUp | `DRO_SolidOps/subtract_color_g` | 0 |
| Couleur de soustraction (B) | Registre SketchUp | `DRO_SolidOps/subtract_color_b` | 0 |

## 7. Interface utilisateur

### 7.1 Menu

Situe dans **Extensions > Solid Ops** :
1. Combine All PRO (Union)
2. Combine All PRO (Shell)
3. *(separateur)*
4. Set Subtract Color

### 7.2 Barre d'outils

Nommee "Solid Ops", contient 3 boutons avec des variantes d'icones 16px et 24px :
1. Combine All PRO (Union)
2. Combine All PRO (Shell)
3. Set Subtract Color

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
| 2.0.0 | 2026-04-04 | Suppression du moteur custom. Ajout Combine All PRO (Union/Shell) utilisant les methodes natives Pro. Ajout Set Subtract Color. Suppression des operations individuelles Union, Subtract, Split. |
