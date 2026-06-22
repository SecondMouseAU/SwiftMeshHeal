---
type: reference
title: References index
resource: https://github.com/SecondMouseAU/SwiftMeshHeal
tags: [index, references]
description: Algorithms, prior art, and packaging references for SwiftMeshHeal.
timestamp: 2026-06-22
---

# References

- **Liepa (2003), "Filling Holes in Meshes"** — the minimum-dihedral-angle hole-triangulation
  method used by `liepaFill` / `tier1Healed`. (Eurographics Symposium on Geometry Processing.)
- **Generalized Winding Number** — Jacobson et al., used for internal-membrane detection and
  inside/outside classification (`generalizedWindingNumber(_:)`).
- **Prior-art contrast** — Netfabb, Polygonica, fTetWild, and CGAL alpha-wrapping are the heavy /
  paid / GPL / server-side robust healers this library is a lightweight, non-destructive
  alternative to.
- **Swift Package Index** — package page driven by `.spi.yml`
  (documentation target `SwiftMeshHeal`).
- **License** — MIT; see `LICENSE` in the repo root.
