#!/usr/bin/env bash
# Regression tests for claude-notify approve mode. Covers the non-interactive
# paths (empty / malformed / incomplete stdin). Interactive paths — actual
# button clicks — must be exercised manually.
set -euo pipefail

BIN="${BIN:-./build/claude-notify}"
if [[ ! -x "$BIN" ]]; then
  echo "Binary not found or not executable: $BIN" >&2
  echo "Run 'make build' first." >&2
  exit 1
fi

pass=0
fail=0

check() {
  local name=$1
  local stdin=$2
  local expected=$3
  local out
  out=$(printf '%s' "$stdin" | "$BIN" approve 2>/dev/null || true)
  if grep -q -- "$expected" <<<"$out"; then
    echo "  ok  $name"
    pass=$((pass + 1))
  else
    echo "  FAIL $name"
    echo "       stdin: $(printf '%q' "$stdin")"
    echo "       want substring: $expected"
    echo "       got: $out"
    fail=$((fail + 1))
  fi
}

echo "Regression tests for $BIN"

check "empty stdin defers to ask"        ""                        '"permissionDecision":"ask"'
check "non-JSON text defers to ask"      "not json at all"         '"permissionDecision":"ask"'
check "JSON array (not object) defers"   "[1,2,3]"                 '"permissionDecision":"ask"'
check "JSON missing tool_name defers"    '{"foo":"bar"}'           '"permissionDecision":"ask"'
check "reason string is included"        ""                        '"permissionDecisionReason"'
check "hookEventName is PreToolUse"      ""                        '"hookEventName":"PreToolUse"'
check "version flag prints something"    ""                        "."

# Version flag is its own codepath
ver=$("$BIN" --version)
if [[ -n "$ver" ]]; then
  echo "  ok  --version prints: $ver"
  pass=$((pass + 1))
else
  echo "  FAIL --version produced no output"
  fail=$((fail + 1))
fi

echo ""
echo "Passed: $pass   Failed: $fail"
[[ $fail -eq 0 ]]
