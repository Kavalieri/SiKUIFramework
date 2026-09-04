#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const model = require("../lib/sik-ui-model.js");
const visual = require("../lib/visual-baseline.js");

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function readDocument(filePath) {
  const bytes = fs.readFileSync(filePath);
  return { bytes, value: JSON.parse(bytes.toString("utf8")), sha256: sha256(bytes) };
}

function stage(name, errors) {
  return { name, ok: errors.length === 0, errors };
}

function resolveRepository(workspaceRoot, repositoryMap, repositoryId, label) {
  const errors = [];
  const relativeRoot = repositoryMap && repositoryMap[repositoryId];
  if (typeof relativeRoot !== "string" || relativeRoot.length === 0) {
    errors.push({ path: `${label}.repository`, message: `unknown repository id: ${repositoryId}` });
    return { errors };
  }
  if (path.isAbsolute(relativeRoot) || relativeRoot.split(/[\\/]/).includes("..")) {
    errors.push({ path: `${label}.repository`, message: `invalid repository root for: ${repositoryId}` });
    return { errors };
  }
  const repositoryRoot = path.resolve(workspaceRoot, relativeRoot);
  if (repositoryRoot !== workspaceRoot && !repositoryRoot.startsWith(`${workspaceRoot}${path.sep}`)) {
    errors.push({ path: `${label}.repository`, message: `repository root escapes workspace: ${repositoryId}` });
    return { errors };
  }
  if (!fs.existsSync(repositoryRoot) || !fs.statSync(repositoryRoot).isDirectory()) {
    errors.push({ path: `${label}.repository`, message: `repository root not found: ${repositoryId}` });
    return { errors };
  }
  return { errors, repositoryRoot };
}

function resolveModule(workspaceRoot, repositoryMap, reference, label) {
  const repository = resolveRepository(workspaceRoot, repositoryMap, reference.repository, label);
  const errors = repository.errors.slice();
  if (!repository.repositoryRoot) return errors;
  const repositoryRoot = repository.repositoryRoot;
  const modulePath = path.resolve(repositoryRoot, reference.modulePath);
  if (!modulePath.startsWith(`${repositoryRoot}${path.sep}`)) {
    errors.push({ path: label, message: "module path escapes repository" });
    return errors;
  }
  if (!fs.existsSync(modulePath) || !fs.statSync(modulePath).isFile()) {
    errors.push({ path: label, message: `module not found: ${path.relative(workspaceRoot, modulePath)}` });
    return errors;
  }
  const source = fs.readFileSync(modulePath, "utf8");
  if (!sourceContainsSymbol(source, reference.symbol)) errors.push({ path: `${label}.symbol`, message: `symbol not found: ${reference.symbol}` });
  return errors;
}

function sourceContainsSymbol(source, symbol) {
  source = stripLuaComments(source);
  const escaped = String(symbol).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const leftBoundary = `(^|[^A-Za-z0-9_.:])${escaped}`;
  const exact = new RegExp(`${leftBoundary}(?=$|[^A-Za-z0-9_.:])`, "m");
  const namespaceMember = new RegExp(`${leftBoundary}\\.[A-Za-z_]`, "m");
  return exact.test(source) || namespaceMember.test(source);
}

function stripLuaComments(source) {
  return String(source).replace(/--\[\[[\s\S]*?\]\]/g, "").replace(/--[^\r\n]*/g, "");
}

function relativeFile(workspaceRoot, repositoryMap, repositoryId, relativePath, label) {
  const repository = resolveRepository(workspaceRoot, repositoryMap, repositoryId, label);
  const errors = repository.errors.slice();
  if (!repository.repositoryRoot) return { errors };
  const filePath = path.resolve(repository.repositoryRoot, relativePath);
  if (filePath !== repository.repositoryRoot && !filePath.startsWith(`${repository.repositoryRoot}${path.sep}`)) {
    errors.push({ path: label, message: "path escapes repository" });
    return { errors, repositoryRoot: repository.repositoryRoot };
  }
  return { errors, repositoryRoot: repository.repositoryRoot, filePath };
}

function moduleEvidence(workspaceRoot, repositoryMap, reference, label) {
  const result = relativeFile(workspaceRoot, repositoryMap, reference.repository, reference.modulePath, label);
  if (!result.filePath) return result;
  if (!fs.existsSync(result.filePath) || !fs.statSync(result.filePath).isFile()) {
    result.errors.push({ path: label, message: `module not found: ${path.relative(workspaceRoot, result.filePath)}` });
    return result;
  }
  result.source = fs.readFileSync(result.filePath, "utf8");
  if (!sourceContainsSymbol(result.source, reference.symbol)) result.errors.push({ path: `${label}.symbol`, message: `symbol not found: ${reference.symbol}` });
  return result;
}

