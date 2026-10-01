extends Control
# ================= WILL / FORM MINI ICON =================
# Small flat 2-D icon shown at the far left/right of the Particle/Iota/Mote
# Assemble buttons (2026-10-01), reflecting which branch the WILL/FORM
# switch (will_form_switch.gd) currently has lit. Each button carries TWO
# of these, fixed to opposite sides -- a filled "faceted ball" standing in
# for the icosahedral Uonite lattice, permanently on the LEFT, and a filled
# triangle standing in for the tetrahedral Grain lattice, permanently on
# the RIGHT. They never swap places or shape; `side` alone decides which
# one this instance is. Only its VISIBILITY tracks the switch: the WILL/
# Uonite icon is visible while WILL is lit and fades out when FORM is
# selected, the FORM/Grain icon the mirror image of that. Purely cosmetic:
# reads GameContext.will_form_switch_is_will / will_form_switch_changed,
# writes nothing -- same scope as the switch button itself.
#
# "Rotate through the vertical axis to visibility/invisibility" is faked in
# flat 2-D by tweening scale.x toward 0 (edge-on, invisible) or back toward
# 1 (face-on, visible) -- a classic card-flip, applied here to a single
# fixed shape fading in/out rather than swapping between two shapes.
#
# Instance WillFormMiniIcon.tscn as a child of any Button, with `side` set
# to "left" or "right" -- it positions itself at that edge, vertically
# centered, same mouse_filter=IGNORE overlay pattern as ButtonLabel.tscn /
# WillFormSwitch.tscn so it never steals the button's own click.

const ICON_SIZE: float = 18.0
const EDGE_MARGIN: float = 3.0
const FLIP_DURATION: float = 0.35

@export var side: String = "left" # "left" = WILL/Uonite, "right" = FORM/Grain

var _uonite_color: Color = Color.WHITE
var _grain_color: Color = Color.WHITE
var _flip_tween: Tween = null


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    size = Vector2(ICON_SIZE, ICON_SIZE)
    pivot_offset = size * 0.5

    # Deliberately NOT using set_anchors_and_offsets_preset() here -- it
    # left both size AND the resulting offsets wrong in practice (confirmed
    # live: the icon rendered nothing, and a headless test caught the
    # right-side icon landing flush against the button's edge with no
    # inward margin at all). Anchors stay at their Control default (0,0),
    # so `position` is a plain absolute offset -- the same scheme
    # ButtonLabelInstance/WillLabel/FormLabel already use elsewhere in this
    # project (layout_mode=0, explicit offsets, no anchor math). The parent
    # Button's own size may not be finalized the instant this runs (it can
    # depend on an ancestor Container's layout pass), so position is
    # computed now AND re-computed on the parent's `resized` signal.
    var parent := get_parent()
    if parent is Control:
        parent.resized.connect(_reposition)
    _reposition()

    var game_data = get_node_or_null("/root/GameData")
    if game_data:
        _uonite_color = Color(game_data.RESOURCES.get("uonite", {}).get("color", "#ffffff"))
        _grain_color = Color(game_data.RESOURCES.get("grain", {}).get("color", "#ffffff"))

    var gc = get_node_or_null("/root/GameContext")
    if gc:
        scale.x = 1.0 if _should_show(gc.will_form_switch_is_will) else 0.0
        gc.connect("will_form_switch_changed", _on_switch_changed)

    queue_redraw()


## This instance's own icon is shown when the switch is on ITS side --
## WILL for the left/Uonite icon, FORM for the right/Grain icon.
func _should_show(is_will: bool) -> bool:
    return is_will if side == "left" else not is_will


func _reposition() -> void:
    var parent := get_parent()
    var parent_size: Vector2 = parent.size if parent is Control else Vector2(ICON_SIZE + EDGE_MARGIN * 2.0, ICON_SIZE)
    position.y = (parent_size.y - ICON_SIZE) * 0.5
    if side == "right":
        position.x = parent_size.x - EDGE_MARGIN - ICON_SIZE
    else:
        position.x = EDGE_MARGIN


func _on_switch_changed(is_will: bool) -> void:
    var target: float = 1.0 if _should_show(is_will) else 0.0
    if is_equal_approx(scale.x, target):
        return
    if _flip_tween and _flip_tween.is_valid():
        _flip_tween.kill()
    _flip_tween = create_tween()
    _flip_tween.tween_property(self, "scale:x", target, FLIP_DURATION)


func _draw() -> void:
    if side == "left":
        _draw_uonite_icon()
    else:
        _draw_grain_icon()


## Filled "faceted ball" standing in for the icosahedral Uonite lattice --
## a filled decagon with spokes to its own vertices suggesting many small
## triangular facets, the simplest flat 2-D read of "icosahedron" at icon
## scale.
func _draw_uonite_icon() -> void:
    const SIDES: int = 10
    var center: Vector2 = size * 0.5
    var radius: float = size.x * 0.5
    var points: PackedVector2Array = []
    for i in range(SIDES):
        var angle: float = TAU * float(i) / float(SIDES) - PI / 2.0
        points.append(center + Vector2(cos(angle), sin(angle)) * radius)
    draw_colored_polygon(points, _uonite_color)
    var spoke_color: Color = _uonite_color.darkened(0.35)
    for p in points:
        draw_line(center, p, spoke_color, 1.0)


## Filled triangle standing in for the tetrahedral Grain lattice -- three
## lines from the centroid to each corner suggest the three visible faces
## meeting at a shared vertex, the classic flat "tetrahedron" glyph.
func _draw_grain_icon() -> void:
    var radius: float = size.x * 0.5
    var center: Vector2 = size * 0.5
    var points: PackedVector2Array = []
    for i in range(3):
        var angle: float = TAU * float(i) / 3.0 - PI / 2.0
        points.append(center + Vector2(cos(angle), sin(angle)) * radius)
    draw_colored_polygon(points, _grain_color)
    var edge_color: Color = _grain_color.darkened(0.35)
    for p in points:
        draw_line(center, p, edge_color, 1.0)
