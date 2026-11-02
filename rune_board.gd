extends RefCounted
# ================= RUNE BOARD v1.0.0 =================
# The inscription board Runes are fitted onto (Firmament, 2026-11-02): pointy-top
# hex cells, each addressed [half-cell column, row] exactly as the "hex" fits on
# a Rune in constellation_data.gd, so column and row are both odd or both even.
# A Rune uses the cells its stars sit in plus every cell one of its lines passes
# through (the prototype's rule, author's pick 2026-11-02; see _cells_crossed).
# Runes on one board never share a cell.
#
# Pure data and geometry, no nodes: rune_fitting_popout.gd draws it.

const SQRT3: float = 1.7320508
## Points sampled along each line to find the cells it crosses (the prototype's).
const SAMPLES: int = 60

## Every cell of the board -> true.
var cells: Dictionary = {}
## Each Rune on the board: {"rune", "sixths", "anchor", "at", "cells", "stars"}.
## "anchor" is the Rune's own cell held under the pointer, "at" the board cell
## it was dropped on, and "stars" maps each star to its board cell.
var placed: Array = []
## Board cell -> index into `placed`.
var _owner: Dictionary = {}


func _init(radius: int = 1) -> void:
    for c in hexagon(radius):
        cells[c] = true


## A hexagon of cells `radius` rings out from [0,0]: 1 -> 7 cells, 2 -> 19, 3 -> 37.
static func hexagon(radius: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for r in range(-radius, radius + 1):
        for q in range(-2 * radius, 2 * radius + 1):
            if posmod(q - r, 2) == 0 and distance(Vector2i(0, 0), Vector2i(q, r)) <= radius:
                out.append(Vector2i(q, r))
    return out


## Steps between two cells.
static func distance(a: Vector2i, b: Vector2i) -> int:
    var dq: int = absi(a.x - b.x)
    var dr: int = absi(a.y - b.y)
    return dr + maxi(0, (dq - dr) / 2)


## Centre of a cell, for cells whose corners sit `size` from their centres.
static func cell_point(cell: Vector2i, size: float) -> Vector2:
    return Vector2(float(cell.x) * SQRT3 * 0.5, float(cell.y) * 1.5) * size


## The cell a point falls in.
static func point_cell(p: Vector2, size: float) -> Vector2i:
    var c: Vector2i = _round_axial((SQRT3 / 3.0 * p.x - p.y / 3.0) / size, (2.0 / 3.0 * p.y) / size)
    return Vector2i(2 * c.x + c.y, c.y)


## `cell` turned `sixths` sixths of a turn clockwise on screen about [0,0].
static func rotated(cell: Vector2i, sixths: int) -> Vector2i:
    var c: Vector2i = cell
    for _i in posmod(sixths, 6):
        c = Vector2i((c.x - 3 * c.y) / 2, (c.x + c.y) / 2)
    return c


## Star -> its cell in the Rune's own fit.
static func star_cells(rune: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    var hex: Dictionary = rune.get("hex", {})
    for s in hex:
        var at: Array = hex[s]
        out[int(s)] = Vector2i(int(at[0]), int(at[1]))
    return out


## Every cell the Rune uses in its own fit: its stars' cells and the cells its
## lines pass through.
static func rune_cells(rune: Dictionary) -> Array[Vector2i]:
    var stars: Dictionary = star_cells(rune)
    var used: Dictionary = {}
    for s in stars:
        used[stars[s]] = true
    var flat: Array = rune.get("lines", [])
    for i in range(0, flat.size() - 1, 2):
        var a: Vector2i = stars[int(flat[i])]
        var b: Vector2i = stars[int(flat[i + 1])]
        for c in _cells_crossed(a, b):
            used[c] = true
    var out: Array[Vector2i] = []
    for c in used:
        out.append(c)
    return out


## Cells the straight line from a's centre to b's passes through, found the way
## the author's prototype found them (2026-11-01): 61 evenly spaced points along
## the line, each rounded to its cell. The fits and their cell counts were
## approved on this rule, so it is kept as is. Where a line runs exactly along
## an edge between two cells, rounding picks the side, so a Rune's cells are
## found once in its own fit and turned with it, never found again turned.
static func _cells_crossed(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
    var pa: Vector2 = _prototype_centre(a)
    var pb: Vector2 = _prototype_centre(b)
    var out: Array[Vector2i] = []
    for i in SAMPLES + 1:
        var p: Vector2 = pa.lerp(pb, float(i) / float(SAMPLES))
        var r: float = p.y / 1.5
        var c: Vector2i = _round_axial(p.x / sqrt(3.0) - r * 0.5, r)
        var cell := Vector2i(2 * c.x + c.y, c.y)
        if not out.has(cell):
            out.append(cell)
    return out


## A cell's centre in the prototype's own axial arithmetic, so its rounding on
## cell edges comes out the same.
static func _prototype_centre(cell: Vector2i) -> Vector2:
    var q: int = (cell.x - cell.y) / 2
    return Vector2(sqrt(3.0) * (float(q) + float(cell.y) * 0.5), 1.5 * float(cell.y))


static func _round_axial(q: float, r: float) -> Vector2i:
    var x: float = q
    var z: float = r
    var y: float = -x - z
    var rx: float = round(x)
    var ry: float = round(y)
    var rz: float = round(z)
    var dx: float = absf(rx - x)
    var dy: float = absf(ry - y)
    var dz: float = absf(rz - z)
    if dx > dy and dx > dz:
        rx = -ry - rz
    elif dy <= dz:
        rz = -rx - ry
    return Vector2i(int(rx), int(rz))


## The six corners of a cell, clockwise from the top, offset by `origin` and
## drawn at `shrink` of full size (below 1 leaves a gap between cells).
static func cell_outline(cell: Vector2i, size: float, origin: Vector2 = Vector2.ZERO,
        shrink: float = 1.0) -> PackedVector2Array:
    var centre: Vector2 = origin + cell_point(cell, size)
    var out := PackedVector2Array()
    for k in 6:
        var ang: float = deg_to_rad(-90.0 + 60.0 * float(k))
        out.append(centre + Vector2(cos(ang), sin(ang)) * size * shrink)
    return out


## The Rune's cells relative to `anchor` (one of its own cells, which lands on
## the board cell under the pointer), turned `sixths` clockwise about it.
static func held_cells(rune: Dictionary, anchor: Vector2i, sixths: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for c in rune_cells(rune):
        out.append(rotated(c - anchor, sixths))
    return out


## Star -> cell relative to `anchor`, turned like held_cells().
static func held_stars(rune: Dictionary, anchor: Vector2i, sixths: int) -> Dictionary:
    var out: Dictionary = {}
    var stars: Dictionary = star_cells(rune)
    for s in stars:
        out[s] = rotated(stars[s] - anchor, sixths)
    return out


## The Rune's own cell nearest the middle of its fit: what the pointer holds
## when the Rune is picked from the list.
static func middle_cell(rune: Dictionary) -> Vector2i:
    var all: Array[Vector2i] = rune_cells(rune)
    var mid := Vector2.ZERO
    for c in all:
        mid += cell_point(c, 1.0)
    mid /= maxf(1.0, float(all.size()))
    var best: Vector2i = all[0]
    for c in all:
        if cell_point(c, 1.0).distance_to(mid) < cell_point(best, 1.0).distance_to(mid) - 0.0001:
            best = c
    return best


## Whether the Rune, held at `anchor` and turned `sixths`, can drop with the
## anchor on board cell `at`.
func can_place(rune: Dictionary, anchor: Vector2i, sixths: int, at: Vector2i) -> bool:
    for c in held_cells(rune, anchor, sixths):
        var on: Vector2i = at + c
        if not cells.has(on) or _owner.has(on):
            return false
    return true


## Drops the Rune; returns its index in `placed`, or -1 where it doesn't fit.
func place(rune: Dictionary, anchor: Vector2i, sixths: int, at: Vector2i) -> int:
    if not can_place(rune, anchor, sixths, at):
        return -1
    var used: Array[Vector2i] = []
    for c in held_cells(rune, anchor, sixths):
        used.append(at + c)
    var stars: Dictionary = {}
    var rel: Dictionary = held_stars(rune, anchor, sixths)
    for s in rel:
        stars[s] = at + (rel[s] as Vector2i)
    placed.append({"rune": rune, "sixths": posmod(sixths, 6), "anchor": anchor,
        "at": at, "cells": used, "stars": stars})
    _reindex()
    return placed.size() - 1


## Lifts the Rune covering `cell` off the board and returns its placement, with
## "anchor" moved to the lifted cell so it stays under the pointer; {} if the
## cell is empty.
func take(cell: Vector2i) -> Dictionary:
    if not _owner.has(cell):
        return {}
    var p: Dictionary = placed[int(_owner[cell])]
    placed.remove_at(int(_owner[cell]))
    _reindex()
    # Undo the turn on the lifted cell's offset to find which of the Rune's own
    # cells it is.
    var own: Vector2i = rotated(cell - (p["at"] as Vector2i), 6 - int(p["sixths"])) + (p["anchor"] as Vector2i)
    var out: Dictionary = p.duplicate()
    out["anchor"] = own
    return out


func clear() -> void:
    placed.clear()
    _owner.clear()


## Whether the Rune fits on this board, empty, in any turn.
func fits_empty(rune: Dictionary) -> bool:
    var own: Array[Vector2i] = rune_cells(rune)
    if own.size() > cells.size():
        return false
    var saved: Dictionary = _owner
    _owner = {}
    var ok: bool = false
    for sixths in 6:
        for at in cells:
            if can_place(rune, own[0], sixths, at):
                ok = true
                break
        if ok:
            break
    _owner = saved
    return ok


func used_count() -> int:
    return _owner.size()


func _reindex() -> void:
    _owner.clear()
    for i in placed.size():
        for c in placed[i]["cells"]:
            _owner[c] = i
