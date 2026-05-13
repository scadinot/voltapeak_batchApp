//
//  SignalProcessing.swift
//  voltapeak_batch
//
//  Détection de pic et utilitaires numériques
//  (repris à l'identique de voltapeakApp).
//

import Foundation

/// Algorithmes de traitement du signal pour voltampérométrie
enum SignalProcessing {

    // MARK: - Peak Detection

    /// Détecte le pic (maximum) du signal avec protection des bords
    /// - Parameters:
    ///   - signal: Signal dans lequel chercher le pic
    ///   - potentials: Potentiels correspondants
    ///   - marginRatio: Fraction du signal à exclure de chaque côté (0.1 = 10%)
    ///   - maxSlope: Pente maximale tolérée (nil = pas de filtre)
    /// - Returns: Tuple (potentiel du pic, courant du pic)
    static func detectPeak(
        signal: [Double],
        potentials: [Double],
        marginRatio: Double = 0.10,
        maxSlope: Double? = 500
    ) -> (potential: Double, current: Double) {
        let n = signal.count
        let margin = Int(Double(n) * marginRatio)

        let searchRegion = Array(signal[margin..<(n - margin)])
        let potentialsRegion = Array(potentials[margin..<(n - margin)])

        var peakIndex = 0

        if let maxSlope = maxSlope {
            let slopes = gradient(searchRegion, x: potentialsRegion)

            var validIndices: [Int] = []
            for i in 0..<slopes.count {
                if abs(slopes[i]) < maxSlope {
                    validIndices.append(i)
                }
            }

            if validIndices.isEmpty {
                peakIndex = 0
            } else {
                var maxValue = -Double.infinity
                for idx in validIndices {
                    if searchRegion[idx] > maxValue {
                        maxValue = searchRegion[idx]
                        peakIndex = idx
                    }
                }
            }
        } else {
            if let maxIdx = searchRegion.enumerated().max(by: { $0.element < $1.element })?.offset {
                peakIndex = maxIdx
            }
        }

        let actualIndex = peakIndex + margin
        return (potentials[actualIndex], signal[actualIndex])
    }

    // MARK: - Helper

    /// Calcule le gradient (dérivée numérique) d'un signal — reproduit `numpy.gradient(y, x)`
    ///
    /// Bords : différences finies 1ᵉʳ ordre (edge_order=1, défaut numpy).
    /// Intérieur : différences centrées 2ᵉ ordre pour pas non-uniformes, avec
    /// `hd = x[i] − x[i−1]`, `hs = x[i+1] − x[i]` :
    ///   grad[i] = −hs/(hd·(hd+hs))·y[i−1] + (hs−hd)/(hd·hs)·y[i] + hd/(hs·(hd+hs))·y[i+1]
    private static func gradient(_ y: [Double], x: [Double]) -> [Double] {
        var grad = [Double](repeating: 0, count: y.count)
        let n = y.count

        for i in 0..<n {
            if i == 0 {
                grad[i] = (y[1] - y[0]) / (x[1] - x[0])
            } else if i == n - 1 {
                grad[i] = (y[i] - y[i - 1]) / (x[i] - x[i - 1])
            } else {
                let hd = x[i] - x[i - 1]
                let hs = x[i + 1] - x[i]
                let a = -hs / (hd * (hd + hs))
                let b = (hs - hd) / (hd * hs)
                let c = hd / (hs * (hd + hs))
                grad[i] = a * y[i - 1] + b * y[i] + c * y[i + 1]
            }
        }

        return grad
    }
}
