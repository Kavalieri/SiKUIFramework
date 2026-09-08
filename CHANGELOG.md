# Changelog

All entries describe repository contents, not in-game certification of a
consumer surface.

## 1.0.1 - 2026-09-08

### Added

- Reusable scrollable descriptions and item annexes bounded by the viewport.

### Improved and fixed

- Mouse-relative tooltips with explicit element anchoring where appropriate.
- Control and table sizing, spacing and composition, alerts and progress indicators.
- Focus handling, Escape dismissal and cleanup for tooltip and annex surfaces.

## 1.0.0 — 2026-09-06

- Provides standalone reusable windows, tabs, tables, forms, menus and lifecycle management through `SiK.UI`.
- Rebuilt the public documentation from the current standalone runtime rather
  than from the catalog alone.
- Added the public runtime reference for constructors, factories, lifecycle,
  error results, reflow and ownership.
- Corrected the Controls declarative entry point: direct runtime use is
  `SiK.UI.Controls.create(kind, options)`, while declarative `control` nodes
  are built through `SiK.UI.Builder`/`SiK.UI.Factories`.
- Aligned framework and ecosystem metadata to the owner-approved common
  compatibility floor: Project Zomboid Build 42.20+.
- Published the source-available licence, contribution, security, maintenance
  and third-party notice set approved for the public repository.
- Published the first complete source-available framework contract. Individual
  product integrations remain subject to their own runtime compatibility.
