//
//  BatchProcessor.swift
//  voltapeak_batch
//
//  Pipeline complet appliqué à UN fichier `.txt` SWV, équivalent strict de
//  `processSignalFile` (voltapeak_batch/__main__.py côté Python) et de
//  `VoltapeakViewModel.analyzeFile(at:)` côté voltapeakApp.
//

import Foundation

enum BatchProcessor {

    struct Outcome {
        let result: BatchFileResult         // ligne du récapitulatif
        let analysis: VoltammetryAnalysis   // pour PNG / CSV / XLSX par fichier
        let potentials: [Double]            // série triée
        let rawCurrents: [Double]           // série triée + signe inversé
    }

    /// Exécute la chaîne complète sur un fichier.
    ///
    /// Étapes (cf. `processSignalFile` Python) :
    /// 1. lecture du fichier
    /// 2. nettoyage + tri + inversion du signe
    /// 3. Savitzky-Golay (window=11, order=2)
    /// 4. détection de pic préliminaire (margin=10 %, maxSlope=500)
    /// 5. asPLS (lam = 1e3·n², exclusion 3 %, tol=1e-2, maxIter=25)
    /// 6. signal corrigé = lissé − baseline
    /// 7. re-détection du pic (= valeur retenue)
    /// 8. parsing `<base>_C<NN>.txt`
    static func process(
        fileURL: URL,
        config: SWVFileConfiguration
    ) throws -> Outcome {
        // 1. Lecture
        let rawPoints = try SWVFileReader.readFile(at: fileURL, config: config)

        // 2. Tri + inversion
        let (potentials, currents) = SWVFileReader.processData(rawPoints)

        // 3. Lissage Savitzky-Golay
        let smoothed = SavitzkyGolay.filter(currents, windowLength: 11, polynomialOrder: 2)

        // 4. Détection de pic brut (pour positionner la fenêtre d'exclusion asPLS)
        let (peakPotential, _) = SignalProcessing.detectPeak(
            signal: smoothed,
            potentials: potentials,
            marginRatio: 0.10,
            maxSlope: 500
        )

        // 5. Baseline asPLS — paramètres identiques à __main__.py
        let n = smoothed.count
        let lambdaFactor = 1e3
        let lam = lambdaFactor * Double(n * n)

        let exclusionWidthRatio = 0.03
        let potentialRange = potentials.last! - potentials.first!
        let exclusionWidth = exclusionWidthRatio * potentialRange
        let exclusionMin = peakPotential - exclusionWidth
        let exclusionMax = peakPotential + exclusionWidth

        var initialWeights = [Double](repeating: 1.0, count: n)
        for i in 0..<n {
            if potentials[i] > exclusionMin && potentials[i] < exclusionMax {
                initialWeights[i] = 0.001
            }
        }

        let baseline = WhittakerASPLS.aspls(
            y: smoothed,
            lam: lam,
            diffOrder: 2,
            maxIter: 25,
            tol: 1e-2,
            weights: initialWeights
        )

        // 6. Signal corrigé
        let corrected = zip(smoothed, baseline).map { $0 - $1 }

        // 7. Détection finale du pic
        let (correctedPeakPotential, correctedPeakCurrent) = SignalProcessing.detectPeak(
            signal: corrected,
            potentials: potentials,
            marginRatio: 0.10,
            maxSlope: 500
        )

        let analysis = VoltammetryAnalysis(
            rawData: rawPoints,
            smoothedSignal: smoothed,
            baseline: baseline,
            correctedSignal: corrected,
            peakPotential: correctedPeakPotential,
            peakCurrent: correctedPeakCurrent,
            fileName: fileURL.lastPathComponent
        )

        // 8. Extraction `<base>_C<NN>.txt`
        let fileName = fileURL.lastPathComponent
        let (base, electrode) = parseBaseAndElectrode(fileName: fileName)

        let result = BatchFileResult(
            baseName: base,
            electrode: electrode,
            peakPotential: correctedPeakPotential,
            peakCurrent: correctedPeakCurrent
        )

        return Outcome(
            result: result,
            analysis: analysis,
            potentials: potentials,
            rawCurrents: currents
        )
    }

    // MARK: - Outputs par fichier

    /// Écrit un CSV à 4 colonnes (équiv. export Python `to_csv`).
    static func writeCSV(outcome: Outcome, to url: URL) throws {
        let analysis = outcome.analysis
        let potentials = outcome.potentials
        let currents = outcome.rawCurrents

        var csv = "Potential,Current,SignalLisse,SignalCorrigé\n"
        for i in 0..<potentials.count {
            // Python exporte les courants déjà inversés (cleaned_df["Current"])
            csv += String(
                format: "%.9g,%.9g,%.9g,%.9g\n",
                potentials[i],
                currents[i],
                analysis.smoothedSignal[i],
                analysis.correctedSignal[i]
            )
        }
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Écrit un XLSX à 5 colonnes (équiv. export Python `to_excel`).
    static func writeXLSX(outcome: Outcome, to url: URL) throws {
        let data = XLSXWriter.write(
            analysis: outcome.analysis,
            potentials: outcome.potentials,
            rawCurrents: outcome.rawCurrents
        )
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Parsing du nom de fichier

    /// Reproduit la regex Python `(.+)_C(\d{2})\.txt`.
    /// - Si le nom correspond : retourne (base, "C<NN>")
    /// - Sinon : (nom complet, "")
    static func parseBaseAndElectrode(fileName: String) -> (base: String, electrode: String) {
        let pattern = #"^(.+)_C(\d{2})\.txt$"#
        let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: fileName, range: range),
              match.numberOfRanges == 3,
              let baseRange = Range(match.range(at: 1), in: fileName),
              let elecRange = Range(match.range(at: 2), in: fileName)
        else {
            return (fileName, "")
        }
        return (String(fileName[baseRange]), "C\(fileName[elecRange])")
    }
}
