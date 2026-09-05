# SiK UI runtime reference

This is the human-readable reference for the current standalone runtime. It
was audited from `SiK_UI.lua` and the modules it loads. Every entry is
**preview**: source presence is not a promise of stable compatibility, visual
parity, product migration or QA acceptance.

All examples run on the client after `require "SiK_UI"`. `parent` means an
`ISPanel`-compatible object. `bounds` means `{ x, y, w, h }` (most APIs also
accept `width`/`height`). `playerNum` is optional and defaults to `0`.

Every visual constructor below has the same declared scope: **Project Zomboid
Build 42.20+ client Lua**. `mod.info` and the visible description share that
minimum. The metadata is not a substitute for the integrated runtime acceptance
matrix. No visual constructor is shared or server-side.

## Version and profile namespaces

The framework currently has two independent version axes:

- `SiK.UI.Version.string()` and `mod.info` report the runtime/mod version
  `1.0.0-dev1`.
- The catalog manifest reports `manifestVersion=0.1.0-preview`. Generated
  surface `frameworkRef.manifestVersion` pins this manifest contract, not the
  runtime/mod release number.

Neither version implies Build compatibility or QA acceptance. Consumers must
not compare the manifest version with `Version.atLeast`, and a manifest match
does not replace a declared `SiKUIFramework` dependency.

Profiles also belong to separate layers and must not be interchanged:

| Layer | Accepted names | Purpose |
|---|---|---|
| catalog manifest | `compact`, `standard`, `wide` | declarative layout overrides and validation |
| `Metrics.profile(width, requested)` | `compact`, `standard`, `wide`, `terminal`, `editor`, `staff` | density, row and control metrics |
| `Window.profile(name, overrides)` | `terminal`, `compact`, `standard`, `wide`, `editor`, `task` | shell bounds and viewport caps |

An unknown Metrics or Window name currently falls back to its own default.
That fallback does not make a name from another layer supported. In particular,
`staff` is a Metrics profile, while `task` is a Window profile.

## Construction rules shared by every component

- Validate input first. Constructors return `nil, reason` instead of silently
  selecting a different component or product fallback.
- The caller that constructs an imperative object owns `dispose()`. A builder
  tree owns only handles it created/adopted.
- `reflow` changes geometry only; it does not fetch product data or mutate a
  product. Rebuild/update data separately.
- Callback context is framework-local and bounded. It can include `playerNum`,
  `component`, `payload`, `event` and `value`; do not put authority decisions
  or unbounded product objects into it.
- Product translations, assets and action implementations are supplied by the
  consumer. The framework does not import product namespaces.

### Callback, return and lifecycle schema

Unless a row below states otherwise, a framework callback receives one context
table produced by `Namespace.context`: `component`, `playerNum`, `payload`,
`event` and `value`. Product callbacks remain synchronous and local; their
return value has no authority meaning. The explicit exceptions are
`Modal.confirm` (`onAccept()`/`onCancel()`), `Modal.input`
(`onAccept(value, panel)`, `validate(value, panel)`,
`onInvalid(reason, value, panel)`), DropTarget callbacks (drag payload followed
by context), and low-level layout/render visitors documented in their export
row.

| Result kind | Contract |
|---|---|
| constructor/attachment | instance or handle; invalid required input returns `nil, reason` |
| mutator | instance/value on success; a rejected operation returns `nil, reason` or a documented boolean |
| close/veto | `Window.close` returns `false` when already closing or vetoed; accepted close returns `true` |
| reflow | geometry only; it never fetches product state and normally returns the same handle or resolved rectangles |
| disposal | every owning handle exposes idempotent `dispose()` unless its row explicitly says it is a pure value/helper; first disposal is `true`, repeats are `false` |

Convenience constructors inherit the schema of their canonical owner:
`Modal.compact` and `Modal.task` call `Modal.create`; `Modal.confirm` and
`Modal.input` own their Window-backed content and controls; `Card.accentPanel`
returns a caller-owned passive panel. Pure geometry, registry, rendering and
lookup functions allocate no lifecycle owner and therefore have no disposal.

## Canonical visual constructors

