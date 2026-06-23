# `MeshHeal` API reference

`MeshHeal` is a `public struct` (a `Sendable`, `Equatable` value type) representing a **welded,
indexed triangle mesh** — one connected body the healer operates on. It is the single public type
in SwiftMeshHeal; every operation below is a property or method on it.

```swift
import SwiftMeshHeal
```

All geometry is stored as `SIMD3<Float>` positions plus a flat `[UInt32]` index buffer (three
indices per triangle). The package has **no dependencies** (no OCCT, CGAL, GMP, or Eigen) and ships
as pure Swift on iOS arm64 and macOS.

<!-- 3D render TODO: broken vs healed mesh -->

---

## Construction

### `init(positions:indices:)`

```swift
public init(positions: [SIMD3<Float>], indices: [UInt32])
```

Create a mesh from a welded vertex array and a flat triangle-index buffer (3 indices per triangle).
Vertices are expected to be unique (welded); `indices` references them.

- **positions** — unique vertex coordinates.
- **indices** — `3 * triangleCount` vertex indices, one triangle per consecutive triple.

```swift
let positions: [SIMD3<Float>] = [
    SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0),
]
let indices: [UInt32] = [0, 1, 2, 0, 2, 3]   // two triangles forming a quad
let mesh = MeshHeal(positions: positions, indices: indices)
print(mesh.triangleCount)   // 2
```

---

## Counts and accessors

### `vertexCount` / `triangleCount`

```swift
public var vertexCount: Int { get }
public var triangleCount: Int { get }
```

Number of vertices, and number of triangles (`indices.count / 3`).

### `triangle(_:)`

```swift
public func triangle(_ t: Int) -> (UInt32, UInt32, UInt32)
```

The three vertex indices of triangle `t`.

### `trianglePositions(_:)`

```swift
public func trianglePositions(_ t: Int) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
```

The three vertex positions of triangle `t`.

### `triangleArea(_:)`

```swift
public func triangleArea(_ t: Int) -> Float
```

Area of triangle `t` (half the cross-product magnitude of two edges).

```swift
let mesh = MeshHeal(positions: positions, indices: indices)
for t in 0..<mesh.triangleCount {
    let (a, b, c) = mesh.triangle(t)
    print("tri \(t): verts \(a),\(b),\(c)  area \(mesh.triangleArea(t))")
}
```

---

## Measurements

### `bounds`

```swift
public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? { get }
```

Axis-aligned bounding box, or `nil` if the mesh has no vertices.

### `surfaceArea`

```swift
public var surfaceArea: Float { get }
```

Total surface area (sum of all triangle areas).

### `enclosedVolume`

```swift
public var enclosedVolume: Double { get }
```

Enclosed volume via the divergence theorem about the centroid. Meaningful only when the mesh is
watertight.

### `pcaExtents`

```swift
public var pcaExtents: SIMD3<Float> { get }
```

The body's size along its three principal axes (PCA), returned in **ascending** order of the
covariance eigenvalues. Useful for detecting thin / sheet-like bodies.

```swift
let mesh = MeshHeal(positions: positions, indices: indices)
if let bb = mesh.bounds {
    print("box: \(bb.min) … \(bb.max)")
}
print("area:", mesh.surfaceArea)
print("volume:", mesh.enclosedVolume)   // only meaningful once watertight
print("PCA extents:", mesh.pcaExtents)
```

---

## Topology queries

### `isWatertight`

```swift
public var isWatertight: Bool { get }
```

`true` iff every edge is shared by exactly two triangles (closed surface).

### `nonManifoldEdgeCount`

```swift
public var nonManifoldEdgeCount: Int { get }
```

Count of edges shared by 3 or more triangles. Zero means manifold (modulo open boundaries).

### `boundaryLoops()`

```swift
public func boundaryLoops() -> [[UInt32]]
```

Ordered boundary loops — rings of open edges (edges used by exactly one triangle). Deterministic:
seeds and neighbours are taken in sorted order, so loop chaining is reproducible run to run. Each
inner array is a cycle of vertex indices.

