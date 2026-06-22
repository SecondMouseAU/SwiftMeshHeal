---
type: component
title: Components index
resource: https://github.com/SecondMouseAU/SwiftMeshHeal
tags: [index, api]
description: SwiftMeshHeal public API — the MeshHeal value type and its healing pipeline.
timestamp: 2026-06-22
---

# Components

`SwiftMeshHeal` ships **one** public library product/target:

- **`SwiftMeshHeal`** (`.library`, target `SwiftMeshHeal`) — Swift 6 language mode, macOS 12+ /
  iOS 15+, no dependencies.

## Public API surface (`MeshHeal`)

The API is a value type `MeshHeal(positions:indices:)` over welded, indexed triangles.

- **Construction & metrics** — `MeshHeal(positions:indices:)`, `isWatertight`,
  `enclosedVolume`, `surfaceArea`, `pcaExtents`, `bounds`
- **Topology analysis & cleanup** — `boundaryLoops()`, `nonManifoldEdgeCount`,
  `resolveNonManifoldEdges()`, `removingDuplicateFaces()`, `repairedManifold()`
- **Geometric predicates** — `generalizedWindingNumber(_:)`, `firstRayHit(origin:direction:)`,
  `isDegenerateSheet`
- **Hole filling** — `liepaFill(loop:bndNormals:existingEdges:)`, `filledHoles(skipLoop:)`
- **Top-level pipeline** — `tier1Healed(skipLoop:)`
- **Opening preservation** — `throughOpeningSkip(minArea:clearDist:)` (a predicate that keeps
  genuine through-openings — e.g. windows — open while still filling defect holes)

## Healing pipeline (`tier1Healed`)

1. Remove internal-membrane faces (generalized winding number) + duplicate / degenerate faces.
2. Resolve non-manifold edges (iterated).
3. Fill every boundary loop with **Liepa (2003) minimum-dihedral** triangulation (non-planar
   holes, edge-collision-avoiding diagonals, fan-from-fresh-vertex for slits/cracks).
4. Pass degenerate zero-thickness sheets through unchanged (not solidifiable).
