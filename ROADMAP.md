# ROADMAP — voltapeak_batchApp

Évolutions planifiées, regroupées en **vagues de priorité**. L'ordre des vagues est indicatif : un item peut être avancé si une demande utilisateur le rend prioritaire. Aucun item n'a de date d'engagement — le projet reste en usage interne GROUPE TRACE et avance par opportunité.

> Cette feuille de route est partagée entre les trois applications [`voltapeakApp`](https://github.com/scadinot/voltapeakApp), [`voltapeak_batchApp`](https://github.com/scadinot/voltapeak_batchApp) et [`voltapeak_loopsApp`](https://github.com/scadinot/voltapeak_loopsApp) : les items marqués **(commun)** s'appliquent aux trois et bénéficieront idéalement de la même implémentation (cf. Vague 6 — mutualisation du noyau scientifique dans un package `VoltapeakCore`).

---

## Table des matières

1. [Vague 1 — Hygiène & robustesse](#vague-1--hygiène--robustesse)
2. [Vague 2 — Configurabilité](#vague-2--configurabilité)
3. [Vague 3 — Fonctionnalités utilisateur](#vague-3--fonctionnalités-utilisateur)
4. [Vague 4 — Qualité logicielle](#vague-4--qualité-logicielle)
5. [Vague 5 — Distribution](#vague-5--distribution)
6. [Vague 6 — Extensions scientifiques](#vague-6--extensions-scientifiques)
7. [Contribuer](#contribuer)

---

## Vague 1 — Hygiène & robustesse

Items qui éliminent des pièges connus ou des limitations documentées dans le [`README`](README.md).

- **Encodage configurable** *(commun)* — l'encodage de lecture est aujourd'hui figé à `ISO Latin-1`. Exposer dans l'UI une bascule `Latin-1 / UTF-8 / UTF-8 BOM`, avec auto-détection optionnelle (heuristique BOM + fallback Latin-1).
- **Support du pic anodique** *(commun)* — `SWVFileReader.processData` inverse systématiquement le signe du courant. Ajouter dans la GUI une case à cocher *« Pic en courant positif (anodique) »* qui désactive l'inversion.
- **Affinage des erreurs `FileError`** *(commun)* — enrichir les `LocalizedError` (`fileNotFound`, `invalidFormat`, `insufficientData`, `tooManyPoints`, `permissionDenied`, `encodingError`) avec des suggestions actionnables dans le bouton *Aide* de l'alerte (lien direct vers la section *Dépannage* du README).
- **Validation préalable de la convention de nommage** *(spécifique batch)* — avant lancement, lister dans le journal les fichiers qui ne respectent pas `<base>_C<NN>.txt` plutôt que de les agréger silencieusement sous une colonne d'électrode vide.

---

## Vague 2 — Configurabilité

Exposer dans l'UI ce qui est aujourd'hui codé en dur.

- **Exposition des hyperparamètres** *(commun)* — section « Paramètres avancés » repliable, avec sliders / `Stepper` SwiftUI pour :
  - `windowLength` (Savitzky-Golay)
  - `polyorder`
  - `marginRatio`
  - `maxSlope`
  - `exclusionWidthRatio`
  - `lambdaFactor`
- **Fréquence SWV configurable** *(spécifique batch)* — la valeur `50 Hz` injectée dans le récap Excel est codée en dur dans `BatchAggregator`. Ajouter un `TextField` numérique dans la GUI et propager la valeur dans la formule `=<courantCol><row> / <freqCol><row>`.
- **Profils de paramètres** *(commun)* — sauvegarde / rechargement de jeux de paramètres nommés (JSON dans `~/Library/Application Support/voltapeak/profiles/`), pour basculer rapidement entre différentes campagnes.

---

## Vague 3 — Fonctionnalités utilisateur

- **Bouton « Annuler »** — interrompre proprement un lot en cours via la `Task` racine du `TaskGroup`, vider la file de résultats, restaurer la barre de progression et journaliser l'interruption.
- **Statistiques par électrode** — sur le récap Excel, ajouter en bas du tableau une ligne de moyenne et d'écart-type par électrode pour les pics corrigés (Tension, Courant, Charge).
- **Filtre de noms à inclure / exclure** — champ texte (glob) pour ne traiter qu'un sous-ensemble du dossier, sans déplacer les fichiers.
- **Récap au format CSV en plus de XLSX** — option pour produire un récap CSV en parallèle, utile pour intégration dans des chaînes d'analyse tierces.

---

## Vague 4 — Qualité logicielle

- **Tests Swift `Testing` étendus** *(commun)* — `voltapeakApp` héberge déjà la suite de référence (`SavitzkyGolayTests`, `WhittakerASPLSTests`, `SignalProcessingTests`). Ajouter ici une target de tests couvrant `BatchProcessor` (pipeline end-to-end sur fichier de référence), `BatchAggregator` (mise en forme du récap + formule Excel), et `parseBaseAndElectrode` (regex sur cas limites : casse, séparateurs, motifs invalides).
- **CI multi-repo unifiée** *(commun)* — étendre le workflow `swift.yml` (build + test + analyze) à `voltapeak_batchApp` et `voltapeak_loopsApp` ; ajouter `swift-format` ou `swiftlint` en pré-commit + CI.
- **App Sandbox réactivée** *(commun)* — actuellement `ENABLE_APP_SANDBOX = NO`. Repasser à `YES` avec entitlements `com.apple.security.files.user-selected.read-write` + `com.apple.security.files.bookmarks.app-scope` ; tester la régression sur l'accès au dossier `<entrée> (results)`.
- **Tests UI XCUITest** *(commun)* — vérifier que le pipeline end-to-end (drag-drop d'un fichier de référence → affichage du graphe ou lancement du lot → présence du XLSX agrégé) ne régresse pas.

---

## Vague 5 — Distribution

- **Signature Developer ID + notarisation** *(commun)* — actuellement `CODE_SIGN_IDENTITY="-"` (ad-hoc). Configurer la signature Developer ID Application + agrafer la notarisation Apple dans le workflow `release.yml`. Élimine le clic droit → *Ouvrir* au premier lancement.
- **Distribution Mac App Store** *(commun)* — pré-requis : Sandbox réactivée (Vague 4) + entitlements minimaux. Ajouter un schéma de release App Store séparé.
- **Mode CLI** *(commun)* — target Xcode `voltapeak_batch-cli` (executable) qui prend un dossier en argument et produit les exports + XLSX agrégé sans afficher de fenêtre. Utile pour scripts d'intégration externes.
- **Découpage en SwiftPM modules** *(commun)* — créer un package `VoltapeakCore` partagé (cf. Vague 6) et plusieurs targets dans chaque app (`...Algorithms`, `...IO`, `...UI`). Pré-requis pour la mutualisation.

---

## Vague 6 — Extensions scientifiques

- **Mutualisation `VoltapeakCore`** *(commun)* — extraire les implémentations actuellement dupliquées entre les 3 apps (`SavitzkyGolay`, `WhittakerASPLS`, `SignalProcessing`, `SWVFileReader`, `XLSXWriter` / `ZIPStore` / `XLSXBoilerplate`, `VoltammetryData`) dans un Swift Package partagé `VoltapeakCore`. Élimine la duplication actuelle (3 copies à maintenir manuellement) et garantit que les correctifs scientifiques se propagent automatiquement.
- **Détection multi-pics** *(commun)* — repérer plusieurs maxima locaux significatifs et tous les annoter, au lieu du seul maximum global.
- **Métriques de qualité du fit** *(commun)* — afficher SNR, résidus baseline (RMSE), FWHM du pic dans l'UI / exports, pour qualifier objectivement la détection.
- **Support d'autres techniques voltammétriques** *(commun)* — DPV (*Differential Pulse Voltammetry*), CV (*Cyclic Voltammetry*) : pipelines adaptés mais réutilisant le noyau de lissage / baseline.

---

## Contribuer

- Pour proposer une évolution non listée : ouvrir une *issue* sur le dépôt avec le label `enhancement`.
- Pour signaler un bug : ouvrir une *issue* avec le label `bug` et joindre un fichier `.txt` reproductible si possible.
- Les contributions externes (pull requests) sont les bienvenues — préférer une discussion préalable en issue pour les changements architecturaux.
