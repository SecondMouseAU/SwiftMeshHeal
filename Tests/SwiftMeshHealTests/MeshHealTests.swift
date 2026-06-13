import Testing
import simd
@testable import SwiftMeshHeal

/// A unit cube as 8 vertices + 12 triangles, optionally omitting the +Z top face (a square hole).
private func cube(openTop: Bool) -> MeshHeal {
    let p: [SIMD3<Float>] = [
        [0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],   // 0..3 bottom (z=0)
        [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1],   // 4..7 top (z=1)
    ]
    var f: [UInt32] = [
        0, 2, 1, 0, 3, 2,   // bottom
        0, 1, 5, 0, 5, 4,   // -Y
        1, 2, 6, 1, 6, 5,   // +X
        2, 3, 7, 2, 7, 6,   // +Y
        3, 0, 4, 3, 4, 7,   // -X
    ]
    if !openTop { f += [4, 5, 6, 4, 6, 7] }   // +Z top
    return MeshHeal(positions: p, indices: f)
}

@Suite("MeshHeal hole filling")
struct MeshHealTests {
    @Test func closedCubeIsWatertight() {
        #expect(cube(openTop: false).isWatertight)
    }

    @Test func openCubeHasOneBoundaryLoop() {
        let m = cube(openTop: true)
        #expect(!m.isWatertight)
        #expect(m.boundaryLoops().count == 1)
        #expect(m.boundaryLoops().first?.count == 4)   // the square rim
    }

    @Test func tier1HealClosesTheHole() {
        let healed = cube(openTop: true).tier1Healed().mesh
        #expect(healed.isWatertight)
        #expect(healed.nonManifoldEdgeCount == 0)
        // Volume of the unit cube is recovered (the fill only adds the missing cap).
        #expect(abs(healed.enclosedVolume - 1.0) < 1e-4)
    }

    @Test func fillIsNonDestructive() {
        // Every original vertex is still present and at its original position after healing.
        let raw = cube(openTop: true)
        let healed = raw.tier1Healed().mesh
        for p in raw.positions { #expect(healed.positions.contains(p)) }
    }

    @Test func degenerateSheetIsPassedThrough() {
        // A single quad (2 triangles, zero thickness) is not solidifiable.
        let sheet = MeshHeal(positions: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], indices: [0, 1, 2, 0, 2, 3])
        #expect(sheet.isDegenerateSheet)
        #expect(sheet.tier1Healed().mesh == sheet)
    }
}
