# SiK UI public API

`SiK.UI` is the sole public namespace of the standalone framework. It is a
preview client API. A consumer must not import `SiK/UI/*.lua` implementation
files as a private dependency, nor treat Global Storage or another product
namespace as a framework alias.

## Load and scope

Declare the exact ModID in the consuming mod metadata:

```text
require=SiKUIFramework
```

Then load the public client entry point:

```lua
require "SiK_UI"
local UI = SiK.UI
```

The publishable mod metadata declares `id=SiKUIFramework` and
`versionMin=42.20.0`. Runtime modules live under `media/lua/client`; the API is
therefore for client UI construction. It performs no server mutation or
authority check. Kava fixed Build 42.20+ as the shared minimum for the
framework and every SiK product/addon on 2026-09-01.

The framework dependency is explicit. If the ModID, entry point or public root
is unavailable, a consumer must stop constructing the affected surface and
report the dependency failure. The supported contract does not include an
embedded copy, hidden fallback, product-owned alias or automatic downgrade to
hand-painted controls.

## Bootstrap and declarative tree

| Entry point | Contract |
|---|---|
| `UI.bootstrap()` | Registers default factories/capabilities once. Returns `true` or `nil, reason`. It is called by `SiK_UI` load. |
| `UI.validateSurface(spec)` | Bootstraps then checks a data-only `sik-ui-runtime-surface`. Returns `true` or `false, reason`. |
| `UI.buildSurface(parent, spec, context)` | Bootstraps and builds a validated surface. Returns a tree or `nil, reason`; the caller owns `tree:dispose()`. |
| `UI.setTextResolver(fn)` / `UI.resolveText(key, fallback, ...)` | Installs/removes the optional local text resolver. `resolveText` falls back to `getText`, then fallback/key. |
| `UI.setObserver(fn)` / `UI.observe(name, payload)` | Installs/removes one optional observer for bounded framework events. Observer failures are isolated with `pcall`. |

`UI.buildSurface` rejects invalid specs with an error. Product action IDs resolve
through the supplied builder context; they are not network commands and must
remain product-owned.

## Public module families

| Family | Modules |
|---|---|
| Namespace/runtime | `Namespace`, `Version`, `Surface`, `Builder`, `Factories`, `Capabilities`, `Bindings` |
| Geometry/style | `Viewport`, `Metrics`, `Layout`, `Theme`, `Icon` |
| Composition/content | `Container`, `Block`, `Collection`, `Card`, `CardCollection`, `ActionGroup`, `Scroll`, `ScrollDock`, `VirtualList`, `Table`, `Form` |
| Surface host | `Window`, `Modal` |
| Interaction | `Controls`, `Tooltip`, `Feedback`, `Popover`, `Menu`, `Drag`, `DragGhost`, `DropTarget`, `WorldPicker`, `FocusStack`, `Lifecycle`, `State` |

`Container` is the recursive composition primitive. A root Container may own
header, navigation, content and footer regions; a nested Container may own the
same navigation capability for subviews. Every navigation option receives a
stable child Container host. `Navigation` and `Tabs` are low-level runtime
implementation/compatibility modules: product surfaces compose navigation via
`Container`, never by creating a parallel tab rail or manually hiding panels.

`Block` is a semantic section preset, `Collection` repeats data, `Card` is an
atomic final compound widget, and `ActionGroup` arranges related actions. A Card
does not host Containers, Tables or another navigation hierarchy.

The complete list of public constructors and facilities, including exact
option schemas, callbacks, reflow and disposal obligations, is in
[RUNTIME_REFERENCE.md](RUNTIME_REFERENCE.md).

Every callable `Module.symbol` exported on `SiK.UI` is treated as preview
public API until it is explicitly deprecated and removed. Source-file imports
remain private even when the resulting module table is public: consumers load
only `SiK_UI`, then access the documented namespace. The runtime reference has
an exhaustive export index so low-level geometry/render helpers cannot be
mistaken for undocumented internals. Functions described there as pure helpers
create no lifecycle owner; every constructor or attachment that returns an
owning handle documents its reflow/update and disposal path.

## Version and profile axes

Runtime and declarative compatibility use different identifiers:

- `SiK.UI.Version` and `mod.info` identify runtime `1.0.0`.
- `catalog/manifests/sik-ui-framework.manifest.json` identifies manifest
  `0.1.0-preview`; generated `frameworkRef.manifestVersion` pins that value.

They are not interchangeable and neither alone certifies product runtime
support. Build 42.20+ is the declared compatibility floor; actual runtime
acceptance still belongs to the integrated game/QA matrix.

Profile names are likewise scoped: the manifest exposes `compact`, `standard`
and `wide`; `Metrics.profile` additionally knows `terminal`, `editor` and
`staff`; `Window.profile` knows `terminal`, `editor` and `task` in addition to
its common profiles. A name supported by one layer is not automatically valid
in another. See the runtime reference for the complete matrix and fallback
behavior.

## Error and lifecycle convention

### Editable-field submission

`Controls.field` is a padded panel with one native text child, available as
`field.entry`. The panel and child retain distinct native identities and their
own vanilla instantiation lifecycle. Text, focus, selection and font operations
are explicitly forwarded; `javaObject`, `target` and `instantiate` are not aliases
of the child. Attach and resize the panel, not its text backend.

`UI.Controls.field(parent, { onSubmit = callback })` invokes the optional
callback only for that field's Enter submission, using the standard context
envelope (`value` is the current text). Disabled fields do not submit. The
consumer validates and stores the value; this does not imply a window-wide
default action, row activation, disclosure or confirmation.

