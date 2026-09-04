# SiK UI lifecycle and ownership

Every visible component has exactly one runtime owner. Ownership includes
children, handlers, input capture, focus layers, pooled rows, tooltip state,
drag state and any scoped hook installed for that component.

## Lifecycle sequence

1. **validate**: reject invalid options, unresolved references and unsupported
   capabilities before creating visible state.
2. **create**: allocate the owning instance and its data-only configuration.
3. **mount**: attach children and install scoped handlers.
4. **reflow/update**: apply current bounds, profile/layout bindings or a
   declared data patch without fetching product state.
5. **hide/close**: stop visible interaction and release transient capture.
6. **dispose**: restore handlers and release all owned resources.

`dispose()` is idempotent. Success, failure, cancellation and owner removal use
the same cleanup path. A component must not rely on periodic polling to repair
leaked ownership.

`Lifecycle.bindVisibleRefresh(owner, options)` is the bounded exception for a
visible component that genuinely needs periodic refresh. It registers
`Events.OnTick` only while the owner is visible and the binding is active, and
removes it immediately on `setVisible(false)`, `setActive(false)` or
`dispose()`. If the event API is unavailable the handle reports `manual` mode;
the consumer must call `handle:refresh()` explicitly. Direct writes to an
owner's `visible` field are outside this contract: use `setVisible`.

`Lifecycle.bindHoverReveal(owner, options)` is the canonical hover-flyout
binding. It reuses the same visible-only lifecycle, considers both trigger
controls and the revealed target, falls back to absolute pointer hit-testing
when PZ has not updated `isMouseOver()` yet, and keeps a configurable number of
transition ticks before hiding. Products supply only the target, triggers,
optional visibility predicates and show/hide callbacks; they do not reproduce
hover polling or grace counters locally.

## Repository ownership

The framework repository owns:

- public component behavior and lifecycle;
- profiles, metrics, tokens and icon resolution;
- the closed manifest and schema;
- validator, generator and editor versions;
- data-only runtime artifact identity and provenance.

Each product repository owns:

- surface specs, owner/caller symbols and action allowlists;
- data sources, translations and product assets;
- permissions, network authority, persistence and mechanics;
- integration code that maps external `actionId` values to product behavior;
- surface-specific acceptance evidence.

An owner/caller declaration proves a reference exists during staged catalog
validation. It does not transfer runtime authority to the framework.

## Declarative manifest lifecycle

`staged` is the pre-runtime state for a product surface. It validates schema,
stable `surfaceId`, framework/component contracts, owner/caller references,
assets, external surface references and every declared provenance/hash field.
It intentionally omits only the consuming product's loader boundary
(`require`, builder construction and caller reachability) while the surface
waits for visual/runtime validation.

This omission is a gate, never a fallback. A `staged` surface blocks its
candidate from certification and cannot yield `QA_READY`; it must close the
loader boundary and then pass the product's visual/runtime validation before it
can be treated as a runtime candidate. The framework cannot infer that outcome
from generated HTML, a schema pass or a manifest hash.

## Player and input isolation

Visible focus and Escape layers are scoped by `playerNum`. Window visibility
and disposal unregister their installed layer; replacement cancels the prior
Drag session for that player. A product lifecycle handler must call
`FocusStack.clearPlayer(playerNum)` for death/reconnect cleanup because the
framework does not install product lifecycle hooks itself. When no SiK surface
is visible for a player, its scoped Escape wrapper delegates to the prior
vanilla handler.

An Escape pulse is armed and consumed on key-down. Its matching key-up schedules
the top-layer close for the immediately following UI tick, while the originating
layer remains the key consumer for the complete release dispatch. The one-shot
tick callback removes itself and is cancelled by disposal. Therefore one
physical pulse closes exactly one visible SiK layer and cannot continue into
vanilla pause handling.

