# ``SwiftMeshHeal``

On-device, dependency-free triangle-mesh healing in pure Swift.

## Overview

SwiftMeshHeal turns broken / non-watertight STL bodies into closed, manifold solids — body by body —
embedded on **iOS arm64 and macOS** with no OCCT, no CGAL, no GMP, no Eigen, and no native build step.

It is a **feature-preserving, local** healer, not a volumetric one: it fills genuine defect holes,
leaves intended openings open, never moves existing geometry, and runs in milliseconds per body.

```swift
import SwiftMeshHeal

let mesh = MeshHeal(positions: positions, indices: indices)   // welded, indexed triangles
let healed = mesh.tier1Healed().mesh                          // closed + manifold (where solidifiable)
```

### Preserving intended openings

A part's missing back is a *defect* (fill it); a shell's window is an *opening* (keep it). Size alone
can't tell them apart — both can be large. Pass a predicate to protect genuine through-openings:

```swift
let skip = mesh.throughOpeningSkip()                         // real area + ray clears space both sides
let healed = mesh.tier1Healed(skipLoop: skip).mesh
```

### How `tier1Healed` works

1. Remove internal-membrane faces (generalized winding number) and duplicate / degenerate faces.
2. Resolve non-manifold edges (iterated resolve→fill, so each pass clears the prior pass's leftovers).
3. Fill every boundary loop with **Liepa (2003) minimum-dihedral** triangulation — handling non-planar
   holes, forbidding diagonals that would collide with existing edges, and fanning from a fresh vertex
   for slits/cracks.
4. Pass degenerate zero-thickness sheets through unchanged (not solidifiable).

## Topics

### Essentials

- ``MeshHeal``
- ``MeshHeal/tier1Healed(skipLoop:)``

### Selective hole filling

- ``MeshHeal/filledHoles(skipLoop:)``
- ``MeshHeal/liepaFill(loop:bndNormals:existingEdges:)``
- ``MeshHeal/throughOpeningSkip(minArea:clearDist:)``
- ``MeshHeal/boundaryEdgeFaceNormals()``

### Topology & repair primitives

- ``MeshHeal/boundaryLoops()``
- ``MeshHeal/nonManifoldEdgeCount``
- ``MeshHeal/resolveNonManifoldEdges()``
- ``MeshHeal/removingDuplicateFaces()``
- ``MeshHeal/repairedManifold(maxFaces:)``
- ``MeshHeal/generalizedWindingNumber(_:)``
- ``MeshHeal/firstRayHit(origin:direction:maxDist:eps:)``
- ``MeshHeal/isDegenerateSheet``

### Measuring a mesh

- ``MeshHeal/isWatertight``
- ``MeshHeal/enclosedVolume``
- ``MeshHeal/surfaceArea``
- ``MeshHeal/pcaExtents``
- ``MeshHeal/bounds``
