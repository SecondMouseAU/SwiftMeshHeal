# Changelog

All notable changes to SwiftMeshHeal are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Pre-1.0: the API may change between minor
versions.

## [Unreleased]

### Added
- `tier1Healed(skipLoopFor:)` — a mesh-parameterized overload that re-derives the skip predicate
  against the current mesh before each fill pass. Because healing grows the mesh, a predicate captured
  against the original mesh (e.g. `throughOpeningSkip()`, which reads vertex positions) can be handed
  loops whose indices exceed its `positions`; rebinding per pass keeps it valid. Pass
  `{ $0.throughOpeningSkip() }`. ([#4](https://github.com/gsdali/SwiftMeshHeal/issues/4))

### Fixed
- `tier1Healed(skipLoop:)` no longer crashes with `Index out of range` on real multi-hole shells. The
  `throughOpeningSkip` predicate captures the pre-heal mesh, but `tier1Healed` applies it across an
  evolving mesh that grows when slits/cracks are fan-filled from a fresh vertex; the predicate now
  declines loops carrying appended (out-of-range) indices — they are fill artifacts, never genuine
  openings — instead of indexing out of bounds. ([#4](https://github.com/gsdali/SwiftMeshHeal/issues/4))

## [0.1.1] - 2026-06-14

### Added
- DocC documentation catalog and a full API reference landing page.
- `CHANGELOG.md`.

## [0.1.0] - 2026-06-14

Initial release. Pure-Swift, dependency-free, on-device triangle-mesh healing.

### Added
- `MeshHeal` value type (welded positions + indices) with `isWatertight`, `enclosedVolume`,
  `surfaceArea`, `pcaExtents`, `bounds`.
- Topology: `boundaryLoops()`, `nonManifoldEdgeCount`, `resolveNonManifoldEdges()`,
  `removingDuplicateFaces()`, `repairedManifold()`, `generalizedWindingNumber(_:)`,
  `firstRayHit(origin:direction:)`.
- **Liepa (2003) minimum-dihedral hole filling** — `liepaFill(loop:bndNormals:existingEdges:)` —
  handling non-planar holes, forbidding diagonals that collide with existing edges, with a centroid-fan
  fallback for slits/cracks.
- `filledHoles(skipLoop:)` and the `tier1Healed(skipLoop:)` preprocessing entry point.
- `throughOpeningSkip(minArea:clearDist:)` — protect genuine through-openings (windows/doors) by a
  ray + enclosed-area test, so they're left open instead of welded shut.
- `isDegenerateSheet` — route zero-thickness sheets / membranes past the healer.

### Notes
- Validated on a 278k-triangle, 3946-body reference STL: `tier1Healed` closes 99.8% of solidifiable
  bodies to watertight, ~ms/body, non-destructively (0 mm distortion of existing geometry), preserving
  intended openings.

[0.1.1]: https://github.com/gsdali/SwiftMeshHeal/releases/tag/v0.1.1
[0.1.0]: https://github.com/gsdali/SwiftMeshHeal/releases/tag/v0.1.0
