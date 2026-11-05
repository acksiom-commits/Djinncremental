extends Control
# ================= RUNE FITTING POPOUT v1.0.0 =================
# Firmament (2026-11-02): fits Runes onto a tool's or device's inscription
# board. The board (rune_board.gd) sits in the middle and every Beginner Rune
# in a column on the right, grouped by Sigil. A Rune needing more cells than
# the board has (7) is greyed and can't be picked up.
#
# Click and drag has misbehaved in this project, so Runes move by clicks
# (author, 2026-11-02): a left click on a Rune in the column puts a copy of it
# on the pointer, a right click turns the held Rune a sixth clockwise, and a
# left click on the board drops it there. Clicking a placed Rune picks it back
# up, still turned. Esc lets go of the held Rune (one lifted off the board is
# then gone); with nothing held, Esc closes the panel.
#
# The player builds the board (author, 2026-11-04): it opens empty, with its 7
# cells (the standard start, once a fixed hexagon) waiting in a column on the
# left. Cells move by the same clicks as Runes: click the column to take one,
# click the board's faint grid to set it (touching a placed cell), click a
# bare placed cell to take it back up (not under a Rune, and not if that
# would split the board). A Rune needs at most 7 cells to be usable. The two
# columns take turns: while a cell is held the Runes can't be picked, and
# while a Rune is held the cells can't.
#
# Stars are drawn in their constellation stars' colours (author, 2026-11-02),
# read from the constellation's Beginner puzzle; with no Beginner puzzle yet
# they are grey. Stars of the same colour may share a board cell, linking
# their Runes (rune_board.gd); the footer counts the linked Runes.
#
# Nothing is saved: the board empties when the panel closes. Tools and devices
# don't exist yet, so firmament_ui.gd opens this from a placeholder button,
# and on Primordial the Constellation slideout's Runes column opens it.
#
# Charging (design, not built; author 2026-11-02): Runes are charged with
# Quintessence typed Red, Yellow or Blue (reduced at an Oscillation from the
# Phlogiston of Monads, Particles and Motes). Each star of a Rune takes the
# colour the player's star-colour generation gave that star in the Rune's
# constellation (ConstellationData.get_puzzle_star_colors(); a Rune's "lines"
# name its constellation's star indices) and charges from Quintessence of
# that colour. Runes change shape with the highest level of their
# constellation's puzzle solved, starting at Beginner, so the stars and
# colours are those of that level's layout. A White star charges from every
# Quintessence, Tetrad, Iota and Grain Quintessence included. Those three
# charge either of their composite colours at 1/4 effectiveness: Tetrads Red or Yellow, Iotas Yellow or Blue,
# Grains Blue or Red. Colour-match efficiency and off-colour charging are
# both improvable. See SysDoc section 7.

const Board = preload("res://rune_board.gd")
## The constellation stars' own colours, by star colour index.
const STAR_COLORS_BY_IDX: Array = preload("res://star_color_palette.tres").by_idx

const PANEL_SIZE := Vector2(1000, 620)
const LIST_WIDTH: float = 330.0
## The cell column on the left.
const STOCK_WIDTH: float = 84.0
## Cells a board is built from: the old fixed hexagon's count.
const STANDARD_CELLS: int = 7
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
## The faint grid of places a cell can be set on.
const GRID_EDGE  := Color(0.36, 0.36, 0.54, 0.25)
const FITS_TINT  := Color(0.35, 0.9, 0.5)
const BLOCK_TINT := Color(0.95, 0.35, 0.35)
## A star whose colour isn't known yet (no Beginner puzzle for its constellation).
const UNKNOWN_STAR := Color(0.5, 0.5, 0.58)
const STAR_EDGE  := Color(0.05, 0.05, 0.1, 0.85)
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
const HINT := "Click a cell on the left, then the grid, to build the board.  " \
    + "Click a Rune to pick it up; right-click turns it.  Click the board to place.  Esc lets go."

## Rings of grid around the centre where cells can be set: 3 gives 37 places.
@export var area_radius: int = 3

var board = null
## The Rune on the pointer: {"rune", "color", "star_colors", "anchor", "sixths"};
## {} when none. "color" is its Sigil's, "star_colors" maps each star to its
## star_color_palette index (Board.NO_COLOUR when unknown).
var held: Dictionary = {}
## Whether a board cell is on the pointer. Never at the same time as a Rune.
var held_cell: bool = false
## Grid places a cell can be set on -> true.
var _area: Dictionary = {}
var _stock_view: Control = null
var _stock_hover: bool = false

