extends Control
# Border effects for one constellation selector button (ConstellationPopout).
#
#   gold border      a Parent Volition is assigned to this constellation
#   rotating arc     Foci are assigned: a brighter segment, about a quarter
#                    of the perimeter long, circling clockwise
#
# Both can show at once (gold border, with the arc drawn over it in a paler
# gold). This is a child Control of the Button with mouse_filter IGNORE, so it
# only paints; the button keeps every click. It redraws every frame only while
# the arc is on.

const GOLD          := Color(1.0, 0.85, 0.2, 0.95)
const GOLD_ARC      := Color(1.0, 0.96, 0.72, 1.0)
const NORMAL_BORDER := Color(0.3, 0.25, 0.45, 0.6)
const NORMAL_ARC    := Color(0.78, 0.70, 0.98, 0.95)
const ARC_FRACTION  := 0.25    # of the perimeter
const LAP_SECONDS   := 4.0
const ARC_STEPS     := 28
const LINE_W        := 2.0
const INSET         := 1.0

var parent_gold: bool = false
var foci_arc: bool = false

var _phase: float = 0.0   # 0..1 around the perimeter


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    # ConstellationPopout._set_subtree_mouse_filter() forces every Control in
    # its panel to STOP when the panel opens; this tag exempts the overlay.
    set_meta("paint_only", true)
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    set_process(false)


func set_effects(gold: bool, arc: bool) -> void:
    if gold == parent_gold and arc == foci_arc:
        return
    parent_gold = gold
    foci_arc = arc
    set_process(arc)
    queue_redraw()


func _process(delta: float) -> void:
    _phase = fmod(_phase + delta / LAP_SECONDS, 1.0)
    queue_redraw()


## Point at distance `t` (0..1 of the perimeter) around the inset rectangle,
## clockwise from the top-left corner.
func _perimeter_point(t: float) -> Vector2:
    var w: float = maxf(size.x - 2.0 * INSET, 1.0)
    var h: float = maxf(size.y - 2.0 * INSET, 1.0)
    var total: float = 2.0 * (w + h)
    var d: float = fposmod(t, 1.0) * total
    if d < w:
        return Vector2(INSET + d, INSET)
    d -= w
    if d < h:
        return Vector2(INSET + w, INSET + d)
    d -= h
    if d < w:
        return Vector2(INSET + w - d, INSET + h)
    d -= w
    return Vector2(INSET, INSET + h - d)


func _draw() -> void:
    if not parent_gold and not foci_arc:
        return
    if parent_gold:
        draw_rect(Rect2(Vector2(INSET, INSET), size - Vector2(2.0 * INSET, 2.0 * INSET)),
            GOLD, false, LINE_W)
    if foci_arc:
        var base: Color = GOLD_ARC if parent_gold else NORMAL_ARC
        # Soft ends: alpha follows a half-sine across the arc, so the segment
        # fades in at its tail and out at its head instead of ending abruptly.
        var prev: Vector2 = _perimeter_point(_phase)
        for i in range(1, ARC_STEPS + 1):
            var f: float = float(i) / float(ARC_STEPS)
            var p: Vector2 = _perimeter_point(_phase + f * ARC_FRACTION)
            var env: float = sin(PI * (f - 0.5 / float(ARC_STEPS)))
            var c := Color(base.r, base.g, base.b, base.a * clampf(env, 0.0, 1.0))
            draw_line(prev, p, c, LINE_W + 1.0)
            prev = p
