"use strict";

const crypto = require("crypto");

const CANONICALIZER_V1 = "sik-ui-visual-v1";
const CANONICALIZER_V2 = "sik-ui-dom-v2";
const CANONICALIZER = CANONICALIZER_V2;
const VOID_TAGS = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function decode(value) {
  return String(value || "")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}

function attributes(source) {
  const result = {};
  const pattern = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    const key = match[1].toLowerCase();
    result[key] = decode(match[2] !== undefined ? match[2] : (match[3] !== undefined ? match[3] : (match[4] !== undefined ? match[4] : "")));
  }
  return result;
}

function selectorSurfaceId(selector) {
  const match = /^\[data-surface-id=(?:"([a-z][a-z0-9-]*)"|'([a-z][a-z0-9-]*)')\]$/.exec(selector || "");
  if (!match) throw new Error(`unsupported visual selector '${selector}'`);
  return match[1] || match[2];
}

function tagTokens(html) {
  const tokens = [];
  const pattern = /<!--[\s\S]*?-->|<\/?[A-Za-z][^>]*>/g;
  let match;
  while ((match = pattern.exec(html)) !== null) {
    const raw = match[0];
    if (raw.startsWith("<!--")) continue;
    const close = /^<\//.test(raw);
    const nameMatch = /^<\/?\s*([^\s/>]+)/.exec(raw);
    if (!nameMatch) continue;
    const name = nameMatch[1].toLowerCase();
    const attrSource = close ? "" : raw.slice(nameMatch[0].length, raw.length - (raw.endsWith("/>") ? 2 : 1));
    tokens.push({ raw, start: match.index, end: pattern.lastIndex, close, name,
      selfClosing: !close && (raw.endsWith("/>") || VOID_TAGS.has(name)), attrs: close ? {} : attributes(attrSource) });
  }
  return tokens;
}

function extractUniqueSubtree(html, selector) {
  const surfaceId = selectorSurfaceId(selector);
  const tokens = tagTokens(html);
  const starts = tokens.filter((token) => !token.close && token.attrs["data-surface-id"] === surfaceId);
  if (starts.length !== 1) throw new Error(`visual selector '${selector}' matched ${starts.length} subtrees; expected exactly 1`);
  const start = starts[0];
  if (start.selfClosing) return start.raw;
  let depth = 0;
  let foundStart = false;
  for (const token of tokens) {
    if (token === start) foundStart = true;
    if (!foundStart || token.name !== start.name) continue;
    if (!token.close && !token.selfClosing) depth += 1;
    if (token.close) depth -= 1;
    if (foundStart && depth === 0) return html.slice(start.start, token.end);
  }
  throw new Error(`visual selector '${selector}' has an unclosed root element`);
}

function addUnique(target, value) {
  if (value && !target.includes(value)) target.push(value);
}