## One per Rune in the column: {"rune", "cid", "color", "star_colors", "fits", "node"}.
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
    board = Board.new(0, false)
    for c in Board.hexagon(area_radius):
        _area[c] = true

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

    _stock_view = Control.new()
    _stock_view.custom_minimum_size = Vector2(STOCK_WIDTH, 0)
    _stock_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _stock_view.mouse_filter = Control.MOUSE_FILTER_STOP
    _stock_view.tooltip_text = "Board cells: click one, then the grid"
    _stock_view.draw.connect(_draw_stock)
    _stock_view.gui_input.connect(_on_stock_input)
    _stock_view.mouse_entered.connect(_set_stock_hover.bind(true))
    _stock_view.mouse_exited.connect(_set_stock_hover.bind(false))
    body.add_child(_stock_view)
    body.add_child(VSeparator.new())

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
    board.cells.clear()
    held = {}
    held_cell = false
    # Puzzles are generated and replaced while the game runs, so the colours
    # are read again each time the board opens.
    for e in _entries:
        e["star_colors"] = rune_star_colors(int(e["cid"]), e["rune"])
    visible = true
    _pointer = get_viewport().get_mouse_position()
    _refresh()


func close() -> void:
    board.clear()
    board.cells.clear()
    held = {}
    held_cell = false
    visible = false


## Cells still in the column: the standard count less those placed or held.
func cells_left() -> int:
    return STANDARD_CELLS - board.cells.size() - (1 if held_cell else 0)


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
        if not held.is_empty() or held_cell:
            _held_view.queue_redraw()
    elif event.is_action_pressed("ui_cancel"):
        if held_cell:
            held_cell = false   # back to the column
            _refresh()
        elif held.is_empty():
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
            # The player shapes the board, so a Rune is usable if its cells
            # don't outnumber the board's.
            var fits: bool = Board.rune_cells(rune).size() <= STANDARD_CELLS
            _entries.append({"rune": rune, "cid": cid, "color": color,
                "star_colors": rune_star_colors(cid, rune), "fits": fits, "node": node})
            node.draw.connect(_draw_entry.bind(i))
            node.gui_input.connect(_on_entry_input.bind(i))
            node.mouse_entered.connect(_on_entry_hover.bind(i, true))
            node.mouse_exited.connect(_on_entry_hover.bind(i, false))
            if fits:
                node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
            else:
                node.modulate.a = 0.4
                node.tooltip_text = "Needs more than the board's %d cells" % STANDARD_CELLS
            list.add_child(node)


func _refresh() -> void:
    if _used_label:
        var linked: int = 0
        for g in board.link_groups():
            linked += (g as Array).size()
        _used_label.text = "Cells placed: %d / %d    Used: %d" \
            % [board.cells.size(), STANDARD_CELLS, board.used_count()]
        if linked > 0:
            _used_label.text += "    Linked Runes: %d" % linked
    if _stock_view:
        # The columns take turns: holding a Rune shuts the cells, and back.
        _stock_view.modulate.a = 0.4 if not held.is_empty() else 1.0
        _stock_view.queue_redraw()
    for e in _entries:
        var usable: bool = bool(e["fits"]) and not held_cell
        (e["node"] as Control).modulate.a = 1.0 if usable else 0.4
    if _board_view:
        _board_view.queue_redraw()
    if _held_view:
        _held_view.queue_redraw()
    for e in _entries:
        (e["node"] as Control).queue_redraw()


# ---------------------------------------------------------------- the board

## Cell size that fits the whole grid of places in the board view.
func _cell_size() -> float:
    var reach := Vector2.ZERO
    for c in _area:
        var p: Vector2 = Board.cell_point(c, 1.0)
        reach = Vector2(maxf(reach.x, absf(p.x)), maxf(reach.y, absf(p.y)))
    reach += Vector2(Board.SQRT3 * 0.5, 1.0)
    var room: Vector2 = _board_view.size * 0.45
    return minf(MAX_CELL, minf(room.x / reach.x, room.y / reach.y))


func _board_origin() -> Vector2:
    return _board_view.size * 0.5


func _pointer_in(node: Control) -> Vector2:
    return node.get_global_transform_with_canvas().affine_inverse() * _pointer


## The grid place under the pointer (placed cell or not), or null off the grid.
func _cell_under_pointer():
    var local: Vector2 = _pointer_in(_board_view)
    if not Rect2(Vector2.ZERO, _board_view.size).has_point(local):
        return null
    var c: Vector2i = Board.point_cell(local - _board_origin(), _cell_size())
    if _area.has(c):
        return c
    return null