| Constructor | Required options | Main events | Reflow / update | Ownership | Minimal client example |
|---|---|---|---|---|---|
| `Window.create(options)` | shell options; no parent | `onClose`, `onReflow`, resize callbacks | `panel:reflow()`, `setSize`, header/footer setters | window owns shell chrome and focus layer, not product children | `Window.create({ profile = "standard" })` |
| `Window.apply(panel, options)` | existing panel | same as Window | same panel methods | caller owns the applied panel | `Window.apply(panel, { profile = "standard" })` |
| `Window.applyEditor(panel, options)` | existing editor panel | same as Window | same panel methods | caller owns the applied panel | `Window.applyEditor(panel, {})` |
| `Window.newInstance(class, x, y, w, h)` | derived PZ class and raw bounds | none until the class initializes | uninitialized class instance | caller owns initialization and disposal | `Window.newInstance(MyWindow, x, y, w, h)` |
| `Window.derive(name)` / `Window.callBase(panel, method, ...)` | stable class name / supported base lifecycle event | validated class and method | derived class / base result or stable error | caller owns the derived class | `local MyWindow = Window.derive("MyWindow")` |
| `Modal.create(options)` | Window options; optional `kind`, `buildContent` | close/cancel callbacks | `panel:reflow()`, `Modal.fitContent` | modal owns its content host; `Modal.show` enters its per-player stack | `Modal.create({ kind = "compact" })` |
| `Modal.apply(panel, options)` | existing Window panel | close/cancel callbacks | `panel:reflow()`, `Modal.fitContent` | caller owns the applied panel; stack only after `Modal.show` | `Modal.apply(panel, { kind = "compact" })` |
| `Container.create(options)` | `parent`, bounds/layout; optional `navigation` | navigation `onActivate` | `setBounds`, `setLayout`, `setItems`, `setActive`, `mountContent`, `reflow` | container owns its panel, navigation selector and one common content host | `Container.create({ parent = host, navigation = { placement = "left", items = items } })` |
| `Block.create(options)` | `parent`, geometry | subscribed layout listener | `setBounds`, `setReserved`, `setContentHeight` | block owns its panel/listeners and owned scroll | `Block.create({ parent = host, x = 0, y = 0, w = 1, h = 1 })` |
| `Scroll.create(options)` | `parent`, `viewportRect`; track/content optional | `subscribe(listener)` | `setGeometry`, `setContentHeight`, offset methods | scroll owns viewport, host, bar and listener list | `Scroll.create({ parent = host, viewportRect = rect })` |
| `VirtualList.create(options)` | either `scroll` or `parent`; data callbacks optional | `onSelect`, `onActivate`, row interaction | `setData`, `setBounds`, `refresh` | list owns its reusable row pool and an internally created scroll only | `VirtualList.create({ parent = host, data = {} })` |
| `Table.create(options)` | `parent`, non-empty `columns` | select, row, sort, expansion, row-adapter callbacks, external child-page request | `setRows`, `setColumns`, `setBounds`, `layout`, `setChildPage` | table owns Block, Scroll, VirtualList, header/pager and cell actions; consumer owns external requests/data | `Table.create({ parent = host, columns = columns })` |
| `Form.create(options)` | `parent`, optional field descriptors | field `onChange`, `onInvalid`, `onSubmit` | `reflow`, `setValue` | form owns its labels/field controls/submit control | `Form.create({ parent = host, fields = {} })` |
| `Card.create(options)` | `parent`, geometry | consumer action/build callbacks | `reflow`, `setData`, `setContentHeight` | card owns panel, content block/scroll and children it creates | `Card.create({ parent = host, x = 0, y = 0, w = 1, h = 1 })` |
| `Card.accentPanel(options)` | geometry; `parent` optional | none | `setBounds` | caller owns the returned panel | `Card.accentPanel({ parent = host })` |
| `CardCollection.create(options)` | `parent`/bounds and `items` or build items | item action | `setItems`, `reflow` | collection owns its cards | `CardCollection.create({ parent = host, items = {} })` |
| `Collection.create(options)` | `parent`/bounds and `items` | item action | `setItems`, `reflow` | collection owns generated item views | `Collection.create({ parent = host, items = rows })` |
| `ActionGroup.create(options)` | `parent`, actions and `mode` | action activation | `setActions`, `setBounds`, `reflow` | group owns generated action controls | `ActionGroup.create({ parent = host, mode = "equal", actions = actions })` |
| `Controls.create(kind, options)` | a supported kind and `options.parent` when visual | kind callback | control-specific setters/reflow where provided | caller owns returned control | `Controls.create("button", { parent = host })` |
| `Tooltip.attach(options)` | `control`; text or factory optional | hover is supplied by owner control | handle `setText`, `getActive`, `hide`; static `Tooltip.position`/`anchorToPointer` | handle owns wrapper/tooltip state and restores chain on dispose | `Tooltip.attach({ control = button, text = "Help" })` |
| `Controls.setTooltip(control, text, options)` | any framework/vanilla control table | reusable tooltip bridge | updates and reuses the owned attachment | never assumes that the concrete PZ widget implements `setTooltip`; lifecycle remains owned by the control decorator | `Controls.setTooltip(button, "Help")` |
| `Tooltip.createDocument(options)` | optional ephemeral `sections` and render metrics | none | `append`, `set`, `clear`, `measure`, `render`, `dispose` | document owns only its current section records; `set` replaces without accumulation | `Tooltip.createDocument({ sections = help })` |
| `Tooltip.appendSection(target, section, options)` | data target and neutral title/text/lines/tone | none | `clearSections`, `setSections`, `measureSection(s)`, `renderSection(s)`; returned handle removes its section | caller owns target and rendering host | `Tooltip.appendSection(document, { title = "Info", text = copy })` |
| `Popover.attach(control, options)` | anchor control, `factory`, trigger `click`/`manual`/`passive` | `onOpen`, `onClose` | `open`, `close`, `toggle`, `reposition`, `getActive` | handle owns transient widget; focus is optional and passive defaults unfocused | `Popover.attach(button, { trigger = "manual", factory = buildPopover })` |
| `DropTarget.attach(control, options)` | control; optional `accept` and function/object `dragProvider` | `onEnter`, `onLeave`, `onOver`, `onDrop`, optional `finishDrag` | `setEnabled`, `isOver`, `getSession`, `sync` | handle owns wrappers/highlight and clears hover when hidden; provider owns external drag | `DropTarget.attach(host, { dragProvider = currentDrag, onDrop = receive })` |
| `DropTarget.monitor(control, options)` | control; required `isDragging`, `payload`, `isOver`, `onDrop`; optional tick-like `event` | `onDrop(payload, context)` | `start`, `stop`, `setEnabled`, `isInstalled` | handle owns event registration, visibility suspension, release detection and disposal; consumer owns payload semantics | `DropTarget.monitor(window, { isDragging = vanillaActive, payload = vanillaItems, isOver = overWindow, onDrop = receive })` |
| `WorldPicker.create(options)` | player viewport/bounds, optional `resolvePoint`; `multiStep`/`stepsRequired` | start/move/step/confirm/cancel/render/refresh | `show`, `complete`, `cancel`, `getSteps`, `clearSteps`, `dispose` | picker owns capture, transient focus and visible-only refresh; idle or active cancellation is idempotent and multi-step remains visible between clicks | `WorldPicker.create({ playerNum = 0, multiStep = true, onStep = addPoint })` |
| `Lifecycle.bindVisibleRefresh(owner, options)` | visible owner and `refresh` callback | refresh context | `refresh`, `sync`, `setActive`, `isActive`, `mode` | handle owns a balanced visible-only tick or explicit manual fallback | `Lifecycle.bindVisibleRefresh(panel, { refresh = update })` |
| `Lifecycle.bindHoverReveal(owner, options)` | visible owner, `target`, trigger `sources`; optional grace/predicates | transition `onShow`/`onHide` | same lifecycle handle plus `isPointerOver` | handle owns hover sampling, target visibility, grace and balanced cleanup | `Lifecycle.bindHoverReveal(panel, { target = flyout, sources = { button } })` |
| `Menu.create(options)` | optional `items`, `playerNum` | item `onSelect` | `setItems`, `show`, `hide` | menu owns the menu panel/entries it creates | `Menu.create({ items = {} })` |
| `Menu.attach(control, options)` | existing `control`; items/provider optional | right-click, item `onSelect` | `setItems`, `show`, `hide` | returned menu owns/restores its right-click wrapper | `Menu.attach(button, { items = {} })` |
| `Drag.begin(options)` | drag payload/options | `onBegin`, `onMove`, `onDrop`, `onCancel` | `update`, `drop`, `cancel` | active drag owns its per-player session and optional ghost | `Drag.begin({ payload = item })` |
| `Drag.bind(control, options)` | existing `control`; drag options | mouse/drag callbacks | binding replaces/then restores mouse handlers | returned binding owns its active session | `Drag.bind(row, { payload = item })` |
| `DragGhost.create(options)` | typed `rows` | none | `setRows`, `moveTo`, `moveToPointer`, `show` | ghost owns its single panel until `dispose`/`destroy` | `DragGhost.create({ rows = {} })` |

