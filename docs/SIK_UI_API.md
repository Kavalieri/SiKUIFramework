# SiK UI public API

`SiK.UI` is the sole public namespace of the standalone framework. It is a
preview client API. A consumer must not import `SiK/UI/*.lua` implementation
files as a private dependency, nor treat Global Storage or another product
namespace as a framework alias.

## Optional icons in list choices

`UI.Controls.listOption(parent, options)` retains its existing full-row click,
wrapping and selection behavior. Optional `icon` (or `texture`) is resolved by
`UI.Icon`; `iconSize` defaults to 32 and `iconGap` to 8. The control owns the
leading icon rectangle and subtracts it from the text width. Its minimum height
includes the icon plus vertical padding. Without an icon geometry is unchanged.
`setData({icon=...})` updates the icon; `icon=false` clears it.

Optional `afterRender(control)` runs after the control's own drawing. It lets a
consumer drive a presentation-only hover attachment without adding a global
listener. The consumer owns that attachment's hide/dispose lifecycle. The
framework does not resolve item types, learning, network or product semantics.

## Window material, focus and initial cascade

`UI.Theme.resolveMaterial(role, parent, overrides, themeContext?)` returns a descriptor with
`role`, `paint`, `effective` and the inherited `surfaceBase`. `paint` is the
source RGBA drawn once by the current widget; `effective` is the composited
RGBA available to children and diagnostics. Roles are `window` (.80),
`header`/`footer` (.20), `surface` (.13), `surfaceAlt` (.18), `popover` (.72),
`control` (.88), `inherit` and `transparent`.
The latter two have `paint=nil` and add no base. `parent` accepts a descriptor
or panel `_sikMaterial`; explicit overrides use a role key, for example
`{window={r=0,g=0,b=0,a=.80}}`, and alpha zero is valid. Legacy `Theme.tokens`
and table tokens do not change.

Structural `surface` and `surfaceAlt` roles inherit the nearest non-structural
`surfaceBase`. The resolver derives only the source-over alpha delta still
needed over the parent that PZ has already painted. Repeating ordinary Blocks
therefore does not darken the same area at every nesting level. Controls and
detached popovers are capped at effective alpha `.92`. A table Block keeps its
existing opaque table palette and does not resolve either structural role.

### Theme context

`Theme.set(overrides, playerNum?)` replaces the selected override layer with
validated colours. Omitted tokens inherit; `{}` clears that layer, preserving
the original reset contract.
Without `playerNum` it changes the framework-global active palette; with a
player number (integer 0 through 3) it changes only that player's layer. Equal effective values are a
no-op. Table tokens (`tableHeader`, `tableRow`, `tableRowAlt`, `tableRowHover`,
`tableRowGroup`, `tableRowChild` and `tableRowDivider`) remain ordinary palette
tokens and keep their supplied colours.

`Theme.context(parent, overrides?, playerNum?)` returns a live inheritance
descriptor. `parent` may be a parent context or a panel with
`_sikThemeContext`; a missing player inherits from that parent or panel.
`Theme.tokens(context)` returns a new, independent resolved snapshot each time:
defaults, global layer, player layer, parent partial overrides and local partial
overrides, in that order. Zero channels are valid overrides.

`Theme.bind(widget, context, apply)` stores the binding only on `widget` and
keeps a weak widget registry. It invokes `apply(widget, context)` initially and
only after a `Theme.set` changes that widget's resolved snapshot. The callback
reads its snapshot with `Theme.tokens(context)`. Passing `nil` as `context`
removes the binding. No polling, surface reconstruction or owner-to-widget
strong registry is introduced. `resolveMaterial` accepts an optional fourth
`themeContext` argument and obtains its RGB tokens from that context while
preserving the material alpha contract.

`Block.create` and `Container.create` accept `accentTone` as an optional
semantic tone such as `info`, `warning` or `danger`. It paints the existing
left accent line from the inherited live context and updates only on the
existing Theme binding; it does not reflow or rebuild the surface. An explicit
RGBA `accent` always takes precedence and preserves the prior compatibility
path.

`Window` stores `_sikMaterial`, `_sikHeaderMaterial` and
`_sikFooterMaterial` once. Its focus frame reads the top `FocusStack` Window
for that player and draws the focus border, inner line and rectangular
`(4,4,.46)` shadow without blur, polling or repaint subscriptions.
`FocusStack.activate(owner, playerNum)` orders an existing visible peer within
its current band. `FocusStack.activeWindow(playerNum)` follows modal,
transient-owner and parent links to its Window.

