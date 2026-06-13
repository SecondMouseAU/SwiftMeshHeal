// Liepa (2003) minimum-dihedral hole triangulation + the selective, opening-aware fill pipeline.
//
// Fills a hole directly in 3D: a dynamic program over the boundary ring chooses the triangulation
// (using only the existing rim vertices) that minimises the worst dihedral angle between adjacent
// patch faces and the existing mesh faces across the rim — area as tie-breaker. Same algorithm CGAL/PMP
// expose as triangulate_hole, in pure Swift so it ships on-device with no native dependency. Only the
// base triangulation (no refine/fair): the holes we fill are small defects; large holes are intended
// openings we skip.

import Foundation
import simd

public extension MeshHeal {

    private func ekey(_ a: UInt32, _ b: UInt32) -> UInt64 { (UInt64(max(a, b)) << 32) | UInt64(min(a, b)) }

    /// Outward normal of the single existing triangle on each boundary edge (used once).
    func boundaryEdgeFaceNormals() -> [UInt64: SIMD3<Double>] {
        var use: [UInt64: Int] = [:], one: [UInt64: SIMD3<Double>] = [:]
        for t in 0..<triangleCount {
            let (a, b, c) = triangle(t)
            let nrm = simd_cross(pos(b) - pos(a), pos(c) - pos(a))
            for e in [ekey(a, b), ekey(b, c), ekey(c, a)] { use[e, default: 0] += 1; one[e] = nrm }
        }
        var out: [UInt64: SIMD3<Double>] = [:]
        for (e, n) in one where use[e] == 1 { out[e] = n }
        return out
    }

    /// Liepa min-dihedral triangulation of one boundary loop, using only the loop's vertices. Forbids a
    /// diagonal that coincides with an existing mesh edge (it would make that edge non-manifold). Returns
    /// nil if every triangulation needs such a diagonal (a slit/crack) — caller falls back to a fan.
    func liepaFill(loop: [UInt32], bndNormals: [UInt64: SIMD3<Double>], existingEdges: Set<UInt64>) -> [(UInt32, UInt32, UInt32)]? {
        let n = loop.count
        guard n >= 3 else { return nil }
        if n == 3 { return [(loop[0], loop[1], loop[2])] }
        let P = loop.map { pos($0) }
        func triN(_ i: Int, _ k: Int, _ j: Int) -> SIMD3<Double> { simd_cross(P[k] - P[i], P[j] - P[i]) }
        func triArea(_ i: Int, _ k: Int, _ j: Int) -> Double { simd_length(triN(i, k, j)) * 0.5 }
        func ang(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
            let la = simd_length(a), lb = simd_length(b)
            guard la > 1e-20, lb > 1e-20 else { return .pi }
            return acos(max(-1, min(1, simd_dot(a, b) / (la * lb))))
        }
        struct W { var dih: Double; var area: Double }
        func better(_ x: W, _ y: W) -> Bool { x.dih < y.dih - 1e-12 || (abs(x.dih - y.dih) <= 1e-12 && x.area < y.area) }
        let INF = W(dih: .greatestFiniteMagnitude, area: .greatestFiniteMagnitude)
        var Wt = [[W]](repeating: [W](repeating: INF, count: n), count: n)
        var lam = [[Int]](repeating: [Int](repeating: -1, count: n), count: n)
        for i in 0..<(n - 1) { Wt[i][i + 1] = W(dih: 0, area: 0) }
        func adjNormal(_ i: Int, _ k: Int) -> SIMD3<Double> {
            if k == i + 1 { return bndNormals[ekey(loop[i], loop[k])] ?? triN(i, k, (k + 1) % n) }
            let m = lam[i][k]; return m >= 0 ? triN(i, m, k) : triN(i, k, (i + k) / 2)
        }
        var span = 2
        while span < n {
            var i = 0
            while i + span < n {
                let j = i + span; var best = INF, bestM = -1
                for m in (i + 1)..<j {
                    let wl = Wt[i][m], wr = Wt[m][j]
                    if wl.dih == INF.dih || wr.dih == INF.dih { continue }
                    if m != i + 1, existingEdges.contains(ekey(loop[i], loop[m])) { continue }
                    if j != m + 1, existingEdges.contains(ekey(loop[m], loop[j])) { continue }
                    let nT = triN(i, m, j)
                    let cand = W(dih: max(max(wl.dih, wr.dih), max(ang(nT, adjNormal(i, m)), ang(nT, adjNormal(m, j)))),
                                 area: wl.area + wr.area + triArea(i, m, j))
                    if better(cand, best) { best = cand; bestM = m }
                }
                Wt[i][j] = best; lam[i][j] = bestM; i += 1
            }
            span += 1
        }
        guard lam[0][n - 1] >= 0 else { return nil }
        var tris: [(UInt32, UInt32, UInt32)] = []
        func emit(_ i: Int, _ j: Int) {
            if j <= i + 1 { return }
            let m = lam[i][j]; guard m >= 0 else { return }
            tris.append((loop[i], loop[m], loop[j])); emit(i, m); emit(m, j)
        }
        emit(0, n - 1)
        return tris.isEmpty ? nil : tris
    }