### Window and Modal

`Window.create` accepts `profile` (`terminal`, `compact`, `standard`, `wide`,
`editor` or `task`), optional initial bounds, `safeMargin`, `draggable`, `resizable`,
`closable`, `geometryKey`, `closeOnEscape`, `disposeOnClose`, header/footer
tables and local callbacks. A header accepts `productName`, `contextName`,
`separator`, `status`, `statusPlacement`, `statusDot` and `close`. A footer
accepts `items`/`versions`, `align`, `visible`, `insetLeft`,
`expandWhenTight` and `separator`.

```lua
local panel, err = SiK.UI.Window.create({
    playerNum = 0, profile = "standard",
    header = { productName = "Example", status = { text = "Ready", tone = "success" } },
    footer = { items = { "Example 0.1" }, align = "center" },
    onClose = function(context) return true end,
})
if panel then panel:show() end
```

Use `Modal.create` when the Window must participate in the per-player modal
stack, then call `Modal.show(panel[, focusControl])`. Pass `owner = window` to
keep the modal above that window only; this is scoped ordering, not global
always-on-top. `Modal.raiseOwner(window)` raises the owner and its visible modal
children in order, while `Modal.topForOwner(window)` is a read-only lookup.
Modals are fixed-size by default, including `kind = "task"`; adaptive surfaces
must opt in explicitly with `resizable = true`. `Modal.confirm(options)`,
`Modal.input(options)`, `Modal.compact` and `Modal.task` are convenience
constructors. `Modal.input` accepts optional accept/cancel callbacks;
`validate(value, panel)` can return `false, detail`.
`Modal.close(panel, reason)` and disposal remove the stack entry.

### Block and Scroll

`Block.create` needs `{ parent, x, y, w, h }`; optional `reservedTop`,
`reservedBottom`, `contentHeight`, `metrics`, `background`, `border` and
`fill` control its content and scrollbar rectangles. `Block.resolveLayout`,
`resolveContentRect`, `resolveScrollBarRect` and `bindScrollable` expose the
same geometry calculation without constructing a Block.

`Block.resolveViewportRect(bounds, overflow, { metrics = ... })` returns
detached content and optional track rectangles for an already-inset descendant
viewport. It adds no padding, preserves the supplied origin, and reserves the
canonical scrollbar width plus gap only at the right when overflow is true.
Consumers of an already narrowed Block rectangle pass false: never reserve
the same scrollbar twice. Table delegates its intermediate viewport here.

`Scroll.create` accepts `{ parent, viewportRect, trackRect, contentHeight,
wheelStep, playerNum }`. It exposes `scrollBy`, `setScrollOffset`,
`getScrollOffset`, `captureState`, `restoreState`, `addChild`, `removeChild`,
`clear`, `subscribe` and `unsubscribe`. A subscriber is a local layout
listener; remove it or dispose the scroll with the owner.

```lua
local block = assert(SiK.UI.Block.create({ parent = host, x = 8, y = 8, w = 400, h = 240 }))
local scroll = assert(SiK.UI.Scroll.create({ parent = block.panel,
    viewportRect = block:getContentRect(), trackRect = block:getTrackRect(), contentHeight = 600 }))
block:attachScroll(scroll, true) -- Block will dispose this scroll.
```

### VirtualList and Table

`VirtualList.create` accepts `{ parent | scroll, data, rowHeight, buffer,
keyOf, createRow, updateRow, onSelect, onActivate, interaction }`. `interaction`
can receive `onMouseDown`, `onMouseMove`, `onMouseUp`, `onMouseUpOutside`,
`onDoubleClick` and `onRightClick`; each receives the local row context.
`captureState`/`restoreState` preserve selection/focus/offset only.

`Table.create` is the sole table constructor. Required `columns` is an ordered
array; a column may provide `key`, `title`, size/minimum/fraction properties,
`value`, `render`, `sortable` and one `actions` adapter. `rows` can be set
later. Optional `expansion = { childrenOf, keyOf, hasChildren }` makes
hierarchical rows; optional `pagination = { pageSize, height }` paginates local
table data. Expansion, connectors, child pagination, table header, pager and
rows are Table features, not independent widgets.

```lua
local table = assert(SiK.UI.Table.create({
    parent = host, x = 8, y = 8, w = 600, h = 300,
    columns = {
        { key = "name", title = "Name", fraction = 1, value = function(row) return row.name end },
        { key = "count", title = "Count", width = 80, value = function(row) return row.count end },
    },
    rows = records,
    expansion = { childrenOf = function(row) return row.children or {} end },
    onRowClick = function(context) openRecord(context.item) end,
}))
```

Use `setRows(rows, preserveOffset)`, `setColumns(columns)`, `setPage`,
`setChildPage`, `toggleExpanded`, `setSort`, `setSelectedKey(s)`,
`captureState`, `restoreState` and `dispose`. Table callbacks include
`onSelect`, `onRowClick`, `onSort`, `onColumnResize` and `onExpansionChange`.
They receive stable keys and local row/selection context, not product authority.

#### Row adapter

`options.row` is a reusable-row adapter. It may provide `render`, `update`,
`dispose`, `onMouseDown`, `onMouseMove`, `onMouseUp`, `onMouseUpOutside`,
`onDoubleClick` and `onRightClick`. Interaction callbacks receive a row context
containing the player, Table, pooled row, current item, source/visible indexes,
stable key, parent key, row kind, semantic selection and pointer event.

Declarative surfaces opt into this adapter boundary with
`table.row-interactions` and `adapter = context.tableOptions`. The Builder then
merges `context.tableOptions[nodeId]` into that Table's runtime options. The
capability only declares whether lazy tooltip, context-menu and drag behavior
is permitted and how selection/ghost scope is interpreted; it does not create
those widgets or supply callbacks.

Because rows are pooled, `update` must replace item-specific state rather than
append it. `dispose` must release attachments and restored handler chains.
Consumers retain responsibility for permission checks, payload meaning and any
authoritative action.

#### External child pagination

External paging augments the normal pagination table:

```lua
pagination = {
    pageSize = 15,
    external = true,
    stateOf = function(parent, parentKey, tableView)
        return { total = parent.childCount, page = parent.loadedPage, pageSize = 15 }
    end,
    onPageChange = function(context)
        -- Request context.page for context.parentKey, then update the Table.
        return requestChildPage(context.parentKey, context.page)
    end,
}
```

