#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const model = require("../lib/sik-ui-model.js");
const visual = require("../lib/visual-baseline.js");
const validator = require("../validator/validate.js");

function hash(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function escapeHtml(value) {
  return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function localPreviewResource(masterPath, reference) {
  if (!reference || /^[a-z]+:/i.test(reference) || reference.startsWith("//")) return null;
  const resolved = path.resolve(path.dirname(masterPath), reference.split(/[?#]/)[0]);
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) return null;
  return fs.readFileSync(resolved, "utf8");
}

function previewEnvelope(masterHtml, masterPath, rootHtml, surfaceId, provenance) {
  const styles = [];
  const scripts = [];
  const linkPattern = /<link\b[^>]*rel=["']stylesheet["'][^>]*href=["']([^"']+)["'][^>]*>/gi;
  let match;
  while ((match = linkPattern.exec(masterHtml)) !== null) {
    const content = localPreviewResource(masterPath, match[1]);
    if (content !== null) styles.push(content);
  }
  const stylePattern = /<style\b[^>]*>([\s\S]*?)<\/style>/gi;
  while ((match = stylePattern.exec(masterHtml)) !== null) styles.push(match[1]);
  const scriptPattern = /<script\b[^>]*src=["']([^"']+)["'][^>]*><\/script>/gi;
  while ((match = scriptPattern.exec(masterHtml)) !== null) {
    const content = localPreviewResource(masterPath, match[1]);
    if (content !== null) scripts.push(content);
  }
  return `<!doctype html>\n<html lang="es">\n<head>\n  <meta charset="utf-8">\n  <meta name="viewport" content="width=device-width,initial-scale=1">\n  <meta name="sik-ui-provenance" content="${escapeHtml(model.stableStringify(provenance).trim())}">\n  <title>${escapeHtml(surfaceId)}</title>\n  <style>${styles.join("\n")}</style>\n</head>\n<body data-sik-surface="${escapeHtml(surfaceId)}">\n${rootHtml}\n${scripts.length > 0 ? `<script>${scripts.join("\n")}</script>\n` : ""}</body>\n</html>\n`;
}

function bindingValue(binding, translations) {
  if (binding === null || typeof binding !== "object" || Array.isArray(binding)) return binding;
  if (binding.kind === "literal") return binding.value;
  if (binding.kind === "i18n") return translations.get(binding.ref) || binding.ref;
  if (binding.kind === "asset" || binding.kind === "token") return binding.ref;
  if (binding.kind === "data" || binding.kind === "state") return `{{${binding.path}}}`;
  return "";
}

function layoutLiteral(value, tokens) {
  if (value && value.kind === "literal") return value.value;
  if (value && value.kind === "token") return tokens.get(value.ref);
  if (value && (value.kind === "data" || value.kind === "state")) return null;
  return value;
}

function layoutCss(layout, tokens, bindings) {
  const css = [];
  const modes = {
    flow: ["display:flex", "flex-direction:column"],
    row: ["display:flex", "flex-direction:row"],
    column: ["display:flex", "flex-direction:column"],
    grid: ["display:grid"],
    overlay: ["display:grid"],
    absolute: ["position:absolute"]
  };
  css.push(...(modes[layout.mode] || []));
  const names = {
    x: "left", y: "top", width: "width", height: "height",
    "min-width": "min-width", "min-height": "min-height", "max-width": "max-width", "max-height": "max-height",
    gap: "gap", padding: "padding", grow: "flex-grow", shrink: "flex-shrink",
    align: "align-items", justify: "justify-content"
  };
  bindings.forEach((binding) => {
    const value = layoutLiteral(binding.value, tokens);
    if (value === null || value === undefined) return;
    if (binding.name === "columns") css.push(`grid-template-columns:repeat(${value},minmax(0,1fr))`);
    else if (binding.name === "span") css.push(`grid-column:span ${value}`);
    else if (binding.name === "clip") { if (value) css.push("overflow:hidden"); }
    else if (binding.name === "fill") { if (value) css.push("width:100%", "height:100%"); }
    else if (names[binding.name]) {
      const metric = typeof value === "number" && !["grow", "shrink"].includes(binding.name) ? `${value}px` : value;
      css.push(`${names[binding.name]}:${metric}`);
    }
  });
  return css.join(";");
}

function htmlForNode(node, definitions, translations, tokens, profiles, rules, depth, semanticAttributes) {
  const definition = definitions.get(node.type);
  const indent = "  ".repeat(depth);
  const attributes = [
    `class="${escapeHtml(definition.htmlClass)}"`,
    `data-sik-node="${escapeHtml(node.id)}"`,
    `data-sik-type="${escapeHtml(node.type)}"`,
    `data-sik-variant="${escapeHtml(node.variant)}"`
  ];
  Object.keys(semanticAttributes || {}).sort().forEach((name) => attributes.push(`${name}="${escapeHtml(semanticAttributes[name])}"`));
  if (node.state) attributes.push("data-state-group", `data-state="${escapeHtml(node.state.default)}"`);
  attributes.push(`data-layout-mode="${escapeHtml(node.layout.mode)}"`);
  attributes.push(`data-layout-base="${escapeHtml(JSON.stringify(node.layout.base))}"`);
  attributes.push(`data-layout-overrides="${escapeHtml(JSON.stringify(node.layout.overrides))}"`);
  const baseCss = layoutCss(node.layout, tokens, node.layout.base);
  if (baseCss) rules.push(`[data-sik-node="${node.id}"]{${baseCss}}`);
  const stackBinding = node.layout.base.find((binding) => binding.name === "stack-below");
  const stackBelow = stackBinding && layoutLiteral(stackBinding.value, tokens);
  if (typeof stackBelow === "number" && node.layout.mode === "row") {
    rules.push(`@media (max-width:${stackBelow}px){[data-sik-node="${node.id}"]{flex-direction:column}[data-sik-node="${node.id}"]>*{width:100%;flex-basis:auto}}`);
  }
  node.layout.overrides.forEach((override) => {
    const profile = profiles.get(override.profileId);
    if (profile) rules.push(`@media (min-width:${profile.minViewportWidth}px) and (min-height:${profile.minViewportHeight}px){[data-sik-node="${node.id}"]{${layoutCss(node.layout, tokens, override.bindings)}}}`);
  });
  node.props.forEach((prop) => attributes.push(`data-prop-${escapeHtml(prop.name)}="${escapeHtml(bindingValue(prop.value, translations))}"`));
  if (node.visual && node.visual.visibleWhen) attributes.push(`data-visible-when="${escapeHtml(node.visual.visibleWhen)}"`);
  if (node.type === "table") attributes.push("data-sik-table");
  if (node.columns) attributes.push(`data-columns="${escapeHtml(JSON.stringify(node.columns))}"`);
  if (node.options) attributes.push(`data-options="${escapeHtml(JSON.stringify(node.options))}"`);
  if (node.capabilities) attributes.push(`data-capabilities="${escapeHtml(JSON.stringify(node.capabilities))}"`);
  if (node.actions.length > 0) attributes.push(`data-actions="${escapeHtml(JSON.stringify(node.actions))}"`);
  const optionByContent = new Map((node.options || []).filter((option) => option.contentId).map((option) => [option.contentId, option]));
  const stateViewByContent = new Map((node.state ? node.state.views : []).map((view) => [view.contentId, view.values.join(" ")]));
  const isNavigationHost = node.type === "tabs" || (node.capabilities || []).some((capability) => capability.id === "container.navigation");
  const tabsOptionHtml = isNavigationHost ? (node.options || []).map((option) =>
    `${"  ".repeat(depth + 1)}<button type="button" data-state-option="${escapeHtml(option.value)}">${escapeHtml(translations.get(option.labelRef) || option.labelRef)}</button>`).join("\n") : "";
  const stateOptionHtml = node.state ? node.state.options.map((value) =>
    `${"  ".repeat(depth + 1)}<button type="button" data-state-option="${escapeHtml(value)}" hidden></button>`).join("\n") : "";
  const children = node.children.map((child) => {
    const option = optionByContent.get(child.id);
    const stateView = stateViewByContent.get(child.id);
    return htmlForNode(child, definitions, translations, tokens, profiles, rules, depth + 1,
      stateView ? { "data-state-view": stateView } : (option ? { "data-state-view": option.value } : null));
  }).join("\n");
  const title = node.props.find((prop) => prop.name === "title");
  const titleHtml = title ? `${"  ".repeat(depth + 1)}<h2>${escapeHtml(bindingValue(title.value, translations))}</h2>` : "";
  const content = [titleHtml, tabsOptionHtml, stateOptionHtml, children].filter(Boolean).join("\n");
  return `${indent}<${definition.htmlTag} ${attributes.join(" ")}>${content ? `\n${content}\n${indent}` : ""}</${definition.htmlTag}>`;
}

function luaString(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\r/g, "\\r").replace(/\n/g, "\\n")}"`;
}

function luaValue(value, depth) {
  const indent = "  ".repeat(depth || 0);
  const childIndent = "  ".repeat((depth || 0) + 1);
  if (value === null) return "nil";
  if (typeof value === "string") return luaString(value);
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  if (Array.isArray(value)) {
    if (value.length === 0) return "{}";
    return `{\n${value.map((entry) => `${childIndent}${luaValue(entry, (depth || 0) + 1)}`).join(",\n")}\n${indent}}`;
  }
  const keys = Object.keys(value).sort();
  if (keys.length === 0) return "{}";
  return `{\n${keys.map((key) => `${childIndent}[${luaString(key)}] = ${luaValue(value[key], (depth || 0) + 1)}`).join(",\n")}\n${indent}}`;
}

function collectUsed(node, types, capabilities, tokens) {
  types.add(node.type);
  (node.capabilities || []).forEach((capability) => capabilities.add(capability.id));
  node.props.forEach((prop) => {
    if (prop.value && prop.value.kind === "token") tokens.add(prop.value.ref);
  });
  node.layout.base.forEach((binding) => { if (binding.value && binding.value.kind === "token") tokens.add(binding.value.ref); });
  node.layout.overrides.forEach((override) => override.bindings.forEach((binding) => { if (binding.value && binding.value.kind === "token") tokens.add(binding.value.ref); }));
  node.children.forEach((child) => collectUsed(child, types, capabilities, tokens));
}

function runtimeProjection(value) {
  if (Array.isArray(value)) return value.map(runtimeProjection);
  if (!value || typeof value !== "object") return value;
  const projected = {};
  Object.keys(value).forEach((key) => { projected[key] = runtimeProjection(value[key]); });
  if (projected.kind === "state") projected.kind = "data";
  return projected;
}

function runtimeSpec(framework, spec, provenance) {
  const types = new Set();
  const capabilities = new Set();
  const tokens = new Set();
  collectUsed(spec.surface.root, types, capabilities, tokens);
  const componentFactories = framework.components.filter((component) => types.has(component.id)).map((component) => ({ typeId: component.id, runtimeFactory: component.runtimeFactory }));
  return {
    documentKind: "sik-ui-runtime-surface",
    schemaId: "sik-ui-runtime-v1",
    schemaVersion: 1,
    frameworkRef: {
      id: framework.framework.id,
      namespace: framework.framework.namespace,
      manifestVersion: framework.framework.manifestVersion,
      manifestSha256: provenance.frameworkManifestSha256
    },
    provenance,
    profiles: framework.profiles.filter((profile) => spec.surface.profiles.includes(profile.id)),
    tokens: framework.tokens.filter((token) => token.runtime && tokens.has(token.id)),
    componentFactories,
    capabilities: framework.capabilities.filter((capability) => capabilities.has(capability.id)).map((capability) => capability.id),
    product: spec.product,
    surface: runtimeProjection(spec.surface),
    surfaceReferences: spec.surfaceReferences,
    assets: spec.assets.map((asset) => ({ id: asset.id, path: asset.runtimePath, sha256: asset.sha256 })),
    i18n: spec.i18n,
    actionAllowlist: spec.actionAllowlist
  };
}

function generatorHash() {
  const sources = [__filename, path.resolve(__dirname, "../lib/sik-ui-model.js"), path.resolve(__dirname, "../lib/visual-baseline.js"), path.resolve(__dirname, "../validator/validate.js")];
  return hash(Buffer.concat(sources.sort().map((source) => fs.readFileSync(source))));
}

function generate(options) {
  const schema = validator.readDocument(path.resolve(options.schema));
  const frameworkDocument = validator.readDocument(path.resolve(options.framework));
  const surfaceDocument = validator.readDocument(path.resolve(options.surface));
  const validation = validator.validateResolved(frameworkDocument, surfaceDocument, {
    workspaceRoot: options.workspaceRoot,
    repositoryMap: options.repositoryMap,
    runtimeArtifactPolicy: options.runtimePolicy === "staged"
      ? "staged-input" : "metadata-only"
  });
  if (!validation.ok) {
    const error = new Error("Surface validation failed");
    error.validation = validation;
    throw error;
  }
  const provenance = {
    schemaSha256: schema.sha256,
    frameworkManifestSha256: frameworkDocument.sha256,
    surfaceSpecSha256: surfaceDocument.sha256,
    generatorSha256: generatorHash(),
    visualMasterSha256: surfaceDocument.value.visualBaseline.masterSha256,
    visualSubtreeSha256: surfaceDocument.value.visualBaseline.subtreeSha256,
    visualCanonicalizer: surfaceDocument.value.visualBaseline.canonicalizer
  };
  const framework = frameworkDocument.value;
  const spec = surfaceDocument.value;
  const translations = new Map(spec.i18n.map((entry) => {
    const preferred = entry.translations.find((item) => item.locale === "es") || entry.translations[0];
    return [entry.id, preferred.text];
  }));
  const masterPath = path.resolve(options.workspaceRoot, spec.visualBaseline.masterPath);
  const workspaceRoot = path.resolve(options.workspaceRoot);
  if (masterPath !== workspaceRoot && !masterPath.startsWith(`${workspaceRoot}${path.sep}`)) throw new Error("Visual master path escapes workspace");
  const masterHtml = fs.readFileSync(masterPath, "utf8");
  let html;
  if (spec.visualBaseline.canonicalizer === visual.CANONICALIZER_V2) {
    const rootHtml = visual.extractUniqueSubtree(masterHtml, spec.visualBaseline.selector);
    html = previewEnvelope(masterHtml, masterPath, rootHtml, spec.surface.id, provenance);
  } else {
    const definitions = new Map(framework.components.map((component) => [component.id, component]));
    const tokens = new Map(framework.tokens.map((token) => [token.id, token.value]));
    const profiles = new Map(framework.profiles.map((profile) => [profile.id, profile]));
    const rules = [];
    const rootHtml = htmlForNode(spec.surface.root, definitions, translations, tokens, profiles, rules, 2,
      { "data-surface-id": spec.surface.id });
    html = `<!doctype html>\n<html lang="es">\n<head>\n  <meta charset="utf-8">\n  <meta name="sik-ui-provenance" content="${escapeHtml(model.stableStringify(provenance).trim())}">\n  <title>${escapeHtml(spec.surface.id)}</title>\n  <style>${rules.join("\n")}</style>\n</head>\n<body data-sik-surface="${escapeHtml(spec.surface.id)}">\n${rootHtml}\n</body>\n</html>\n`;
  }
  let generatedVisual;
  try {
    generatedVisual = visual.canonicalizeDocument(html, spec.visualBaseline.selector, spec.visualBaseline.canonicalizer);
  } catch (cause) {
    const error = new Error("Generated visual subtree is invalid");
    error.validation = { ok: false, stages: [{ name: "spec-master-parity", ok: false,
      errors: [{ path: "generated.html", message: cause.message }] }] };
    throw error;
  }
  if (generatedVisual.sha256 !== spec.visualBaseline.subtreeSha256) {
    const error = new Error("Generated visual subtree does not match the validated master");
    error.validation = { ok: false, stages: [{ name: "spec-master-parity", ok: false,
      errors: [{ path: "generated.html", message: `visual subtree hash mismatch: expected ${spec.visualBaseline.subtreeSha256}, actual ${generatedVisual.sha256}` }] }] };
    throw error;
  }
  const runtime = runtimeSpec(framework, spec, provenance);
  const runtimeErrors = model.validateRuntimeArtifact(framework, runtime);
  if (runtimeErrors.length > 0) {
    const error = new Error("Generated runtime artifact validation failed");
    error.validation = { ok: false, stages: [{ name: "runtime-artifact", ok: false, errors: runtimeErrors }] };
    throw error;
  }
  const lua = `-- Generated data only. Do not edit.\nreturn ${luaValue(runtime, 0)}\n`;
  const companion = {
    surfaceId: spec.surface.id,
    inputs: provenance,
    runtime: spec.runtime,
    runtimePolicy: options.runtimePolicy === "staged" ? "staged" : "required",
    outputs: { htmlSha256: hash(Buffer.from(html, "utf8")), luaSha256: hash(Buffer.from(lua, "utf8")) }
  };
  const result = { html, lua, provenance: `${model.stableStringify(companion)}` , validation };
  if (options.outDir) {
    fs.mkdirSync(options.outDir, { recursive: true });
    fs.writeFileSync(path.join(options.outDir, `${spec.surface.id}.generated.html`), html, "utf8");
    fs.writeFileSync(path.join(options.outDir, `${spec.surface.id}.generated.lua`), lua, "utf8");
    fs.writeFileSync(path.join(options.outDir, `${spec.surface.id}.provenance.json`), result.provenance, "utf8");
    const repositoryRoot = options.repositoryMap[spec.runtime.artifact.repository];
    if (typeof repositoryRoot !== "string") throw new Error(`Unknown runtime repository '${spec.runtime.artifact.repository}'`);
    const artifactPath = path.resolve(options.workspaceRoot, repositoryRoot, spec.runtime.artifact.modulePath);
    const mappedRoot = path.resolve(options.workspaceRoot, repositoryRoot);
    if (!artifactPath.startsWith(`${mappedRoot}${path.sep}`)) throw new Error("Runtime artifact path escapes repository");
    fs.mkdirSync(path.dirname(artifactPath), { recursive: true });
    fs.writeFileSync(artifactPath, lua, "utf8");
    const completeValidation = validator.validateResolved(frameworkDocument, surfaceDocument, {
      workspaceRoot: options.workspaceRoot,
      repositoryMap: options.repositoryMap,
      runtimeArtifactPolicy: options.runtimePolicy === "staged" ? "staged" : "required"
    });
    if (!completeValidation.ok) {
      const error = new Error("Generated runtime boundary validation failed");
      error.validation = completeValidation;
      throw error;
    }
    result.validation = completeValidation;
  }
  return result;
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 2) args[argv[index].replace(/^--/, "")] = argv[index + 1];
  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.schema || !args.framework || !args.surface || !args["workspace-root"] || !args["repository-map"] || !args["out-dir"]) {
    process.stderr.write("Usage: node generate.js --schema <schema> --framework <manifest> --surface <spec> --workspace-root <root> --repository-map <json> --out-dir <dir> [--runtime-policy staged]\n");
    process.exitCode = 2;
    return;
  }
  try {
    const repositoryMap = JSON.parse(fs.readFileSync(path.resolve(args["repository-map"]), "utf8"));
    const result = generate({ schema: args.schema, framework: args.framework, surface: args.surface,
      workspaceRoot: args["workspace-root"], repositoryMap, outDir: path.resolve(args["out-dir"]),
      runtimePolicy: args["runtime-policy"] });
    process.stdout.write(result.provenance);
  } catch (error) {
    if (error.validation) process.stderr.write(`${JSON.stringify(error.validation, null, 2)}\n`);
    else process.stderr.write(`${error.stack || error.message}\n`);
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = { generate, luaValue, runtimeSpec };
