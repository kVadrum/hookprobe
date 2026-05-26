#!/usr/bin/env bash
# example-hook.sh — toy Claude Code PreToolUse hook for hookprobe's tests
# and documentation. Demonstrates the input/output contract and the
# three common decisions (allow / ask / deny).
#
# Rules:
#   - Bash commands containing 'rm -rf /' or 'curl ... | sh'  → deny
#   - Bash commands containing 'sudo'                          → ask
#                                                                (in headless mode, converted to deny)
#   - everything else (any tool, any other Bash)               → allow

set -euo pipefail

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"
[[ "$tool" != "Bash" ]] && exit 0

cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"

emit() {
  local decision="$1" reason="$2"
  jq -cn --arg d "$decision" --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

ask() {
  if [[ "${CLAUDE_HEADLESS:-}" == "1" ]]; then
    emit deny "$1 (headless session — ask converted to deny)"
  fi
  emit ask "$1"
}

# Hard blocks.
# Match rm with combined -rf/-fr flags followed by a bare /, where the
# path arg is exactly "/" (followed by whitespace, end-of-string, or a
# shell separator). Won't match rm -rf /etc/passwd or rm -rf ./.
if grep -qE '(^|[[:space:]&|;])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*|-[a-zA-Z]*[fF][a-zA-Z]*[rR][a-zA-Z]*)[[:space:]]+/([[:space:]]|$|[;&|])' <<<"$cmd"; then
  emit deny "rm -rf with absolute root path is not allowed"
fi
if grep -qE 'curl[^|;]*\|[[:space:]]*(sh|bash)' <<<"$cmd"; then
  emit deny "curl | sh pattern is not allowed"
fi

# Ask gates.
if grep -qE '(^|[[:space:]&|;])sudo([[:space:]]|$)' <<<"$cmd"; then
  ask "sudo requires explicit approval"
fi

exit 0
