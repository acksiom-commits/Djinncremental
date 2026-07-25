class_name NameChecklistPopup
extends PopupPanel

## Emitted when a name row's check button is pressed.
signal name_check_pressed(record_idx: int, name_str: String, row: StaffPopupRow)
## Emitted when a name row's X button is pressed.
signal name_x_pressed(record_idx: int, name_str: String, row: StaffPopupRow)
## Emitted when a name row is right-clicked (protect toggle).
signal name_row_right_clicked(record_idx: int, name_str: String)
## Undo row — mirrors the star widget's Undo selects/blocks/all buttons.
## See constellation_study_overlay.gd's _undo_category_selects/_blocks for
## what each one actually reverts.
signal undo_selects_pressed(record_idx: int)
signal undo_blocks_pressed(record_idx: int)
signal undo_all_pressed(record_idx: int)

## Preloaded row scene for instantiation — same reusable row the staff
## popup uses, so cosmetic overrides apply in both places at once.
var _row_scene: PackedScene = preload("res://StaffPopupRow.tscn")

## Record this popup is currently showing a checklist for.
var current_record_idx: int = -1

## Rows added since the last clear_rows() — drives left/right column
## balancing. NOT derived from _left_col/_right_col.get_child_count():
## clear_rows() below uses queue_free(), which is deferred, so a rebuild
## that calls clear_rows() then immediately repopulates in the same frame
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
    for child in _left_col.get_children():
        child.queue_free()
    for child in _right_col.get_children():
        child.queue_free()
    _added_count = 0


func add_name_row(name_str: String, state: int, label_color: Color) -> StaffPopupRow:
    var row: StaffPopupRow = _row_scene.instantiate()
    row.label_text = name_str
    row.show_count = false
    row.label_color = label_color
    row.set_visual_state(state)

    row.check_pressed.connect(func(): name_check_pressed.emit(current_record_idx, name_str, row))
    row.x_pressed.connect(func(): name_x_pressed.emit(current_record_idx, name_str, row))
    row.row_right_clicked.connect(func(): name_row_right_clicked.emit(current_record_idx, name_str))

    if _added_count % 2 == 0:
        _left_col.add_child(row)
    else:
        _right_col.add_child(row)
    _added_count += 1
    return row
