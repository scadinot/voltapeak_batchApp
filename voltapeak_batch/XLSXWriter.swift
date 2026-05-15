//
//  XLSXWriter.swift
//  voltapeak_batch
//
//  Génère des fichiers .xlsx (OOXML) sans dépendance externe :
//  mini-ZIP store-only (compression method = 0) + 5 fichiers XML minimaux.
//
//  Deux modes :
//   - `write(analysis:potentials:rawCurrents:)`  → export par fichier (5 colonnes)
//   - `writeSummary(headers:rows:sheetName:)`    → classeur récapitulatif avec
//                                                  cellules `.number/.string/.formula`
//

import Foundation

/// Cellule supportée par le writer récapitulatif.
enum XLSXCell {
    case number(Double)
    case string(String)
    case formula(String)     // ex. "=B2/C2" — Excel calculera la valeur
    case empty
}

nonisolated enum XLSXWriter {

    // MARK: - Mode 1 : export par fichier (analyse complète)

    /// Construit un .xlsx pour UN fichier analysé : 5 colonnes
    /// `Potentiel | Courant brut | Signal lissé | Baseline | Signal corrigé`.
    static func write(
        analysis: VoltammetryAnalysis,
        potentials: [Double],
        rawCurrents: [Double]
    ) -> Data {
        let headers = [
            "Potentiel (V)",
            "Courant brut (A)",
            "Signal lissé (A)",
            "Baseline (A)",
            "Signal corrigé (A)"
        ]
        var rows: [[XLSXCell]] = []
        let n = potentials.count
        for i in 0..<n {
            rows.append([
                .number(potentials[i]),
                .number(rawCurrents[i]),
                .number(analysis.smoothedSignal[i]),
                .number(analysis.baseline[i]),
                .number(analysis.correctedSignal[i])
            ])
        }
        return buildXLSX(headers: headers, rows: rows, sheetName: "Analyse SWV")
    }

    // MARK: - Mode 2 : classeur récapitulatif (batch)

    /// Construit un .xlsx récapitulatif avec cellules typées (incluant formules Excel).
    /// Utilisé pour le classeur agrégé multi-électrodes : 1 ligne par base, une
    /// colonne `Charge (C)` portant la formule `=Courant/Fréq`.
    static func writeSummary(
        headers: [String],
        rows: [[XLSXCell]],
        sheetName: String = "Récapitulatif"
    ) -> Data {
        return buildXLSX(headers: headers, rows: rows, sheetName: sheetName)
    }

    // MARK: - Construction commune

    private static func buildXLSX(
        headers: [String],
        rows: [[XLSXCell]],
        sheetName: String
    ) -> Data {
        let files: [(name: String, data: Data)] = [
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rootRels.utf8)),
            ("xl/workbook.xml", Data(workbookXML(sheetName: sheetName).utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)),
            ("xl/worksheets/sheet1.xml",
             Data(buildSheetXML(headers: headers, rows: rows).utf8))
        ]
        return ZIPStore.archive(files)
    }

    // MARK: - XML statiques

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
    </Types>
    """

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

    private static func workbookXML(sheetName: String) -> String {
        let escaped = xmlEscape(sheetName)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <sheets><sheet name="\(escaped)" sheetId="1" r:id="rId1"/></sheets>\
        </workbook>
        """
    }

    private static let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
    </Relationships>
    """

    // MARK: - Construction de la feuille

    private static func buildSheetXML(headers: [String], rows: [[XLSXCell]]) -> String {
        var sheet = ""

        // En-tête (ligne 1) — chaînes inline
        sheet += "<row r=\"1\">"
        for (i, header) in headers.enumerated() {
            let col = columnLetter(i)
            sheet += "<c r=\"\(col)1\" t=\"inlineStr\"><is><t>\(xmlEscape(header))</t></is></c>"
        }
        sheet += "</row>"

        // Données (lignes 2..n+1)
        for (rIndex, row) in rows.enumerated() {
            let r = rIndex + 2
            sheet += "<row r=\"\(r)\">"
            for (cIndex, cell) in row.enumerated() {
                let col = columnLetter(cIndex)
                let ref = "\(col)\(r)"
                switch cell {
                case .number(let value):
                    if value.isFinite {
                        sheet += "<c r=\"\(ref)\"><v>\(value)</v></c>"
                    } else {
                        sheet += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t></t></is></c>"
                    }
                case .string(let s):
                    sheet += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(xmlEscape(s))</t></is></c>"
                case .formula(let f):
                    // Excel recalcule la valeur à l'ouverture ; on n'écrit pas <v>.
                    // Le `=` initial est retiré : OOXML attend l'expression seule.
                    var expr = f
                    if expr.hasPrefix("=") { expr.removeFirst() }
                    sheet += "<c r=\"\(ref)\"><f>\(xmlEscape(expr))</f></c>"
                case .empty:
                    // Cellule vide : on l'omet purement et simplement.
                    break
                }
            }
            sheet += "</row>"
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <sheetData>\(sheet)</sheetData>\
        </worksheet>
        """
    }

    /// Convertit un index 0-based en lettre de colonne Excel (A, B, …, Z, AA, AB, …).
    static func columnLetter(_ index: Int) -> String {
        var n = index
        var result = ""
        repeat {
            let r = n % 26
            result = String(UnicodeScalar(65 + r)!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    /// Échappe les caractères réservés XML dans les chaînes.
    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Mini ZIP store-only (compression method = 0)

private nonisolated enum ZIPStore {

    /// Empaquette une liste de fichiers en archive ZIP non compressée.
    /// Format suffisant pour OOXML : Excel/Numbers acceptent le ZIP store-only.
    static func archive(_ files: [(name: String, data: Data)]) -> Data {
        var output = Data()
        var centralDirectory = Data()

        for file in files {
            let nameBytes = Array(file.name.utf8)
            let crc = crc32(file.data)
            let size = UInt32(file.data.count)
            let localOffset = UInt32(output.count)

            // Local File Header
            var lfh = Data()
            lfh.appendUInt32LE(0x04034b50)
            lfh.appendUInt16LE(20)
            lfh.appendUInt16LE(0)
            lfh.appendUInt16LE(0)          // compression method = 0 (store)
            lfh.appendUInt16LE(0)
            lfh.appendUInt16LE(0)
            lfh.appendUInt32LE(crc)
            lfh.appendUInt32LE(size)       // compressed size = uncompressed pour store
            lfh.appendUInt32LE(size)
            lfh.appendUInt16LE(UInt16(nameBytes.count))
            lfh.appendUInt16LE(0)
            lfh.append(contentsOf: nameBytes)
            output.append(lfh)
            output.append(file.data)

            // Central Directory Entry
            var cde = Data()
            cde.appendUInt32LE(0x02014b50)
            cde.appendUInt16LE(20)
            cde.appendUInt16LE(20)
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt32LE(crc)
            cde.appendUInt32LE(size)
            cde.appendUInt32LE(size)
            cde.appendUInt16LE(UInt16(nameBytes.count))
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt16LE(0)
            cde.appendUInt32LE(0)
            cde.appendUInt32LE(localOffset)
            cde.append(contentsOf: nameBytes)
            centralDirectory.append(cde)
        }

        let centralStart = UInt32(output.count)
        let centralSize = UInt32(centralDirectory.count)
        output.append(centralDirectory)

        // End of Central Directory Record
        var eocd = Data()
        eocd.appendUInt32LE(0x06054b50)
        eocd.appendUInt16LE(0)
        eocd.appendUInt16LE(0)
        eocd.appendUInt16LE(UInt16(files.count))
        eocd.appendUInt16LE(UInt16(files.count))
        eocd.appendUInt32LE(centralSize)
        eocd.appendUInt32LE(centralStart)
        eocd.appendUInt16LE(0)
        output.append(eocd)

        return output
    }

    /// CRC32 standard PKZIP (polynôme inversé 0xEDB88320).
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask: UInt32 = (crc & 1) != 0 ? 0xEDB88320 : 0
                crc = (crc >> 1) ^ mask
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private nonisolated extension Data {
    mutating func appendUInt16LE(_ v: UInt16) {
        append(UInt8(v & 0xff))
        append(UInt8((v >> 8) & 0xff))
    }
    mutating func appendUInt32LE(_ v: UInt32) {
        append(UInt8(v & 0xff))
        append(UInt8((v >> 8) & 0xff))
        append(UInt8((v >> 16) & 0xff))
        append(UInt8((v >> 24) & 0xff))
    }
}
