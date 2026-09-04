# SiK UI standalone catalog

This directory owns framework schemas, canonical component definitions,
deterministic generators and the data-first editor. It does not own product
surface specifications and is never loaded wholesale by Project Zomboid.

## Documents

- `schema/sik-ui-catalog-v1.schema.json`: closed JSON Schema for framework
  manifests and product surface specs. A technical surface root must contain
  at least one child.
- `manifests/sik-ui-framework.manifest.json`: framework-only profiles, tokens,
  events, capabilities and component contracts.
- `validator/validate.js`: staged structural and reference validation.
- `generator/generate.js`: deterministic HTML and minimal Lua data generation.
- `editor/editor.html`: data-first editor for product-owned surface specs.

Product specs contain owner/caller references, typed data/state/action
contracts, explicit source/runtime asset paths, runtime loader metadata, i18n
and action allowlists. They remain in the owning product repository. The fixtures under
`tests/catalog/` exercise the portable contract without becoming product
specifications of the framework.

The public contract is consolidated in `docs/SIK_UI_DATA_SPEC_SCHEMA.md` and
`docs/SIK_UI_COMPONENT_CATALOG.md`. This file is the tooling quick reference.

`table-row`, expandable rows and pagers are not public component types.
`SiK.UI.Table.create` is the sole table constructor; columns are part of the
Table node and expansion/pagination are typed Table capabilities.

The closed public node vocabulary in v1 is:

- `window`, `container`, `scroll`, `virtual-list`, `table`, `block`, `form`,
  `card`, `card-collection`, `collection`, `action-group`, `tooltip`, `menu`,
  `drag` and `control`;
- `Layout`, `Theme` and `Icon` remain framework facilities rather than surface
  nodes;
- `control` is the sole declarative control type and delegates to
  `SiK.UI.Controls.create`; its closed `kind` selects button, icon button,
  field, combo, search, toggle, status, feedback or section title;
- navigation is a capability of `container`; its options target stable direct
  child containers and delegate internally to `SiK.UI.Navigation`/`Tabs`;
- the legacy `tabs` node remains accepted only as a migration compatibility
  input and is not emitted by new product specifications;
- headers, footers, modal chrome, rows, expansion and pagers remain typed
  configuration owned by the nearest public facility. They do not gain
  independent factories merely to make the editor convenient.

Every component node carries a required layout object:

```json
{
  "mode": "column",
  "base": [{ "name": "gap", "value": { "kind": "token", "ref": "spacing.8" } }],
  "overrides": [{ "profileId": "wide", "bindings": [{ "name": "padding", "value": 16 }] }]
}
```

Normal authoring composes nested pieces rather than calculating coordinates.
Rows and columns preserve declaration order, `grow` provides flexible spacers,
`justify` packs the group and `align-x`/`align-y` choose
`start|center|end|stretch`. The framework's canonical padding and gap are the
safe visual defaults. `x`/`y` are an exceptional escape hatch; repeated use
must be treated as a missing framework piece or preset.

Composition is recursive. Any child-hosting piece can contain another
row/column/grid host, including grids with 1..N columns selected by a responsive
profile. Each host lays out only its own content rectangle; descendants never
need to know or compensate for ancestor chrome, padding or scrollbars. If a
common arrangement needs tuned coordinates, the framework is missing a preset
or component and must be extended before offsets are duplicated in consumers.

Modes and binding names/value kinds come from the framework manifest. Profile
overrides may only reference declared profiles. HTML receives the same layout
as data attributes and deterministic media rules; Lua receives the unchanged
data object.

An action binding is always data-only:

```json
{ "event": "submit", "actionId": "product.submit" }
```

The accepted event vocabulary is `activate`, `change`, `submit`, `cancel`,
`hover`, `contextmenu`, `dragstart`, `dragover`, `drop` and `dragcancel`.
Vocabulary support does not imply component support. Every component definition
has a closed `events` list and a binding is rejected unless its component
actually emits that event. The current matrix is: Window `cancel`;
VirtualList/Table `change, activate`; Form `change, submit`; Tooltip `hover`;
Menu `contextmenu`; Drag `dragstart, dragover, drop, dragcancel`; Control
`activate, change, submit`; Container `change`; CardCollection, Collection and
ActionGroup `activate`; Scroll and Block emit none. The framework never stores product commands;
`actionId` resolves through the product allowlist and every used action/event
pair declares its payload contract.

Bindings with `kind: data` and `kind: state` resolve only when the product
declares the exact path in `contracts.data` or `contracts.state`. Contracts are
recursive (`string`, `number`, `boolean`, `object`, `array`, `any`) and may mark
values nullable. State is an editorial distinction; generation projects it to
the established runtime `data` binding without changing the visual tree.

