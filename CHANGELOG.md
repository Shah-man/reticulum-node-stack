# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
