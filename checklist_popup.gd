class_name ChecklistPopup
extends PopupPanel
# ================= CHECKLIST POPUP (base) =================
# Shared machinery for NameChecklistPopup/PitchChecklistPopup — extracted
# 2026-07-28, they were near-exact structural twins (same Undo signals,
# same left/right column balancing, same open()/clear_rows()) differing
# only in their per-row-type signals and add_*_row() population function.
# staff_popup.gd's _add_row_to_columns()/_clear_container() pair already
# showed the right shape for this; this base class generalizes it across
# scenes instead of just within one.

## Undo row — mirrors the star widget's Undo selects/blocks/all buttons.
## See constellation_study_overlay.gd's _undo_category_selects/_blocks for
## what each one actually reverts.
signal undo_selects_pressed(record_idx: int)
signal undo_blocks_pressed(record_idx: int)
signal undo_all_pressed(record_idx: int)

## Preloaded row scene for instantiation — same reusable row the staff
## popup and both checklist popups use, so cosmetic overrides apply
## everywhere at once.
var _row_scene: PackedScene = preload("res://StaffPopupRow.tscn")

## Record this popup is currently showing a checklist for.
var current_record_idx: int = -1

## Rows added since the last clear_rows() — drives left/right column
## balancing. NOT derived from left_col/right_col.get_child_count():
## clear_rows() uses queue_free(), which is deferred, so a rebuild that
## calls clear_rows() then immediately repopulates in the same frame
## would still see the outgoing rows in the live child count and split
## unevenly (visible as the row order/column assignment shifting on every
## reopen).
var _added_count: int = 0

@onready var _left_col: VBoxContainer = %LeftCol
@onready var _right_col: VBoxContainer = %RightCol
@onready var _btn_undo_selects: Button = %BtnUndoSelects
@onready var _btn_undo_blocks: Button = %BtnUndoBlocks
@onready var _btn_undo_all: Button = %BtnUndoAll


func _ready() -> void:
    _btn_undo_selects.pressed.connect(func(): undo_selects_pressed.emit(current_record_idx))
    _btn_undo_blocks.pressed.connect(func(): undo_blocks_pressed.emit(current_record_idx))
    _btn_undo_all.pressed.connect(func(): undo_all_pressed.emit(current_record_idx))


func open(record_idx: int, screen_pos: Vector2) -> void:
    current_record_idx = record_idx
    position = Vector2i(screen_pos)
    popup()


func clear_rows() -> void:
    # remove_child() first so each row stops counting toward its column's
    # minimum-size computation immediately — queue_free() alone only
    # defers deletion, so a caller that repopulates in the same frame
    # (every _open_*_checklist_popup() call does) would see
    # get_contents_minimum_size() count both the outgoing and incoming
    # rows at once, inflating the popup's computed size and causing the
    # visible position/size jump on every reopen.
    for child in _left_col.get_children():
        _left_col.remove_child(child)
        child.queue_free()
    for child in _right_col.get_children():
        _right_col.remove_child(child)
        child.queue_free()
    _added_count = 0


## Subclasses call this after building a row to place it and connect its
## row-independent signals (check_pressed/x_pressed/row_right_clicked are
## still connected by the caller, since those carry type-specific args).
func _add_row_to_columns(row: StaffPopupRow) -> void:
    if _added_count % 2 == 0:
        _left_col.add_child(row)
    else:
        _right_col.add_child(row)
    _added_count += 1
