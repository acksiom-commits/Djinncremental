# dev_tests/

Local verification harnesses. Tracked in git (not gitignored) as of
2026-08-13 — `test_matrix_up_lint.gd` is a standing guard against a
recurring class of bug in the puzzle's deduction engine, and a guard that
only exists on one machine isn't one. They live in-tree, alongside the code
they test, so Godot can reach them through `res://` without copying files
in and out on every run — that part of the original reasoning still holds,
only the "not tracked" conclusion was wrong.

## Running

One command, always exactly this, from the project root:

```bash
"/c/Users/xosax/Downloads/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64_console.exe" --headless --script dev_tests/test_runner.gd
```

No `cd`, no `cp`, no `rm`, no pipe, no shell loop around it. That matters
for two reasons, both measured on this project:

- **Speed.** Booting Godot headless costs 1-4 minutes. `test_runner.gd`
  runs every module in ONE process; the old one-launch-per-file approach
  cost ~13 boots for the same suite.
- **Permission prompts.** Approval is matched on the command pattern, so a
  pipeline that varies per run (`| tail -30` one time, `| grep -E "..."`
  the next, a different `for` loop each time) needs a fresh approval almost
  every time. One unchanging string is approved once.

To run a subset, append `-- <substring>`. Use sparingly: it changes the
command string, which is the thing being kept stable.

```bash
... --script dev_tests/test_runner.gd -- same_position
```

## Adding a test

Write it as a normal test module:

```gdscript
extends "res://dev_tests/test_base.gd"

var fails: int = 0
func ok(c: bool, s: String) -> void:
    if c: print("  PASS  ", s)
    else: print("  FAIL  ", s); fails += 1

func run() -> void:
    ...
```

The runner auto-discovers any `test_*.gd` or `probe_*.gd` here (except
`test_runner.gd` and `test_base.gd`) and reports each module's `fails` or
`fail_count` in the summary.

**Filenames must start with** `test_` / `probe_` / `bench_` / `audit_` /
`diag` / `check_` / `verify_`. `test_record_boundary.gd` scans all of
`res://` for shipped code reaching into engine internals and uses that
prefix list as its harness allowlist — anything else here gets scanned as
if it were game code and false-positives.

## Converting a standalone `extends SceneTree` script

Two lines, deliberately — so converting one can't quietly change what it
asserts:

| from | to |
|---|---|
| `extends SceneTree` | `extends "res://dev_tests/test_base.gd"` |
| `func _init() -> void:` | `func run() -> void:` |

The body is otherwise untouched. `test_base.gd` supplies `root`,
`process_frame` and a no-op `quit()`; see its header for why each is
needed.

## probe_scratch.gd

The reusable throwaway driver. **Edit it in place** for one-off
investigations rather than creating `diag_foo.gd`, `diag_foo2.gd`,
`check_bar.gd` … — every new filename is a new command string and a new
permission prompt. Reset it to the template when done.
