# Changelog

All notable changes to this project will be documented in this file. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [SemVer](https://semver.org/).

## [Unreleased]

### Added
- `CLAUDE_NOTIFY_DEBUG=1` env var streams parsed stdin, locale, and decision emission to stderr.
- `CLAUDE_NOTIFY_SOUND` env var: `none` / `off` / `0` disables the HUD sound; any other value is looked up as an NSSound name.
- `--version` / `-v` flag prints the compiled version (injected from `git describe` at build time).
- `make test` runs non-interactive regression tests against `approve` mode (empty / malformed / incomplete stdin).
- `make universal` produces a fat binary (arm64 + x86_64) for release distribution.
- Signal handler in `approve` mode: if the hook is killed by SIGTERM / SIGHUP before the user clicks, emit a fallback `ask` decision so Claude Code's default prompt still runs.
- GitHub Actions workflow (`.github/workflows/build.yml`) builds and tests on every push and PR.
- Troubleshooting / FAQ section in README.

### Changed
- `install.sh` now expands `$HOME` to the absolute path when printing the settings snippet, so older Claude Code loaders that don't evaluate env vars still work.
- Source renamed from `src/notify.swift` to `src/main.swift` (required once multi-file compilation with the generated version constant was introduced).

## [0.2.0] - 2026-04-20

### Added
- `approve` mode (`PreToolUse` hook) — larger HUD with **允许 / 问我 / 拒绝** buttons that return the decision directly to Claude Code via stdout JSON.
- `CLAUDE_NOTIFY_LANG` env var + auto-detected `L10n` struct (Chinese / English).
- `ApproveController` with re-entry guard (`didDecide`) to avoid double-emitting decisions on rapid clicks.

### Fixed
- Close button color now uses `attributedTitle` so the intended semi-transparent grey actually renders on HUD material.
- Body preview sizes to fit (`fittingSize.height`, capped at 3 lines) instead of leaving a hardcoded empty band for short commands.
- `permission` string typos no longer silently ship — they're now an `enum PermissionDecision`.

## [0.1.0] - 2026-04-20

### Added
- Initial release: `notify` mode with a small HUD reminder when Claude Code fires its `Notification` hook.
- `Makefile` build / install / run / clean targets.
- `install.sh` one-shot build + deploy script.
- README with install and configuration instructions.