function numberOrUndefined(value) {
  if (value === undefined || value === "") return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function normalizedColumn(column) {
  const result = { key: column.key, align: column.align || "left" };
  ["width", "flex", "min"].forEach((key) => {
    const value = numberOrUndefined(column[key]);
    if (value !== undefined) result[key] = value;
  });
  return result;
}

function immediateText(subtree, tokens, index) {
  const token = tokens[index];
  const next = tokens[index + 1];
  const end = next ? next.start : subtree.length;
  return decode(subtree.slice(token.end, end).replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim());
}

function canonicalObject(subtree, canonicalizer) {
  if (canonicalizer === CANONICALIZER_V2) return canonicalDomObject(subtree);
  if (canonicalizer !== CANONICALIZER_V1) throw new Error(`unsupported visual canonicalizer '${canonicalizer}'`);
  const tokens = tagTokens(subtree);
  const root = tokens.find((token) => !token.close);
  if (!root || !root.attrs["data-surface-id"]) throw new Error("visual subtree root has no data-surface-id");
  const result = {
    canonicalizer: CANONICALIZER_V1,
    surfaceId: root.attrs["data-surface-id"],
    states: { options: [], views: [] },
    blocks: [],
    tables: [],
    conditions: []
  };
  const stack = [];
  let activeTable = null;
  let activeBlock = null;
  tokens.forEach((token, tokenIndex) => {
    if (token.close) {
      const closed = stack.pop();
      if (activeTable && closed && closed.table === activeTable) activeTable = null;
      if (activeBlock && closed && closed.block === activeBlock) activeBlock = closed.previousBlock;
      return;
    }
    const attrs = token.attrs;
    if (attrs["data-state-option"]) {
      const option = { id: attrs["data-state-option"], label: immediateText(subtree, tokens, tokenIndex) };
      if (!result.states.options.some((entry) => entry.id === option.id)) result.states.options.push(option);
    }
    String(attrs["data-state-view"] || "").split(/\s+/).forEach((value) => addUnique(result.states.views, value));
    let blockId = attrs["data-options-block"];
    if (!blockId) {
      const blockMatch = /^options-([a-z][a-z0-9-]*)-block$/.exec(attrs["data-sik-node"] || "");
      if (blockMatch) blockId = blockMatch[1];
    }
    let openedBlock = null;
    const previousBlock = activeBlock;
    if (blockId) {
      openedBlock = { id: blockId, title: attrs["data-prop-title"] || "", help: attrs["data-prop-help"] || "" };
      result.blocks.push(openedBlock);
      activeBlock = openedBlock;
    } else if (activeBlock && String(attrs.class || "").split(/\s+/).includes("sik-block-header")) {
      activeBlock.title = immediateText(subtree, tokens, tokenIndex);
      activeBlock.help = attrs["data-help"] || "";
    }
    addUnique(result.conditions, attrs["data-visible-when"]);
    const isTable = Object.prototype.hasOwnProperty.call(attrs, "data-sik-table") || attrs["data-sik-type"] === "table";
    let openedTable = null;
    if (isTable) {
      openedTable = { columns: [] };
      if (attrs["data-columns"]) {
        const columns = JSON.parse(attrs["data-columns"]);
        openedTable.columns = columns.map(normalizedColumn);
      }
      result.tables.push(openedTable);
      activeTable = openedTable;
    } else if (activeTable && Object.prototype.hasOwnProperty.call(attrs, "data-col")) {
      activeTable.columns.push(normalizedColumn({
        key: attrs["data-key"], align: attrs["data-align"], width: attrs["data-width"],
        flex: attrs["data-flex"], min: attrs["data-min"]
      }));
    }
    if (!token.selfClosing) stack.push({ name: token.name, table: openedTable, block: openedBlock, previousBlock });
    else {
      if (openedTable) activeTable = null;
      if (openedBlock) activeBlock = previousBlock;
    }
  });
  return result;
}

function normalizedAttributes(attrs) {
  const result = {};
  Object.keys(attrs).sort().forEach((key) => {
    let value = attrs[key];
    if (key === "class" || key === "data-state-view") {
      value = String(value).split(/\s+/).filter(Boolean).sort().join(" ");
    } else if (key === "style") {
      value = String(value).split(";").map((entry) => entry.trim()).filter(Boolean).sort().join(";");
    } else if (key === "src" || key === "href") {
      value = String(value).replace(/\\/g, "/");
    } else {
      value = String(value).replace(/\s+/g, " ").trim();
    }
    result[key] = value;
  });
  return result;
}

function appendText(node, source) {
  const value = decode(String(source || "").replace(/\s+/g, " ").trim());
  if (!value) return;
  const last = node.children[node.children.length - 1];
  if (last && Object.prototype.hasOwnProperty.call(last, "text")) last.text = `${last.text} ${value}`;
  else node.children.push({ text: value });
}

function canonicalDomObject(subtree) {
  const tokens = tagTokens(subtree);
  const documentNode = { children: [] };
  const stack = [documentNode];
  let cursor = 0;
  tokens.forEach((token) => {
    appendText(stack[stack.length - 1], subtree.slice(cursor, token.start));
    cursor = token.end;
    if (token.close) {
      if (stack.length <= 1 || stack[stack.length - 1].tag !== token.name) {
        throw new Error(`unbalanced visual DOM near </${token.name}>`);
      }
      stack.pop();
      return;
    }
    const node = { tag: token.name, attrs: normalizedAttributes(token.attrs), children: [] };
    stack[stack.length - 1].children.push(node);
    if (!token.selfClosing) stack.push(node);
  });
  appendText(stack[stack.length - 1], subtree.slice(cursor));
  if (stack.length !== 1) throw new Error(`unclosed visual DOM element <${stack[stack.length - 1].tag}>`);
  if (documentNode.children.length !== 1 || !documentNode.children[0].attrs["data-surface-id"]) {
    throw new Error("visual subtree must contain one rooted surface");
  }
  return { canonicalizer: CANONICALIZER_V2, root: documentNode.children[0] };
}

function canonicalizeDocument(html, selector, canonicalizer) {
  const subtree = extractUniqueSubtree(String(html), selector);
  const canonical = JSON.stringify(canonicalObject(subtree, canonicalizer));
  return { subtree, canonical, sha256: sha256(Buffer.from(canonical, "utf8")) };
}

module.exports = {
  CANONICALIZER,
  CANONICALIZER_V1,
  CANONICALIZER_V2,
  canonicalObject,
  canonicalizeDocument,
  extractUniqueSubtree,
  selectorSurfaceId,
  sha256
};
