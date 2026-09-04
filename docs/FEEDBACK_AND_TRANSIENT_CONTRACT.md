# Feedback and transient presentation contract

This document defines the public boundary for short-lived player feedback in
`SiK.UI`. The halo service and transient tooltip attachment described here are
implemented by the standalone runtime.

The contract covers two presentation families:

- `halo-feedback`: short messages displayed over a specific player;
- `transient-tooltip`: passive help attached to a control and removed when its
  owner or hover state ends.

It does not move product authority, network commands, result-code selection or
translation ownership into the framework. Consumers provide already resolved
text and decide when feedback is warranted.

## Status

| Capability | Status | Current boundary |
|---|---|---|
| Static control tooltip | **Implemented** | `SiK.UI.Tooltip.attach(control, { text = ... })` delegates to the control tooltip and returns a disposable handle. |
| Lazy passive tooltip | **Implemented** | `Tooltip.attach(..., { factory = ... })` owns show/hide/dispose and pointer or control-side placement. |
| Tooltip sections and vanilla inventory extension | **Implemented** | `Tooltip.createDocument`, section measure/render helpers and `Tooltip.appendSection` support caller-owned vanilla tooltip hosts. |
| Tabs flyout | **Implemented locally; migration candidate** | `SiK.UI.Tabs` currently creates and paints its own reusable `ISPanel` flyout. It must converge on the canonical tooltip attachment rather than remain a second tooltip implementation. |
| `SiK.UI.Feedback.halo` | **Implemented** | Validates explicit player context and delegates only the final presentation to vanilla. |
| Player-scoped queue/deduplication | **Implemented** | Bounded by player and channel, with finite active/queue TTL and idle scheduler removal. |
| Transient tooltip attachment | **Implemented** | `Tooltip.attach(..., { variant = "transient" })` owns one active surface per player/channel, wrap, clamp, optional timeout and cleanup. |

The callable surface is indexed in `RUNTIME_REFERENCE.md`; examples below use
that implemented preview API.

## Shared principles

1. A transient presentation belongs to one explicit `playerNum`. A supplied
   `player` may be used as the vanilla target, but the framework must not fall
   back silently to player zero.
2. The framework owns presentation state and cleanup. The consumer owns text,
   localization, product result codes, permissions, sandbox policy and actions.
3. State is bounded by player and channel. No cache or queue grows without a
   fixed limit and expiry.
4. A transient visual is passive. It must not consume mouse input, join
   `FocusStack`/`EscapeStack` or obscure the control that owns it.
5. No permanent polling hook is permitted. A scheduler may exist only while a
   queue or timeout is active and must unregister when idle.
6. Disposal is idempotent. Hiding a surface releases visible state; disposing
   it also releases callback wrappers, queue entries and owner references.
7. Kahlua-safe data is plain, shallow and bounded. Consumers do not pass
   mutable product objects as retained framework state.

## Halo feedback

### Public API

```lua
local result, handleOrReason = SiK.UI.Feedback.halo({
    player = player,
    playerNum = 0,
    text = translatedText,
    tone = "warning",
    durationMs = 420,
    channel = "network-operation",
    dedupeKey = "redistribution-locked",
    policy = "dedupe",
    throttleMs = 1000,
})
```

Fields:

| Field | Contract |
|---|---|
| `player` | Optional resolved `IsoPlayer` used for the vanilla call. When supplied, it must correspond to `playerNum`. |
| `playerNum` | Required player context unless it can be derived unambiguously from `player`. |
| `text` | Required non-empty display text. It is already localized by the consumer. |
| `tone` | `info`, `success`, `warning` or `danger`. The framework maps it to the theme/presentation defaults. |
| `durationMs` | Optional bounded lifetime for note-style presentation; the default is 300 ms. |
| `color` | Optional `{ r, g, b }` byte override used only when exact visual parity requires it. |
| `channel` | Required stable presentation channel local to a player. It is not a product command or event name. |
| `dedupeKey` | Optional stable identity within the channel. Defaults to normalized text and tone. |
| `policy` | `replace`, `dedupe` or `queue`. |
| `throttleMs` | Optional minimum interval for repeated updates in the same channel. |
| `maxQueue` | Optional value capped by the framework maximum; it cannot remove the global bound. |
| `presentation` | Optional neutral compatibility mode: `note` or `semantic`. See the vanilla boundary below. |

The function returns a stable result such as `shown`, `deduped`, `queued` or
`unavailable`, plus a disposable handle when framework-owned pending state
exists. Validation failure returns `nil, reason` and does not display anything.

The handle may cancel a queued message and remove its deduplication record. It
cannot promise to erase a halo that vanilla has already displayed. That engine
limitation must remain explicit.

### Vanilla boundary

The adapter adds value by validating player context, normalizing tone and
duration, bounding the queue, applying deduplication, and owning cleanup. It is
not a public alias for one vanilla function.

- `presentation = "note"` uses
  `player:setHaloNote(text, red, green, blue, duration)` and preserves exact
  duration/RGB behaviour where existing surfaces depend on it.
- `presentation = "semantic"` uses the corresponding good/bad
  `HaloTextHelper` path for consumers whose established presentation already
  uses those vanilla semantics. `durationMs` and `color` are not promised for
  that path.

The framework selects safe defaults from `tone`; consumers should not select a
vanilla class or method by name. If neither vanilla path is available, the
result is `unavailable`. The framework does not manufacture a replacement
world widget.

