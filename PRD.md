# Solid Batch — Document des exigences produit (PRD)

Version du document : 2026-10-26 (livraison 2.5.0). Le *quoi* et le *pourquoi* ; le *comment* est dans `docs/FSD_FR.md` / `docs/FSD_EN.md`.

## 1. Contexte et problème

Pour concevoir des pièces techniques (impression 3D, assemblages) dans SketchUp, on construit souvent une forme à partir de volumes simples (boîtes, cylindres, extrusions) que l'on combine par opérations booléennes. Faire les unions et soustractions une par une sur des dizaines d'objets est long et source d'erreurs. De plus, les booléens natifs de SketchUp cassent les cercles et les arcs (segments sans inférence du centre), ce qui gêne la suite de la modélisation.

## 2. Utilisateurs et usages

- Concepteurs de pièces pour l'impression 3D, makers : plaque percée de nombreux trous, tétons, chambrages ; sous SketchUp Pro ou SketchUp Make 2017 (gratuit, usage non commercial).
- Architectes et designers : murs et ouvertures, assemblages, moules.
- Usage type : peindre les volumes à soustraire d'une couleur, tout sélectionner, un clic sur Combine All, un seul Ctrl+Z pour revenir en arrière.

## 3. Objectifs et critères de succès

- Un clic pour combiner toute une sélection (union ou enveloppe, puis soustractions).
- Un seul Ctrl+Z pour annuler toute l'opération.
- Des cercles et arcs natifs sur le résultat (inférence du centre, rayon et segments dans *Infos sur l'entité*).
- Temps acceptable sur une plaque à nombreux trous (plaque à 20 trous : reconstruction des cercles en environ 2 s sous SketchUp 2021).
- Aucune régression : batterie de tests automatique sans échec sous SketchUp 2021 et Make 2017 avant chaque livraison.

## 4. Périmètre

### Inclus
- Combine All (Union) et Combine All (Shell), soustraction des solides de la couleur de soustraction.
- Set Subtract Color, Set Repair Options.
- Reconstruction des cercles et arcs cassés en cercles natifs (méthode de Re-Cercle), soudure de secours.
- SketchUp Pro 2017 et plus récent (booléens natifs) et SketchUp Make 2017 (moteur booléen Ruby intégré) ; une seule ligne de code réserve Combine All à Pro.

### Exclu
- Opérations individuelles union / subtract / split (natives dans SketchUp Pro).
- SketchUp Free (version web) : n'exécute pas d'extensions.
- Diffusion par l'Extension Warehouse (voir § 9).
- Sous SketchUp Pro, tout moteur booléen autre que les booléens natifs.

## 5. Exigences fonctionnelles

| ID | Exigence | Priorité | Statut |
|----|----------|----------|--------|
| EF-01 | Combine All (Union) : union des solides de base, puis soustraction des solides de la couleur de soustraction, une seule étape d'annulation | indispensable | livrée en v2.0.0 |
| EF-02 | Combine All (Shell) : comme EF-01 avec Outer Shell en phase 1 | indispensable | livrée en v2.0.0 |
| EF-03 | Set Subtract Color : couleur de soustraction prise sur la sélection, mémorisée entre les sessions | indispensable | livrée en v2.0.0 |
| EF-04 | Set Repair Options : réparation des gros objets (Yes / No), seuil « gros objet », nombre minimum de segments d'un arc ; dans toutes les versions de SketchUp | important | livrée en v2.1.0 ; toutes les versions en v2.4.0 |
| EF-05 | Restauration des cercles et arcs sur le résultat : cercles natifs (plans, cylindres, troncs de cône), soudure de secours ; aussi avant SketchUp 2020.1 | indispensable | livrée en v2.1.0 (cercles), v2.2.0 (arcs), v2.3.0 (natifs) ; avant 2020.1 en v2.4.0 |
| EF-06 | Validation des solides de la sélection (au moins 2 solides) | indispensable | livrée en v2.0.0 |
| EF-07 | Sans SketchUp Pro (Make) : Combine All par le moteur Ruby, même résultat que sous Pro ; une seule ligne, commentée par défaut, réserve Combine All à Pro (message « PRO Only vs. main.rb:<ligne> », rien de modifié) ; un seul contrôle de l'édition dans tout le plugin | important | livrée en v2.4.0 (message), v2.5.0 (moteur Ruby par défaut) |

## 6. Exigences non fonctionnelles

| ID | Exigence | Statut |
|----|----------|--------|
| NF-01 | Fiabilité avant vitesse : une optimisation n'est acceptée que si elle donne le même résultat, vérifié sur la même géométrie | livrée en v2.4.0 (`repair_holes`) |
| NF-02 | Performance : `repair_holes` par grilles (plaque à 20 trous 9,6 → 2,2 s sous 2021) | livrée en v2.4.0 |
| NF-03 | Une seule étape d'annulation pour tout Combine All ; un échec de la restauration des cercles n'annule que la restauration | livrée en v2.0.0 / v2.3.0 |
| NF-04 | Progression dans la barre de statut, bilan de la restauration (barre de statut, console Ruby) | livrée en v2.0.0 / v2.3.0 |
| NF-05 | Compatibilité SketchUp 2017 et Ruby 2.2 (aucune syntaxe ni méthode Ruby 2.3+, garde `respond_to?` pour les API récentes) | livrée en v2.2.1, étendue en v2.4.0 |
| NF-06 | Plugin autonome : code repris d'autres plugins copié dans `solid_batch/` (Re-Cercle, Solid for Maker), aucune dépendance | livrée en v2.3.0 / v2.4.0 |
| NF-07 | Batterie de tests automatique (`tools/tests`), SketchUp 2021 et Make 2017, aucune écriture dans les réglages du PC | livrée en v2.4.0 |
| NF-08 | Libellés à l'écran en anglais ; nom affiché « Solid Batch » identique partout (extension, menu, barre d'outils, registre `SolidBatch`, console) | livrée en v2.0.0 |
| NF-09 | Dépôt public : aucun chemin local, nom d'utilisateur ou adresse dans les fichiers suivis | livrée en v2.3.0 |
| NF-10 | Échec d'une étape de Combine All : le modèle revient exactement comme avant (étapes déjà faites annulées, action précédente de l'utilisateur gardée) ; le message nomme l'étape (numéro, opération), le solide (nom, position) et la raison ; ce solide est sélectionné | livrée en v2.4.1 |
| NF-11 | Licence du moteur : notice MIT d'Eneroth reproduite exactement (« Copyright (c) 2017 Julia Christina Eneroth ») dans `solid_operations.rb`, `LICENSE-solid-operations.txt` (livré dans le `.rbz`) ; crédit dans le README ; « not an official Eneroth extension » | livrée en v2.5.0 |

