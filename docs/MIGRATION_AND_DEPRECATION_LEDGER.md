# Migration and deprecation ledger

This ledger distinguishes repository extraction from actual consumer
migration. A catalog entry or generated artifact does not mean that a product
surface has been migrated or accepted.

## Current ledger

| Item | State | Replacement / target | Removal condition |
|---|---|---|---|
| Standalone `SiK.UI` repository | preview | independent framework boundary | stable release criteria met |
| Framework manifest and schema v1 | preview | canonical declarative contract | versioned schema replacement |
| Catalog editor | preview tooling | product-owned JSON specs | editor workflow accepted |
| Deterministic HTML/Lua generator | preview tooling | common provenance pipeline | runtime consumer accepts artifact contract |
| Product surface marked `staged` | validation-only | runtime candidate after loader and visual/runtime gates | no staged surface remains in the candidate |
| Embedded Global Storage `GS_SiK_UI_*` helpers | removed in the current consumer working tree; not yet a released migration claim | standalone `SiK.UI` public root | product boundary and release gates remain green on the frozen candidate |
| Separate Global Storage TerminalScroll/Sections/TabRail modules | removed in the current consumer working tree; composition still exists in product owners | `Scroll`, `Block`, `Tabs` and `Window` capabilities | callers and surface parity are certified, not merely renamed or inlined |
| Global Storage `tab-options` declarative surface | `required`; generated runtime artifact has a reachable `SiK.UI.buildSurface` loader/caller | generated surface is the active declarative path | matching provenance plus product visual/runtime gates pass on the frozen candidate |
| Global Storage `tab-warehouse` declarative surface | `required`; generated runtime artifact has a reachable `SiK.UI.buildSurface` loader/caller | generated surface is the active declarative path | matching provenance plus product visual/runtime gates pass on the frozen candidate |
| Manure Manager `MM_UIChrome` | removed in the current product working tree | public `SiK.UI` components consumed by both custom surfaces | dependency, lifecycle and visual/runtime gates pass on the frozen candidate |
| Other product-local imperative composition | open migration debt | canonical framework component where applicable | every owning surface migrated or a justified vanilla bridge recorded |
| `GlobalStorageSiK.SiK_UI` namespace | no framework alias published; retired in the current product tree | none | boundary remains alias-free on the frozen candidate |

No legacy product implementation is removed merely because a replacement type
exists in the framework manifest.

The product states above are a 2026-09-01 working-tree audit, not release or
ingame evidence. Product repositories remain responsible for their exact
surface inventories and acceptance records; this ledger records migration
state without becoming a second owner of product UI.

## Per-surface migration record

Every migrated surface records:

- stable surface ID and owning product;
- previous owner/caller and replacement spec;
- framework manifest, schema, generator and surface spec hashes;
- generated HTML/Lua/provenance artifact hashes;
- action, asset and translation ownership;
- current integration status and outstanding runtime limitations;
- removal release for any temporary product adapter.

## Deprecation rules

Only documented public contracts can be deprecated. An entry names the exact
symbol or schema version, replacement, first warning release and removal
release. Warnings are bounded to once per consumer/session and never emitted
per frame or row.

Internal files and helpers may change without a public deprecation window, but
the owning repository must first remove all internal callers. Temporary legacy
adapters live in the consumer product, remain stateless and delegate to the
public API. The framework does not export a permanent legacy namespace.

## Documentation consolidation

The canonical public migration and deprecation contract is this ledger. The
older `MIGRATION.md` and `DEPRECATIONS.md` filenames remain as compatibility
links while external references are updated; they do not define separate
rules.