```swift
let mesh = MeshHeal(positions: positions, indices: indices)
let loops = mesh.boundaryLoops()
print("open boundary loops:", loops.count)
for loop in loops { print("  loop of \(loop.count) verts") }
print("watertight?", mesh.isWatertight)
print("non-manifold edges:", mesh.nonManifoldEdgeCount)
```

### `isDegenerateSheet`

```swift
public var isDegenerateSheet: Bool { get }
```

`true` for a degenerate micro-part: 4 or fewer triangles, or a near zero-thickness sheet / membrane
(smallest PCA extent under 1% of the largest). Such bodies have no volume to close, so the healer
passes them through unchanged.

---

## Cleanup operations

Each returns a **new** `MeshHeal` (value semantics — the receiver is unchanged).

### `removingDuplicateFaces()`

```swift
public func removingDuplicateFaces() -> MeshHeal
```

Drop duplicate / coincident triangles (exact repeats and opposite-wound coincident faces) and any
triangle with a repeated vertex. Keeps the first occurrence of each unordered vertex triple.

### `resolveNonManifoldEdges()`

```swift
public func resolveNonManifoldEdges() -> MeshHeal
```

Resolve non-manifold edges by orientation: at each edge shared by 3+ triangles, drop the extra
faces, keeping one traversal each way. Iterates (removals can expose new non-manifold edges).

### `repairedManifold(maxFaces:)`

```swift
public func repairedManifold(maxFaces: Int = 6000) -> MeshHeal
```

Remove internal-membrane faces (material on **both** sides per the generalized winding number) and
degenerate faces, then resolve residual non-manifold edges. O(faces²), so it is guarded to bodies
with `triangleCount <= maxFaces` and only runs when non-manifold edges exist.

```swift
let cleaned = mesh
    .removingDuplicateFaces()
    .resolveNonManifoldEdges()
    .repairedManifold()          // membrane removal on small bodies
print("non-manifold edges now:", cleaned.nonManifoldEdgeCount)
```

---

## Geometry primitives

### `generalizedWindingNumber(_:)`

```swift
public func generalizedWindingNumber(_ p: SIMD3<Double>) -> Double
```

Generalized winding number at point `p` (Jacobson et al. 2013): ≈ 1 inside a closed mesh, ≈ 0
outside. Degrades gracefully on open / non-manifold input — the basis for membrane detection.

```swift
let center = SIMD3<Double>(0.5, 0.5, 0.5)
let w = mesh.generalizedWindingNumber(center)
print(w > 0.5 ? "inside" : "outside")
```

### `firstRayHit(origin:direction:maxDist:eps:)`

```swift
public func firstRayHit(
    origin: SIMD3<Double>,
    direction: SIMD3<Double>,
    maxDist: Double = .greatestFiniteMagnitude,
    eps: Double = 1e-4
) -> Double?
```

Distance to the nearest triangle the ray crosses (Möller–Trumbore), or `nil` if nothing is hit
within `maxDist`. `direction` is normalized internally.

```swift
let hit = mesh.firstRayHit(
    origin: SIMD3<Double>(0, 0, -1),
    direction: SIMD3<Double>(0, 0, 1)
)
print(hit.map { "hit at \($0)" } ?? "clear")
```

---

## Hole filling

### `boundaryEdgeFaceNormals()`

```swift
public func boundaryEdgeFaceNormals() -> [UInt64: SIMD3<Double>]
```

For each boundary edge (used by exactly one triangle), the outward normal of that single existing
triangle, keyed by a packed edge key. Feed this to `liepaFill` as `bndNormals` so the fill matches
the existing surface orientation.

### `liepaFill(loop:bndNormals:existingEdges:)`

```swift
public func liepaFill(
    loop: [UInt32],
    bndNormals: [UInt64: SIMD3<Double>],
    existingEdges: Set<UInt64>
) -> [(UInt32, UInt32, UInt32)]?
```

Liepa (2003) **minimum-dihedral** triangulation of one boundary loop, using only the loop's own
vertices. A dynamic program over the boundary ring chooses the triangulation that minimises the
worst dihedral angle between adjacent patch faces (and against the existing rim faces), with area as
the tie-breaker. Forbids a diagonal that coincides with an existing mesh edge (which would make that
edge non-manifold).