Both functions are required when `external=true`, otherwise construction fails
with `invalid_external_pagination`. `expansion.childrenOf(parent)` returns the
currently loaded physical child page; `stateOf` supplies its logical `total`,
`page` and `pageSize`. `setChildPage(parentKey, page)` calls `onPageChange` and
does not mutate or replace source rows. After the request completes, the
consumer updates its child data and calls `setRows` or updates the owning
surface. `expansion.hasChildren` can keep the expand affordance available
before the first page is loaded.

This external contract currently applies to child pages of expanded parents.
Flat/root `setPage` remains local; do not present it as an external data-source
callback. Functions stay in runtime consumer code and are never serialized in
the data-only surface spec.

### Form, Card and CardCollection

`Form.create` takes `{ parent, bounds, fields, submit, onChange, onSubmit,
onInvalid }`. Each field requires a unique string `key`; supported `type` is a
Controls kind such as `field`, `combo` or `toggle`. A descriptor can supply
`label`, `default`, `items`, `placeholder`, `tooltip`, `payload`, `onChange`
and `validate(value, allValues, descriptor)`. `submit()` calls `validate()`
before `onSubmit`.

`Card.create` accepts named terminal slots such as `{ parent, bounds, icon,
title, value, description, status, statusTone, payload, tooltip, onActivate }`.
It is atomic final content: it deliberately exposes no child host, nested
container, Block or Scroll. The returned owner exposes `panel`, `data`,
`setData`, `reflow` and `dispose`. `CardCollection.create` takes `{ parent,
bounds, items, gap, minCardWidth }`; item cards use the same named slots.

### Container navigation and Controls

`Container.create` accepts a `navigation` descriptor with `placement`, ordered
`items`, `activeKey`, selector metrics and `onActivate`. Placement is `top`,
`bottom`, `left` or `right`. Each item has a stable `key`, optional text/icon,
tooltip and enabled state. Navigation owns one common content host;
`mountContent(key, panel)` adopts each selectable surface into that host.
Selection changes child-surface visibility and focus without creating a
destination container per tab, rebuilding, or manually positioning content.
`Tabs.create` and `Navigation.create` implement this capability and remain low-level
compatibility surfaces; product code must not build a separate rail with them.

`Controls.create(kind, options)` is direct runtime API, not a declarative node
factory. Supported kinds are `button`, `iconButton`, `icon`, `field`, `combo`,
`search`, `toggle`, `status`, `feedback`, `panel`, `separator`, `progress`,
`copyText`, `sectionTitle`, `blockHeader`, `listOption`, `requirementRow` and
Card's `summary` variant. The catalog's
hyphenated IDs (`icon-button`, `section-title`, `requirement-row`) are normalized by Factories,
not by direct `Controls.create`. Direct code may pass either
`Controls.create(kind, options)` (with `options.parent`) or
`Controls.create(kind, parent, options)`.

```lua
local save = SiK.UI.Controls.create("button", {
    parent = host, x = 8, y = 8, w = 120, h = 30, text = "Save",
    onClick = function(context) saveProductData(context.payload) end,
})
```

Common control options are `parent`, geometry, `text`, `tooltip`, `enabled`,
`payload`, `playerNum` and a relevant callback (`onClick`, `onChange` or
`onSubmit`). Text-bearing components that expose alignment use the shared
`align = left|center|right` and `verticalAlign = top|middle|bottom` presets;
component defaults are safe and fine offsets remain optional. Use specialized helpers for their richer options: `button`,
`iconButton`, `field`, `combo`, `search`, `toggle`, `status`, `feedback`,
`panel`, `separator`, `progress`, `copyText`, `sectionTitle`, `blockHeader`, `listOption`,
`requirementRow`. Text helpers are `alignOffset`, `textPosition`,
`truncateText`, `wrapText`,
`renderWrappedLinePool`, `measureButtonWidth` and `fitButtonToContent`.

Every entry in this control matrix is client-only under the common Build 42
target stated above. All returned controls use the common `dispose()` wrapper;
the direct consumer owns that wrapper unless a higher-level component created
the control itself.

| Control kind / helper | Schema beyond common options | Event | Reflow / setter | Minimal example |
|---|---|---|---|---|
| `panel` | optional background/border colours | none | native bounds setters | `Controls.panel({ parent = host })` |
| `separator` | geometry; optional `color`, semantic `tone`, or `theme` override | none | native bounds setters | `Controls.separator(host, { w = 240 })` |
| `button` | `text`, optional `locked`, `fullWidth` | `onClick` | `setEnabled`, `setLocked`, `setText` | `Controls.button(host, { text = "OK" })` |
| `iconButton` | `icon`/`texture`, optional `iconSize` | `onClick` | `getTexture`, `setTexture` | `Controls.iconButton(host, { icon = "close" })` |
| `icon` | passive `icon`/`texture`, optional `iconSize`/`tone` | none | `getTexture`, `setTexture`, `setTone`, `reflow` | `Controls.icon(host, { icon = "info" })` |
| `field` | `placeholder`, `numeric`, `maxLength` | `onChange` | `setEnabled` | `Controls.field(host, { placeholder = "Name" })` |
| `combo` | `items`/`options`, optional numeric `selected` | `onChange` | `setEnabled` | `Controls.combo(host, { items = { "A" } })` |
| `search` | field text and optional search action | `onChange`, `onSubmit` | composite control bounds by consumer | `Controls.search(host, { onSubmit = find })` |
| `toggle` | boolean `selected` | `onChange` | `setSelected` | `Controls.toggle(host, { selected = true })` |
| `status` | `text`, semantic `tone`, optional `indicator`/`framed` rendering | none | `setStatus`, `reflow` where rendered as a panel | `Controls.status(host, { text = "Online", tone = "success" })` |
| `feedback` | `text`, semantic `tone`, optional font | none | `setFeedback`, `reflow` | `Controls.feedback(host, { text = "Saved", tone = "success" })` |
| `progress` | normalized `value`, optional `label`, `tone`/colour | none | `setValue`, `reflow` | `Controls.progress(host, { value = 0.5 })` |
| `alertRow` | square alert icon, visible `text`, `severity`, optional `glow`/tooltip | none | `setText`, `setSeverity`, `reflow` | `Controls.alertRow(host, { text = "Warning", severity = "warning" })` |
| `headerOperation` | compact operation `text`, optional progress and semantic `tone` | none | `setOperation`, `reflow` | `Controls.headerOperation(host, { text = "Scanning", value = 0.5 })` |
| `copyText` | wrapped `text`, `tone`, font/line gap, optional two-axis alignment | none | `setText`, `setAlignment`, `reflow` | `Controls.copyText(host, { text = "Info" })` |
| `sectionTitle` | `text`, optional `info`/tooltip and trailing `action`, optional two-axis alignment | info/action click callbacks | `setText`, `setAlignment`, `reflow`; preserves full text and fits the rendered label with UTF-8-safe ellipsis | `Controls.sectionTitle(host, { text = "Section" })` |
| `blockHeader` | same schema as `sectionTitle` | same callbacks | same fitted-title methods | `Controls.blockHeader(host, { text = "Section" })` |
| `listOption` | `text`, selection/activation state | `onClick` | `setSelected`, `setText`, `reflow` | `Controls.listOption(host, { text = "Option" })` |
| `requirementRow` | `text`, `state`/`met`, optional `icon`/texture | none | `setData`, `setState`, `reflow` | `Controls.requirementRow(host, { text = "Need item", met = false })` |

