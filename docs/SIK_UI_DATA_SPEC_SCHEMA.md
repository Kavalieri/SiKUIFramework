# SiK UI data specification schema

The canonical schema is `catalog/schema/sik-ui-catalog-v1.schema.json`. It is a
closed JSON Schema: unknown fields are rejected at documented boundaries.

## Document kinds

### Framework manifest

`documentKind: framework-manifest`, `schemaId: sik-ui-catalog-v1`.

It declares the framework identity/version, events, profiles, runtime tokens,
layout modes/bindings, capabilities and public component definitions. It does
not contain product surface trees or product commands.

### Product surface specification

`documentKind: product-surface-spec`, `schemaId: sik-ui-catalog-v1`.

It belongs to a product repository and declares:

- a pinned `frameworkRef`;
- product repository/module ownership;
- a non-empty surface tree and supported profiles;
- assets with repository `sourcePath`, game-facing `runtimePath` and content hash;
- optional external surface references with logical repository ID, path and
  content hash;
- i18n entries;
- external action allowlists;
- typed data, mutable state and action-payload contracts;
- generated artifact, loader and reachable caller metadata.

Each component node declares `id`, `type`, `variant`, `layout`, `props`,
`actions`, `capabilities`, optional columns/options and children. Bindings are
portable data (`literal`, `data`, `i18n`, `asset` or `token`); executable
functions are not valid spec values. A `data` or `state` binding resolves only
when its exact path is declared. Every used action/event pair has a recursive
payload contract.

The manifest declares a closed event list per component. A globally recognised
event is invalid on a component that does not emit it; for example, Table
accepts `change` and `activate`, not `hover`, context-menu or drag events.

### Runtime surface artifact

The generator emits a data-only Lua table with:

```text
documentKind = sik-ui-runtime-surface
schemaId = sik-ui-runtime-v1
schemaVersion = 1
frameworkRef = { id, namespace, manifestVersion, manifestSha256 }
provenance = { schemaSha256, frameworkManifestSha256,
  surfaceSpecSha256, generatorSha256 }
```

The artifact includes only selected profiles, referenced runtime tokens, used
component factories and used capabilities, plus the product surface data,
surface references, runtime asset paths, i18n and action allowlist. The full editorial manifest is not emitted
into the game artifact.

## Layout

Every node has an obligatory data-only layout:

```json
{
  "mode": "column",
  "base": [
    { "name": "gap", "value": { "kind": "token", "ref": "spacing.8" } }
  ],
  "overrides": [
    { "profileId": "wide", "bindings": [
      { "name": "padding", "value": { "kind": "literal", "value": 16 } }
    ] }
  ]
}
```

Modes and binding names/value kinds are declared in the framework manifest.
Profile overrides may reference only profiles declared by both framework and
surface.

Layout is compositional. `row`, `column` and `grid` arrange direct children in
declaration order using the standard spacing tokens; `grow` creates flexible
space, while `justify` distributes the resulting group on its main axis.
`align-x` and `align-y` place any child on its two axes with
`start|center|end|stretch`; `align` and `vertical-align` remain readable aliases.
Explicit `x` and `y` are an exceptional escape hatch after composition, not a
normal authoring tool. Repeated use is a framework-gap signal: add the missing
piece or preset instead of teaching consumers to compensate with coordinates.
A consumer should therefore be able to add, remove or reorder pieces without
recalculating sibling coordinates.

Every component that accepts children is also a layout host. Hosts can be
nested recursively: a column may contain a two-column grid, either grid cell
may contain rows or further grids, and the complete tree reflows from its
owning viewport. `columns` accepts any positive count; changing it in a
responsive profile reorganizes the same child declarations. The host content
rectangle is authoritative, so descendants cannot overwrite its header,
footer, padding or scroll reservation. Ordinary product surfaces express
1..N-column and row/column organization through these layouts, never through
sibling coordinate calculations.

## Structural exclusivity

- `tabs.options[]` contains exactly one target: a stable local `contentId`
  resolving to a direct child, or a stable external `surfaceRef` resolving to
  a declared hash-pinned surface. Unreferenced or duplicate targets are invalid.
