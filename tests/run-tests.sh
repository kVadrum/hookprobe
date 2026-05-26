#!/usr/bin/env bash
# Self-tests for hookprobe.
#
# Exercises:
#   1. Single-shot mode against the example hook (one assertion per decision).
#   2. Exit codes (0 / 10 / 20 / 2).
#   3. --explain output contains the envelope + raw + decision.
#   4. --json mode prints the raw hook output unchanged.
#   5. Batch mode against examples/example-hook.sh + tests/cases.tsv all pass.
#   6. Batch mode with a deliberately-broken case returns non-zero.
#   7. Non-Bash tools pass through (the example hook ignores Read).
#   8. Malformed --input JSON is reported as malformed (exit 2).
#
# Run:  ./tests/run-tests.sh         (from anywhere; auto-resolves paths)

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$HERE/.." && pwd)"
HP="$PROJECT_DIR/bin/hookprobe"
HOOK="$PROJECT_DIR/examples/example-hook.sh"
CASES="$PROJECT_DIR/tests/cases.tsv"

pass=0; fail=0
failures=()

# assert_eq <name> <expected> <actual>
assert_eq() {
  if [[ "$2" == "$3" ]]; then
    pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else
    fail=$((fail + 1))
    failures+=("$1: expected [$2] got [$3]")
    printf '  FAIL  %s\n        expected [%s]\n        got      [%s]\n' "$1" "$2" "$3"
  fi
}

# assert_contains <name> <needle> <haystack>
assert_contains() {
  if [[ "$3" == *"$2"* ]]; then
    pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else
    fail=$((fail + 1))
    failures+=("$1: expected substring [$2]")
    printf '  FAIL  %s\n        looking for [%s]\n        in: %s\n' "$1" "$2" "$3"
  fi
}

[[ -x "$HP" ]]   || { echo "hookprobe not executable: $HP" >&2; exit 2; }
[[ -x "$HOOK" ]] || { echo "example hook not executable: $HOOK" >&2; exit 2; }
[[ -r "$CASES" ]]|| { echo "cases file unreadable: $CASES" >&2; exit 2; }

echo "==> single-shot decisions"
out="$("$HP" "$HOOK" --bash 'ls -la' 2>&1)";        rc=$?
assert_eq  "allow decision text" "allow" "$(awk '{print $1}' <<<"$out" | head -1)"
assert_eq  "allow exit code"     "0"      "$rc"

out="$("$HP" "$HOOK" --bash 'sudo apt' 2>&1)";      rc=$?
assert_eq  "ask decision text"   "ask"   "$(awk '{print $1}' <<<"$out" | head -1)"
assert_eq  "ask exit code"       "10"    "$rc"

out="$("$HP" "$HOOK" --bash 'rm -rf /' 2>&1)";      rc=$?
assert_eq  "deny decision text"  "deny"  "$(awk '{print $1}' <<<"$out" | head -1)"
assert_eq  "deny exit code"      "20"    "$rc"

echo
echo "==> headless converts ask → deny"
out="$("$HP" "$HOOK" --headless --bash 'sudo apt' 2>&1)"; rc=$?
assert_eq  "headless sudo → deny" "deny" "$(awk '{print $1}' <<<"$out" | head -1)"
assert_eq  "headless deny exit"   "20"   "$rc"

echo
echo "==> --explain shows envelope + raw + decision"
out="$("$HP" "$HOOK" --explain --bash 'rm -rf /' 2>&1)"
assert_contains "explain has hook line"     "hook:"     "$out"
assert_contains "explain has input line"    "input:"    "$out"
assert_contains "explain has decision line" "decision:" "$out"
assert_contains "explain has raw output"    "permissionDecision" "$out"

echo
echo "==> --json emits raw output"
out="$("$HP" "$HOOK" --json --bash 'rm -rf /' 2>&1)"
assert_contains "json has permissionDecision" "permissionDecision" "$out"
# allow case prints nothing on --json
empty_out="$("$HP" "$HOOK" --json --bash 'ls' 2>&1)"
assert_eq "json allow prints nothing" "" "$empty_out"

echo
echo "==> non-Bash tool passes through"
out="$("$HP" "$HOOK" --tool Read --input '{"file_path":"/etc/passwd"}' 2>&1)"; rc=$?
assert_eq "Read tool allow"    "allow" "$(awk '{print $1}' <<<"$out" | head -1)"
assert_eq "Read tool exit 0"   "0"     "$rc"

echo
echo "==> batch mode runs cases.tsv against example hook"
batch_out="$("$HP" "$HOOK" --batch "$CASES" 2>&1)"; rc=$?
# All cases should pass — exit 0.
assert_eq "batch overall exit 0" "0" "$rc"
assert_contains "batch summary present"  "passed"  "$batch_out"
assert_contains "batch no failures listed" "0 failed" "$batch_out"

echo
echo "==> batch mode reports failure when an expectation is wrong"
bad_cases="$(mktemp)"
printf 'bad case\tdeny\tls -la\n' > "$bad_cases"
batch_bad="$("$HP" "$HOOK" --batch "$bad_cases" 2>&1)"; rc=$?
rm -f "$bad_cases"
assert_eq "batch bad case exits non-zero" "1" "$rc"
assert_contains "batch bad case shows FAIL" "FAIL" "$batch_bad"

echo
echo "==> malformed --input JSON yields malformed"
out="$("$HP" "$HOOK" --tool Bash --input 'not json' 2>&1)"; rc=$?
assert_eq "malformed decision" "malformed" "$(awk '{print $1}' <<<"$out" | head -1)"
assert_eq "malformed exit 2"   "2"         "$rc"

echo
echo "==> error reporting"
out="$("$HP" --bash 'ls' 2>&1)"; rc=$?
assert_contains "missing hook errors out" "missing hook" "$out"
assert_eq "missing hook exit 2" "2" "$rc"

out="$("$HP" /nonexistent --bash 'ls' 2>&1)"; rc=$?
assert_contains "non-executable errors out" "not executable" "$out"

echo
echo "---"
echo "$pass passed · $fail failed"
if (( fail > 0 )); then
  printf '\nfailures:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
