//
//  WhittakerASPLS.swift
//  voltapeak_batch
//
//  Implémentation EXACTE de pybaselines.whittaker.aspls (Zhang 2020)
//  (reprise à l'identique de voltapeakApp).
//

import Foundation

/// Implémentation EXACTE de pybaselines.whittaker.aspls (Zhang 2020)
///
/// Adaptive Smoothness Penalized Least Squares :
/// - vecteur α modulant la pénalité localement : `lhs = diag(α) · (λ·D^TD)`
/// - mise à jour sigmoïdale des poids basée sur `σ = std(résidus négatifs)`
/// - convergence sur le changement relatif des poids (PAS de la baseline)
enum WhittakerASPLS {

    /// Calcule la baseline par algorithme asPLS exact (pybaselines.whittaker.aspls)
    /// - Parameters:
    ///   - y: Signal d'entrée
    ///   - lam: Paramètre de lissage (typiquement `1e3 * n²` chez voltapeak)
    ///   - diffOrder: Ordre de la matrice de différences (défaut 2)
    ///   - maxIter: Nombre max d'itérations (défaut 100 ; voltapeak utilise 25)
    ///   - tol: Tolérance de convergence sur le changement de poids (défaut 1e-3)
    ///   - weights: Poids initiaux ; pour exclure une zone autour du pic, mettre 0.001
    ///   - alpha: Vecteur α initial (défaut ones)
    ///   - asymmetricCoef: Coefficient k du papier asPLS (défaut 0.5 — pybaselines)
    /// - Returns: Baseline estimée
    static func aspls(
        y: [Double],
        lam: Double = 1e5,
        diffOrder: Int = 2,
        maxIter: Int = 100,
        tol: Double = 1e-3,
        weights: [Double]? = nil,
        alpha: [Double]? = nil,
        asymmetricCoef: Double = 0.5
    ) -> [Double] {
        let n = y.count
        var w = weights ?? [Double](repeating: 1.0, count: n)
        var a = alpha ?? [Double](repeating: 1.0, count: n)

        let DTD = buildDTD(n: n, diffOrder: diffOrder)

        var baseline = [Double](repeating: 0.0, count: n)

        for _ in 0...maxIter {
            // lhs = diag(a) · (λ · DTD), puis + diag(w) sur la diagonale
            var A = [[Double]](repeating: [Double](repeating: 0.0, count: n), count: n)
            for i in 0..<n {
                let scale = lam * a[i]
                for j in 0..<n {
                    A[i][j] = scale * DTD[i][j]
                }
                A[i][i] += w[i]
            }

            // RHS = w * y
            var b = [Double](repeating: 0.0, count: n)
            for i in 0..<n {
                b[i] = w[i] * y[i]
            }

            // Système non-symétrique (α multiplie chaque ligne) → solveur général
            baseline = solveFallback(A: A, b: b)

            // Résidus
            var residual = [Double](repeating: 0.0, count: n)
            var maxAbsRes = 0.0
            for i in 0..<n {
                residual[i] = y[i] - baseline[i]
                let absR = abs(residual[i])
                if absR > maxAbsRes { maxAbsRes = absR }
            }

            // Résidus négatifs pour calculer σ
            var negRes: [Double] = []
            for r in residual where r < 0 {
                negRes.append(r)
            }
            if negRes.count < 2 {
                break
            }

            // σ = std(negRes, ddof=1)
            let negMean = negRes.reduce(0, +) / Double(negRes.count)
            var variance = 0.0
            for r in negRes {
                let d = r - negMean
                variance += d * d
            }
            let sigma = sqrt(variance / Double(negRes.count - 1))
            guard sigma > 0 else { break }

            // new_w[i] = 1 / (1 + exp((k/σ) · (residual[i] - σ)))
            var newW = [Double](repeating: 0.0, count: n)
            let kOverSigma = asymmetricCoef / sigma
            for i in 0..<n {
                newW[i] = 1.0 / (1.0 + exp(kOverSigma * (residual[i] - sigma)))
            }

            // Convergence : relative_difference(w, new_w) = sum|w - new_w| / sum|new_w|
            var sumDiff = 0.0
            var sumNewAbs = 0.0
            for i in 0..<n {
                sumDiff += abs(w[i] - newW[i])
                sumNewAbs += abs(newW[i])
            }
            let relDiff = sumNewAbs > 0 ? sumDiff / sumNewAbs : 0.0
            if relDiff < tol { break }

            // Mise à jour
            w = newW
            if maxAbsRes > 0 {
                for i in 0..<n {
                    a[i] = abs(residual[i]) / maxAbsRes
                }
            }
        }

        return baseline
    }

    /// Construit D^T D directement (optimisation)
    /// En Python : D = difference_matrix(n, diff_order); DTD = D.T @ D
    ///
    /// Pour diffOrder=2, D est la matrice de différences secondes (n-2)×n :
    /// D[i,i] = 1, D[i,i+1] = -2, D[i,i+2] = 1
    /// D^T D résultant est une matrice pentadiagonale n×n.
    private static func buildDTD(n: Int, diffOrder: Int) -> [[Double]] {
        guard diffOrder == 2 else {
            fatalError("Seul diffOrder=2 est supporté (comme pybaselines par défaut)")
        }

        var DTD = [[Double]](repeating: [Double](repeating: 0.0, count: n), count: n)

        for i in 0..<n {
            for j in 0..<n {
                let dist = abs(i - j)

                if dist == 0 {
                    if i == 0 || i == n - 1 {
                        DTD[i][j] = 1.0
                    } else if i == 1 || i == n - 2 {
                        DTD[i][j] = 5.0
                    } else {
                        DTD[i][j] = 6.0
                    }
                } else if dist == 1 {
                    if (i == 0 && j == 1) || (i == 1 && j == 0) ||
                       (i == n - 1 && j == n - 2) || (i == n - 2 && j == n - 1) {
                        DTD[i][j] = -2.0
                    } else {
                        DTD[i][j] = -4.0
                    }
                } else if dist == 2 {
                    DTD[i][j] = 1.0
                }
            }
        }

        return DTD
    }

    /// Résout A·x = b par élimination de Gauss avec pivotage partiel.
    ///
    /// La matrice `diag(α) · (λ·D^TD) + diag(w)` n'est PAS symétrique : Cholesky
    /// n'est pas applicable. Pour n ~ quelques centaines de points, Gauss dense
    /// reste largement assez rapide.
    private static func solveFallback(A: [[Double]], b: [Double]) -> [Double] {
        let n = A.count

        var M = A
        var y = b

        for k in 0..<n {
            var maxRow = k
            var maxVal = abs(M[k][k])

            for i in (k + 1)..<n {
                if abs(M[i][k]) > maxVal {
                    maxVal = abs(M[i][k])
                    maxRow = i
                }
            }

            if maxRow != k {
                M.swapAt(k, maxRow)
                y.swapAt(k, maxRow)
            }

            for i in (k + 1)..<n {
                let factor = M[i][k] / M[k][k]
                for j in k..<n {
                    M[i][j] -= factor * M[k][j]
                }
                y[i] -= factor * y[k]
            }
        }

        var x = [Double](repeating: 0.0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = y[i]
            for j in (i + 1)..<n {
                sum -= M[i][j] * x[j]
            }
            x[i] = sum / M[i][i]
        }

        return x
    }
}
