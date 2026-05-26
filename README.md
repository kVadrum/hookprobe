# hookprobe

Run a Claude Code hook with synthetic input, see the decision.

A Claude Code `PreToolUse` hook reads a JSON envelope on stdin and
either prints nothing (allow) or prints a small JSON object asking
for approval or denying the tool call. Debugging a hook by hand
means hand-rolling the envelope, piping it into the script, and
squinting at the output.

`hookprobe` does that part for you, with a flag for the common case
(`--bash`), batch mode for fixture-driven tests, and a `--headless`
toggle so you can verify the `ask → deny` conversion that autonomous
sessions depend on.

```
hookprobe ./guardrails.sh --bash 'rm -rf ./tmp'
hookprobe ./guardrails.sh --bash 'npm publish' --headless
hookprobe ./guardrails.sh --batch cases.tsv
```

## Background

hookprobe came out of a private workshop where Claude builds small
utilities under operator oversight. The reflection on why
hooks-as-unit-testable-functions is a usefully different framing
than hooks-as-infrastructure:
[Hooks are functions. Test them.](https://github.com/kVadrum/claude-journal/blob/main/2026-05-20.md)
in [claude-journal](https://github.com/kVadrum/claude-journal).

## Why

Hooks are unit-testable. They take JSON on stdin and produce JSON on
stdout — that's just a function. But the framing as "shell scripts
the harness pipes envelopes into" makes them feel like infrastructure
rather than code you'd write tests for. So most hooks ship without a
test suite, and bugs surface in production: the legitimate `rm -rf
./tmp/scratch` you tried to run trips a deny that was meant to catch
`rm -rf /etc/passwd`.

`hookprobe` makes the function-shape obvious. Once you have one
fixture file with the cases that matter — the cases that go through,
the cases that get blocked, the headless-mode conversions — every
edit to the hook is a `--batch` rerun.

## Install

```
ln -s "$(pwd)/bin/hookprobe" ~/.local/bin/hookprobe
```

or run it in place at `bin/hookprobe`. Pure bash plus `jq`; no
package manager, no registry.

## Usage

```
hookprobe <hook> [flags]
```

Required: `<hook>` is the path to an executable hook script.

**Input flags** (pick one; default is empty Bash input):

| flag | meaning |
| --- | --- |
| `--bash CMD` | shorthand: `--tool Bash --input {"command":CMD}` |
| `--tool NAME` | tool name in the envelope (default: `Bash`) |
| `--input JSON` | full `tool_input` JSON object |
| `--event NAME` | hook event name (default: `PreToolUse`) |

**Environment flags**:

| flag | meaning |
| --- | --- |
| `--headless` | set `CLAUDE_HEADLESS=1` for the run |
| `--project-dir PATH` | export `CLAUDE_PROJECT_DIR` (default: cwd) |

**Output flags**:

| flag | meaning |
| --- | --- |
| (default) | pretty single line: `decision  reason` |
| `--json` | print the hook's raw stdout, nothing else |
| `--explain` | print envelope + raw output + decision |

**Batch mode**:

| flag | meaning |
| --- | --- |
| `--batch FILE` | read tab-separated cases, run each, summarize |

Batch file format (tab-separated, blank lines and `#`-comments ignored):

```
NAME<TAB>EXPECT<TAB>CMD[<TAB>HEADLESS]
```

- `EXPECT` is one of `allow`, `ask`, `deny`.
- `HEADLESS` is `0` (default) or `1`.

Exit code in single-shot mode:

| decision | exit |
| --- | --- |
| `allow` | 0 |
| `ask` | 10 |
| `deny` | 20 |
| malformed / argument error | 2 |

Batch mode exits 0 if every case matched, 1 otherwise.

## Examples

A toy hook lives at `examples/example-hook.sh`: denies `rm -rf /`,
denies `curl … | sh`, asks before `sudo`, converts ask → deny under
`--headless`. The fixtures under `tests/` exercise every shape.

```
$ hookprobe examples/example-hook.sh --bash 'ls -la'
allow

$ hookprobe examples/example-hook.sh --bash 'sudo apt update'
ask  sudo requires explicit approval

$ hookprobe examples/example-hook.sh --bash 'sudo apt update' --headless
deny  sudo requires explicit approval (headless session — ask converted to deny)

$ hookprobe examples/example-hook.sh --bash 'rm -rf /'
deny  rm -rf with absolute root path is not allowed
```

Batch:

```
$ hookprobe examples/example-hook.sh --batch tests/cases.tsv
  ok    rm rf root denied	(deny)
  ok    curl pipe sh denied	(deny)
  ok    sudo asks	(ask)
  ok    sudo denies under headless	(deny)
  ok    plain ls allowed	(allow)
  ok    git status allowed	(allow)
  ok    rm of single file allowed	(allow)
  ok    rm -rf relative allowed	(allow)

8 passed · 0 failed
```

## Tests

```
./tests/run-tests.sh
```

Twenty-six assertions cover single-shot decisions, exit codes,
`--explain`, `--json`, headless conversion, non-Bash passthrough,
batch success + failure, malformed input, and argument-error paths.
The tests use the toy hook under `examples/`; they do not require
any external Claude Code installation.

## What it deliberately is not

- Not a sandbox. `hookprobe` runs the hook script. If your hook
  forks subprocesses, makes network calls, or writes files, it will
  do those things. Hooks should be pure functions of their input;
  if yours isn't, that's already a problem.
- Not a static analyzer. The decision comes from running the hook,
  not from reading it. Hook bugs visible only under conditions you
  don't put in your fixtures will not be found here.
- Not a replacement for Claude Code's own hook execution. The
  envelope shape and the decision JSON format follow Claude Code's
  public hook contract; if the contract evolves, this tool needs to
  evolve with it. As of this writing it targets the `PreToolUse`
  `hookSpecificOutput.permissionDecision` shape.

## Status

v0.2.1. Extracted as a standalone repo. One-shot mode + batch mode.
Targets `PreToolUse` hooks with the
`hookSpecificOutput.permissionDecision` response shape. Pure
bash + jq.

---

KeMeK Network © 2026 — MIT licensed (see `LICENSE`).
