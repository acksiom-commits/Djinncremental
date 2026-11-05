extends Node
## Runs Kaleb's command stack (GameContext.kaleb_stack; SysDoc §7.3) on the
## Primordial page: one bar at a time, top to bottom, recycling to the top.
## Press bars wait for their button's cooldown, then press it through
## root_ui.gd (kaleb_press()), once per frame at most; Lock/Unlock and If-then
## bars are instant. Off bars are skipped. Created by root_ui.gd, so Kaleb
## works while the Primordial page is up.

const KalebCommands = preload("res://kaleb_commands.gd")

## Instant bars (locks, If-then, Off bars) Kaleb may pass in one frame. Keeps
## a stack of nothing but instant bars, or an If-then that jumps to itself,
## from spinning forever inside a frame.
const MAX_INSTANT_STEPS: int = 64

var ui: Node = null
var gc: Node = null


func setup(root_ui: Node, game_context: Node) -> void:
    ui = root_ui
    gc = game_context


func _process(_delta: float) -> void:
    step()


## One frame of work. Public so tests can drive Kaleb without waiting.
func step() -> void:
    if gc == null or ui == null or not gc.kaleb_running or gc.kaleb_stack.is_empty():
        return
    for _i in MAX_INSTANT_STEPS:
        if gc.kaleb_index < 0 or gc.kaleb_index >= gc.kaleb_stack.size():
            gc.kaleb_index = 0
            gc.kaleb_repeat_done = 0
        var bar: Dictionary = gc.kaleb_stack[gc.kaleb_index]
        var def: Dictionary = KalebCommands.COMMANDS.get(String(bar.get("cmd", "")), {})
        if def.is_empty() or not bool(bar.get("on", true)):
            _advance()
            continue
        match String(def["kind"]):
            "press":
                var cd: Node = ui._get_cooldown_bar(def["cooldown"]) if def["cooldown"] != "" else null
                if cd and not cd.is_ready():
                    return   # wait for the button
                ui.kaleb_press(def["handler"])
                gc.kaleb_repeat_done += 1
                if gc.kaleb_repeat_done >= int(bar.get("repeat", 1)):
                    _advance()
                return
            "lock", "unlock":
                _set_lock(String(bar.get("target", "")), def["kind"] == "lock")
                _advance()
            "if":
                if KalebCommands.test(gc, bar):
                    gc.kaleb_index = clampi(int(bar.get("goto", 0)), 0, gc.kaleb_stack.size() - 1)
                    gc.kaleb_repeat_done = 0
                else:
                    _advance()
            _:
                _advance()


func _advance() -> void:
    gc.kaleb_repeat_done = 0
    gc.kaleb_index = (gc.kaleb_index + 1) % gc.kaleb_stack.size()


## Puts the Purity Lock on `key` into the wanted state, through the same
## calls a click makes (they assign and free the lock's Volition). A lock
## that can't be had (no Volition free, locks not unlocked) is left as is.
func _set_lock(key: String, want: bool) -> void:
    if key == "" or not gc.locks.has(key):
        return
    if bool(gc.locks.get(key, false)) == want:
        return
    if key.begins_with("cat_"):
        gc.toggle_category_lock(key)
    else:
        gc.toggle_lock(key)
