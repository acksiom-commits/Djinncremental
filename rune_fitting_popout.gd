extends Control
# ================= RUNE FITTING POPOUT v1.0.0 =================
# Firmament (2026-11-02): fits Runes onto a tool's or device's inscription
# board. The board (rune_board.gd) sits in the middle and every Beginner Rune
# in a column on the right, grouped by Sigil. A Rune too large for the board
# in any turn is greyed and can't be picked up.
#
# Click and drag has misbehaved in this project, so Runes move by clicks
# (author, 2026-11-02): a left click on a Rune in the column puts a copy of it
# on the pointer, a right click turns the held Rune a sixth clockwise, and a
# left click on the board drops it there. Clicking a placed Rune picks it back
# up, still turned. Esc lets go of the held Rune (one lifted off the board is
# then gone); with nothing held, Esc closes the panel.
#
# Nothing is saved: the board empties when the panel closes. Tools and devices
# don't exist yet, so firmament_ui.gd opens this from a placeholder button.

const Board = preload("res://rune_board.gd")

const PANEL_SIZE := Vector2(1000, 620)
const LIST_WIDTH: float = 330.0
## Largest board cell, centre to corner.
const MAX_CELL: float = 80.0
const ENTRY_HEIGHT: float = 64.0
const ENTRY_SHAPE := Vector2(84, 52)
## Gap left between neighbouring cells, as a share of a cell.
const CELL_SHRINK: float = 0.93

const BACKDROP   := Color(0.0, 0.0, 0.0, 0.55)
const PANEL_BG   := Color(0.07, 0.07, 0.13, 0.97)
const PANEL_EDGE := Color(0.45, 0.42, 0.7)
const CELL_FILL  := Color(0.15, 0.15, 0.25)
const CELL_EDGE  := Color(0.36, 0.36, 0.54)
const FITS_TINT  := Color(0.35, 0.9, 0.5)
const BLOCK_TINT := Color(0.95, 0.35, 0.35)
const STAR_COLOR := Color(1.0, 0.97, 0.88)
const TEXT_COLOR := Color(0.9, 0.9, 0.95)
const DIM_COLOR  := Color(0.6, 0.6, 0.7)
const HOVER_BG   := Color(1.0, 1.0, 1.0, 0.06)
## Each Sigil's Runes, by constellation id.
const SIGIL_COLORS := {
    0: Color(0.95, 0.8, 0.35),   # The Archon
    1: Color(1.0, 0.55, 0.25),   # The Spark
    2: Color(0.4, 0.85, 0.95),   # The Hourglass
    3: Color(0.8, 0.8, 0.8),     # The Bellows (no Runes)
    4: Color(0.75, 0.5, 0.95),   # The Phial
    5: Color(0.5, 0.85, 0.45),   # The Satchel
    6: Color(0.95, 0.5, 0.7),    # The Djinn, as the player's Vessel
}
const CONSTELLATION_IDS := [0, 1, 2, 3, 4, 5, 6]
const HINT := "Left-click a Rune to pick it up.  Right-click turns it a sixth clockwise.  " \
    + "Left-click the board to place it, or a placed Rune to pick it back up.  Esc lets go."

## Rings of cells around the centre: 1 is the basic 7-cell board.
@export var board_radius: int = 1

var board = null
## The Rune on the pointer: {"rune", "color", "anchor", "sixths"}; {} when none.
var held: Dictionary = {}

