# Changelog

All notable changes to this project are documented in this file.

This project follows semantic versioning.

## [1.0.0] - 2026-02-21

### Added
- Automated and interactive installation flow via `install.sh`.
- Docker-first deployment with:
  - interactive first-run config bootstrap,
  - environment variable bootstrap,
  - mounted config support,
  - host-metrics verification command (`--verify-host`).
- Optional SMS sending with explicit enable flag.
- Configurable server label via `server_name` / `SERVER_NAME` with `ipinfo.io` fallback.
- Systemd service/timer templates and scheduling documentation.
- GHCR Docker publishing workflow with multi-arch support (`amd64`, `arm64`).
- Agent contribution guide (`AGENT_WORKFLOW.md`).

### Changed
- Memory alerting now uses `mem_used_percent` threshold only (no MB-based alert threshold).
- Improved Docker setup reliability for non-interactive compose sessions.
- Added `vi` and `nano` editors in Docker image for in-container config editing.
- Updated README with deployment, test, update, and operational runbook guidance.
