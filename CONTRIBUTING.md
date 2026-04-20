# Contributing

Thanks for your interest. This project is small on purpose — a single Swift file, a Makefile, and a few shell/docs glue files. Contributions that keep it that way are very welcome.

## Dev setup

```bash
git clone https://github.com/vzpd/claude-code-permission-hud.git
cd claude-code-permission-hud
make build        # compiles to build/claude-notify
make test         # non-interactive regression tests
make run          # shows a sample notify HUD
```

You need:
- macOS (AppKit is the GUI layer)
- Xcode Command Line Tools (`xcode-select --install`) for `swiftc` and `lipo`

## Before opening a PR

1. `make test` passes.
2. `make universal` succeeds (catches arch-specific regressions).
3. If you changed user-visible behavior, update **README.md** and **CHANGELOG.md** (`[Unreleased]` section).
4. Interactive paths (actual HUD rendering, button clicks) are not covered by `make test` — verify by hand and note what you tested in the PR description.

## Code conventions

- Keep everything in `src/main.swift` until the file crosses ~600 lines. Premature splitting adds build complexity with no payoff at this scale.
- No third-party dependencies. Cocoa + Foundation + Darwin only. Any new dependency needs a clear justification.
- User-facing strings go through `L10n` (both `zh` and `en`). Protocol strings sent back to Claude Code (`permissionDecisionReason`, hook field names) stay English for log-searchability.
- New env vars use the `CLAUDE_NOTIFY_*` prefix. Document them in the README **Configuration** section and `install.sh` output.

## Adding a language

1. Add a new `static let <code>` to `L10n` with all fields filled in.
2. Extend `resolveLocale()` with the prefix check.
3. Mention the new locale in README **Language** section.

## Release process (maintainers)

1. Update `CHANGELOG.md`: move `[Unreleased]` items under a new version heading.
2. Commit: `chore: release vX.Y.Z`.
3. Tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`.
4. Push: `git push && git push --tags`.
5. CI builds the universal binary; attach it to the GitHub Release.
