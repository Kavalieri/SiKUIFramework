# Changelog

All entries describe repository contents, not in-game certification of a
consumer surface.

## Unreleased

- Rebuilt the public documentation from the current standalone runtime rather
  than from the catalog alone.
- Added the public runtime reference for constructors, factories, lifecycle,
  error results, reflow and ownership.
- Corrected the Controls declarative entry point: direct runtime use is
  `SiK.UI.Controls.create(kind, options)`, while declarative `control` nodes
  are built through `SiK.UI.Builder`/`SiK.UI.Factories`.
- Aligned framework and ecosystem metadata to the owner-approved common
  compatibility floor: Project Zomboid Build 42.20+.
- Recorded the absence of a published license/contribution policy without
  inventing owner decisions.
- Kept every public contract in preview. This entry does not declare stability,
  product migration, HTML-to-Lua parity or QA readiness.

## 1.0.0-dev1

- Created the independent `SiKUIFramework` repository and publishable mod
  scaffold.
- Added the `SiK.UI` client runtime module set, preview manifest/schema,
  staged validator, deterministic generator and data-first editor.
- Added generated data-only runtime-surface artifacts with provenance fields.

This development entry does not declare any product UI visually equivalent or
accepted in game.
