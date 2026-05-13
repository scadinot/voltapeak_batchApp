# Architecture

`voltapeak_batchApp` est l'**application batch multi-électrodes** de la
famille `voltapeak*`. Les fonctions d'analyse (lecture SWV, Savitzky-Golay,
détection de pic, asPLS) sont reprises sans modification de
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp) (référence
canonique mono-fichier) ; ce document décrit l'orchestration batch ajoutée
par-dessus. La variante loops/dosage est documentée dans
[`voltapeak_loopsApp`](https://github.com/scadinot/voltapeak_loopsApp).

Détails numériques de chaque étape de calcul dans [ALGORITHMS.md](ALGORITHMS.md).

## Pipeline

Le pipeline batch enchaîne 9 étapes, orchestrées par
`BatchViewModel.runAnalysis()` et exécutées par fichier via
`BatchProcessor.process(fileURL:config:)` :

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

## Fichiers Swift

| Fichier | Rôle | Origine |
|---|---|---|
| `voltapeak_batchApp.swift` | Entry point `@main` SwiftUI | nouveau |
| `ContentView.swift` | UI : dossier + paramètres + progression + journal | nouveau |
| `BatchViewModel.swift` | Orchestrateur (sélection, parallélisme, journal) | nouveau |
| `BatchProcessor.swift` | Pipeline complet pour un fichier (étapes 1-8) | nouveau |
| `BatchAggregator.swift` | Construction du classeur récapitulatif (étape 9) | nouveau |
| `ChartPNGRenderer.swift` | Rendu PNG offscreen via `ImageRenderer` | nouveau |
| `VoltammetryData.swift` | Modèles + extensions batch (`PerFileExport`, `BatchFileResult`) | repris de `voltapeakApp` + extensions |
| `SWVFileReader.swift` | Lecture et parsing `.txt` SWV | **identique** à `voltapeakApp` |
| `SavitzkyGolay.swift` | Filtre scipy-exact (window=11, ordre=2) | **identique** à `voltapeakApp` |
| `SignalProcessing.swift` | Détection de pic + gradient `numpy` 2ᵉ ordre | **identique** à `voltapeakApp` |
| `WhittakerASPLS.swift` | Algorithme asPLS Zhang 2020 | **identique** à `voltapeakApp` |
| `XLSXWriter.swift` | Mini-ZIP + OOXML : `write(analysis:...)` + `writeSummary(...)` | adapté de `voltapeakApp` (cellules typées + formules) |

**12 fichiers Swift au total.** Aucun fichier de test pour le moment.

## Dépendances

### Frameworks Apple (SDK)

| Framework | Utilisation |
|---|---|
| `SwiftUI` | UI déclarative |
| `Charts` | Rendu du voltampérogramme (PNG via `ImageRenderer`) |
| `Foundation` | Types de base, `URL`, `Data`, `String`, `FileManager`, `NSRegularExpression` |
| `AppKit` (`NSOpenPanel`, `NSWorkspace`, `NSBitmapImageRep`) | Boîtes de dialogue natives, export PNG |
| `Observation` (macro `@Observable`) | Réactivité ViewModel → UI |

### Dépendances externes

**Aucune.** Pas de Swift Package Manager, pas de CocoaPods. Tous les
algorithmes scientifiques sont implémentés à partir des spécifications
mathématiques. L'export `.xlsx` est généré sans bibliothèque tierce
(mini-ZIP store-only + XML OOXML).

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

1. L'utilisateur sélectionne le dossier → `BatchViewModel.inputFolder`
   mis à jour.
2. Bouton « Lancer l'analyse » → `BatchViewModel.runAnalysis()` (async).
3. Création du dossier `<entrée> (results)`, nettoyage des artefacts.
4. Énumération triée des `.txt`, dispatch séquentiel ou parallèle.
5. Pour chaque fichier : `BatchProcessor.process` → PNG (+ CSV/XLSX) →
   `BatchFileResult` accumulé.
6. `BatchAggregator.writeSummary` → `<nom_dossier>.xlsx`.
7. Bouton « Ouvrir le dossier de résultats » activé.

## Choix de design

### Fonctions d'analyse copiées telles quelles de `voltapeakApp`

`SWVFileReader`, `SavitzkyGolay`, `SignalProcessing`, `WhittakerASPLS` et
le cœur de `VoltammetryData` sont importés sans modification depuis
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp). Mêmes
signatures, mêmes noms (`SavitzkyGolay.filter(_:)`,
`WhittakerASPLS.aspls(...)`, `SignalProcessing.detectPeak(...)`). La
parité numérique avec la référence Python en découle automatiquement (cf.
[VALIDATION.md](VALIDATION.md)).

### Mise à jour des fonctions analytiques

Lorsqu'une amélioration est apportée côté `voltapeakApp` (correction de
bug, nouveau paramètre), la procédure standard est :

1. Copier le fichier modifié dans `voltapeak_batch/`.
2. Mettre à jour l'entête de copyright si nécessaire.
3. Vérifier que la sortie batch reste identique sur les jeux de
   validation (cf. [VALIDATION.md](VALIDATION.md)).

### Pipeline pur compute + I/O ViewModel

`BatchProcessor.process` ne touche pas au disque autrement que pour lire
le `.txt` d'entrée ; il retourne un `BatchFileResult` + les vecteurs
nécessaires aux exports. Les écritures (PNG, CSV, XLSX) sont déléguées au
`BatchViewModel` sur le MainActor. Avantages :

- Le `TaskGroup` parallélise du calcul, pas d'I/O concurrent.
- `ImageRenderer` (MainActor) fonctionne sans hop supplémentaire.
- Les échecs d'écriture sont logués en rouge dans la GUI sans bloquer
  l'analyse des fichiers restants.

### Export `.xlsx` sans dépendance

`XLSXWriter` construit, sans bibliothèque tierce :

1. Les 5 fichiers XML OOXML minimaux.
2. Un conteneur ZIP store-only (compression method = 0).
3. CRC32 PKZIP (polynôme inversé `0xEDB88320`).

Le récapitulatif inter-fichiers injecte des **formules Excel**
(`=Courant / Fréq`) recalculées dynamiquement à l'ouverture du classeur.

## Compatibilité

- **macOS 26.1+** — déploiement minimum.
- **Xcode 26+** pour builder (`objectVersion = 77` du `project.pbxproj`).
- **Architectures** : Universal (Intel x86_64 + Apple Silicon arm64).
- **App Sandbox** désactivé pour permettre la lecture/écriture du dossier
  voisin `<entrée> (results)`.

## Hors-scope (volontairement)

- Pas de tests unitaires (les fonctions d'analyse sont déjà validées dans
  [`voltapeakApp`](https://github.com/scadinot/voltapeakApp) ; la
  validation propre au batch est documentée dans
  [VALIDATION.md](VALIDATION.md)).
- Pas de prévisualisation in-app du graphique (l'aperçu individuel se
  fait via `voltapeakApp` sur un fichier donné).
- Pas de configuration des paramètres scientifiques via UI
  (`lam = 1e3·n²`, etc., hardcodés pour parité `voltapeakApp`).
- Pas de gestion des formats loops/dosage — voir
  [`voltapeak_loopsApp`](https://github.com/scadinot/voltapeak_loopsApp).
