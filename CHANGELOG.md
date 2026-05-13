# Changelog

Toutes les modifications notables de `voltapeak_batchApp` sont listées
ici. Le format suit
[Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et la
numérotation respecte
[Semantic Versioning](https://semver.org/lang/fr/).

Pour le contexte famille `voltapeak*`, voir les CHANGELOG des dépôts
frères :
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp/blob/main/CHANGELOG.md),
[`voltapeak_loopsApp`](https://github.com/scadinot/voltapeak_loopsApp/blob/main/CHANGELOG.md).

## [1.0.0] — 2026-05-13 — Conversion Swift macOS de `voltapeak_batch`

Première version de `voltapeak_batchApp` : conversion Swift macOS native
de
[`voltapeak_batch`](https://github.com/scadinot/voltapeak_batch)
(Python / Tkinter). Les fonctions d'analyse sont **reprises à
l'identique** de
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp), version déjà
validée bit-exact à la 6ᵉ décimale contre la référence Python.

### Ajouté

- **Application macOS native** (Swift / SwiftUI) reproduisant fidèlement
  la fenêtre Tkinter de la version Python :
  - sélecteur de dossier d'entrée (`NSOpenPanel`) ;
  - paramètres de lecture : séparateur de colonnes
    (`\t` / `,` / `;` / espace), séparateur décimal (`.` / `,`),
    encodage ISO Latin-1 ;
  - option d'export par fichier : *Aucun* / *CSV* / *Excel* ;
  - commutateur **traitement parallèle** (activé par défaut) ;
  - barre de progression et journal défilant avec coloration d'erreur
    en rouge ;
  - bouton **Ouvrir le dossier de résultats** activé en fin de
    traitement.

- **Pipeline d'analyse** (par fichier) :
  - lecture (`SWVFileReader.readFile`) ;
  - tri + inversion du signe (`SWVFileReader.processData`) ;
  - lissage Savitzky-Golay scipy-exact (`SavitzkyGolay.filter`,
    window=11, order=2) ;
  - détection de pic préliminaire (`SignalProcessing.detectPeak`,
    margin=10 %, maxSlope=500) ;
  - baseline asPLS Zhang 2020 (`WhittakerASPLS.aspls`, `lam=1e3·n²`,
    `tol=1e-2`, `maxIter=25`, exclusion 3 %) ;
  - signal corrigé = lissé − baseline ;
  - re-détection du pic sur le signal corrigé ;
  - rendu PNG haute résolution (`ChartPNGRenderer`, `ImageRenderer`
    SwiftUI Charts).

- **Sorties** :
  - un `.png` par fichier (toujours), 5 courbes superposées + marqueur
    de pic ;
  - un `.csv` ou `.xlsx` optionnel par fichier ;
  - un classeur Excel récapitulatif `<dossier>.xlsx` agrégé par base,
    avec colonnes par électrode et formule Excel `=Courant / Fréq` pour
    la charge (fréquence par défaut 50 Hz).

- **Parallélisme** : Swift Concurrency (`TaskGroup` à fenêtre
  glissante), concurrence =
  `ProcessInfo.processInfo.activeProcessorCount`. Mode séquentiel
  disponible.

- **Aucune dépendance externe** : tous les algorithmes scientifiques en
  pur Swift, mini-ZIP store-only + XML OOXML pour `.xlsx`.

- **Documentation** : `README.md`, `ARCHITECTURE.md`, `ALGORITHMS.md`,
  `CHANGELOG.md`, `DEVELOPMENT.md`, `DISTRIBUTION.md`, `VALIDATION.md`.

### Choix de conception

- **Fonctions d'analyse importées sans modification** depuis
  [`voltapeakApp`](https://github.com/scadinot/voltapeakApp) : mêmes
  signatures, mêmes noms (`SavitzkyGolay.filter`,
  `WhittakerASPLS.aspls`, `SignalProcessing.detectPeak`,
  `SWVFileReader`, `VoltammetryData`). La parité numérique avec la
  référence Python en découle automatiquement.
- **Pipeline pur compute + I/O ViewModel** : `BatchProcessor.process`
  ne touche pas au disque autrement que pour lire le `.txt` d'entrée ;
  les écritures (PNG, CSV, XLSX) sont déléguées au `BatchViewModel` sur
  le MainActor.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** dans le pbxproj : le
  code CPU-bound utilise explicitement `Task.detached(...)` pour ne pas
  bloquer l'UI.
- **App Sandbox désactivé** : lecture/écriture libre du dossier de
  travail pour la parité avec la version Python. Signature ad-hoc
  (`CODE_SIGN_IDENTITY="-"`).

### Compatibilité

- macOS 26.1+ requis.
- Xcode 26+ pour builder (`objectVersion = 77`).
- Architecture cible : Apple Silicon (`arm64`) uniquement — macOS 26
  (Tahoe) n'étant plus disponible sur Mac Intel, le binaire n'a pas de
  tranche `x86_64` utile.

### Notes de validation

Les fonctions d'analyse (`SWVFileReader`, `SavitzkyGolay`,
`SignalProcessing`, `WhittakerASPLS`) sont **reprises à l'identique** de
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp), version déjà
validée à la 6ᵉ décimale par rapport à `scipy` / `pybaselines` — cf.
[`voltapeakApp/VALIDATION.md`](https://github.com/scadinot/voltapeakApp/blob/main/VALIDATION.md).
Voir [VALIDATION.md](VALIDATION.md) pour la procédure de validation
propre au batch (agrégation multi-électrodes, parsing, cohérence
séquentiel vs parallèle).

### Crédits

- Script Python source :
  [`scadinot/voltapeak_batch`](https://github.com/scadinot/voltapeak_batch).
- App macOS mono-fichier de référence pour les fonctions d'analyse :
  [`scadinot/voltapeakApp`](https://github.com/scadinot/voltapeakApp).
