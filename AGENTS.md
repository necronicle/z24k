# Repository Guidelines

## Project Structure & Module Organization
- `z24k` and `z24k.sh` are the main installer/menu scripts used on Keenetic + Entware.
- `install.sh`, `install_bin.sh`, and `install_easy.sh` are supporting install flows.
- `categories.ini`, `strategies-*.ini`, and `blobs.txt` define category routing and strategy presets.
- `lists/` contains domain/ipset lists; `files/fake/` contains blob payload binaries.
- `init.d/` and `keenetic/` provide service hooks and router-specific extras.
- `blockcheck2.sh` and `blockcheck2.d/` are for strategy testing.
- `docs/` holds upstream documentation; `Makefile` builds native binaries from `nfq2/`, `ip2net/`, `mdig/`.

## Build, Test, and Development Commands
- `make` builds the embedded binaries into `binaries/my` (requires toolchain).
- `make clean` removes build artifacts across `nfq2/`, `ip2net/`, `mdig/`.
- `sh z24k` runs the menu locally (for logic checks; on router for real use).
- `curl -O https://raw.githubusercontent.com/necronicle/z24k/master/z24k && sh z24k` is the canonical install/upgrade command.

## Coding Style & Naming Conventions
- Shell scripts target POSIX `sh`; avoid Bash-only syntax.
- Use tabs/spaces as already present in file (no reformatting). Keep lines readable.
- INI keys are lower-case with underscores; section names are lower-case (e.g., `[youtube_udp]`).
- Strategy names mirror `strategies-*.ini` section headers (e.g., `syndata_multisplit_tls_google_700`).

## Testing Guidelines
- No automated test suite. Validate with:
  - Menu flow (`z24k`), service restart, and `blockcheck2.sh` execution.
  - List downloads into `/opt/zapret2/ipset/` on router.
  - Connectivity checks (TLS 1.2/1.3, optional HTTP/3) via menu.

## Commit & Pull Request Guidelines
- Commits follow short, imperative, sentence-case subjects (e.g., “Fix list_strategies parsing”).
- PRs should describe user-facing impact, affected scripts, and how to reproduce/verify.
- Link related issues or logs when debugging router-specific behavior.

## Configuration & Ops Notes
- Default mode is category-based rules from `/opt/zapret2/z24k-categories.ini`.
- Keep `lists/`, `strategies-*.ini`, and `blobs.txt` in sync with the menu logic.
- Avoid changing `curl -O ... && sh z24k` behavior without explicit approval.
