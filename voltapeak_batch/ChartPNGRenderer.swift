//
//  ChartPNGRenderer.swift
//  voltapeak_batch
//
//  Rendu offscreen d'un voltampérogramme en PNG, équivalent de
//  `plotSignalAnalysis` (matplotlib) côté Python.
//
//  Couleurs alignées sur matplotlib tab10 pour parité visuelle.
//

import SwiftUI
import Charts
import AppKit

enum ChartPNGRenderer {

    /// Trame le voltampérogramme complet (5 courbes + marqueur de pic) en PNG
    /// haute résolution (≈ 3000×1800 px) écrit à l'URL fournie.
    @MainActor
    static func renderPNG(
        analysis: VoltammetryAnalysis,
        potentials: [Double],
        rawCurrents: [Double],
        to url: URL
    ) throws {
        let view = VoltammogramExportChart(
            analysis: analysis,
            potentials: potentials,
            rawCurrents: rawCurrents
        )
        .frame(width: 1000, height: 600)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0   // ≈ 300 dpi sur l'écran de référence

        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw RenderError.failed
        }

        try pngData.write(to: url, options: .atomic)
    }

    enum RenderError: LocalizedError {
        case failed
        var errorDescription: String? { "Échec du rendu PNG du graphique." }
    }
}

/// Vue offscreen du voltampérogramme — utilisée uniquement pour l'export PNG.
private struct VoltammogramExportChart: View {
    let analysis: VoltammetryAnalysis
    let potentials: [Double]
    let rawCurrents: [Double]

    // matplotlib tab10
    private static let mplBlue    = Color(red: 0.122, green: 0.467, blue: 0.706)
    private static let mplOrange  = Color(red: 1.000, green: 0.498, blue: 0.055)
    private static let mplGreen   = Color(red: 0.173, green: 0.627, blue: 0.173)
    private static let mplRed     = Color(red: 0.839, green: 0.153, blue: 0.157)
    private static let mplMagenta = Color(red: 1.0,   green: 0.0,   blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Correction de baseline : \(analysis.fileName)")
                .font(.headline)

            chartView

            legendView
                .font(.caption)
        }
        .padding(16)
        .background(Color.white)
    }

    private var chartView: some View {
        let xMin = potentials.min() ?? 0
        let xMax = potentials.max() ?? 1
        let allY = rawCurrents + analysis.smoothedSignal + analysis.baseline + analysis.correctedSignal
        let yMin = (allY.min() ?? 0)
        let yMax = (allY.max() ?? 1)
        let yPad = (yMax - yMin) * 0.05

        return Chart {
            // Signal brut (bleu α=0.5)
            ForEach(potentials.indices, id: \.self) { i in
                LineMark(
                    x: .value("Potentiel", potentials[i]),
                    y: .value("Courant", rawCurrents[i]),
                    series: .value("Série", "brut")
                )
                .foregroundStyle(Self.mplBlue.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 0.8))
            }

            // Signal lissé (orange)
            ForEach(potentials.indices, id: \.self) { i in
                LineMark(
                    x: .value("Potentiel", potentials[i]),
                    y: .value("Courant", analysis.smoothedSignal[i]),
                    series: .value("Série", "lissé")
                )
                .foregroundStyle(Self.mplOrange)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            // Baseline (vert dashed)
            ForEach(potentials.indices, id: \.self) { i in
                LineMark(
                    x: .value("Potentiel", potentials[i]),
                    y: .value("Courant", analysis.baseline[i]),
                    series: .value("Série", "baseline")
                )
                .foregroundStyle(Self.mplGreen)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }

            // Signal corrigé (rouge)
            ForEach(potentials.indices, id: \.self) { i in
                LineMark(
                    x: .value("Potentiel", potentials[i]),
                    y: .value("Courant", analysis.correctedSignal[i]),
                    series: .value("Série", "corrigé")
                )
                .foregroundStyle(Self.mplRed)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Ligne verticale au pic
            RuleMark(x: .value("Pic", analysis.peakPotential))
                .foregroundStyle(Self.mplMagenta.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // Marqueur du pic
            PointMark(
                x: .value("Potentiel", analysis.peakPotential),
                y: .value("Courant", analysis.peakCurrent)
            )
            .foregroundStyle(Self.mplMagenta)
            .symbolSize(80)
        }
        .chartXScale(domain: xMin...xMax)
        .chartYScale(domain: (yMin - yPad)...(yMax + yPad))
        .chartXAxisLabel("Potentiel (V)")
        .chartYAxisLabel("Courant (A)")
    }

    private var legendView: some View {
        HStack(spacing: 16) {
            LegendDot(color: Self.mplBlue.opacity(0.5), label: "Signal brut")
            LegendDot(color: Self.mplOrange, label: "Signal lissé")
            LegendDot(color: Self.mplGreen, label: "Baseline (asPLS)", dashed: true)
            LegendDot(color: Self.mplRed, label: "Signal corrigé")
            LegendDot(
                color: Self.mplMagenta,
                label: String(
                    format: "Pic à %.3f V (%.3f mA)",
                    analysis.peakPotential,
                    analysis.peakCurrent * 1e3
                ),
                isPoint: true
            )
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var dashed: Bool = false
    var isPoint: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if isPoint {
                Circle().fill(color).frame(width: 8, height: 8)
            } else if dashed {
                Rectangle()
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    .frame(width: 20, height: 2)
            } else {
                Rectangle().fill(color).frame(width: 20, height: 2)
            }
            Text(label)
        }
    }
}