The existing render hit-test adjusts only the window chrome source alpha:
active+hover `1.00`, active outside `0.94`, inactive+hover `0.90`, inactive
outside `0.82`. It installs no event or global poll. Content and text retain
their own alpha, so the active or hovered window gains legibility without
fading labels and the world remains visible through every ordinary window.

`cascadeOnOverlap=true` is opt-in. A new unanchored Window with no restored
geometry cascades only when it overlaps a visible SiK Window for that player:
`(+54,+48)`, or compact `(+32,+32)`, then viewport-clamped. Restored geometry,
`positionAnchor` and `viewportAnchor` always take precedence. Menus and
popovers do not use this Window option.

Dragged Windows may be parked almost completely beyond either horizontal edge.
The shared clamp keeps a 32 px header grip visible so the player can recover
the Window; it does not force the close control to remain on screen. A versions
footer paints only its text on the window material: it adds no band, divider or
frame. Its hover hitbox is transparent and its descriptive tooltip preserves
each supplied component as an explicit row.

## Retained editor geometry and transient ownership

`Layout.column({retain=true, ...})` records placement operations;
`column:reflow({x,y,w})` replays geometry on the same widgets. Heights may be
numbers or `function(width)` for intrinsic wrapped content. Ordinary columns
remain immediate and return `column_not_retained` from `reflow`.
`Block:beginColumn({retain=true})` retains its column and recalculates intrinsic
height when its width changes. Enclosing retained columns consume the resulting
height of nested Blocks. Consumers must lay out their outer Blocks in order;
reflow must not perform data queries or recreate interactive controls.
When content height changes without a width change, `Block:refreshLayout()`
replays the retained subtree once from children to parent. Existing controls,
focus and callbacks remain mounted; call it on the content-change event.

`Modal.apply` and `Modal.create` preserve `onReflow(context)`, but invoke it
once only after the Modal has synchronized its content Block or dock host.
`context.value` is therefore the final Modal content rectangle suitable for
consumer layout; the callback is not emitted during Modal construction.

`Popover.attach(control, {owner=optionalWindow, playerNum=optionalPlayer, ...})`
resolves the top ancestor as its default owner at open time. A supplied player
must match that owner. Transients inherit native top-layer priority, follow
owner activation, and close on owner hide, removal or disposal. The owner
binding is shared while popovers are open and restores its methods when the
last one closes; no global event hook is installed. The control still owns and
disposes the returned popover handle.

The declarative layout binding `stack-below` accepts a numeric threshold or
number token. A row becomes a column when the surface viewport width is at or
below that threshold; measuring and placement use the same mode. This viewport
is local to the mounted surface, not the monitor. A button with the
`field-action` variant takes its measured label width alongside a flexible
field, and fills the available width after stacking. Ordinary sibling actions
retain equal widths. Form and action-group heights include all stacked rows.

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

- `SiK.UI.Version` and `mod.info` identify runtime `1.0.2-dev1.5`.
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

### Tooltip classes

`Tooltip.attach(control, options)` and `Controls.setTooltip(control, text,
options)` use an explicit `kind`. Informational `brief` is one measured
line plus padding, while `descriptive` wraps at its readable width clamped to
the safe player viewport and derives its height from real font metrics. `brief`
rejects embedded newlines and an unsafe measured width before it changes the
control or installs hover handlers; callers select `descriptive` when help
needs multiple lines. It rechecks that same measured rectangle once when it is
shown, so a resize, UI-scale change or split-screen transition hides an active
brief instead of overflowing; it does not poll. Neither class invokes `InventoryItem:DoTooltip` or
creates an object-tooltip section.

Informational control tooltips use safe pointer placement by default. A body or
rail flyout must explicitly request `{ anchor = "control", side = "before" | "after" |
"above" | "below" }`; if that side does not fit, the framework tries the
opposite side before its final viewport clamp. Both variants resolve their final
rectangle against the player viewport. `setText` and `setContent` validate the final displayed text,
then keep `content.text` synchronized while preserving its visual options. An
owned active panel is remeasured only when its displayed value or a rendered
content option changes. A
rejected `brief` leaves its prior control, content and panel unchanged; setting
informational text/content to `nil` hides it and prevents a later `show()` from
creating an empty surface. A disposed handle also cannot show again.

