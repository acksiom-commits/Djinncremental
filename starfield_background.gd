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

# Constellation snap
const SNAP_PULL_STRENGTH: float = 4.0   # angular velocity scale while snapping
const SNAP_PULL_RAMP:     float = 3.0   # how quickly snap blend reaches full strength

# ==================================================
# STATE
# ==================================================
var _time: float = 0.0

#   var _yaw:       float = 0.0
#   var _pitch:     float = 0.0
var _vel_yaw:   float = 0.0
var _vel_pitch: float = 0.0

var _mouse_idle_time: float = 0.0

var _has_constellation_target: bool = false
var _target_yaw:   float = 0.0
var _target_pitch: float = 0.0
var _pull_blend:   float = 0.0

var _snap_active:     bool    = false
var _snap_target_dir: Vector3 = Vector3.ZERO
var _snap_target_basis: Basis = Basis.IDENTITY
var _snap_blend:      float   = 0.0
var _snap_draw_offset_px: Vector2 = Vector2.ZERO

var _game_context: Node = null

var _cd:                   Node  = null
var _current_combined_rot: Basis = Basis.IDENTITY

# Auto-rotation speed — matches the removed shader default (0.025 * 0.12)
const AUTO_ROT_SPEED:    float = 0.003

#   var _auto_rot_angle:     float = 0.0
var _rotation_locked:    bool  = false
var _user_locked:        bool  = false

func _ready() -> void:
    _game_context = get_node_or_null("/root/GameContext")
    _cd           = get_node_or_null("/root/ConstellationData")


# ==================================================
# PUBLIC API
# ==================================================
func set_constellation_target(yaw: float, pitch: float) -> void:
    _has_constellation_target = true
    _target_yaw   = yaw
    _target_pitch = pitch


func clear_constellation_target() -> void:
    _has_constellation_target = false
    _pull_blend      = 0.0
    _snap_active     = false
    _snap_blend      = 0.0
    _snap_draw_offset_px = Vector2.ZERO
    _rotation_locked = _user_locked
    if _user_locked:
        _vel_yaw   = 0.0
        _vel_pitch = 0.0


func snap_to_constellation(constellation_id: int, panel_center_px: Vector2) -> void:
    if not _cd:
        return
    var positions: Array = _cd.get_star_positions(constellation_id)
    if positions.is_empty():
        return

    # Store pixel offset so the overlay can shift drawn positions
    # from screen center to the panel center.
    var vp_size := get_viewport_rect().size
    _snap_draw_offset_px = panel_center_px - vp_size * 0.5

    # Shared with constellation_study_overlay.gd's map projection, so both
    # surfaces always settle on the same canonical orientation — see
    # get_canonical_display_basis() for the leveling + disambiguation logic.
    _snap_target_basis = _cd.get_canonical_display_basis(constellation_id)

    # Single target direction for convergence check (same forward the
    # basis maps (0,0,1) to, regardless of roll — rotating around Z
    # doesn't move points on the Z axis).
    _snap_target_dir = _snap_target_basis * Vector3(0.0, 0.0, 1.0)

    _snap_active     = true
    _snap_blend      = 0.0
    _vel_yaw         = 0.0
    _vel_pitch       = 0.0
    _pull_blend      = 0.0


# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
    _time += delta

    var mat = material as ShaderMaterial
    if not mat:
        return

    var vp_size: Vector2 = get_viewport_rect().size
    var sparks: float = 0.0
    if _game_context and not _game_context.sparks.is_zero():
        sparks = float(_game_context.sparks.to_int())
    mat.set_shader_parameter("spark_count",   sparks)
    mat.set_shader_parameter("time_offset",   _time)
    mat.set_shader_parameter("viewport_size", vp_size)

    # ── SNAP-TO-CONSTELLATION (single-phase full-basis) ──
    if _snap_active:
        var diff := _snap_target_basis * _current_combined_rot.inverse()
        var q := Quaternion(diff)
        var axis: Vector3 = q.get_axis()
        var angle: float = q.get_angle()
        if angle < 0.015 or axis.length_squared() < 0.0001:
            _snap_active     = false
            _vel_yaw         = 0.0
            _vel_pitch       = 0.0
            _rotation_locked = true
        else:
            _snap_blend = minf(_snap_blend + SNAP_PULL_RAMP * delta, 1.0)
            var rot_amount: float = angle * SNAP_PULL_STRENGTH * _snap_blend * delta
            rot_amount = minf(rot_amount, angle)
            _current_combined_rot = Basis(axis.normalized(), rot_amount) * _current_combined_rot
            _current_combined_rot = _current_combined_rot.orthonormalized()
    elif not _rotation_locked:
        var mouse_pos: Vector2   = get_viewport().get_mouse_position()
        var norm: Vector2        = (mouse_pos / vp_size) * 2.0 - Vector2.ONE
        var dist: float          = norm.length()
        var active_norm: Vector2 = Vector2.ZERO
        if dist > DEAD_ZONE:
            var remapped = (dist - DEAD_ZONE) / (1.0 - DEAD_ZONE)
            active_norm  = norm.normalized() * remapped

        var target_vel_yaw:   float =  active_norm.x * POSITION_SCALE
        var target_vel_pitch: float = -active_norm.y * POSITION_SCALE
        _vel_yaw   = lerp(_vel_yaw,   target_vel_yaw,   VELOCITY_SMOOTH * delta)
        _vel_pitch = lerp(_vel_pitch, target_vel_pitch, VELOCITY_SMOOTH * delta)

        if dist <= IDLE_THRESHOLD:
            _mouse_idle_time += delta
        else:
            _mouse_idle_time = 0.0
            _pull_blend      = 0.0

        if _has_constellation_target and _mouse_idle_time >= PULL_DELAY:
            var fwd: Vector3 = _current_combined_rot * Vector3(0.0, 0.0, 1.0)
            var current_yaw:   float = atan2(fwd.x, fwd.z)
            var current_pitch: float = asin(clamp(fwd.y, -1.0, 1.0))
            _pull_blend = min(_pull_blend + PULL_RAMP_SPEED * delta, 1.0)
            _vel_yaw   += _angle_diff(_target_yaw,   current_yaw)   * PULL_STRENGTH * _pull_blend * delta
            _vel_pitch += _angle_diff(_target_pitch, current_pitch) * PULL_STRENGTH * _pull_blend * delta

        var yaw_increment:   float = (_vel_yaw + AUTO_ROT_SPEED) * delta
        var pitch_increment: float = _vel_pitch * delta
        _current_combined_rot = _current_combined_rot * Basis(Vector3.UP, yaw_increment)
        _current_combined_rot = _current_combined_rot * Basis(Vector3.RIGHT, pitch_increment)
        _current_combined_rot = _current_combined_rot.orthonormalized()

    mat.set_shader_parameter("view_matrix", _current_combined_rot)


# ==================================================
# HELPER
# ==================================================
func _angle_diff(target: float, current: float) -> float:
    var d = fmod(target - current, TAU)
    if d > PI:   d -= TAU
    elif d < -PI: d += TAU
    return d
    
    
func get_effective_view_matrix() -> Basis:
    # Combined view_matrix * auto_rot — matches the full transform applied
    # in the shader so the overlay's projection stays in sync.
    return _current_combined_rot


func get_snap_draw_offset() -> Vector2:
    return _snap_draw_offset_px


func set_rotation_locked(locked: bool) -> void:
    _user_locked     = locked
    _rotation_locked = locked
    if locked:
        _vel_yaw   = 0.0
        _vel_pitch = 0.0
