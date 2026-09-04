# Container navigation

Navigation is an optional capability of `SiK.UI.Container`; it is not an
independent author-placed bar. The owning Container creates the selector and
one stable child Container for every destination. Product code mounts content
once and only changes the active key.

`SiK.UI.Tabs` and `SiK.UI.Navigation` are internal implementation modules.
Consumers use `SiK.UI.Container.create`.

```lua
local surface = assert(SiK.UI.Container.create({
    parent = window,
    bounds = { x = 0, y = 0, w = 900, h = 620 },
    navigation = {
        placement = "left",
        activeKey = "warehouse",
        iconOnly = true,
        iconFit = "cover",
        iconPadding = 0,
        items = {
            { key = "warehouse", text = "Warehouse", icon = warehouseIcon },
            { key = "options", text = "Options", icon = optionsIcon },
        },
        onActivate = function(context)
            local destination = context.value
            -- Update product state only; the framework switches hosts.
        end,
    },
}))

surface:mountContent("warehouse", warehousePanel)
surface:mountContent("options", optionsPanel)
surface:setActive("warehouse", false)
```

## Contract

- Placement accepts `top`, `bottom`, `left` and `right`.
- Each stable `key` owns one persistent Container host.
- `mountContent(key, panel)` adopts an existing panel and owns its parentage,
  visibility and geometry.
- `getContentHost(key)` is available for building content directly in the
  destination Container.
- `setActive(key, emit)` switches destinations without rebuilding content.
- `setItems(items)` preserves hosts and mounted content for keys that remain.
- `ensureHost(key)` provides a host-only state such as a blocked surface that
  must not appear in the selector.
- Icon sizing, fit, padding, badges, hover help, pinned items and selection
  style are configuration of the capability.
- Nested Containers may activate the same capability for subnavigation.

The owning Container disposes navigation, selector controls and hosts. Product
code must not add/remove panels, toggle tab visibility or calculate destination
rectangles manually.
