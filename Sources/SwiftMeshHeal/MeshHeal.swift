// SwiftMeshHeal — on-device, dependency-free triangle-mesh healing.
//
// A pure-Swift mesh-repair stage for turning broken / non-watertight STL bodies into closed,
// manifold solids, body-by-body, embedded on iOS arm64 + macOS with NO native dependency (no OCCT,
// no CGAL, no GMP, no Eigen). The headline algorithm is Liepa (2003) minimum-dihedral hole filling;
// see HoleFill.swift. This file holds the mesh value type and the topology / linear-algebra / ray
// primitives the healer needs, all self-contained so the package stands alone.

import Foundation
import simd

/// A welded, indexed triangle mesh: unique `positions`, `indices` holding 3 vertex indices per
/// triangle. The unit the healer operates on (one connected body at a time).
public struct MeshHeal: Sendable, Equatable {
    public var positions: [SIMD3<Float>]
    public var indices: [UInt32]

    public init(positions: [SIMD3<Float>], indices: [UInt32]) {
        self.positions = positions
        self.indices = indices
    }

    public var vertexCount: Int { positions.count }
    public var triangleCount: Int { indices.count / 3 }

    public func triangle(_ t: Int) -> (UInt32, UInt32, UInt32) {
        let b = t * 3; return (indices[b], indices[b + 1], indices[b + 2])
    }
    func pos(_ vi: UInt32) -> SIMD3<Double> {
        let p = positions[Int(vi)]; return SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z))
    }
    public func trianglePositions(_ t: Int) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        let (a, b, c) = triangle(t); return (positions[Int(a)], positions[Int(b)], positions[Int(c)])
    }

    public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard var lo = positions.first else { return nil }
        var hi = lo
        for p in positions { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return (lo, hi)
    }

    public func triangleArea(_ t: Int) -> Float {
        let (a, b, c) = trianglePositions(t); return simd_length(simd_cross(b - a, c - a)) * 0.5
    }
    public var surfaceArea: Float { (0..<triangleCount).reduce(0) { $0 + triangleArea($1) } }

    /// Closed ⇔ every edge shared by exactly two triangles.
    public var isWatertight: Bool {
        var count: [UInt64: Int] = [:]
        func key(_ a: UInt32, _ b: UInt32) -> UInt64 { (UInt64(min(a, b)) << 32) | UInt64(max(a, b)) }
        for t in 0..<triangleCount {
            let (a, b, c) = triangle(t)
            count[key(a, b), default: 0] += 1; count[key(b, c), default: 0] += 1; count[key(c, a), default: 0] += 1
        }
        return !count.values.contains { $0 != 2 }
    }

    /// Enclosed volume via the divergence theorem about the centroid (meaningful only when watertight).
    public var enclosedVolume: Double {
        guard let bb = bounds else { return 0 }
        let ctr = (SIMD3<Double>(bb.min) + SIMD3<Double>(bb.max)) * 0.5
        var v = 0.0
        for t in 0..<triangleCount {
            let (a, b, c) = trianglePositions(t)
            let ad = SIMD3<Double>(a) - ctr, bd = SIMD3<Double>(b) - ctr, cd = SIMD3<Double>(c) - ctr
            v += simd_dot(ad, simd_cross(bd, cd)) / 6.0
        }
        return abs(v)
    }

    /// PCA extents (ascending): the body's size along its three principal axes.
    public var pcaExtents: SIMD3<Float> {
        let pts = positions.map { SIMD3<Double>($0) }
        let (cov, c) = Linalg.covariance(pts)
        let (_, vecs) = Linalg.eigenSymmetric3(cov)
        var e = SIMD3<Float>(repeating: 0)
        for k in 0..<3 {
            let axis = SIMD3<Double>(vecs[k][0], vecs[k][1], vecs[k][2])
            var lo = Double.greatestFiniteMagnitude, hi = -lo
            for p in pts { let d = simd_dot(p - c, axis); lo = min(lo, d); hi = max(hi, d) }
            e[k] = Float(hi - lo)
        }
        return e
    }
}

// MARK: - Topology

public extension MeshHeal {
    private func ekey(_ a: UInt32, _ b: UInt32) -> UInt64 { (UInt64(max(a, b)) << 32) | UInt64(min(a, b)) }

    /// Count of edges shared by 3+ triangles. Zero ⇒ manifold (modulo open boundaries).
    var nonManifoldEdgeCount: Int {
        var c: [UInt64: Int] = [:]
        for t in 0..<triangleCount { let (a, b, x) = triangle(t); for e in [ekey(a, b), ekey(b, x), ekey(x, a)] { c[e, default: 0] += 1 } }
        return c.values.filter { $0 >= 3 }.count
    }

