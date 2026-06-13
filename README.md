# SwiftMeshHeal

On-device, **dependency-free** triangle-mesh healing in pure Swift — turn broken / non-watertight STL
bodies into closed, manifold solids, body-by-body, embedded on **iOS arm64 + macOS** with no OCCT, no
CGAL, no GMP, no Eigen, no native build step.

## Why

Mesh-repair tools that "just work" (Netfabb, Polygonica, fTetWild, CGAL alpha-wrapping) are either
paid, GPL, server-side, or too heavy / too slow to embed in a shipping app — and the robust volumetric
ones **weld intended openings shut** (a railcar's windows) and remesh away the original triangulation.
SwiftMeshHeal is a feature-preserving *local* healer: it fills defect holes, leaves intended openings
open, never moves existing geometry, and runs in milliseconds per body.

## What it does

```swift
import SwiftMeshHeal

var mesh = MeshHeal(positions: positions, indices: indices)   // welded, indexed triangles
let healed = mesh.tier1Healed().mesh                          // closed, manifold (where solidifiable)
```

`tier1Healed()`:
1. removes internal-membrane faces (generalized winding number) and duplicate / degenerate faces,
2. resolves non-manifold edges (iterated),
3. fills every boundary loop with **Liepa (2003) minimum-dihedral** triangulation — handling non-planar
   holes, forbidding diagonals that collide with existing edges, and fanning from a fresh vertex for
   slits/cracks,
4. passes degenerate zero-thickness sheets through unchanged (not solidifiable).

### Preserving intended openings

A part's missing back is a *defect* (fill it); a shell's window is an *opening* (keep it). Pass a
predicate to protect genuine through-openings:

```swift
let skip = mesh.throughOpeningSkip()          // real area + ray clears space both sides = an opening
let healed = mesh.tier1Healed(skipLoop: skip).mesh
```

## API surface

- `MeshHeal(positions:indices:)`, `isWatertight`, `enclosedVolume`, `surfaceArea`, `pcaExtents`, `bounds`
- `boundaryLoops()`, `nonManifoldEdgeCount`, `resolveNonManifoldEdges()`, `removingDuplicateFaces()`
- `repairedManifold()`, `generalizedWindingNumber(_:)`, `firstRayHit(origin:direction:)`
- `liepaFill(loop:bndNormals:existingEdges:)`, `filledHoles(skipLoop:)`, `tier1Healed(skipLoop:)`
- `throughOpeningSkip(minArea:clearDist:)`, `isDegenerateSheet`

## Validation

On a 278k-triangle, 3946-body STL (a 1:80 railcar), `tier1Healed` closes **99.8%** of solidifiable
bodies to watertight, ~ms/body, non-destructively (0 mm distortion of existing geometry), while
preserving the shell's through-openings.

## License

MIT.
