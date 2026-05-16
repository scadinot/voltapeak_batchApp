# voltapeak_batchApp

> Analyse par lot de voltampérogrammes SWV — agrégation multi-électrodes. Application macOS native (SwiftUI).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift 5.0](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![macOS 26.1+](https://img.shields.io/badge/macOS-26.1+-blue.svg)](https://www.apple.com/macos/)
[![CI](https://github.com/scadinot/voltapeak_batchApp/actions/workflows/build-artifact.yml/badge.svg)](https://github.com/scadinot/voltapeak_batchApp/actions/workflows/build-artifact.yml)
[![Release](https://github.com/scadinot/voltapeak_batchApp/actions/workflows/release.yml/badge.svg)](https://github.com/scadinot/voltapeak_batchApp/actions/workflows/release.yml)

---

## Table des matières

1. [À quoi sert cet outil ?](#à-quoi-sert-cet-outil)
2. [Écosystème voltapeak](#écosystème-voltapeak)
3. [Fonctionnalités](#fonctionnalités)
4. [Prérequis](#prérequis)
5. [Installation](#installation)
6. [Build & lancement](#build--lancement)
7. [Format des fichiers d'entrée](#format-des-fichiers-dentrée)
8. [Utilisation — interface graphique](#utilisation--interface-graphique)
9. [Résultats produits](#résultats-produits)
10. [Chaîne de traitement par fichier](#chaîne-de-traitement-par-fichier)
11. [Paramètres algorithmiques](#paramètres-algorithmiques)
12. [Architecture du code](#architecture-du-code)
13. [Performance & concurrence](#performance--concurrence)
14. [Tests](#tests)
15. [CI/CD](#cicd)
16. [Algorithmes & références](#algorithmes--références)
17. [Dépannage](#dépannage)
18. [Feuille de route](#feuille-de-route)
19. [Licence et auteur](#licence-et-auteur)

---

## À quoi sert cet outil ?

La **voltammétrie à vagues carrées** (Square Wave Voltammetry, SWV) est une technique électrochimique qui mesure le courant traversant une électrode en fonction d'un potentiel imposé. Le signal obtenu présente un **pic** caractéristique de l'espèce analysée, superposé à une **ligne de base** (*baseline*) qui dérive lentement avec le potentiel.

Pour exploiter le pic, il faut :

1. **lisser** le signal pour atténuer le bruit de mesure ;
2. **estimer puis soustraire** la ligne de base ;
3. **relever** les coordonnées (tension, courant) du pic corrigé.

`voltapeak_batchApp` automatise ces trois étapes en s'appuyant sur :

- **Savitzky-Golay** pour le lissage (convolution polynomiale locale) ;
- **asPLS Whittaker** (*asymmetric Penalized Least Squares*, port Swift de [`pybaselines.whittaker.aspls`](https://pybaselines.readthedocs.io/)) pour l'estimation robuste de la baseline, avec une pondération réduite autour du pic afin d'éviter que la baseline ne « suive » et n'efface le pic.

> **Convention de signe.** Le pipeline est calibré pour des **SWV cathodiques** : le signe du courant est systématiquement inversé avant la détection de pic, donc le pic doit apparaître **en courant négatif** dans le fichier d'entrée. Un fichier où le pic est déjà en courant positif (orientation anodique) sera mal traité — il faut alors inverser la colonne en amont.

`voltapeak_batchApp` cible les **campagnes multi-électrodes multi-échantillons** : chaque fichier porte un nom de la forme `<base>_C<NN>.txt` (`ESSAI1_C01.txt`, `ESSAI1_C02.txt`, …). L'outil traite tous les fichiers du dossier en **parallèle** (`TaskGroup` borné au nombre de cœurs) et produit un **classeur Excel récapitulatif** regroupant une ligne par base et trois colonnes par électrode (Tension, Courant, Charge calculée par formule Excel). Pour de l'exploration interactive d'un seul fichier, voir [`voltapeakApp`](https://github.com/scadinot/voltapeakApp) ; pour les plans d'expérience structurés en boucles ou en dosages, voir [`voltapeak_loopsApp`](https://github.com/scadinot/voltapeak_loopsApp).

---

## Écosystème voltapeak

Cette application fait partie d'une suite de 3 outils macOS dédiés à l'analyse de signaux de voltampérométrie à ondes carrées (SWV) :

- **[voltapeakApp](https://github.com/scadinot/voltapeakApp)** — analyseur interactif fichier-par-fichier (source de vérité des algorithmes).
- **[voltapeak_batchApp](https://github.com/scadinot/voltapeak_batchApp)** — traitement par lot multi-électrodes, agrégation Excel par canal (`*_C<NN>.txt`).
- **[voltapeak_loopsApp](https://github.com/scadinot/voltapeak_loopsApp)** — traitement par lot pour expériences en boucles ou dosages (`*_loopZZ.txt`, `ZZ_<concentration>_*`).

Les 3 applications partagent le même pipeline scientifique et les mêmes implémentations Swift natives.

Elles sont des **portages natifs** de leurs équivalents Python ([`scadinot/voltapeak`](https://github.com/scadinot/voltapeak), [`scadinot/voltapeak_batch`](https://github.com/scadinot/voltapeak_batch), [`scadinot/voltapeak_loops`](https://github.com/scadinot/voltapeak_loops)) — avec parité numérique stricte : coefficients Savitzky-Golay identiques à `scipy.signal.savgol_coeffs(11, 2)` et solveur asPLS aligné sur `pybaselines.whittaker.aspls`.

---

## Fonctionnalités

- Traitement de **tous les `.txt` d'un dossier**, sélectionné via la GUI.
- **Parallélisation Swift Concurrency** (`TaskGroup` borné à `ProcessInfo.activeProcessorCount`), basculable en mode séquentiel pour le débogage.
- **Séparateur de colonnes** (tabulation, virgule, point-virgule, espace) et **séparateur décimal** (point ou virgule) configurables dans l'interface.
- **Lissage** Savitzky-Golay (fenêtre 11, ordre 2) avec coefficients pré-calculés depuis `scipy.signal.savgol_coeffs` — parité numérique stricte.
- **Détection de pic robuste** : exclusion des 10 % de bords du scan et filtre de pente `maxSlope = 500`.
- **Estimation de ligne de base asPLS** avec zone d'exclusion ±3 % centrée sur le pic, résolution via solveur LAPACK banded `dgbsv_` (Accelerate, O(n)).
- **Agrégation multi-électrodes** : nom `<base>_C<NN>.txt` parsé par regex (case-insensitive) pour pivoter en colonnes par canal.
- **Classeur Excel récapitulatif** avec **formule** `=Courant / Fréquence` recalculée à l'ouverture (50 Hz par défaut).
- **Exports optionnels par fichier** : graphique PNG (`ImageRenderer`, scale 3, ~3000×1800), CSV ou XLSX nettoyé.
- **Journal de traitement** auto-scrollable et **barre de progression** en temps réel.
- Bouton **« Ouvrir le dossier de résultats »** à la fin du traitement (`NSWorkspace.open`).
- **Zéro dépendance externe** : 100 % Swift + frameworks Apple (`SwiftUI`, `Charts`, `Accelerate`, `AppKit`, `Foundation`, `Observation`), y compris le générateur XLSX (mini-ZIP store-only + CRC32 PKZIP maison).

---

## Prérequis

- **macOS 26.1** ou supérieur (Tahoe — cible définie par `MACOSX_DEPLOYMENT_TARGET = 26.1`).
- **Xcode 26** ou supérieur (`objectVersion = 77`, requis pour le SDK macOS 26).
- **Swift 5.0**.

Aucune dépendance externe : tout repose sur les frameworks Apple (`SwiftUI`, `AppKit`, `Charts`, `Accelerate`, `Foundation`, `Observation`).

---

## Installation

```bash
git clone https://github.com/scadinot/voltapeak_batchApp.git
cd voltapeak_batchApp
open voltapeak_batch.xcodeproj
```

Aucune installation de dépendance, aucun `pod install`, aucun `swift package resolve`.

Pour récupérer une `.app` pré-construite (non signée Developer ID), télécharger l'archive depuis l'onglet [Releases](https://github.com/scadinot/voltapeak_batchApp/releases) du dépôt.

---

## Build & lancement

Avec Xcode : ouvrir `voltapeak_batch.xcodeproj` et lancer (⌘R).

En ligne de commande :

```bash
xcodebuild build \
  -project voltapeak_batch.xcodeproj \
  -scheme voltapeak_batch
```

> Le projet Xcode et le scheme s'appellent `voltapeak_batch` (sans suffixe `App`) — seul le **repo** porte le suffixe `App`.

---

## Format des fichiers d'entrée

| Caractéristique          | Valeur                                                       |
|--------------------------|--------------------------------------------------------------|
| Extension                | `.txt`                                                       |
| Encodage                 | `ISO Latin-1` (par défaut des potentiostats BioLogic / PalmSens européens) |
| Nombre de colonnes       | ≥ 2 (seules les 2 premières sont lues)                       |
| Première ligne           | en-tête — **ignorée**                                        |
| Colonne 1                | Potentiel en volts (`Double`)                                |
| Colonne 2                | Courant en ampères — **pic attendu en valeur négative** (convention SWV cathodique : le pipeline inverse le signe avant la détection) |
| Séparateur de colonnes   | configurable : tabulation / virgule / point-virgule / espace |
| Séparateur décimal       | configurable : point / virgule                               |
| Nombre minimal de lignes | ~11 (fenêtre Savitzky-Golay)                                 |
| Nombre maximum de points | **200 000** par fichier (garde-fou anti-DoS du solveur asPLS — `FileError.tooManyPoints`) |

### Convention de nommage

Pour permettre l'agrégation multi-électrodes, le nom de fichier doit suivre le pattern (regex case-insensitive) :

```
<base>_C<NN>.txt
```

Exemples valides : `ESSAI1_C01.txt`, `MANIP_2025-04_C12.txt`.

Un fichier qui ne respecte pas ce pattern est traité individuellement mais apparaît dans le récapitulatif Excel avec son nom complet comme *Base* et une colonne d'électrode vide.

### Exemple de contenu (tabulation, point décimal)

```
Potential	Current
-0.500	-1.2e-6
-0.490	-1.1e-6
-0.480	-0.9e-6
...
```

---

## Utilisation — interface graphique

La fenêtre principale (720×520) s'organise en `VStack` :

1. **Dossier d'entrée** — label + bouton **Parcourir** (`NSOpenPanel`) pour sélectionner le dossier contenant les fichiers `.txt`.
2. **GroupBox « Paramètres de lecture »** — 5 `Picker(.segmented)` :
   - *Séparateur de colonnes* : `Tabulation` (défaut), `Virgule`, `Point-virgule`, `Espace`,
   - *Séparateur décimal* : `Point` (défaut) ou `Virgule`,
   - *Export par fichier* : `Ne pas exporter` (défaut), `CSV` ou `XLSX`,
   - *Export graphique* : `Non` (défaut) ou `PNG`,
   - *Mode de traitement* : `Multi-thread (un Task par cœur)` (défaut) ou `Séquentiel`.
3. **GroupBox « Progression »** — `ProgressView` + compteur `X / Y fichier(s)`.
4. **GroupBox « Journal »** — `ScrollViewReader` + `LazyVStack` à auto-scroll, lignes colorées info/success/error, `textSelection(.enabled)`.
5. **Boutons d'action** :
   - **Ouvrir le dossier de résultats** (`NSWorkspace.shared.open`) — s'active une fois le traitement terminé,
   - **Lancer l'analyse** (`borderedProminent`).

Toute la rangée d'actions est `.disabled(isProcessing)` pendant le traitement.

> L'app fonctionne **App Sandbox désactivé** : accès libre au dossier choisi et à son frère `(results)`.

---

## Résultats produits

À chaque exécution, un dossier frère du dossier d'entrée est créé (ou nettoyé s'il existe déjà) :

```
<dossier_entrée>            ← vos fichiers .txt
<dossier_entrée> (results)  ← sortie générée
```

Le dossier de sortie est **nettoyé automatiquement** au début de chaque exécution (`.png`, `.csv` et `.xlsx` supprimés).

### Par fichier traité

| Fichier      | Toujours produit ? | Contenu                                                                                                                         |
|--------------|:------------------:|---------------------------------------------------------------------------------------------------------------------------------|
| `<nom>.png`  | si *Export graphique = PNG* | Rendu `ImageRenderer` (scale 3, ~3000×1800, palette matplotlib tab10) : signal brut, lissé, baseline asPLS, signal corrigé, marqueur de pic + `RuleMark` au potentiel du pic. |
| `<nom>.csv`  | si *Export par fichier = CSV*   | Colonnes `Potential`, `Current`, `SignalLisse`, `SignalCorrigé`.                                                          |
| `<nom>.xlsx` | si *Export par fichier = XLSX*  | Mêmes colonnes que le CSV.                                                                                                |

### Récapitulatif agrégé

Un unique `<nom_du_dossier>.xlsx` est écrit à la racine du dossier de résultats **dès qu'au moins un fichier valide a été traité** (en l'absence de résultat exploitable, le classeur n'est pas produit). Il regroupe une ligne par base, avec les colonnes suivantes pour chaque électrode détectée :

| Colonne                  | Source                                                                                                                                |
|--------------------------|---------------------------------------------------------------------------------------------------------------------------------------|
| `Base`                   | base extraite du nom de fichier                                                                                                       |
| `Fréq (Hz)`              | **50,0** par défaut (valeur codée en dur — voir [Feuille de route](#feuille-de-route))                                                |
| `C<NN> - Tension (V)`    | potentiel du pic après correction                                                                                                     |
| `C<NN> - Courant (A)`    | amplitude du pic après correction                                                                                                     |
| `C<NN> - Charge (C)`     | **formule Excel** `=<courantCol><row> / <freqCol><row>` — recalculée dynamiquement si la fréquence est modifiée dans la cellule       |

Note : aucune valeur `<v>` numérique n'est écrite pour la colonne Charge — seule la formule l'est, ce qui garantit le recalcul à l'ouverture par Excel / Numbers / Google Sheets / LibreOffice.

---

## Chaîne de traitement par fichier

```
┌──────────────────────────┐
│ Fichier *.txt (entrée)   │
└────────────┬─────────────┘
             │ SWVFileReader.read()        ISO Latin-1, séparateurs configurables
             ▼
┌──────────────────────────┐
│ [VoltammetryPoint] brut  │
└────────────┬─────────────┘
             │ processData()               tri par potentiel, inversion du signe (-I)
             ▼
┌──────────────────────────┐
│ Signal nettoyé           │
└────────────┬─────────────┘
             │ SavitzkyGolay.apply()       window=11, polyorder=2, coeffs scipy
             ▼
┌──────────────────────────┐
│ Signal lissé             │
└────────────┬─────────────┘
             │ SignalProcessing.detectPeak()   marge 10 %, maxSlope=500
             ▼
┌───────────────────────────┐
│ (x_pic, y_pic) provisoires│
└────────────┬──────────────┘
             │ WhittakerASPLS.baseline()   asPLS, exclusion ±3 %, dgbsv_ banded
             ▼
┌──────────────────────────┐
│ Baseline estimée         │
└────────────┬─────────────┘
             │ signal_corrigé = signal_lissé - baseline
             ▼
┌──────────────────────────┐
│ Signal corrigé           │
└────────────┬─────────────┘
             │ SignalProcessing.detectPeak()   pic final
             ▼
┌──────────────────────────┐
│ (x_pic, y_pic) corrigés  │
└────────────┬─────────────┘
             │ parseBaseAndElectrode()     regex ^(.+)_C(\d{2})\.txt$
             │ exports optionnels          (PNG / CSV / XLSX sur MainActor)
             ▼
┌──────────────────────────┐
│ BatchFileResult          │  → agrégé par BatchAggregator dans le classeur .xlsx récap
└──────────────────────────┘
```

---

## Paramètres algorithmiques

Les hyperparamètres sont actuellement **codés en dur** dans le code Swift. Leur exposition dans l'interface graphique est prévue (voir [Feuille de route](#feuille-de-route)).

| Paramètre               | Valeur     | Rôle                                                                                         |
|-------------------------|------------|----------------------------------------------------------------------------------------------|
| `windowLength`          | `11`       | Largeur de la fenêtre Savitzky-Golay (nombre impair de points).                              |
| `polyorder`             | `2`        | Ordre du polynôme ajusté localement par Savitzky-Golay.                                      |
| `marginRatio`           | `0.10`     | Fraction de points exclus aux deux bords lors de la recherche du pic.                        |
| `maxSlope`              | `500`      | Pente absolue maximale tolérée pour un candidat-pic (filtre les fronts).                     |
| `exclusionWidthRatio`   | `0.03`     | Demi-largeur (fraction de la plage de potentiel) de la zone protégée autour du pic.          |
| `lambdaFactor`          | `1e3`      | Facteur multiplicatif du paramètre de lissage Whittaker : `lam = lambdaFactor · n²`.         |
| `diffOrder`             | `2`        | Ordre de différence dans l'ajustement Whittaker (matrice pentadiagonale).                    |
| `tol`                   | `1e-2`     | Tolérance de convergence asPLS (sur Δ poids, pas Δ baseline — comme pybaselines).            |
| `maxIter`               | `25`       | Nombre maximum d'itérations de réajustement des poids (boucle `0...maxIter`).                |
| `maxN`                  | `200 000`  | Nombre maximum de points accepté par le solveur asPLS (garde-fou anti-DoS).                  |
| Fréquence injectée      | `50 Hz`    | Utilisée pour la formule `Charge = Courant / Fréquence` dans le classeur récap.              |

---

## Architecture du code

Source dans `voltapeak_batch/` :

| Fichier                          | Rôle                                                                                          |
|----------------------------------|-----------------------------------------------------------------------------------------------|
| `voltapeak_batchApp.swift`       | `@main App` SwiftUI — `WindowGroup` 720×520, supprime `CommandGroup(.newItem)`.               |
| `ContentView.swift`              | Vue racine SwiftUI : `folderRow`, `settingsBox`, `progressBox`, `logBox`, `actionRow`.        |
| `BatchViewModel.swift`           | `@MainActor @Observable` — orchestrateur ; gère `TaskGroup`, journal, progression, écriture XLSX final. |
| `BatchProcessor.swift`           | `nonisolated enum` — pipeline **d'un** fichier (compute-only) + `writeCSV`, `writeXLSX`, `parseBaseAndElectrode` (regex `^(.+)_C(\d{2})\.txt$`). |
| `BatchAggregator.swift`          | Classeur récapitulatif : 1 ligne / base, 3 colonnes / électrode (Tension, Courant, Charge formule). |
| `SWVFileReader.swift`            | Lecture `.txt` (ISO Latin-1), `SWVFileConfiguration`, erreurs localisées (`LocalizedError`). |
| `SavitzkyGolay.swift`            | 11 jeux de coefficients pré-calculés depuis `scipy.signal.savgol_coeffs(11, 2)` (`mode='interp'`), fallback moyenne glissante pour autres tailles. |
| `WhittakerASPLS.swift`           | `enum WhittakerASPLS` — port Swift exact (Zhang 2020), matrice pentadiagonale `D^T D` en banded LAPACK (KL=KU=2, LDAB=7), `dgbsv_` via Accelerate. |
| `SignalProcessing.swift`         | `detectPeak()` (marge + filtre de pente), `gradient()` (reproduit `numpy.gradient` pour pas non uniformes). |
| `ChartPNGRenderer.swift`         | Rendu PNG offscreen via `Swift Charts` + `ImageRenderer` (`@MainActor`, scale 3, ~300 dpi, ~3000×1800 px), `autoreleasepool` pour borner la heap. |
| `XLSXWriter.swift`               | Génération XLSX 100 % autonome : 5 XML OOXML minimaux + mini-ZIP store-only (méthode 0) + CRC32 PKZIP. Cellules `.number / .string / .formula / .empty`. |
| `VoltammetryData.swift`          | Modèles `Sendable` : `VoltammetryPoint`, `VoltammetryAnalysis`, `SWVFileConfiguration` (enums `ColumnSeparator` / `DecimalSeparator`), `PerFileExport`, `BatchFileResult`. |
| `Assets.xcassets/`               | `AccentColor`, `AppIcon` (PNG 16…1024 px).                                                    |

Chaînage des appels :

```
voltapeak_batchApp
 └── ContentView
      ├── Picker → BatchViewModel.config (séparateurs, exports, parallelEnabled)
      ├── Bouton Parcourir → NSOpenPanel → BatchViewModel.inputFolder
      └── Bouton Lancer l'analyse → BatchViewModel.runAnalysis() [async, @MainActor]
           ├── enumerateInputFiles()
           ├── cleanOutputFolder()
           ├── withTaskGroup(...) borné à activeProcessorCount  (mode parallèle)
           │     pour chaque fichier (nonisolated) :
           │     └── BatchProcessor.processOne(url:, options:)
           │           ├── SWVFileReader.read()
           │           ├── processData()
           │           ├── SavitzkyGolay.apply()
           │           ├── SignalProcessing.detectPeak()    (signal lissé)
           │           ├── WhittakerASPLS.baseline()
           │           ├── SignalProcessing.detectPeak()    (signal corrigé)
           │           └── BatchProcessor.parseBaseAndElectrode()
           │     puis (@MainActor) finalize() : ChartPNGRenderer / writeCSV / writeXLSX
           ├── BatchAggregator.write(_:to:)                 classeur récap
           └── append au journal + activation "Ouvrir le dossier de résultats"
```

---

## Performance & concurrence

- `async/await` partout ; `runAnalysis()` est `async` sur `@MainActor`.
- **Toggle séquentiel / parallèle exposé dans la GUI** (`parallelEnabled`).
- En mode parallèle : `withTaskGroup` avec **pool borné = `ProcessInfo.activeProcessorCount`**, géré en sliding-window (amorce + drain en remplacement 1-pour-1) pour maintenir la fenêtre pleine pendant les exports MainActor.
- Le **calcul CPU-bound est hors MainActor** : les `group.addTask` s'exécutent en contexte `nonisolated`.
- Les **écritures (PNG / CSV / XLSX) sont sérialisées sur le MainActor** dans `finalize(...)` — `ImageRenderer` est confiné `@MainActor`, et un freeze a été observé à ~800 fichiers en concurrence simultanée d'`ImageRenderer`. Un `autoreleasepool` interne au rendu PNG borne la heap.
- En mode séquentiel : chaque fichier passe par `Task.detached(priority: .userInitiated)`, awaité. Utile en débogage (exceptions parfois absorbées par le `TaskGroup`) ou sur environnement contraint (1 vCPU).
- Tri par index d'origine pour rendre le récapitulatif **déterministe** (peu importe l'ordre d'achèvement).

---

## Tests

**Pas encore de target de tests** dans ce repo : les algorithmes scientifiques (Savitzky-Golay, Whittaker asPLS, détection de pic) sont vérifiés en amont dans [`voltapeakApp`](https://github.com/scadinot/voltapeakApp), qui en héberge la suite `Testing` complète (`SavitzkyGolayTests`, `WhittakerASPLSTests`, `SignalProcessingTests`). Comme le code algorithmique est partagé à l'identique, les garanties s'étendent à cette app.

---

## CI/CD

| Workflow              | Déclencheur                | Action                                      | Artefact                    |
|-----------------------|----------------------------|---------------------------------------------|-----------------------------|
| `build-artifact.yml`  | `push` sur `main`, `workflow_dispatch` | Détection auto du scheme + `xcodebuild archive` Release **non signé** (`CODE_SIGN_IDENTITY="-"`), sortie `xcpretty` | `voltapeak_batch-unsigned-<sha>` (`.app` via `actions/upload-artifact@v4`) |
| `release.yml`         | tag `v*` ou `[0-9]*`       | `xcodebuild archive` + `ditto -c -k --keepParent` → zip + `gh release create --generate-notes` (ou `upload --clobber` si tag existe) | `voltapeak_batch-<TAG>.zip` (release GitHub) |

> Les `.app` produites sont **ad-hoc signed** (`CODE_SIGN_IDENTITY="-"`) — ni signature Developer ID, ni notarisation. Au premier lancement, Gatekeeper bloque : faire un clic droit → *Ouvrir*, puis confirmer.

---

## Algorithmes & références

- **Savitzky-Golay** : implémentation Swift native avec **coefficients pré-calculés** depuis `scipy.signal.savgol_coeffs(window_length=11, polyorder=2)`. Les 11 jeux de coefficients (bord gauche pos 0-4, centre symétrique pos 5, bord droit pos 6-10) reproduisent `mode='interp'` de scipy **bit-pour-bit** sur le cas (11, 2).
- **Whittaker asPLS** (*Adaptive Smoothness Penalized Least Squares*) : port Swift de [`pybaselines.whittaker.aspls`](https://pybaselines.readthedocs.io/en/latest/api/whittaker/index.html#pybaselines.whittaker.aspls), résolu par un solveur **LAPACK banded `dgbsv_`** (Accelerate, KL=KU=2, LDAB=7) en O(n) — au lieu de O(n³) d'un Gauss dense — ce qui rend tractable des signaux jusqu'à 200 000 points. Itération `0...maxIter` (reproduction de `range(max_iter+1)` Python), convergence sur Δ poids (et non Δ baseline), mise à jour sigmoïde `expit(-(k/σ)·(r-σ))` avec `σ = std(résidus négatifs, ddof=1)`, `α[i] = |r[i]| / max|r|`.
  - Référence : Zhang, F., et al. (2020). *Baseline correction for Raman spectra using an improved asymmetric least squares method.*

Les détails d'implémentation (paramètres, garde-fous, conventions de signe) sont préservés à l'identique entre les 3 applications Swift et leurs origines Python.

---

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `Erreur dans le fichier … : Error tokenizing data` | Mauvais séparateur de colonnes | Choisir le bon séparateur dans la GUI. |
| Toutes les valeurs sont lues comme chaînes ou zéro | Mauvais séparateur décimal | Basculer entre *Point* et *Virgule*. |
| Pic « inversé » ou détecté loin du sommet visible | Fichier avec pic déjà en courant positif (orientation anodique) | Pré-inverser la colonne courant en amont — le pipeline attend une convention cathodique (cf. [Format des fichiers d'entrée](#format-des-fichiers-dentrée)). |
| `FileError.tooManyPoints` | Fichier > 200 000 lignes (garde-fou asPLS) | Décimer le signal en amont. |
| Le fichier n'apparaît pas dans la bonne colonne d'électrode du récap | Nom de fichier ne respectant pas `<base>_C<NN>.txt` (regex case-insensitive) | Renommer les fichiers — `_C` suivi de **deux chiffres exactement** avant `.txt`. |
| Journal vide et pas de traitement | Aucun `.txt` dans le dossier sélectionné | Vérifier l'extension et le dossier. |
| Le pic détecté est sur un bord | Bruit important aux extrémités | Augmenter `marginRatio` dans le code (exposition UI prévue). |
| La baseline épouse le pic | `lambdaFactor` trop bas ou zone d'exclusion trop étroite | Augmenter `lambdaFactor` ou `exclusionWidthRatio` dans le code (exposition UI prévue). |
| Freeze visible vers ~800 fichiers en parallèle | Saturation `ImageRenderer` `@MainActor` | Désactiver *Export graphique = PNG* ou basculer en mode séquentiel. |
| Premier lancement bloqué par Gatekeeper | `.app` non signée Developer ID | Clic droit sur l'app → *Ouvrir* → confirmer. |

---

## Feuille de route

Voir [`ROADMAP.md`](ROADMAP.md) pour l'ensemble des évolutions prévues (à venir : exposition des hyperparamètres dans l'UI, fréquence configurable, signature Developer ID, etc.).

---

## Licence et auteur

- **Auteur** : Stéphane Cadinot ([@scadinot](https://github.com/scadinot)).
- **Licence** : [MIT](LICENSE) — Copyright (c) 2026 Stéphane Cadinot.

Pour toute question ou contribution, ouvrir une *issue* sur le dépôt GitHub.