    /// Ordered boundary loops (rings of open edges — edges used by exactly one triangle). Deterministic:
    /// seeds and neighbours are taken in sorted order so loop chaining is reproducible run-to-run.
    func boundaryLoops() -> [[UInt32]] {
        var edgeCount: [UInt64: Int] = [:]
        for t in 0..<triangleCount { let (a, b, c) = triangle(t); for e in [ekey(a, b), ekey(b, c), ekey(c, a)] { edgeCount[e, default: 0] += 1 } }
        let boundary = edgeCount.filter { $0.value == 1 }.keys
        guard !boundary.isEmpty else { return [] }
        var remaining = Set<UInt64>(boundary)
        var nbr: [UInt32: [UInt32]] = [:]
        for e in boundary { let a = UInt32(e >> 32), b = UInt32(e & 0xffff_ffff); nbr[a, default: []].append(b); nbr[b, default: []].append(a) }
        for k in Array(nbr.keys) { nbr[k]?.sort() }
        var loops: [[UInt32]] = []
        for seed in boundary.sorted() where remaining.contains(seed) {
            let sa = UInt32(seed >> 32), sb = UInt32(seed & 0xffff_ffff); remaining.remove(seed)
            var loop: [UInt32] = [sa, sb], prev = sa, cur = sb
            while cur != sa {
                let opts = (nbr[cur] ?? []).filter { $0 != prev && remaining.contains(ekey(cur, $0)) }
                guard let nx = opts.first ?? (nbr[cur] ?? []).first(where: { remaining.contains(ekey(cur, $0)) }) else { break }
                remaining.remove(ekey(cur, nx)); if nx == sa { break }
                loop.append(nx); prev = cur; cur = nx
                if loop.count > boundary.count + 2 { break }
            }
            if loop.count >= 3 { loops.append(loop) }
        }
        return loops
    }

    /// Resolve non-manifold edges by orientation only — drop the extra faces at each edge shared by 3+
    /// triangles, keeping one traversal each way. Iterates (removals can expose new non-manifold edges).
    func resolveNonManifoldEdges() -> MeshHeal {
        guard nonManifoldEdgeCount > 0 else { return self }
        var faces: [(UInt32, UInt32, UInt32)] = (0..<triangleCount).map { triangle($0) }
        for _ in 0..<8 {
            var byEdge: [UInt64: [(face: Int, fwd: Bool)]] = [:]
            for (i, f) in faces.enumerated() { for (x, y) in [(f.0, f.1), (f.1, f.2), (f.2, f.0)] { byEdge[ekey(x, y), default: []].append((i, x < y)) } }
            var drop = Set<Int>()
            for (_, fs) in byEdge where fs.count > 2 {
                var keptFwd = false, keptBwd = false
                for entry in fs where !drop.contains(entry.face) {
                    if entry.fwd && !keptFwd { keptFwd = true }
                    else if !entry.fwd && !keptBwd { keptBwd = true }
                    else { drop.insert(entry.face) }
                }
            }
            if drop.isEmpty { break }
            faces = faces.enumerated().filter { !drop.contains($0.offset) }.map { $0.element }
        }
        var idx: [UInt32] = []; idx.reserveCapacity(faces.count * 3)
        for f in faces { idx.append(f.0); idx.append(f.1); idx.append(f.2) }
        return MeshHeal(positions: positions, indices: idx)
    }

    /// Drop duplicate / coincident triangles (exact repeats and opposite-wound coincident faces) and
    /// triangles with a repeated vertex. Keeps the first occurrence of each unordered vertex triple.
    func removingDuplicateFaces() -> MeshHeal {
        var seen = Set<SIMD3<UInt32>>()
        var out: [UInt32] = []; out.reserveCapacity(indices.count)
        for t in 0..<triangleCount {
            let (a, b, c) = triangle(t); let s = [a, b, c].sorted()
            if s[0] == s[1] || s[1] == s[2] { continue }
            if seen.insert(SIMD3<UInt32>(s[0], s[1], s[2])).inserted { out.append(a); out.append(b); out.append(c) }
        }
        return out.count == indices.count ? self : MeshHeal(positions: positions, indices: out)
    }

    /// Generalized winding number at `p` (Jacobson et al. 2013): ≈1 inside a closed mesh, 0 outside;
    /// degrades gracefully on open / non-manifold input.
    func generalizedWindingNumber(_ p: SIMD3<Double>) -> Double {
        var omega = 0.0
        for t in 0..<triangleCount {
            let (a, b, c) = trianglePositions(t)
            let av = SIMD3<Double>(a) - p, bv = SIMD3<Double>(b) - p, cv = SIMD3<Double>(c) - p
            let la = simd_length(av), lb = simd_length(bv), lc = simd_length(cv)
            if la < 1e-12 || lb < 1e-12 || lc < 1e-12 { continue }
            let num = simd_dot(av, simd_cross(bv, cv))
            let den = la * lb * lc + simd_dot(av, bv) * lc + simd_dot(bv, cv) * la + simd_dot(cv, av) * lb
            omega += 2.0 * atan2(num, den)
        }
        return omega / (4.0 * Double.pi)
    }

