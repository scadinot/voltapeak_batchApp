//
//  ContentView.swift
//  voltapeak_batch
//
//  Interface minimaliste reproduisant la fenêtre Tkinter de la version
//  Python : dossier d'entrée, paramètres de lecture, barre de progression,
//  journal défilant et deux boutons d'action.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = BatchViewModel()

    var body: some View {
        VStack(spacing: 12) {
            folderRow
            settingsGroup
            progressGroup
            logGroup
            actionRow
        }
        .padding(16)
        .frame(minWidth: 660, minHeight: 480)
    }

    // MARK: - Sélection de dossier

    private var folderRow: some View {
        HStack(spacing: 8) {
            Text("Dossier d'entrée :")
            Text(viewModel.inputFolder?.path ?? "—")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            Button("Parcourir") { viewModel.selectFolder() }
                .disabled(viewModel.isProcessing)
        }
    }

    // MARK: - Paramètres de lecture

    private var settingsGroup: some View {
        GroupBox("Paramètres de lecture") {
            Grid(alignment: .leadingFirstTextBaseline,
                 horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Séparateur de colonnes :")
                    Picker("", selection: $viewModel.config.columnSeparator) {
                        ForEach(SWVFileConfiguration.ColumnSeparator.allCases, id: \.self) { sep in
                            Text(sep.displayName).tag(sep)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("Séparateur décimal :")
                    Picker("", selection: $viewModel.config.decimalSeparator) {
                        ForEach(SWVFileConfiguration.DecimalSeparator.allCases, id: \.self) { sep in
                            Text(sep.displayName).tag(sep)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("Export des fichiers traités :")
                    Picker("", selection: $viewModel.perFileExport) {
                        ForEach(PerFileExport.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("Export des graphiques :")
                    Picker("", selection: $viewModel.exportGraph) {
                        Text("Ne pas exporter").tag(false)
                        Text("Exporter au format .png").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("Mode de traitement :")
                    Picker("", selection: $viewModel.parallelEnabled) {
                        Text("Multi-thread (un Task par cœur)").tag(true)
                        Text("Séquentiel").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(viewModel.isProcessing)
        }
    }

    // MARK: - Progression

    private var progressGroup: some View {
        GroupBox("Progression du traitement") {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(
                    value: Double(viewModel.progressCurrent),
                    total: Double(max(viewModel.progressTotal, 1))
                )
                if viewModel.progressTotal > 0 {
                    Text("\(viewModel.progressCurrent) / \(viewModel.progressTotal) fichier(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Journal

    private var logGroup: some View {
        GroupBox("Journal de traitement") {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.logLines) { line in
                            Text(line.message)
                                .foregroundStyle(color(for: line.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(6)
                }
                .frame(minHeight: 140)
                .onChange(of: viewModel.logLines.count) { _, _ in
                    if let last = viewModel.logLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func color(for kind: BatchViewModel.LogLine.Kind) -> Color {
        switch kind {
        case .info: return .primary
        case .success: return .primary
        case .error: return .red
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack {
            Spacer()
            Button("Ouvrir le dossier de résultats") {
                viewModel.openResultsFolder()
            }
            .disabled(!viewModel.canOpenResults)

            Button("Lancer l'analyse") {
                Task { await viewModel.runAnalysis() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.inputFolder == nil || viewModel.isProcessing)
        }
    }
}

#Preview {
    ContentView()
}
