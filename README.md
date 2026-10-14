# Remote Desktop (omarchy plugin)

A bar widget and panel that run [hypr-rdp](https://github.com/MuNeNICK/hypr-rdp) on an
Omarchy machine: start and stop the server, set the RDP password, choose the interface and
port to listen on, pick the screen to share, and arm the server to come back with your
session — all without editing a config file or memorising flags.

The panel is the only control surface, and it drives the helpers that ship in this repo, so
the UI and the runtime it manages are always the same version.

## Requirements

- Omarchy (the shell, `omarchy` CLI and `omarchy-launch-terminal`).
- `hypr-rdp` — an AUR package (`omarchy-pkg-add hypr-rdp` is what the panel's **Install**
  button runs).
- `openssl` — used once to create the self-signed TLS identity.

## Install

```bash
omarchy plugin add https://github.com/yudopr11/omarchy-remote-desktop-server.git --enable --yes
omarchy restart shell
```

Then open the panel from the **RDP** pill in the bar and press **Install**. That runs
`install.sh` in a terminal, which installs the package if needed, copies the helpers into
`~/.local/bin`, writes the systemd user unit, creates the default options file and generates
the TLS certificate.

## The panel

| Section | What it does |
| --- | --- |
| Header | State chip: **Connected-ready**, **Password required**, **Stopped**, **Setup required**, **Status unavailable**. |
| Package | `hypr-rdp` presence and version, **Install**, and **Update runtime** when the installed helpers differ from this plugin's copy. |
| Power | **Start** (asks for a password first when there is none), **Stop & disarm**, and **Stop & forget password** when a password is stored on disk. |
| Credentials | The RDP username, and the password state — *held in RAM* or *stored on disk*. Passwords are only ever typed in a terminal, never in the panel. |
| Network | Listen on this machine only, any interface, a specific address, or a hostname you type; port (default 3389); **Copy address**; a warning when the bind is not loopback. |
| Display | A physical monitor (with its resolution) or a virtual display. |
| Start at login | Arms the service for future sessions; the first enable stores the password on disk so the service can come back without you. |
| Video | Frames per second, bitrate, H.264 backend and capture mode. |
| Footer | **Refresh**, **Logs** (`journalctl --user -u hypr-rdp.service -b`), and a reminder that changing settings restarts the service. |

Changing a setting restarts the service, so connected clients reconnect. The panel refreshes
itself while it is open.

## Command line

The panel is a front end for five helpers, which are equally usable on their own. They are
installed to `~/.local/bin` (the panel runs the copies bundled with the plugin).

```bash
omarchy-rdp-status                     # one JSON object: state of package, service, listener, runtime
omarchy-rdp-password [--store] [--password-stdin]
omarchy-rdp-stop [--forget]            # stop; --forget also deletes the stored password and disables the unit
omarchy-rdp-config get
omarchy-rdp-config set bind --mode localhost|lan|custom [--host H] [--port P]
omarchy-rdp-config set username --value U
omarchy-rdp-config set output --value NAME|virtual
omarchy-rdp-config set opt --fps N | --bitrate BPS | --h264-backend auto|software|vaapi \
                        | --capture-mode wlr|ext|none
omarchy-rdp-config set autostart --value on|off
omarchy-rdp-config restart             # restart only if it was running, then wait for the listener
omarchy-rdp-config start               # start an inactive service and wait for the listener
```

`omarchy-rdp-status` prints a single JSON object:
`installed`, `configured`, `armed`, `active`, `serviceKnown`, `listening`, `bind`, `endpoint`,
`host`, `port`, `username`, `output`, `virtual`, `autostart`, `storedPassword`, `version`,
`runtimeInstalled`, `runtimeStale`. `endpoint` is the address a client should connect to.

The install and removal scripts are also usable directly:

```bash
bash install.sh [--bind lan|localhost] [--skip-password]
bash uninstall.sh [--remove-config] [--remove-package]
```

Both print a JSON summary; `uninstall.sh` exits `3` when it skipped a file that it does not
own, and lists every skipped path.

A bar-widget panel can be opened from the command line too:

```bash
omarchy-shell shell toggle io.github.yudopr11.omarchy-remote-desktop-server
```

## Where things live

| Path | Contents |
| --- | --- |
| `~/.config/hypr-rdp/options` | `BIND`, `USERNAME` and the extra `hypr-rdp` flags. Comments and flags the panel does not know about are preserved. |
| `~/.config/hypr-rdp/password` | Optional stored password, `0600`, so the service can re-arm at login. |
| `~/.config/hypr-rdp/tls.crt`, `tls.key` | Self-signed certificate for the RDP listener (RSA 3072, SHA-256). |
| `$XDG_RUNTIME_DIR/hypr-rdp/password` | The password in RAM only. Removed by **Stop & disarm** and on logout. |
| `~/.config/systemd/user/hypr-rdp.service` | The user unit, started with the graphical session. |
| `~/.local/state/omarchy-rdp/installed-files/` | Ownership ledger: which files this plugin installed, and their checksums. |

## Security

- RDP gets its own credential — `hypr-rdp` uses a username/password pair, not your PAM
  password, so a leaked RDP password is not a shell password.
- Passwords are written `0600`, are never passed on a command line (the service reads
  `--password-file`), and never appear in the panel or its logs.
- The password is only stored on disk when you ask for it (autostart or `--store`); the
  default is a password that lives in RAM for the current session only.
- The panel warns when the listener is not loopback. Nothing here changes your firewall —
  exposing port 3389 to a network is your decision, and the warning is there to make it a
  conscious one.
- `install.sh` refuses to overwrite files it does not own, and `uninstall.sh` reports (and
  keeps) anything it did not install.

## Development

```bash
git clone https://github.com/yudopr11/omarchy-remote-desktop-server.git
cd omarchy-remote-desktop-server
ln -sfn "$PWD" ~/.config/omarchy/plugins/io.github.yudopr11.omarchy-remote-desktop-server
omarchy restart shell          # or: omarchy-shell shell rescanPlugins
bash tests/run.sh              # whole suite; bash tests/run.sh test-status.sh for one file
```

`tests/` runs against temporary `HOME`/`XDG_*` directories and stubbed system commands
(`systemctl`, `ss`, `ip`, `hyprctl`, …), so it never touches a real install and needs no root.
QML changes are live after the shell reloads the plugin; the panel's own actions can be
reproduced with the helpers above.

## Migration from the old plugin

This is the successor to `ylaung-uod/omarchy-rdp-plugin`. That plugin installed its own
`omarchy-rdp-*` helpers in `~/.local/bin`, a unit with the same name and its own
`~/.config/hypr-rdp/options`. To migrate:

1. Stop and disable the old runtime, then remove the old helpers, unit and config
   (`systemctl --user stop hypr-rdp.service`, `systemctl --user disable hypr-rdp.service`,
   `rm -f ~/.config/systemd/user/hypr-rdp.service ~/.local/bin/omarchy-rdp-{server,password,status,stop}`,
   `rm -rf ~/.config/hypr-rdp`, `systemctl --user daemon-reload`).
2. Install this plugin and press **Install** in the panel.
3. Set the password and pick the monitor and bind again from the panel — the panel re-reads
   what is actually there, so this is also how you verify the migration.

Legacy options are not adopted automatically: the file is small, and re-picking from the
panel is the acceptance test that everything works.

## Rollback

Reinstall the previous plugin (`omarchy plugin add https://github.com/ylaung-uod/omarchy-rdp-plugin --enable --yes`)
and run its installer again, or keep the files this plugin installed and run
`bash uninstall.sh --remove-config` to remove only what belongs to it.

## Tests

```bash
bash tests/run.sh
```

No root, no network, no real service: everything is driven through stubs.

## License

MIT — see [LICENSE](LICENSE).
