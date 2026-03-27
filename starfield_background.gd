extends ColorRect
# ================= STARFIELD BACKGROUND v1.5.0 =================
# Position-driven rotation — mouse distance from screen center
# drives continuous angular velocity. Holding mouse at screen
# edge keeps rotating indefinitely. Mouse at center = no push.
# Delta impulse removed — position IS the velocity driver.
#
# This gives the "spinning in space" feel where the player's
# viewpoint keeps moving as long as they hold the mouse away
# from center, and coasts to a stop when they return to center.
#
# Constellation pull: after PULL_DELAY seconds with mouse near
# center, viewpoint drifts toward active constellation angle.
#
# Public API:
#   set_constellation_target(yaw: float, pitch: float)
#   clear_constellation_target()

# ==================================================
# TUNING CONSTANTS
# ==================================================

# How strongly mouse position drives rotation speed.
# At screen edge (normalized distance 1.0), rotation speed
# will be POSITION_SCALE radians/second.
# 0.15 = slow and atmospheric. Increase for faster response.
const POSITION_SCALE   : float = 0.15

# Dead zone radius — mouse must be this far from center
# (normalized 0..1) before rotation starts.
# 0.05 = tiny dead zone to prevent drift from imprecise centering.
const DEAD_ZONE        : float = 0.05

# Smoothing for velocity changes — how quickly current velocity
# tracks the target velocity. Higher = snappier, lower = floatier.
# 4.0 gives a smooth but responsive feel.
const VELOCITY_SMOOTH  : float = 4.0

# Momentum decay when mouse is near center (normalized speed below
# dead zone). Keeps a gentle coast rather than instant stop.
const COAST_DECAY      : float = 0.85

# Constellation pull
const PULL_DELAY       : float = 8.0
const PULL_STRENGTH    : float = 0.003
const PULL_RAMP_SPEED  : float = 0.25

# How close to center (normalized) counts as "idle" for pull delay
const IDLE_THRESHOLD   : float = 0.08

# ==================================================
# STATE
# ==================================================
var _time: float = 0.0

var _yaw:       float = 0.0
var _pitch:     float = 0.0
var _vel_yaw:   float = 0.0
var _vel_pitch: float = 0.0

var _mouse_idle_time: float = 0.0

var _has_constellation_target: bool = false
var _target_yaw:   float = 0.0
var _target_pitch: float = 0.0
var _pull_blend:   float = 0.0

var _game_context: Node = null


func _ready() -> void:
    _game_context = get_node_or_null("/root/GameContext")


# ==================================================
# PUBLIC API
# ==================================================
func set_constellation_target(yaw: float, pitch: float) -> void:
    _has_constellation_target = true
    _target_yaw   = yaw
    _target_pitch = pitch


func clear_constellation_target() -> void:
    _has_constellation_target = false
    _pull_blend = 0.0


# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
    _time += delta

    var mat = material as ShaderMaterial
    if not mat:
        return

    var sparks: float = 0.0
    if _game_context and not _game_context.sparks.is_zero():
        sparks = float(_game_context.sparks.to_int())
    # print("spark_count being set to: ", sparks)
    mat.set_shader_parameter("spark_count", sparks)
    mat.set_shader_parameter("time_offset", _time)

    # --- Mouse position -> target velocity ---
    var viewport_size: Vector2 = get_viewport_rect().size
    var mouse_pos: Vector2     = get_viewport().get_mouse_position()

    # Normalize mouse to -1..1 with 0 at screen center
    var norm: Vector2 = (mouse_pos / viewport_size) * 2.0 - Vector2.ONE

    # Apply dead zone
    var dist: float = norm.length()
    var active_norm: Vector2 = Vector2.ZERO
    if dist > DEAD_ZONE:
        # Remap so dead zone edge = 0, screen edge = 1
        var remapped = (dist - DEAD_ZONE) / (1.0 - DEAD_ZONE)
        active_norm = norm.normalized() * remapped

    # Target velocity from position
    var target_vel_yaw:   float =  active_norm.x * POSITION_SCALE
    var target_vel_pitch: float = -active_norm.y * POSITION_SCALE

    # Smooth current velocity toward target
    _vel_yaw   = lerp(_vel_yaw,   target_vel_yaw,   VELOCITY_SMOOTH * delta)
    _vel_pitch = lerp(_vel_pitch, target_vel_pitch, VELOCITY_SMOOTH * delta)

    # Mouse idle tracking for constellation pull
    # "Idle" = mouse near center
    if dist <= IDLE_THRESHOLD:
        _mouse_idle_time += delta
    else:
        _mouse_idle_time = 0.0
        _pull_blend = 0.0

    # Constellation pull
    if _has_constellation_target and _mouse_idle_time >= PULL_DELAY:
        _pull_blend = min(_pull_blend + PULL_RAMP_SPEED * delta, 1.0)
        _vel_yaw   += _angle_diff(_target_yaw,   _yaw)   * PULL_STRENGTH * _pull_blend * delta
        _vel_pitch += _angle_diff(_target_pitch, _pitch) * PULL_STRENGTH * _pull_blend * delta

    # Accumulate freely — no clamp
    _yaw   += _vel_yaw   * delta
    _pitch += _vel_pitch * delta

    # Build rotation matrix
    var cy := cos(_yaw);   var sy := sin(_yaw)
    var cp := cos(_pitch); var sp := sin(_pitch)

    var rot := Basis(
        Vector3( cy,       0.0,  -sy),
        Vector3( sy * sp,  cp,    cy * sp),
        Vector3( sy * cp, -sp,    cy * cp)
    )

    mat.set_shader_parameter("view_matrix", rot)


# ==================================================
# HELPER
# ==================================================
func _angle_diff(target: float, current: float) -> float:
    var d = fmod(target - current, TAU)
    if d > PI:   d -= TAU
    elif d < -PI: d += TAU
    return d
