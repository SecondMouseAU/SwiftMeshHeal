# Getting started: heal a broken mesh

SwiftMeshHeal turns broken / non-watertight triangle meshes into closed, manifold solids — pure
Swift, no native dependency, on iOS arm64 and macOS. This walkthrough builds a deliberately broken
mesh, heals it, and inspects the result. Every call below is a real API on the `MeshHeal` value type
(see the [API reference](../reference/MeshHeal.md)).

## 1. Add the package

In `Package.swift`:

```swift
.package(url: "https://github.com/SecondMouseAU/SwiftMeshHeal.git", from: "1.0.0")
```

and add `"SwiftMeshHeal"` to your target's dependencies. Then:

```swift
import SwiftMeshHeal
```

## 2. Construct a broken mesh

`MeshHeal` is a welded, indexed triangle mesh: unique `positions` plus a flat `[UInt32]` index
buffer (3 indices per triangle). Here we build the 8 corners of a unit cube but **omit the top two
triangles**, leaving an open square hole.

```swift
import SwiftMeshHeal
import simd

let positions: [SIMD3<Float>] = [
    SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0),   // bottom (z = 0)
    SIMD3(0, 0, 1), SIMD3(1, 0, 1), SIMD3(1, 1, 1), SIMD3(0, 1, 1),   // top    (z = 1)
]

// All six cube faces EXCEPT the top — a cube missing its lid (one open square hole).
let indices: [UInt32] = [
    0, 2, 1,  0, 3, 2,   // bottom
    // top (4,6,5 / 4,7,6) intentionally omitted -> one boundary loop
    0, 1, 5,  0, 5, 4,   // front
    1, 2, 6,  1, 6, 5,   // right
    2, 3, 7,  2, 7, 6,   // back
    3, 0, 4,  3, 4, 7,   // left
]

let broken = MeshHeal(positions: positions, indices: indices)
```

> Any single missing face leaves one boundary loop; add the top face (`4, 6, 5,  4, 7, 6`) back to
> get a closed cube.

## 3. Inspect the damage

```swift
print("watertight?       ", broken.isWatertight)          // false when a face is missing
print("boundary loops:   ", broken.boundaryLoops().count) // one loop per hole
print("non-manifold edges:", broken.nonManifoldEdgeCount) // 0 for this clean-but-open mesh
print("surface area:     ", broken.surfaceArea)
print("triangles:        ", broken.triangleCount)
```

<!-- 3D render TODO: broken cube with open lid -->

## 4. Heal it

`tier1Healed()` is the one-call entry point: it removes membranes and duplicate faces, resolves
non-manifold edges, and fills every boundary loop with a Liepa minimum-dihedral patch. It returns a
tuple — the new `mesh` plus counts.

```swift
let result = broken.tier1Healed()

print("filled holes:     ", result.filled)
print("skipped (openings):", result.skipped)
print("remaining open:   ", result.remainingUnfilled)
print("watertight now?   ", result.mesh.isWatertight)
print("enclosed volume:  ", result.mesh.enclosedVolume)   // meaningful once watertight
```

<!-- 3D render TODO: healed watertight cube -->

## 5. Preserve intended openings

A part's missing back is a *defect* (fill it); a shell's window is an *opening* (keep it).
`throughOpeningSkip()` returns a predicate that protects genuine through-openings — loops that
enclose real area and clear space on both sides — while still filling small defects. Pass it as
`skipLoop`:

```swift
var shell = MeshHeal(positions: positions, indices: indices)
let keepWindows = shell.throughOpeningSkip(minArea: 6.0, clearDist: 10.0)

let healed = shell.tier1Healed(skipLoop: keepWindows)
print("filled \(healed.filled) defects, preserved \(healed.skipped) openings")
```

<!-- 3D render TODO: shell healed with windows preserved -->

## 6. Step through the pipeline manually (optional)

For finer control you can call the stages yourself, all of which return new value-type meshes:

```swift
let cleaned = broken
    .removingDuplicateFaces()     // drop coincident / degenerate faces
    .resolveNonManifoldEdges()    // drop extra faces at 3+-shared edges
    .repairedManifold()           // remove internal membranes (small bodies)

let (filledMesh, filled, _, remaining) = cleaned.filledHoles()
print("filled \(filled), \(remaining) loops still open, watertight: \(filledMesh.isWatertight)")
```

## What next

- Full per-symbol reference: [`docs/reference/MeshHeal.md`](../reference/MeshHeal.md).
- The healer never moves existing geometry and runs in milliseconds per body, so it is safe to run
  body-by-body across a large multi-body STL before solidification.
