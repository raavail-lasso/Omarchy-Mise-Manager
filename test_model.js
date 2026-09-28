const assert = require("node:assert/strict")
const model = require("./Model.js")

const installed = { node: [{ version: "20", installed: true }, { version: "22", installed: true }] }
const globals = { node: [{ version: "22", requested_version: "latest", installed: true, active: true }] }
const updates = { node: { latest: "24" }, other: { latest: "2" } }
const prunable = { node: [{ version: "20" }] }
const row = model.rows(installed, globals, updates, prunable, "no")[0]

assert.equal(model.updateCount(globals, updates), 1)
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
console.log("Model checks passed")
