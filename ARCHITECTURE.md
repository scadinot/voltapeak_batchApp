# Architecture

## Pipeline

Le pipeline batch enchaîne 9 étapes, orchestrées par `BatchViewModel.runAnalysis()`
et exécutées par fichier via `BatchProcessor.process(fileURL:config:)` :

```
┌─────────────────┐   ┌──────────────┐   ┌────────────────┐   ┌──────────────────┐
│ 1. readFile     │ → │ 2. processData│ → │ 3. Savitzky-G. │ → │ 4. détection pic │
│   (Latin-1)     │   │ (tri + signe)│   │  (scipy exact) │   │  (margin + slope)│
└─────────────────┘   └──────────────┘   └────────────────┘   └────────┬─────────┘
                                                                       │
                       ┌──────────────────────────────────────┐        │
                       │   5. asPLS (Zhang 2020)              │ ←──────┘
                       │   poids=0.001 dans la fenêtre du pic │
                       │   λ = lambdaFactor · n²              │
                       └───────────────┬──────────────────────┘
                                       │
                       ┌───────────────▼──────────────────────┐
                       │ 6. signal corrigé = lissé − baseline │
                       │ 7. re-détection de pic               │
                       └───────────────┬──────────────────────┘
                                       │
              ┌────────────┬───────────┼───────────┬───────────────────────┐
              ▼            ▼           ▼           ▼                       ▼
       8a. PNG (×n)   8b. CSV/XLSX  Outcome   9. agrégation       Excel récapitulatif
                       optionnel    (V, A)    inter-fichiers      (1 ligne / base,
                                                                   formule =I/F)
```

Détails numériques de chaque étape dans [ALGORITHMS.md](ALGORITHMS.md).

## Fichiers Swift

| Fichier | Rôle | Origine |
|---|---|---|
| `voltapeak_batchApp.swift` | Entry point `@main` SwiftUI | nouveau |
| `ContentView.swift` | UI : dossier + paramètres + progression + journal | nouveau |
| `BatchViewModel.swift` | Orchestrateur (sélection, parallélisme, journal) | nouveau |
| `BatchProcessor.swift` | Pipeline complet pour un fichier (étapes 1-8) | nouveau |
| `BatchAggregator.swift` | Construction du classeur récapitulatif (étape 9) | nouveau |
| `ChartPNGRenderer.swift` | Rendu PNG offscreen via `ImageRenderer` | nouveau |
| `VoltammetryData.swift` | Modèles `VoltammetryPoint`, `VoltammetryAnalysis`, `SWVFileConfiguration`, `PerFileExport`, `BatchFileResult` | repris de `voltapeakApp` + extensions batch |
| `SWVFileReader.swift` | Lecture et parsing `.txt` SWV | **identique** à `voltapeakApp` |
| `SavitzkyGolay.swift` | Filtre scipy-exact (window=11, ordre=2) | **identique** à `voltapeakApp` |
| `SignalProcessing.swift` | Détection de pic + gradient `numpy` 2ᵉ ordre | **identique** à `voltapeakApp` |
| `WhittakerASPLS.swift` | Algorithme asPLS Zhang 2020 | **identique** à `voltapeakApp` |
| `XLSXWriter.swift` | Mini-ZIP + OOXML : `write(analysis:...)` + `writeSummary(...)` | adapté de `voltapeakApp` (ajout des cellules typées et des formules) |

**12 fichiers Swift au total.** Aucun fichier de test pour le moment.

## Dépendances

### Frameworks Apple

| Framework | Utilisation |
|---|---|
| `SwiftUI` | UI déclarative |
| `Charts` | Rendu du voltampérogramme (PNG via `ImageRenderer`) |
| `Foundation` | Types de base, `URL`, `Data`, `String`, `FileManager`, `NSRegularExpression` |
| `AppKit` (`NSOpenPanel`, `NSWorkspace`, `NSBitmapImageRep`) | Boîtes de dialogue natives, export PNG |
| `Observation` (`@Observable`) | Réactivité ViewModel → UI |

### Dépendances externes

**Aucune.** Pas de SPM, pas de CocoaPods. Tous les algorithmes scientifiques
sont implémentés à partir des spécifications mathématiques. L'export `.xlsx`
est généré sans bibliothèque tierce (mini-ZIP store-only + XML OOXML).

## Modèles de données

```swift
struct VoltammetryPoint: Identifiable {
    let id = UUID()
    let potential: Double     // volts
    let current: Double       // ampères
}

struct VoltammetryAnalysis {
    let rawData: [VoltammetryPoint]
    let smoothedSignal: [Double]
    let baseline: [Double]
    let correctedSignal: [Double]
    let peakPotential: Double
    let peakCurrent: Double
    let fileName: String
}

struct SWVFileConfiguration {
    var columnSeparator: ColumnSeparator = .tab    // \t , ; espace
    var decimalSeparator: DecimalSeparator = .point // . ou ,
    var encoding: String.Encoding = .isoLatin1
}

enum PerFileExport: Int { case none, csv, xlsx }

struct BatchFileResult {
    let baseName: String
    let electrode: String         // ex. "C01", ou "" si pas de convention
    let peakPotential: Double
    let peakCurrent: Double
}
```

## Concurrence

- Tout l'état UI vit sur le `MainActor` (`BatchViewModel` est `@MainActor`).
- Le pipeline CPU-intensif (`BatchProcessor.process`) est exécuté via
  `Task.detached(priority: .userInitiated)` pour ne pas bloquer l'UI.
- Le rendu PNG (`ChartPNGRenderer.renderPNG`) revient sur le `MainActor`
  (SwiftUI `ImageRenderer` requiert le MainActor).
- Le mode parallèle limite la concurrence à
  `ProcessInfo.processInfo.activeProcessorCount` via un `TaskGroup` à
  fenêtre glissante (slot libéré → tâche suivante lancée).

## Cycle de vie d'une analyse

1. L'utilisateur sélectionne le dossier → `BatchViewModel.inputFolder` mis à jour.
2. Bouton « Lancer l'analyse » → `BatchViewModel.runAnalysis()` (async).
3. Création du dossier `<entrée> (results)`, nettoyage des artefacts.
4. Énumération triée des `.txt`, dispatch séquentiel ou parallèle.
5. Pour chaque fichier : `BatchProcessor.process` → PNG (+ CSV/XLSX) →
   `BatchFileResult` accumulé.
6. `BatchAggregator.writeSummary` → `<nom_dossier>.xlsx`.
7. Bouton « Ouvrir le dossier de résultats » activé.

## Conventions de nommage

- **Fichiers** : un mot par concept (`BatchProcessor`, `BatchAggregator`).
- **Functions analyse** : copiées telles quelles de `voltapeakApp`
  (mêmes signatures, mêmes noms — `SavitzkyGolay.filter(_:)`,
  `WhittakerASPLS.aspls(...)`, `SignalProcessing.detectPeak(...)`).