An owned descriptive transient records the effective safe viewport used for
its wrap. At its next show/hover boundary, it remeasures only if that rectangle
changed, covering resize, UI-scale and split-screen transitions without polling.
When its complete measured document exceeds the safe height, it becomes the
approved `sik-tooltip--scrollable` variant: the normal tooltip frame contains a
real `Scroll` viewport and scrollbar, while `Scroll.setContentHeight` receives
the complete measured height. No line is hidden or truncated. This overflow
variant is touching and control-adjacent, so the pointer can enter its viewport;
its local control/panel handlers keep it alive across that union, and the wheel
is consumed only inside the overflowing viewport. It closes on leaving both
rectangles, timeout, disposal or Escape through `FocusStack`. It adds no
`OnTick` handler; expiry and a changed safe viewport are checked by the
visible panel's local `update` plus its pointer callbacks. `brief` and `object`
retain their existing pointer and vanilla-host behavior.
If the required `Scroll` host cannot be constructed, `show()` returns
`nil, "scroll_unavailable"`; it creates neither a partial panel nor an Escape
layer, and a later show can retry construction.
`FocusStack` is the Framework implementation of the per-player EscapeStack
contract: the scrollable panel installs one `TRANSIENT` layer for its
`playerNum`, unregisters when hidden or removed, and its owned disposal also
releases that layer. No second Escape stack is created for tooltips.

`brief` rejects a nonempty content title too, because it would render a second
line. A custom `factory` owns its returned widget's rendering and must preserve
the selected kind's one-line or wrapped contract; the framework can validate
only the textual transient surface it creates itself.

`Tooltip.attach(control, { kind = "object", ... })` is only a lifecycle
attachment for an external object-tooltip host. It accepts no `text`, `tooltip`,
`content` or factory, creates no panel, and `handle:show(host)` requires the
already-created host. `show(nil)` returns `nil, "object_host_required"` and
`setText` returns `nil, "object_text_unsupported"`. This preserves the object
body and its existing renderer/composition and position without a second wrapper.
For an active object host, `handle:reposition()` returns that host unchanged;
it never applies pointer or control placement.

`Tooltip.objectSection(lines, options)` returns only a neutral section record
tagged `kind="object"`, for composition after the vanilla body in an
already-owned object-tooltip host. It creates no panel and does not wrap the
vanilla renderer. Object descriptions remain owned by their product and use
localized semantic line breaks when needed.

`Tooltip.createScrollableSections(options)` creates a neutral, separately owned
document handle for an oversized annex. It never replaces the native object
host. Options include `playerNum`, theme/colors and `isValid`, `onInvalid`,
`onClose` callbacks. `handle:update(sections, identityKey, {x,y,w,h})` returns
the visible panel or `nil, reason`; unchanged identity and bounds reuse layout
and scroll offset. Bounds must be finite and positive. The panel uses canonical
Block/Scroll geometry and clamps to the player's safe viewport. `isPointerOver`,
`hide`, `close` and idempotent `dispose` complete its lifecycle. Escape closes
only that player's transient and suppresses reopening the same document until
its identity changes. The caller owns hover retention and restoration of any
external host properties. Validation runs only with the visible panel's update;
no global tick hook is installed. Every owner must dispose the handle on exit.

Compatibility in Framework 1.0.x maps legacy `option`/`rail` profiles to
`brief`, and `informational`, `compact`, or an omitted profile to
`descriptive`; it emits no new trace. Profiles are not a semantic API and this
adapter is scheduled for removal in Framework 1.1.0. New consumers must pass
`kind`; `tooltipKind` is the equivalent property when a control constructor
forwards a tooltip declaration. Until that removal, a legacy geometry profile
still preserves its existing width: `informational` is 680 px and
`compact`/omitted is 320 px unless `maxWidth` is supplied. It never selects the
tooltip class.

The declarative Builder tooltip factory forwards `data.text` or `data.content`,
plus `data.kind`, `data.placement`, `data.profile` and `data.maxWidth`, to the
same `Tooltip.attach(control, options)` contract. A data table without `text`
does not become a stringified tooltip. Its legacy lazy factory remains available
only for informational classes; `kind="object"` requires the caller-created
host and never accepts a factory.

### Editable-field submission

`Controls.field` is a padded panel with one native text child, available as
`field.entry`. The panel and child retain distinct native identities and their
own vanilla instantiation lifecycle. Text, focus, selection and font operations
are explicitly forwarded; `javaObject`, `target` and `instantiate` are not aliases
of the child. Attach and resize the panel, not its text backend. The SiK panel
owns the complete visible surface and semantic border. The native child keeps
only text, caret, selection, IME and keyboard behaviour; both its Lua chrome
flags and its `UITextBox2` frame are disabled after instantiation.
The semantic border reacts to hover and uses the current palette accent while
focused. This behaviour is standard; pass `statefulChrome=false` only for a
deliberately static field.

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

