# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A pure-Swift, **dependency-free** Swift Package (`swift-tools-version: 6.0`, Swift 6 language mode,
macOS 12+/iOS 15+) for healing broken/non-watertight triangle meshes (STL bodies) into closed,
manifold solids — on-device, with no native build step and no third-party geometry libraries (no
OCCT/CGAL/GMP/Eigen). Only `simd` and the Swift stdlib are used.

The defining constraint: healing is **local and feature-preserving**. It fills defect holes but never
moves existing vertices, never remeshes, and leaves *intended* through-openings (windows, doors) open.
Keep any change consistent with that contract — a "fix" that distorts existing geometry or welds real
openings shut is a regression, not an improvement.

## Commands

```bash
swift build
swift test
swift test --filter tier1HealClosesTheHole   # single test by name (swift-testing @Test)
```

Tests use the **swift-testing** framework (`import Testing`, `@Test`/`@Suite`, `#expect`), not XCTest.

## Architecture

Two source files, both extending one value type. There is no class hierarchy or actor — `MeshHeal` is
a `Sendable, Equatable` struct of `positions: [SIMD3<Float>]` + `indices: [UInt32]` (welded, indexed
triangles). All operations are pure functions returning new values.

- **`Sources/SwiftMeshHeal/MeshHeal.swift`** — the core type plus geometry/topology primitives:
  metrics (`isWatertight`, `enclosedVolume`, `surfaceArea`, `pcaExtents`, `bounds`), topology
  (`boundaryLoops()`, `nonManifoldEdgeCount`, `resolveNonManifoldEdges()`, `removingDuplicateFaces()`,
  `repairedManifold()`), point/ray queries (`generalizedWindingNumber(_:)`, `firstRayHit(...)`), and an
  internal `Linalg` enum (Jacobi `eigenSymmetric3`, `covariance`) backing PCA.
- **`Sources/SwiftMeshHeal/HoleFill.swift`** — hole filling: `liepaFill(...)` (the Liepa 2003
  minimum-dihedral DP triangulation), `filledHoles(skipLoop:)`, the `tier1Healed(skipLoop:)` pipeline
  entry point, `throughOpeningSkip(...)`, and `isDegenerateSheet`.

### The `tier1Healed` pipeline (the main entry point)

`tier1Healed(skipLoop:)` is what callers use. It: optionally `repairedManifold()` (skipped above 6000
faces for cost) → `removingDuplicateFaces()` → iterates `filledHoles` until no further progress. Each
`filledHoles` pass walks `boundaryLoops()`, and for each loop either skips it (the `skipLoop`
predicate) or fills it via `liepaFill`, falling back to a centroid-fan for slits/cracks where the DP
fill fails.

Because the centroid-fan fallback **appends vertices**, the mesh grows across iterations. A `skipLoop`
predicate that reads positions (e.g. `throughOpeningSkip`) is therefore unsafe if bound once to the
pre-heal mesh — a later loop can carry indices beyond its `positions` (this was issue #4). Two layers
guard against it: `throughOpeningSkip` self-checks `Int($0) < positions.count`, and
`tier1Healed(skipLoopFor:)` takes a `(MeshHeal) -> ([UInt32]) -> Bool` factory that re-derives the
predicate against the current mesh each pass. Prefer the factory form for any position-reading
predicate; `tier1Healed(skipLoop:)` now just delegates with a constant factory.

### Key conventions to preserve

- **Edge keys are packed `UInt64`** (`(max << 32) | min`) for undirected-edge hashing — the recurring
  `ekey`/`key` helpers. Several methods redeclare a private `ekey`; keep them in sync.
- **Compute in `Double`, store in `Float`.** Positions are `Float`; nearly all geometry math promotes
  to `SIMD3<Double>` (`pos(_:)` does this). New numeric code should follow suit.
- **`liepaFill` forbids diagonals that collide with `existingEdges`** and uses boundary-face normals
  (`bndNormals`) to orient new triangles consistently with the surrounding surface. Don't drop either —
  they are why the fill stays manifold and correctly wound.
- **Defect vs. opening** is decided by `throughOpeningSkip` (real enclosed area + ray clears space on
  both sides ⇒ an opening, skip it). Tunable via `minArea`/`clearDist`.

## Releasing / docs

- DocC catalog lives in `Sources/SwiftMeshHeal/SwiftMeshHeal.docc/`; `.spi.yml` drives the Swift
  Package Index docs build for the `SwiftMeshHeal` target.
- Keep `CHANGELOG.md` (Keep a Changelog format, SemVer; pre-1.0 so minor versions may break API) and
  the README API surface in sync when public API changes.
- For Swift Package Index submission/removal, follow the issue-based process in the user's global
  CLAUDE.md — do **not** open a PR against `SwiftPackageIndex/PackageList`.
