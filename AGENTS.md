# Omarchy Mise Manager

A bar widget for managing global mise tools in Omarchy. `BarWidget.qml` is the
popup and bar indicator; `Model.js` handles mise output and command arguments.

## Dev loop

Edit files here in `~/Projects/Omarchy Mise Manager`. The live plugin at
`~/.config/omarchy/plugins/raavail.mise-manager` is a checkout of the published
GitHub repo. Omarchy runs that copy.

`~/.local/bin/mise-manager` drives the loop. It lives outside this repo because
it cleans a tree, updates a plugin, and restarts a service; those actions read
like an installer to the plugin marketplace's security scan.

**1. See your change live** — no commit needed:

```bash
mise-manager sync --restart
```

`mise-manager sync` copies without restarting. The shell runs with its file
watcher off, so use `--restart` when a change does not appear.

**2. Once you're happy**, commit and push from this project.

**3. Deploy the published commit:**

```bash
mise-manager deploy --yes
```

This restores the live checkout, fast-forwards it from GitHub, checks its HEAD,
and restarts the shell. Omit `--yes` for an interactive update prompt. Deploy
refuses uncommitted or unpushed work because it ships the remote commit.

### Doing it by hand

```bash
# 1. sync
rsync -a --delete --exclude='.git/' --exclude='CLAUDE.md' \
  "$HOME/Projects/Omarchy Mise Manager/" \
  "$HOME/.config/omarchy/plugins/raavail.mise-manager/"
omarchy-restart-shell
omarchy-shell shell ping

# 2. commit and push from the project

# 3. tidy up the live copy
git -C "$HOME/.config/omarchy/plugins/raavail.mise-manager" checkout .
git -C "$HOME/.config/omarchy/plugins/raavail.mise-manager" clean -fd

# 4. pull the published version and restart
omarchy plugin update raavail.mise-manager --yes
omarchy-restart-shell
omarchy-shell shell ping
```

### Four things not to get wrong

- Keep `-C` on the live Git commands. Without it, they can delete project work.
- Never add `--delete-excluded` to rsync. It would remove the live `.git` folder.
- Clean the live copy before updating. Local files can block the fast-forward.
- `checkout .` alone is not enough. It restores tracked files, but `clean -fd`
  must remove files added by sync.
