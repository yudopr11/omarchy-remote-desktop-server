# Remote Desktop — Omarchy plugin

Manage the [hypr-rdp](https://github.com/MuNeNICK/hypr-rdp) server from the Omarchy
bar: start and stop it, change credentials, pick the bind address and monitor,
and start it automatically at login. Full usage, prerequisites and the migration
notes for an existing hand-rolled `hypr-rdp` setup land in Task 12 of the
implementation plan (`docs/superpowers/plans/2026-10-14-omarchy-rdp-manager.md`).

Development install (this repo is not on GitHub yet): symlink the working tree
into the plugin directory and rescan, then enable it once from the bar.

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.yudopr11.omarchy-remote-desktop-server
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.yudopr11.omarchy-remote-desktop-server --section right
```

`omarchy plugin add <git-url>` is the install path once the repo is pushed; it
refuses an id that already exists, so remove the symlink first.