## One per Rune in the column: {"rune", "color", "fits", "node"}.
var _entries: Array = []
var _hover_entry: int = -1
## Where the pointer is, in viewport coordinates, from the last mouse event.
var _pointer := Vector2.ZERO
var _board_view: Control = null
var _held_view: Control = null
var _used_label: Label = null


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    visible = false
    board = Board.new(board_radius)

    var backdrop := ColorRect.new()
    backdrop.color = BACKDROP
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(backdrop)

    var panel := PanelContainer.new()
    var style := StyleBoxFlat.new()
    style.bg_color = PANEL_BG
    style.border_color = PANEL_EDGE
    style.set_border_width_all(2)
    style.set_corner_radius_all(8)
    style.set_content_margin_all(14)
    panel.add_theme_stylebox_override("panel", style)
    panel.set_anchors_preset(Control.PRESET_CENTER)
    panel.offset_left = -PANEL_SIZE.x * 0.5
    panel.offset_right = PANEL_SIZE.x * 0.5
    panel.offset_top = -PANEL_SIZE.y * 0.5
    panel.offset_bottom = PANEL_SIZE.y * 0.5
    add_child(panel)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 10)
    panel.add_child(vbox)

    var header := HBoxContainer.new()
    vbox.add_child(header)
    var title := Label.new()
    title.text = "Inscribe Runes"
    title.add_theme_font_size_override("font_size", 22)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title)
    var close_btn := Button.new()
    close_btn.text = "Close"
    close_btn.pressed.connect(close)
    header.add_child(close_btn)

    var body := HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 12)
    vbox.add_child(body)

    _board_view = Control.new()
    _board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _board_view.mouse_filter = Control.MOUSE_FILTER_STOP
    _board_view.draw.connect(_draw_board)
    _board_view.gui_input.connect(_on_board_input)
    body.add_child(_board_view)

    body.add_child(VSeparator.new())

    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    body.add_child(scroll)
    var list := VBoxContainer.new()
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.add_theme_constant_override("separation", 2)
    scroll.add_child(list)
    _build_list(list)

    var footer := HBoxContainer.new()
    vbox.add_child(footer)
    var hint := Label.new()
    hint.text = HINT
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hint.add_theme_color_override("font_color", DIM_COLOR)
    hint.add_theme_font_size_override("font_size", 14)
    footer.add_child(hint)
    _used_label = Label.new()
    footer.add_child(_used_label)

    # Drawn over everything else, never in the way of a click.
    _held_view = Control.new()
    _held_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _held_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _held_view.draw.connect(_draw_held)
    add_child(_held_view)

    _refresh()


func open() -> void:
    board.clear()
    held = {}
    visible = true
    _pointer = get_viewport().get_mouse_position()
    _refresh()


func close() -> void:
    board.clear()
    held = {}
    visible = false


func _input(event: InputEvent) -> void:
    if not is_visible_in_tree():
        return
    if event is InputEventMouse:
        _pointer = event.position
    if event is InputEventMouseButton and event.pressed \
            and event.button_index == MOUSE_BUTTON_RIGHT:
        if not held.is_empty():
            held["sixths"] = (int(held["sixths"]) + 1) % 6
            _held_view.queue_redraw()
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseMotion:
        if not held.is_empty():
            _held_view.queue_redraw()
    elif event.is_action_pressed("ui_cancel"):
        if held.is_empty():
            close()
        else:
            held = {}
            _refresh()
        get_viewport().set_input_as_handled()


func _build_list(list: VBoxContainer) -> void:
    var cd: Node = get_node_or_null("/root/ConstellationData")
    if cd == null:
        return
    for cid in CONSTELLATION_IDS:
        var def: Dictionary = cd.get_constellation_def(cid)
        var layout = def.get("easy_layout")
        if not (layout is Dictionary) or not (layout.get("runes") is Array) \
                or (layout["runes"] as Array).is_empty():
            continue
        var color: Color = SIGIL_COLORS.get(cid, TEXT_COLOR)
        var heading := Label.new()
        heading.text = str(def.get("name", "?"))
        heading.add_theme_color_override("font_color", color)
        list.add_child(heading)
        for rune in layout["runes"]:
            var node := Control.new()
            node.custom_minimum_size = Vector2(0, ENTRY_HEIGHT)
            node.mouse_filter = Control.MOUSE_FILTER_STOP
            var i: int = _entries.size()
            var fits: bool = board.fits_empty(rune)
            _entries.append({"rune": rune, "color": color, "fits": fits, "node": node})
            node.draw.connect(_draw_entry.bind(i))
            node.gui_input.connect(_on_entry_input.bind(i))
            node.mouse_entered.connect(_on_entry_hover.bind(i, true))
            node.mouse_exited.connect(_on_entry_hover.bind(i, false))
            if fits:
                node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
            else:
                node.modulate.a = 0.4
                node.tooltip_text = "Too large for this board"
            list.add_child(node)