`panel` is a general-purpose visual container. It is transparent unless the
consumer explicitly enables and supplies its chrome. `separator` is the
non-interactive semantic rule: it always draws its background, defaults to a
horizontal height of `1`, and resolves its colour from the `divider` theme token.
Consumers may select another semantic `tone`, pass a local `theme` override, or
provide an explicit `color`; width and any non-default thickness remain layout
decisions owned by the consumer. The `divider` token is a colour, not a control
or spacing metric.

`styleField(existingEntry, options)` and `styleCombo(existingCombo, options)`
are canonical chrome adapters for already-created vanilla controls. They style
the supplied instance but do not take ownership or install a disposal wrapper.
`renderWrappedLinePool(host, pool, options)` deliberately keeps the label pool
caller-owned; it returns the next vertical position after reusing/hiding labels.

### Tooltip, Menu, Drag and DragGhost

`Tooltip.attach` accepts `{ control, text, factory, playerNum, ... }` and
returns a handle with `setText`, `getActive`, `hide` and `dispose`.
`Tooltip.position`, `Tooltip.pointerPosition` and
`Tooltip.anchorToPointer` are static placement helpers for the active tooltip
widget; the attachment handle does not expose `refresh`, `show` or placement
methods. It preserves/restores the control chain it wraps; only one owner
should attach it to a given control at a time.

For composed tooltip content, `Tooltip.createDocument` owns an ordered set of
neutral sections. `measureSection`/`renderSection` accept `title`, `text` or
`lines`, `font`, `tone`, `lineColor`, `framed`, `backgroundColor`,
`borderColor`, `padding`, or independent `paddingX`/`paddingY`. Colours may be
`{ r, g, b, a }` records or positional `{ r, g, b, a }` arrays. Product code
supplies content and semantic parameters; it must not redraw the section
frame/text locally. `Tooltip.renderFrame(panel, x, y, w, h, options)` is the
bounded bridge for a vanilla tooltip body whose internal content is still
rendered by vanilla: it owns only background and border chrome and accepts the
same colour records plus `border=false`.

`Menu.create({ items, playerNum, payload })` returns a menu with `setItems`,
`show(x, y, payload)`, `hide` and `dispose`. Item callbacks remain consumer
code. `Drag.begin` uses `payload`, pointer origin, optional `createGhost` and
the four callbacks listed above; its returned session advances with
`update(x, y)` and must end in `drop` or `cancel`.
`DragGhost.create({ rows, maxRows, playerNum, environment })` creates only the
visual ghost. It exposes `setRows`, `moveTo`, `moveToPointer`, `show` and
`dispose` (with `destroy` as the equivalent static helper) and is disposed by
its owning drag/session.

## Declarative construction

The preview manifest declares generic composition and interaction nodes,
including `window`, `container`, `scroll`, `virtual-list`, `table`, `block`,
`form`, `card`, `card-collection`, `collection`, `action-group`, `tooltip`,
`menu`, `drag`, `control` and the low-level `tabs` compatibility node. The builder expects a
`sik-ui-runtime-surface` with identity/provenance fields, profiles, tokens,
i18n, assets, action allowlist, capabilities, component factories and one
surface root. Use the exact data schema in
[SIK_UI_DATA_SPEC_SCHEMA.md](SIK_UI_DATA_SPEC_SCHEMA.md).

```lua
local ok, reason = SiK.UI.validateSurface(surfaceSpec)
if not ok then return nil, reason end
local tree, buildReason = SiK.UI.buildSurface(host, surfaceSpec, {
    playerNum = 0,
    actions = { ["example.close"] = function() closeExample() end },
})
-- Later: tree:update(contextPatch), tree:reflow(bounds, profileId), tree:dispose().
```

The builder resolves only registered factories/capabilities and declared
actions. It captures/restores state for factory definitions that implement it,
rolls back a failed partial build and emits observer events for create/update/
dispose. It does not establish product authority or execute a product command
on its own.

## Facilities and infrastructure

| Module | Current public functions | Use |
|---|---|---|
| `Namespace` | `define`, `module`, `context`, `owned` | module registration/internal ownership helper; avoid redefining framework modules from consumers |
| `Version` | `string`, `atLeast` | current runtime version comparison |
| `Surface` | `registerType`, `unregisterType`, `componentContract`, `registerCapability`, `capabilityContract`, `registerActionEvent`, `validate`, `validateReferenceArtifact`, `assertValid`, `actionAllowlist` | closed declarative contracts |
| `Builder` | `resolve`, `resolveSurface`, `register`, `unregister`, `build` | build validated declarative trees |
| `Factories` | `registerDefaults`, `definitions` | default factory registry used by bootstrap |
| `Capabilities` | `registerDefaults`, `resolve` | capability registration/resolution |
| `Bindings` | `bind`, `emit` | bounded event/action dispatch; binding handles dispose their target mapping |
| `Viewport` | `resolve`, `safe`, `clamp` | player/screen viewport and safe geometry |
| `Metrics` | `tokens`, `profile`, `blockRects` | numeric metrics and block rectangles |
| `Layout` | `rect`, `inset`, `insets`, `axis`, `alignRect`, `place`, `flow`, `wrap`, `grid`, `stack`, `columns`, `apply`, `column`, `profile` | deterministic geometry and composition helpers |
| `Theme` | `tokens`, `set`, `color`, `palette`, `normalizeColor`, `apply` | presentation tokens, validated colors and widget role application |
| `Icon` | `register`, `resolve`, `draw`, `clearCache` | icon cache/texture drawing |
| `FocusStack` | `push`, `top`, `isTop`, `handleEscape`, `remove`, `install`, `clearPlayer` | per-player Escape/focus stack |
| `State` | `snapshot`, `merge`, `save`, `load`, `set`, `get`, `clear`, `clearPlayer`, `clearAll`, `capture`, `restore` | local per-player UI state; not persistence/authority |
| `StateMachine` | `validate`, `define`, `create`, `asyncResource` | validated shared definitions and isolated stateful instances; not persistence/authority |