Any host node can also declare a generic `state` group without pretending to
be a Tabs component. It names the default, the closed option set and the direct
children shown by one or more values. The generator emits the same
`data-state-option`/`data-state-view` semantics for HTML and preserves the
declaration in Lua data:

```json
{
  "state": {
    "default": "list",
    "options": ["list", "drop"],
    "views": [{ "contentId": "content", "values": ["list", "drop"] }]
  }
}
```

Assets declare both `sourcePath` (repository-relative file used for hash
verification) and `runtimePath` (the `media/...` path passed to the game). The
generated runtime artifact carries only the runtime path as its legacy `path`.

Table capabilities use the same data-only shape. In v1 they are
`table.expandable` (`expandable`, `depth`, `connectors`, `child-pagination`),
`table.pagination` (`page-size`) and `table.row-interactions` (lazy tooltip,
context-menu and drag policy). Row interactions declare policy only: the
consumer supplies callbacks and data through `context.tableOptions[nodeId]`;
they do not create eager Tooltip, Menu or Drag nodes. Local pagination is owned
by Table. Externally loaded child pages use the same adapter boundary and the
lifecycle documented in
[`SIK_UI_LIFECYCLE_AND_OWNERSHIP.md`](../docs/SIK_UI_LIFECYCLE_AND_OWNERSHIP.md).

Reusable internal configuration is expressed as capabilities rather than new
component types: `window.chrome`, `window.modal`, `container.navigation`,
`block.header`, `form.fields`, `card.actions`, `tooltip.vanilla-chain` and
`drag.ghost`. Modal remains a Window variant/capability.

Navigation options carry exactly one target: a stable local `contentId` that
resolves to one direct child Container, or a declared hash-pinned external
`surfaceRef`. Form uses
child controls or structured fields, never both.
CardCollection uses child cards or data-driven items, never both. Tooltip,
Menu and Drag are non-host nodes and therefore do not accept children.

Containers own layout and may nest only where composition requires it. A Card
is an atomic final widget, not a generic container: it may expose terminal
controls in declared slots, but it cannot contain Blocks, Tables, Tabs, other
Cards or CardCollections. Dashboards and product galleries are composed by
arranging multiple Cards in a parent Container or CardCollection. Prefer the
fewest useful containers; do not wrap a simple widget in a decorative Card only
to obtain spacing.

The generated Lua table starts with the closed identity
`documentKind=sik-ui-runtime-surface`, `schemaId=sik-ui-runtime-v1`,
`schemaVersion=1` and a pinned `frameworkRef`. `SiK.UI.Surface` can reject an
artifact before construction. Only used factories, capabilities and runtime
tokens are emitted; the editorial manifest never travels wholesale.

## Commands

```text
node tests/catalog/run-tests.js
node catalog/validator/validate.js --framework catalog/manifests/sik-ui-framework.manifest.json --surface <product-spec.json> --workspace-root <workspace> --repository-map <repository-map.json> [--runtime-policy staged]
node catalog/generator/generate.js --schema catalog/schema/sik-ui-catalog-v1.schema.json --framework catalog/manifests/sik-ui-framework.manifest.json --surface <product-spec.json> --workspace-root <workspace> --repository-map <repository-map.json> --out-dir <generated-dir> [--runtime-policy staged]
```

Repository IDs resolve only through the explicit repository map. Owner/caller
modules, referenced surfaces and assets resolve below their mapped root.
Validation rejects unknown IDs, traversal, escape from that root, missing
files/symbols and mismatched hashes before generation.

`runtime` is a required, enforceable boundary. It declares the generated
artifact repository, require-safe module ID and exact file location; the owner
module that loads it and invokes a `SiK.UI` builder; and the callers that reach
that loader. Normal validation requires the artifact to exist and checks all of
that evidence. Omitting `--runtime-policy` means `required`. Default generation
uses an internal metadata-only input pass, writes the artifact to its declared
location, then reruns the complete required boundary.

`--runtime-policy staged` is only for a surface waiting for product visual or
runtime validation. It still validates schema, ownership, assets, references,
the current artifact and provenance, but deliberately omits loader/builder and
caller reachability. Generation uses a staged-input pass before writing and a
staged pass afterwards. Staged output is not a fallback, cannot certify a
candidate and cannot yield `QA_READY`; the final gate must be rerun without the
flag after the product connects the exact surface through `SiK.UI.buildSurface`.

The editor supports File System Access when the browser grants permission and
falls back to JSON export/import. `localStorage` is only an explicit draft and
is never authoritative.

Generated HTML and Lua embed the same input provenance. A companion provenance
JSON records their final artifact hashes because a file cannot contain its own
hash without making the hash recursive.

Nothing in this catalog proves visual or runtime parity with the existing
validated mockups. Migration remains surface-by-surface.