- `form` uses child `control` nodes or structured fields data, never both.
- `card-collection` uses child `card` nodes or items data, never both.
- `tooltip`, `menu` and `drag` do not accept child nodes.
- `table` owns rows, expansion and pagination internally.

### Declarative table policy and runtime adapters

Table behavior that is safe to serialize remains in capabilities. Local page
size is declared with `table.pagination`; hierarchy and child-pager presence
are declared with `table.expandable`. Optional lazy row behavior is declared
with `table.row-interactions` and its required adapter value
`context.tableOptions`.

The capability never carries functions, product commands or eager Tooltip,
Menu or Drag child nodes. A consuming runtime may provide callbacks and loaded
data at build time under `context.tableOptions[nodeId]`. This boundary does not
weaken schema validation: the spec still declares the Table, its columns, data
bindings and interaction policy, while the consumer remains responsible for
permissions, authoritative actions and external requests.

External pagination currently applies to children of an expanded parent. The
surface declares `table.expandable` with `child-pagination` and a local
`table.pagination` page size. The runtime adapter supplies
`pagination.external=true`, `pagination.stateOf` and
`pagination.onPageChange`. Those functions are deliberately absent from JSON.
External root-page loading is not part of the current contract.

These constraints are semantic validation rules even where JSON Schema alone
cannot express every cross-reference.

## Manifest lifecycle: `staged` to runtime

A product surface begins as `staged`. This is a deliberately incomplete
delivery state, not a runtime fallback and not an accepted surface. In this
state the validator must close every data and ownership boundary that can be
verified without mounting the product UI:

1. document/schema and closed-shape validation;
2. framework manifest, component/event and capability compatibility;
3. stable, non-empty `surfaceId`, tree, parent/child and target resolution;
4. logical repository, owner/caller, i18n, action and asset resolution;
5. declared asset, external-surface, framework-manifest, schema, surface-spec
   and generator hashes; and
6. generated artifact subset and provenance validation.

The only boundary deliberately omitted while a surface is `staged` is the
**runtime loader boundary**: generated module presence, `require`, builder
construction and caller-to-loader reachability in the consuming product. It
remains omitted only until that product receives visual/runtime validation; it
is not optional and cannot be replaced by a preview render.

Any `staged` surface blocks the affected candidate from certification and
cannot yield `QA_READY`. Promotion to a runtime candidate requires closing the
loader boundary, then completing the product's visual and runtime validation.
The framework does not promote a surface automatically.

## Validation stages

Full validation of a runtime candidate performs:

1. document and closed-shape validation;
2. framework manifest validation;
3. non-empty tree and parent/child validation;
4. props, layout, columns, options and capability validation;
5. logical repository, owner, caller, referenced surface, asset, i18n, token
   and action resolution;
6. exact component/event compatibility and typed data/state/action payloads;
7. runtime artifact location, require-safe module ID, loader require/builder
   evidence and caller-to-loader reachability (the boundary omitted by
   `staged` validation);
8. runtime artifact subset and provenance validation.

The editor imports and exports the same product spec shape. File System Access
is used only with explicit user permission; JSON import/export is the fallback
and local storage is a non-authoritative draft.

Filesystem resolution always receives an explicit logical repository map.
Specs never carry absolute paths, and validators reject unknown repository IDs,
path traversal and targets outside the mapped root.

Normal validation requires the declared runtime artifact to exist. Default
generation first validates the internal metadata-only input boundary, emits the
artifact at the declared repository-relative path and repeats validation with
the final `required` runtime policy. Generation invoked explicitly with
`--runtime-policy staged` instead uses the staged-input boundary before writing
and repeats `staged` validation afterwards; it never closes loader/caller
reachability. The runtime module ID must be a slash-separated Lua `require` ID
whose segments are valid identifiers, and `modulePath` must end in
`<moduleId>.lua`.

## Generator guarantees and limits

For identical ordered inputs and generator sources, generation is
deterministic. Generated HTML, Lua and companion provenance record hashes. The
HTML output is a structural renderer of declared components and bindings; it
does not by itself reproduce every Project Zomboid widget or certify visual
parity. The Lua output is data only and does not embed product commands,
editor-only contracts or loader metadata. State bindings are projected to data
bindings and asset `runtimePath` becomes the runtime artifact `path`.
