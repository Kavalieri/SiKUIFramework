# SiK UI component catalog

This catalog chooses one canonical, parameterized framework tool for each
presentation responsibility. All entries are preview. A visual variation alone
does not justify a new public constructor.

| Responsibility | Canonical tool | Do not create instead |
|---|---|---|
| top-level shell, title, live status, footer, resize | `Window` | product-specific window frames/headers/footers |
| modal shell and focus-stack lifetime | `Modal` | a second modal chrome type |
| bounded content area and scrollbar reservation | `Block` + `Scroll` | manual table/list scrollbar gutters |
| virtual repeated rows | `VirtualList` | per-screen row pools |
| sortable/selectable/hierarchical tabular data | `Table` | product table header/row/pager widgets |
| labelled input collection | `Form` + `Controls` | a product form renderer |
| information/action panel | `Card` | several card classes for visual variants |
| card arrangement | `CardCollection` | one collection per product layout |
| side/top/bottom navigation | `Tabs` | product tab/rail implementations |
| button, field, selector, toggle, status and text feedback | `Controls` | multiple product control families |
| contextual menu | `Menu` | ad-hoc menu panel wrappers |
| tooltip attachment/cleanup, sections, frame chrome and bounded placement | `Tooltip` | independent tooltip patch chains or product-painted tooltip chrome |
| drag capture and visual rows | `Drag` + `DragGhost` | product drag ghosts/capture loops |
| geometry/tokens/icons/state/focus | listed facilities | duplicated constants and global listeners |

## Declarative node map

The manifest's canonical node types are `window`, `scroll`, `virtual-list`,
`table`, `block`, `form`, `card`, `card-collection`, `tooltip`, `menu`, `drag`,
`control` and `tabs`. They map to the runtime factories registered by
`SiK.UI.Factories.registerDefaults`. Node construction is via
`SiK.UI.Builder.build`, not by calling the factory tables directly.

- `Table` owns expandable rows and optional parent/child pagination.
- `Tabs` owns tab buttons/selection only; its content remains a local child or
  a declared external `surfaceRef` with explicit ownership.
- `Window` owns shell chrome; `Modal` is a Window-backed modal convenience.
- Tooltip, Menu and Drag are non-host nodes; their typed configuration must
  not contain an arbitrary child tree.
- `control` normalizes declarative `icon-button`/`section-title` into direct
  Controls kinds; direct code uses the runtime kind names in the reference.

## Capability map

| Capability | Host | Current purpose |
|---|---|---|
| `table.expandable` | `table` | children, depth/connectors and child pagination flag |
| `table.pagination` | `table` | parent result page size |
| `table.row-interactions` | `table` | lazy tooltip, context-menu and drag policy resolved by the table adapter |
| `window.chrome` | `window` | header context/status/separator, footer and resize grip |
| `window.tabs` | `window` | manifest-level window tab/rail declaration |
| `window.modal` | `window` | modal/dismiss/Escape declaration |
| `block.header` | `block` | title help affordance and declared actions |
| `form.fields` | `form` | structured fields and form actions |
| `card.actions` | `card` | card action descriptor/equal distribution flag |
| `tooltip.vanilla-chain` | `tooltip` | preserve/lazy/append declaration |
| `drag.ghost` | `drag` | typed ghost rows and maximum visible rows |

Capabilities are data attached to their declared host; they never create a
second public widget. The runtime does not turn product callbacks into product
commands.

### Table row interactions

`table.row-interactions` is declarative policy on the owning Table. It does not
instantiate Tooltip, Menu or Drag children and it does not embed executable
callbacks in a surface spec. Its `adapter` value is currently
`context.tableOptions`: at build time the consumer may supply neutral table
options for that node ID.

| Property | Type/default | Meaning |
|---|---|---|
| `adapter` | required enum: `context.tableOptions` | runtime adapter boundary |
| `tooltip` | boolean, `false` | allow lazy row tooltip behavior |
| `contextMenu` | boolean, `false` | allow a row context menu |
| `drag` | boolean, `false` | allow row drag behavior |
| `preserveVanillaTooltip` | boolean, `true` | preserve an existing tooltip chain |
| `exactSelection` | boolean, `true` | bind interaction to the semantic row selection |
| `dragGhostMode` | `visible-rows` or `logical-selection`; default `visible-rows` | choose the visual rows represented by the ghost |
| `transferScope` | `visible-rows` or `logical-selection`; default `visible-rows` | describe the logical transfer scope |