    /// Fill boundary-loop holes via Liepa. By DEFAULT fills EVERY loop (a part's missing back is a defect,
    /// not an opening — size alone mis-classifies it). Pass `skipLoop` to PROTECT intended openings (the
    /// shell's windows/doors — see `throughOpeningSkip`). When Liepa can't fill without a colliding
    /// diagonal, fans from a fresh centroid vertex (all-new spokes can't create non-manifold edges).
    func filledHoles(skipLoop: ([UInt32]) -> Bool = { _ in false }) -> (mesh: MeshHeal, filled: Int, skipped: Int, remainingUnfilled: Int) {
        let loops = boundaryLoops()
        guard !loops.isEmpty else { return (self, 0, 0, 0) }
        let bnd = boundaryEdgeFaceNormals()
        var existingEdges = Set<UInt64>()
        for t in 0..<triangleCount { let (a, b, c) = triangle(t); existingEdges.insert(ekey(a, b)); existingEdges.insert(ekey(b, c)); existingEdges.insert(ekey(c, a)) }
        var newIndices = indices, newPositions = positions
        var filled = 0, skipped = 0
        for loop in loops where loop.count >= 3 {
            if skipLoop(loop) { skipped += 1; continue }
            let tris: [(UInt32, UInt32, UInt32)]
            if let lt = liepaFill(loop: loop, bndNormals: bnd, existingEdges: existingEdges) {
                tris = lt
            } else {
                let c = loop.map { pos($0) }.reduce(SIMD3<Double>.zero, +) / Double(loop.count)
                let cIdx = UInt32(newPositions.count)
                newPositions.append(SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z)))
                tris = (0..<loop.count).map { (cIdx, loop[$0], loop[($0 + 1) % loop.count]) }
            }
            func np(_ vi: UInt32) -> SIMD3<Double> { let p = newPositions[Int(vi)]; return SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z)) }
            for (a, b, c) in tris {
                let fn = simd_cross(np(b) - np(a), np(c) - np(a))
                var ref = SIMD3<Double>.zero
                for (x, y) in [(a, b), (b, c), (c, a)] { if let rn = bnd[ekey(x, y)] { ref = rn; break } }
                newIndices.append(contentsOf: simd_dot(fn, ref) >= 0 ? [a, c, b] : [a, b, c])
            }
            filled += 1
        }
        let result = MeshHeal(positions: newPositions, indices: newIndices)
        return (result, filled, skipped, result.boundaryLoops().filter { !skipLoop($0) }.count)
    }

    /// THE preprocessing entry point. (1) Internal-membrane removal (small bodies) + size-aware non-
    /// manifold resolve, then (2) iterate resolve→fill ×3 (each pass clears the prior pass's residual
    /// non-manifold edges). Degenerate sheets are passed through unchanged (not solidifiable). Pass
    /// `skipLoop` to protect intended openings.
    func tier1Healed(skipLoop: ([UInt32]) -> Bool = { _ in false }) -> (mesh: MeshHeal, filled: Int, skipped: Int, remainingUnfilled: Int) {
        if isDegenerateSheet { return (self, 0, 0, boundaryLoops().count) }
        var m = (triangleCount > 6000 ? self : repairedManifold()).removingDuplicateFaces()
        var lastFilled = 0, lastSkipped = 0
        for _ in 0..<3 {
            if m.nonManifoldEdgeCount > 0 { m = m.resolveNonManifoldEdges() }
            let (filled, f, s, _) = m.filledHoles(skipLoop: skipLoop)
            lastFilled = f; lastSkipped = s; m = filled
            if m.isWatertight { break }
        }
        return (m, lastFilled, lastSkipped, m.boundaryLoops().filter { !skipLoop($0) }.count)
    }

    /// A `skipLoop` predicate that protects genuine through-openings (the shell's windows/doors): a loop
    /// is intended when it encloses real planar area ≥ `minArea` AND a ray through its centroid clears
    /// `clearDist` on both sides (opens into space, not a thin part's near interior). Small parts never
    /// trigger it (rays hit nearby → fill fully); the area gate keeps cracks classed as defects.
    func throughOpeningSkip(minArea: Double = 6.0, clearDist: Double = 10.0) -> ([UInt32]) -> Bool {
        return { loop in
            guard loop.count >= 6 else { return false }
            let pts = loop.map { self.pos($0) }
            let c = pts.reduce(SIMD3<Double>.zero, +) / Double(pts.count)
            let (cov, _) = Linalg.covariance(pts)
            let (vals, vecs) = Linalg.eigenSymmetric3(cov)
            let k = [0, 1, 2].min(by: { vals[$0] < vals[$1] })!
            let n = simd_normalize(SIMD3<Double>(vecs[k][0], vecs[k][1], vecs[k][2]))
            let ref = abs(n.x) < 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
            let u = simd_normalize(simd_cross(ref, n)), v = simd_cross(n, u)
            var a2 = 0.0
            for i in 0..<pts.count { let a = pts[i] - c, b = pts[(i + 1) % pts.count] - c
                a2 += simd_dot(a, u) * simd_dot(b, v) - simd_dot(b, u) * simd_dot(a, v) }
            guard abs(a2) * 0.5 >= minArea else { return false }
            let up = self.firstRayHit(origin: c + n * 0.05, direction: n, maxDist: clearDist * 4) ?? .greatestFiniteMagnitude
            let dn = self.firstRayHit(origin: c - n * 0.05, direction: -n, maxDist: clearDist * 4) ?? .greatestFiniteMagnitude
            return min(up, dn) >= clearDist
        }
    }

    /// A degenerate micro-part: too few triangles, or a (near) zero-thickness sheet / membrane. Not a
    /// hole-filling problem — no volume to close. The healer passes these through unchanged.
    var isDegenerateSheet: Bool {
        if triangleCount <= 4 { return true }
        let e = pcaExtents
        let mn = Double(min(e.x, min(e.y, e.z))), mx = Double(max(e.x, max(e.y, e.z)))
        return mx > 1e-9 && mn / mx < 0.01
    }
}