func _refresh() -> void:
    if _used_label:
        _used_label.text = "Cells used: %d / %d" % [board.used_count(), board.cells.size()]
    if _board_view:
        _board_view.queue_redraw()
    if _held_view:
        _held_view.queue_redraw()
    for e in _entries:
        (e["node"] as Control).queue_redraw()


# ---------------------------------------------------------------- the board

## Board cell size that fits the whole board in its view.
func _cell_size() -> float:
    var reach := Vector2.ZERO
    for c in board.cells:
        var p: Vector2 = Board.cell_point(c, 1.0)
        reach = Vector2(maxf(reach.x, absf(p.x)), maxf(reach.y, absf(p.y)))
    reach += Vector2(Board.SQRT3 * 0.5, 1.0)
    var room: Vector2 = _board_view.size * 0.45
    return minf(MAX_CELL, minf(room.x / reach.x, room.y / reach.y))


func _board_origin() -> Vector2:
    return _board_view.size * 0.5


func _pointer_in(node: Control) -> Vector2:
    return node.get_global_transform_with_canvas().affine_inverse() * _pointer


## The board cell under the pointer, or null off the board.
func _cell_under_pointer():
    var local: Vector2 = _pointer_in(_board_view)
    if not Rect2(Vector2.ZERO, _board_view.size).has_point(local):
        return null
    var c: Vector2i = Board.point_cell(local - _board_origin(), _cell_size())
    return c if board.cells.has(c) else null


func _on_board_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton and event.pressed
            and event.button_index == MOUSE_BUTTON_LEFT):
        return
    var at = _cell_under_pointer()
    if at == null:
        return
    if held.is_empty():
        var lifted: Dictionary = board.take(at)
        if not lifted.is_empty():
            held = {"rune": lifted["rune"], "color": lifted["color"],
                "anchor": lifted["anchor"], "sixths": lifted["sixths"]}
    else:
        var idx: int = board.place(held["rune"], held["anchor"], int(held["sixths"]), at)
        if idx >= 0:
            board.placed[idx]["color"] = held["color"]
            held = {}
    _board_view.accept_event()
    _refresh()


func _draw_board() -> void:
    var size: float = _cell_size()
    var origin: Vector2 = _board_origin()
    for c in board.cells:
        var outline: PackedVector2Array = Board.cell_outline(c, size, origin, CELL_SHRINK)
        _board_view.draw_colored_polygon(outline, CELL_FILL)
        outline.append(outline[0])
        _board_view.draw_polyline(outline, CELL_EDGE, 1.5, true)
    for p in board.placed:
        _draw_rune(_board_view, p["rune"], p["anchor"], int(p["sixths"]),
            origin + Board.cell_point(p["at"], size), size, p["color"], p["color"])


## The held Rune: snapped to the cell under the pointer on the board, green
## where it fits and red where it doesn't; following the pointer elsewhere.
func _draw_held() -> void:
    if held.is_empty():
        return
    var size: float = _cell_size()
    var at = _cell_under_pointer()
    if at == null:
        _draw_rune(_held_view, held["rune"], held["anchor"], int(held["sixths"]),
            _pointer_in(_held_view), size, held["color"], held["color"], 0.22)
        return
    var tint: Color = FITS_TINT if board.can_place(held["rune"], held["anchor"], int(held["sixths"]), at) \
        else BLOCK_TINT
    var origin: Vector2 = _board_view.global_position - _held_view.global_position \
        + _board_origin() + Board.cell_point(at, size)
    _draw_rune(_held_view, held["rune"], held["anchor"], int(held["sixths"]), origin, size,
        tint, held["color"], 0.4)