### Queue, timeout and cleanup

Queue and deduplication state is keyed by `playerNum + channel`. Defaults are
deliberately small: at most eight pending entries per channel,
with a finite TTL. A repeated `dedupeKey` retains the existing entry under
`dedupe`, replaces under `replace`, and never appends unbounded duplicates.

Active or queued descriptors require scheduling only until their finite TTL.
The scheduler is installed lazily and removed as soon as no pending entry remains.
Framework cleanup must also run
when the owning product explicitly closes/resets its operation and when the
player dies, disconnects or is replaced. A public
`Feedback.clear(playerNum [, channel])` may provide that explicit boundary.

No scheduler is registered before the first presentation or retained after the
last active/queued descriptor expires.

## Transient tooltip

### Canonical API

The canonical public entry remains `SiK.UI.Tooltip.attach`; a parallel
`Tooltip.transient` constructor would create two equivalent public families.
The attachment should be extended without breaking the implemented static
tooltip contract:

```lua
local handle, reason = SiK.UI.Tooltip.attach(control, {
    variant = "transient",
    playerNum = 0,
    content = {
        title = optionalTitle,
        text = translatedHelp,
        tone = "info",
    },
    placement = {
        anchor = "control",
        side = "before",
        gap = 4,
    },
    maxWidth = 320,
    wrap = true,
    channel = "terminal-rail-help",
})
```

The handle provides `show`, `setContent`, `reposition`, `hide`, `setText`,
`getActive` and `dispose`. A transient attachment creates one framework tooltip panel,
uses the existing section measurement/chrome, makes the panel mouse-passive and
clamps its final rectangle through `Viewport` for the requested player.
When `content` is supplied, hover creates and shows the panel automatically.
Caller-owned vanilla hosts such as `ISToolTipInv` are shown explicitly through
`handle:show(widget)` and are hidden, but never destroyed, by the attachment.

`placement.anchor` is `control` or `pointer`; `side` is `before`, `after`,
`above` or `below`. Placement uses the control's screen rectangle, not product
padding guesses. Long content wraps within `maxWidth`; it never expands beyond
the safe player viewport.

One transient tooltip may be active per `playerNum + channel`. Showing another
one hides the previous owner in that channel. The tooltip hides when hover
ends, the control becomes hidden, an owning tab is activated, the surface is
rebuilt/closed, or the handle is disposed. It uses control events and explicit
lifecycle calls, not polling.

### What is not a transient tooltip

The following paths remain separate because they have different owners and
lifecycle contracts:

- `ISToolTipInv` used by the vanilla inventory and remote item rows. SiK UI may
  append measured sections or provide placement/passive helpers, but it must
  not replace `DoTooltip`, the vanilla tooltip object or another mod's render
  chain.
- `ISContextMenu` option tooltips. These belong to the vanilla menu host; a
  framework bridge is justified only if it adds reusable validation and
  cleanup rather than renaming `addToolTip`.
- Persistent help or feedback blocks inside a window. Those are `Block` and
  `Controls.feedback`, not transient overlays.
- Popovers and modals. They may accept input or focus and therefore retain
  their own lifecycle and Escape behaviour.

## Ownership and lifecycle

The surface owner must retain every returned handle. A control created through
`SiK.UI.Controls` may delegate tooltip ownership to the control's own
idempotent `dispose`. A hand-attached tooltip or halo queue entry belongs to the
calling surface/operation and must be registered with `SiK.UI.Lifecycle` or
disposed explicitly.

Framework state contains presentation descriptors only. Product payloads,
network IDs, permissions and mutable Java objects remain in the consumer and
are resolved again by its callback when needed.

Split-screen is not an afterthought: state, viewport resolution, active
tooltip, dedupe and cleanup are all indexed by `playerNum`. A server response
that lacks enough client context must be fixed at the product request/response
boundary; the framework must not guess the recipient.

## Integration status

The standalone contracts, loader export and focal tests are implemented.
Consumers retain ownership of localized text, exact presentation parameters,
domain authority and actions. Visual acceptance and HTML-to-Lua parity remain
separate gates owned by each consuming product.

## Verification gates

Framework tests must cover:

- invalid/mismatched player context and independent split-screen state;
- all four tones and both vanilla presentation modes;
- replace, dedupe and bounded queue behaviour, TTL and idle scheduler removal;
- idempotent hide/dispose and owner cleanup;
- transient tooltip callback chaining, one-active-per-channel, wrapping,
  viewport clamp and cleanup after hidden/rebuilt controls;
- long Latin, accented, Cyrillic and CJK text without byte truncation.

Consumer static gates should reject new direct `setHaloNote`/`HaloTextHelper`
calls after migration, and reject local transient tooltip panels. They must
retain narrow allowlists for the vanilla `ISToolTipInv` and `ISContextMenu`
bridges described above.

Runtime QA remains required in SP and a remote dedicated client, including
split-screen/player separation where available. It must exercise progress with
the product feedback sandbox option both disabled and enabled, verify that
errors remain visible, and confirm cleanup on cancel, death, reconnect, surface
rebuild and close. Tooltip QA covers mouse and joypad, viewport edges, compact
and wide resolutions, badge/help updates, long translations and coexistence
with vanilla inventory/context-menu tooltips.

Validators and gates are advisory only: they report evidence, conflicts and
options to Kava and Systems. They do not approve exceptions or make release
decisions for either authority.