func _on_board_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton and event.pressed
            and event.button_index == MOUSE_BUTTON_LEFT):
        return
    var at = _cell_under_pointer()
    if at == null:
        return
    if held_cell:
        if board.add_cell(at, _area):
            held_cell = false
    elif held.is_empty():
        var lifted: Dictionary = board.take(at)
        if not lifted.is_empty():
            held = {"rune": lifted["rune"], "color": lifted["color"],
                "star_colors": lifted["star_colors"],
                "anchor": lifted["anchor"], "sixths": lifted["sixths"]}
        elif board.remove_cell(at):
            held_cell = true   # a bare cell, taken back up
    else:
        var idx: int = board.place(held["rune"], held["anchor"], int(held["sixths"]), at,
            held["star_colors"])
        if idx >= 0:
            board.placed[idx]["color"] = held["color"]
            held = {}
    _board_view.accept_event()
    _refresh()


func _draw_board() -> void:
    var cell_size: float = _cell_size()
    var origin: Vector2 = _board_origin()
    # The grid of places, faint, under the cells placed on it.
    for c in _area:
        if not board.cells.has(c):
            var place: PackedVector2Array = Board.cell_outline(c, cell_size, origin, CELL_SHRINK)
            place.append(place[0])
            _board_view.draw_polyline(place, GRID_EDGE, 1.0, true)
    for c in board.cells:
        var outline: PackedVector2Array = Board.cell_outline(c, cell_size, origin, CELL_SHRINK)
        _board_view.draw_colored_polygon(outline, CELL_FILL)
        outline.append(outline[0])
        _board_view.draw_polyline(outline, CELL_EDGE, 1.5, true)
    for p in board.placed:
        _draw_rune(_board_view, p["rune"], p["anchor"], int(p["sixths"]),
            origin + Board.cell_point(p["at"], cell_size), cell_size, p["color"], p["color"],
            p["star_colors"])


## The held Rune: snapped to the cell under the pointer on the board, green
## where it fits and red where it doesn't; following the pointer elsewhere.
func _draw_held() -> void:
    if held_cell:
        _draw_held_cell()
        return
    if held.is_empty():
        return
    var cell_size: float = _cell_size()
    var at = _cell_under_pointer()
    if at == null:
        _draw_rune(_held_view, held["rune"], held["anchor"], int(held["sixths"]),
            _pointer_in(_held_view), cell_size, held["color"], held["color"], held["star_colors"], 0.22)
        return
    var tint: Color = FITS_TINT if board.can_place(held["rune"], held["anchor"], int(held["sixths"]),
        at, held["star_colors"]) else BLOCK_TINT
    var origin: Vector2 = _board_view.global_position - _held_view.global_position \
        + _board_origin() + Board.cell_point(at, cell_size)
    _draw_rune(_held_view, held["rune"], held["anchor"], int(held["sixths"]), origin, cell_size,
        tint, held["color"], held["star_colors"], 0.4)


## The held board cell: snapped to the grid place under the pointer, green
## where it can go and red where it can't; following the pointer elsewhere.
func _draw_held_cell() -> void:
    var cell_size: float = _cell_size()
    var at = _cell_under_pointer()
    var centre: Vector2 = _pointer_in(_held_view)
    var tint: Color = CELL_EDGE
    if at != null:
        centre = _board_view.global_position - _held_view.global_position \
            + _board_origin() + Board.cell_point(at, cell_size)
        tint = FITS_TINT if board.can_add_cell(at, _area) else BLOCK_TINT
    var outline: PackedVector2Array = Board.cell_outline(Vector2i.ZERO, cell_size, centre, CELL_SHRINK)
    _held_view.draw_colored_polygon(outline, Color(CELL_FILL, 0.85))
    outline.append(outline[0])
    _held_view.draw_polyline(outline, tint, 2.0, true)


# ---------------------------------------------------------------- the cells

func _set_stock_hover(inside: bool) -> void:
    _stock_hover = inside
    _stock_view.queue_redraw()


## A click on the cell column takes a cell (when any are left and no Rune is
## held), or puts a held cell back.
func _on_stock_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton and event.pressed
            and event.button_index == MOUSE_BUTTON_LEFT):
        return
    if held_cell:
        held_cell = false
    elif held.is_empty() and cells_left() > 0:
        held_cell = true
    _stock_view.accept_event()
    _refresh()


