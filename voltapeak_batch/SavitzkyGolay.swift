//
//  SavitzkyGolay.swift
//  voltapeak_batch
//
//  Implémentation de Savitzky-Golay scipy-exacte
//  (reprise à l'identique de voltapeakApp).
//

import Foundation

/// Savitzky-Golay avec coefficients pré-calculés de scipy
nonisolated enum SavitzkyGolay {

    /// scipy.signal.savgol_coeffs(window_length=11, polyorder=2, pos=p, use='dot') pour p ∈ 0..10
    ///
    /// boundaryCoeffs[p] s'applique en produit scalaire (coeffs[j] · signal[base + j]) :
    /// - aux 11 PREMIERS points pour p ∈ 0..4 (bord gauche, output[p])
    /// - à la fenêtre centrée [i-5..i+5] pour p == 5 (intérieur, symétrique)
    /// - aux 11 DERNIERS points pour p ∈ 6..10 (bord droit, output[n-11+p])
    ///
    /// Reproduit exactement scipy.signal.savgol_filter avec mode='interp'.
    private static let boundaryCoeffs: [[Double]] = [
        // pos=0
        [5.804195804195814157e-01, 3.776223776223778250e-01, 2.097902097902096807e-01,
         7.692307692307648326e-02, -2.097902097902165641e-02, -8.391608391608465500e-02,
         -1.118881118881125125e-01, -1.048951048951053677e-01, -6.293706293706316512e-02,
         1.398601398601420631e-02, 1.258741258741268021e-01],
        // pos=1
        [3.776223776223753825e-01, 2.783216783216764800e-01, 1.930069930069917838e-01,
         1.216783216783208083e-01, 6.433566433566378917e-02, 2.097902097902067456e-02,
         -8.391608391608473133e-03, -2.377622377622374758e-02, -2.517482517482506552e-02,
         -1.258741258741245470e-02, 1.398601398601405713e-02],
        // pos=2
        [2.097902097902095142e-01, 1.930069930069927830e-01, 1.738927738927737443e-01,
         1.524475524475523425e-01, 1.286713286713286053e-01, 1.025641025641025328e-01,
         7.412587412587412494e-02, 4.335664335664336788e-02, 1.025641025641025987e-02,
         -2.517482517482518001e-02, -6.293706293706295696e-02],
        // pos=3
        [7.692307692307694122e-02, 1.216783216783216826e-01, 1.524475524475524812e-01,
         1.692307692307692124e-01, 1.720279720279720148e-01, 1.608391608391608329e-01,
         1.356643356643356113e-01, 9.650349650349646091e-02, 4.335664335664331237e-02,
         -2.377622377622380309e-02, -1.048951048951049375e-01],
        // pos=4
        [-2.097902097902112212e-02, 6.433566433566470510e-02, 1.286713286713294102e-01,
         1.720279720279730140e-01, 1.944055944055955165e-01, 1.958041958041969455e-01,
         1.762237762237772454e-01, 1.356643356643364440e-01, 7.412587412587455515e-02,
         -8.391608391608431500e-03, -1.118881118881125403e-01],
        // pos=5 (centre symétrique)
        [-8.391608391608411377e-02, 2.097902097902109783e-02, 1.025641025641030046e-01,
         1.608391608391615268e-01, 1.958041958041965847e-01, 2.074592074592082891e-01,
         1.958041958041965847e-01, 1.608391608391614991e-01, 1.025641025641030324e-01,
         2.097902097902112559e-02, -8.391608391608411377e-02],
        // pos=6
        [-1.118881118881125958e-01, -8.391608391608393336e-03, 7.412587412587462454e-02,
         1.356643356643365550e-01, 1.762237762237773564e-01, 1.958041958041970565e-01,
         1.944055944055956830e-01, 1.720279720279731528e-01, 1.286713286713295490e-01,
         6.433566433566483000e-02, -2.097902097902098334e-02],
        // pos=7
        [-1.048951048951049375e-01, -2.377622377622383085e-02, 4.335664335664339564e-02,
         9.650349650349653030e-02, 1.356643356643356946e-01, 1.608391608391608607e-01,
         1.720279720279720426e-01, 1.692307692307692679e-01, 1.524475524475524535e-01,
         1.216783216783216826e-01, 7.692307692307691347e-02],
        // pos=8
        [-6.293706293706270716e-02, -2.517482517482511062e-02, 1.025641025641025467e-02,
         4.335664335664328461e-02, 7.412587412587402780e-02, 1.025641025641024495e-01,
         1.286713286713285775e-01, 1.524475524475523980e-01, 1.738927738927739386e-01,
         1.930069930069931439e-01, 2.097902097902100693e-01],
        // pos=9
        [1.398601398601394437e-02, -1.258741258741230377e-02, -2.517482517482508286e-02,
         -2.377622377622377881e-02, -8.391608391608530379e-03, 2.097902097902067803e-02,
         6.433566433566378917e-02, 1.216783216783208776e-01, 1.930069930069919781e-01,
         2.783216783216769241e-01, 3.776223776223758821e-01],
        // pos=10
        [1.258741258741255531e-01, 1.398601398601435550e-02, -6.293706293706254062e-02,
         -1.048951048951044657e-01, -1.118881118881115827e-01, -8.391608391608394724e-02,
         -2.097902097902150723e-02, 7.692307692307569222e-02, 2.097902097902079321e-01,
         3.776223776223747164e-01, 5.804195804195763086e-01]
    ]

    /// Applique le filtre Savitzky-Golay (scipy.signal.savgol_filter, mode='interp')
    static func filter(_ signal: [Double], windowLength: Int = 11, polynomialOrder: Int = 2) -> [Double] {
        guard signal.count >= windowLength else {
            return signal
        }

        guard windowLength == 11 && polynomialOrder == 2 else {
            return filterGeneral(signal, windowLength: windowLength)
        }

        let halfWindow = 5  // windowLength / 2
        let n = signal.count
        var filtered = [Double](repeating: 0.0, count: n)

        // Bord gauche : output[i] = boundaryCoeffs[i] · signal[0..10]   pour i ∈ 0..4
        for i in 0..<halfWindow {
            let coeffs = boundaryCoeffs[i]
            var sum = 0.0
            for j in 0..<11 {
                sum += coeffs[j] * signal[j]
            }
            filtered[i] = sum
        }

        // Intérieur : convolution centrée avec les coefficients symétriques (pos=5)
        let centerCoeffs = boundaryCoeffs[halfWindow]
        for i in halfWindow..<(n - halfWindow) {
            var sum = 0.0
            for j in 0..<11 {
                sum += centerCoeffs[j] * signal[i - halfWindow + j]
            }
            filtered[i] = sum
        }

        // Bord droit : output[i] = boundaryCoeffs[i - n + 11] · signal[n-11..n-1]  pour i ∈ n-5..n-1
        let rightBase = n - 11
        for i in (n - halfWindow)..<n {
            let pos = i - rightBase  // 6..10
            let coeffs = boundaryCoeffs[pos]
            var sum = 0.0
            for j in 0..<11 {
                sum += coeffs[j] * signal[rightBase + j]
            }
            filtered[i] = sum
        }

        return filtered
    }

    /// Filtre général pour d'autres tailles de fenêtre (moyenne glissante simple).
    private static func filterGeneral(_ signal: [Double], windowLength: Int) -> [Double] {
        let halfWindow = windowLength / 2
        let n = signal.count
        var filtered = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            let start = max(0, i - halfWindow)
            let end = min(n, i + halfWindow + 1)

            var sum = 0.0
            var count = 0

            for j in start..<end {
                sum += signal[j]
                count += 1
            }

            filtered[i] = sum / Double(count)
        }

        return filtered
    }
}
