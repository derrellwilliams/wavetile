---
paths:
  - "Packages/WavetileKit/Sources/DesignSystem/**"
  - "scripts/design-system.py"
  - "docs/design-system.html"
---

## Design system
`DesignSystem/` is the single source of truth for how the app looks; `docs/design-system.html` is its gallery, the reference for every token, icon and component.
- The gallery is generated, never hand-edited: `scripts/design-system.py` reads `Theme.swift` (palette, type, spacing, radius, artwork), `Motion.swift`, `Glyph.swift` with the `Icons.xcassets` SVGs, and `DesignSystem/Components`. It also scans the app's Swift files for each item's "Used in" list (file, line, code). Descriptions are the code's `///` doc comments, so document a token where it's defined.
- Changing the system: edit the token in code → run `scripts/design-system.py` → check the gallery (and the sim) → commit the code and the regenerated HTML together. `scripts/design-system.py --check` exits 1 if the page is stale.
- Views read tokens via `@Environment(\.theme)` (widgets: `Theme.dark`); don't add literal sizes, spacing, radii or hex colors to views. Type sizes live only in `Theme.Typography.scale`; the theme's fonts reference it. A new value goes into `Theme` first, with a doc comment.
- An item showing "No direct references found" is unused (or used in a way the scan doesn't match); confirm with the build before deleting it.