### Exhaustive public export index

The following index is the complete callable module surface currently exposed
after `require "SiK_UI"`. Functions described as low-level or advanced remain
preview public exports because they are reachable through `SiK.UI`; consumers
should prefer the canonical constructor named in the purpose column. A future
release may deprecate them explicitly, but they are not silently internal here.

| Module | Public exports | Input, result and error contract |
|---|---|---|
| root | `UI.bootstrap`, `UI.validateSurface`, `UI.buildSurface`, `UI.setTextResolver`, `UI.resolveText`, `UI.setObserver`, `UI.observe` | Bootstrap returns `true` or `nil, reason`; validation returns `true` or `false, reason`; build returns an owned tree or `nil, reason`. Resolver/observer setters accept a function or `nil`; observer errors are isolated. |
| `Namespace` | `Namespace.define`, `Namespace.module`, `Namespace.context`, `Namespace.owned` | Module registration and context construction. `owned(instance, release)` adds idempotent disposal to a caller-supplied instance; the caller owns it. |
| `Diagnostics` | `Diagnostics.configure`, `Diagnostics.registerSink`, `Diagnostics.unregisterSink`, `Diagnostics.enabled`, `Diagnostics.event`, `Diagnostics.snapshot`, `Diagnostics.checkOverlaps`, `Diagnostics.checkContainment`, `Diagnostics.inspectMount` | Optional, bounded observability owned by the framework. Products register an enable predicate and sink; diagnostics never know product loggers, sandbox keys or payload semantics. Tree, overlap, containment and mount inspection return neutral reports and emit only while a registered channel is enabled. |
| `Version` | `Version.string`, `Version.atLeast` | Pure runtime-version queries; no allocation or disposal. |
| `Surface` | `Surface.registerType`, `Surface.unregisterType`, `Surface.componentContract`, `Surface.registerCapability`, `Surface.capabilityContract`, `Surface.registerActionEvent`, `Surface.validate`, `Surface.validateReferenceArtifact`, `Surface.assertValid`, `Surface.actionAllowlist` | Registry mutations validate IDs/contracts; lookup returns a contract or `nil`; validation returns a boolean and reason, while `assertValid` raises on invalid input. No visual owner is created. |
| `Builder` | `Builder.resolve`, `Builder.resolveSurface`, `Builder.register`, `Builder.unregister`, `Builder.build` | Binding/reference resolution is pure over supplied context. Registry calls reject invalid factories. `build` returns an owned tree with `update`, `reflow` and idempotent `dispose`, or `nil, reason` after rollback. |
| `Factories` | `Factories.registerDefaults` | Registers the canonical factory set once and returns `true` or `nil, reason`; `Factories.definitions` is the public data table consumed by bootstrap, not a constructor. |
| `Capabilities` | `Capabilities.registerDefaults`, `Capabilities.resolve` | Registers defaults or resolves a node capability against supplied context/resolver; returns resolved data or `nil, reason`. |
| `Bindings` | `Bindings.bind`, `Bindings.emit` | `bind(target, declaration, callback, options)` returns a disposable binding or `nil, reason`; `emit` returns callback output or `nil, "event_unbound"`. |
| `SurfaceHost` | `SurfaceHost.snapshotContext`, `SurfaceHost.sanitizeBounds`, `SurfaceHost.mount` | `snapshotContext` returns a detached defensive copy; `sanitizeBounds` normalizes finite bounds against an optional fallback/parent; `mount` owns one declarative surface tree and returns a host with isolated context, refresh/reflow/visibility operations and idempotent disposal, or `nil, reason`. |
| `Viewport` | `Viewport.resolve`, `Viewport.safe`, `Viewport.clamp` | Pure player/environment rectangle resolution; no lifecycle owner. |
| `Metrics` | `Metrics.tokens`, `Metrics.profile`, `Metrics.blockRects`, `Metrics.gridColumns` | Returns copied token/profile/rectangle data. See the profile namespace table above. |
| `Layout` | `Layout.rect`, `Layout.resolveRect`, `Layout.inset`, `Layout.insets`, `Layout.axis`, `Layout.alignRect`, `Layout.place`, `Layout.flow`, `Layout.wrap`, `Layout.grid`, `Layout.stack`, `Layout.columns`, `Layout.apply`, `Layout.column`, `Layout.profile` | Geometry is component-neutral. `resolveRect` returns a detached finite numeric rectangle, accepts `w`/`h` or `width`/`height`, fills absent values from an optional fallback and can enforce a minimum size. `alignRect`/`flow`/`wrap`/`grid` use canonical padding and gap by default; `place`/`apply` mutate only the supplied widget. Framework code applies geometry to arbitrary PZ widgets through `Layout.apply`: B42.20 vanilla `ISUIElement:setBounds` accepts one descriptive table, not four positional arguments. Explicit offsets are an exceptional escape hatch and repeated use identifies a missing framework piece/preset. |
| `Theme` | `Theme.tokens`, `Theme.set`, `Theme.color`, `Theme.palette`, `Theme.normalizeColor`, `Theme.apply` | Theme queries return copied values; `normalizeColor` accepts a supported color form and returns a defensive RGBA value or fallback; `set` changes framework-local defaults; `apply` styles a caller-owned widget and does not own it. |
| `Icon` | `Icon.register`, `Icon.resolve`, `Icon.metadata`, `Icon.drawExact`, `Icon.drawRotatedExact`, `Icon.draw`, `Icon.clearCache` | Registry/cache/draw helpers. `metadata` exposes nominal dimensions; `drawExact` and `drawRotatedExact` use registered native-size assets without crop compensation. `resolve` may return `nil`; no returned texture is owned by the caller. |
| `FocusStack` | `FocusStack.push`, `FocusStack.top`, `FocusStack.isTop`, `FocusStack.handleEscape`, `FocusStack.remove`, `FocusStack.install`, `FocusStack.clearPlayer` | `push`/`install` return disposable per-player layers; removal/clear are idempotent cleanup operations. Installed Escape pulses remain consumed through key release and close on a self-cleaning next-tick barrier, preventing the same pulse from reaching vanilla pause handling. Escape callbacks are local and may return `true` to consume. |
| `State` | `State.snapshot`, `State.merge`, `State.save`, `State.load`, `State.set`, `State.get`, `State.clear`, `State.clearPlayer`, `State.clearAll`, `State.capture`, `State.restore` | Copies and local per-player UI state only. It is not save persistence or product authority and creates no disposable owner. |
| `StateMachine` | `StateMachine.validate`, `StateMachine.define`, `StateMachine.create`, `StateMachine.asyncResource` | `validate` checks a definition without retaining it; `define` returns a defensively compiled reusable definition; `create` returns an isolated mutable instance. Instances expose `can`, `send`, state/generation/snapshot queries, bounded `subscribe` and terminal idempotent `dispose`. `asyncResource` is the neutral `loading`/`ready`/`empty`/`error`/`disposed` preset with reason and counts. See [STATE_MACHINE.md](STATE_MACHINE.md). |
| `Lifecycle` | `Lifecycle.own`, `Lifecycle.bindVisibleRefresh`, `Lifecycle.bindHoverReveal` | `own(owner, resource)` attaches a disposable resource to the owner; refresh and hover-reveal bindings return idempotent handles with balanced visible-only event ownership. |

