extends RefCounted
# Lets a test that was written as a standalone `extends SceneTree` script
# run as one module inside a single shared Godot process, instead of paying
# a whole engine boot (1-4 minutes) per file.
#
# The conversion per test file is deliberately two lines, so converting one
# can't quietly change what it asserts:
#
#     extends SceneTree            ->  extends "res://dev_tests/test_base.gd"
#     func _init() -> void:        ->  func run() -> void:
#
# Everything else in the test body keeps working untouched, because this
# class supplies the three SceneTree members those bodies actually use:
#
#   root            - the real SceneTree's root Window, injected by the
#                     runner via setup() before run() is called. It cannot
#                     be a second SceneTree: only one can be the main loop,
#                     and a `.new()`ed SceneTree subclass has a null root.
#   process_frame   - the real tree's signal, so `await process_frame`
#                     still yields a genuine frame. This matters more than
#                     it looks: _ready() is DEFERRED in --script mode, so a
#                     scene's composed members are null until one passes.
#   quit()          - a no-op. Tests call it as their last line; letting
#                     that reach the real SceneTree would kill the runner
#                     partway through the suite.
#
# Deliberately declares NO `ok()` / `check()` / `fails` / `fail_count`.
# The existing tests each define their own, with different names, and a
# subclass redeclaring a base member is a hard parse error in GDScript.
# Result reporting stays where it already is: each test prints its own
# "ALL PASS (0 failures)" / "FAILURES (n failures)" line, and the runner
# scrapes stdout for those rather than coupling to a shared counter.

var tree: SceneTree = null
var root: Window = null
var process_frame: Signal


func setup(t: SceneTree) -> void:
	tree = t
	root = t.root
	process_frame = t.process_frame


## Swallowed on purpose — see the header. Accepts an exit code so a
## `quit(1)` in a test body still parses.
func quit(_exit_code: int = 0) -> void:
	pass


## Overridden by every test module. Named `run` rather than `_init` because
## `_init` fires during `.new()`, before the runner can inject `root`.
func run() -> void:
	push_error("test module did not override run()")


## Set by finish(). The runner treats a module that ends with this still
## false as a FAILURE.
##
## Closes a real hole found 2026-08-12: a module whose run() aborted partway
## (null deref, bad index) left its own `fails` counter at 0, so the runner
## scored it PASS — hiding a genuine abort through two full runs. An
## aborted test is not a passing test.
##
## VERIFIED the hard way: the obvious fix — `await run(); completed = true`
## inside a wrapper — DOES NOT WORK. GDScript halts the aborting function
## but returns control to the awaiting caller normally, so the assignment
## still ran and the abort still scored PASS. Godot also prints NOTHING to
## stdout or stderr for an out-of-range index here, so there is no output to
## key off either. The flag therefore has to be set by the module itself, at
## the end of its own run() — that is the only point that an abort provably
## cannot reach.
var completed: bool = false


## Every module MUST call this as the last thing run() does, and before any
## early `return` from run(). Forgetting it reports the module as aborted,
## which is deliberately fail-safe: a false alarm is loud and cheap, a
## missed abort is silent and expensive.
func finish() -> void:
	completed = true
