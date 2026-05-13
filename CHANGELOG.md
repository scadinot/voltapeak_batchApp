# Changelog

Toutes les modifications notables de `voltapeak_batchApp` sont listées ici.
Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le
projet utilise [Semantic Versioning](https://semver.org/lang/fr/).

## [1.0.0] — 2026-05-13

### Première version — conversion Swift macOS de `voltapeak_batch` (Python)

#### Ajouté

- **Application macOS native** (Swift / SwiftUI) reproduisant fidèlement la
  fenêtre Tkinter de la version Python :
  - sélecteur de dossier d'entrée (`NSOpenPanel`) ;
  - paramètres de lecture : séparateur de colonnes (`\t` / `,` / `;` / espace),
    séparateur décimal (`.` / `,`), encodage ISO Latin-1 ;
  - option d'export par fichier : *Aucun* / *CSV* / *Excel* ;
  - commutateur **traitement parallèle** (activé par défaut) ;
  - barre de progression et journal défilant avec coloration d'erreur en rouge ;
  - bouton **Ouvrir le dossier de résultats** activé en fin de traitement.

- **Pipeline d'analyse** (par fichier) :
  - lecture (`SWVFileReader.readFile`) ;
  - tri + inversion du signe (`SWVFileReader.processData`) ;
  - lissage Savitzky-Golay scipy-exact (`SavitzkyGolay.filter`, window=11, order=2) ;
  - détection de pic préliminaire (`SignalProcessing.detectPeak`, margin=10 %, maxSlope=500) ;
  - baseline asPLS Zhang 2020 (`WhittakerASPLS.aspls`, lam=1e3·n², tol=1e-2,
    maxIter=25, exclusion 3 %) ;
  - signal corrigé = lissé − baseline ;
  - re-détection du pic sur le signal corrigé ;
  - rendu PNG haute résolution (`ChartPNGRenderer`, `ImageRenderer` SwiftUI Charts).

- **Sorties** :
  - un `.png` par fichier (toujours), 5 courbes superposées + marqueur de pic ;
  - un `.csv` ou `.xlsx` optionnel par fichier ;
  - un classeur Excel récapitulatif `<dossier>.xlsx` agrégé par base, avec
    colonnes par électrode et formule Excel `=Courant / Fréq` pour la charge
    (fréquence par défaut 50 Hz).

- **Parallélisme** : Swift Concurrency (`TaskGroup` à fenêtre glissante),
  concurrence = `ProcessInfo.processInfo.activeProcessorCount`. Mode
  séquentiel disponible.

- **Aucune dépendance externe** : tous les algorithmes scientifiques en pur
  Swift, mini-ZIP store-only + XML OOXML pour `.xlsx`.

- **Documentation** : `README.md`, `ARCHITECTURE.md`, `ALGORITHMS.md`,
  `CHANGELOG.md`, `DEVELOPMENT.md`, `DISTRIBUTION.md`, `VALIDATION.md`.

#### Notes de validation

Les fonctions d'analyse (`SWVFileReader`, `SavitzkyGolay`, `SignalProcessing`,
`WhittakerASPLS`) sont **reprises à l'identique** de
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp), version déjà
validée à la 6ᵉ décimale par rapport à `scipy` / `pybaselines`. Voir
[VALIDATION.md](VALIDATION.md) pour la procédure de validation batch.