function validateVisualBaseline(workspaceRoot, spec) {
  const errors = [];
  const baseline = spec.visualBaseline;
  const masterPath = path.resolve(workspaceRoot, baseline.masterPath);
  if (masterPath === workspaceRoot || !masterPath.startsWith(`${workspaceRoot}${path.sep}`)) {
    errors.push({ path: "spec.visualBaseline.masterPath", message: "master path escapes workspace" });
    return errors;
  }
  if (!fs.existsSync(masterPath) || !fs.statSync(masterPath).isFile()) {
    errors.push({ path: "spec.visualBaseline.masterPath", message: `visual master not found: ${baseline.masterPath}` });
    return errors;
  }
  const bytes = fs.readFileSync(masterPath);
  const actualMaster = sha256(bytes);
  if (actualMaster !== baseline.masterSha256) errors.push({ path: "spec.visualBaseline.masterSha256", message: `visual master hash mismatch: ${actualMaster}` });
  try {
    if (visual.selectorSurfaceId(baseline.selector) !== spec.surface.id) errors.push({ path: "spec.visualBaseline.selector", message: "visual selector must identify the declared surface" });
    const canonical = visual.canonicalizeDocument(bytes.toString("utf8"), baseline.selector, baseline.canonicalizer);
    if (canonical.sha256 !== baseline.subtreeSha256) errors.push({ path: "spec.visualBaseline.subtreeSha256", message: `visual subtree hash mismatch: ${canonical.sha256}` });
  } catch (error) {
    errors.push({ path: "spec.visualBaseline.selector", message: error.message });
  }
  return errors;
}

function validateRuntimeBoundary(workspaceRoot, repositoryMap, spec, policy, documentHashes) {
  const errors = [];
  const runtime = spec.runtime;
  const inputOnly = policy === "metadata-only" || policy === "staged-input";
  const staged = policy === "staged" || policy === "staged-input";
  const artifact = relativeFile(workspaceRoot, repositoryMap, runtime.artifact.repository, runtime.artifact.modulePath, "spec.runtime.artifact");
  errors.push(...artifact.errors);
  if (artifact.filePath) {
    if (!fs.existsSync(artifact.filePath) || !fs.statSync(artifact.filePath).isFile()) {
      if (!inputOnly) errors.push({ path: "spec.runtime.artifact.modulePath", message: `runtime artifact not found: ${path.relative(workspaceRoot, artifact.filePath)}` });
    } else if (!inputOnly) {
      const source = fs.readFileSync(artifact.filePath, "utf8");
      if (!source.includes("Generated data only. Do not edit.")) errors.push({ path: "spec.runtime.artifact.modulePath", message: "runtime artifact is not a generated data module" });
      if (!source.includes('sik-ui-runtime-surface') || !source.includes(spec.surface.id)) errors.push({ path: "spec.runtime.artifact.modulePath", message: "runtime artifact does not identify the declared surface" });
      if (documentHashes && !source.includes(documentHashes.surface)) errors.push({ path: "spec.runtime.artifact.provenance", message: "runtime artifact was generated from a different surface spec" });
      if (documentHashes && !source.includes(documentHashes.framework)) errors.push({ path: "spec.runtime.artifact.provenance", message: "runtime artifact was generated from a different framework manifest" });
      if (documentHashes && !source.includes(documentHashes.visualMaster)) errors.push({ path: "spec.runtime.artifact.provenance", message: "runtime artifact was generated from a different visual master" });
      if (documentHashes && !source.includes(documentHashes.visualSubtree)) errors.push({ path: "spec.runtime.artifact.provenance", message: "runtime artifact was generated from a different visual subtree" });
    }
  }

  if (!staged) {
    const loader = moduleEvidence(workspaceRoot, repositoryMap, runtime.loader, "spec.runtime.loader");
    errors.push(...loader.errors);
    if (loader.source) {
      const moduleId = runtime.artifact.moduleId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const requirePattern = new RegExp(`require\\s*(?:\\(\\s*)?["']${moduleId}["']\\s*\\)?`);
      if (!requirePattern.test(stripLuaComments(loader.source))) errors.push({ path: "spec.runtime.loader", message: `loader does not require runtime module '${runtime.artifact.moduleId}'` });
      if (!sourceContainsSymbol(loader.source, runtime.loader.builderSymbol)) errors.push({ path: "spec.runtime.loader.builderSymbol", message: `builder symbol not found: ${runtime.loader.builderSymbol}` });
    }

    runtime.callers.forEach((caller, index) => {
      const label = `spec.runtime.callers[${index}]`;
      const evidence = moduleEvidence(workspaceRoot, repositoryMap, caller, label);
      errors.push(...evidence.errors);
      if (evidence.source && !sourceContainsSymbol(evidence.source, runtime.loader.symbol)) errors.push({ path: label, message: `caller does not reach loader '${runtime.loader.symbol}'` });
    });
  }
  return errors;
}

