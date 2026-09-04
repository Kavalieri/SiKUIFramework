(function (root, factory) {
  "use strict";
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.SiKUIModel = api;
}(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const IDENTIFIER = /^[a-z][a-z0-9]*(?:[._:-][a-z0-9]+)*$/;
  const PROP_IDENTIFIER = /^[a-z][A-Za-z0-9]*(?:[._:-][a-z0-9][A-Za-z0-9]*)*$/;
  const SYMBOL = /^[A-Za-z][A-Za-z0-9_.:]*$/;
  const MODULE_ID = /^[A-Za-z_][A-Za-z0-9_]*(?:\/[A-Za-z_][A-Za-z0-9_]*)*$/;
  const DATA_PATH = /^[A-Za-z][A-Za-z0-9_.]*$/;
  const EVENTS = new Set(["activate", "change", "submit", "cancel", "hover", "contextmenu", "dragstart", "dragover", "drop", "dragcancel"]);

  function fail(errors, path, message) {
    errors.push({ path, message });
  }

  function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function exactKeys(errors, value, required, optional, path) {
    if (!isObject(value)) {
      fail(errors, path, "expected object");
      return false;
    }
    const allowed = new Set(required.concat(optional || []));
    for (const key of Object.keys(value)) if (!allowed.has(key)) fail(errors, `${path}.${key}`, "unexpected property");
    for (const key of required) if (!Object.prototype.hasOwnProperty.call(value, key)) fail(errors, `${path}.${key}`, "required property missing");
    return true;
  }

  function uniqueByKey(errors, entries, key, path, pattern) {
    if (!Array.isArray(entries)) {
      fail(errors, path, "expected array");
      return new Map();
    }
    const result = new Map();
    entries.forEach((entry, index) => {
      const itemPath = `${path}[${index}]`;
      const value = isObject(entry) ? entry[key] : undefined;
      if (typeof value !== "string" || !(pattern || IDENTIFIER).test(value)) {
        fail(errors, `${itemPath}.${key}`, "invalid identifier");
        return;
      }
      if (result.has(value)) fail(errors, `${itemPath}.${key}`, `duplicate ${key} '${value}'`);
      else result.set(value, entry);
    });
    return result;
  }

  function uniqueById(errors, entries, path) {
    return uniqueByKey(errors, entries, "id", path);
  }

  function stableValue(value) {
    if (Array.isArray(value)) return value.map(stableValue);
    if (!isObject(value)) return value;
    const result = {};
    Object.keys(value).sort().forEach((key) => { result[key] = stableValue(value[key]); });
    return result;
  }

  function stableStringify(value) {
    return `${JSON.stringify(stableValue(value), null, 2)}\n`;
  }

  function validateFramework(manifest) {
    const errors = [];
    if (!exactKeys(errors, manifest,
      ["documentKind", "schemaId", "schemaVersion", "framework", "events", "profiles", "tokens", "layout", "capabilities", "components"], [], "framework")) return errors;
    if (manifest.documentKind !== "framework-manifest") fail(errors, "framework.documentKind", "must equal framework-manifest");
    if (manifest.schemaId !== "sik-ui-catalog-v1" || manifest.schemaVersion !== 1) fail(errors, "framework.schemaVersion", "unsupported schema");
    if (!exactKeys(errors, manifest.framework, ["id", "namespace", "manifestVersion"], [], "framework.framework")) return errors;
    if (manifest.framework.id !== "SiKUIFramework" || manifest.framework.namespace !== "SiK.UI") fail(errors, "framework.framework", "standalone identity must be SiKUIFramework / SiK.UI");
    if (Object.prototype.hasOwnProperty.call(manifest, "surfaces")) fail(errors, "framework.surfaces", "product surfaces are forbidden in the framework manifest");

    if (!Array.isArray(manifest.events) || manifest.events.length === 0) fail(errors, "framework.events", "at least one event is required");
    else {
      const seenEvents = new Set();
      manifest.events.forEach((event, index) => {
        if (!EVENTS.has(event)) fail(errors, `framework.events[${index}]`, `unsupported event '${event}'`);
        if (seenEvents.has(event)) fail(errors, `framework.events[${index}]`, `duplicate event '${event}'`);
        seenEvents.add(event);
      });
    }

    const profiles = uniqueById(errors, manifest.profiles, "framework.profiles");
    ["compact", "standard", "wide"].forEach((id) => { if (!profiles.has(id)) fail(errors, "framework.profiles", `missing canonical profile '${id}'`); });
    const tokens = uniqueById(errors, manifest.tokens, "framework.tokens");
    tokens.forEach((token, id) => {
      exactKeys(errors, token, ["id", "kind", "value", "runtime"], [], `framework.tokens.${id}`);
      if (token.kind === "number" && typeof token.value !== "number") fail(errors, `framework.tokens.${id}.value`, "number token requires number value");
      if ((token.kind === "color" || token.kind === "string") && typeof token.value !== "string") fail(errors, `framework.tokens.${id}.value`, "string/color token requires string value");
    });

    exactKeys(errors, manifest.layout, ["modes", "bindings"], [], "framework.layout");
    if (!Array.isArray(manifest.layout && manifest.layout.modes) || manifest.layout.modes.length === 0) fail(errors, "framework.layout.modes", "at least one layout mode is required");
    else {
      const modes = new Set();
      manifest.layout.modes.forEach((mode, index) => {
        if (!IDENTIFIER.test(mode || "")) fail(errors, `framework.layout.modes[${index}]`, "invalid layout mode");
        if (modes.has(mode)) fail(errors, `framework.layout.modes[${index}]`, `duplicate layout mode '${mode}'`);
        modes.add(mode);
      });
    }
    const layoutBindings = uniqueByKey(errors, manifest.layout && manifest.layout.bindings, "name", "framework.layout.bindings");
    layoutBindings.forEach((binding, name) => {
      exactKeys(errors, binding, ["name", "valueKinds"], [], `framework.layout.bindings.${name}`);
      if (!Array.isArray(binding.valueKinds) || binding.valueKinds.length === 0) fail(errors, `framework.layout.bindings.${name}.valueKinds`, "at least one value kind is required");
      else binding.valueKinds.forEach((kind) => { if (!["number", "string", "boolean", "token", "data"].includes(kind)) fail(errors, `framework.layout.bindings.${name}.valueKinds`, `unsupported value kind '${kind}'`); });
    });

    const components = uniqueById(errors, manifest.components, "framework.components");
    components.forEach((component, id) => {
      exactKeys(errors, component,
        ["id", "runtimeFactory", "htmlTag", "htmlClass", "events", "allowedChildren", "props", "supportsColumns", "supportsOptions", "editorGroup"], [], `framework.components.${id}`);
      if (!SYMBOL.test(component.runtimeFactory || "") || !component.runtimeFactory.startsWith("SiK.UI.")) fail(errors, `framework.components.${id}.runtimeFactory`, "factory must use SiK.UI");
      if (!Array.isArray(component.events)) fail(errors, `framework.components.${id}.events`, "expected array");
      else {
        const componentEvents = new Set();
        component.events.forEach((event, index) => {
          if (!EVENTS.has(event) || !(manifest.events || []).includes(event)) fail(errors, `framework.components.${id}.events[${index}]`, `unsupported event '${event}'`);
          if (componentEvents.has(event)) fail(errors, `framework.components.${id}.events[${index}]`, `duplicate event '${event}'`);
          componentEvents.add(event);
        });
      }
      if (!Array.isArray(component.allowedChildren)) fail(errors, `framework.components.${id}.allowedChildren`, "expected array");
      if (!Array.isArray(component.props)) fail(errors, `framework.components.${id}.props`, "expected array");
      else {
        uniqueByKey(errors, component.props, "name", `framework.components.${id}.props`, PROP_IDENTIFIER);
        component.props.forEach((prop, index) => {
          const propPath = `framework.components.${id}.props[${index}]`;
          exactKeys(errors, prop, ["name", "kind", "required"], ["default", "enum"], propPath);
          if (!["string", "number", "boolean", "i18n", "asset", "token", "data"].includes(prop.kind)) fail(errors, `${propPath}.kind`, "unsupported prop kind");
          if (typeof prop.required !== "boolean") fail(errors, `${propPath}.required`, "expected boolean");
          if (Object.prototype.hasOwnProperty.call(prop, "default")) validateTypedBinding(errors, prop.default, prop, `${propPath}.default`, { i18n: new Set(), asset: new Set(), token: new Set() });
          if (prop.enum && (!Array.isArray(prop.enum) || prop.enum.length === 0)) fail(errors, `${propPath}.enum`, "enum cannot be empty");
        });
      }
    });
    components.forEach((component, id) => {
      if (Array.isArray(component.allowedChildren)) component.allowedChildren.forEach((child) => {
        if (!components.has(child)) fail(errors, `framework.components.${id}.allowedChildren`, `unknown child component '${child}'`);
      });
    });

    const capabilities = uniqueById(errors, manifest.capabilities, "framework.capabilities");
    capabilities.forEach((capability, id) => {
      exactKeys(errors, capability, ["id", "componentType", "props"], [], `framework.capabilities.${id}`);
      if (!components.has(capability.componentType)) fail(errors, `framework.capabilities.${id}.componentType`, "unknown component type");
      uniqueByKey(errors, capability.props, "name", `framework.capabilities.${id}.props`, PROP_IDENTIFIER);
      capability.props.forEach((prop, index) => {
        const propPath = `framework.capabilities.${id}.props[${index}]`;
        exactKeys(errors, prop, ["name", "kind", "required"], ["default", "enum"], propPath);
        if (!["string", "number", "boolean", "i18n", "asset", "token", "data"].includes(prop.kind)) fail(errors, `${propPath}.kind`, "unsupported prop kind");
        if (Object.prototype.hasOwnProperty.call(prop, "default")) validateTypedBinding(errors, prop.default, prop, `${propPath}.default`, { i18n: new Set(), asset: new Set(), token: new Set() });
      });
    });
    return errors;
  }

  function bindingKind(value) {
    if (!isObject(value) || !value.kind) return "literal";
    return value.kind;
  }

  function literalValue(value) {
    return isObject(value) && value.kind === "literal" ? value.value : value;
  }

  function validateTypedBinding(errors, value, definition, path, references) {
    const kind = bindingKind(value);
    if (["i18n", "asset", "token", "data"].includes(definition.kind)) {
      if (kind !== definition.kind && !(definition.kind === "data" && kind === "state")) {
        fail(errors, path, `expected ${definition.kind} binding`);
        return;
      }
      if (definition.kind === "data" && (typeof value.path !== "string" || !DATA_PATH.test(value.path))) fail(errors, path, "invalid data/state path");
      if (definition.kind !== "data" && (!references[definition.kind] || !references[definition.kind].has(value.ref))) fail(errors, path, `unresolved ${definition.kind} '${value.ref}'`);
      return;
    }
    if (kind !== "literal") {
      fail(errors, path, `expected literal ${definition.kind}`);
      return;
    }
    const actual = literalValue(value);
    if (definition.kind === "string" && typeof actual !== "string") fail(errors, path, "expected string");
    if (definition.kind === "number" && (typeof actual !== "number" || !Number.isFinite(actual))) fail(errors, path, "expected finite number");
    if (definition.kind === "boolean" && typeof actual !== "boolean") fail(errors, path, "expected boolean");
    if (Array.isArray(definition.enum) && !definition.enum.includes(actual)) fail(errors, path, `value '${actual}' is outside the declared enum`);
  }

  function validateSurface(framework, spec, options) {
    const runtimeProjection = Boolean(options && options.runtimeProjection);
    const errors = validateFramework(framework).map((entry) => ({ path: entry.path, message: entry.message }));
    if (!exactKeys(errors, spec,
      runtimeProjection
        ? ["documentKind", "schemaId", "schemaVersion", "frameworkRef", "product", "surface", "surfaceReferences", "assets", "i18n", "actionAllowlist"]
        : ["documentKind", "schemaId", "schemaVersion", "frameworkRef", "visualBaseline", "product", "surface", "surfaceReferences", "assets", "i18n", "actionAllowlist", "contracts", "runtime"], [], "spec")) return errors;
    if (spec.documentKind !== "product-surface-spec") fail(errors, "spec.documentKind", "must equal product-surface-spec");
    if (spec.schemaId !== "sik-ui-catalog-v1" || spec.schemaVersion !== 1) fail(errors, "spec.schemaVersion", "unsupported schema");
    exactKeys(errors, spec.frameworkRef, ["id", "manifestSha256"], [], "spec.frameworkRef");
    if (spec.frameworkRef && spec.frameworkRef.id !== "SiKUIFramework") fail(errors, "spec.frameworkRef.id", "must reference SiKUIFramework");
    if (options && options.frameworkSha256 && spec.frameworkRef && spec.frameworkRef.manifestSha256 !== options.frameworkSha256) fail(errors, "spec.frameworkRef.manifestSha256", "framework manifest hash mismatch");
    if (!runtimeProjection) {
      exactKeys(errors, spec.visualBaseline,
        ["masterPath", "masterSha256", "selector", "canonicalizer", "subtreeSha256", "validation"], [], "spec.visualBaseline");
      if (!spec.visualBaseline || typeof spec.visualBaseline.masterPath !== "string" || spec.visualBaseline.masterPath.length === 0) fail(errors, "spec.visualBaseline.masterPath", "expected relative master path");
      if (!spec.visualBaseline || !["sik-ui-visual-v1", "sik-ui-dom-v2"].includes(spec.visualBaseline.canonicalizer)) fail(errors, "spec.visualBaseline.canonicalizer", "unsupported visual canonicalizer");
      ["masterSha256", "subtreeSha256"].forEach((key) => {
        if (!/^[a-f0-9]{64}$/.test((spec.visualBaseline && spec.visualBaseline[key]) || "")) fail(errors, `spec.visualBaseline.${key}`, "invalid sha256");
      });
      if (!spec.visualBaseline || typeof spec.visualBaseline.selector !== "string" || !/^\[data-surface-id=(?:"[a-z][a-z0-9-]*"|'[a-z][a-z0-9-]*')\]$/.test(spec.visualBaseline.selector)) fail(errors, "spec.visualBaseline.selector", "unsupported visual selector");
      if (!spec.visualBaseline || typeof spec.visualBaseline.validation !== "string" || !/^[A-Z][A-Z0-9_]{2,63}$/.test(spec.visualBaseline.validation)) fail(errors, "spec.visualBaseline.validation", "invalid validation marker");
    }
    exactKeys(errors, spec.product, ["id", "namespace"], [], "spec.product");
    if (spec.product && (!IDENTIFIER.test(spec.product.id || "") || !SYMBOL.test(spec.product.namespace || ""))) fail(errors, "spec.product", "invalid product identity");
    exactKeys(errors, spec.surface, ["id", "kind", "owner", "callers", "profiles", "root"], [], "spec.surface");

    const profiles = new Map((framework.profiles || []).map((profile) => [profile.id, profile]));
    if (!Array.isArray(spec.surface && spec.surface.profiles) || spec.surface.profiles.length === 0) fail(errors, "spec.surface.profiles", "at least one profile is required");
    else spec.surface.profiles.forEach((profile, index) => { if (!profiles.has(profile)) fail(errors, `spec.surface.profiles[${index}]`, `unknown profile '${profile}'`); });

    const assets = uniqueById(errors, spec.assets, "spec.assets");
    const i18n = uniqueById(errors, spec.i18n, "spec.i18n");
    const actions = uniqueById(errors, spec.actionAllowlist, "spec.actionAllowlist");
    const surfaceReferences = uniqueById(errors, spec.surfaceReferences, "spec.surfaceReferences");
    surfaceReferences.forEach((reference, id) => {
      exactKeys(errors, reference, ["id", "repository", "specPath", "sha256"], [], `spec.surfaceReferences.${id}`);
      if (!IDENTIFIER.test(reference.repository || "")) fail(errors, `spec.surfaceReferences.${id}.repository`, "invalid repository identifier");
      if (typeof reference.specPath !== "string" || reference.specPath.length === 0 || reference.specPath.includes("\\") || /^(?:[A-Za-z]:|\/)/.test(reference.specPath) || reference.specPath.split("/").includes("..")) fail(errors, `spec.surfaceReferences.${id}.specPath`, "invalid relative surface path");
      if (!/^[a-f0-9]{64}$/.test(reference.sha256 || "")) fail(errors, `spec.surfaceReferences.${id}.sha256`, "invalid sha256");
    });
    assets.forEach((asset, id) => {
      exactKeys(errors, asset, runtimeProjection ? ["id", "path", "sha256"] : ["id", "sourcePath", "runtimePath", "sha256"], [], `spec.assets.${id}`);
      const sourcePath = runtimeProjection ? asset.path : asset.sourcePath;
      if (typeof sourcePath !== "string" || sourcePath.length === 0 || sourcePath.includes("\\") || /^(?:[A-Za-z]:|\/)/.test(sourcePath) || sourcePath.split("/").includes("..")) fail(errors, `spec.assets.${id}.${runtimeProjection ? "path" : "sourcePath"}`, "invalid relative asset path");
      if (!runtimeProjection && (typeof asset.runtimePath !== "string" || !asset.runtimePath.startsWith("media/") || asset.runtimePath.includes("\\") || asset.runtimePath.split("/").includes(".."))) fail(errors, `spec.assets.${id}.runtimePath`, "runtime asset path must be a relative media/... path");
      if (!/^[a-f0-9]{64}$/.test(asset.sha256 || "")) fail(errors, `spec.assets.${id}.sha256`, "invalid sha256");
    });
    i18n.forEach((entry, id) => {
      exactKeys(errors, entry, ["id", "translations"], [], `spec.i18n.${id}`);
      if (!Array.isArray(entry.translations) || entry.translations.length === 0) fail(errors, `spec.i18n.${id}.translations`, "at least one translation is required");
      else {
        const locales = new Set();
        entry.translations.forEach((translation, index) => {
          const translationPath = `spec.i18n.${id}.translations[${index}]`;
          exactKeys(errors, translation, ["locale", "text"], [], translationPath);
          if (locales.has(translation.locale)) fail(errors, `${translationPath}.locale`, `duplicate locale '${translation.locale}'`);
          locales.add(translation.locale);
          if (typeof translation.text !== "string") fail(errors, `${translationPath}.text`, "expected string");
        });
      }
    });
    const frameworkEvents = new Set(framework.events || []);
    actions.forEach((action, id) => {
      exactKeys(errors, action, ["id", "events"], [], `spec.actionAllowlist.${id}`);
      if (!Array.isArray(action.events) || action.events.length === 0) fail(errors, `spec.actionAllowlist.${id}.events`, "at least one event is required");
      else action.events.forEach((event) => { if (!frameworkEvents.has(event)) fail(errors, `spec.actionAllowlist.${id}.events`, `unsupported event '${event}'`); });
    });

    function validateModule(reference, path) {
      exactKeys(errors, reference, ["repository", "modulePath", "symbol"], [], path);
      if (reference && !SYMBOL.test(reference.symbol || "")) fail(errors, `${path}.symbol`, "invalid symbol");
    }

    const dataContracts = new Map();
    const stateContracts = new Map();
    const payloadContracts = new Map();
    function validateValueContract(contract, path) {
      if (!exactKeys(errors, contract, ["type"], ["nullable", "properties", "items"], path)) return;
      if (!["string", "number", "boolean", "object", "array", "any"].includes(contract.type)) fail(errors, `${path}.type`, "unsupported value contract type");
      if (Object.prototype.hasOwnProperty.call(contract, "nullable") && typeof contract.nullable !== "boolean") fail(errors, `${path}.nullable`, "expected boolean");
      if (contract.type === "object") {
        if (!Array.isArray(contract.properties)) fail(errors, `${path}.properties`, "object contract requires properties");
        else {
          const names = new Set();
          contract.properties.forEach((property, index) => {
            const propertyPath = `${path}.properties[${index}]`;
            exactKeys(errors, property, ["name", "required", "schema"], [], propertyPath);
            if (typeof property.name !== "string" || !DATA_PATH.test(property.name)) fail(errors, `${propertyPath}.name`, "invalid property name");
            if (names.has(property.name)) fail(errors, `${propertyPath}.name`, `duplicate property '${property.name}'`);
            names.add(property.name);
            if (typeof property.required !== "boolean") fail(errors, `${propertyPath}.required`, "expected boolean");
            validateValueContract(property.schema, `${propertyPath}.schema`);
          });
        }
      } else if (Object.prototype.hasOwnProperty.call(contract, "properties")) fail(errors, `${path}.properties`, "properties are only valid for object contracts");
      if (contract.type === "array") {
        if (!contract.items) fail(errors, `${path}.items`, "array contract requires items");
        else validateValueContract(contract.items, `${path}.items`);
      } else if (Object.prototype.hasOwnProperty.call(contract, "items")) fail(errors, `${path}.items`, "items are only valid for array contracts");
    }
    function validatePathContracts(entries, path, target) {
      if (!Array.isArray(entries)) { fail(errors, path, "expected array"); return; }
      entries.forEach((entry, index) => {
        const entryPath = `${path}[${index}]`;
        exactKeys(errors, entry, ["path", "schema"], [], entryPath);
        if (typeof entry.path !== "string" || !DATA_PATH.test(entry.path)) fail(errors, `${entryPath}.path`, "invalid data/state path");
        else if (target.has(entry.path)) fail(errors, `${entryPath}.path`, `duplicate contract path '${entry.path}'`);
        else target.set(entry.path, entry);
        validateValueContract(entry.schema, `${entryPath}.schema`);
      });
    }
    if (!runtimeProjection) {
      if (exactKeys(errors, spec.contracts, ["data", "state", "actionPayloads"], [], "spec.contracts")) {
        validatePathContracts(spec.contracts.data, "spec.contracts.data", dataContracts);
        validatePathContracts(spec.contracts.state, "spec.contracts.state", stateContracts);
        stateContracts.forEach((entry, path) => { if (dataContracts.has(path)) fail(errors, "spec.contracts.state", `path '${path}' is declared as both data and state`); });
        if (!Array.isArray(spec.contracts.actionPayloads)) fail(errors, "spec.contracts.actionPayloads", "expected array");
        else spec.contracts.actionPayloads.forEach((entry, index) => {
          const entryPath = `spec.contracts.actionPayloads[${index}]`;
          exactKeys(errors, entry, ["actionId", "event", "payload"], [], entryPath);
          const key = `${entry.actionId}|${entry.event}`;
          if (payloadContracts.has(key)) fail(errors, entryPath, `duplicate action payload contract '${key}'`);
          else payloadContracts.set(key, entry);
          validateValueContract(entry.payload, `${entryPath}.payload`);
        });
      }
      if (exactKeys(errors, spec.runtime, ["artifact", "loader", "callers"], [], "spec.runtime")) {
        exactKeys(errors, spec.runtime.artifact, ["repository", "moduleId", "modulePath"], [], "spec.runtime.artifact");
        if (!IDENTIFIER.test((spec.runtime.artifact && spec.runtime.artifact.repository) || "")) fail(errors, "spec.runtime.artifact.repository", "invalid repository identifier");
        if (spec.runtime.artifact && spec.surface && spec.runtime.artifact.repository !== spec.surface.owner.repository) fail(errors, "spec.runtime.artifact.repository", "runtime artifact must belong to the surface owner repository");
        if (!MODULE_ID.test((spec.runtime.artifact && spec.runtime.artifact.moduleId) || "")) fail(errors, "spec.runtime.artifact.moduleId", "invalid require-safe module id");
        const expectedSuffix = `${(spec.runtime.artifact && spec.runtime.artifact.moduleId) || ""}.lua`;
        if (typeof (spec.runtime.artifact && spec.runtime.artifact.modulePath) !== "string" || !spec.runtime.artifact.modulePath.endsWith(expectedSuffix)) fail(errors, "spec.runtime.artifact.modulePath", `artifact path must end with '${expectedSuffix}'`);
        if (exactKeys(errors, spec.runtime.loader, ["repository", "modulePath", "symbol", "builderSymbol"], [], "spec.runtime.loader")) {
          if (!SYMBOL.test(spec.runtime.loader.symbol || "")) fail(errors, "spec.runtime.loader.symbol", "invalid symbol");
          if (!SYMBOL.test(spec.runtime.loader.builderSymbol || "") || !spec.runtime.loader.builderSymbol.startsWith("SiK.UI.")) fail(errors, "spec.runtime.loader.builderSymbol", "builder symbol must use SiK.UI");
        }
        if (spec.runtime.loader && spec.surface && (spec.runtime.loader.repository !== spec.surface.owner.repository || spec.runtime.loader.modulePath !== spec.surface.owner.modulePath || spec.runtime.loader.symbol !== spec.surface.owner.symbol)) fail(errors, "spec.runtime.loader", "runtime loader must be the declared surface owner");
        if (!Array.isArray(spec.runtime.callers) || spec.runtime.callers.length === 0) fail(errors, "spec.runtime.callers", "at least one runtime caller is required");
        else {
          const expectedCallers = new Set((spec.surface.callers || []).map((caller) => `${caller.repository}|${caller.modulePath}|${caller.symbol}`));
          const actualCallers = new Set();
          spec.runtime.callers.forEach((caller, index) => {
            validateModule(caller, `spec.runtime.callers[${index}]`);
            actualCallers.add(`${caller.repository}|${caller.modulePath}|${caller.symbol}`);
          });
          expectedCallers.forEach((caller) => { if (!actualCallers.has(caller)) fail(errors, "spec.runtime.callers", `missing declared surface caller '${caller}'`); });
          actualCallers.forEach((caller) => { if (!expectedCallers.has(caller)) fail(errors, "spec.runtime.callers", `runtime caller is not declared by surface '${caller}'`); });
        }
      }
    }
    if (spec.surface) {
      validateModule(spec.surface.owner, "spec.surface.owner");
      if (!Array.isArray(spec.surface.callers) || spec.surface.callers.length === 0) fail(errors, "spec.surface.callers", "at least one caller is required");
      else spec.surface.callers.forEach((caller, index) => validateModule(caller, `spec.surface.callers[${index}]`));
    }

    const componentTypes = new Map((framework.components || []).map((component) => [component.id, component]));
    const tokenIds = new Set((framework.tokens || []).map((token) => token.id));
    const layoutModes = new Set((framework.layout && framework.layout.modes) || []);
    const layoutDefinitions = new Map(((framework.layout && framework.layout.bindings) || []).map((binding) => [binding.name, binding]));
    const nodeIds = new Set();
    const usedSurfaceReferences = new Set();

    function validateLayoutBindings(bindings, path) {
      if (!Array.isArray(bindings)) {
        fail(errors, path, "expected array");
        return;
      }
      const names = new Set();
      bindings.forEach((binding, index) => {
        const bindingPath = `${path}[${index}]`;
        exactKeys(errors, binding, ["name", "value"], [], bindingPath);
        if (names.has(binding.name)) fail(errors, `${bindingPath}.name`, `duplicate layout binding '${binding.name}'`);
        names.add(binding.name);
        const definition = layoutDefinitions.get(binding.name);
        if (!definition) {
          fail(errors, `${bindingPath}.name`, `unknown layout binding '${binding.name}'`);
          return;
        }
        const kind = bindingKind(binding.value);
        let valueKind = kind;
        if (kind === "literal") valueKind = typeof literalValue(binding.value);
        if (!definition.valueKinds.includes(valueKind)) fail(errors, `${bindingPath}.value`, `layout binding '${binding.name}' does not accept '${valueKind}'`);
        if (kind === "token" && !tokenIds.has(binding.value.ref)) fail(errors, `${bindingPath}.value`, `unresolved token '${binding.value.ref}'`);
        if (["data", "state"].includes(kind) && (typeof binding.value.path !== "string" || !DATA_PATH.test(binding.value.path))) fail(errors, `${bindingPath}.value`, "invalid data/state path");
        if (!runtimeProjection && kind === "data" && !dataContracts.has(binding.value.path)) fail(errors, `${bindingPath}.value`, `undeclared data path '${binding.value.path}'`);
        if (!runtimeProjection && kind === "state" && !stateContracts.has(binding.value.path)) fail(errors, `${bindingPath}.value`, `undeclared state path '${binding.value.path}'`);
      });
    }

    function validateLayout(layout, path) {
      if (!exactKeys(errors, layout, ["mode", "base", "overrides"], [], path)) return;
      if (!layoutModes.has(layout.mode)) fail(errors, `${path}.mode`, `unknown layout mode '${layout.mode}'`);
      validateLayoutBindings(layout.base, `${path}.base`);
      if (!Array.isArray(layout.overrides)) fail(errors, `${path}.overrides`, "expected array");
      else {
        const overrideProfiles = new Set();
        layout.overrides.forEach((override, index) => {
          const overridePath = `${path}.overrides[${index}]`;
          exactKeys(errors, override, ["profileId", "bindings"], [], overridePath);
          if (!profiles.has(override.profileId)) fail(errors, `${overridePath}.profileId`, `unknown profile '${override.profileId}'`);
          if (overrideProfiles.has(override.profileId)) fail(errors, `${overridePath}.profileId`, `duplicate profile override '${override.profileId}'`);
          overrideProfiles.add(override.profileId);
          validateLayoutBindings(override.bindings, `${overridePath}.bindings`);
        });
      }
    }

    function visit(node, parentType, path, isRoot) {
      if (!exactKeys(errors, node, ["id", "type", "variant", "layout", "props", "actions", "children"], ["visual", "state", "capabilities", "columns", "options"], path)) return;
      if (!IDENTIFIER.test(node.id || "")) fail(errors, `${path}.id`, "invalid node id");
      else if (nodeIds.has(node.id)) fail(errors, `${path}.id`, `duplicate node id '${node.id}'`);
      else nodeIds.add(node.id);
      if (node.visual) {
        exactKeys(errors, node.visual, ["visibleWhen"], [], `${path}.visual`);
        if (!IDENTIFIER.test(node.visual.visibleWhen || "")) fail(errors, `${path}.visual.visibleWhen`, "invalid visibility condition");
      }
      if (node.state) {
        exactKeys(errors, node.state, ["default", "options", "views"], [], `${path}.state`);
        const stateOptions = new Set();
        if (!Array.isArray(node.state.options) || node.state.options.length === 0) fail(errors, `${path}.state.options`, "state options cannot be empty");
        else node.state.options.forEach((value, index) => {
          if (!IDENTIFIER.test(value || "")) fail(errors, `${path}.state.options[${index}]`, "invalid state option");
          if (stateOptions.has(value)) fail(errors, `${path}.state.options[${index}]`, `duplicate state option '${value}'`);
          stateOptions.add(value);
        });
        if (!stateOptions.has(node.state.default)) fail(errors, `${path}.state.default`, "default state must be declared in options");
        const childIds = new Set(Array.isArray(node.children) ? node.children.map((child) => child.id) : []);
        if (!Array.isArray(node.state.views) || node.state.views.length === 0) fail(errors, `${path}.state.views`, "state views cannot be empty");
        else node.state.views.forEach((view, index) => {
          const viewPath = `${path}.state.views[${index}]`;
          if (!exactKeys(errors, view, ["contentId", "values"], [], viewPath)) return;
          if (!childIds.has(view.contentId)) fail(errors, `${viewPath}.contentId`, "state view must target a direct child");
          if (!Array.isArray(view.values) || view.values.length === 0) fail(errors, `${viewPath}.values`, "state view values cannot be empty");
          else view.values.forEach((value, valueIndex) => {
            if (!stateOptions.has(value)) fail(errors, `${viewPath}.values[${valueIndex}]`, `unknown state option '${value}'`);
          });
        });
      }
      const definition = componentTypes.get(node.type);
      if (!definition) fail(errors, `${path}.type`, `unknown component '${node.type}'`);
      if (parentType) {
        const parent = componentTypes.get(parentType);
        if (parent && !parent.allowedChildren.includes(node.type)) fail(errors, `${path}.type`, `'${node.type}' is not allowed below '${parentType}'`);
      }
      if (!Array.isArray(node.children)) fail(errors, `${path}.children`, "expected array");
      else if (isRoot && node.children.length === 0) fail(errors, `${path}.children`, "technical surface root cannot be empty");
      validateLayout(node.layout, `${path}.layout`);

      const props = Array.isArray(node.props) ? node.props : [];
      const propsByName = new Map();
      props.forEach((prop, index) => {
        exactKeys(errors, prop, ["name", "value"], [], `${path}.props[${index}]`);
        if (propsByName.has(prop.name)) fail(errors, `${path}.props[${index}].name`, `duplicate prop '${prop.name}'`);
        propsByName.set(prop.name, prop.value);
      });
      if (definition) {
        const definitions = new Map(definition.props.map((prop) => [prop.name, prop]));
        propsByName.forEach((value, name) => {
          const propDefinition = definitions.get(name);
          if (!propDefinition) {
            fail(errors, `${path}.props`, `unknown prop '${name}' for '${node.type}'`);
            return;
          }
          validateTypedBinding(errors, value, propDefinition, `${path}.props.${name}`, { i18n, asset: assets, token: tokenIds });
          const kind = bindingKind(value);
          if (!runtimeProjection && kind === "data" && !dataContracts.has(value.path)) fail(errors, `${path}.props.${name}`, `undeclared data path '${value.path}'`);
          if (!runtimeProjection && kind === "state" && !stateContracts.has(value.path)) fail(errors, `${path}.props.${name}`, `undeclared state path '${value.path}'`);
        });
        definition.props.filter((prop) => prop.required).forEach((prop) => {
          if (!propsByName.has(prop.name)) fail(errors, `${path}.props`, `required prop '${prop.name}' missing`);
        });
        if (node.columns && !definition.supportsColumns) fail(errors, `${path}.columns`, `'${node.type}' does not support columns`);
        if (node.options && !definition.supportsOptions) fail(errors, `${path}.options`, `'${node.type}' does not support options`);
      }
      if (node.columns) {
        if (!Array.isArray(node.columns) || node.columns.length === 0) fail(errors, `${path}.columns`, "columns cannot be empty");
        else {
          const keys = new Set();
          node.columns.forEach((column, index) => {
            exactKeys(errors, column, ["key", "labelRef", "align"], ["width", "flex", "min"], `${path}.columns[${index}]`);
            if (keys.has(column.key)) fail(errors, `${path}.columns[${index}].key`, `duplicate column '${column.key}'`);
            keys.add(column.key);
            if (!i18n.has(column.labelRef)) fail(errors, `${path}.columns[${index}].labelRef`, `unresolved i18n '${column.labelRef}'`);
            const fixed = Number.isFinite(column.width);
            const flexible = Number.isFinite(column.flex) && Number.isFinite(column.min);
            if (fixed === flexible) fail(errors, `${path}.columns[${index}]`, "use width or flex+min, exclusively");
          });
        }
      }
      if (node.options) {
        if (!Array.isArray(node.options) || node.options.length === 0) fail(errors, `${path}.options`, "options cannot be empty");
        else node.options.forEach((option, index) => {
          exactKeys(errors, option, ["id", "labelRef", "value"], ["contentId", "surfaceRef", "iconRef", "disabled", "reasonRef"], `${path}.options[${index}]`);
          if (!i18n.has(option.labelRef)) fail(errors, `${path}.options[${index}].labelRef`, `unresolved i18n '${option.labelRef}'`);
          if (option.iconRef && !assets.has(option.iconRef)) fail(errors, `${path}.options[${index}].iconRef`, `unresolved asset '${option.iconRef}'`);
          if (option.reasonRef && !i18n.has(option.reasonRef)) fail(errors, `${path}.options[${index}].reasonRef`, `unresolved i18n '${option.reasonRef}'`);
        });
      }
      if (node.capabilities) {
        const capabilityDefinitions = new Map((framework.capabilities || []).map((capability) => [capability.id, capability]));
        const capabilityIds = new Set();
        if (!Array.isArray(node.capabilities)) fail(errors, `${path}.capabilities`, "expected array");
        else node.capabilities.forEach((binding, index) => {
          const bindingPath = `${path}.capabilities[${index}]`;
          exactKeys(errors, binding, ["id", "props"], [], bindingPath);
          if (capabilityIds.has(binding.id)) fail(errors, `${bindingPath}.id`, `duplicate capability '${binding.id}'`);
          capabilityIds.add(binding.id);
          const capability = capabilityDefinitions.get(binding.id);
          if (!capability) fail(errors, `${bindingPath}.id`, `unknown capability '${binding.id}'`);
          else if (capability.componentType !== node.type) fail(errors, `${bindingPath}.id`, `'${binding.id}' does not apply to '${node.type}'`);
          const definitions = new Map((capability && capability.props || []).map((prop) => [prop.name, prop]));
          const values = new Map();
          if (!Array.isArray(binding.props)) fail(errors, `${bindingPath}.props`, "expected array");
          else binding.props.forEach((prop, propIndex) => {
            exactKeys(errors, prop, ["name", "value"], [], `${bindingPath}.props[${propIndex}]`);
            if (!definitions.has(prop.name)) fail(errors, `${bindingPath}.props[${propIndex}].name`, `unknown capability prop '${prop.name}'`);
            else validateTypedBinding(errors, prop.value, definitions.get(prop.name), `${bindingPath}.props[${propIndex}].value`, { i18n, asset: assets, token: tokenIds });
            const kind = bindingKind(prop.value);
            if (!runtimeProjection && kind === "data" && !dataContracts.has(prop.value.path)) fail(errors, `${bindingPath}.props[${propIndex}].value`, `undeclared data path '${prop.value.path}'`);
            if (!runtimeProjection && kind === "state" && !stateContracts.has(prop.value.path)) fail(errors, `${bindingPath}.props[${propIndex}].value`, `undeclared state path '${prop.value.path}'`);
            if (values.has(prop.name)) fail(errors, `${bindingPath}.props[${propIndex}].name`, `duplicate capability prop '${prop.name}'`);
            values.set(prop.name, prop.value);
          });
          definitions.forEach((prop) => { if (prop.required && !values.has(prop.name)) fail(errors, `${bindingPath}.props`, `required capability prop '${prop.name}' missing`); });
        });
      }
      const children = Array.isArray(node.children) ? node.children : [];
      const capabilityIds = new Set((node.capabilities || []).map((binding) => binding.id));
      if (node.type === "form") {
        const structuredFields = propsByName.has("fields") || capabilityIds.has("form.fields");
        if (structuredFields && children.length > 0) fail(errors, `${path}.children`, "form uses child controls or structured fields, never both");
      }
      if (node.type === "card-collection" && propsByName.has("items") && children.length > 0) {
        fail(errors, `${path}.children`, "card-collection uses child cards or items data, never both");
      }
      const isNavigationHost = node.type === "tabs" || capabilityIds.has("container.navigation");
      if (isNavigationHost) {
        const directChildren = new Set(children.map((child) => child.id));
        const targets = new Set();
        (node.options || []).forEach((option, index) => {
          const hasContent = Object.prototype.hasOwnProperty.call(option, "contentId");
          const hasSurface = Object.prototype.hasOwnProperty.call(option, "surfaceRef");
          if (hasContent === hasSurface) {
            fail(errors, `${path}.options[${index}]`, "navigation option requires exactly one contentId or surfaceRef");
            return;
          }
          if (hasContent) {
            if (!IDENTIFIER.test(option.contentId || "")) fail(errors, `${path}.options[${index}].contentId`, "stable direct child contentId required");
            else if (targets.has(`content:${option.contentId}`)) fail(errors, `${path}.options[${index}].contentId`, `duplicate tab contentId '${option.contentId}'`);
            else {
              targets.add(`content:${option.contentId}`);
              if (!directChildren.has(option.contentId)) fail(errors, `${path}.options[${index}].contentId`, `unresolved direct child '${option.contentId}'`);
            }
          } else if (!IDENTIFIER.test(option.surfaceRef || "")) {
            fail(errors, `${path}.options[${index}].surfaceRef`, "stable external surfaceRef required");
          } else if (targets.has(`surface:${option.surfaceRef}`)) {
            fail(errors, `${path}.options[${index}].surfaceRef`, `duplicate tab surfaceRef '${option.surfaceRef}'`);
          } else {
            targets.add(`surface:${option.surfaceRef}`);
            usedSurfaceReferences.add(option.surfaceRef);
            if (!surfaceReferences.has(option.surfaceRef)) fail(errors, `${path}.options[${index}].surfaceRef`, `unresolved surface reference '${option.surfaceRef}'`);
          }
        });
        children.forEach((child) => {
          if (!targets.has(`content:${child.id}`)) fail(errors, `${path}.children`, `unreferenced tab content '${child.id}'`);
        });
      } else {
        (node.options || []).forEach((option, index) => {
          if (Object.prototype.hasOwnProperty.call(option, "contentId")) fail(errors, `${path}.options[${index}].contentId`, "contentId is only valid for navigation hosts");
          if (Object.prototype.hasOwnProperty.call(option, "surfaceRef")) fail(errors, `${path}.options[${index}].surfaceRef`, "surfaceRef is only valid for navigation hosts");
        });
      }
      if (!Array.isArray(node.actions)) fail(errors, `${path}.actions`, "expected array");
      else node.actions.forEach((binding, index) => {
        exactKeys(errors, binding, ["event", "actionId"], [], `${path}.actions[${index}]`);
        const action = actions.get(binding.actionId);
        if (!action) fail(errors, `${path}.actions[${index}].actionId`, `unresolved action '${binding.actionId}'`);
        else if (!action.events.includes(binding.event)) fail(errors, `${path}.actions[${index}]`, `action '${binding.actionId}' does not allow '${binding.event}'`);
        if (definition && !definition.events.includes(binding.event)) fail(errors, `${path}.actions[${index}].event`, `'${node.type}' does not emit '${binding.event}'`);
        if (!runtimeProjection && !payloadContracts.has(`${binding.actionId}|${binding.event}`)) fail(errors, `${path}.actions[${index}]`, `missing payload contract for '${binding.actionId}' on '${binding.event}'`);
      });
      if (Array.isArray(node.children)) node.children.forEach((child, index) => visit(child, node.type, `${path}.children[${index}]`, false));
    }
    if (spec.surface && spec.surface.root) visit(spec.surface.root, null, "spec.surface.root", true);
    surfaceReferences.forEach((reference, id) => {
      if (!usedSurfaceReferences.has(id)) fail(errors, `spec.surfaceReferences.${id}`, "unused surface reference");
    });
    if (!runtimeProjection) {
      payloadContracts.forEach((entry, key) => {
        const action = actions.get(entry.actionId);
        if (!action) fail(errors, "spec.contracts.actionPayloads", `payload contract references unknown action '${entry.actionId}'`);
        else if (!action.events.includes(entry.event)) fail(errors, "spec.contracts.actionPayloads", `payload contract event '${entry.event}' is not allowed by '${entry.actionId}'`);
      });
    }
    return errors;
  }

  function componentIndex(framework) {
    return new Map(framework.components.map((component) => [component.id, component]));
  }

  function validateRuntimeArtifact(framework, artifact) {
    const errors = [];
    if (!exactKeys(errors, artifact,
      ["documentKind", "schemaId", "schemaVersion", "frameworkRef", "provenance", "profiles", "tokens", "componentFactories", "capabilities", "product", "surface", "surfaceReferences", "assets", "i18n", "actionAllowlist"], [], "runtime")) return errors;
    if (artifact.documentKind !== "sik-ui-runtime-surface") fail(errors, "runtime.documentKind", "must equal sik-ui-runtime-surface");
    if (artifact.schemaId !== "sik-ui-runtime-v1" || artifact.schemaVersion !== 1) fail(errors, "runtime.schemaVersion", "unsupported runtime schema");
    if (!exactKeys(errors, artifact.frameworkRef, ["id", "namespace", "manifestVersion", "manifestSha256"], [], "runtime.frameworkRef")) return errors;
    if (artifact.frameworkRef.id !== framework.framework.id || artifact.frameworkRef.namespace !== framework.framework.namespace || artifact.frameworkRef.manifestVersion !== framework.framework.manifestVersion) fail(errors, "runtime.frameworkRef", "framework identity/version mismatch");
    if (!exactKeys(errors, artifact.provenance,
      ["schemaSha256", "frameworkManifestSha256", "surfaceSpecSha256", "generatorSha256", "visualMasterSha256", "visualSubtreeSha256", "visualCanonicalizer"], [], "runtime.provenance")) return errors;
    if (artifact.frameworkRef.manifestSha256 !== artifact.provenance.frameworkManifestSha256) fail(errors, "runtime.frameworkRef.manifestSha256", "provenance mismatch");
    ["schemaSha256", "frameworkManifestSha256", "surfaceSpecSha256", "generatorSha256", "visualMasterSha256", "visualSubtreeSha256"].forEach((key) => {
      if (!/^[a-f0-9]{64}$/.test((artifact.provenance && artifact.provenance[key]) || "")) fail(errors, `runtime.provenance.${key}`, "invalid sha256");
    });
    if (artifact.provenance && !["sik-ui-visual-v1", "sik-ui-dom-v2"].includes(artifact.provenance.visualCanonicalizer)) fail(errors, "runtime.provenance.visualCanonicalizer", "unsupported visual canonicalizer");

    const inputSpec = {
      documentKind: "product-surface-spec",
      schemaId: "sik-ui-catalog-v1",
      schemaVersion: 1,
      frameworkRef: { id: artifact.frameworkRef.id, manifestSha256: artifact.frameworkRef.manifestSha256 },
      product: artifact.product,
      surface: artifact.surface,
      surfaceReferences: artifact.surfaceReferences,
      assets: artifact.assets,
      i18n: artifact.i18n,
      actionAllowlist: artifact.actionAllowlist
    };
    validateSurface(framework, inputSpec, { frameworkSha256: artifact.frameworkRef.manifestSha256, runtimeProjection: true }).forEach((entry) => fail(errors, `runtime.${entry.path}`, entry.message));

    const usedTypes = new Set();
    const usedCapabilities = new Set();
    const usedTokens = new Set();
    function collectBinding(binding, path) {
      if (binding && binding.kind === "state") fail(errors, path, "state bindings must be projected to runtime data bindings");
      if (binding && binding.kind === "token") usedTokens.add(binding.ref);
    }
    function collect(node) {
      usedTypes.add(node.type);
      (node.capabilities || []).forEach((capability) => usedCapabilities.add(capability.id));
      (node.props || []).forEach((prop, index) => collectBinding(prop.value, `runtime.surface.${node.id}.props[${index}]`));
      (node.capabilities || []).forEach((capability, capabilityIndex) => (capability.props || []).forEach((prop, propIndex) => collectBinding(prop.value, `runtime.surface.${node.id}.capabilities[${capabilityIndex}].props[${propIndex}]`)));
      const layoutBindings = (node.layout ? node.layout.base : []).concat(...((node.layout && node.layout.overrides) || []).map((override) => override.bindings));
      layoutBindings.forEach((binding, index) => collectBinding(binding.value, `runtime.surface.${node.id}.layout[${index}]`));
      (node.children || []).forEach(collect);
    }
    if (artifact.surface && artifact.surface.root) collect(artifact.surface.root);
    const factories = uniqueByKey(errors, artifact.componentFactories, "typeId", "runtime.componentFactories");
    const frameworkComponents = componentIndex(framework);
    usedTypes.forEach((type) => {
      const factory = factories.get(type);
      const definition = frameworkComponents.get(type);
      if (!factory) fail(errors, "runtime.componentFactories", `missing used component '${type}'`);
      else {
        exactKeys(errors, factory, ["typeId", "runtimeFactory"], [], `runtime.componentFactories.${type}`);
        if (!definition || factory.runtimeFactory !== definition.runtimeFactory) fail(errors, `runtime.componentFactories.${type}.runtimeFactory`, "factory mismatch");
      }
    });
    factories.forEach((factory, type) => { if (!usedTypes.has(type)) fail(errors, `runtime.componentFactories.${type}`, "unused component factory included"); });
    const runtimeProfiles = uniqueById(errors, artifact.profiles, "runtime.profiles");
    const expectedProfiles = new Set((artifact.surface && artifact.surface.profiles) || []);
    expectedProfiles.forEach((id) => { if (!runtimeProfiles.has(id)) fail(errors, "runtime.profiles", `missing used profile '${id}'`); });
    runtimeProfiles.forEach((profile, id) => { if (!expectedProfiles.has(id)) fail(errors, `runtime.profiles.${id}`, "unused profile included"); });
    const runtimeTokens = uniqueById(errors, artifact.tokens, "runtime.tokens");
    const frameworkTokens = new Map((framework.tokens || []).map((token) => [token.id, token]));
    usedTokens.forEach((id) => {
      const runtimeToken = runtimeTokens.get(id);
      const frameworkToken = frameworkTokens.get(id);
      if (!runtimeToken) fail(errors, "runtime.tokens", `missing used token '${id}'`);
      else if (!frameworkToken || stableStringify(runtimeToken) !== stableStringify(frameworkToken)) fail(errors, `runtime.tokens.${id}`, "token definition mismatch");
    });
    runtimeTokens.forEach((token, id) => { if (!usedTokens.has(id)) fail(errors, `runtime.tokens.${id}`, "unused token included"); });
    if (!Array.isArray(artifact.capabilities)) fail(errors, "runtime.capabilities", "expected array");
    else {
      const actual = new Set(artifact.capabilities);
      usedCapabilities.forEach((id) => { if (!actual.has(id)) fail(errors, "runtime.capabilities", `missing used capability '${id}'`); });
      actual.forEach((id) => { if (!usedCapabilities.has(id)) fail(errors, "runtime.capabilities", `unused capability '${id}' included`); });
    }
    return errors;
  }

  function createNode(framework, type, id) {
    const definition = componentIndex(framework).get(type);
    if (!definition) throw new Error(`Unknown component '${type}'`);
    const props = definition.props.filter((prop) => prop.required).map((prop) => {
      let value;
      if (prop.kind === "i18n" || prop.kind === "asset" || prop.kind === "token") value = { kind: prop.kind, ref: "replace.me" };
      else if (prop.kind === "data") value = { kind: "data", path: "surface.value" };
      else value = { kind: "literal", value: Object.prototype.hasOwnProperty.call(prop, "default") ? prop.default : (Array.isArray(prop.enum) ? prop.enum[0] : prop.kind === "boolean" ? false : prop.kind === "number" ? 0 : "") };
      return { name: prop.name, value };
    });
    const node = { id, type, variant: "default", layout: { mode: "column", base: [], overrides: [] }, props, actions: [], children: [] };
    if (definition.supportsColumns) node.columns = [{ key: "value", labelRef: "replace.me", align: "left", flex: 1, min: 80 }];
    if (definition.supportsOptions) {
      node.options = [{ id: "option-1", labelRef: "replace.me", value: "option-1" }];
      if (type === "tabs") node.options[0].contentId = "replace-content";
    }
    return node;
  }

  return {
    IDENTIFIER,
    PROP_IDENTIFIER,
    MODULE_ID,
    EVENTS,
    componentIndex,
    createNode,
    stableStringify,
    stableValue,
    validateFramework,
    validateRuntimeArtifact,
    validateSurface
  };
}));