`UI.Controls.search` places its search icon inside the field and exposes an
interior clear action only while text is present. The clear action emits one
immediate empty `onChange` notification. The former exterior submit button is
created only with `showButton=true`; Enter continues to submit.

### Searchable combo

`UI.Controls.combo(parent, { searchable=true, searchPlaceholder="Buscar",
items, selected, placeholder })` keeps the ordinary Combo API and opens a
framework Popover containing `Controls.search` plus the option viewport. The
search text is initially empty; its placeholder is presentation only. Filtering
matches the local option name literally and case-insensitively where Lua has a
case mapping, with no pattern interpretation or queries. UTF-8/CJK names remain
literal. Closing and reopening clears the query and rebuilds the visible list.

The closed selector and popup are framework-owned panels, not an `ISComboBox`.
Fields and combos built before their scroll host exists are reconnected by
`UI.Scroll.addChild`: the structural host inherits the nearest player theme and
material, and the attached control recomputes its composed material. Consumers
do not need local colour or alpha patches for this compatibility path.
Their palette-aware material uses the neutral SiK border at rest and the accent
border for an active selection/open popup; error state uses the danger token.
The detached popup resolves its own capped material and does not inherit the
already-composed control alpha.

Items may be `{text, value, group, groupLabel, disabled, placeholder}`.
Nonempty group headings are drawn only for matching items and are never
selectable. Filtering and scrolling use a visible projection, but selection and
the change callback retain the original item/index/value. `disabled=true` and
`placeholder=true` items are muted and cannot become selected. `maxVisibleRows`
counts option rows and group headings; the popup adds the search input above
that viewport.

`placeholder` on the Combo itself is not an item. It displays only while
`selected==0`; `selected=false` or `setSelected(0)` explicitly clears the
selection. Existing nonsearchable Combos still select their first enabled item
when `selected` is omitted. Searchable Combos begin unselected unless the caller
supplies a valid selection. Empty candidate lists should use `enabled=false` and
the caller's placeholder, for example `"Sin candidatos"`.

The popup caps both its width and height to the player safe viewport before the
Popover positions it. Long option and Combo labels use a local stencil, so CJK
text clips inside that rectangle. Replacing items while open closes that stale
projection; invalid or disabled `setSelected(..., true)` calls do not emit a
previously selected item.

`UI.Controls.styleButton(button, { danger=true })` uses the calm destructive
button role (`dangerButtonFill`, `dangerButtonBorder`, `dangerButtonText`),
separate from semantic `danger`. `UI.Controls.setDanger(button, boolean)`
updates that role on an already styled button.

`UI.Controls.dismissibleRow(parent, options)` constructs one atomic bordered
row with truncated left text and a `sik.close.18` removal control.  Options are
`text`, `tone`, `theme`, `tooltip`, `actionTooltip`, `onRemove`, `playerNum`,
`w`, `h` and `profile`; padding and gap default to 8.  The returned row owns
its close child and exposes `reflow(width)` plus idempotent `dispose()`.
`UI.Controls.dismissibleRowHeight(options)` returns its standard allocation.

### Alert row progress

`UI.Controls.alertRow(parent, options)` accepts optional
`progress = { value, status, tone, mode }`. Without it the row creates no
progress child. When present it uses `UI.Controls.progress` as an unlabeled
72 x 10 px bar, right-aligned with an 8 px gap; the alert text wraps in the
remaining rectangle. At a width where that rectangle would no longer leave
legible text, the bar moves below the text and the row remeasures its height.

`row:setAlert(spec)` creates or updates the existing bar when
`spec.progress` is a table, and `progress = false` removes and disposes it.
An omitted or `nil` `progress` preserves its current state. Values and
determinate/indeterminate modes use the same normalization as
`UI.Controls.progress`; the bar never draws a second status label. The row
owns the child through reflow and idempotent disposal and does not install a
timer or an `OnTick` handler.

`Controls.field` exposes `onlyNumbers` and `maxLength` as read-only
construction descriptors alongside its native entry. They describe the
initial `numeric` and `maxLength` options; runtime input state remains on
the native child.

### Inline child pager

