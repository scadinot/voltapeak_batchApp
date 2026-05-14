# Guide développeur

Guide à l'attention des contributeurs souhaitant faire évoluer
`voltapeak_batchApp`. Pour la **méthodologie de validation**, voir
[VALIDATION.md](VALIDATION.md). Pour les **détails algorithmiques**,
voir [ALGORITHMS.md](ALGORITHMS.md).

Les fonctions d'analyse de cette app sont **reprises à l'identique** de
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp), qui en est
la **référence canonique**. Toute modification numérique se fait là-bas
en premier et est propagée ici sans changement (cf. § « Mise à jour des
fonctions d'analyse »).

## Prérequis

| Outil | Version |
|---|---|
| **macOS** | 26.1+ (Tahoe) |
| **Xcode** | 26+ |
| **Python** (uniquement pour validation) | 3.11+ avec `numpy`, `scipy`, `pybaselines`, `pandas`, `matplotlib` |

Toutes les bibliothèques Swift utilisées proviennent du SDK macOS
(`SwiftUI`, `Charts`, `Foundation`, `AppKit`, `Observation`). **Aucun
Swift Package Manager.**

## Build et lancement

```bash
git clone https://github.com/scadinot/voltapeak_batchApp.git
cd voltapeak_batchApp
open voltapeak_batch.xcodeproj
# ⌘R pour compiler et lancer
```

Le `PBXFileSystemSynchronizedRootGroup` (Xcode 26+) découvre
automatiquement les fichiers Swift du dossier `voltapeak_batch/` — pas
besoin d'ajouter manuellement chaque nouveau fichier à la cible.

En ligne de commande :

```bash
xcodebuild -project voltapeak_batch.xcodeproj \
           -scheme voltapeak_batch \
           -configuration Release \
           build
```

### Resets utiles

| Symptôme | Action |
|---|---|
| Code modifié mais comportement inchangé | Product → Clean Build Folder (⌘⇧K) |
| Icône Dock incorrecte / placeholder blanc | Supprimer `~/Library/Developer/Xcode/DerivedData/voltapeak_batch-*` |
| Erreurs de fichiers « rouges » dans Xcode après pull | Quitter Xcode et relancer (le `PBXFileSystemSynchronizedRootGroup` se resync) |
| Permissions de dossier (lecture/écriture refusée) | Vérifier que l'App Sandbox est désactivé dans Signing & Capabilities |

## Structure du projet

Voir [ARCHITECTURE.md](ARCHITECTURE.md) pour la vue d'ensemble.

```
voltapeak_batchApp/                  # racine du dépôt
├── README.md
├── ARCHITECTURE.md
├── ALGORITHMS.md
├── VALIDATION.md
├── DEVELOPMENT.md         # ce fichier
├── DISTRIBUTION.md
├── CHANGELOG.md
├── .gitignore
├── voltapeak_batch.xcodeproj/       # projet Xcode 26
└── voltapeak_batch/                 # sources Swift + assets
    ├── *.swift                      # 12 fichiers core
    └── Assets.xcassets/             # AppIcon + AccentColor
```

## Conventions de code

| Aspect | Convention |
|---|---|
| Langue commentaires / UI | **Français** |
| Indentation | 4 espaces |
| Casing types | `PascalCase` |
| Casing fonctions / variables | `camelCase` |
| Constantes statiques | `camelCase` (Swift style, pas SCREAMING_CASE) |
| Organisation interne | Sections `// MARK: - Section` pour la navigation Xcode |
| Documentation d'API | Triple-slash `///` avec balises `- Parameters`, `- Returns`, `- Throws` |
| Acronymes scientifiques | Conservés en minuscules : `aspls`, `savgol`, etc. |
| Actor isolation | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` dans le pbxproj. Le code CPU-bound utilise explicitement `Task.detached(...)`. |

Les fichiers Swift sont écrits en français pour la cohérence avec l'UI
et les commentaires existants. C'est un projet francophone assumé.

## Ajouter une fonctionnalité

### Exemple : exposer un paramètre scientifique dans l'UI

Les valeurs numériques (margin, maxSlope, lambda, tol, maxIter, freq,
etc.) sont définies dans `BatchProcessor.process(...)` et
`BatchAggregator.writeSummary(...)`. Pour les exposer à l'utilisateur :

1. Ajouter un binding au `BatchViewModel`.
2. Ajouter un contrôle dans `ContentView.swift`.
3. Passer la nouvelle valeur dans l'appel à `BatchProcessor.process`.

### Exemple : nouvelle colonne dans le récapitulatif

`BatchAggregator.writeSummary(...)` construit les colonnes par
électrode. Pour en ajouter une (ex. *Largeur à mi-hauteur*) :

1. Étendre `BatchFileResult` avec la nouvelle métrique.
2. Calculer cette métrique dans `BatchProcessor.process` (à partir du
   signal corrigé).
3. Ajouter la colonne dans `BatchAggregator.writeSummary` (entête +
   valeurs).

### Exemple : nouveau format d'export par fichier (ex. JSON)

1. **XLSXWriter** : ajouter `writeJSON(...)`.
2. **PerFileExport** : ajouter le case `.json`.
3. **BatchViewModel.runAnalysis** : nouveau `case .json`.
4. **ContentView** : ajouter une option radio.

## Mise à jour des fonctions d'analyse

`voltapeakApp` est la **source de vérité** des fonctions d'analyse.
Lorsqu'une amélioration y est apportée
(`SavitzkyGolay.swift`, `WhittakerASPLS.swift`, `SignalProcessing.swift`,
`SWVFileReader.swift`, `VoltammetryData.swift`) :

1. Copier le fichier modifié tel quel dans `voltapeak_batch/`.
2. Mettre à jour l'entête de commentaire (changer `voltapeak` →
   `voltapeak_batch`).
3. Vérifier que la sortie batch reste identique sur les jeux de
   validation ([VALIDATION.md](VALIDATION.md)).
4. Ajouter une entrée dans [CHANGELOG.md](CHANGELOG.md).

## Débugger

### Logs console Xcode

Le `BatchViewModel.runAnalysis` émet des `appendLog(...)` que
l'utilisateur voit dans la GUI, et qui apparaissent aussi en console :

```
Nettoyage du dossier de sortie...
Traitement : ESSAI1_C01.txt
Traitement : ESSAI1_C02.txt
...
Traitement terminé.
Fichiers traités : 24 / 24
Temps écoulé : 1.42 secondes.
```

Pour des détails plus fins (signal intermédiaire, baseline, etc.),
ajouter des `print(...)` dans `BatchProcessor.process`. Format
recommandé pour la comparaison avec `voltapeakApp` / Python :

```swift
print("=== aspls DEBUG (Swift) ===")
print("first5 : \(baseline.prefix(5).map { String(format: "%.6e", $0) })")
print("last5  : \(baseline.suffix(5).map { String(format: "%.6e", $0) })")
```

Visible dans la console Xcode lors du run (View → Debug Area → Show
Debug Area).

### Vérifier la parité numérique avec voltapeakApp

Les fonctions d'analyse étant reprises à l'identique, traiter un même
fichier individuel doit produire un pic strictement identique entre les
deux apps. Si ce n'est pas le cas, c'est un signe que quelque chose a
divergé dans la copie — voir [VALIDATION.md](VALIDATION.md) §
« Parité numérique avec voltapeakApp ».

## Tests

**État actuel** : aucun test unitaire automatisé. Les fonctions
d'analyse sont déjà validées dans `voltapeakApp` (bit-exact contre
Python, cf.
[voltapeakApp/VALIDATION.md](https://github.com/scadinot/voltapeakApp/blob/main/VALIDATION.md)).
La validation propre au batch est manuelle, documentée dans
[VALIDATION.md](VALIDATION.md).

Pistes pour ajouter une cible de tests :

1. **Tests algorithmiques** : priorité faible — déjà couverts par
   `voltapeakTests` côté `voltapeakApp`.
2. **Tests d'agrégation** : `BatchAggregator.writeSummary` — ordre des
   électrodes, formules `=I/F` correctement insérées.
3. **Tests de parsing** : `BatchProcessor.parseBaseAndElectrode` sur des
   cas conformes / non conformes.
4. **Tests d'intégration** : charger un mini-dossier de fixtures →
   lancer `BatchProcessor.process` sur chaque fichier → vérifier pic +
   métadonnées.
5. **Tests XLSX** : lecture-aller-retour avec ZIP / `openpyxl` (Python)
   pour vérifier la conformité OOXML.

Pour démarrer : *File* → *New* → *Target* → **Unit Testing Bundle**,
nom suggéré `voltapeak_batchTests`, framework Swift Testing ou XCTest.

## Profiling

L'asPLS est l'étape la plus coûteuse (élimination de Gauss dense
O(n³)). Pistes d'optimisation :

- Exploiter la structure pentadiagonale de `D^T·D` via un solveur de
  bandes (LAPACK `dgbsv`) — gain potentiel ~10× sur n grand.
- Vectoriser les boucles via `Accelerate` (`vDSP`, `vForce`).
- Mettre en cache `D^T·D` pour un `n` constant.

Toute optimisation doit être validée bit-exact contre la version
actuelle sur le jeu de fixtures (cf. [VALIDATION.md](VALIDATION.md))
avant merge.

## Ressources externes

- [Apple SwiftUI documentation](https://developer.apple.com/documentation/swiftui)
- [Apple Charts framework](https://developer.apple.com/documentation/charts)
- [scipy.signal documentation](https://docs.scipy.org/doc/scipy/reference/signal.html)
- [pybaselines repo](https://github.com/derb12/pybaselines)
- [Zhang et al. 2020 paper (asPLS)](https://www.tandfonline.com/doi/full/10.1080/00387010.2020.1734588)
- [`voltapeakApp`](https://github.com/scadinot/voltapeakApp) — référence canonique des fonctions d'analyse
- [`voltapeak_loopsApp`](https://github.com/scadinot/voltapeak_loopsApp) — variante batch loops/dosage hiérarchique