The capability is valid only on `table`. Geometry, columns, rows, expansion
and paging remain owned by Table. Permissions, payload authority and external
data retrieval remain owned by the consumer.

```json
{
  "id": "asset-table",
  "type": "table",
  "capabilities": [
    {
      "id": "table.row-interactions",
      "props": [
        { "name": "adapter", "value": { "kind": "literal", "value": "context.tableOptions" } },
        { "name": "tooltip", "value": { "kind": "literal", "value": true } },
        { "name": "contextMenu", "value": { "kind": "literal", "value": true } },
        { "name": "drag", "value": { "kind": "literal", "value": true } },
        { "name": "preserveVanillaTooltip", "value": { "kind": "literal", "value": true } },
        { "name": "exactSelection", "value": { "kind": "literal", "value": true } },
        { "name": "dragGhostMode", "value": { "kind": "literal", "value": "visible-rows" } },
        { "name": "transferScope", "value": { "kind": "literal", "value": "logical-selection" } }
      ]
    }
  ]
}
```

`table.pagination` supplies the declarative local `page-size`. For externally
loaded child pages, the consumer augments the Table through
`context.tableOptions[nodeId].pagination`; see the runtime reference and
lifecycle document. The current public contract does not provide external
root-page loading.

## Current migration/removal position

| Item | Current state | Evidence boundary |
|---|---|---|
| standalone `SiK.UI` runtime | implemented preview | source present; no stable/QA claim |
| manifest/schema/tooling | `0.1.0-preview` | development contract, not runtime parity |
| generated HTML/Lua artifact | implemented tooling output | data/provenance only; consumer integration still required |
| product-local UI helpers/duplicates | not inventoried here | owned by each product; not removed by framework extraction |
| compatibility aliases | not published by framework | no permanent product alias is provided |

Use [MIGRATION_AND_DEPRECATION_LEDGER.md](MIGRATION_AND_DEPRECATION_LEDGER.md)
for the removal rule. A product surface is not migrated merely because it
shares a component name or has a generated artifact.

`card` is one configurable component, not a family of locally painted cards.
Its `headerVariant` may be `plain` or `band`; `band` is the compact header strip
with common background, divider, eight-pixel insets and `BlockHeader` content.
Products select the variant and provide data only.

## Common compositional geometry contract

`ScrollDock.create(options)` owns one scrollable `contentHost` and one sibling
`fixedBottomHost`. Its default outer padding is 12 px and the sibling gap is
8 px. `fixedBottomHeight` or `measureFixedBottom(host, dock)` determines the
intrinsic lower region; `setContentHeight`, `setFixedBottomHeight` and
`reflow(bounds)` recalculate both rectangles without overlay. The Dock is the
only scrollbar owner and exposes `getContentRect`, `getFixedBottomRect`,
`getScrollOffset`, `setScrollOffset` and idempotent `dispose`.

`Block.intrinsicHeight(contentHeight, options)` measures an ordinary framed
section. `fill=true` is the explicit functional viewport request. `Table`
accepts `allRowsVisible=true` or `heightMode="content"`; its
`getIntrinsicHeight()` gives an outer ScrollDock the full projected-row height
without a second table scrollbar.

Every public compositional handle that owns a rectangle exposes
`handle:reflow(bounds)`. `bounds` is declarative (`x`, `y`, and either `w`/`h`
or `width`/`height`). Component-specific setters such as `Block:setBounds` and
`Scroll:setGeometry` remain lower-level implementation contracts; consumers do
not need to guess those names when laying out a Window, Container, Block, Card,
Collection, ActionGroup, Form, Table, Navigation or Scroll surface. Builder
adoption rejects compositional handles that do not expose both their required
component-specific contract and the common `reflow` entry point.