    /// Remove internal-membrane faces (material on BOTH sides per the winding number) and degenerate
    /// faces, then resolve residual non-manifold edges. O(faces²) — guarded to small bodies.
    func repairedManifold(maxFaces: Int = 6000) -> MeshHeal {
        guard nonManifoldEdgeCount > 0, triangleCount <= maxFaces, let bb = bounds else { return self }
        let eps = max(Double(simd_length(bb.max - bb.min)) * 0.004, 1e-4)
        var keep = [Bool](repeating: true, count: triangleCount)
        for t in 0..<triangleCount {
            let (a, b, c) = trianglePositions(t)
            let ad = SIMD3<Double>(a), bd = SIMD3<Double>(b), cd = SIMD3<Double>(c)
            let nrm = simd_cross(bd - ad, cd - ad)
            guard simd_length(nrm) > 1e-14 else { keep[t] = false; continue }
            let ctr = (ad + bd + cd) / 3, n = simd_normalize(nrm)
            if min(generalizedWindingNumber(ctr + eps * n), generalizedWindingNumber(ctr - eps * n)) > 0.5 { keep[t] = false }
        }
        var idx: [UInt32] = []
        for t in 0..<triangleCount where keep[t] { let (a, b, c) = triangle(t); idx.append(a); idx.append(b); idx.append(c) }
        guard idx.count >= 12, idx.count < indices.count else { return self }
        return MeshHeal(positions: positions, indices: idx).resolveNonManifoldEdges()
    }

    /// Distance to the nearest triangle the ray crosses (Möller–Trumbore), or nil within `maxDist`.
    func firstRayHit(origin: SIMD3<Double>, direction: SIMD3<Double>, maxDist: Double = .greatestFiniteMagnitude, eps: Double = 1e-4) -> Double? {
        let d = simd_normalize(direction)
        var best = maxDist, found = false
        for t in 0..<triangleCount {
            let (a, b, c) = trianglePositions(t)
            let v0 = SIMD3<Double>(a), e1 = SIMD3<Double>(b) - v0, e2 = SIMD3<Double>(c) - v0
            let pv = simd_cross(d, e2), det = simd_dot(e1, pv)
            if abs(det) < 1e-12 { continue }
            let inv = 1.0 / det, tv = origin - v0
            let bu = simd_dot(tv, pv) * inv
            if bu < -1e-9 || bu > 1 + 1e-9 { continue }
            let qv = simd_cross(tv, e1), bv = simd_dot(d, qv) * inv
            if bv < -1e-9 || bu + bv > 1 + 1e-9 { continue }
            let tt = simd_dot(e2, qv) * inv
            if tt > eps && tt < best { best = tt; found = true }
        }
        return found ? best : nil
    }
}

/// Symmetric 3×3 eigen-decomposition + covariance, in Double for stability. Internal to the package.
enum Linalg {
    static func eigenSymmetric3(_ input: [[Double]]) -> (values: [Double], vectors: [[Double]]) {
        var a = input
        var v: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        let pairs = [(0, 1), (0, 2), (1, 2)]
        for _ in 0..<60 {
            var (p, q) = (0, 1); var off = abs(a[0][1])
            for (i, j) in pairs where abs(a[i][j]) > off { off = abs(a[i][j]); p = i; q = j }
            if off < 1e-15 { break }
            let phi = 0.5 * atan2(2 * a[p][q], a[q][q] - a[p][p]); let c = cos(phi), s = sin(phi)
            for k in 0..<3 { let akp = a[k][p], akq = a[k][q]; a[k][p] = c * akp - s * akq; a[k][q] = s * akp + c * akq }
            for k in 0..<3 { let apk = a[p][k], aqk = a[q][k]; a[p][k] = c * apk - s * aqk; a[q][k] = s * apk + c * aqk }
            for k in 0..<3 { let vkp = v[k][p], vkq = v[k][q]; v[k][p] = c * vkp - s * vkq; v[k][q] = s * vkp + c * vkq }
        }
        var triples = (0..<3).map { (a[$0][$0], [v[0][$0], v[1][$0], v[2][$0]]) }
        triples.sort { $0.0 < $1.0 }
        return (triples.map { $0.0 }, triples.map { normalize3($0.1) })
    }
    static func covariance(_ points: [SIMD3<Double>]) -> (matrix: [[Double]], centroid: SIMD3<Double>) {
        guard !points.isEmpty else { return ([[0, 0, 0], [0, 0, 0], [0, 0, 0]], .zero) }
        var c = SIMD3<Double>.zero
        for p in points { c += p }; c /= Double(points.count)
        var m = [[0.0, 0, 0], [0, 0, 0], [0, 0, 0]]
        for p in points { let d = p - c
            m[0][0] += d.x * d.x; m[0][1] += d.x * d.y; m[0][2] += d.x * d.z
            m[1][1] += d.y * d.y; m[1][2] += d.y * d.z; m[2][2] += d.z * d.z }
        m[1][0] = m[0][1]; m[2][0] = m[0][2]; m[2][1] = m[1][2]
        return (m, c)
    }
    static func normalize3(_ v: [Double]) -> [Double] {
        let len = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).squareRoot()
        return len > 1e-300 ? [v[0] / len, v[1] / len, v[2] / len] : [0, 0, 1]
    }
}
