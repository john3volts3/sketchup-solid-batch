# Solid Batch — Manuel utilisateur

## Presentation

Solid Batch est un plugin SketchUp Pro qui effectue des operations booleennes par lot sur plusieurs solides en un seul clic. Il utilise le moteur booleen natif de SketchUp Pro pour des resultats fiables.

Le plugin fournit quatre commandes accessibles via le menu **Extensions > Solid Batch** et la barre d'outils **Solid Batch**.

## Prerequis

- **SketchUp Pro** 2017 ou plus recent
- Tous les objets doivent etre des groupes ou composants **solides** (geometrie manifold — chaque arete borde exactement 2 faces)

## Commandes

### Combine All (Union)

Fusionne tous les solides selectionnes en un seul, en utilisant `union` natif pour les solides de base et `subtract` natif pour les solides-outils marques par couleur.

**Comportement :**
1. Separe la selection en deux ensembles selon la couleur de soustraction :
   - **Solides de base** — tous les solides qui N'ONT PAS la couleur de soustraction
   - **Solides-outils** — tous les solides qui ONT la couleur de soustraction
2. **Phase 1 (Union) :** Fusionne tous les solides de base en un seul par appels sequentiels a `union`. S'il n'y a qu'un seul solide de base, cette phase est ignoree.
3. **Phase 2 (Subtract) :** Soustrait chaque solide-outil du solide fusionne, un par un.
4. **Phase 3 (Restauration des cercles ET arcs) :** Détecte les cercles ET les arcs cassés par les opérations booléennes natives et les reconstitue en `Sketchup::Curve` sélectionnables en un clic. Cette phase peut être désactivée pour les très gros objets via **Set Repair Options**.
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

**Pourquoi c'est utile :** Les opérations booléennes natives de SketchUp Pro cassent les associations `ArcCurve` des cercles et des arcs : un cercle ou un arc d'origine devient une suite de petits segments individuels qu'on doit cliquer un par un. La Phase 3 détecte ces segments et les regroupe en `Curve` sélectionnable en un clic. Sur les très gros objets (plusieurs dizaines de milliers d'edges), cette détection peut prendre plusieurs secondes ; l'option permet de la désactiver dans ce cas.

**Comment l'utiliser :**
1. Cliquez sur **Set Repair Options** (aucune sélection requise)
2. Une fenêtre s'ouvre avec trois champs :
   - **Auto-repair circles on large objects** (Yes/No) : si `Yes`, la restauration s'exécute toujours, même sur les gros objets ; si `No`, elle est ignorée au-dessus du seuil et un message vous prévient
   - **Large object threshold (edges)** : nombre d'edges à partir duquel un objet est considéré comme « gros »
   - **Min segments for arc detection** : nombre minimum de segments pour qu'une chaîne d'edges soit considérée comme un arc. Plus bas = détecte les arcs plus courts mais risque de faux positifs. Plus haut = plus sûr mais peut manquer les arcs courts.
3. Cliquez **OK** — les valeurs sont mémorisées pour les futures sessions

**Valeurs par défaut :** Auto-repair = `Yes`, Threshold = `10000` edges, Min arc segments = `8`

**Choisir le `Min segments for arc detection` :**

Le seuil par défaut de `8` est conservateur — il évite les faux positifs (3-4 edges en angle qui formeraient « par hasard » un quart de cercle) mais peut manquer les arcs courts. Quelques repères :

| Type d'arc | Segments | Détecté avec seuil = 8 ? |
|------------|----------|--------------------------|
| 360° avec 24 segments (cercle natif fin) | 24 | ✓ |
| 270° avec 12 segments (arc natif par défaut) | 9 | ✓ |
| 180° avec 12 segments | 6 | ✗ — baisser le seuil à 6 ou moins |
| 90° avec 12 segments | 3 | ✗ — risque de faux positif si seuil ≤ 3 |
| 90° avec 24 segments | 6 | ✗ — baisser le seuil à 6 ou moins |

Si vous travaillez avec beaucoup d'arcs courts (≤ 6 segments), baissez le seuil à `4` ou `5`. Si vous voyez des faux positifs (des coudes droits transformés en arcs), remontez à `8` ou plus.

**Décision Phase 3 (résumé) :**

| Cas | Action |
|-----|--------|
| Résultat ≤ seuil | Restauration toujours exécutée |
| Résultat > seuil ET auto-repair = Yes | Restauration exécutée |
| Résultat > seuil ET auto-repair = No | Restauration ignorée + message modal |

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

### "This function requires SketchUp Pro"
Vous utilisez SketchUp Make ou SketchUp Free. Les methodes booleennes natives ne sont disponibles que dans SketchUp Pro.

### "Select at least 2 solid group(s) or component(s)"
Votre selection contient moins de 2 solides valides. Verifiez que :
- Vous avez selectionne au moins 2 objets
- Chaque objet est un Groupe ou un ComposantInstance
- Chaque objet est un solide valide (verifiez dans Infos sur l'entite — il doit afficher "Solide")

### "No base objects found"
Tous les objets selectionnes ont la couleur de soustraction. Au moins un objet doit avoir une couleur differente pour servir de base.

### L'operation echoue a une etape specifique
Une des operations booleennes a echoue. Causes habituelles :
- Deux solides ne s'intersectent pas (rien a fusionner/soustraire)
- La geometrie est trop complexe ou a des faces coplanaires
- Essayez de reordonner ou simplifier les solides problematiques

### Progression
Pendant les operations par lot, la barre de statut en bas de la fenetre SketchUp affiche la progression en temps reel : `Solid Batch — Subtract 7/13 (54%)`. Un message final confirme la fin : `Solid Batch — Done (13 operations)`.

### Annulation
Toutes les operations Combine All sont encapsulees dans une seule etape d'annulation. Appuyez sur **Ctrl+Z** (Cmd+Z sur Mac) pour annuler l'operation entiere.

## Astuces

- **Verifiez les solides d'abord :** Utilisez le panneau Infos sur l'entite de SketchUp pour verifier que chaque objet est un solide valide avant de lancer les operations.
- **La couleur de soustraction est globale :** La couleur s'applique a tous les modeles. Definissez-la une fois, elle persiste.
- **Union vs Shell :** Si vous n'etes pas sur, commencez par Union. Ca preserve plus de geometrie, vous pourrez toujours simplifier ensuite.
- **L'ordre compte pour la soustraction :** Les solides-outils sont soustraits dans l'ordre de selection. Si les resultats sont inattendus, essayez de changer l'ordre de selection.
- **Sauvegardez votre modele :** Bien que Ctrl+Z fonctionne, sauvegardez avant les grosses operations par lot.
