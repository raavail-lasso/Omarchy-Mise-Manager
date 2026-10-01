# Omarchy Mise Manager — project state

## Goal

Build a Quickshell `bar-widget` plugin for Omarchy 4.x that manages mise tools selected globally on this machine.

## Scope agreed

- Bar indicator for available mise tool updates.
- Popup showing globally selected tools, active versions, and older installed versions.
- Manual and periodic refresh, per-tool update, and update-all.
- Global tool search/install, version selection, and removal with clear distinctions between changing configuration and deleting an installed version.
- Project-local `mise.toml` management is a later feature.

## Current environment

- Omarchy 4.0.4-1, mise 2026.9.12, Quickshell installed.
- Active bar: `raavail.islands-bar`; it uses the standard widget registry.
- This project directory began empty.
- Omarchy plugins are user-owned directories with a `manifest.json` and QML entry point. The installed shell and its built-in widgets are available as read-only examples under `/usr/share/omarchy/shell/`.

## Implementation decisions

- Use mise's CLI and JSON output; do not add a daemon or dependency.
- Keep all writes explicitly global. Distinguish `mise uninstall TOOL@VERSION` from `mise unuse --global TOOL`.
- Run one mutation at a time, show progress/errors, and refresh after completion.
- Ask for confirmation before removing an installed version or a global tool request.
- Use one screen, no tabs: header actions, one search field that filters tools and finds registry tools, and one alphabetical tool list with inline updates. Older versions sit in each row's expanded section.
- Expose mise's own settings instead of widget-only copies: auto-prune, prune wait, and release cooldown behind the gear button. Pin and cooldown exceptions live in each tool's expanded row; pin edits `tools.<name>.version` with `mise config set --global`, and unpin returns to `latest`. Presets use ButtonGroup rather than Dropdown popups, which the panel window can clip.
- Leave cache, prerelease, network, and verification settings at mise defaults.

## Progress

- [x] Inspected local Omarchy plugin contract and mise CLI.
- [x] Created this state file.
- [x] Implement global-tool plugin and model check.
- [x] Validate manifest and QML syntax; static lint still reports expected dynamic Omarchy API warnings.
- [x] Test mise read commands and dry-run the global selection and version deletion command forms.
- [x] Install plugin files and place widget in the saved right-side bar layout.
- [x] Exercise Updates, Tools, Add, and registry search in the running Omarchy desktop session.
- [x] Verify pinned global versions and auto-prune setting persistence in the live widget.

## Known test limit

- Mutating actions were not run during the UI check; their command forms were previously dry-run.

## Follow-up ideas

- Project-local tools and configuration selection.
- Pin/range controls and release information, if needed after daily use.
