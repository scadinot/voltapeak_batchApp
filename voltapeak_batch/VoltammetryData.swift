//
//  VoltammetryData.swift
//  voltapeak_batch
//
//  Modèles de données pour l'analyse SWV (repris à l'identique de voltapeak).
//

import Foundation

/// Point de données d'un voltampérogramme (Potentiel, Courant)
struct VoltammetryPoint: Identifiable {
    let id = UUID()
    let potential: Double  // Potentiel en volts
    let current: Double    // Courant en ampères
}

/// Résultats de l'analyse d'un voltampérogramme SWV
struct VoltammetryAnalysis {
    let rawData: [VoltammetryPoint]
    let smoothedSignal: [Double]
    let baseline: [Double]
    let correctedSignal: [Double]
    let peakPotential: Double
    let peakCurrent: Double
    let fileName: String
}

/// Configuration de lecture de fichier SWV
struct SWVFileConfiguration {
    enum ColumnSeparator: String, CaseIterable {
        case tab = "\t"
        case comma = ","
        case semicolon = ";"
        case space = " "

        var displayName: String {
            switch self {
            case .tab: return "Tabulation"
            case .comma: return "Virgule"
            case .semicolon: return "Point-virgule"
            case .space: return "Espace"
            }
        }
    }

    enum DecimalSeparator: String, CaseIterable {
        case point = "."
        case comma = ","

        var displayName: String {
            switch self {
            case .point: return "Point"
            case .comma: return "Virgule"
            }
        }
    }

    var columnSeparator: ColumnSeparator = .tab
    var decimalSeparator: DecimalSeparator = .point
    var encoding: String.Encoding = .isoLatin1
}

/// Option d'export par fichier (réplique de l'option Tkinter de la version Python)
enum PerFileExport: Int, CaseIterable, Identifiable {
    case none = 0
    case csv = 1
    case xlsx = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Ne pas exporter"
        case .csv: return "Exporter au format .CSV"
        case .xlsx: return "Exporter au format Excel"
        }
    }
}

/// Résultat de traitement d'un fichier individuel pour l'agrégation multi-électrodes.
///
/// La convention de nommage `<base>_C<NN>.txt` est appliquée par le pipeline batch ;
/// si le nom ne suit pas la convention, `electrode` est laissé vide et `base`
/// reprend le nom du fichier complet.
struct BatchFileResult {
    let baseName: String
    let electrode: String          // ex. "C01", ou "" si pas de convention
    let peakPotential: Double      // V
    let peakCurrent: Double        // A
}
