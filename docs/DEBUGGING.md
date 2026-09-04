# Debugging

Framework diagnostics are opt-in and bounded. Product diagnostics remain in the
owning product. SiK UI exposes its own Sandbox page, `SiK UI Framework:
diagnostics`, with `Composition and lifecycle diagnostics`; when enabled its
owned sink writes `[SiK.UI][<kind>] ...` lines through `DebugLog`. It never
depends on a consumer's logger, namespace or Sandbox options.

Para una prueba visual SP en español, abre **Opciones de sandbox > SiK UI
Framework: diagnóstico** y activa únicamente **Diagnóstico de composición y
ciclo de vida** (`Composition and lifecycle diagnostics` en inglés). El prefijo
esperado en `console.txt` es `[SiK.UI][<kind>]`; los eventos útiles son
`surface.host.pending`, `surface.host.tree_mounted`, `surface.host.error`,
montaje de pestaña, geometría vacía y solapes. No existe sublog por fotograma.

The public `SiK.UI.Diagnostics` contract also accepts consumer-owned sinks
through `registerSink(ownerId, options)`. Those sinks are for integration facts
owned by each consumer, not a replacement for the framework switch.

Current framework evidence:

- `event(kind, message)`: bounded lifecycle fact;
- `inspectMount(navigation, key)`: distinguishes `missing_host`,
  `inactive_destination`, `hidden_host`, `missing_content`, `hidden_content`
  and `empty_geometry`;
- `snapshot(root, label, limit)`: structured, bounded widget-tree summary.
- `checkOverlaps(root, label, options)`: partial overlaps between visible
  siblings, excluding intentional containment and optional consumer-declared
  chrome;

Diagnostic areas that consumers may classify in their own logger:

- lifecycle: create, mount, hide, close and dispose ownership;
- layout: profile selection, bounds and reflow;
- scroll: content rectangle, overflow, capture and pool counts;
- input: focus, Escape and drag ownership per player;
- manifest: schema, input and generated artifact hashes.

High-volume detail is a separate category and is never enabled by the master
switch alone. Diagnostics do not log product payload contents unless the
consumer explicitly supplies a safe, bounded representation.

```lua
SiK.UI.Diagnostics.registerSink("MyMod", {
    enabled = function() return MyMod.debugUI() end,
    sink = function(event) MyMod.Log.debug("UI", event.kind, event.message) end,
})
```

Consumers that unload dynamically call `unregisterSink(ownerId)`. When neither
the framework sink nor any consumer sink is enabled, navigation does not inspect
mounted content and tree traversal is never performed.
