//
//  SWVFileReader.swift
//  voltapeak_batch
//
//  Lecture des fichiers SWV (repris à l'identique de voltapeak).
//

import Foundation

/// Lecteur de fichiers de voltampérométrie SWV
enum SWVFileReader {

    enum FileError: LocalizedError {
        case fileNotFound
        case invalidFormat
        case insufficientData
        case permissionDenied
        case encodingError

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Fichier introuvable"
            case .invalidFormat:
                return "Format de fichier invalide. Vérifiez que c'est un fichier texte avec deux colonnes (Potentiel, Courant)."
            case .insufficientData:
                return "Données insuffisantes (moins de 5 points). Le fichier doit contenir au moins 5 lignes de données."
            case .permissionDenied:
                return "Permissions insuffisantes pour accéder au fichier. Vérifiez les paramètres App Sandbox dans Xcode."
            case .encodingError:
                return "Erreur d'encodage. Le fichier doit être encodé en ISO Latin-1."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .permissionDenied:
                return "Dans Xcode : Signing & Capabilities > App Sandbox > User Selected File (Read Only)"
            case .invalidFormat:
                return "Le fichier doit avoir le format :\nPotentiel    Courant\n-0.500    -1.234e-06\n..."
            case .encodingError:
                return "Essayez de réenregistrer le fichier avec l'encodage ISO Latin-1"
            default:
                return nil
            }
        }
    }

    /// Lit un fichier SWV et retourne les données brutes
    /// - Parameters:
    ///   - url: URL du fichier
    ///   - config: Configuration de lecture
    /// - Returns: Tableau de points (potentiel, courant)
    static func readFile(at url: URL, config: SWVFileConfiguration) throws -> [VoltammetryPoint] {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw FileError.permissionDenied
        }

        let content: String
        do {
            content = try String(contentsOf: url, encoding: config.encoding)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == 257 {
                throw FileError.permissionDenied
            }
            if error.domain == NSCocoaErrorDomain && error.code == 261 {
                throw FileError.encodingError
            }
            throw error
        }

        let lines = content.components(separatedBy: .newlines)

        guard lines.count > 1 else {
            throw FileError.invalidFormat
        }

        // Première ligne = entête (métadonnées du potentiostat), ignorée.
        let dataLines = lines.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var points: [VoltammetryPoint] = []

        for line in dataLines {
            // Découpage : pour le séparateur espace on compresse les répétitions
            // (plusieurs espaces consécutifs → un seul délimiteur) ; pour les
            // autres séparateurs on filtre simplement les tokens vides issus
            // d'un séparateur en début/fin de ligne.
            let rawColumns: [String]
            if config.columnSeparator == .space {
                rawColumns = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            } else {
                rawColumns = line.components(separatedBy: config.columnSeparator.rawValue)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
            guard rawColumns.count >= 2 else { continue }

            let potentialString = rawColumns[0].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: config.decimalSeparator.rawValue, with: ".")
            let currentString = rawColumns[1].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: config.decimalSeparator.rawValue, with: ".")

            if let potential = Double(potentialString),
               let current = Double(currentString),
               current != 0 {
                points.append(VoltammetryPoint(potential: potential, current: current))
            }
        }

        guard points.count >= 5 else {
            throw FileError.insufficientData
        }

        return points
    }

    /// Traite les données brutes : tri et inversion du signe du courant (COMME PYTHON)
    /// - Parameter points: Points bruts
    /// - Returns: Tuple (potentiels, courants) triés
    static func processData(_ points: [VoltammetryPoint]) -> (potentials: [Double], currents: [Double]) {
        let sorted = points.sorted { $0.potential < $1.potential }
        // Convention SWV : on inverse le signe pour ramener les pics vers le haut.
        let potentials = sorted.map { $0.potential }
        let currents = sorted.map { -$0.current }
        return (potentials, currents)
    }
}
