# StateMachine

`SiK.UI.StateMachine` is a neutral, client-local state machine for UI and
resource lifecycle. Load it only through the public facade:

```lua
local UI = require "SiK_UI"
```

It is not persistence, networking or product authority. A definition is
validated and compiled from a defensive copy, so the same definition can
create multiple isolated mutable instances.

## Definition and instance

```lua
local definition, reason = UI.StateMachine.define({
    initial = "closed",
    disposedState = "disposed",
    maxObservers = 8,
    data = { attempts = 0 },
    states = {
        closed = {},
        open = {
            onEnter = function(context) end,
            onExit = function(context) end,
        },
        disposed = { terminal = true },
    },
    transitions = {
        show = {
            from = "closed",
            to = "open",
            guard = function(context) return context.payload.allowed == true end,
            action = function(context)
                return { attempts = context.data.attempts + 1 }
            end,
        },
        hide = { from = "open", to = "closed" },
    },
})
local machine = assert(definition:create())
```

`states` is a non-empty map. `initial` and an optional `disposedState` must
name states in that map. A state may declare `onEnter`, `onExit` and
`terminal=true`. `transitions` maps an event to one transition or an ordered
array of alternatives. `from` accepts a state, an array of states or `"*"`;
`to` accepts a state or a function returning one. `guard`, `action`, state
hooks and `onObserverError` are optional.

Callbacks receive a detached context with `state`, `target`, `event`,
`payload`, `data` and `generation`. A guard must return exactly `true` to
accept. An action returns a shallow patch, `nil` for no patch, or
`false, reason` to reject. Use `UI.StateMachine.CLEAR` as a patch value to
remove a field. Internal state commits only after exit, action and enter
callbacks succeed; external side effects performed by callbacks cannot be
rolled back.

Public operations are:

- `StateMachine.validate(spec)` returns `true` or `false, reason`.
- `StateMachine.define(spec)` returns a reusable definition or `nil, reason`.
- `StateMachine.create(definition, options)` and `definition:create(options)`
  create isolated instances. `options.data` overrides initial fields.
- `machine:can(event, payload)` checks a transition without running its action.
- `machine:send(event, payload)` commits once and returns a detached snapshot,
  or `nil, reason` without changing state or generation.
- `machine:getState()`, `getGeneration()`, `isDisposed()` and `snapshot()` are
  read operations. Snapshots never expose mutable internal tables.
- `machine:subscribe(listener, { immediate = true })` returns an idempotent
  subscription. The definition bounds observers to `maxObservers` (default
  16, accepted range 1-128). Listener failures are isolated and optionally
  reported through `onObserverError`.
- `machine:dispose(reason)` performs one terminal disposal, notifies then
  releases observers, and returns `false` on repeats. Events are rejected
  after disposal. Disposal remains terminal even if an exit/enter hook fails;
  the optional second return reports that hook failure.

Transitions and notifications are synchronous and reject re-entrant events
with `transition_in_progress`. Guards and dynamic targets should therefore be
pure and fast. Observer callbacks receive `(snapshot, change)`; both values are
detached.

## Asynchronous resource preset

`StateMachine.asyncResource(options)` returns a reusable definition with the
states `loading`, `ready`, `empty`, `error` and terminal `disposed`:

```lua
local resourceDefinition = assert(UI.StateMachine.asyncResource({
    counts = { total = 0 },
    maxObservers = 4,
}))
local resource = assert(resourceDefinition:create())

resource:send("resolve", { counts = { total = 12, visible = 8 } }) -- ready
resource:send("begin")                                             -- loading
resource:send("resolve", { count = 0 })                            -- empty
resource:send("begin")
resource:send("fail", { reason = "timeout", counts = { total = 0 } }) -- error
resource:dispose("owner_closed")                                  -- disposed
```

`begin` accepts optional non-negative integer counts and clears the prior
reason. When omitted, counts retain their last snapshot. `resolve` requires
counts and selects `empty` only when `total` is zero; otherwise it selects
`ready`. `fail` records a reason (`unknown` when absent) and replaces counts
only when supplied. Resource snapshots expose detached `reason` and
`counts` fields in addition to the generic `data` field. Hooks for preset
states may be supplied as `onEnter[stateId]` and `onExit[stateId]`.

The preset does not start requests, schedule timeouts, retry, translate errors
or decide whether a response is authoritative. Consumers own those policies
and feed only their resulting events and neutral data into the machine.
