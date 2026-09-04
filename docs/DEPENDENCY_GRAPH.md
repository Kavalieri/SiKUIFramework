# Dependency graph

SiK UI Framework is an independent Project Zomboid mod and Git repository. It
is neither part of Global Storage SiK nor one of its addons.

## Runtime graph

```text
SiKUIFramework (SiK.UI)
  <- Global Storage SiK Core (GSSiK.API)
       <- Craft addon
       <- Builder addon
       <- Tablet addon
  <- Manure Manager SiK (dependency declared; custom surfaces use SiK.UI)

SiK Corpse Loot Guard remains vanilla-first unless it gains a real custom UI
requirement.
```

| Consumer | Declared dependencies after migration | Product boundary |
|---|---|---|
| SiK UI Framework | none | `SiK.UI` |
| Global Storage SiK Core | `SiKUIFramework` | `GSSiK.API` |
| Global Storage SiK Craft | `SiKUIFramework`, Global Storage Core | `SiK.UI` + `GSSiK.API` |
| Global Storage SiK Builder | `SiKUIFramework`, Global Storage Core | `SiK.UI` + `GSSiK.API` |
| Global Storage SiK Tablet | `SiKUIFramework`, Global Storage Core | `SiK.UI` + `GSSiK.API` |
| Manure Manager SiK | `SiKUIFramework` (currently declared) | `MMSiK.API` |
| SiK Corpse Loot Guard | none at present | `SCLGSiK.API` |

The table describes the dependency boundary, not visual or ingame acceptance.
Manure currently declares the framework and its two custom surfaces consume
public `SiK.UI`; the former `MM_UIChrome` helper is removed in the current
working tree. Corpse Loot Guard has no custom SiK UI surface and therefore
declares no framework dependency.

## Catalog and generation graph

```text
framework schema + framework manifest + generator sources
                              |
product-owned surface spec ---+--> staged validation
                                      |
                                      +--> structural HTML preview
                                      +--> minimal Lua data artifact
                                      +--> provenance JSON
```

The editor reads and writes product surface specs. It does not become the
source of product data or action implementations. The full framework manifest
and editor are development inputs and are not loaded wholesale at runtime.

## Ownership boundary

- Framework: components, facilities, tokens, lifecycle, schema, validator,
  editor and deterministic generator.
- Product: surfaces, translations, assets, caller/owner symbols, action
  allowlists and mechanics.
- Generated artifact: immutable bridge pinned to framework/spec/generator
  hashes; it is not a new source of product authority.

Products do not import another repository's private files. Official addons
follow the same public-boundary rule as third-party consumers. A missing
required framework is an explicit dependency error; it does not activate an
embedded copy.
