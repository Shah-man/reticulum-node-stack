# Reticulum Node Stack

A complete, production-ready stack for running a Reticulum network node — an AI-powered LXMF bot, a NomadNet propagation node, a message board, and extended LXMF distribution groups, all managed through a single interactive shell tool.

## What's inside

### `scripts/`
Bash tools for managing the node:
- **`rn`** — main interactive stack manager (PIN protection, ESC navigation, inline editing of knowledge base and group configs)
- **`f2b`** — interactive fail2ban manager with SQLite stats and recidive jail support
- **`fetch-rnode-firmware.sh`** — RNode firmware synchronization with selective updates and versioned backups

### `systemd/`
Unit files for service auto-start:
- `surgutbot86.service` — AI bot (Ollama + LXMF)
- `messageboard.service` — NomadNet message board
- `nomadnet.service` — propagation node + pages
- `ollama.service` — Ollama server for LLM inference

### `configs/`
Configurations (without identity files or runtime state):
- `reticulum-root/` — main node (`/root/.reticulum/config`)
- `reticulum-user/` — Reticulum config for the bot (`/home/user/.reticulum/config`)
- `nomadnet/` — NomadNet propagation node

### `ollama-bot/`
**SurgutBot86** — AI assistant on the LXMF network:
- Model: `gemma2:9b` (GPU acceleration)
- Knowledge base covering Reticulum, RNode, antennas, FAQ
- Group management (SURGUT GROUP, izbrannoe)
- Whitelist-based access control for group operations
- `config.example.env` — template for your own `.env`

### `nomadnet-pages/`
Propagation node pages and shared files:
- `pages/` — `.mu` micron pages (index, guide, board)
- `files/` — shared files served by the node (Meshtastic interface, etc.)

### `messageboard/`
A customized message board that attaches to the shared `rnsd` instance
instead of spawning its own Reticulum instance.

### `lxmf-group/`
Extended LXMF distribution group server:
- **SURGUT GROUP** — public group
- **izbrannoe** — private group

## Hardware requirements

- **GPU**: NVIDIA with at least 10 GB VRAM (the `gemma2:9b` model uses ~8–9 GB; the bot is tested on RTX 4090)
- **CPU fallback**: technically supported, but expect ~30–120 seconds per response — not recommended for live use
- **RAM**: 16 GB minimum, 32 GB recommended (Ollama + Reticulum stack + NomadNet)
- **Disk**: 20 GB free (model + stack + system overhead + room for logs and NomadNet propagation cache to grow)
- **Network**: a static public IP is strongly recommended for the propagation node and TCP peering

## Deployment

1. Restore identity files from a private backup into the system paths:
   - `/root/.reticulum/storage/`
   - `/home/user/.reticulum/storage/`
   - `/home/user/ollama-bot/config/identity`
   - `/root/.nomadnetwork/storage/identity`
   - `/root/.nomadmb/storage/identity`
   - `/root/.config/lxmf_distribution_group_extended/identity`
   - `/root/.config/lxmf_group_izbrannoe_private/identity`
2. Place files from this repo into the appropriate system paths (see `docs/deployment.md`)
3. Enable the systemd units
4. Create the bot `.env` from `config.example.env`

## Security

- All identity files and secrets are excluded via `.gitignore`
- Bot `.env` is **not** in the repository
- Identity files are stored encrypted **outside** the repository

## Tech stack

- **Reticulum Network Stack (RNS)** v1.2.6
- **LXMF** — extended distribution group
- **NomadNet** — propagation node + pages
- **Ollama** + `gemma2:9b` — LLM backend
- **Python 3.10 / 3.11** — runtime
- **fail2ban** + custom manager
- **HiveOS** — host OS

## Versioning

This project follows [Semantic Versioning](https://semver.org/). See [`CHANGELOG.md`](CHANGELOG.md) for the full release history.