## The cells still in the column, one above another from the top.
func _draw_stock() -> void:
    var font: Font = get_theme_default_font()
    var w: float = _stock_view.size.x
    _stock_view.draw_string(font, Vector2(0, 18), "Cells %d" % cells_left(),
        HORIZONTAL_ALIGNMENT_CENTER, w, 14, DIM_COLOR)
    if _stock_hover and held.is_empty() and (cells_left() > 0 or held_cell):
        _stock_view.draw_rect(Rect2(Vector2.ZERO, _stock_view.size), HOVER_BG)
    var size_px: float = minf(w * 0.32, (_stock_view.size.y - 30.0) / (STANDARD_CELLS * 1.75 + 0.25))
    for k in cells_left():
        var centre := Vector2(w * 0.5, 30.0 + size_px * (1.0 + 1.75 * k))
        var outline: PackedVector2Array = Board.cell_outline(Vector2i.ZERO, size_px, centre, CELL_SHRINK)
        _stock_view.draw_colored_polygon(outline, CELL_FILL)
        outline.append(outline[0])
        _stock_view.draw_polyline(outline, CELL_EDGE, 1.5, true)


## Each of the Rune's stars -> the colour index its constellation's Beginner
## puzzle gave that star, or Board.NO_COLOUR. A Rune's stars are its Beginner
## layout's, so a cached puzzle counts only when its star count is the
## Beginner layout's (every Hard layout has more stars).
func rune_star_colors(cid: int, rune: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    var colours: Array = []
    var cd: Node = get_node_or_null("/root/ConstellationData")
    if cd:
        var layout = cd.get_constellation_def(cid).get("easy_layout")
        var colors: Array = cd.get_puzzle_star_colors(cid)
        if layout is Dictionary and colors.size() == int(layout.get("star_count", -1)):
            colours = colors
    for s in Board.star_cells(rune):
        var raw = colours[s] if s < colours.size() else null
        # The cache round-trips through saves; int() on a non-number can hang.
        out[s] = clampi(int(raw), 0, STAR_COLORS_BY_IDX.size() - 1) \
            if typeof(raw) in [TYPE_INT, TYPE_FLOAT] else Board.NO_COLOUR
    return out


## Draws a Rune on `canvas` with its `anchor` cell centred on `origin`, turned
## `sixths` clockwise: its cells filled in `fill`, its lines over them, and its
## stars in their constellation stars' colours.
func _draw_rune(canvas: Control, rune: Dictionary, anchor: Vector2i, sixths: int, origin: Vector2,
        cell_size: float, fill: Color, line: Color, star_colors: Dictionary,
        fill_alpha: float = 0.3) -> void:
    for c in Board.held_cells(rune, anchor, sixths):
        canvas.draw_colored_polygon(Board.cell_outline(c, cell_size, origin, CELL_SHRINK),
            Color(fill, fill_alpha))
    var stars: Dictionary = Board.held_stars(rune, anchor, sixths)
    var flat: Array = rune.get("lines", [])
    var width: float = maxf(1.5, cell_size * 0.09)
    for i in range(0, flat.size() - 1, 2):
        canvas.draw_line(origin + Board.cell_point(stars[int(flat[i])], cell_size),
            origin + Board.cell_point(stars[int(flat[i + 1])], cell_size), line, width, true)
    var radius: float = maxf(2.5, cell_size * 0.17)
    for s in stars:
        var ci: int = int(star_colors.get(s, Board.NO_COLOUR))
        var colour: Color = UNKNOWN_STAR if ci == Board.NO_COLOUR else STAR_COLORS_BY_IDX[ci]
        var at: Vector2 = origin + Board.cell_point(stars[s], cell_size)
        canvas.draw_circle(at, radius + 1.5, STAR_EDGE)
        canvas.draw_circle(at, radius, colour)


# ---------------------------------------------------------------- the column

func _on_entry_input(event: InputEvent, i: int) -> void:
    if not (event is InputEventMouseButton and event.pressed
            and event.button_index == MOUSE_BUTTON_LEFT):
        return
    var e: Dictionary = _entries[i]
    # The columns take turns: no Rune is picked while a cell is held.
    if bool(e["fits"]) and not held_cell:
        held = {"rune": e["rune"], "color": e["color"], "star_colors": e["star_colors"],
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
    elif _hover_entry == i and bool(e["fits"]) and not held_cell:
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
    var cell_size: float = minf(ENTRY_SHAPE.x / (hi.x - lo.x), ENTRY_SHAPE.y / (hi.y - lo.y))
    var box_centre := Vector2(6.0 + ENTRY_SHAPE.x * 0.5, node.size.y * 0.5)
    var origin: Vector2 = box_centre - (lo + hi) * 0.5 * cell_size
    _draw_rune(node, rune, Vector2i.ZERO, 0, origin, cell_size, color, color, e["star_colors"], 0.3)

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
