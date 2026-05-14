//
//  BatchViewModel.swift
//  voltapeak_batch
//
//  Orchestrateur du traitement par lot : sélection du dossier, paramétrage,
//  exécution parallèle ou séquentielle, journal, barre de progression et
//  appel à `BatchAggregator` pour le classeur final.
//
//  Équivalent strict de `run_analysis()` côté Python (Tkinter).
//

import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class BatchViewModel {

    // MARK: - Types

    struct LogLine: Identifiable {
        enum Kind { case info, success, error }
        let id = UUID()
        let kind: Kind
        let message: String
    }

    // MARK: - État (binding UI)

    var inputFolder: URL?
    var config = SWVFileConfiguration()
    var perFileExport: PerFileExport = .none
    var parallelEnabled: Bool = true

    var isProcessing: Bool = false
    var logLines: [LogLine] = []
    var progressCurrent: Int = 0
    var progressTotal: Int = 0

    var resultsFolder: URL?
    var canOpenResults: Bool = false

    // MARK: - Actions UI

    /// Ouvre un `NSOpenPanel` pour sélectionner le dossier d'entrée.
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Sélectionnez le dossier contenant les fichiers .txt"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            inputFolder = url
        }
    }

    /// Ouvre le dossier de résultats dans le Finder.
    func openResultsFolder() {
        guard let url = resultsFolder else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Pipeline principal

    /// Lance le traitement complet (équivalent de `run_analysis()` Tkinter).
    func runAnalysis() async {
        guard let folder = inputFolder else {
            appendLog(.error, "Veuillez sélectionner un dossier valide.")
            return
        }

        isProcessing = true
        canOpenResults = false
        logLines.removeAll()
        progressCurrent = 0
        progressTotal = 0
        resultsFolder = nil

        defer { isProcessing = false }

        // 1. Dossier de sortie : <entrée> (results)
        let folderName = folder.lastPathComponent
        let outputFolder = folder.deletingLastPathComponent()
            .appendingPathComponent("\(folderName) (results)")
        do {
            try FileManager.default.createDirectory(
                at: outputFolder,
                withIntermediateDirectories: true
            )
        } catch {
            appendLog(.error, "Impossible de créer le dossier de sortie : \(error.localizedDescription)")
            return
        }

        // 2. Nettoyage des artefacts d'une exécution précédente
        appendLog(.info, "Nettoyage du dossier de sortie...")
        cleanupPreviousArtefacts(in: outputFolder)

        // 3. Énumération triée des .txt
        let txtFiles = listTxtFiles(in: folder)
        if txtFiles.isEmpty {
            appendLog(.error, "Aucun fichier .txt trouvé dans le dossier sélectionné.")
            return
        }
        progressTotal = txtFiles.count

        // Snapshot des paramètres pour les tâches concurrentes
        let configSnapshot = config
        let exportSnapshot = perFileExport

        // 4. Traitement
        let startedAt = Date()
        let collected: [BatchFileResult] = parallelEnabled
            ? await runParallel(
                txtFiles: txtFiles,
                outputFolder: outputFolder,
                config: configSnapshot,
                export: exportSnapshot
              )
            : await runSequential(
                txtFiles: txtFiles,
                outputFolder: outputFolder,
                config: configSnapshot,
                export: exportSnapshot
              )

        // 5. Classeur récapitulatif
        if !collected.isEmpty {
            do {
                let url = try BatchAggregator.writeSummary(
                    results: collected,
                    outputFolder: outputFolder,
                    folderBaseName: folderName
                )
                appendLog(.info, "Classeur récapitulatif : \(url.lastPathComponent)")
            } catch {
                appendLog(.error, "Échec écriture récapitulatif : \(error.localizedDescription)")
            }
        }

        // 6. Bilan
        let duration = Date().timeIntervalSince(startedAt)
        appendLog(.info, "")
        appendLog(
            .success,
            String(
                format: "Traitement terminé. Fichiers traités : %d / %d. Temps écoulé : %.2f s.",
                collected.count,
                txtFiles.count,
                duration
            )
        )
        resultsFolder = outputFolder
        canOpenResults = true
    }

    // MARK: - Exécution séquentielle

    private func runSequential(
        txtFiles: [URL],
        outputFolder: URL,
        config: SWVFileConfiguration,
        export: PerFileExport
    ) async -> [BatchFileResult] {
        var collected: [BatchFileResult] = []
        for file in txtFiles {
            if let result = await processOne(
                fileURL: file,
                outputFolder: outputFolder,
                config: config,
                export: export
            ) {
                collected.append(result)
            }
            progressCurrent += 1
        }
        return collected
    }

    // MARK: - Exécution parallèle

    private func runParallel(
        txtFiles: [URL],
        outputFolder: URL,
        config: SWVFileConfiguration,
        export: PerFileExport
    ) async -> [BatchFileResult] {
        let maxConcurrency = max(1, ProcessInfo.processInfo.activeProcessorCount)
        var indexed: [(index: Int, result: BatchFileResult)] = []

        await withTaskGroup(of: (Int, BatchFileResult?).self) { group in
            var nextIndex = 0
            var running = 0

            // Amorce du pool : `maxConcurrency` tâches en vol
            while nextIndex < txtFiles.count && running < maxConcurrency {
                let idx = nextIndex
                let file = txtFiles[idx]
                group.addTask {
                    let result = await self.processOne(
                        fileURL: file,
                        outputFolder: outputFolder,
                        config: config,
                        export: export
                    )
                    return (idx, result)
                }
                nextIndex += 1
                running += 1
            }

            // Drain : à chaque tâche terminée, on en lance une nouvelle
            while let (idx, result) = await group.next() {
                progressCurrent += 1
                if let result {
                    indexed.append((idx, result))
                }
                if nextIndex < txtFiles.count {
                    let i = nextIndex
                    let file = txtFiles[i]
                    group.addTask {
                        let result = await self.processOne(
                            fileURL: file,
                            outputFolder: outputFolder,
                            config: config,
                            export: export
                        )
                        return (i, result)
                    }
                    nextIndex += 1
                }
            }
        }

        // Tri par ordre d'origine pour un récapitulatif déterministe
        return indexed.sorted { $0.index < $1.index }.map(\.result)
    }

    // MARK: - Traitement d'un fichier
    //
    // L'API est MainActor. Le `Task.detached(...).value` interne libère le
    // MainActor pendant le calcul CPU-bound : plusieurs `processOne` en vol
    // s'exécutent donc en parallèle sur leurs tâches détachées respectives.
    // PNG / CSV / XLSX et journal restent sur le MainActor (sérialisé).
    private func processOne(
        fileURL: URL,
        outputFolder: URL,
        config: SWVFileConfiguration,
        export: PerFileExport
    ) async -> BatchFileResult? {
        do {
            // 1. Pipeline CPU-bound sur tâche détachée
            let outcome = try await Task.detached(priority: .userInitiated) {
                try BatchProcessor.process(fileURL: fileURL, config: config)
            }.value

            // 2. Rendu PNG (ImageRenderer requiert le MainActor)
            let pngURL = outputFolder.appendingPathComponent(
                fileURL.deletingPathExtension().lastPathComponent + ".png"
            )
            try ChartPNGRenderer.renderPNG(
                analysis: outcome.analysis,
                potentials: outcome.potentials,
                rawCurrents: outcome.rawCurrents,
                to: pngURL
            )

            // 3. Exports optionnels par fichier
            switch export {
            case .none:
                break
            case .csv:
                let csvURL = outputFolder.appendingPathComponent(
                    fileURL.deletingPathExtension().lastPathComponent + ".csv"
                )
                try BatchProcessor.writeCSV(outcome: outcome, to: csvURL)
            case .xlsx:
                let xlsxURL = outputFolder.appendingPathComponent(
                    fileURL.deletingPathExtension().lastPathComponent + ".xlsx"
                )
                try BatchProcessor.writeXLSX(outcome: outcome, to: xlsxURL)
            }

            appendLog(.success, "Traitement : \(fileURL.lastPathComponent)")
            return outcome.result

        } catch {
            appendLog(
                .error,
                "Erreur dans le fichier \(fileURL.lastPathComponent) : \(error.localizedDescription)"
            )
            return nil
        }
    }

    // MARK: - Utilitaires fichiers

    private func listTxtFiles(in folder: URL) -> [URL] {
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension.lowercased() == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func cleanupPreviousArtefacts(in folder: URL) {
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let extensions: Set<String> = ["png", "csv", "xlsx"]
        for url in urls where extensions.contains(url.pathExtension.lowercased()) {
            try? manager.removeItem(at: url)
        }
    }

    // MARK: - Journal

    private func appendLog(_ kind: LogLine.Kind, _ message: String) {
        logLines.append(LogLine(kind: kind, message: message))
    }
}