function validateResolved(frameworkDocument, surfaceDocument, options) {
  const workspaceRoot = path.resolve(options.workspaceRoot);
  const repositoryMap = options.repositoryMap || {};
  const structural = model.validateSurface(frameworkDocument.value, surfaceDocument.value, {
    frameworkSha256: frameworkDocument.sha256
  });
  const stages = [stage("schema-and-semantics", structural)];
  if (structural.length > 0) return { ok: false, stages };

  stages.push(stage("visual-master-provenance", validateVisualBaseline(workspaceRoot, surfaceDocument.value)));

  const references = [];
  references.push(...resolveModule(workspaceRoot, repositoryMap, surfaceDocument.value.surface.owner, "spec.surface.owner"));
  surfaceDocument.value.surface.callers.forEach((caller, index) => {
    references.push(...resolveModule(workspaceRoot, repositoryMap, caller, `spec.surface.callers[${index}]`));
  });
  stages.push(stage("owner-and-callers", references));

  const surfaceReferences = [];
  surfaceDocument.value.surfaceReferences.forEach((reference, index) => {
    const label = `spec.surfaceReferences[${index}]`;
    const repository = resolveRepository(workspaceRoot, repositoryMap, reference.repository, label);
    surfaceReferences.push(...repository.errors);
    if (!repository.repositoryRoot) return;
    const specPath = path.resolve(repository.repositoryRoot, reference.specPath);
    if (!specPath.startsWith(`${repository.repositoryRoot}${path.sep}`)) {
      surfaceReferences.push({ path: label, message: "surface spec path escapes repository" });
    } else if (!fs.existsSync(specPath) || !fs.statSync(specPath).isFile()) {
      surfaceReferences.push({ path: label, message: `surface spec not found: ${reference.id}` });
    } else {
      const bytes = fs.readFileSync(specPath);
      const actual = sha256(bytes);
      if (actual !== reference.sha256) surfaceReferences.push({ path: `${label}.sha256`, message: `surface spec hash mismatch: ${actual}` });
      try {
        const target = JSON.parse(bytes.toString("utf8"));
        if (!target.surface || target.surface.id !== reference.id) surfaceReferences.push({ path: `${label}.id`, message: `referenced surface id mismatch: ${reference.id}` });
      } catch (error) {
        surfaceReferences.push({ path: label, message: `invalid referenced surface JSON: ${reference.id}` });
      }
    }
  });
  stages.push(stage("surface-references", surfaceReferences));

  const assets = [];
  const ownerRepository = resolveRepository(workspaceRoot, repositoryMap,
    surfaceDocument.value.surface.owner.repository, "spec.surface.owner");
  const repositoryRoot = ownerRepository.repositoryRoot;
  surfaceDocument.value.assets.forEach((asset, index) => {
    if (!repositoryRoot) return;
    const assetPath = path.resolve(repositoryRoot, asset.sourcePath);
    const label = `spec.assets[${index}]`;
    if (!assetPath.startsWith(`${repositoryRoot}${path.sep}`)) assets.push({ path: label, message: "asset path escapes owner repository" });
    else if (!fs.existsSync(assetPath) || !fs.statSync(assetPath).isFile()) assets.push({ path: label, message: `asset not found: ${path.relative(workspaceRoot, assetPath)}` });
    else {
      const actual = sha256(fs.readFileSync(assetPath));
      if (actual !== asset.sha256) assets.push({ path: `${label}.sha256`, message: `asset hash mismatch: ${actual}` });
    }
  });
  stages.push(stage("assets", assets));
  stages.push(stage("runtime-boundary", validateRuntimeBoundary(workspaceRoot, repositoryMap,
    surfaceDocument.value, options.runtimeArtifactPolicy || "required", {
      surface: surfaceDocument.sha256,
      framework: frameworkDocument.sha256,
      visualMaster: surfaceDocument.value.visualBaseline.masterSha256,
      visualSubtree: surfaceDocument.value.visualBaseline.subtreeSha256
    })));
  return { ok: stages.every((entry) => entry.ok), stages };
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 2) args[argv[index].replace(/^--/, "")] = argv[index + 1];
  return args;
}

function runtimeArtifactPolicy(value) {
  if (value === undefined || value === "required") return "required";
  if (value === "staged") return "staged";
  throw new Error(`invalid runtime policy '${value}'; expected required or staged`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.framework || !args.surface || !args["workspace-root"] || !args["repository-map"]) {
    process.stderr.write("Usage: node validate.js --framework <manifest> --surface <spec> --workspace-root <root> --repository-map <json> [--runtime-policy required|staged]\n");
    process.exitCode = 2;
    return;
  }
  try {
    const framework = readDocument(path.resolve(args.framework));
    const surface = readDocument(path.resolve(args.surface));
    const repositoryMap = JSON.parse(fs.readFileSync(path.resolve(args["repository-map"]), "utf8"));
    const result = validateResolved(framework, surface, {
      workspaceRoot: args["workspace-root"],
      repositoryMap,
      runtimeArtifactPolicy: runtimeArtifactPolicy(args["runtime-policy"])
    });
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    if (!result.ok) process.exitCode = 1;
  } catch (error) {
    process.stderr.write(`${error.stack || error.message}\n`);
    process.exitCode = 2;
  }
}

if (require.main === module) main();

module.exports = { readDocument, runtimeArtifactPolicy, sha256, sourceContainsSymbol, stripLuaComments, validateResolved, validateRuntimeBoundary, validateVisualBaseline };