## 7. Contraintes et dépendances

- Booléens natifs : SketchUp Pro uniquement (`Group#union`, `#outer_shell`, `#subtract`). Ordre natif : `outil.subtract(base)` (l'outil est effacé, la base modifiée et renvoyée).
- `Entities#weld` (soudure de secours) : SketchUp 2020.1 et plus récent.
- Code repris, copié dans le plugin : moteur des cercles de Re-Cercle v2.0.0 ; moteur booléen Ruby `solid_operations.rb` de Solid for Maker 1.0.1, porté d'Eneroth Solid Tools 3.0.0 (licence MIT, `solid_batch/LICENSE-solid-operations.txt`).
- Licence MIT d'Eneroth Solid Tools : garder sa notice et le texte de la licence dans toute copie ; aucune autorisation nécessaire ; ne pas laisser croire à un soutien d'Eneroth ni de Trimble.
- Versions de test : SketchUp 2021 Pro (21.0.391) et SketchUp Make 2017 (17.2.2555, Ruby 2.2.4).

## 8. Critères d'acceptation

| Exigences | Critère |
|-----------|---------|
| EF-01, EF-02, NF-03 | T02, T03, T05 : trois boîtes → un solide de volume 2 000 ; une seule annulation rend les 4 solides d'origine |
| EF-01, EF-05 | T04 : plaque à 2 trous → volume exact, outils effacés, 96 arêtes en cercles natifs |
| EF-04 | T08, T09 : seuil et Yes / No respectés ; valeurs invalides ramenées aux défauts |
| EF-05 | T07 : cylindre aux cercles éclatés → 2 cercles natifs, dans toutes les versions |
| EF-06 | T06 : messages « Select at least 2 » et « No base objects found » |
| EF-07 | T02 à T05, T08, T12, T13 avec le moteur Ruby (Make 2017, et Make simulé sous Pro) : mêmes résultats que les booléens natifs ; T15 : base composant partagée ; T10 : un seul `is_pro?`, ligne Pro seulement commentée par défaut, décommentée → « PRO Only vs. main.rb:<ligne> », rien de modifié |
| NF-01, NF-02 | T11, T12 : grilles = parcours complet ; 13 cas identiques ancienne / nouvelle méthode ; plaque à 20 trous au moins 2 fois plus rapide |
| NF-05, NF-07 | Batterie sans échec sous SketchUp 2021 et Make 2017 |
| NF-10 | T13 : échec forcé à la première étape, au milieu, à la dernière, et erreur Ruby → mêmes solides et volumes qu'avant, action précédente gardée, message de l'étape, solide sélectionné ; T14 : annuler une opération enchaînée annule toute la chaîne, et seulement elle |

## 9. Questions ouvertes et décisions

- **Décision (2026-10-26)** : le moteur booléen Ruby de Solid for Maker 1.0.1 est copié dans le plugin (`solid_operations.rb`, MIT) ; sous SketchUp Pro, les booléens natifs restent seuls utilisés. Cette décision remplace celle du 2026-04-12 (code sans Eneroth Solid Tools).
- **Décision (2026-10-26)** : version 2.4.0, outils de test dans le dépôt public, release GitHub avec le `.rbz`.
- **Décision (2026-10-26, 2.4.1)** : en cas d'échec d'une étape, le modèle revient comme avant et un message clair nomme l'étape et le solide, qui est sélectionné. Vérifié par la batterie : SketchUp annule déjà toute la chaîne d'étapes quand l'étape qui échoue est annulée (T14) ; le constat inverse, écrit à la livraison 2.4.0, était faux.
- **Décision (2026-10-26, 2.5.0)** : pas de diffusion par l'Extension Warehouse. Sa règle (citée par Eneroth dans `menu.rb` d'Eneroth Solid Tools) n'accepte une extension qui reproduit une fonction de Pro que si elle est réservée à Pro. Hors de ce magasin (GitHub, SketchUcation), rien n'empêche de proposer le moteur aux utilisateurs de Make ; la licence MIT le permet. Make est donc débloqué par défaut dans Solid Batch, Solid Procedural et Solid for Maker, avec une seule ligne pour le bloquer.

