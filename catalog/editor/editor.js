(function () {
  "use strict";

  const model = window.SiKUIModel;
  const draftKey = "sik-ui-catalog-editor-draft-v1";
  const state = { framework: null, spec: null, selectedId: null, fileHandles: { surface: null, manifest: null } };
  const byId = (id) => document.getElementById(id);

  function clone(value) { return JSON.parse(JSON.stringify(value)); }
  function readJsonFile(file) { return file.text().then((text) => JSON.parse(text)); }
  function indexComponents() { return model.componentIndex(state.framework); }
  function findNode(node, id, parent) {
    if (!node) return null;
    if (node.id === id) return { node, parent };
    for (const child of node.children) {
      const found = findNode(child, id, node);
      if (found) return found;
    }
    return null;
  }
  function selected() { return state.spec ? findNode(state.spec.surface.root, state.selectedId, null) : null; }
  function nextId(type) {
    let value = 1;
    while (findNode(state.spec.surface.root, `${type}-${value}`, null)) value += 1;
    return `${type}-${value}`;
  }

  function renderTreeNode(node) {
    const item = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = `${node.type} · ${node.id}`;
    button.classList.toggle("is-selected", node.id === state.selectedId);
    button.addEventListener("click", () => { state.selectedId = node.id; render(); });
    item.appendChild(button);
    if (node.children.length > 0) {
      const list = document.createElement("ol");
      node.children.forEach((child) => list.appendChild(renderTreeNode(child)));
      item.appendChild(list);
    }
    return item;
  }

  function renderTree() {
    const tree = byId("tree");
    tree.replaceChildren();
    if (state.spec) tree.appendChild(renderTreeNode(state.spec.surface.root));
  }

  function writeInspector() {
    const found = selected();
    const node = found && found.node;
    ["props", "actions", "capabilities", "columns", "options"].forEach((key) => {
      byId(`node-${key}`).value = node ? JSON.stringify(node[key] || [], null, 2) : "[]";
      byId(`node-${key}`).disabled = !node;
    });
    byId("node-layout").value = node ? JSON.stringify(node.layout, null, 2) : "{}";
    byId("node-layout").disabled = !node;
    byId("surface-profiles").value = state.spec ? JSON.stringify(state.spec.surface.profiles, null, 2) : "[]";
    byId("surface-contracts").value = state.spec ? JSON.stringify(state.spec.contracts, null, 2) : "{}";
    byId("surface-runtime").value = state.spec ? JSON.stringify(state.spec.runtime, null, 2) : "{}";
    byId("surface-assets").value = state.spec ? JSON.stringify(state.spec.assets, null, 2) : "[]";
    byId("framework-profiles").value = state.framework ? JSON.stringify(state.framework.profiles, null, 2) : "[]";
  }

  function previewNode(node) {
    const definition = indexComponents().get(node.type);
    const element = document.createElement(definition.htmlTag);
    element.className = definition.htmlClass;
    element.dataset.sikNode = node.id;
    element.dataset.sikType = node.type;
    element.dataset.layoutMode = node.layout.mode;
    element.dataset.layoutBase = JSON.stringify(node.layout.base);
    element.dataset.layoutOverrides = JSON.stringify(node.layout.overrides);
    applyPreviewLayout(element, node.layout);
    node.children.forEach((child) => element.appendChild(previewNode(child)));
    return element;
  }

  function applyPreviewLayout(element, layout) {
    const tokenMap = new Map(state.framework.tokens.map((token) => [token.id, token.value]));
    const modeStyles = {
      flow: ["display", "flex", "flexDirection", "column"],
      row: ["display", "flex", "flexDirection", "row"],
      column: ["display", "flex", "flexDirection", "column"],
      grid: ["display", "grid"],
      overlay: ["display", "grid"],
      absolute: ["position", "absolute"]
    };
    const mode = modeStyles[layout.mode] || [];
    for (let index = 0; index < mode.length; index += 2) element.style[mode[index]] = mode[index + 1];
    const properties = { x: "left", y: "top", width: "width", height: "height", "min-width": "minWidth", "min-height": "minHeight", "max-width": "maxWidth", "max-height": "maxHeight", gap: "gap", padding: "padding", grow: "flexGrow", shrink: "flexShrink", align: "alignItems", justify: "justifyContent" };
    const activeBindings = layout.base.slice();
    layout.overrides.forEach((override) => {
      const profile = state.framework.profiles.find((entry) => entry.id === override.profileId);
      if (profile && window.innerWidth >= profile.minViewportWidth && window.innerHeight >= profile.minViewportHeight) activeBindings.push(...override.bindings);
    });
    activeBindings.forEach((binding) => {
      let value = binding.value && binding.value.kind === "literal" ? binding.value.value : binding.value;
      if (binding.value && binding.value.kind === "token") value = tokenMap.get(binding.value.ref);
      if (binding.value && (binding.value.kind === "data" || binding.value.kind === "state")) return;
      if (binding.name === "columns") element.style.gridTemplateColumns = `repeat(${value},minmax(0,1fr))`;
      else if (binding.name === "clip" && value) element.style.overflow = "hidden";
      else if (binding.name === "fill" && value) { element.style.width = "100%"; element.style.height = "100%"; }
      else if (properties[binding.name]) element.style[properties[binding.name]] = typeof value === "number" && !["grow", "shrink"].includes(binding.name) ? `${value}px` : value;
    });
  }

  function validateAndPreview() {
    const status = byId("validation");
    const preview = byId("preview");
    preview.replaceChildren();
    if (!state.framework || !state.spec) {
      status.textContent = "Importa manifest y surface spec.";
      status.className = "is-error";
      return;
    }
    const errors = model.validateSurface(state.framework, state.spec);
    status.className = errors.length ? "is-error" : "is-ok";
    status.textContent = errors.length ? errors.map((error) => `${error.path}: ${error.message}`).join("\n") : "Árbol válido (sin resolver filesystem/hash).";
    preview.appendChild(previewNode(state.spec.surface.root));
  }

  function renderSelectors() {
    const surface = byId("surface-select");
    surface.replaceChildren();
    if (state.spec) surface.add(new Option(state.spec.surface.id, state.spec.surface.id));
    const type = byId("component-type");
    type.replaceChildren();
    if (!state.framework) return;
    const found = selected();
    const allowed = found ? indexComponents().get(found.node.type).allowedChildren : state.framework.components.map((component) => component.id);
    state.framework.components.filter((component) => allowed.includes(component.id)).forEach((component) => type.add(new Option(component.id, component.id)));
    const tokens = byId("token-select");
    tokens.replaceChildren();
    state.framework.tokens.forEach((token) => tokens.add(new Option(token.id, token.id)));
    syncTokenValue();
  }

  function render() {
    renderTree();
    writeInspector();
    renderSelectors();
    validateAndPreview();
  }

  function applyNode() {
    const found = selected();
    if (!found) return;
    try {
      found.node.layout = JSON.parse(byId("node-layout").value);
      ["props", "actions", "capabilities", "columns", "options"].forEach((key) => {
        const value = JSON.parse(byId(`node-${key}`).value);
        if ((key === "columns" || key === "options" || key === "capabilities") && value.length === 0) delete found.node[key];
        else found.node[key] = value;
      });
      render();
    } catch (error) { window.alert(`JSON inválido: ${error.message}`); }
  }

  function applyProfiles() {
    try {
      if (state.spec) state.spec.surface.profiles = JSON.parse(byId("surface-profiles").value);
      if (state.framework) state.framework.profiles = JSON.parse(byId("framework-profiles").value);
      render();
    } catch (error) { window.alert(`JSON inválido: ${error.message}`); }
  }

  function applySurfaceContract() {
    if (!state.spec) return;
    try {
      state.spec.contracts = JSON.parse(byId("surface-contracts").value);
      state.spec.runtime = JSON.parse(byId("surface-runtime").value);
      state.spec.assets = JSON.parse(byId("surface-assets").value);
      render();
    } catch (error) { window.alert(`JSON inválido: ${error.message}`); }
  }

  function addNode() {
    const found = selected();
    if (!found) return;
    const type = byId("component-type").value;
    if (!type) return;
    const node = model.createNode(state.framework, type, nextId(type));
    found.node.children.push(node);
    state.selectedId = node.id;
    render();
  }

  function removeNode() {
    const found = selected();
    if (!found || !found.parent) return;
    found.parent.children = found.parent.children.filter((child) => child !== found.node);
    state.selectedId = found.parent.id;
    render();
  }

  function move(offset) {
    const found = selected();
    if (!found || !found.parent) return;
    const siblings = found.parent.children;
    const index = siblings.indexOf(found.node);
    const target = index + offset;
    if (target < 0 || target >= siblings.length) return;
    siblings.splice(index, 1);
    siblings.splice(target, 0, found.node);
    render();
  }

  function syncTokenValue() {
    if (!state.framework) return;
    const token = state.framework.tokens.find((entry) => entry.id === byId("token-select").value);
    byId("token-value").value = token ? String(token.value) : "";
  }

  function applyToken() {
    const token = state.framework.tokens.find((entry) => entry.id === byId("token-select").value);
    if (!token) return;
    const raw = byId("token-value").value;
    token.value = token.kind === "number" ? Number(raw) : raw;
    render();
  }

  function exportDocument(documentValue, filename) {
    if (!documentValue) return;
    const blob = new Blob([model.stableStringify(documentValue)], { type: "application/json" });
    const anchor = document.createElement("a");
    anchor.href = URL.createObjectURL(blob);
    anchor.download = filename;
    anchor.click();
    URL.revokeObjectURL(anchor.href);
  }

  async function saveDocument(kind, documentValue, filename) {
    if (!documentValue) return;
    if (window.showSaveFilePicker) {
      state.fileHandles[kind] = state.fileHandles[kind] || await window.showSaveFilePicker({ suggestedName: filename, types: [{ description: "JSON", accept: { "application/json": [".json"] } }] });
      const writable = await state.fileHandles[kind].createWritable();
      await writable.write(model.stableStringify(documentValue));
      await writable.close();
    } else exportDocument(documentValue, filename);
  }

  function bind() {
    byId("manifest-file").addEventListener("change", async (event) => { state.framework = await readJsonFile(event.target.files[0]); render(); });
    byId("surface-file").addEventListener("change", async (event) => { state.spec = await readJsonFile(event.target.files[0]); state.selectedId = state.spec.surface.root.id; state.fileHandles.surface = null; render(); });
    byId("add-node").addEventListener("click", addNode);
    byId("remove-node").addEventListener("click", removeNode);
    byId("move-up").addEventListener("click", () => move(-1));
    byId("move-down").addEventListener("click", () => move(1));
    byId("apply-node").addEventListener("click", applyNode);
    byId("apply-profiles").addEventListener("click", applyProfiles);
    byId("apply-surface-contract").addEventListener("click", applySurfaceContract);
    byId("token-select").addEventListener("change", syncTokenValue);
    byId("apply-token").addEventListener("click", applyToken);
    byId("export-file").addEventListener("click", () => { if (state.spec) exportDocument(state.spec, `${state.spec.surface.id}.json`); });
    byId("save-file").addEventListener("click", () => { if (state.spec) saveDocument("surface", state.spec, `${state.spec.surface.id}.json`).catch((error) => window.alert(error.message)); });
    byId("export-manifest").addEventListener("click", () => exportDocument(state.framework, "sik-ui-framework.manifest.json"));
    byId("save-manifest").addEventListener("click", () => saveDocument("manifest", state.framework, "sik-ui-framework.manifest.json").catch((error) => window.alert(error.message)));
    byId("save-draft").addEventListener("click", () => { if (state.spec) localStorage.setItem(draftKey, model.stableStringify(state.spec)); });
  }

  async function init() {
    bind();
    try { state.framework = await fetch("../manifests/sik-ui-framework.manifest.json").then((response) => response.json()); } catch (_) { /* File import remains available. */ }
    const draft = localStorage.getItem(draftKey);
    if (draft) {
      try { state.spec = JSON.parse(draft); state.selectedId = state.spec.surface.root.id; } catch (_) { localStorage.removeItem(draftKey); }
    }
    render();
  }

  init();
}());