- **loop** — one boundary loop, e.g. an element of `boundaryLoops()`.
- **bndNormals** — boundary-edge face normals from `boundaryEdgeFaceNormals()`.
- **existingEdges** — packed keys of all current mesh edges, so colliding diagonals are skipped.
- **Returns** the patch triangles, or `nil` if every triangulation needs a colliding diagonal
  (a slit / crack) — the higher-level `filledHoles` then falls back to a centroid fan.

```swift
let bnd = mesh.boundaryEdgeFaceNormals()
var existingEdges = Set<UInt64>()
for t in 0..<mesh.triangleCount {
    let (a, b, c) = mesh.triangle(t)
    func key(_ x: UInt32, _ y: UInt32) -> UInt64 { (UInt64(max(x, y)) << 32) | UInt64(min(x, y)) }
    existingEdges.insert(key(a, b)); existingEdges.insert(key(b, c)); existingEdges.insert(key(c, a))
}
if let loop = mesh.boundaryLoops().first,
   let patch = mesh.liepaFill(loop: loop, bndNormals: bnd, existingEdges: existingEdges) {
    print("filled with \(patch.count) triangles")
}
```

### `filledHoles(skipLoop:)`

```swift
public func filledHoles(
    skipLoop: ([UInt32]) -> Bool = { _ in false }
) -> (mesh: MeshHeal, filled: Int, skipped: Int, remainingUnfilled: Int)
```

Fill boundary-loop holes via `liepaFill`. **By default it fills every loop** (a part's missing back
is a defect, not an opening — size alone misclassifies it). When Liepa can't fill without a
colliding diagonal, it fans from a fresh centroid vertex (all-new spokes can't create non-manifold
edges). Pass `skipLoop` to protect intended openings (see `throughOpeningSkip`).

- **Returns** a tuple: the new `mesh`, the count `filled`, the count `skipped`, and
  `remainingUnfilled` (loops still open that were not skipped).

```swift
let result = mesh.filledHoles()
print("filled \(result.filled), skipped \(result.skipped), remaining \(result.remainingUnfilled)")
print("watertight now?", result.mesh.isWatertight)
```

---

## The healing entry point

### `tier1Healed(skipLoop:)`

```swift
public func tier1Healed(
    skipLoop: ([UInt32]) -> Bool = { _ in false }
) -> (mesh: MeshHeal, filled: Int, skipped: Int, remainingUnfilled: Int)
```

**THE preprocessing entry point.** Pipeline:

1. internal-membrane removal (`repairedManifold`, small bodies only) + duplicate-face removal,
2. iterate `resolveNonManifoldEdges` → `filledHoles` up to 3 times (each pass clears the prior
   pass's residual non-manifold edges), stopping early once watertight.

Degenerate sheets (`isDegenerateSheet`) are passed through unchanged — there is no volume to close.
Pass `skipLoop` to protect intended openings.

- **Returns** the same tuple shape as `filledHoles`: `(mesh, filled, skipped, remainingUnfilled)`.

```swift
var mesh = MeshHeal(positions: positions, indices: indices)
let healed = mesh.tier1Healed()
print("watertight?", healed.mesh.isWatertight)
print("filled \(healed.filled) holes; \(healed.remainingUnfilled) loops remain open")
```

### `throughOpeningSkip(minArea:clearDist:)`

```swift
public func throughOpeningSkip(
    minArea: Double = 6.0,
    clearDist: Double = 10.0
) -> ([UInt32]) -> Bool
```

Build a `skipLoop` predicate that **protects genuine through-openings** (a shell's windows / doors)
while still treating defects as fillable. A loop is judged an intended opening when it encloses real
planar area ≥ `minArea` **and** a ray through its centroid clears `clearDist` on both sides (it opens
into space, not into a thin part's near interior). Small parts never trigger it (rays hit nearby, so
they fill fully); the area gate keeps cracks classed as defects.

```swift
var mesh = MeshHeal(positions: positions, indices: indices)
let skip = mesh.throughOpeningSkip(minArea: 6.0, clearDist: 10.0)
let healed = mesh.tier1Healed(skipLoop: skip)
print("filled \(healed.filled), preserved openings: \(healed.skipped)")
```

<!-- 3D render TODO: shell with preserved windows vs naively welded-shut shell -->
