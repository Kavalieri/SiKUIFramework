# SiK UI Framework

The public composition hierarchy and Card/Container boundary are documented in
[`docs/SIK_UI_COMPOSITION_MODEL.md`](docs/SIK_UI_COMPOSITION_MODEL.md).

SiK UI Framework is a standalone, client-side UI composition framework for
Project Zomboid. Its only public namespace is `SiK.UI`; it is not a Global
Storage SiK addon and does not import product mechanics, product assets,
network commands, persistence, permissions or translations.

## Status and compatibility

The publishable mod ID is `SiKUIFramework`. Kava has fixed the common minimum
for the framework and every SiK product/addon at Project Zomboid Build 42.20,
so `mod.info` and its human-readable description both declare 42.20+. This is
a client Lua framework; it is not a server API. The API remains **preview**
until the complete integrated candidate receives runtime and QA acceptance.

The runtime, manifest, validator, generator and editor exist in this tree.
That does not mean a product surface is migrated, visually equivalent in game,
or accepted by QA. No `SiK.UI` public contract is stable or QA-ready yet.

## Start here

1. Declare `SiKUIFramework` as a dependency in the consuming mod:

   ```text
   require=SiKUIFramework
   ```

   When the consumer also requires another mod, use the normal comma-separated
   `mod.info` list, for example `require=SiKUIFramework,GlobalStorageSiK`.
2. Load `SiK_UI` from client UI code, then use only `SiK.UI` public modules.
3. Use [the runtime reference](docs/RUNTIME_REFERENCE.md) for exact
   constructors, events, reflow and disposal requirements.
4. For a declarative surface, validate first with `SiK.UI.validateSurface` and
   construct it with `SiK.UI.buildSurface`.
5. Keep product data, actions, authority, i18n and assets in the consuming
   product. The framework receives bounded callbacks and descriptors only.

Minimal imperative example:

```lua
require "SiK_UI"

local window, err = SiK.UI.Window.create({
    playerNum = 0,
    profile = "standard",
    header = { productName = "Example" },
    footer = { items = { "Example 0.1" }, align = "center" },
})
if not window then error(err) end

local button = SiK.UI.Controls.button(window, {
    x = 8, y = 8, w = 160, h = 30, text = "Close",
    onClick = function() window:close("example") end,
})
window:show()
```

The consumer owns both instances and must dispose them when its surface ends.
Do not treat the example as an in-game compatibility test.

The dependency is mandatory, not optional. If the ModID or `SiK.UI` bootstrap
is missing, the consumer must fail explicitly and stop constructing that
surface. Do not ship a copied subset, hidden fallback, product namespace alias
or hand-painted replacement for the missing framework. A product that truly
supports operation without SiK UI must keep that non-UI path independent; it
must not pretend that a framework surface was built.

## Documentation map

- [Public API](docs/SIK_UI_API.md): public boundary and error convention.
- [Runtime reference](docs/RUNTIME_REFERENCE.md): every current public
  constructor/facility, schema, events, reflow and disposal requirements.
- [Component catalog](docs/SIK_UI_COMPONENT_CATALOG.md): one canonical tool
  per presentation responsibility.
- [Lifecycle and ownership](docs/SIK_UI_LIFECYCLE_AND_OWNERSHIP.md): explicit
  owner rules, builder tree lifecycle and input scope.
- [Window](docs/WINDOW.md) and [Tabs](docs/TABS.md): detailed shell/navigation
  contracts.
- [Data specification schema](docs/SIK_UI_DATA_SPEC_SCHEMA.md): generated
  runtime-surface boundary.
- [Dependency graph](docs/DEPENDENCY_GRAPH.md): standalone ModID, consumer and
  product-API boundaries.
- [Migration and deprecation ledger](docs/MIGRATION_AND_DEPRECATION_LEDGER.md):
  current extraction/migration/removal state.
- [Refactor procedure](docs/REFACTOR_PROCEDURE.md): inventory, recovery and
  evidence sequence for consumer migrations.
- [Debugging](docs/DEBUGGING.md): diagnostics boundary and current gaps.

## Repository layout

- `SiKUIFramework/`: publishable Project Zomboid mod.
- `catalog/`: preview manifest, schema, validator, generator and editor.
- `docs/`: public contracts and migration record.
- `tests/`: local QA/authoring checks. This directory is intentionally ignored
  and is not distributed in the public repository or Workshop artifact; its
  results are not game acceptance evidence.

## Policy gaps

`PENDING_KAVA`: this repository currently has no declared license, copyright
policy, public repository URL, support channel or contribution policy. This README therefore
does not invent reuse permission, attribution terms, contribution workflow or
support promises. Those decisions must be supplied by the project owner before
they can be published.

## Español

SiK UI Framework es un framework independiente de composición de interfaz para
Project Zomboid, de cliente y reutilizable. Su único espacio público es
`SiK.UI`; no es un addon de Global Storage SiK ni importa mecánicas, recursos,
comandos de red, persistencia, permisos o traducciones de productos.

El ModID publicable es `SiKUIFramework`. Kava ha fijado Build 42.20 como
mínimo común del framework y de todos los productos/addons SiK; `mod.info` y la
descripción visible declaran por tanto 42.20+. La API continúa en **preview**
hasta superar la aceptación runtime y QA del candidato integrado; ningún
componente se declara todavía estable o `QA_READY`.

Para empezar: declara la dependencia, carga `SiK_UI` solo desde código visual
de cliente, consume los módulos `SiK.UI` documentados y conserva datos,
acciones, autoridad, traducciones y recursos dentro del mod consumidor. La
referencia técnica en inglés de arriba es la fuente contractual completa; esta
sección solo resume su alcance.
