---
type: policy
title: Code style
description: Swift naming/API shape follows the Swift API Design Guidelines, formatting follows Google's Swift Style Guide via swift-format, and doc comments stay terse; docs/ is the single source of truth for design rationale, not a second copy of it.
tags: [policy, style, swift, docs, agents]
timestamp: 2026-08-12
---

# Code style

**Naming and API shape** follow the
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) as-is:
clarity at the point of use over brevity, methods without side effects read as noun phrases,
methods with side effects as imperative verbs, boolean properties/methods read as assertions.

**Formatting and file layout** follow
[Google's Swift Style Guide](https://google.github.io/swift/), enforced by `swift-format`
(configured in `.swift-format`: 100-column limit, 4-space indent, the ecosystem's one deliberate
divergence from Google's own 2-space default, chosen to avoid a repo-wide reformat diff with no
readability gain). `swift-format lint --strict` is a blocking CI check
(`.github/workflows/code-style.yml`): formatting has no judgment call in it.

**SwiftLint is scoped to `orphaned_doc_comment` only** (`.swiftlint.yml`), not its full default
rule set. SwiftLint's defaults duplicate `swift-format`'s formatting opinions (and can disagree
with them on the same line) and add a large, separate surface of code-quality/complexity opinions
(`identifier_name`, `cyclomatic_complexity`, `function_body_length`, `nesting`, ...) that overlap
the ecosystem's own [code-structure](code-structure.md) policy rather than this one; a repo that
needs a structural pass runs one as its own scoped initiative, not as a side effect of a style-lint
gate. `orphaned_doc_comment` is the one rule left that catches something `swift-format` has no
equivalent for.

**Doc comments stay terse.** A `///` comment is a single-sentence summary plus only the
`Parameter`/`Returns`/`Throws` tags that add something the summary doesn't already say.
Design rationale, extended examples, and cross-references to prior issues belong in `docs/`, not
duplicated in source: `docs/` is the single source of truth for *why* and *how*, per
[GitLab's documentation style guide](https://docs.gitlab.com/development/documentation/styleguide/)
("share the link to the documentation instead of rephrasing the information"). This repo's
`docs/reference/MeshHeal.md` documents the `MeshHeal` type's own public surface directly; keep the
source doc comment's one-line summary and that page's lead sentence for the same symbol in
agreement when either changes.

**The comment:code ratio check is a nudge, not a gate.** `Scripts/comment-ratio-check.sh` flags
(never fails) a file whose comment lines outnumber its code lines: a high ratio is sometimes
legitimate, so it's a signal for review, not an automatic failure.

**No first-party C++ in this repo** (confirmed: pure Swift, no OCCT/CGAL/GMP/Eigen dependency, no
bridge layer), so the ecosystem proposal's `clang-format` tier does not apply here.

Why: this repo is small enough (~547 Swift lines across 4 files) to sweep into full compliance in
one PR rather than needing a gradual adoption mechanism, following the pattern already proven at
[OCCTSwiftScripts#114](https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/114) /
[OCCTSwiftScripts#115](https://github.com/SecondMouseAU/OCCTSwiftScripts/pull/115). Full research
and rationale:
[`ecosystem` docs/code-style-policy-proposal-2026-08.md](https://github.com/SecondMouseAU/ecosystem/blob/main/docs/code-style-policy-proposal-2026-08.md).
Filed and tracked as [SwiftMeshHeal#12](https://github.com/SecondMouseAU/SwiftMeshHeal/issues/12).

Ecosystem standard: see
[OKF-STANDARD.md](https://github.com/SecondMouseAU/ecosystem/blob/main/OKF-STANDARD.md).
