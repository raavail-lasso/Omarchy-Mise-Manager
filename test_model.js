const assert = require("node:assert/strict")
const model = require("./Model.js")

const installed = { node: [{ version: "20", installed: true }, { version: "22", installed: true }] }
const globals = { node: [{ version: "22", requested_version: "latest", installed: true, active: true }] }
const updates = { node: { latest: "24" }, other: { latest: "2" } }
const prunable = { node: [{ version: "20" }] }
const row = model.rows(installed, globals, updates, prunable, "no")[0]

assert.equal(row.activeVersion, "22")
assert.equal(row.displayVersion, "22")
assert.equal(row.pinned, false)
assert.equal(row.versions.find(v => v.version === "20").prunable, true)
assert.equal(row.versions.some(v => v.version === "22"), false)
const pinned = model.rows({ bun: [{ version: "1.2.3", installed: true }] },
  { bun: [{ version: "1.2.3", requested_version: "1.2.3", installed: true, active: true }] }, {}, {}, "")[0]
assert.equal(pinned.pinned, true)
assert.equal(pinned.displayVersion, "1.2.3")
const installedOnly = model.rows({ go: [{ version: "1.22", installed: true }, { version: "1.23", installed: true }] }, {}, {}, {}, "")[0]
assert.equal(installedOnly.displayVersion, "1.23")
assert.deepEqual(installedOnly.versions.map(v => v.version), ["1.22"])
assert.equal(model.rows(installed, globals, updates, prunable, "missing").length, 0)
assert.deepEqual(model.searchResults("node  Node.js\npython  Python\n" ).map(r => r.name), ["node", "python"])
assert.equal(model.validToolSpec("npm:prettier@3"), true)
assert.equal(model.validToolSpec("--all"), false)
assert.equal(model.validToolSpec("node;rm"), false)
assert.deepEqual(model.upgradeProgressLine("  node@24  downloading  3.0s  42.1/78.3 MB · 12.4 MB/s", ["node", "python"]),
  { name: "node", phase: "downloading", percent: 54 })
assert.deepEqual(model.upgradeProgressLine("  python@3.14  installing  1.0s  32/48 pkgs", ["node", "python"]),
  { name: "python", phase: "installing", percent: 67 })
assert.deepEqual(model.upgradeProgressLine("  node@24  extracting  3.0s", ["node"]),
  { name: "node", phase: "extracting", percent: null })
assert.equal(model.upgradeProgressLine("✓ node@24  3.0s", ["node"]), null)
const presets = [{ value: "", label: "Off" }, { value: "7d", label: "7 days" }]
assert.equal(model.presetOptions(presets, "7d"), presets)
assert.equal(model.presetOptions(presets, null), presets)
assert.deepEqual(model.presetOptions(presets, "5d").map(o => o.value), ["", "7d", "5d"])
const found = [{ name: "node", description: "Node" }, { name: "ruby", description: "Ruby" }]
assert.deepEqual(model.addRows("n", found, { node: [] }).map(r => r.name), ["ruby"])
assert.deepEqual(model.addRows("node@20", found, {}).map(r => r.name), ["node@20"])
assert.deepEqual(model.addRows("node@ 20", found, {}), [])
// Omarchy's lazy system defaults: hidden until searched, never counted as updates.
const etc = { path: "/etc/mise/conf.d/omarchy-tools.toml" }
const lazyGlobals = { amp: [{ version: "1", requested_version: "latest", installed: false, active: false, source: etc }],
  claude: [{ version: "2", requested_version: "latest", installed: true, active: true, source: etc }] }
const lazyUpdates = { amp: { current: null, latest: "1" }, claude: { current: "2", latest: "3" } }
const system = model.systemTools([{ path: "/home/u/.config/mise/config.toml", tools: ["uv"] }, { path: etc.path, tools: ["amp", "claude", "uv"] }])
assert.deepEqual(Object.keys(system).sort(), ["amp", "claude", "uv"])
const lazyRows = model.rows({ claude: [{ version: "2", installed: true }] }, lazyGlobals, lazyUpdates, {}, "", system)
assert.deepEqual(lazyRows.map(r => [r.name, r.latest, r.fromSystem]), [["claude", "3", true]])
const searched = model.rows({}, lazyGlobals, lazyUpdates, {}, "amp", system)[0]
assert.equal(searched.latest, "")
assert.equal(searched.systemDefault, true)
console.log("Model checks passed")
