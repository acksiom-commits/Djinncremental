extends Control
# ================= COOLDOWN BAR v1.0.0 =================
# Reusable cooldown/status bar for timed production operations.
# Self-contained: pulls all data from GameContext and
# ProductionManager directly via autoload paths.
#
# Set resource_key and operation_key in the Inspector.
# The bar handles:
#   - Cooldown fill progress (0->100% over timer interval)
#   - GenBar drain projection (time-to-empty as % of scaled window)
#   - Empty-resource blink-flash
#   - Not-ready flash on early button click
#
# Usage:
#   Instance CooldownBar.tscn as a child of any VBoxContainer.
#   Set resource_key (e.g. "sparks") and operation_key
#   (e.g. "sparks_summon") in the Inspector.
#   Call flash_not_ready() from the button's pressed handler
#   when the cooldown is not complete.
#   Call notify_tick() when the production timer fires so the
#   cooldown resets cleanly in sync with the actual timer.

# ===================== EXPORTS ====================
@export var resource_key:  String = ""
@export var operation_key: String = ""

# ===================== TUNING ===================
const BAR_HEIGHT:           float = 6.0
const FLASH_NOT_READY_TIME: float = 0.25   # seconds for not-ready flash to fade
const EMPTY_FLASH_SPEED:    float = 4.0    # sine cycles per second for empty blink
const DRAIN_WINDOW_SCALE:   float = 10.0   # seconds of drain = full GenBar

# ===================== NODE REFS =================
@onready var _progress_bar: ProgressBar = $ProgressBar

# ===================== AUTOLOAD REFS =============
var _gc: Node = null
var _pm: Node = null
var _gd: Node = null

# ===================== STATE =====================
var _cooldown_elapsed:    float = 0.0   # time since last tick
var _timer_interval:      float = 1.0   # pulled from ProductionManager
var _time:                float = 0.0   # running time for flash sine
var _not_ready_flash_t:   float = 0.0   # countdown for not-ready flash
var _base_color:          Color = Color.WHITE
var _is_ready:            bool  = false


func _ready() -> void:
    _gc = get_node_or_null("/root/GameContext")
    _pm = get_node_or_null("/root/ProductionManager")
    _gd = get_node_or_null("/root/GameData")
    _setup_bar()
    _refresh_interval()
    _refresh_color()
    _connect_to_timer()

func _connect_to_timer() -> void:
    if not _pm or operation_key == "":
        return
    var timer = _pm.get_node_or_null(operation_key + "_timer")
    if timer:
        timer.timeout.connect(notify_tick)
    else:
        push_warning("CooldownBar: timer not found for " + operation_key)


func _setup_bar() -> void:
    custom_minimum_size = Vector2(0, BAR_HEIGHT)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL

    if not _progress_bar:
        push_warning("CooldownBar: ProgressBar child not found on " + resource_key)
        return

    _progress_bar.min_value = 0.0
    _progress_bar.max_value = 100.0
    _progress_bar.value     = 0.0
    _progress_bar.show_percentage = false
    _progress_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
    _progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _refresh_interval() -> void:
    if not _pm:
        return
    var intervals = _pm.get_timer_intervals()
    if intervals.has(operation_key):
        _timer_interval = intervals[operation_key]


func _refresh_color() -> void:
    if not _gd or resource_key == "":
        return
    _base_color = Color.from_string(
        _gd.RESOURCES.get(resource_key, {}).get("color", "#ffffff"),
        Color.WHITE)


# ==================================================
# PUBLIC API
# ==================================================

# Call from the production timer's timeout signal so the
# cooldown resets in sync with the actual timer firing.
# TODO: connect to editor signal connection on timer timeout
func notify_tick() -> void:
    _cooldown_elapsed = 0.0
    _is_ready = false
    # Re-read interval in case a bonus has changed it
    _refresh_interval()


# Call from the manual button's pressed handler when
# the cooldown is not yet complete.
func flash_not_ready() -> void:
    _not_ready_flash_t = FLASH_NOT_READY_TIME


# Returns true if the cooldown is complete and a manual
# action is permitted this cycle.
func is_ready() -> bool:
    return _is_ready


# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
    if not _gc or not _pm or not _progress_bar:
        return

    _time += delta

    # Re-read interval each frame so bonus changes apply immediately
    _refresh_interval()

    # Advance cooldown
    _cooldown_elapsed = min(_cooldown_elapsed + delta, _timer_interval)
    _is_ready = (_cooldown_elapsed >= _timer_interval)

    var cooldown_pct = (_cooldown_elapsed / _timer_interval) * 100.0
    _progress_bar.value = clamp(cooldown_pct, 0.0, 100.0)

    # Determine display color
    var display_color = _base_color

    if _not_ready_flash_t > 0.0:
        # Not-ready flash: bright white fading back to accent color
        _not_ready_flash_t -= delta
        var t = clamp(_not_ready_flash_t / FLASH_NOT_READY_TIME, 0.0, 1.0)
        display_color = _base_color.lerp(Color.WHITE, t)

    elif _is_ready and _resource_is_empty():
        # Empty blink: sine pulse on the bar when resource pool is zero
        var pulse = sin(_time * EMPTY_FLASH_SPEED * TAU) * 0.5 + 0.5
        display_color = Color.RED.lerp(Color.WHITE, pulse * 0.5)

    _progress_bar.add_theme_stylebox_override("fill", _make_fill_style(display_color))
    _progress_bar.add_theme_stylebox_override("background", _make_bg_style())


# ==================================================
# HELPERS
# ==================================================
func _resource_is_empty() -> bool:
    if not _gc or resource_key == "":
        return false
    match resource_key:
        "sparks":   return _gc.sparks.is_zero()
        "monad":    return _gc.get_monad_total().is_zero()
        "tetrad":   return _gc.get_tetrad_total().is_zero()
        "iota":     return _gc.iota.is_zero()
        "mote":     return _gc.mote.is_zero()
        "particle": return _gc.particle.is_zero()
        "grain":    return _gc.grain.is_zero()
        "uonite":   return _gc.uonite.is_zero()
    return false


func _make_fill_style(color: Color) -> StyleBoxFlat:
    var s = StyleBoxFlat.new()
    s.bg_color                   = color
    s.corner_radius_top_left     = 2
    s.corner_radius_top_right    = 2
    s.corner_radius_bottom_left  = 2
    s.corner_radius_bottom_right = 2
    return s


func _make_bg_style() -> StyleBoxFlat:
    var s = StyleBoxFlat.new()
    s.bg_color                   = Color(0.07, 0.06, 0.10, 0.85)
    s.border_color               = Color(0.92, 0.90, 0.85, 0.35)
    s.border_width_left          = 1
    s.border_width_right         = 1
    s.border_width_top           = 1
    s.border_width_bottom        = 1
    s.corner_radius_top_left     = 2
    s.corner_radius_top_right    = 2
    s.corner_radius_bottom_left  = 2
    s.corner_radius_bottom_right = 2
    return s
