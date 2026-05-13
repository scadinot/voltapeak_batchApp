# Développement

Guide à l'attention des contributeurs souhaitant faire évoluer
`voltapeak_batchApp`.

## Environnement requis

- **macOS 26.1** ou supérieur.
- **Xcode 26.2** ou supérieur (`objectVersion = 77` dans `project.pbxproj`,
  `MACOSX_DEPLOYMENT_TARGET = 26.1`).
- Pas d'outil de build supplémentaire : pas de SPM, pas de CocoaPods.

## Cloner et ouvrir le projet

```bash
git clone https://github.com/scadinot/voltapeak_batchApp.git
cd voltapeak_batchApp
open voltapeak_batch.xcodeproj
```

Le `PBXFileSystemSynchronizedRootGroup` (Xcode 26+) découvre automatiquement
les fichiers Swift du dossier `voltapeak_batch/` — pas besoin d'ajouter
manuellement chaque nouveau fichier à la cible.

## Conventions de code

- **Swift 5+, MainActor par défaut** : `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor`. Le code CPU-bound doit explicitement `Task.detached(...)`.
- **Aucune dépendance externe** : pas de SPM, pas de CocoaPods, pas de
  Carthage. Tout est implémenté à partir des spécifications mathématiques.
- **Commentaires** : les fichiers d'algorithmes sont **identiques** à ceux
  de `voltapeakApp`. Toute modification doit être propagée des deux côtés
  ou justifiée par une référence à `ALGORITHMS.md`.
- **Langue** : commentaires et UI **en français** (cohérence avec
  `voltapeak_batch` Python). Les noms de symboles restent en anglais.

## Lancer l'application en débogage

1. `Cmd+R` dans Xcode → l'application se lance et le débogueur LLDB est attaché.
2. Le `print(...)` dans le pipeline (le cas échéant) apparaît dans la console
   Xcode.
3. Aucun App Sandbox : l'app peut lire / écrire librement dans le dossier
   choisi par l'utilisateur (parité avec la version Python). À adapter si
   distribution App Store.

## Ajouter des tests

Le projet n'inclut pas (encore) de cible de tests. Pour en ajouter :

1. *File* → *New* → *Target* → **Unit Testing Bundle**.
2. Cible existante : `voltapeak_batch`. Nom suggéré : `voltapeak_batchTests`.
3. Exemples de tests à privilégier :
   - validation pixel-perfect de `SavitzkyGolay.filter` contre `savgol_coeffs` ;
   - validation des paramètres `WhittakerASPLS.aspls` sur jeux de données fixes ;
   - `BatchProcessor.parseBaseAndElectrode` (cas conformes / non conformes) ;
   - `BatchAggregator.writeSummary` : ordre des électrodes, formules
     `=I/F` correctement insérées ;
   - `XLSXWriter.writeSummary` : lecture-aller-retour avec ZIP / openpyxl
     (Python) pour vérifier la conformité OOXML.

## Mise à jour des fonctions d'analyse

Lorsqu'une amélioration est apportée aux algorithmes côté
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp) :

1. Copier le fichier modifié tel quel dans `voltapeak_batch/`.
2. Mettre à jour l'entête de commentaire (changer `voltapeak` →
   `voltapeak_batch`).
3. Vérifier que la sortie batch reste identique sur les jeux de validation
   ([VALIDATION.md](VALIDATION.md)).
4. Ajouter une entrée dans [CHANGELOG.md](CHANGELOG.md).

## Mise à jour des paramètres

Les valeurs numériques (margin, maxSlope, lambda, tol, maxIter, freq, etc.)
sont définies dans `BatchProcessor.process(...)` et `BatchAggregator.writeSummary(...)`.
Pour les exposer à l'utilisateur, ajouter des bindings au `BatchViewModel`
et des contrôles dans `ContentView.swift`.

## Profiling

L'asPLS est l'étape la plus coûteuse (élimination de Gauss dense O(n³)).
Pistes d'optimisation :

- exploiter la structure pentadiagonale de `D^T D` via un solveur de bandes
  (LAPACK `dgbsv`) — gain potentiel ~10× sur n grand ;
- vectoriser les boucles via `Accelerate` (`vDSP`, `vForce`) ;
- mettre en cache `D^T D` pour un n constant (déjà pratiqué dans une
  campagne).

## Git workflow

- Branche par défaut : `main`.
- Branches de travail : `claude/<feature>` (compatible Claude Code).
- Commits courts et descriptifs en français.
- Pas de PR créée automatiquement : la branche est poussée, la PR est ouverte
  manuellement.
