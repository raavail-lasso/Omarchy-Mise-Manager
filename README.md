# Omarchy Mise Manager

A Quickshell bar widget for Omarchy 4.x that shows mise tool updates and manages global tool selections.

## Features

- Bar update count, checked every 30 minutes and on demand.
- Global tool inventory, active versions, and older installed versions.
- Update one tool or all outdated global tools. The Updates tab can keep replaced versions or let mise auto-prune them after its configured grace period; the choice is saved with the widget.
- Search mise's tool registry and install a tool globally. Enter `tool@version` to pick a release.
- Select an installed version globally, unselect a global tool while keeping its files, or delete an unused installed version. Exact global version requests are marked Pinned. Destructive actions require confirmation; deletion appears only for versions reported by `mise ls --prunable`.

The plugin uses `mise` directly. It never edits project configuration and does not need another service or dependency.

## Install locally

Validate the plugin folder with `omarchy plugin validate .`, then copy `manifest.json`, `BarWidget.qml`, and `Model.js` into `~/.config/omarchy/plugins/raavail.mise-manager/`. Run `omarchy plugin enable raavail.mise-manager --section right` while Omarchy Shell is running. The widget works with the stock bar and other bars using Omarchy's widget registry, including Islands Bar.

## Controls

- Left click: open or close the manager.
- Middle click: refresh.
- The popup has Updates, Tools, and Add tabs. Filter installed tools in Tools; search the registry or enter `tool@version` in Add.
- Auto-prune affects upgrades started in this popup. Off keeps replaced versions; on uses mise's configured pruning grace period.
- `Unselect` removes the tool from global mise configuration with `--no-prune`; `Delete` removes one installed version after confirmation.

The version labelled active is the one selected in global mise configuration. Project-local configurations may select another version when you enter their directories.
