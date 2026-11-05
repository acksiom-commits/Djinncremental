# carousel.gd - Robust reposition-based seamless loop
extends Control
# Three cards show at a time (author, 2026-11-04), and the arrow buttons below
# step the row one card left or right, gliding there. Click-and-drag scrolling
# was replaced: it stayed too finicky through several attempts. The loop is
# seamless both ways.
# Cards that hold a skill (GameData.SKILLS: Mold, Carve and Forge on red cards
# 0-2, Distill on blue card 6) show its name across the top (2026-11-04).

var panels: Array[Panel] = []
## GameData autoload: card colours and which skill each card holds.
var game_data: Node = null
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

    game_data = get_node_or_null("/root/GameData")
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

        # Six cards per colour, red then blue then yellow (GameData.CARD_COLORS).
        var base_col: Color = game_data.card_color(i) if game_data else Color.WHITE

        style.border_color = base_col
        panel.add_theme_stylebox_override("panel", style)
        _add_skill_label(panel, i, base_col)
        add_child(panel)
        panels.append(panel)


## Names the skill this card holds (GameData.SKILLS), if any, across its top.
func _add_skill_label(panel: Panel, card: int, col: Color) -> void:
    if game_data == null:
        return
    var skill: Dictionary = game_data.skill_on_card(card)
    if skill.is_empty():
        return
    var lbl := Label.new()
    lbl.name = "SkillLabel"
    lbl.text = String(skill["name"])
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    lbl.add_theme_color_override("font_color", col.lightened(0.35))
    lbl.add_theme_font_size_override("font_size", 16)
    lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    lbl.offset_top = 14.0
    lbl.offset_bottom = 38.0
    panel.add_child(lbl)


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