| Visual module | Public exports | Preferred use and ownership |
|---|---|---|
| `Window` | `Window.derive`, `Window.callBase`, `Window.profile`, `Window.resolveBounds`, `Window.updateConstraints`, `Window.safeRect`, `Window.resizeHandleRect`, `Window.hitTestResizeHandle`, `Window.forgetGeometry`, `Window.chromeRects`, `Window.composeHeaderTitle`, `Window.render`, `Window.reflow`, `Window.apply`, `Window.create`, `Window.newInstance`, `Window.applyEditor` | `create`/`apply` are canonical. Geometry and title-composition helpers return values only. `render` and static `reflow` are advanced hooks for an applied Window; they do not create a second owner. Invalid panels/methods return a stable reason where applicable. |
| `Modal` | `Modal.top`, `Modal.topForOwner`, `Modal.setOwner`, `Modal.raiseOwned`, `Modal.raiseOwner`, `Modal.resolve`, `Modal.apply`, `Modal.create`, `Modal.show`, `Modal.close`, `Modal.fitContent`, `Modal.confirm`, `Modal.input`, `Modal.compact`, `Modal.task` | `top` lookups are read-only; `resolve` returns bounds/profile data; `create`/conveniences return Window-backed owned panels. `owner` provides scoped owner-before-modal ordering without global always-on-top. Modals resize only by explicit opt-in. `show` registers modal focus; close/dispose removes stack and owner bindings. |
| `Container` | `Container.create`, `Container.resolveRects` | `create` is the recursive composition primitive and owns optional navigation plus one common content host. A created container exposes `getContentHost(key)`, `ensureContentHost(key)`, `mountContent(key, panel)`, `setActive(key, emit)`, `setNavigationVisible(visible)` and `getContentBounds(fallback)` so consumers never read or mutate its navigation implementation; tab keys resolve to the same host and only select its mounted child surface. The latter always returns a detached finite numeric rectangle. `resolveRects` is the shared pure geometry resolver used by direct and declarative construction. |
| `Block` | `Block.resolveContentRect`, `Block.resolveScrollBarRect`, `Block.resolveViewportRect`, `Block.resolveLayout`, `Block.intrinsicHeight`, `Block.contentOwner`, `Block.bindScrollable`, `Block.create` | Resolve and intrinsic-height helpers are pure. `contentOwner` resolves physical Block ancestry. `bindScrollable` returns a disposable geometry binding. `create` owns its panel/listeners and an explicitly adopted scroll. |
| `Scroll` | `Scroll.rowPoolSizeForViewport`, `Scroll.create`, `Scroll.childHost`, `Scroll.contentRect`, `Scroll.contentWidth`, `Scroll.setContentHeight`, `Scroll.finish`, `Scroll.getScrollOffset`, `Scroll.setScrollOffset`, `Scroll.resetPosition`, `Scroll.applyPanelOffset`, `Scroll.applyWheelDelta`, `Scroll.resize`, `Scroll.setOnContentRectChanged`, `Scroll.addChild`, `Scroll.disposeChild`, `Scroll.isLiveWidget`, `Scroll.forEachChild`, `Scroll.childCount`, `Scroll.clearTagged`, `Scroll.clear`, `Scroll.setContentX`, `Scroll.setContentY`, `Scroll.bindScrollEvents`, `Scroll.ensureScrollBars`, `Scroll.setScrollBarsVisible`, `Scroll.isScrollBarWidget`, `Scroll.syncTree`, `Scroll.contentBottomInset`, `Scroll.viewportBottomGap`, `Scroll.listBottomGap`, `Scroll.bottomPad` | `create(options[, x,y,w,h])` is canonical and owns viewport/host/bar/listeners. The positional tail is a preview compatibility form. Child/tree/bar helpers operate only on the supplied Scroll and do not transfer ownership unless `addChild`/`disposeChild` is explicitly used. `bindScrollEvents` and geometry callbacks must be cleared by the Scroll owner or disposal. |
| `ScrollDock` | `ScrollDock.create` | Returns a container with a scrollable middle region and an optional fixed final Block outside the global scroll. |
| `VirtualList` | `VirtualList.create` | Returns a pooled list or `nil, reason`; instance methods cover data, selection/focus, offset, bounds, refresh and idempotent disposal. |
| `Table` | `Table.normalizeColumns`, `Table.metrics`, `Table.resolveColumns`, `Table.intrinsicHeight`, `Table.drawExpansionPrefix`, `Table.drawHeader`, `Table.attachHeaderResize`, `Table.resolve`, `Table.rowRect`, `Table.hitRect`, `Table.columnAtX`, `Table.create` | `create` is canonical and owns its composed table. `normalizeColumns` validates and returns a defensive canonical copy. Resolve/rect/intrinsic-height helpers are pure; draw helpers paint a supplied panel. `attachHeaderResize` returns/installs caller-scoped header interaction that belongs to the table/panel owner. |
| `Combo` | `Combo.create` | Returns a framework-styled combo owner with palette-aware field and popup chrome; items, selection, reflow and disposal stay inside that owner. |
| `Form` | `Form.create` | Returns an owned form or `nil, reason`; change/invalid/submit callbacks are local, `reflow` is geometric and `dispose` releases labels/controls. |
| `Card` | `Card.metrics`, `Card.summaryMetrics`, `Card.create` | `create` returns atomic final content with named icon/title/value/description/status slots and no recursive child host. The Card owns its panel; `setData`, `reflow` and `dispose` are instance operations. |
| `CardCollection` | `CardCollection.create` | Returns a collection owning the cards it builds; `setItems`, `reflow`, `clear` and `dispose` are instance operations. |
| `Collection` | `Collection.create` | Returns a generic repeated-content owner; item semantics remain consumer data. |
| `ActionGroup` | `ActionGroup.create` | Returns an owned group using `content`, `equal`, `wrap` or `stack` layout without product-specific button types. |
| `Navigation` / `Tabs` | `Navigation.create`, `Tabs.create` | Low-level implementation compatibility used by `Container.navigation`; direct product construction is unsupported because it bypasses common content-host ownership. Tabs and subtabs are selectors, never destination containers. |
| `Controls` | `Controls.metrics`, `Controls.alignOffset`, `Controls.textPosition`, `Controls.truncateText`, `Controls.wrapText`, `Controls.renderWrappedLinePool`, `Controls.styleField`, `Controls.styleCombo`, `Controls.styleButton`, `Controls.panel`, `Controls.separator`, `Controls.button`, `Controls.fitButtonToContent`, `Controls.measureButtonWidth`, `Controls.iconButton`, `Controls.icon`, `Controls.field`, `Controls.combo`, `Controls.search`, `Controls.effectiveSearchQuery`, `Controls.toggle`, `Controls.listOption`, `Controls.status`, `Controls.feedback`, `Controls.progress`, `Controls.alertRow`, `Controls.headerOperation`, `Controls.copyText`, `Controls.sectionTitle`, `Controls.blockHeader`, `Controls.requirementRow`, `Controls.dismissibleRow`, `Controls.dismissibleRowHeight`, `Controls.setTooltip`, `Controls.create` | `create` and named constructors return caller-owned controls or `nil, reason`; common callbacks use neutral context. `setTooltip` owns and reuses the framework attachment even when a concrete PZ control has no native tooltip setter. Alignment/metrics/text/measurement helpers are pure. Style helpers and wrapped-line pools remain caller-owned. |
| `Requirements` | `Requirements.create` | Builds a responsive requirement collection using canonical rows and one or two columns according to available content. |
| `Tooltip` | `Tooltip.measureSection`, `Tooltip.renderFrame`, `Tooltip.renderSection`, `Tooltip.appendSection`, `Tooltip.clearSections`, `Tooltip.setSections`, `Tooltip.measureSections`, `Tooltip.renderSections`, `Tooltip.createDocument`, `Tooltip.makePassive`, `Tooltip.pointerPosition`, `Tooltip.position`, `Tooltip.hide`, `Tooltip.anchorToPointer`, `Tooltip.attach` | Measure/position helpers return values only; render helpers paint a supplied panel. Documents, appended-section handles and attachments are disposable. `attach(..., { variant = "transient" })` adds one-active-per-player/channel ownership, wrapped framework content or a caller-supplied vanilla tooltip host, viewport clamping and optional active-only timeout. Its handle exposes `show`, `hide`, `getActive`, `setText`, `setContent`, `reposition` and idempotent `dispose`. `makePassive`/`hide` mutate the supplied widget but do not own it. |
| `Feedback` | `Feedback.create`, `Feedback.halo`, `Feedback.clear` | `create` returns an isolated halo service. `halo` validates explicit player context and supports bounded `replace`, `dedupe` and `queue` policies for `note` or `semantic` presentation. Queue scheduling exists only while pending entries require it. `clear` and service `dispose` release retained descriptors idempotently; vanilla may keep an already emitted note visible. |
| `Popover` | `Popover.attach` | Returns a disposable attachment with `open`, `close`, `toggle`, `reposition` and `getActive`; open/close callbacks receive neutral context. |
| `Menu` | `Menu.create`, `Menu.attach`, `Menu.sideMenuExtension` | Returns disposable neutral menu owners. `sideMenuExtension` attaches an optional hover-revealed action to a vanilla side-menu entry while the consumer supplies its own image, tint and callback. Items use consumer callbacks and payload. |
| `Drag` | `Drag.active`, `Drag.begin`, `Drag.bind` | `active` is a player-scoped lookup. `begin` returns a session ending in drop/cancel; `bind` returns a disposable handler restoration. |
| `DragGhost` | `DragGhost.create`, `DragGhost.moveToPointer`, `DragGhost.destroy` | `create` returns the owned visual ghost; movement is geometric; `destroy` is the static disposal equivalent. |
| `DropTarget` | `DropTarget.attach`, `DropTarget.monitor` | `attach` returns a disposable wrapper/highlight handle. `monitor` adapts a consumer-supplied external drag source and owns its tick registration/cleanup, including visibility and removal lifecycle. Product code retains payload and authority decisions. |
| `WorldPicker` | `WorldPicker.create` | Returns a player-scoped picker or `nil, reason`; start/move/step/confirm/cancel/render/refresh callbacks are bounded to the picker context. `cancel(reason)` works before or during capture, invokes `onCancel` once per visible cycle, and releases capture, visible refresh and transient focus. Complete/cancel/dispose release their owned state. |

