# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.11.0] - 2026-07-05
### Added
- **`installret.sh` — one-command installer / uninstaller.** A new top-level, bilingual (English / Russian) installer sets up the entire stack on a fresh machine: it detects the target user, installs the latest Reticulum stack (`rns`, `nomadnet`, `lxmf`) from PyPI, lays down configs, generates and enables all systemd services, and installs the `rn` / `f2b` management tools. The installer detects the distribution family and picks the right package manager automatically — `apt` for the Debian family (Debian, Ubuntu, Kali, HiveOS, Raspberry Pi OS, and derivatives) and `apt-get` for Alt Linux. The AI bot (Ollama + model) is optional and offered during installation.
- **`installret.sh` — automatic identity backup on uninstall.** Running `installret.sh --uninstall` always backs up every identity file (the irreplaceable cryptographic keys that define the node's, groups', and bot's network addresses) into a timestamped `/root/reticulum-backup-<timestamp>.tar.gz` (owner-only, `chmod 600`) **before** anything is deleted. The archive contains only identity files — configs, board, and databases are intentionally excluded, since they are recreated on reinstall. Covered keys: the Reticulum node's `transport_identity`, NomadNet, each distribution group (including dynamically created ones), the broadcaster, and the bot. When the backup is written, the uninstaller prints a short instruction block with the exact commands to inspect, restore (`tar -xvzf … -C /`, with a reminder to restart services afterward), and delete it.
- **`scripts/rn` — dynamic group status everywhere.** Groups created through the bot are now shown alongside the built-in services in `rn status` (terminal), in the Reticulum Services menu header, and in the main status view. Groups are discovered dynamically, so a newly created group appears automatically with no configuration.
- **`scripts/rn` — LXMF address and file path in headers.** The SURGUT GROUP, dynamic groups, and the bot menus now display their LXMF address and storage path in the header, read live from each identity file, so the operator can see and copy the exact network address of every component.
- **`scripts/rn` — live logs exit with ESC.** Log views that stream `journalctl -f` now run the log in the background and return to the menu on **ESC**, instead of requiring `Ctrl+C`. Every live-log screen shows a titled header naming the source and a bilingual hint.
### Changed
- **`scripts/rn` — instant, unified ESC navigation.** The ncurses `ESCDELAY` is lowered at startup, so a single ESC now reacts instantly instead of lagging by up to a second. ESC consistently means "back / cancel" from any menu, and the Back button behaves identically; tapping ESC walks up to the terminal from any depth.
- **`scripts/rn` and `scripts/f2b` — Enter / ESC confirmation model.** All yes/no prompts were unified: **Enter (or `y`) confirms** the action, `n` declines, and ESC cancels. Prompt hints were updated in both languages to match, and list/log viewers now exit on ESC only, removing the previous mix of `0` / `q` / `Q` exit keys.
- **`scripts/rn` — auto-sizing menus.** Dialog menus size themselves from the item count and terminal dimensions, so they render correctly on small terminals, phones, and remote sessions instead of overflowing.
- **`scripts/rn` and `scripts/f2b` — shared PIN.** Both tools now read a single PIN file, so one PIN protects the whole stack. Destructive actions in `rn` (editing the Reticulum config, updating packages, editing/restarting SSH) are PIN-guarded.
- **`scripts/rn` — cleaner status display.** Service names in status lines no longer carry emoji; private groups are marked with a single lock glyph and public groups are left unmarked, keeping the status output easy to scan.
- **`scripts/rn` and `scripts/f2b` — visible cancel button.** PIN and text-input dialogs now show explicit labelled OK / Back buttons, so cancelling with the button or ESC is obvious.
- **`installret.sh` — simplified uninstall.** Uninstall now asks a single confirmation and then removes everything (services, scripts, virtual environment, and all runtime data, including dynamically created groups). Identity keys are always backed up first, so a full removal is safe.
- **`README.md` — rewritten.** The project overview now explains what Reticulum is and what the stack actually gives you, leads with the one-command installer (with a link to the manual guide for advanced users), documents uninstall and identity restoration, lists supported systems, and includes an English screenshot gallery of `rn` and `f2b`.
### Fixed
- **`scripts/rn` — status color bug.** The `[running]` tag after a `[private]` group marker was rendered without color because the private marker reset the color state; the color is now reopened so the status stays correctly colored.
- **`scripts/rn` — `rn status` now includes groups.** The command-line `rn status` used its own service loop that skipped dynamically created groups; it now lists them the same way the interactive views do.
- **`scripts/rn` — stray escape characters after live logs.** Exiting a view no longer leaks leftover escape bytes (e.g. `^[`) into the shell; both the live-log viewer and the "press Enter" prompt now accept ESC cleanly and drain any trailing input.


## [0.10.0] - 2026-06-29
### Added
- **Bilingual interface (English / Russian)** across the whole management stack. Every user-facing string in `scripts/rn`, `scripts/f2b`, and `scripts/fetch-rnode-firmware.sh` is now served from a per-language dictionary, with English and Russian kept at parity. Proper nouns, device identifiers, firmware filenames, configuration keys, and user data are intentionally left untranslated.
- **Shared language switch.** A single language file (`.rn_lang`, stored next to the Reticulum user's data) drives all three scripts at once. Switching the language from `rn` ("Environment & Settings" -> language) instantly changes the language of `f2b` and `fetch-rnode-firmware.sh` as well; each script discovers the same file through identical user-resolution logic, so they never drift out of sync.
- **`scripts/f2b`** -- the Fail2ban manager is now part of the stack and shares the project's look and feel. Its main menu was converted to the same `dialog`-based TUI as `rn` (black background, cyan borders, white tags, color-coded items), while all informational screens (status, banned IPs, event log, attack statistics) remain in the plain terminal so they stay copyable.
- **`scripts/rn`** -- translated CLI help (`rn help`) now follows the active interface language.
### Changed
- **`scripts/f2b`** -- the header no longer hard-codes a machine name or DNS entry; it shows the current hostname dynamically and the obsolete DNS line was removed, making the script portable across installations.
- **`scripts/rn`** -- the Fail2ban Manager entry in the main menu now appears only when `f2b` is actually installed.
### Fixed
- **`scripts/rn`** -- opening the Fail2ban Manager is now guarded: if `f2b` is missing or removed after the menu is drawn, the script shows a short notice instead of crashing on a failed `exec`.

## [0.9.0] - 2026-06-24
### Changed
- **`scripts/rn`** — full conversion of the management interface to a `dialog`-based TUI. Every menu (main menu, services, NomadNet, groups, bot, knowledge base, logs, trusted users, RNode firmware, environment, SSH, monitoring, pages, message board, PIN dialogs) now renders as a proper boxed dialog with white tags, cyan borders, letter accelerators, and auto-sizing, replacing the previous arrow-key/raw-terminal navigation. Informational output (logs, statistics, conversations, address lists) is still printed to the plain terminal so it stays copyable.
- **`scripts/rn`** — broadcaster identity and storage paths are now resolved from environment variables at send time instead of being hard-coded, so the group-message sender is portable across installations.
### Added
- **`scripts/rn`** — smart numeric-input helper for menus, supporting variable-length numbers with instant Esc and Backspace handling.
### Fixed
- **`scripts/rn`** — RNode polling now stops every service that holds the serial port (including dynamic group services), queries the device, and restarts only the services that were previously active, fixing a bug where groups were left stopped after a poll.

## [0.8.0] - 2026-06-14
### Added
- **`scripts/rn`** — broadcaster-based group messaging. The "send message" menu now opens a submenu with: send message, recreate broadcaster, back up broadcaster identity, and restore from backup. A dedicated service identity (broadcaster) is registered in the group with send-only, anonymous rights, so the group itself distributes each post to all members under its own name — online immediately, offline via the group's propagation node.
### Changed
- **`scripts/rn`** — group messages are now sent by handing one message to the group's own distribution mechanism (via the broadcaster) instead of iterating over every member individually. This removes the previous manual per-recipient delivery loop and keeps the group service running while sending.
## [0.7.0] - 2026-06-04
### Fixed
- **`scripts/rn`** — composing a message to a group now opens an editor, so
  multi-line, multi-paragraph posts are delivered to members intact.
  Previously the prompt read a single line, so only the first line of a
  multi-paragraph post was sent.
### Removed
- **`scripts/rn`** — Meshtastic bridge management submenu and all of its
  helpers (status, restart, logs, config, node info, traffic monitor, version
  check, update, backup restore). The bridge deployment was already dropped
  from the installer; this removes the now-orphaned management UI. The original
  code remains available in git history if it is ever needed again.
## [0.6.0] - 2026-06-01
### Added
- **`scripts/rn`** — automatic PyPI access recovery for package updates.
  When the upstream PyPI host is unreachable (e.g. a CDN edge IP is blocked
  at the network level), the script now detects the failure and transparently
  cycles through a list of known-good Fastly edge IPs, writing the first
  working one into `/etc/hosts` before retrying. This keeps the
  "Update Reticulum packages" action working even when the default IP is
  filtered.
  - New helpers: `check_pypi_access()`, `fix_pypi_access()`,
    `ensure_pypi_access()`, `clean_pypi_hosts()`.
  - Reachability check uses `curl` with a `python3` fallback, so it works
    even on minimal systems without `curl`.
  - Fallback IP list is kept in a single `PYPI_FALLBACK_IPS` array for easy
    maintenance if edge addresses change.
  - New `[p] 🌐` entry in the environment/settings menu to check and repair
    PyPI access manually, showing any current `/etc/hosts` overrides.
### Changed
- **`scripts/rn`** — the "Update Reticulum packages" action now runs the
  PyPI reachability check first and only proceeds with `pip install` once
  access is confirmed (or successfully repaired).

## [0.2.0] - 2026-05-16

### Changed
- **`ollama-bot/cogs/ai.py`** — firmware catalog rewritten to use dynamic lookup.
  Instead of a hardcoded filename catalog (`FILE_CATALOG`), the bot now uses
  a `RNODE_DEVICES` device dictionary with filename patterns plus a
  `find_firmware()` helper that searches `knowledge/files/*.zip` for matches.
  This makes the bot resilient to upstream renames (e.g. `rnode_xxx.zip`
  → `rnode_firmware_xxx.zip`).
- **`ollama-bot/cogs/ai.py`** — the `/files` command now dynamically checks
  which firmwares are actually on disk and only lists those. A counter of
  missing firmwares is shown at the bottom.
- **`ollama-bot/cogs/ai.py`** — the `/get` command uses `find_firmware()` to
  locate firmware by pattern. If the file is missing, the bot informs the
  user and links to the GitHub releases page.
- **`scripts/fetch-rnode-firmware.sh`** — added new operating modes:
  - `--list` — show on-disk firmwares with sizes and backup counts;
  - `--missing` — download only firmwares not on disk;
  - `--no-overwrite` — skip existing files;
  - `--help` — usage examples;
  - positional arguments (`fetch ... t114 tbeam`) — selective download
    of specific devices by name.
- **`scripts/fetch-rnode-firmware.sh`** — backups of old versions now use
  a timestamp suffix (`<filename>.YYYYMMDD-HHMMSS`) with rotation
  (up to 5 versions of each firmware kept in `knowledge/files/.old/`).
  Previously there was a single backup that was overwritten on every update.
- **`scripts/fetch-rnode-firmware.sh`** — reconciliation with `RNODE_DEVICES`
  in `ai.py` updated for the new dictionary format.

### Added
- **`scripts/rn`** — new `[f] 🔄 Обновление прошивок RNode` entry in
  `menu_surgutbot`, opening a submenu with 4 actions:
  - `[1]` Update all firmwares (with backups),
  - `[2]` Download only missing firmwares,
  - `[3]` Update a single firmware (with name selection),
  - `[4]` Show what is currently on disk.
  Destructive operations (updating all or a single firmware) are PIN-protected.

### Infrastructure
- `.gitignore` now excludes `ollama-bot/knowledge/files/.old/` (local
  firmware backups, not meant to be committed).

## [0.1.0] - 2026-05-15

### Added
- Initial commit of the stack to GitHub.
- Main components:
  - `scripts/rn` — central bash stack manager (~4000+ lines);
  - `scripts/f2b` — fail2ban manager;
  - `scripts/fetch-rnode-firmware.sh` — RNode firmware sync;
  - `systemd/` — unit files for `surgutbot86`, `messageboard`, `nomadnet`,
    `ollama`;
  - `configs/` — Reticulum, NomadNet and LXMF group configurations
    (without identity files);
  - `ollama-bot/` — SurgutBot86 code (LXMF bot with Ollama / gemma2:9b);
  - `messageboard/` — message board code;
  - `lxmf-group/` — LXMF group server (SURGUT GROUP);
  - `nomadnet-pages/` — micron pages of the NomadNet propagation node.
- `README.md` describing the stack.
- `.gitignore` to protect identity, `.env` and runtime files.

[0.2.0]: https://github.com/Shah-man/reticulum-node-stack/releases/tag/v0.2.0
[0.1.0]: https://github.com/Shah-man/reticulum-node-stack/releases/tag/v0.1.0
