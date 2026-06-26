---
type: repo
title: SwiftMeshHeal
resource: https://github.com/SecondMouseAU/SwiftMeshHeal
tags: [mesh, healing, repair, stl, manifold, swift, kernel]
description: On-device, dependency-free triangle-mesh healing in pure Swift — broken STL bodies to closed, manifold solids.
timestamp: 2026-06-22
---

# SwiftMeshHeal

A pure-Swift, **dependency-free** triangle-mesh healer for Apple platforms (iOS arm64 + macOS).
It turns broken / non-watertight STL bodies into closed, manifold solids body-by-body — no OCCT,
no CGAL, no GMP, no Eigen, and no native build step. It is a *feature-preserving local* healer:
it fills defect holes, leaves intended openings open, never moves existing geometry, and runs in
milliseconds per body.

## Role in the ecosystem

- **Cluster:** kernel
- **Depends on:** nothing — a self-contained leaf library (no intra-org deps, no native deps).
- **Feeds products:** none declared yet; a lightweight on-device repair primitive consumable by
  any CAD/mesh pipeline that needs watertight bodies without the OCCT toolchain.

## Components

See [`components/`](components/index.md) — the single `SwiftMeshHeal` library target and its
public `MeshHeal` API surface.

## References

See [`references/`](references/index.md) — the Liepa (2003) hole-filling method, generalized
winding number, and the Swift Package Index page.

## Notes

- `tier1Healed()` is the headline pipeline: membrane removal (generalized winding number),
  duplicate/degenerate face removal, non-manifold edge resolution, then Liepa minimum-dihedral
  hole filling.
- Validated on a 278k-triangle, 3946-body railcar STL: closes ~99.8% of solidifiable bodies to
  watertight, ~ms/body, with 0 mm distortion of existing geometry.
- MIT licensed. Published to the Swift Package Index via `.spi.yml`.

## Policies

- [Query `context` first for OCCT / OCCTSwift docs](policies/context-first.md)