## Draws a Rune on `canvas` with its `anchor` cell centred on `origin`, turned
## `sixths` clockwise: its cells filled in `fill`, its lines and stars over them.
func _draw_rune(canvas: Control, rune: Dictionary, anchor: Vector2i, sixths: int, origin: Vector2,
        size: float, fill: Color, line: Color, fill_alpha: float = 0.3) -> void:
    for c in Board.held_cells(rune, anchor, sixths):
        canvas.draw_colored_polygon(Board.cell_outline(c, size, origin, CELL_SHRINK),
            Color(fill, fill_alpha))
    var stars: Dictionary = Board.held_stars(rune, anchor, sixths)
    var flat: Array = rune.get("lines", [])
    var width: float = maxf(1.5, size * 0.09)
    for i in range(0, flat.size() - 1, 2):
        canvas.draw_line(origin + Board.cell_point(stars[int(flat[i])], size),
            origin + Board.cell_point(stars[int(flat[i + 1])], size), line, width, true)
    for s in stars:
        canvas.draw_circle(origin + Board.cell_point(stars[s], size), maxf(2.0, size * 0.16), STAR_COLOR)


# ---------------------------------------------------------------- the column

func _on_entry_input(event: InputEvent, i: int) -> void:
    if not (event is InputEventMouseButton and event.pressed
            and event.button_index == MOUSE_BUTTON_LEFT):
        return
    var e: Dictionary = _entries[i]
    if bool(e["fits"]):
        held = {"rune": e["rune"], "color": e["color"],
            "anchor": Board.middle_cell(e["rune"]), "sixths": 0}
        _refresh()
    (e["node"] as Control).accept_event()


func _on_entry_hover(i: int, inside: bool) -> void:
    if inside:
        _hover_entry = i
    elif _hover_entry == i:
        _hover_entry = -1
    (_entries[i]["node"] as Control).queue_redraw()


func _draw_entry(i: int) -> void:
    var e: Dictionary = _entries[i]
    var node: Control = e["node"]
    var rune: Dictionary = e["rune"]
    var color: Color = e["color"]
    var is_held: bool = not held.is_empty() and str(held["rune"].get("name")) == str(rune.get("name"))
    if is_held:
        node.draw_rect(Rect2(Vector2.ZERO, node.size), Color(color, 0.14))
        node.draw_rect(Rect2(Vector2.ONE, node.size - Vector2(2, 2)), Color(color, 0.8), false, 1.5)
    elif _hover_entry == i and bool(e["fits"]):
        node.draw_rect(Rect2(Vector2.ZERO, node.size), HOVER_BG)

    # The shape, scaled into a box at the left.
    var cells: Array[Vector2i] = Board.rune_cells(rune)
    var lo := Vector2(INF, INF)
    var hi := Vector2(-INF, -INF)
    for c in cells:
        var p: Vector2 = Board.cell_point(c, 1.0)
        lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
        hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
    lo -= Vector2(Board.SQRT3 * 0.5, 1.0)
    hi += Vector2(Board.SQRT3 * 0.5, 1.0)
    var size: float = minf(ENTRY_SHAPE.x / (hi.x - lo.x), ENTRY_SHAPE.y / (hi.y - lo.y))
    var box_centre := Vector2(6.0 + ENTRY_SHAPE.x * 0.5, node.size.y * 0.5)
    var origin: Vector2 = box_centre - (lo + hi) * 0.5 * size
    _draw_rune(node, rune, Vector2i.ZERO, 0, origin, size, color, color, 0.3)

    var font: Font = get_theme_default_font()
    var fsize: int = get_theme_default_font_size()
    var x: float = ENTRY_SHAPE.x + 16.0
    var width: float = node.size.x - x - 4.0
    var name_text: String = str(rune.get("name", "?"))
    # Long names step down a size or two rather than being cut off.
    var name_size: int = fsize - 2
    while name_size > 11 and font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > width:
        name_size -= 1
    node.draw_string(font, Vector2(x, node.size.y * 0.5 - 4.0), name_text,
        HORIZONTAL_ALIGNMENT_LEFT, width, name_size, TEXT_COLOR)
    var sub: String = "%d cells" % cells.size()
    if not bool(e["fits"]):
        sub += " - too large"
    node.draw_string(font, Vector2(x, node.size.y * 0.5 + 16.0), sub,
        HORIZONTAL_ALIGNMENT_LEFT, width, fsize - 5, DIM_COLOR)