## 10. Historique des livraisons

| Date | Version | Commit | Exigences livrées |
|------|---------|--------|-------------------|
| 2026-04-03 | 1.0.0 | `2977680` | Union, Subtract, Split (moteur booléen Ruby, retiré en 2.0.0) |
| 2026-04-04 | 2.0.0 | `cb465f9` | EF-01, EF-02, EF-03, EF-06, NF-03, NF-04, NF-08 |
| 2026-04-11 | 2.1.0 | `4db6de6` | EF-04, EF-05 (cercles) |
| 2026-04-11 | 2.2.0 | `0bfc19f` | EF-05 (arcs) |
| 2026-04-12 | 2.2.1 | `bb9d8c7` | NF-05 (SketchUp Pro 2017, Ruby 2.2) |
| 2026-10-11 | 2.3.0 | `13748c4` | EF-05 (cercles natifs, méthode de Re-Cercle), NF-06, NF-09 |
| 2026-10-26 | 2.4.0 | `5f57c96` | EF-04 et EF-05 dans toutes les versions, EF-07, NF-01, NF-02, NF-05 (étendue), NF-06 (moteur Ruby), NF-07 |
| 2026-10-26 | 2.4.1 | `d65a0d3` | NF-10 |
| 2026-10-26 | 2.5.0 | voir l'étiquette `v2.5.0` | EF-07 (moteur Ruby par défaut sous Make), NF-11 |
