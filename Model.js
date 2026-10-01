function objectFromJson(text) {
  var value = JSON.parse(text)
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error("Expected a JSON object from mise")
  return value
}

function updateCount(globals, updates) {
  var count = 0
  for (var name in updates) if (globals[name] && updates[name] && updates[name].latest) count++
  return count
}

function rows(installed, globals, updates, prunable, filter) {
  var names = {}
  for (var name in installed) names[name] = true
  for (var globalName in globals) names[globalName] = true
  var query = String(filter || "").trim().toLowerCase()
  var result = []

  for (var tool in names) {
    if (query && tool.toLowerCase().indexOf(query) === -1) continue
    var selected = Array.isArray(globals[tool]) ? globals[tool] : []
    var active = selected.find(function(record) { return record.active }) || selected[0] || null
    var installedRecords = Array.isArray(installed[tool]) ? installed[tool] : []
    var prunableRecords = Array.isArray(prunable[tool]) ? prunable[tool] : []
    var versions = []

    for (var i = installedRecords.length - 1; i >= 0; i--) {
      var record = installedRecords[i]
      if (!record.installed) continue
      var version = String(record.version)
      versions.push({
        version: version,
        active: !!active && version === String(active.version),
        prunable: prunableRecords.some(function(candidate) { return String(candidate.version) === version })
      })
    }

    var requested = active ? String(active.requested_version || active.version || "") : ""
    var activeVersion = active && active.installed ? String(active.version) : ""
    var displayVersion = activeVersion || (selected.length ? requested : (versions[0] ? versions[0].version : ""))

    result.push({
      name: tool,
      configured: selected.length > 0,
      requested: requested,
      activeVersion: activeVersion,
      displayVersion: displayVersion,
      pinned: requested !== "" && requested === activeVersion,
      latest: updates[tool] && selected.length > 0 ? String(updates[tool].latest || "") : "",
      versions: versions.filter(function(item) { return item.version !== displayVersion })
    })
  }

  result.sort(function(a, b) {
    if (a.configured !== b.configured) return a.configured ? -1 : 1
    return a.name.localeCompare(b.name)
  })
  return result
}

function searchResults(text) {
  var result = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length && result.length < 4; i++) {
    var match = lines[i].match(/^(\S+)\s{2,}(.*)$/)
    if (match) result.push({ name: match[1], description: match[2] })
  }
  return result
}

function validToolSpec(value) {
  return /^[A-Za-z0-9][A-Za-z0-9_.:+/@-]*$/.test(String(value || "").trim())
}

function upgradeProgressLine(line, names) {
  var text = String(line || "").replace(/\x1b\[[0-9;]*m/g, "")
  for (var i = 0; i < names.length; i++) {
    var marker = names[i] + "@"
    var start = text.indexOf(marker)
    if (start < 0 || (start > 0 && !/\s/.test(text[start - 1]))) continue
    var match = text.slice(start + marker.length).match(/^\S+\s{2,}(.+?)\s{2,}\d+(?:\.\d+)?(?:ms|s)\b(?:\s{2,}(.+))?$/)
    if (!match) continue
    var amount = String(match[2] || "").match(/^(\d+(?:\.\d+)?)\/(\d+(?:\.\d+)?)(?:\s|$)/)
    var percent = amount && Number(amount[2]) > 0 ? Math.min(100, Math.round(100 * Number(amount[1]) / Number(amount[2]))) : null
    return { name: names[i], phase: match[1], percent: percent }
  }
  return null
}

function addRows(query, suggestions, known) {
  var text = String(query || "").trim()
  if (text.indexOf("@") !== -1) return validToolSpec(text) ? [{ name: text, description: "Install this version" }] : []
  return suggestions.filter(function(item) { return !known[item.name] })
}

function presetOptions(presets, current) {
  var value = String(current || "")
  if (presets.some(function(option) { return option.value === value })) return presets
  return presets.concat([{ value: value, label: value }])
}

if (typeof module !== "undefined") module.exports = {
  objectFromJson: objectFromJson,
  updateCount: updateCount,
  rows: rows,
  searchResults: searchResults,
  validToolSpec: validToolSpec,
  upgradeProgressLine: upgradeProgressLine,
  presetOptions: presetOptions,
  addRows: addRows
}
