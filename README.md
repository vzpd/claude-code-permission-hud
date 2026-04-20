# claude-code-permission-hud

A tiny macOS HUD that pops up **only when Claude Code actually needs your approval** — so you stop missing permission prompts while you're in another window.

## Why

Claude Code's built-in permission prompts live inside the terminal. If you tab away while Claude is working, you won't notice it's waiting for you — and Claude sits idle until you come back.

macOS's native notifications help a little, but they auto-dismiss and are easy to miss too. This tool shows a **persistent, click-to-dismiss HUD** on top of every space, with a sound, that fires on the exact moment Claude would have prompted you — allowlist hits and auto-approved tools stay silent.

## Requirements

- macOS (tested on Apple Silicon; should work on Intel too)
- Xcode Command Line Tools (`xcode-select --install`) for `swiftc`
- Claude Code installed, with a writable `~/.claude/settings.json`

## Install

```bash
git clone https://github.com/vzpd/claude-code-permission-hud.git
cd claude-code-permission-hud
./install.sh
```

This compiles the binary, copies it to `~/.claude/hooks/claude-notify`, and prints the JSON snippet you need to merge into `~/.claude/settings.json`.

## Configure

Add (or merge) this into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/claude-notify notify '需要你的授权批准' &"
          }
        ]
      }
    ]
  }
}
```

- `matcher: "permission_prompt"` is the exact Claude Code signal for "I need approval." Fires in both `default` and `auto` modes, only when an actual prompt is about to appear.
- The trailing `&` detaches the HUD process so the hook returns immediately.
- The quoted string is the HUD body text — swap it for anything you like.

## Verify

```bash
~/.claude/hooks/claude-notify notify "hello from claude-notify"
```

A small HUD should appear in the top-right with the Glass sound. Click anywhere on it to dismiss.

## Configuration

Everything is controlled via environment variables set in the hook command string. None are required — defaults match the screenshot.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `CLAUDE_NOTIFY_LANG` | `zh*` / `en*` | system locale | UI language. Anything not starting with `zh` or `en` falls back to English. |
| `CLAUDE_NOTIFY_SOUND` | any NSSound name / `none` / `off` / `0` | `Glass` | HUD sound. Set to `none` for silent. |
| `CLAUDE_NOTIFY_DEBUG` | `1` | unset | Verbose logs to stderr — parsed stdin, locale, decisions. |

Example combining several:

```json
"command": "CLAUDE_NOTIFY_LANG=en CLAUDE_NOTIFY_SOUND=none /Users/you/.claude/hooks/claude-notify notify &"
```

PRs adding more locales to `L10n` in `src/main.swift` welcome.

## Check the version

```bash
claude-notify --version
```

Version is injected at build time from `git describe` (e.g., `v0.2.0` on tagged releases, `a65168d-dirty` from local builds).

## Customize the UI

Colors, size, position, title, and font are hardcoded in `src/main.swift`. Tweak and rebuild:

```bash
make install
```

## Uninstall

```bash
make uninstall
```

Then remove the hook entry from `~/.claude/settings.json`.

## Development

```bash
make build      # compile to build/claude-notify (native arch)
make test       # non-interactive regression tests
make run        # compile + show a sample notify HUD
make install    # compile + copy to ~/.claude/hooks/
make universal  # fat binary (arm64 + x86_64) for release
make clean      # remove build/
```

## Troubleshooting

### The HUD doesn't appear

1. Run manually: `~/.claude/hooks/claude-notify notify "test"`. If nothing appears, the binary or macOS permissions are the culprit.
2. Check the binary is executable: `ls -l ~/.claude/hooks/claude-notify`.
3. Hook firing? Enable debug and tail the log: tell Claude Code to do something that needs approval, then check stderr in the Claude Code terminal — you should see `[claude-notify] debug: startup: args=...`.

### The HUD appears but no sound

- Silent mode override? Check `CLAUDE_NOTIFY_SOUND`.
- macOS alert volume? System Settings → Sound → Sound Effects.

### The HUD appears on the wrong screen

The HUD always renders on `NSScreen.main`, which macOS defines as the screen containing the active app. If Claude Code is on your second monitor, the HUD follows.

### `approve` mode hangs / Claude Code times out

- Make sure the hook command does **not** have a trailing `&`. With `&`, the hook returns immediately and Claude Code never sees the decision JSON.
- Check the stderr log with `CLAUDE_NOTIFY_DEBUG=1` — did the HUD render or did stdin parsing fail?
- If you killed the HUD process (or macOS did), the built-in SIGTERM handler should have emitted a fallback `ask` decision. Verify by `echo '{"tool_name":"Bash"}' | ~/.claude/hooks/claude-notify approve &` and then `kill -TERM <pid>`; stdout should contain a valid JSON `ask` decision.

### The HUD appears even for safe / allowlisted tools (approve mode)

That's a Claude Code design limitation, not a bug. `PreToolUse` fires on every matched tool call regardless of allowlist. Narrow your `matcher` regex — see the **Advanced: approve mode** section.

### `make build` fails with "statements are not allowed at the top level"

You're compiling with a renamed or extra Swift file. The entry point must be `src/main.swift` — the Makefile relies on this.

---

## Advanced: approve mode

The binary also ships a second mode — `claude-notify approve` — that shows a **larger HUD with three buttons (允许 / 问我 / 拒绝)** and returns your choice as a decision that Claude Code honors. Instead of tabbing to the terminal, you click a button.

**Tradeoff:** `approve` hooks into `PreToolUse`, which fires on **every** matched tool call — even tools already in your `permissions.allow`. Claude Code does not expose a "fire only when would-have-prompted" signal, so you must pick a matcher narrow enough to avoid HUD fatigue.

### Config

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/claude-notify approve",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

- **No trailing `&`** — the hook must stay alive until you click, so its stdout can carry your decision back to Claude Code.
- `matcher` is a regex matched against tool names. Widen / narrow to your taste. Empty `""` or `".*"` means every tool call triggers the HUD and is usually too aggressive.
- `timeout` is in seconds.

### Buttons

| Button | Keyboard | Result |
|---|---|---|
| 允许 / Allow | Return | `permissionDecision: "allow"` — tool runs immediately |
| 问我 / Ask | Esc | `permissionDecision: "ask"` — falls back to Claude Code's normal prompt |
| 拒绝 / Deny | — | `permissionDecision: "deny"` — blocks the tool; Claude receives the reason |
| ✕ close | — | Same as **问我 / Ask** |

### Manual test

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  | ~/.claude/hooks/claude-notify approve
# Click a button. stdout prints the decision JSON.
```

### Caveat

Even when you click 允许, Claude Code still honors `permissions.deny`. A HUD approval can't override a denylist. This is by design.

---

## Roadmap

- CLI flags for position / sound / colors
- Free-form reason field on deny
- Optional allowlist mirroring so `approve` can auto-allow tools already in `permissions.allow` (bringing behavior closer to "only fire when would-have-prompted")
- Linux / Windows ports

PRs welcome.

## License

MIT — see [LICENSE](LICENSE).
