# Refactor procedure

This procedure migrates an existing product interface without redesigning an
accepted visual reference or moving product mechanics into the framework.

## 1. Freeze and inventory

1. Record the source tree, visible states and content hashes.
2. Assign stable surface IDs and list owners, callers, assets, translations,
   actions, profiles and lifecycle paths.
3. Identify reusable behavior and product-only semantics separately.
4. Record the existing runtime reference; do not infer it from an outdated
   mockup or catalog placeholder.

## 2. Establish the framework contract

1. Select an existing canonical component or extend one parameterized behavior.
2. Avoid new public types for rows, pagers, modal chrome or visual variants.
3. Add typed props/capabilities/tokens to manifest and schema.
4. Add deterministic validation for invalid composition and references.
5. Keep action implementations in the product allowlist/adapter.

## 3. Describe the product surface

1. Create a non-empty, product-owned surface spec.
2. Declare one layout per node and explicit profile overrides.
3. Resolve owner/caller symbols, assets, i18n and actions.
4. Use exclusive composition modes: Form controls or fields data;
   CardCollection cards or items data; Tabs content IDs for direct children.
5. Generate HTML, Lua data and provenance from the same ordered inputs.

## 4. Integrate one surface

1. Pin the generated runtime artifact to its framework manifest hash.
2. Validate the artifact before construction.
3. Map external `actionId` entries to product-owned implementations.
4. Reproduce the accepted geometry, content, interactions and disposal paths.
5. Record any mismatch as an open surface limitation; do not hide it behind a
   local fallback.

## 5. Remove the duplicate

1. Migrate every caller of the responsibility.
2. Confirm no product reaches into private framework modules.
3. Add a bounded product-owned compatibility adapter only when required.
4. Remove the legacy implementation after the ledger records its replacement
   and removal condition as complete.

## Technical gates per surface

- closed schema and semantic validation;
- owner, caller, action, token, asset and i18n resolution;
- deterministic regeneration and provenance verification;
- runtime artifact subset/identity validation;
- Lua/Kahlua static validation of the consuming integration;
- lifecycle, resize, input isolation and cleanup checks;
- visual and interaction comparison with the accepted reference;
- runtime exercise in the actual product environment.

Catalog validation and generated preview success do not substitute for the last
three gates. Runtime observations take precedence over assumptions in a spec or
preview and reopen the affected surface when they differ.

## Required public record

The migration ledger records surface ID, owner, old/new entry points, artifact
hashes, status, remaining limitations and any adapter removal release. Public
documentation describes technical contracts and results; product-internal
workflow and local machine paths are not part of the framework API.
