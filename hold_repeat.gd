extends RefCounted
# ================= HOLD REPEAT =================
# Hold-to-repeat for assignment +/- buttons. The first step fires on press
# (not release, as `pressed` would); after INITIAL_DELAY it repeats every
# REPEAT_START seconds, ramping down to REPEAT_MIN over RAMP_TIME of
# continued holding. Each repeat is one normal press of the button's action.
#
# Used by the allocation wheel (Uonite/Focus) and the Constellation popout
# (Focus). Volition +/- buttons are deliberately NOT hold-repeat on either:
# Volition assignment is kept apart from the other automation resources by
# design, so each one is placed by its own click.
#
# The owner keeps one instance, calls connect_button() per button, and
# tick(delta) from its _process(). Load with preload(), not a class_name.

const INITIAL_DELAY := 0.4
const REPEAT_START  := 0.2
const REPEAT_MIN    := 0.05
const RAMP_TIME     := 1.5

# The button currently held, if any
var _button: Button = null
var _action: Callable
var _elapsed: float = 0.0
var _timer: float = 0.0


func connect_button(btn: Button, action: Callable) -> void:
    btn.button_down.connect(func(): _start(btn, action))
    btn.button_up.connect(func(): _stop(btn))


func _start(btn: Button, action: Callable) -> void:
    action.call()
    _button  = btn
    _action  = action
    _elapsed = 0.0
    _timer   = INITIAL_DELAY


func _stop(btn: Button) -> void:
    if _button == btn:
        _button = null


## Call after the owner refreshes its buttons' disabled state, so a pool that
## just ran dry has already disabled its button. Godot drops a disabled
## button's press state, so the hold ends there rather than resuming if the
## pool refills mid-hold. Dragging off the button pauses the repeat without
## ending the hold. At most one step fires per frame, so a slow frame never
## bursts several at once.
func tick(delta: float) -> void:
    if _button == null:
        return
    if _button.disabled or not _button.is_pressed():
        _button = null
        return
    _elapsed += delta
    _timer -= delta
    if not _button.get_global_rect().has_point(_button.get_global_mouse_position()):
        return
    if _timer > 0.0:
        return
    _action.call()
    var ramp: float = clampf((_elapsed - INITIAL_DELAY) / RAMP_TIME, 0.0, 1.0)
    _timer = lerpf(REPEAT_START, REPEAT_MIN, ramp)