An owned modal uses scoped z-order: activating its owner raises the visible
modal children immediately afterwards. Closing the last child restores the
owner's original `bringToTop` method. This relationship installs no polling and
does not force the modal above unrelated game UI.

Drag, modal and tooltip state belong to the active owning surface. A component
cannot install an unbounded global listener as its primary input path.
Popover and WorldPicker install a player-scoped transient Escape layer only
while they own visible interaction. DropTarget observes the existing
player-scoped Drag session and owns no global listener.
Popover may instead use a manual trigger or passive hover with focus disabled;
those modes still restore the control's prior handlers on disposal. DropTarget
may read a consumer-owned drag provider, but clears transient hover when its
control is hidden or removed and never assumes ownership of that provider.
WorldPicker multi-step capture releases the mouse between clicks while keeping
its player-scoped cancellation layer until completion, cancellation or disposal.

## Global hooks

A global vanilla hook is acceptable only when a scoped instance hook cannot
meet the public behavior. It must be installed once, preserve the existing
chain and have an explicit restoration or process-lifetime ownership policy.
Product-specific global hooks remain in the product repository.

## Declarative ownership

The `Builder.build` result owns records for every handle it constructs and
every explicitly adopted handle. `tree:update(contextPatch)` captures/restores
factory state where the factory declares that capability; `tree:reflow(bounds,
profileId)` is an update with a new viewport; `tree:dispose()` tears down the
tree and restores adoptions. A failed partial build is rolled back.

Tabs own selection state but not caller-supplied content. A tab target is a
separate local child by stable `contentId` or a declared external surface by
`surfaceRef`; the tab button does not own it. Table owns its rows, expansion,
pager and cell-action controls. Window owns header/footer/close chrome and its
focus layer, but never infers product-child ownership. Tooltip, Menu and Drag
are non-host nodes and own only their typed configuration and transient state.

## Table interaction and external-page lifecycle

`table.row-interactions` declares optional row policy; it does not create eager
Tooltip, Menu or Drag components. The Builder resolves
`context.tableOptions[nodeId]` once for the Table, and the consumer supplies any
row adapter callbacks or external data functions. This keeps the surface
artifact data-only and leaves permissions and action authority outside the
framework.

Reusable rows are updated as visible data changes. A row adapter must therefore
rebind by stable semantic key during `update`, avoid retaining stale item
references, and release any row-scoped attachment during `dispose`. Tooltip,
menu and drag state should be created only after the corresponding user
interaction and must be closed when the row is recycled, hidden or disposed.

For local pagination, Table slices the supplied rows or child collection and
owns the current page. For externally loaded child pages:

1. `expansion.hasChildren` may advertise children before a page is loaded.
2. `pagination.stateOf(parent, parentKey, table)` reports the authoritative
   `total`, current `page` and `pageSize` for that parent.
3. A pager request calls `pagination.onPageChange(context)` with the parent and
   requested page; the consumer starts or deduplicates the external request.
4. The existing page remains valid until the consumer supplies the loaded child
   rows and updates the Table or owning surface.
5. Stable row keys preserve semantic selection and expansion state where the
   update path supports restoration; late responses must be ignored after a
   newer revision, hide or disposal.

External pagination is currently a hierarchical child-page contract, not a
root-result-page contract. Cancellation, request versioning, cache invalidation
and authoritative data validation belong to the consumer. Table owns pager
geometry, visible-page state and row recycling; the consumer owns the remote
request and returned data.

## Current implementation boundary

Runtime modules and lifecycle helpers exist, and the catalog validator can
verify structural/reference contracts. The catalog editor does not mount game
UI, and generated HTML is a structural preview. Complete consumer lifecycle
and visual equivalence remain surface-specific integration requirements until
they are exercised by the actual consumer runtime.

For current constructors and their owner/mutator pairs, use
[RUNTIME_REFERENCE.md](RUNTIME_REFERENCE.md). This document does not declare
the preview lifecycle accepted in any product runtime.
