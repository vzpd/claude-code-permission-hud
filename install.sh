#!/usr/bin/env bash
# Build and install claude-notify into ~/.claude/hooks/, then print the
# default Notification-hook config snippet ready to merge into settings.json.
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This tool is macOS-only (uses AppKit)." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Install Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

make install

HOOK_PATH="$HOME/.claude/hooks/claude-notify"

cat <<EOF

────────────────────────────────────────────────────────────
 Merge this into ~/.claude/settings.json:

 {
   "hooks": {
     "Notification": [
       {
         "matcher": "permission_prompt",
         "hooks": [
           {
             "type": "command",
             "command": "${HOOK_PATH} notify '需要你的授权批准' &"
           }
         ]
       }
     ]
   }
 }

 The HUD fires only when Claude Code actually needs your approval
 — allowlist hits and auto-approved tools stay silent.

 Test it now:
   ${HOOK_PATH} notify "hello"

 Optional env vars (set in the hook command string):
   CLAUDE_NOTIFY_LANG=en        Force English UI (default: system locale)
   CLAUDE_NOTIFY_SOUND=none     Disable Glass sound (or name any system sound)
   CLAUDE_NOTIFY_DEBUG=1        Verbose logs on stderr

 Want an advanced HUD with Allow / Ask / Deny buttons that directly
 decides the outcome? See the "Advanced: approve mode" section in
 README.md.
────────────────────────────────────────────────────────────
EOF
