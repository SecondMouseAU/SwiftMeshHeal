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

    @Test func throughOpeningSkipDeclinesOutOfRangeLoop() {
        // Regression for issue #4: `tier1Healed` applies a captured predicate across an evolving mesh
        // that grows during fan-fallback healing, so a later loop can carry indices beyond the pre-heal
        // mesh's `positions`. The predicate must decline such loops (→ fill), not index out of range.
        let m = cube(openTop: true)
        let skip = m.throughOpeningSkip()
        let outOfRange: [UInt32] = [0, 1, 2, 3, 4, UInt32(m.positions.count)]   // last index is appended
        #expect(skip(outOfRange) == false)
    }

    @Test func tier1HealedFactoryRebindsPredicatePerPass() {
        // The factory overload re-derives the predicate against the *current* mesh each pass, so a
        // position-reading predicate stays valid as healing grows the mesh (issue #4, option 2). The
        // factory is handed the evolving mesh; assert it never sees a loop index out of that mesh's
        // range, and that healing still closes the hole.
        let healed = cube(openTop: true).tier1Healed(skipLoopFor: { mesh in
            { loop in
                for vi in loop { #expect(Int(vi) < mesh.positions.count) }
                return mesh.throughOpeningSkip()(loop)
            }
        }).mesh
        #expect(healed.isWatertight)
    }

    @Test func degenerateSheetIsPassedThrough() {
        // A single quad (2 triangles, zero thickness) is not solidifiable.
        let sheet = MeshHeal(positions: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], indices: [0, 1, 2, 0, 2, 3])
        #expect(sheet.isDegenerateSheet)
        #expect(sheet.tier1Healed().mesh == sheet)
    }
}
