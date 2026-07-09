@tool
extends Control
class_name ConcaveNotch
## Draws a concave (inward-curving) corner at a tab/panel junction,
## plus an optional straight border continuation line.
##
## Position this Control so its origin sits exactly at the inside
## corner where the tab edge meets the panel edge.  Size it to
## cover the area the border continuation needs to fill.
##
##  Corner diagram — each type shows where the tab and panel are
##  relative to the corner, and which way the border continues:
##
##  TAB_RIGHT_PANEL_BELOW  (left-edge popout, tab on right of panel)
##      Tab bottom border runs RIGHT from the corner →
##      Panel right border runs DOWN from the corner ↓
##      Border continuation: vertical, downward
##
##  TAB_LEFT_PANEL_BELOW   (right-edge popout, tab on left of panel)
##      Tab bottom border runs LEFT from the corner ←
##      Panel left border runs DOWN from the corner ↓
##      Border continuation: vertical, downward
##
##  TAB_RIGHT_PANEL_ABOVE  (left-edge popout, tab below panel)
##      Tab top border runs RIGHT from the corner →
##      Panel right border runs UP from the corner ↑
##      Border continuation: vertical, upward
##
##  TAB_LEFT_PANEL_ABOVE   (right-edge popout, tab below panel)
##      Tab top border runs LEFT from the corner ←
##      Panel left border runs UP from the corner ↑
##      Border continuation: vertical, upward

enum Corner {
    TAB_RIGHT_PANEL_BELOW,
    TAB_LEFT_PANEL_BELOW,
    TAB_RIGHT_PANEL_ABOVE,
    TAB_LEFT_PANEL_ABOVE,
}

@export var corner_type := Corner.TAB_RIGHT_PANEL_BELOW
@export var radius: float = 6.0
@export var border_color: Color = Color(0.4, 0.28, 0.62, 0.9)
@export var border_width: float = 1.0
@export var draw_border_continuation: bool = true


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
    var r: float = radius
    var w: float = size.x
    var h: float = size.y
    var steps: int = 12

    var arc_points: PackedVector2Array = []
    var center: Vector2
    var border_from: Vector2
    var border_to: Vector2

    match corner_type:

        Corner.TAB_RIGHT_PANEL_BELOW:
            # Origin (0,0) is the inside corner.
            # Tab's bottom border goes RIGHT from (0,0).
            # Panel's right border goes DOWN from (0,0).
            # Arc center at (r, r), sweeps from (r,0) to (0,r).
            center = Vector2(r, r)
            for i in range(steps + 1):
                var t: float = float(i) / float(steps)
                var angle: float = (-PI / 2.0) - (PI / 2.0) * t
                arc_points.append(center + Vector2(cos(angle), sin(angle)) * r)
            border_from = Vector2(0.0, r)
            border_to = Vector2(0.0, h)

        Corner.TAB_LEFT_PANEL_BELOW:
            # Origin (0,0) is the inside corner.  Control extends LEFT and DOWN,
            # so place the Control so its TOP-RIGHT corner is at the junction.
            # Tab's bottom border goes LEFT from (w, 0).
            # Panel's left border goes DOWN from (w, 0).
            # Arc center at (w - r, r), sweeps from (w-r-r*cos, ...).
            center = Vector2(w - r, r)
            for i in range(steps + 1):
                var t: float = float(i) / float(steps)
                var angle: float = (-PI / 2.0) + (PI / 2.0) * t
                arc_points.append(center + Vector2(cos(angle), sin(angle)) * r)
            border_from = Vector2(w, r)
            border_to = Vector2(w, h)

        Corner.TAB_RIGHT_PANEL_ABOVE:
            # Origin at bottom-left.  Tab's top border goes RIGHT.
            # Panel's right border goes UP.
            center = Vector2(r, h - r)
            for i in range(steps + 1):
                var t: float = float(i) / float(steps)
                var angle: float = (PI / 2.0) + (PI / 2.0) * t
                arc_points.append(center + Vector2(cos(angle), sin(angle)) * r)
            border_from = Vector2(0.0, 0.0)
            border_to = Vector2(0.0, h - r)

        Corner.TAB_LEFT_PANEL_ABOVE:
            # Origin at bottom-right.  Tab's top border goes LEFT.
            # Panel's left border goes UP.
            center = Vector2(w - r, h - r)
            for i in range(steps + 1):
                var t: float = float(i) / float(steps)
                var angle: float = (PI / 2.0) - (PI / 2.0) * t
                arc_points.append(center + Vector2(cos(angle), sin(angle)) * r)
            border_from = Vector2(w, 0.0)
            border_to = Vector2(w, h - r)

    # Draw the concave arc
    if arc_points.size() > 1:
        draw_polyline(arc_points, border_color, border_width, true)

    # Draw the straight border continuation
    if draw_border_continuation and border_from.distance_to(border_to) > 0.5:
        draw_line(border_from, border_to, border_color, border_width, true)
