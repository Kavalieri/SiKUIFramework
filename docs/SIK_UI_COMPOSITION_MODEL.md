# SiK UI composition model

## Purpose

SiK UI builds interfaces from a small, explicit hierarchy. Product code
supplies data, state and callbacks; framework components own geometry, spacing,
alignment, responsive reflow, lifecycle and visual chrome.

The model follows the useful part of professional visual builders: recursive
layout containers, atomic widgets, declared parent/child compatibility and
reusable variations. It deliberately avoids wrapper inflation and product-
specific visual components.

## Component hierarchy

1. `Surface` describes one complete renderable UI artifact.
2. A root `Container(role="surface")`, hosted by a Window, Modal or embedded
   parent, owns the optional header, navigation, content and footer regions.
3. `container.navigation` creates one stable child Container per destination;
   its internal `Tabs` selector never appears as an author-placed component.
4. `Container` owns recursive layout: row, column, grid, wrapping, alignment,
   justification, gaps, padding, responsive order and spans.
5. `Block` is a semantic Container preset with optional title, information
   tooltip and actions.
6. Collections arrange repeated homogeneous widgets. `CardCollection` owns
   Cards; `Table` owns rows; `List` owns list items.
7. Widgets are final interactive or presentational elements: Card, button,
   field, combo, status, text, icon, progress and similar controls.
8. Overlays are lifecycle-bound surfaces such as tooltip, menu and drag ghost.

## Card boundary

A Card is an atomic compound widget representing one entity, fact, option or
actionable summary. It is not a generic layout container.

Allowed Card content is limited to declared terminal slots such as icon, title,
value, short description, status and actions. A Card cannot contain a Block,
Table, Tabs, another Card, CardCollection or dashboard. A dashboard is a parent
Container or Block arranging several Cards.

Use a Card when its border/background and contents form one meaningful unit.
Do not wrap a simple button, label or field in a Card merely to obtain padding.
Use Container layout or an `ActionGroup` for related controls.

Card variations reuse the same component and contract. A variation supplies
different defaults or visible slots; it does not create `AddonCard`,
`ProgramCard` or another product-specific framework type.

## Container contract

Containers may contain widgets and, where required, child Containers. The
standard presets must cover ordinary construction without fine coordinates:

- direction: row, column or grid;
- alignment and self-alignment: start, center, end or stretch;
- justification: start, center, end, space-between, space-around or
  space-evenly;
- canonical padding and gap tokens;
- wrap/no-wrap and responsive column count;
- item order, grow, shrink, minimum size and grid span;
- overflow: visible, clipped or scrollable.

Nested Containers are used only when they express a real grouping or layout
change. The smallest useful tree is preferred.

## Product mapping

- Addons: one dynamic CardCollection; one Card per public
  `GSSiK.API.Addon.list()` definition.
- Programming: Cards represent actual programs or programming options; layout
  belongs to the parent collection, never to product-specific card geometry.
- Status dashboard: a parent Container combines independent metric/status
  Cards. No Card contains the dashboard.
- Forms: fields and actions live in a Block/Container. Related buttons use an
  ActionGroup unless the action itself is a meaningful Card entity.
- Tables and expandable rows remain Table behavior, not Cards.

## Enforcement

The component manifest is authoritative for allowed children. Validation must
reject unknown components, forbidden nesting, product-specific framework
widgets, direct vanilla visual construction and manual sibling geometry in a
consumer. Runtime and HTML use the same surface specification and component
manifest.

Fine offsets remain an escape hatch for genuinely new primitives. Repeated fine
positioning is evidence that the framework lacks a component, token or layout
capability and must be reviewed rather than copied across consumers.

## External reference patterns

- Elementor containers: recursive Flexbox/Grid layout, widget children,
  responsive ordering and reusable container templates.
- WordPress Block Editor: explicit `parent`, `ancestor` and `allowedBlocks`
  relationships, plus variations of one registered block type.

These are architectural references only. SiK UI retains its PZ/Kahlua runtime,
public namespace and validated visual standards.
