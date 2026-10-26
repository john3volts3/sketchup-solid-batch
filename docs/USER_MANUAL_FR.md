# Solid Batch — Manuel utilisateur

## Presentation

Solid Batch est un plugin SketchUp qui effectue des operations booleennes par lot sur plusieurs solides en un seul clic. Sous SketchUp Pro, il utilise le moteur booléen natif ; sous SketchUp Make, qui n'en a pas, un moteur Ruby intégré.

Le plugin fournit quatre commandes accessibles via le menu **Extensions > Solid Batch** et la barre d'outils **Solid Batch**.

## Prerequis

- **SketchUp Pro** 2017 ou plus récent, ou **SketchUp Make** 2017 (SketchUp Make est concédé par Trimble pour un usage non commercial uniquement)
- Tous les objets doivent etre des groupes ou composants **solides** (geometrie manifold — chaque arete borde exactement 2 faces)

### Compatibilité par version

| Version SketchUp | Fonctionnalités disponibles |
|---|---|
| Pro 2017 ou plus récent | Toutes les fonctions : Combine All (Union, Shell), Set Subtract Color, Set Repair Options, restauration automatique des cercles et arcs (cercles natifs) |
| Pro 2020.1 ou plus récent | En plus, la soudure de secours : un cercle non reconstructible en natif est soudé en une courbe (avant 2020.1, il reste en segments) |
| Make 2017 | Toutes les fonctions, avec le moteur Ruby intégré : plus lent sur les pièces chargées, et Shell supprime un solide enfermé dans un autre (l'Outer Shell natif de Pro le garde) |

## Commandes

### Combine All (Union)

Fusionne tous les solides selectionnes en un seul, en utilisant `union` natif pour les solides de base et `subtract` natif pour les solides-outils marques par couleur.

**Comportement :**
1. Separe la selection en deux ensembles selon la couleur de soustraction :
   - **Solides de base** — tous les solides qui N'ONT PAS la couleur de soustraction
   - **Solides-outils** — tous les solides qui ONT la couleur de soustraction
2. **Phase 1 (Union) :** Fusionne tous les solides de base en un seul par appels sequentiels a `union`. S'il n'y a qu'un seul solide de base, cette phase est ignoree.
3. **Phase 2 (Subtract) :** Soustrait chaque solide-outil du solide fusionne, un par un.
4. **Phase 3 (Restauration des cercles ET arcs) :** Détecte les cercles ET les arcs cassés par les opérations booléennes natives et les reconstruit en **vrais cercles et arcs natifs** de SketchUp (inférence du centre, rayon et segments dans *Infos sur l'entité*). Quand la reconstruction native est impossible, ils sont soudés en une `Curve` sélectionnable en un clic (voir [Ce que produit la Phase 3](#ce-que-produit-la-phase-3)). Cette phase peut être désactivée pour les très gros objets via **Set Repair Options**.
5. L'operation entiere est encapsulee dans une seule etape d'annulation.

**Quand l'utiliser :** Quand vous voulez fusionner des solides en preservant les vides internes (ex. fusion de murs avec des ouvertures de fenetres).

### Combine All (Shell)

Meme principe que Combine All (Union), mais utilise `outer_shell` au lieu de `union` en Phase 1.

**Difference avec Union :**
- **Union** preserve la geometrie interne (vides, faces internes)
- **Outer Shell** supprime toute geometrie interne et ne garde que la surface exterieure

**Quand l'utiliser :** Quand vous voulez une enveloppe exterieure propre sans faces internes (ex. creation d'un solide simplifie pour le calcul de volume ou l'impression 3D).

### Set Subtract Color

Enregistre une couleur pour identifier les solides a soustraire lors des operations Combine All.

**Comment l'utiliser :**
1. Selectionnez un groupe ou composant auquel un materiau/couleur est applique
2. Cliquez sur **Set Subtract Color**
3. La couleur est sauvegardee et persiste entre les sessions SketchUp

**Couleur par defaut :** Rouge (RGB 255, 0, 0)

### Set Repair Options

Configure le comportement de la **Phase 3** (restauration automatique des cercles ET arcs) à la fin des opérations Combine All.

**Pourquoi c'est utile :** Les opérations booléennes natives de SketchUp Pro cassent les associations `ArcCurve` des cercles et des arcs : un cercle ou un arc d'origine devient une suite de petits segments individuels (ou une courbe simple sans inférence du centre). La Phase 3 les détecte et les reconstruit en cercles et arcs natifs. Sur les très gros objets (plusieurs dizaines de milliers d'edges), cela peut prendre plusieurs secondes ; l'option permet de la désactiver dans ce cas.

**Comment l'utiliser :**
1. Cliquez sur **Set Repair Options** (aucune sélection requise)
2. Une fenêtre s'ouvre avec trois champs :
   - **Auto-repair circles on large objects** (Yes/No) : si `Yes`, la restauration s'exécute toujours, même sur les gros objets ; si `No`, elle est ignorée au-dessus du seuil et un message vous prévient
   - **Large object threshold (edges)** : nombre d'edges à partir duquel un objet est considéré comme « gros »
   - **Min segments for arc detection** : nombre minimum de segments pour qu'une chaîne d'edges soit considérée comme un arc. Plus bas = détecte les arcs plus courts mais risque de faux positifs. Plus haut = plus sûr mais peut manquer les arcs courts.
3. Cliquez **OK** — les valeurs sont mémorisées pour les futures sessions

**Valeurs par défaut :** Auto-repair = `Yes`, Threshold = `10000` edges, Min arc segments = `6` (si vous aviez enregistré ces options avec une version précédente, votre valeur est conservée : vérifiez-la dans la fenêtre)

**Choisir le `Min segments for arc detection` :**

Un arc n'est reconnu que si ses segments ont la même longueur et tournent du même angle (60° au plus chacun). Un cercle demande toujours 6 segments ou plus. Le défaut de `6` est aligné sur les cercles ; quelques repères :

| Type d'arc | Segments | Détecté avec seuil = 6 ? |
|------------|----------|--------------------------|
| 360° avec 24 segments (cercle natif fin) | 24 | ✓ (cercle) |
| 270° avec 12 segments (arc natif par défaut) | 9 | ✓ |
| 180° avec 12 segments | 6 | ✓ |
| 90° avec 24 segments | 6 | ✓ |
| 90° avec 12 segments | 3 | ✗ — baisser le seuil à 3 |

Si vous travaillez avec beaucoup d'arcs courts, baissez le seuil (minimum `3`). Si des morceaux de polygones à côtés égaux sont transformés en arcs, remontez-le.

**Décision Phase 3 (résumé) :**

| Cas | Action |
|-----|--------|
| Résultat ≤ seuil | Restauration toujours exécutée |
| Résultat > seuil ET auto-repair = Yes | Restauration exécutée |
| Résultat > seuil ET auto-repair = No | Restauration ignorée + message modal |

### Ce que produit la Phase 3

| Cas dans le résultat | Résultat |
|----------------------|----------|
| Trou traversant, trou borgne, tenon (boîte ± cylindre), tronc de cône | Les deux cercles d'extrémité deviennent **natifs** (reconstruits par Pousser/Tirer) |
| Cercle ou arc posé sur une face plane | Cercle ou arc **natif** |
| Cercle traversé par une ligne | Arcs **natifs** entre les croisements |
| Arcs d'une arête arrondie (congé), cylindre coupé par une arête, trous qui se croisent ou empilés, cercle sur une surface courbe, cylindre oblique | **Soudés** en une courbe (sélection en un clic, sans inférence du centre) ; avant SketchUp 2020.1, laissés en segments |
| Cercles déjà natifs | Inchangés |

Un bilan s'affiche dans la barre de statut et, avec la raison de chaque soudure, dans la console Ruby (**Fenêtre > Console Ruby**).

**Limitations :** les faces reconstruites autour d'un cercle réparé (paroi du trou, extrémités, face hôte) gardent leur matériau, leur balise et leur orientation, mais perdent la position de leur texture et leurs attributs. Un polygone régulier de 6 côtés ou plus (hexagone…) ne peut pas être distingué d'un cercle et en devient un.

## Flux de travail

### Flux de base

1. **Modelez vos solides** — Creez tous les groupes/composants que vous voulez combiner. Assurez-vous qu'ils sont tous des solides valides (les Infos sur l'entite doivent afficher "Groupe solide" ou "Composant solide").

2. **Peignez les outils** — Appliquez une couleur specifique (ex. rouge) a tous les objets qui doivent etre soustraits du resultat final.

3. **Enregistrez la couleur de soustraction** — Selectionnez un des objets-outils peints et cliquez sur **Set Subtract Color**. Vous n'avez besoin de le faire qu'une seule fois (la couleur est memorisee).

4. **Selectionnez tout** — Selectionnez tous les solides a traiter (bases et outils).

5. **Lancez l'operation** — Cliquez sur **Combine All (Union)** ou **Combine All (Shell)**.

6. **Resultat** — Un seul solide reste. En cas de probleme, appuyez sur **Ctrl+Z** pour annuler l'operation entiere.

### Exemple : Mur avec fenetres

1. Creez un mur comme groupe solide
2. Creez les formes d'ouverture de fenetres comme groupes solides
3. Peignez les formes de fenetres en rouge
4. Definissez la couleur de soustraction sur rouge (si ce n'est pas deja fait)
5. Selectionnez le mur + toutes les formes de fenetres
6. Cliquez sur **Combine All (Union)**
7. Resultat : mur avec les ouvertures de fenetres decoupees

### Exemple : Fusion de plusieurs pieces

1. Creez chaque piece comme un groupe solide (murs, sol, plafond)
2. Aucun objet n'a besoin de la couleur de soustraction
3. Selectionnez tous les groupes de pieces
4. Cliquez sur **Combine All (Shell)** pour une enveloppe exterieure propre
5. Resultat : un seul solide representant l'enveloppe du batiment

## Icones de la barre d'outils

| Icone | Commande | Description |
|-------|----------|-------------|
| Combine Union | Combine All (Union) | Union native + soustraction + restauration cercles & arcs |
| Combine Shell | Combine All (Shell) | Outer shell native + soustraction + restauration cercles & arcs |
| Set Color | Set Subtract Color | Choix couleur depuis la selection |
| Cercle ✓ | Set Repair Options | Configurer auto-repair, seuil edges et min segments arc |

## Resolution de problemes

### « PRO Only vs. main.rb:... »
Cette copie du plugin a été réservée à SketchUp Pro : la ligne citée par le message, dans `solid_batch/main.rb`, a été décommentée. Rien n'est modifié dans le modèle. Pour utiliser Combine All sous SketchUp Make, remettez cette ligne en commentaire (un `#` au début) et redémarrez SketchUp.

### "Select at least 2 solid group(s) or component(s)"
Votre selection contient moins de 2 solides valides. Verifiez que :
- Vous avez selectionne au moins 2 objets
- Chaque objet est un Groupe ou un ComposantInstance
- Chaque objet est un solide valide (verifiez dans Infos sur l'entite — il doit afficher "Solide")

### "No base objects found"
Tous les objets selectionnes ont la couleur de soustraction. Au moins un objet doit avoir une couleur differente pour servir de base.

### « Combine All failed at step 3 of 5: Subtract 2 of 4, group "…" at (…) »
Une des opérations booléennes n'a pas pu donner un solide valide. **Rien n'a été modifié** : les étapes déjà faites sont annulées elles aussi, et le modèle est exactement comme avant Combine All. Le message nomme l'étape (son numéro, l'opération) et le solide de cette étape (son nom et sa position), et ce solide est **sélectionné**.

À vérifier sur le solide sélectionné :
- C'est un solide valide (Infos sur l'entité affiche « Groupe solide » ou « Composant solide »)
- Ses faces ne sont pas au ras des faces des autres solides (déplacez-le un peu, ou allongez-le pour qu'il traverse)
- La géométrie n'est pas trop fine ni trop complexe
- Relancez ensuite Combine All

### "Circle and arc restoration failed"
Un cercle n'a pas pu être reconstruit. Seule la restauration est annulée : le résultat du Combine All est conservé et ses cercles restent dans leur état. La console Ruby donne le détail.

### Progression
Pendant les operations par lot, la barre de statut en bas de la fenetre SketchUp affiche la progression en temps reel : `Solid Batch — Subtract 7/13 (54%)`. Un message final confirme la fin, avec le bilan de la restauration des cercles : `Solid Batch — Done (13 operations) — 4 circle(s)/arc(s) rebuilt as native circles`.

### Annulation
Toutes les operations Combine All sont encapsulees dans une seule etape d'annulation. Appuyez sur **Ctrl+Z** (Cmd+Z sur Mac) pour annuler l'operation entiere.

## Astuces

- **Verifiez les solides d'abord :** Utilisez le panneau Infos sur l'entite de SketchUp pour verifier que chaque objet est un solide valide avant de lancer les operations.
- **La couleur de soustraction est globale :** La couleur s'applique a tous les modeles. Definissez-la une fois, elle persiste.
- **Union vs Shell :** Si vous n'etes pas sur, commencez par Union. Ca preserve plus de geometrie, vous pourrez toujours simplifier ensuite.
- **L'ordre compte pour la soustraction :** Les solides-outils sont soustraits dans l'ordre de selection. Si les resultats sont inattendus, essayez de changer l'ordre de selection.
- **Sauvegardez votre modele :** Bien que Ctrl+Z fonctionne, sauvegardez avant les grosses operations par lot.
