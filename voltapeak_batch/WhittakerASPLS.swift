//
//  WhittakerASPLS.swift
//  voltapeak_batch
//
//  Implémentation EXACTE de pybaselines.whittaker.aspls (Zhang 2020)
//  (reprise à l'identique de voltapeakApp).
//
//  Solveur banded LAPACK `dgbsv_` via Accelerate.framework : la matrice
//  `diag(α)·(λ·D^TD) + diag(w)` est pentadiagonale (KL=KU=2), résolue en
//  O(n) au lieu d'un Gauss dense O(n³). Sur les fichiers à plusieurs
//  milliers de points, gain pratique > 1000×.
//

import Foundation
import Accelerate

/// Implémentation EXACTE de pybaselines.whittaker.aspls (Zhang 2020)
///
/// Adaptive Smoothness Penalized Least Squares :
/// - vecteur α modulant la pénalité localement : `lhs = diag(α) · (λ·D^TD)`
/// - mise à jour sigmoïdale des poids basée sur `σ = std(résidus négatifs)`
/// - convergence sur le changement relatif des poids (PAS de la baseline)
nonisolated enum WhittakerASPLS {

    /// Garde-fou : au-delà de cette taille, le caller DOIT refuser le fichier
    /// en amont. L'algorithme banded reste correct numériquement à toute
    /// taille, mais on bloque par sécurité contre les fichiers corrompus
    /// ou mal parsés. Très permissif (200 000 points couvrent toute donnée
    /// légitime de voltampérométrie SWV).
    static let maxN: Int = 200_000

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
        // Garde-fou debug-only. Les callers (`BatchProcessor.process`, etc.)
        // sont responsables du filtre amont qui remonte une `FileError.tooManyPoints`
        // dans le journal du batch. En Release, on laisse passer si jamais un
        // chemin oublie le check : le solveur banded reste tractable bien au-delà
        // de `maxN`, donc dégradation perf < crash batch.
        assert(
            n <= maxN,
            "WhittakerASPLS.aspls: signal trop grand (\(n) > \(maxN)). Le caller doit filtrer en amont."
        )

        var w = weights ?? [Double](repeating: 1.0, count: n)
        var a = alpha ?? [Double](repeating: 1.0, count: n)

        // Format LAPACK band column-major : KL=KU=2, LDAB = 2·KL+KU+1 = 7.
        // A[i,j] est stocké à AB[(KL+KU+i-j) + j*LDAB] pour |i-j| ≤ 2.
        // Les KL premières lignes (rows 0-1) sont réservées au fill-in du
        // pivotage LU et doivent être initialisées à 0.
        let kl = 2
        let ku = 2
        let ldab = 2 * kl + ku + 1   // 7

        // Template DTD banded, indépendant de α et w : calculé une seule fois.
        let dtdBandedTemplate = buildDTDBanded(n: n, diffOrder: diffOrder, kl: kl, ku: ku, ldab: ldab)

        var baseline = [Double](repeating: 0.0, count: n)

        // pybaselines fait `for i in range(max_iter + 1):` (cf. _Whittaker.aspls)
        // — donc `maxIter + 1` itérations possibles. La borne inclusive
        // `0...maxIter` reproduit ce comportement à l'identique ; ne pas
        // remplacer par `0..<maxIter` sous peine de casser la parité numérique.
        for _ in 0...maxIter {
            // ab = diag(α) · (λ · DTD), puis + diag(w) sur la diagonale.
            // α multiplie chaque LIGNE i (système non symétrique).
            var ab = dtdBandedTemplate
            for j in 0..<n {
                let iMin = max(0, j - ku)
                let iMax = min(n - 1, j + kl)
                for i in iMin...iMax {
                    let bandRow = kl + ku + i - j
                    ab[bandRow + j * ldab] *= lam * a[i]
                }
                // Diagonale (i == j) : bandRow = kl + ku
                ab[(kl + ku) + j * ldab] += w[j]
            }

            // RHS = w * y (sera écrasé par dgbsv avec la solution)
            var b = [Double](repeating: 0.0, count: n)
            for i in 0..<n {
                b[i] = w[i] * y[i]
            }

            // Résolution banded LU avec pivotage partiel : dgbsv_
            var n_l = __LAPACK_int(n)
            var kl_l = __LAPACK_int(kl)
            var ku_l = __LAPACK_int(ku)
            var nrhs = __LAPACK_int(1)
            var ldab_l = __LAPACK_int(ldab)
            var ldb_l = __LAPACK_int(n)
            var info = __LAPACK_int(0)
            var ipiv = [__LAPACK_int](repeating: 0, count: n)

            ab.withUnsafeMutableBufferPointer { abPtr in
                b.withUnsafeMutableBufferPointer { bPtr in
                    _ = dgbsv_(
                        &n_l, &kl_l, &ku_l, &nrhs,
                        abPtr.baseAddress, &ldab_l,
                        &ipiv,
                        bPtr.baseAddress, &ldb_l,
                        &info
                    )
                }
            }
            // dgbsv_ doit retourner info=0 sur matrice non-singulière. Les cas
            // d'échec sont diagnostiquement séparés : info<0 = bug d'appel (taille
            // invalide, pointeur null, etc.) ; info>0 = matrice singulière à la
            // ligne `info` (entrée pathologique : poids/α nuls, NaN/Inf dans y).
            if info < 0 {
                fatalError("dgbsv_ : argument invalide à la position \(-info) (bug d'appel interne).")
            }
            if info > 0 {
                fatalError("dgbsv_ : matrice singulière à la ligne \(info) — vérifiez NaN/Inf dans y, ou poids/α extrêmes.")
            }
            baseline = b

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

    /// Construit D^T D directement en format LAPACK band column-major.
    /// En Python : D = difference_matrix(n, diff_order); DTD = D.T @ D
    ///
    /// Pour diffOrder=2, D est la matrice de différences secondes (n-2)×n :
    /// D[i,i] = 1, D[i,i+1] = -2, D[i,i+2] = 1
    /// D^T D résultant est une matrice pentadiagonale n×n.
    ///
    /// Stockage band : buffer plat de taille `ldab * n` (column-major) ;
    /// l'élément DTD[i,j] avec |i-j| ≤ 2 va à `ab[(kl+ku+i-j) + j*ldab]`.
    /// Les `kl` premières lignes (réservées au pivotage) restent à 0.
    private static func buildDTDBanded(
        n: Int, diffOrder: Int, kl: Int, ku: Int, ldab: Int
    ) -> [Double] {
        guard diffOrder == 2 else {
            fatalError("Seul diffOrder=2 est supporté (comme pybaselines par défaut)")
        }

        var ab = [Double](repeating: 0.0, count: ldab * n)

        // Diagonale principale (i == j) : 1 aux coins, 5 aux quasi-bords, 6 au centre
        for j in 0..<n {
            let v: Double
            if j == 0 || j == n - 1 {
                v = 1.0
            } else if j == 1 || j == n - 2 {
                v = 5.0
            } else {
                v = 6.0
            }
            ab[(kl + ku) + j * ldab] = v
        }

        // Super-diagonale 1 (i = j-1) : -2 aux extrémités, -4 sinon
        for j in 1..<n {
            let i = j - 1
            let v: Double = ((i == 0 && j == 1) || (i == n - 2 && j == n - 1)) ? -2.0 : -4.0
            ab[(kl + ku - 1) + j * ldab] = v
        }

        // Sub-diagonale 1 (i = j+1) : -2 aux extrémités, -4 sinon
        for j in 0..<(n - 1) {
            let i = j + 1
            let v: Double = ((i == 1 && j == 0) || (i == n - 1 && j == n - 2)) ? -2.0 : -4.0
            ab[(kl + ku + 1) + j * ldab] = v
        }

        // Super-diagonale 2 (i = j-2) : 1
        for j in 2..<n {
            ab[(kl + ku - 2) + j * ldab] = 1.0
        }

        // Sub-diagonale 2 (i = j+2) : 1
        for j in 0..<(n - 2) {
            ab[(kl + ku + 2) + j * ldab] = 1.0
        }

        return ab
    }
}
