# carousel.gd - Robust reposition-based seamless loop
extends Control
# Three cards show at a time (author, 2026-11-04), and the arrow buttons below
# step the row one card left or right, gliding there. Click-and-drag scrolling
# was replaced: it stayed too finicky through several attempts. The loop is
# seamless both ways.

var panels: Array[Panel] = []
var current_offset: float = 0.0
## Where the row is gliding to; each arrow click moves it one card.
var target_offset: float = 0.0

# Panel count for the seamless reposition-based loop — create_panels()'s
# range and _process()'s reposition loop both need this in sync, or the loop
# stops being seamless.
const PANEL_COUNT: int = 18
## Cards showing at a time.
const VISIBLE: int = 3
## How quickly the row glides to its target (per second, as a lerp rate).
const GLIDE_RATE: float = 10.0
## Space between the outer cards and the panel's edges.
const SIDE_PAD: float = 10.0
const ARROW_COLOR := Color(0.85, 0.85, 0.95)

@export var panel_width: float = 120.0
@export var panel_height: float = 160.0
@export var panel_spacing: float = 26.0


func _ready() -> void:
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    # Exactly VISIBLE cards wide (FirmamentUI's CarouselPanel fits it). Cards
    # wrap round just past both edges, so clip them to the carousel.
    custom_minimum_size = Vector2(visible_width(), 200)
    clip_contents = true
    mouse_filter = Control.MOUSE_FILTER_IGNORE

    create_panels()
    # The arrows sit below the panel holding this, in CarouselArrows.
    var arrows: Node = get_parent().get_parent().get_node_or_null("CarouselArrows")
    if arrows:
        _setup_arrow(arrows.get_node_or_null("LeftArrowButton"), -1)
        _setup_arrow(arrows.get_node_or_null("RightArrowButton"), 1)


func visible_width() -> float:
    return VISIBLE * panel_width + (VISIBLE - 1) * panel_spacing + 2.0 * SIDE_PAD


func create_panels() -> void:
    for i in PANEL_COUNT:
        var panel = Panel.new()
        panel.custom_minimum_size = Vector2(panel_width, panel_height)
        panel.size = Vector2(panel_width, panel_height)
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

        var style = StyleBoxFlat.new()
        style.bg_color = Color(0.0, 0.0, 0.0, 0.12)
        style.border_width_left = 5
        style.border_width_right = 5
        style.border_width_top = 5
        style.border_width_bottom = 5
        style.corner_radius_top_left = 10
        style.corner_radius_top_right = 10
        style.corner_radius_bottom_left = 10
        style.corner_radius_bottom_right = 10

        @warning_ignore("integer_division")  # six cards per colour
        var cat = int(i / 6)
        var base_col: Color = Color(0.95, 0.22, 0.22) if cat == 0 else \
                             Color(0.25, 0.6, 1.0) if cat == 1 else Color(1.0, 0.9, 0.2)

        style.border_color = base_col
        panel.add_theme_stylebox_override("panel", style)
        add_child(panel)
        panels.append(panel)


## Moves the row one card: dir 1 brings in the next card from the right, -1
## the previous one from the left.
func step(dir: int) -> void:
    target_offset -= dir * (panel_width + panel_spacing)


func _process(delta: float) -> void:
    if size.x < 100:
        return

    current_offset = lerpf(current_offset, target_offset, minf(1.0, GLIDE_RATE * delta))
    if absf(current_offset - target_offset) < 0.5:
        current_offset = target_offset
    # Keep both in one loop's length of zero, shifted together, so they never grow.
    var segment: float = panel_width + panel_spacing
    var loop: float = segment * PANEL_COUNT
    if absf(target_offset) > loop:
        var shift: float = loop * signf(target_offset)
        target_offset -= shift
        current_offset -= shift

    # Each card sits at its place in the loop, wrapped so the row is seamless.
    for i in PANEL_COUNT:
        panels[i].position.x = fposmod(current_offset + i * segment + segment, loop) - segment + SIDE_PAD
        panels[i].position.y = (size.y - panel_height) / 2.0


## Wires an arrow button and draws its triangle (the game's font has no arrow
## glyphs, so they aren't text).
func _setup_arrow(btn: Button, dir: int) -> void:
    if btn == null:
        return
    btn.pressed.connect(step.bind(dir))
    btn.draw.connect(func() -> void:
        var c: Vector2 = btn.size * 0.5
        var w: float = minf(btn.size.y * 0.32, 10.0)
        var pts := PackedVector2Array([
            c + Vector2(w * dir, 0.0),
            c + Vector2(-w * dir, -w),
            c + Vector2(-w * dir, w)])
        btn.draw_colored_polygon(pts, ARROW_COLOR))
