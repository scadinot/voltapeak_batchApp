//
//  BatchAggregator.swift
//  voltapeak_batch
//
//  Construit le classeur Excel récapitulatif : une ligne par base, des colonnes
//  par électrode (Tension / Courant / Charge), avec formule Excel
//  `=Courant / Fréq` pour la charge — équivalent strict du post-traitement
//  `openpyxl` côté Python.
//

import Foundation

enum BatchAggregator {

    /// Construit et écrit le classeur agrégé.
    /// - Parameters:
    ///   - results: résultats produits par `BatchProcessor.process(...)`
    ///   - outputFolder: dossier `<entrée> (results)`
    ///   - folderBaseName: nom du dossier d'entrée (sans le suffixe « (results) »)
    ///   - frequencyHz: fréquence SWV (50 Hz par défaut)
    /// - Returns: URL du `.xlsx` écrit
    @discardableResult
    static func writeSummary(
        results: [BatchFileResult],
        outputFolder: URL,
        folderBaseName: String,
        frequencyHz: Double = 50.0
    ) throws -> URL {
        // 1. Tri stable des électrodes distinctes (ordre lexicographique : C01 < C02 < …)
        // Les fichiers hors convention `<base>_C<NN>.txt` ont une électrode vide :
        // ils contribuent une ligne `Base`/`Fréq` mais ne créent pas de colonnes
        // « sans préfixe » qui seraient ambiguës dans le récapitulatif.
        let electrodes = Array(Set(results.map(\.electrode)))
            .filter { !$0.isEmpty }
            .sorted()

        // 2. En-têtes : Base | Fréq (Hz) | <e0> - Tension | <e0> - Courant | <e0> - Charge | …
        var headers: [String] = ["Base", "Fréq (Hz)"]
        for elec in electrodes {
            headers.append("\(elec) - Tension (V)")
            headers.append("\(elec) - Courant (A)")
            headers.append("\(elec) - Charge (C)")
        }

        // 3. Regroupement par base (en préservant l'ordre d'apparition)
        var bases: [String] = []
        var byBase: [String: [String: BatchFileResult]] = [:]   // base -> electrode -> result
        for r in results {
            if byBase[r.baseName] == nil {
                bases.append(r.baseName)
                byBase[r.baseName] = [:]
            }
            byBase[r.baseName]?[r.electrode] = r
        }

        // 4. Repérer les indices de colonnes du courant et de la fréquence pour la formule
        let freqCol = XLSXWriter.columnLetter(1)     // colonne B
        var courantColForElectrode: [String: String] = [:]
        for (i, h) in headers.enumerated() {
            if h.hasSuffix(" - Courant (A)") {
                let elec = String(h.dropLast(" - Courant (A)".count))
                courantColForElectrode[elec] = XLSXWriter.columnLetter(i)
            }
        }

        // 5. Construction des lignes
        var rows: [[XLSXCell]] = []
        for (rowIdx, base) in bases.enumerated() {
            let excelRow = rowIdx + 2   // ligne 1 = headers, données dès la ligne 2
            var cells: [XLSXCell] = [
                .string(base),
                .number(frequencyHz)
            ]
            for elec in electrodes {
                if let r = byBase[base]?[elec] {
                    cells.append(.number(r.peakPotential))
                    cells.append(.number(r.peakCurrent))
                    if let courantCol = courantColForElectrode[elec] {
                        // Formule Excel : =<courantCol><row>/<freqCol><row>
                        cells.append(.formula("=\(courantCol)\(excelRow)/\(freqCol)\(excelRow)"))
                    } else {
                        cells.append(.empty)
                    }
                } else {
                    cells.append(.empty)
                    cells.append(.empty)
                    cells.append(.empty)
                }
            }
            rows.append(cells)
        }

        // 6. Génération du XLSX
        let data = XLSXWriter.writeSummary(headers: headers, rows: rows)

        let outURL = outputFolder.appendingPathComponent("\(folderBaseName).xlsx")
        try data.write(to: outURL, options: .atomic)
        return outURL
    }
}
