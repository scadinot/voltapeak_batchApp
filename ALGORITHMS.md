# Algorithmes numériques

Ce document détaille les algorithmes utilisés et leur correspondance avec la
référence Python (`scipy`, `numpy`, `pybaselines`). Tous les paramètres sont
identiques à ceux de
[`voltapeak_batch`](https://github.com/scadinot/voltapeak_batch) (Python) et
de [`voltapeakApp`](https://github.com/scadinot/voltapeakApp) (Swift
mono-fichier, déjà validé à la 6ᵉ décimale).

## 1. Lecture du fichier SWV

**Implémentation :** `SWVFileReader.readFile(at:config:)`

- **Encodage** : ISO Latin-1.
- **Format attendu** :
  ```
  [Entête - 1 ligne, ignorée]
  potentiel<sep>courant
  potentiel<sep>courant
  ...
  ```
- **Séparateurs configurables** : tabulation, virgule, point-virgule, espace.
- **Décimale configurable** : point ou virgule.
- **Filtrage anticipé** : les lignes à courant nul sont écartées dès la
  lecture (`current != 0`).

## 2. Traitement des données

**Implémentation :** `SWVFileReader.processData(_:)`

1. **Tri** par potentiel croissant.
2. **Inversion de signe** du courant : `signal = -current` (convention SWV
   cathodique → pic en maximum).

Sortie : `(potentials: [Double], currents: [Double])`, alignés et triés.

## 3. Lissage Savitzky-Golay

**Implémentation :** `SavitzkyGolay.filter(_:windowLength:polynomialOrder:)`

Équivalent strict de `scipy.signal.savgol_filter(signal, 11, 2, mode='interp')`.

### Coefficients

- **Intérieur (indices 5..n-6)** : convolution centrée avec
  `[−36, 9, 44, 69, 84, 89, 84, 69, 44, 9, −36] / 429` (somme = 1).
- **Bords (5 premiers et 5 derniers points)** : 10 jeux de coefficients
  `savgol_coeffs(11, 2, pos=p, use='dot')` codés en dur dans
  `SavitzkyGolay.boundaryCoeffs[p]` pour `p ∈ {0,1,2,3,4,6,7,8,9,10}`.

## 4. Détection de pic

**Implémentation :** `SignalProcessing.detectPeak(signal:potentials:marginRatio:maxSlope:)`

- **Marge** : `marginRatio = 0.10` → ignore les 10 % des deux côtés.
- **Filtre de pente** : `maxSlope = 500` → écarte les points dont la pente
  locale `|dI/dV|` dépasse le seuil.
- **Gradient** : `gradient(y, x)` reproduit `numpy.gradient(y, x)` avec
  différences finies 1ᵉʳ ordre aux bords et différences centrées 2ᵉ ordre
  non-uniformes à l'intérieur.

Appliqué deux fois dans le pipeline batch :
1. sur le signal lissé pour positionner la zone d'exclusion asPLS,
2. sur le signal corrigé pour la valeur finale retenue.

## 5. Baseline asPLS (Zhang 2020)

**Implémentation :** `WhittakerASPLS.aspls(...)`

Équivalent strict de `pybaselines.whittaker.aspls`.

### Paramètres utilisés par le pipeline batch

| Paramètre | Valeur | Notes |
|---|---|---|
| `lam` | `1e3 · n²` | rigidité ; mise à l'échelle par n² (densité indépendante) |
| `diffOrder` | 2 | différences secondes |
| `tol` | 1e-2 | convergence sur le changement relatif des poids |
| `maxIter` | 25 | nombre maximal d'itérations |
| `asymmetricCoef` | 0.5 | coefficient k du papier asPLS |
| `weights` initiaux | 1.0 partout, **0.001** dans la zone d'exclusion |

### Zone d'exclusion

```swift
let exclusionWidthRatio = 0.03
let exclusionWidth = exclusionWidthRatio * (potentials.last! - potentials.first!)
let min = peakPotential - exclusionWidth
let max = peakPotential + exclusionWidth
```

### Cœur de l'algorithme

À chaque itération `i` :

1. Construction de `lhs = diag(α) · (λ · D^T D)` puis `lhs[diag] += w`.
2. Résolution `lhs · baseline = w · y` par élimination de Gauss avec
   pivotage partiel (matrice non-symétrique → pas de Cholesky).
3. Résidus `r = y - baseline`.
4. Si `card(r < 0) < 2` → exit_early (comme pybaselines).
5. `σ = std(r[r<0], ddof=1)` ; si `σ = 0` → break.
6. Nouveaux poids : `w_new[i] = 1 / (1 + exp((k/σ) · (r[i] - σ)))`.
7. Convergence : `|w - w_new|₁ / |w_new|₁ < tol` → break.
8. Sinon : `w ← w_new`, `α[i] = |r[i]| / max(|r|)`.

### Construction de `D^T D`

`D` matrice de différences secondes de taille `(n-2) × n`. Le produit
`D^T D` est pentadiagonal et est construit directement par
`WhittakerASPLS.buildDTD(n:diffOrder:)`.

## 6. Signal corrigé

```swift
let corrected = zip(smoothed, baseline).map { $0 - $1 }
```

## 7. Re-détection du pic

Même fonction qu'à l'étape 4, appliquée sur `corrected`. La valeur retenue
pour le récapitulatif est `(correctedPeakPotential, correctedPeakCurrent)`.

## 8. Sorties par fichier

- **PNG** (toujours) : 5 courbes (`raw`, `smoothed`, `baseline`, `corrected`,
  `peak marker`), couleurs matplotlib tab10, rendu via `ImageRenderer`
  SwiftUI à `scale = 3.0` (≈ 300 dpi sur écran de référence).
- **CSV** (option) : 4 colonnes `Potential,Current,SignalLisse,SignalCorrigé`.
- **XLSX** (option) : 5 colonnes via `XLSXWriter.write(analysis:...)`.

## 9. Agrégation multi-électrodes

**Implémentation :** `BatchAggregator.writeSummary(results:outputFolder:folderBaseName:frequencyHz:)`

1. Convention `<base>_C<NN>.txt` → base + électrode (regex
   `^(.+)_C(\d{2})\.txt$`).
2. Regroupement par `base` (préservation de l'ordre d'apparition).
3. Pour chaque électrode distincte (triée) : 3 colonnes
   `<elec> - Tension (V)`, `<elec> - Courant (A)`, `<elec> - Charge (C)`.
4. La colonne `Charge (C)` contient la **formule Excel**
   `=<courantCol><row>/<freqCol><row>` (calculée par Excel à l'ouverture).
5. La colonne `Fréq (Hz)` est en position B avec la valeur 50.0 par défaut.

## Parité avec la version Python

Toutes les valeurs numériques (paramètres, seuils, ordres) sont **strictement
identiques** à `voltapeak_batch/__main__.py`. La validation à la 6ᵉ décimale
de l'implémentation `voltapeakApp` ([VALIDATION.md de voltapeakApp](https://github.com/scadinot/voltapeakApp/blob/main/VALIDATION.md))
s'applique directement puisque les fonctions sont reprises sans modification.
