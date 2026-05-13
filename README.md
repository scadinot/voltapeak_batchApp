# voltapeak_batchApp — analyse SWV batch multi-électrodes (macOS / Swift)

**Application macOS native (Swift / SwiftUI) d'analyse par lot de fichiers
de voltampérométrie à onde carrée (SWV) avec correction de ligne de base
asPLS et agrégation multi-électrodes.**

`voltapeak_batchApp` est la conversion Swift macOS de
[`scadinot/voltapeak_batch`](https://github.com/scadinot/voltapeak_batch)
(Python / Tkinter). Les algorithmes d'analyse (Savitzky-Golay scipy-exact,
asPLS Zhang 2020) sont repris sans modification de
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp), validé
bit-exact à la 6ᵉ décimale contre la référence Python.

## Famille de projets

| Repo | Rôle |
|---|---|
| [`voltapeakApp`](https://github.com/scadinot/voltapeakApp) | **App GUI mono-fichier**, référence canonique des algorithmes |
| [`voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp) | App batch multi-fichiers avec **agrégation multi-électrodes** *(ce repo)* |
| [`voltapeak_loopsApp`](https://github.com/scadinot/voltapeak_loopsApp) | App batch multi-fichiers avec **agrégation loops/dosage hiérarchique** |

## Table des matières

1. [À quoi sert cet outil ?](#à-quoi-sert-cet-outil-)
2. [Prérequis](#prérequis)
3. [Build et lancement](#build-et-lancement)
4. [Utilisation](#utilisation)
5. [Format des fichiers d'entrée](#format-des-fichiers-dentrée)
6. [Fichiers produits en sortie](#fichiers-produits-en-sortie)
7. [Paramètres de l'algorithme](#paramètres-de-lalgorithme)
8. [Parallélisme](#parallélisme)
9. [Documentation complémentaire](#documentation-complémentaire)
10. [Crédits & licence](#crédits--licence)

## À quoi sert cet outil ?

Lors d'expériences de voltampérométrie à onde carrée, on mesure un courant
en fonction du potentiel. Le signal utile — un pic centré sur le potentiel
caractéristique de l'espèce électroactive — est superposé à une **ligne de
base** lentement variable. L'analyse quantitative nécessite donc de
soustraire cette ligne de base pour ne garder que le pic.

L'application automatise ce traitement pour des **campagnes
multi-électrodes multi-échantillons** : chaque fichier porte un nom de la
forme `<base>_C<NN>.txt` (ex. `ESSAI1_C01.txt`, `ESSAI1_C02.txt`, …).
L'outil produit :

- un graphique PNG d'analyse par fichier (300 dpi) ;
- éventuellement un CSV ou un XLSX par fichier (signal lissé + corrigé) ;
- un **fichier Excel récapitulatif** regroupant une ligne par base et des
  colonnes par électrode (Tension, Courant, Charge), avec une formule
  Excel `=Courant / Fréquence` injectée pour la charge.

## Prérequis

- **macOS 26.1** ou supérieur (déploiement minimum)
- **Xcode 26** ou supérieur (`objectVersion = 77` du `project.pbxproj`)
- Aucune dépendance externe — tous les algorithmes scientifiques sont
  implémentés en pur Swift (cf. [ARCHITECTURE.md](ARCHITECTURE.md)).

## Build et lancement

### Depuis Xcode

```bash
git clone https://github.com/scadinot/voltapeak_batchApp.git
cd voltapeak_batchApp
open voltapeak_batch.xcodeproj
# ⌘R pour lancer
```

### Depuis la ligne de commande

```bash
xcodebuild -project voltapeak_batch.xcodeproj \
           -scheme voltapeak_batch \
           -configuration Release \
           build
```

Le binaire produit se trouve dans
`build/Release/voltapeak_batch.app` (ou dans
`~/Library/Developer/Xcode/DerivedData/...` selon votre configuration).

## Utilisation

L'interface reproduit fidèlement la fenêtre Tkinter de la version Python :

1. **Dossier d'entrée** — cliquer sur *Parcourir* et sélectionner le dossier
   contenant les fichiers `.txt`.
2. **Paramètres de lecture** :
   - séparateur de colonnes (*Tabulation*, *Virgule*, *Point-virgule*, *Espace*),
   - séparateur décimal (*Point* ou *Virgule*),
   - export par fichier (*Ne pas exporter*, *CSV*, *Excel*),
   - traitement parallèle (activé par défaut).
3. **Lancer l'analyse** — le journal affiche chaque fichier traité (en
   rouge en cas d'erreur), la barre de progression avance au fur et à
   mesure.
4. **Ouvrir le dossier de résultats** — disponible une fois le traitement
   terminé, ouvre le dossier `<entrée> (results)` dans le Finder.

## Format des fichiers d'entrée

Chaque fichier `.txt` doit contenir :

- une **première ligne d'entête** (ignorée), généralement produite par le
  potentiostat ;
- **deux colonnes** : *Potentiel* (V) et *Courant* (A) ;
- séparateur configurable dans l'UI ;
- décimale configurable dans l'UI ;
- encodage **ISO Latin-1** (Western, par défaut sur les exports Windows).

### Convention de nommage

Pour permettre l'agrégation multi-électrodes, le nom de fichier doit
suivre :

```
<base>_C<NN>.txt
```

Exemples valides : `ESSAI1_C01.txt`, `MANIP_2025-04_C12.txt`.

Si un fichier ne respecte pas ce pattern, il est traité individuellement
mais apparaît dans le récapitulatif avec son nom complet comme *Base* et
des colonnes d'électrode vides.

## Fichiers produits en sortie

À chaque exécution, un dossier frère du dossier d'entrée est créé :

```
<dossier_entrée>          ← vos fichiers .txt
<dossier_entrée> (results) ← sortie générée
```

Le dossier est **nettoyé** au début de chaque exécution : les `.png`,
`.csv` et `.xlsx` préexistants y sont supprimés.

### Par fichier traité

| Fichier | Toujours produit ? | Contenu |
|---|:---:|---|
| `<nom>.png` | oui | Graphique haute résolution (5 courbes + pic) |
| `<nom>.csv` | si option *CSV* | Colonnes `Potential`, `Current`, `SignalLisse`, `SignalCorrigé` |
| `<nom>.xlsx` | si option *Excel* | Idem CSV avec colonne `Baseline` en plus |

### Récapitulatif agrégé

Un unique `<nom_du_dossier>.xlsx` est écrit à la racine du dossier de
résultats. Il regroupe **une ligne par base**, avec ces colonnes pour
chaque électrode détectée :

| Colonne | Source |
|---|---|
| `Base` | base extraite du nom de fichier |
| `Fréq (Hz)` | **50,0** par défaut |
| `C<NN> - Tension (V)` | potentiel du pic après correction |
| `C<NN> - Courant (A)` | amplitude du pic après correction |
| `C<NN> - Charge (C)` | **formule Excel** `=Courant / Fréq` — recalculée dynamiquement |

## Paramètres de l'algorithme

Identiques à la version Python et aux autres apps de la famille — détails
mathématiques dans [ALGORITHMS.md](ALGORITHMS.md) :

| Paramètre | Valeur | Rôle |
|---|---|---|
| `windowLength` (Savitzky-Golay) | **11** | largeur de la fenêtre de lissage |
| `polynomialOrder` (Savitzky-Golay) | **2** | ordre du polynôme local |
| `marginRatio` | **0,10** | fraction des bords exclue pour la détection de pic |
| `maxSlope` | **500** (`nil` pour désactiver) | plafond de pente `|dI/dV|` |
| `exclusionWidthRatio` | **0,03** | demi-largeur d'exclusion asPLS (fraction de l'étendue) |
| `lambdaFactor` | **1 000** | rigidité de la baseline : λ effectif = `lambdaFactor · n²` |
| `diffOrder` (asPLS) | **2** | ordre de la différence pénalisée |
| `tol` (asPLS) | **1e-2** | tolérance de convergence (sur les poids) |
| `maxIter` (asPLS) | **25** | nombre maximal d'itérations |
| `asymmetricCoef` (asPLS) | **0,5** | coefficient `k` du papier asPLS |
| `frequencyHz` (récapitulatif) | **50 Hz** | dénominateur de `Charge = Courant / Fréq` |

## Parallélisme

Le traitement par défaut est parallélisé via Swift Concurrency
(`TaskGroup`) avec une concurrence égale au nombre de cœurs logiques
(`ProcessInfo.processInfo.activeProcessorCount`).

Un mode séquentiel est disponible (commutateur dans l'UI) pour le débogage
ou la reproductibilité stricte de l'ordre d'écriture.

## Documentation complémentaire

| Document | Contenu |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Structure du projet, pipeline, fichiers Swift, modèles de données, concurrence |
| [ALGORITHMS.md](ALGORITHMS.md) | Algorithmes numériques (Savitzky-Golay, détection de pic, asPLS Zhang 2020) |
| [VALIDATION.md](VALIDATION.md) | Méthodologie de validation, parité avec la référence Python |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Guide développeur : build, debug, conventions, ajout de features |
| [DISTRIBUTION.md](DISTRIBUTION.md) | Signature, notarisation Apple, création de DMG, CI |
| [CHANGELOG.md](CHANGELOG.md) | Historique des versions (Keep-a-Changelog) |

## Crédits & licence

Algorithmes — portages directs des bibliothèques Python de référence :

- **scipy** (`scipy.signal.savgol_filter`) — lissage Savitzky-Golay
- **pybaselines** (`pybaselines.whittaker.aspls`) — baseline asPLS Zhang 2020
- **numpy** (`np.gradient`) — gradient 2ᵉ ordre non-uniforme
- **matplotlib** — palette **tab10** pour parité visuelle

Sources d'inspiration :

- [`scadinot/voltapeak_batch`](https://github.com/scadinot/voltapeak_batch) — script Python source (Tkinter)
- [`scadinot/voltapeakApp`](https://github.com/scadinot/voltapeakApp) — référence canonique des fonctions d'analyse, validée bit-exact

Références bibliographiques détaillées dans [ALGORITHMS.md](ALGORITHMS.md).

Distribué sous **licence MIT** — Copyright (c) 2026 @scadinot.