`UI.Modal.input` shares its validation/acceptance path between the explicit
accept control and field submission. Invalid input stays open; an `onAccept`
result of `false` also keeps it open. `UI.Modal.confirm` does not inherit this
editable-field submission behaviour.

Both dialog constructors measure their body Blocks at the available width.
They use `ScrollDock` inside the modal content rectangle: the question or
input Block scrolls only when needed; the intrinsic Actions Block stays in
the fixed bottom host. The dock adds no second outer padding and owns the
single inter-block gap. Resizing remeasures wrapped text and the overflow
gutter; disposal releases both Blocks and the dock. A quantity input only
allocates its maximum control when a maximum exists. Its minus/plus controls
edit the field without submitting it; validation must return a truthy result
before acceptance proceeds.

`UI.Controls.effectiveSearchQuery(text, options)` returns `query, active`, with
`query=nil` below the same character threshold used by `Controls.search`
(default three regular characters or two wide characters). It performs no
filtering, scheduling or mutation; consumers retain their raw query separately
so clearing, resizing and changing filters do not lose the entered value.

`UI.Controls.dismissibleRow(parent, options)` constructs one atomic bordered
row with truncated left text and a `sik.close.18` removal control.  Options are
`text`, `tone`, `theme`, `tooltip`, `actionTooltip`, `onRemove`, `playerNum`,
`w`, `h` and `profile`; padding and gap default to 8.  The returned row owns
its close child and exposes `reflow(width)` plus idempotent `dispose()`.
`UI.Controls.dismissibleRowHeight(options)` returns its standard allocation.

### Inline child pager

`UI.Table.create` keeps `pagination` as its single pagination option.  When
`expansion` is present, it projects one inline pager row after each expanded
parent instead of reserving a table-global footer.  The row is structural:
it is not selectable, draggable, a tooltip item, a row-adapter callback or an
object/row total.

For external sources, provide `pagination={ pageSize=N, external=true,
stateOf=function(parent,parentKey,table) return state end,
onPageChange=function(context) end, labelOf=function(state,parent,parentKey,table)
return localizedText end }`.  `state` may contain `page`, `totalRows`,
`totalUnits`, `pending` and `stale`; `pending` or `stale` disable both arrows.
`context` is `{playerNum, component, parentKey, parent, page}`.  The framework
does not poll or fetch: `onPageChange` is declarative and the consumer refreshes
the rows when its state changes.  `labelOf` owns localization and plural rules;
without it the framework emits only a language-neutral numeric fallback.

Constructors return `instance` on success, or `nil, reason` for invalid inputs
or unsupported setup. Mutators return their instance/value on success, or
`nil, reason` where the runtime can reject the request. `dispose()` is
idempotent: first success returns `true`; a repeated call returns `false`.

An owner that creates a public instance must call its `dispose()` when the
consumer surface closes, is replaced or fails during construction. A Window
does not infer ownership of product children. A Builder tree owns handles that
it constructs or adopts according to its declared adoption contract.

## Staged surfaces and HTML-to-Lua boundary

A catalog surface marked `staged` is data that has passed schema, ownership,
asset and provenance validation while its runtime loader/caller boundary is
deliberately still open. It is not a runtime fallback, a compatibility promise
or evidence of visual parity. A staged surface cannot be a final candidate:
promotion requires the default `required` validator policy, a reachable loader
that calls `SiK.UI.buildSurface`, and the consuming product's own visual/runtime
validation.

Generated HTML is a deterministic structural preview of the same surface data.
It is not a second UI implementation and does not certify Project Zomboid
geometry or behaviour. Generated Lua is data-only; the product supplies the
validated host, context, actions and lifecycle.

## Bridges and adapters

A bridge is permitted only at a consumer boundary where an existing vanilla or
product-owned widget must be presented to a `SiK.UI` component. The bridge stays
in the consuming product, exposes bounded descriptors/callbacks, declares who
owns disposal and does not publish an alias for `SiK.UI` or import
`SiK/UI/*.lua` internals. It must not copy product authority, network commands
or persistence into the framework. Temporary migration adapters are explicit,
stateless delegates with a removal owner; they are not a second public API.

## Boundary with product APIs

`SiK.UI` is presentation and client-interaction infrastructure. It does not
replace the public product APIs:

- `GSSiK.API` for Global Storage SiK mechanics;
- `MMSiK.API` for Manure Manager SiK mechanics;
- `SCLGSiK.API` for SiK Corpse Loot Guard mechanics.

Before adding a product API, consumers should use an existing vanilla action
where it already meets the product contract. A product API must add reusable
product value; a UI callback must add reusable presentation/lifecycle value.
Neither is a wrapper that only renames one vanilla call.

## Exact product-surface ID note

`tab-options` is the only documented ID for that product surface. This
framework does not define aliases for it.
# Requirements

`SiK.UI.Requirements.create({parent, x, y, w, groups, profile, playerNum})`
returns `{panel, height, reflow(width), dispose()}`. Each ordered group has
`rows={{text, texture, state, tone}, ...}`. `state` uses the shared
`Controls.requirementRow` contract (`met`/`missing`). Product owns labels,
textures and classification; the framework owns all geometry.

Exactly two nonempty groups with at least four rows receive two untitled
Blocks. `Metrics.gridColumns(Viewport.resolve(playerNum))` stacks them below
900 viewport pixels wide or 700 high, matching the approved HTML media query.
Otherwise they sit side by side. `environment` optionally supplies the neutral
Viewport test adapter; consumers do not override margins or breakpoints.
Other group counts render one continuous list without dropping rows. Padding
and gap come from Block/Metrics. Height follows wrapped rows; no fill.
`reflow` replaces owned controls and updates `height`; callers position the
panel through their Block column and repeat enclosing layout after reflow.
Disposing the panel also disposes its handle, idempotently.