`UI.Table.create` creates pagination only when its `pagination` option is
present. With `expansion` and no pagination, every expanded child is projected
using the normal table scroll with no pager row, height reservation or pager
hitbox. With both options present, it projects one inline pager row after each
expanded parent only when that parent has more than one child page, instead of
reserving a table-global footer. A single-page hierarchy has no pager row,
reserved height or pager hitbox. When present, the row is structural:
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

### Table row density

Table rows use the effective height `max(fontHeight + 2 * rowVerticalPadding,
nominalRowHeight, requestedRowHeight)`. The default `standard` density uses the canonical table
tokens. `density="compact"` is the only reduced-density variant and uses its
own `Metrics.table.compact` row-height and vertical-padding tokens. Partial
`metrics.table.compact` overrides retain any omitted canonical token. A numeric
`rowHeight` may increase a density, but cannot reduce its nominal or
font-and-padding minimum; the same effective metric drives row rectangles, hit testing,
virtualization, scrolling and intrinsic height.

### Block header leading indicator

The optional `block.header` capability property `leading-indicator` accepts a
context-resolved descriptor or `nil`. Its descriptor is neutral:
`{ icon = <assetId>, tooltip = <text>, severity = "warning" }`. The Block
passes the descriptor to its header, where the control owns its leading icon,
tooltip, geometry and removal of any reserved space when the descriptor becomes
`nil`. A surface update may change the descriptor without remounting the Block.

Blocks may directly contain Blocks. Each Block remains a geometry boundary: its
own header, canonical padding and optional scrollbar reservation apply only to
its descendants, with no consumer-side reservation or compensation.

### Header operation

`UI.Controls.headerOperation` reserves a 10 px progress bar and the canonical
control gap before it. Its label is measured, UTF-8-truncated and clipped to
the rectangle before that gap; after `reflow`, the bar remains right-aligned.
`setOperation({ showProgress = false })` hides the bar and returns its width to
the label for an idle or completed operation.

### Wrapped semantic status

`UI.Controls.status(parent, { wrap = true, text, tone, indicator?, framed?, w })`
measures complete text and derives its height after every `setStatus` or
`reflow(width)`. `indicator = true` uses the shared 8 px semantic state marker
with a 16 px leading reservation. `framed = true` uses the compact bordered
status row with padding 10 px horizontally and 6 px vertically, minimum height
30 px. Neither variant truncates text or changes its semantic class by length.
Existing status constructors without `wrap` retain their behavior.

`UI.Controls.measureStatus(text, width, { framed?, indicator?, font? })` returns
`{ lines, height }` without creating a widget. Wrapped status controls and the
Builder use this same measurement. Declarative control data can supply `text`,
`wrap`, `framed` and `maxLength` (for fields). An explicit layout height remains
an override; omit it when the status should grow with translated content.

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

# Card and Collection

`Card.create({variant="output", requirement, output, actionLabel, ...})` accepts
an `output` slot with `{text, icon, tone, iconSize}`. When supplied, the card
uses the existing `Controls.requirementRow` for the output and suppresses its
legacy icon/value/description renderer. A table `requirement` is its preceding
sibling row. Both rows use 8 px Card padding and gaps, a 26 px header, 32 px
icons, a 38 px minimum row and the existing 32 px full-width action. Wrapped
text determines the row height; `Card:measure(width)` returns the required
card height. `Card.measureData(data, width, variant)` provides the same measure
before mounting, without allocating controls. Cards without `output` retain
their former slots and layout.

`Collection.create` accepts optional
`measureItem(entry, item, width, index, collection) -> height`. It is evaluated
only during creation/reflow and the greatest declared or measured height sets a
row's common height. `Collection.measure(items, options, bounds)` returns
`{rects, columns, contentHeight}` using that same layout resolver. Its optional
measurement callback receives no mounted entry during this pure preflight.
`CardCollection.measure(items, options, bounds)` applies Card variants and
wrapped output measurements; the declarative Builder uses it at the resolved
local width before allocating the parent Block's height. `CardCollection`
forwards the `output` slot to each retained Card. Reflow keeps the
existing Card, requirement rows, output row and action instances; no factory or
host API change is required.
# Table: visible data order

`table:getVisibleDataRows()` returns a new array of the consumer's row data
references in the current expansion/page order. It excludes synthetic pager
rows, collapsed children and children on other pages. Rows outside the scrolled
viewport remain included: this is the navigable data order, not the recycled
widget pool. Mutating the array does not mutate the table; treat its data
references as read-only. A disposed table returns an empty array. Intended for
on-demand range selection, without observing private projection state.
