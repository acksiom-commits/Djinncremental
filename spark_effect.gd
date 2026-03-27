extends Node2D
# ================= SPARK EFFECT v0.1.0 =================
# One-shot visual effect: bright bloom at origin that fades,
# plus a single spark point that launches outward and fades.
# Instantiated by RootUI on Summon Spark press, added to
# CanvasLayer so it renders above all UI.
#
# Usage from RootUI:
#   var effect = SPARK_EFFECT.instantiate()
#   get_node("/root/Main/CanvasLayer").add_child(effect)
#   effect.launch(origin_position)
#
# The node queues itself free when the animation completes.

# === TUNING ===
const BLOOM_DURATION   : float = 0.35   # seconds bloom takes to fade
const BLOOM_MAX_RADIUS : float = 28.0   # peak bloom circle radius px
const BLOOM_COLOR      : Color = Color(1.00, 0.97, 0.80, 1.0)  # warm white

const SPARK_DURATION   : float = 1.4    # seconds spark travels
const SPARK_SPEED_MIN  : float = 180.0  # px/s initial minimum speed
const SPARK_SPEED_MAX  : float = 320.0  # px/s initial maximum speed
const SPARK_ACCEL      : float = 60.0   # px/s² acceleration outward
const SPARK_SIZE_START : float = 4.0    # radius of spark point at launch
const SPARK_SIZE_END   : float = 0.8    # radius at fade-out
const SPARK_COLOR      : Color = Color(1.00, 0.97, 0.80, 1.0)  # warm white

# === STATE ===
var _time: float = 0.0
var _alive: bool = false

var _bloom_origin: Vector2 = Vector2.ZERO
var _bloom_alpha: float = 0.0

var _spark_pos: Vector2 = Vector2.ZERO
var _spark_dir: Vector2 = Vector2.ZERO
var _spark_speed: float = 0.0
var _spark_alpha: float = 0.0
var _spark_size: float = 0.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


# ==================================================
# LAUNCH — call this after adding to scene tree
# ==================================================
func launch(origin: Vector2) -> void:
    _rng.randomize()
    _time = 0.0
    _alive = true

    _bloom_origin = origin
    _bloom_alpha = 1.0

    # Random launch direction (full 360°)
    var angle = _rng.randf() * TAU
    _spark_dir = Vector2(cos(angle), sin(angle))
    _spark_speed = _rng.randf_range(SPARK_SPEED_MIN, SPARK_SPEED_MAX)
    _spark_pos = origin
    _spark_alpha = 1.0
    _spark_size = SPARK_SIZE_START


# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
    if not _alive:
        return

    _time += delta

    # --- Bloom ---
    var bloom_t = clamp(_time / BLOOM_DURATION, 0.0, 1.0)
    # Bloom fades out using a smoothstep curve
    _bloom_alpha = 1.0 - smoothstep(0.0, 1.0, bloom_t)

    # --- Spark ---
    var spark_t = clamp(_time / SPARK_DURATION, 0.0, 1.0)
    # Accelerate outward
    _spark_speed += SPARK_ACCEL * delta
    _spark_pos += _spark_dir * _spark_speed * delta
    # Fade out using smoothstep, starts fading halfway through
    _spark_alpha = 1.0 - smoothstep(0.4, 1.0, spark_t)
    # Shrink as it travels
    _spark_size = lerp(SPARK_SIZE_START, SPARK_SIZE_END, spark_t)

    queue_redraw()

    # --- Done ---
    if _time >= SPARK_DURATION:
        queue_free()


# ==================================================
# DRAW
# ==================================================
func _draw() -> void:
    if not _alive:
        return

    # Bloom — soft outer glow ring then bright core
    if _bloom_alpha > 0.0:
        var bloom_t = clamp(_time / BLOOM_DURATION, 0.0, 1.0)
        # Radius expands quickly then contracts
        var radius = BLOOM_MAX_RADIUS * sin(bloom_t * PI)
        # Outer soft ring
        var outer_color = Color(BLOOM_COLOR.r, BLOOM_COLOR.g, BLOOM_COLOR.b,
            _bloom_alpha * 0.3)
        draw_circle(_bloom_origin, radius * 1.6, outer_color)
        # Inner bright core
        var inner_color = Color(BLOOM_COLOR.r, BLOOM_COLOR.g, BLOOM_COLOR.b,
            _bloom_alpha * 0.85)
        draw_circle(_bloom_origin, radius * 0.5, inner_color)

    # Spark point — small glowing dot
    if _spark_alpha > 0.0:
        # Outer soft halo
        var halo_color = Color(SPARK_COLOR.r, SPARK_COLOR.g, SPARK_COLOR.b,
            _spark_alpha * 0.35)
        draw_circle(_spark_pos, _spark_size * 2.2, halo_color)
        # Bright core
        var core_color = Color(SPARK_COLOR.r, SPARK_COLOR.g, SPARK_COLOR.b,
            _spark_alpha)
        draw_circle(_spark_pos, _spark_size, core_color)