Facilities have no independent visual host. Their schema is their argument
table/function signature; they do not receive arbitrary product configuration.
`Surface.registerType`/`Builder.register` alter the local registry and should
be used only by a framework extension that can own versioning and removal;
ordinary product code should consume the default catalog instead.

## Actual errors and gaps

Common construction reasons include `invalid_parent`, `invalid_columns`,
`invalid_expansion`, `invalid_pagination`, `invalid_field_key`,
`duplicate_field_key`, `unsupported_field_type`, `invalid_factory`,
`unknown_tab`, `disabled_tab`, `event_unbound`, `invalid_listener` and
`disposed`. Exact reason text is current implementation detail in this preview;
consumer code should handle failure rather than branch its mechanics on an
undocumented string.

There is no published license, contribution policy, support channel or stable
compatibility promise. No documentation or local source review can replace
client/host/dedicated runtime validation of a consuming product surface.
### Composite blocks and atomic cards

`SiK.UI.Card` is terminal content with named data slots and never hosts child
widgets. Use `SiK.UI.Block.create({ title = ..., variant = "section" })` when a
bordered section must contain controls. A Block is itself the container: every
child widget or nested container is parented directly to `block.panel` and is
laid out inside `block:getContentRect()`. No intermediate content panel exists.

Framework defaults are the product standard: a Block owns one title/help header,
one background and border, canonical 8 px padding and the only scroll gutter;
a Card owns the same title/help ordering, its differentiated surface and its
terminal content slots. Direct framework consumers may override semantic colour
when a distinct state requires it. Declarative product surfaces do not receive
visual or spacing overrides: their layout supplies parentage and available
space, and the framework derives placement, gaps and padding automatically.
