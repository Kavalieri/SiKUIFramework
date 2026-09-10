# Window

`SiK.UI.Window` owns the neutral top-level shell: safe viewport bounds,
header, content rectangle, optional footer, close behavior, dragging, resizing,
focus registration and geometry persistence. It does not own product data or
the component tree placed in its content rectangle.

The API is currently **preview**.

## Construction

```lua
local window, err = SiK.UI.Window.create({
    playerNum = 0,
    profile = "standard",
    geometryKey = "sample.editor",
    header = {
        productName = "Sample tools",
        contextName = "Selection",
        status = { text = "Ready", tone = "success" },
        statusDot = true,
        close = { tooltip = "Close" },
    },
    footer = {
        items = {
            { label = "Runtime", value = "1.0" },
            { label = "Module", value = "2.3" },
        },
        align = "center",
		verticalAlign = "middle",
    },
    onClose = function(context)
        -- Return false to veto this close request.
    end,
    onReflow = function(context)
        local content = context.value
        -- Reflow owned children inside content.x/y/w/h.
    end,
})

if not window then error(err) end
window:show()
```

`Window.create(options)` creates and initializes an `ISPanel` and then applies
the Window contract. `Window.apply(panel, options)` applies the same contract
to a caller-owned panel. Reapplying it to the same panel is a no-op.
`Window.applyEditor(panel, options)` is a compatibility convenience that
selects the `editor` profile unless the caller provides another profile.

An applied Window is both `panel` and `childParent`. Direct runtime consumers
add their children to that panel and place them inside `window:contentRect()`.
Declarative consumers receive the same content rectangle through the Window
factory.

## Profiles and bounds

Built-in Window profiles are `terminal`, `compact`, `standard`, `wide`,
`editor` and `task`.
Each profile provides preferred, minimum and maximum dimensions plus viewport
caps. The caller may provide `x`, `y`, `w`/`width`, `h`/`height`, or numeric
profile overrides. A window may extend beyond the selected player's safe
viewport while its reachable header and close control remain visible.

These are Window shell profiles, not the closed catalog-profile vocabulary or
the complete Metrics density vocabulary. In particular, `staff` is accepted by
`Metrics.profile` but is not a Window profile, while `task` is a Window profile
but not a Metrics profile. An unknown Window profile currently falls back to
`standard`; consumers must not use that fallback as capability detection.

Relevant options include:

- `playerNum`, `environment` and `safeMargin` for viewport resolution.
- `profile` for the base geometry profile.
- `padding`, `contentPadding` and `headerHeight` for shell geometry.
- `draggable`, `resizable`, `resizeHandle`, `resizeHitSize` and `closable` to
  enable or disable shell interactions. `resizeHandle` controls the compact
  painted corner; `resizeHitSize` independently provides a forgiving input
  target (40 px by default).
- `captureMouseWheel` to control whether unhandled wheel input is retained by
  the window.
- `geometryKey` to persist bounds per player.
- `closeOnEscape` and `focusPriority` for the per-player focus stack.
- `disposeOnClose = false` to hide instead of disposing after an accepted close.

Public geometry helpers are:

- `Window.profile(name, overrides)` — copies a profile and applies numeric
  overrides.
- `Window.resolveBounds(options)` — resolves and clamps the initial rectangle.
- `Window.safeRect(playerNum, environment, margin)` — returns the safe viewport.
- `Window.resizeHandleRect(panel, size)` and
  `Window.hitTestResizeHandle(panel, x, y, size)` — expose the resize affordance.
- `Window.chromeRects(panel)` — returns frame, header, title, status, close,
  content, footer and resize rectangles for an applied window.
- `Window.forgetGeometry(key, playerNum)` — removes saved geometry.
- `Window.updateConstraints(panel, overrides)` — reapplies profile/viewport
  constraints and returns `panel, bounds`, or `nil, "not_applied"`.

`Window.render(panel, phase)` and `Window.reflow(panel)` are advanced public
hooks for an already applied Window. Direct consumers normally call
`window:reflow()` and let the installed chrome wrappers invoke render. Neither
static hook creates or owns another panel.

## Header contract

Header values may be supplied in `options.header`:

| Field | Meaning |
|---|---|
| `productName` | Primary shell title. |
| `contextName` | Optional live context appended to the title. |
| `separator` | Separator between product and context text. |
| `status` | String or `{ text, tone, color }` live status. |
| `statusPlacement` | `separate` (default) or `inline`. |
| `statusDot` | Shows a status-color dot when true. |
| `statusDotSize`, `statusDotGap` | Optional dot geometry. |
| `variant` | Header variant; `blocked` intentionally suppresses context/status. |
| `close` | `false` or a table with `visible`, `size`, `icon`, `text`, `tooltip`. |

The equivalent top-level aliases remain accepted for direct runtime callers,
including `productName`, `contextName`, `liveStatus`, `headerSeparator` and
close-related options.

Runtime updates use:

- `window:setHeader(spec [, contextName])`
- `window:setProductName(value)`
- `window:setContextName(value)`
- `window:setHeaderStatus(value [, tone, color])`

Header text is fitted to the available title rectangle. The status and close
control reserve their own space rather than painting over the title.
Title and live-status controls are passive header chrome: pointer gestures on
either are relayed to the owning Window. Header dragging and the bottom-right
resize handle take priority over a consumer `onMouseDown`; clicks outside those
shared chrome regions continue to delegate to the consumer unchanged.

## Footer contract

`options.footer` accepts `items` (or `versions`), `tooltip`, `align`, `verticalAlign`,
`font`, `insetLeft`, `expandWhenTight`, `separator` and `visible`. Footer items may be strings,
`{ text = ... }`, `{ label = ..., value = ... }`, or an ordered list of those
forms. Horizontal alignment defaults to `center` and also supports `left` and
`right`; vertical alignment defaults to `middle` and also supports `top` and
`bottom`. Both axes are resolved from the measured font rather than fixed
offsets. The safe resize reservation is symmetric, so centered content remains
geometrically centered.

When `footerHeight` is omitted, Window reserves one canonical row only while a
visible footer has text. It reserves no footer space otherwise. A fixed
`footerHeight` remains fixed when visibility changes. The resize handle is
excluded from the footer text rectangle.

Runtime updates use:

- `window:setFooterItems(items [, align])`
- `window:setFooterTooltip(lines)` for a multiline tooltip over the footer
- `window:setVersions(items [, tooltipLines])` as a centered convenience
- `window:setFooterVisible(value)`

## Runtime lifecycle

An applied window exposes `contentRect`, `setSize`, `reflow`, `show`, `hide`,
`close` and `dispose`.

- `hide()` preserves the instance and saves geometry.
- `close(reason)` invokes `onClose`; returning `false` vetoes the close.
- Accepted close requests dispose by default or hide when
  `disposeOnClose = false`.
- `dispose()` is idempotent. It saves geometry, unregisters focus and pointer
  hooks, disposes owned chrome controls and removes the panel from the UI
  manager. A second call returns `false`.

Child components remain owned by the consumer or declarative builder. They
must be disposed by that owner; Window does not infer product child ownership.
