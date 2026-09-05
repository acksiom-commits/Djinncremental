extends Control
# ================= COOLDOWN BAR v1.4.0 =================
# v1.4.0: Empty-pool flash now requires both workers assigned
#         AND resource produced at least once this session.
#         _has_ever_produced flag set on first non-zero stock
#         detection. Prevents false flashing at game start.
#
# v1.3.0: Cleaned up empty-flash logic. Single _should_flash_empty()
#         checks both pool empty AND active automation consuming it
#         (via gc.rates). Removed duplicate drain check and broken
#         class-level drain variable. No behaviour change.
#
# v1.2.0: Bar is a manual-click throttle only. Starts full, resets
#         on successful manual action, refills over timer interval.
#
# Set resource_key and operation_key in the Inspector.
#
# resource_key:  matches GameData.RESOURCES key (e.g. "sparks")
#                drives accent color and empty-pool blink
# operation_key: matches ProductionManager timer name
#                (e.g. "sparks_summon") -- used for wait_time only
#
# Call notify_clicked() from RootUI after a successful manual action.
# Call flash_not_ready() from RootUI when player clicks too early.

# ===================== EXPORTS ====================
@export var resource_key:  String = ""
@export var operation_key: String = ""

# ===================== TUNING ====================
const BAR_HEIGHT:           float = 6.0
const FLASH_NOT_READY_TIME: float = 0.25
const EMPTY_FLASH_SPEED:    float = 4.0

# ===================== NODE REFS =================
@onready var _progress_bar: ProgressBar = $ProgressBar

# ===================== AUTOLOAD REFS =============
var _gc: Node = null
var _pm: Node = null
var _gd: Node = null

# ===================== STATE =====================
var _elapsed:              float = 0.0
var _interval:             float = 1.0
var _time:                 float = 0.0
var _not_ready_flash_t:    float = 0.0
var _base_color:           Color = Color.WHITE
var _is_ready:             bool  = true
var _has_ever_produced:    bool  = false


func _ready() -> void:
    _gc = get_node_or_null("/root/GameContext")
    _pm = get_node_or_null("/root/ProductionManager")
    _gd = get_node_or_null("/root/GameData")
    _setup_bar()
    _refresh_color()
    _find_timer()
    _elapsed  = _interval
    _is_ready = true
    if _progress_bar:
        _progress_bar.value = 100.0


func _setup_bar() -> void:
    custom_minimum_size         = Vector2(0, BAR_HEIGHT)
    size_flags_horizontal       = Control.SIZE_EXPAND_FILL
    if not _progress_bar:
        push_warning("CooldownBar: ProgressBar child not found on " + resource_key)
        return
    _progress_bar.min_value             = 0.0
    _progress_bar.max_value             = 100.0
    _progress_bar.value                 = 100.0
    _progress_bar.show_percentage       = false
    _progress_bar.custom_minimum_size   = Vector2(0, BAR_HEIGHT)
    _progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _refresh_color() -> void:
    if not _gd or resource_key == "":
        return
    _base_color = Color.from_string(
        _gd.RESOURCES.get(resource_key, {}).get("color", "#ffffff"),
        Color.WHITE)


func _find_timer() -> void:
    if not _pm or operation_key == "":
        _interval = 1.0
        return
    var intervals: Dictionary = _pm.get_timer_intervals()
    if not intervals.has(operation_key):
        _interval = 1.0
        push_warning("CooldownBar: unknown operation_key '%s' -- defaulting to 1.0s" % operation_key)
        return
    _interval = intervals[operation_key]


func notify_clicked() -> void:
    _elapsed  = 0.0
    _is_ready = false


func flash_not_ready() -> void:
    _not_ready_flash_t = FLASH_NOT_READY_TIME


func is_ready() -> bool:
    return _is_ready


func _process(delta: float) -> void:
    if not _progress_bar:
        return
    _time += delta

    # Update ever-produced flag once stock is detected
    if not _has_ever_produced:
        _has_ever_produced = _check_has_stock()

    if not _is_ready:
        _elapsed += delta
        if _elapsed >= _interval:
            _elapsed  = _interval
            _is_ready = true
    
    # Re-check interval every 2 seconds in case constellation state changed
    if int(_time) % 2 == 0 and fmod(_time, 2.0) < delta:
        _find_timer()

    var progress = clamp(_elapsed / _interval, 0.0, 1.0)
    _progress_bar.value = progress * 100.0

    var display_color = _base_color
    if _not_ready_flash_t > 0.0:
        _not_ready_flash_t -= delta
        var t = clamp(_not_ready_flash_t / FLASH_NOT_READY_TIME, 0.0, 1.0)
        display_color = _base_color.lerp(Color.WHITE, t)
    elif _is_ready and _should_flash_empty():
        var pulse = sin(_time * EMPTY_FLASH_SPEED * TAU) * 0.5 + 0.5
        display_color = Color.RED.lerp(Color.WHITE, pulse * 0.5)

    _progress_bar.add_theme_stylebox_override("fill",       _make_fill_style(display_color))
    _progress_bar.add_theme_stylebox_override("background", _make_bg_style())


func _check_has_stock() -> bool:
    # Returns true once the resource has non-zero stock for the first time.
    if not _gc or resource_key == "":
        return false
    match resource_key:
        "sparks":   return not _gc.sparks.is_zero()
        "monad":    return not _gc.get_monad_total().is_zero()
        "tetrad":   return not _gc.get_tetrad_total().is_zero()
        "particle":    return not _gc.particle.is_zero()
        "iota_uonite": return not _gc.iota_uonite.is_zero()
        "mote_uonite": return not _gc.mote_uonite.is_zero()
        "grain":    return not _gc.grain.is_zero()
        "uonite":   return not _gc.uonite.is_zero()
    return false


func _should_flash_empty() -> bool:
    # Requires: workers assigned AND produced at least once AND pool now empty.
    if not _gc or not _pm or resource_key == "" or operation_key == "":
        return false
    if not _has_ever_produced:
        return false

    var assigned    = _gc.get_operation_total_bignum(operation_key)
    var actual_rate = BigNum.zero()
    if _gc.rates.has(operation_key):
        actual_rate = _gc.rates[operation_key]

    # Workers assigned but producing nothing — always flash
    if not assigned.is_zero() and actual_rate.is_zero():
        return true

    # Workers assigned and pool empty — flash
    if not assigned.is_zero() and _check_has_stock() == false:
        return true

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
    s.border_color               = Color(UIAccentColors.CREAM, 0.35)
    s.border_width_left          = 1
    s.border_width_right         = 1
    s.border_width_top           = 1
    s.border_width_bottom        = 1
    s.corner_radius_top_left     = 2
    s.corner_radius_top_right    = 2
    s.corner_radius_bottom_left  = 2
    s.corner_radius_bottom_right = 2
    return s
