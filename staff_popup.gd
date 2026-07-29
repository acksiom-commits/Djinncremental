class_name StaffPopup
extends PopupPanel

## Emitted when a pitch row check button is pressed.
## Parameters: record_idx, note_name, row (StaffPopupRow)
signal pitch_check_pressed(record_idx: int, note_name: String, row: StaffPopupRow)
## Emitted when a pitch row X button is pressed.
signal pitch_x_pressed(record_idx: int, note_name: String, row: StaffPopupRow)
## Emitted when a pitch row is right-clicked (protect toggle).
signal pitch_row_right_clicked(record_idx: int, note_name: String)

## Emitted when a color row check button is pressed.
signal color_check_pressed(record_idx: int, color_idx: int, row: StaffPopupRow)
## Emitted when a color row X button is pressed.
signal color_x_pressed(record_idx: int, color_idx: int, row: StaffPopupRow)
## Emitted when a color row is right-clicked (protect toggle).
signal color_row_right_clicked(record_idx: int, color_idx: int)

## Emitted when a name row check button is pressed.
signal name_check_pressed(record_idx: int, name_str: String, row: StaffPopupRow)
## Emitted when a name row X button is pressed.
signal name_x_pressed(record_idx: int, name_str: String, row: StaffPopupRow)
## Emitted when a name row is right-clicked (protect toggle).
signal name_row_right_clicked(record_idx: int, name_str: String)

## Undo rows, one per section — mirror the star widget's Undo
## selects/blocks/all buttons. See constellation_study_overlay.gd's
## _undo_category_selects/_blocks for what each one actually reverts.
signal pitch_undo_selects_pressed(record_idx: int)
signal pitch_undo_blocks_pressed(record_idx: int)
signal pitch_undo_all_pressed(record_idx: int)
signal color_undo_selects_pressed(record_idx: int)
signal color_undo_blocks_pressed(record_idx: int)
signal color_undo_all_pressed(record_idx: int)
signal name_undo_selects_pressed(record_idx: int)
signal name_undo_blocks_pressed(record_idx: int)
signal name_undo_all_pressed(record_idx: int)

## Preloaded row scene for instantiation.
var _row_scene: PackedScene = preload("res://StaffPopupRow.tscn")

## Currently displayed sequence position.
var current_seq_pos: int = -1

## Currently displayed record index.
var current_record_idx: int = -1

## Rows added per section since the last clear_all_rows() — drives
## left/right column balancing. NOT derived from live get_child_count():
## clear_all_rows() uses queue_free(), which is deferred, so a rebuild that
## clears then immediately repopulates in the same frame would still see
## the outgoing rows in the count and split unevenly.
var _pitch_added_count: int = 0
var _color_added_count: int = 0
var _name_added_count: int = 0


@onready var _title_label: Label = %TitleLabel
@onready var _pitch_left_col: VBoxContainer = %PitchLeftCol
@onready var _pitch_right_col: VBoxContainer = %PitchRightCol
@onready var _color_left_col: VBoxContainer = %ColorLeftCol
@onready var _color_right_col: VBoxContainer = %ColorRightCol
@onready var _name_left_col: VBoxContainer = %NameLeftCol
@onready var _name_right_col: VBoxContainer = %NameRightCol

@onready var _pitch_btn_undo_selects: Button = %PitchBtnUndoSelects
@onready var _pitch_btn_undo_blocks: Button = %PitchBtnUndoBlocks
@onready var _pitch_btn_undo_all: Button = %PitchBtnUndoAll
@onready var _color_btn_undo_selects: Button = %ColorBtnUndoSelects
@onready var _color_btn_undo_blocks: Button = %ColorBtnUndoBlocks
@onready var _color_btn_undo_all: Button = %ColorBtnUndoAll
@onready var _name_btn_undo_selects: Button = %NameBtnUndoSelects
@onready var _name_btn_undo_blocks: Button = %NameBtnUndoBlocks
@onready var _name_btn_undo_all: Button = %NameBtnUndoAll


func _ready() -> void:
    _pitch_btn_undo_selects.pressed.connect(func(): pitch_undo_selects_pressed.emit(current_record_idx))
    _pitch_btn_undo_blocks.pressed.connect(func(): pitch_undo_blocks_pressed.emit(current_record_idx))
    _pitch_btn_undo_all.pressed.connect(func(): pitch_undo_all_pressed.emit(current_record_idx))
    _color_btn_undo_selects.pressed.connect(func(): color_undo_selects_pressed.emit(current_record_idx))
    _color_btn_undo_blocks.pressed.connect(func(): color_undo_blocks_pressed.emit(current_record_idx))
    _color_btn_undo_all.pressed.connect(func(): color_undo_all_pressed.emit(current_record_idx))
    _name_btn_undo_selects.pressed.connect(func(): name_undo_selects_pressed.emit(current_record_idx))
    _name_btn_undo_blocks.pressed.connect(func(): name_undo_blocks_pressed.emit(current_record_idx))
    _name_btn_undo_all.pressed.connect(func(): name_undo_all_pressed.emit(current_record_idx))


func open(seq_pos: int, record_idx: int, screen_pos: Vector2) -> void:
    current_seq_pos = seq_pos
    current_record_idx = record_idx
    _title_label.text = "Note %d" % seq_pos
    position = Vector2i(screen_pos)
    popup()


func clear_all_rows() -> void:
    _clear_container(_pitch_left_col)
    _clear_container(_pitch_right_col)
    _clear_container(_color_left_col)
    _clear_container(_color_right_col)
    _clear_container(_name_left_col)
    _clear_container(_name_right_col)
    _pitch_added_count = 0
    _color_added_count = 0
    _name_added_count = 0


func add_pitch_row(note_name: String, incidence_count: int, state: int, label_color: Color) -> StaffPopupRow:
    var row: StaffPopupRow = _row_scene.instantiate()
    row.label_text = note_name
    row.show_count = true
    row.count_value = incidence_count
    row.label_color = label_color
    row.set_visual_state(state)

    row.check_pressed.connect(func(): pitch_check_pressed.emit(current_record_idx, note_name, row))
    row.x_pressed.connect(func(): pitch_x_pressed.emit(current_record_idx, note_name, row))
    row.row_right_clicked.connect(func(): pitch_row_right_clicked.emit(current_record_idx, note_name))

    _add_row_to_columns(row, _pitch_left_col, _pitch_right_col, _pitch_added_count)
    _pitch_added_count += 1
    return row


func add_color_row(color_name: String, color_idx: int, state: int, star_color: Color) -> StaffPopupRow:
    var row: StaffPopupRow = _row_scene.instantiate()
    row.label_text = color_name
    row.show_count = false
    row.label_color = star_color
    row.set_visual_state(state)

    row.check_pressed.connect(func(): color_check_pressed.emit(current_record_idx, color_idx, row))
    row.x_pressed.connect(func(): color_x_pressed.emit(current_record_idx, color_idx, row))
    row.row_right_clicked.connect(func(): color_row_right_clicked.emit(current_record_idx, color_idx))

    _add_row_to_columns(row, _color_left_col, _color_right_col, _color_added_count)
    _color_added_count += 1
    return row


func add_name_row(name_str: String, state: int, label_color: Color) -> StaffPopupRow:
    var row: StaffPopupRow = _row_scene.instantiate()
    row.label_text = name_str
    row.show_count = false
    row.label_color = label_color
    row.set_visual_state(state)

    row.check_pressed.connect(func(): name_check_pressed.emit(current_record_idx, name_str, row))
    row.x_pressed.connect(func(): name_x_pressed.emit(current_record_idx, name_str, row))
    row.row_right_clicked.connect(func(): name_row_right_clicked.emit(current_record_idx, name_str))

    _add_row_to_columns(row, _name_left_col, _name_right_col, _name_added_count)
    _name_added_count += 1
    return row


func _add_row_to_columns(row: StaffPopupRow, left_col: VBoxContainer, right_col: VBoxContainer, added_index: int) -> void:
    # Strict alternation driven by the caller's per-section counter, not
    # live get_child_count() (see the counter vars' comment above).
    if added_index % 2 == 0:
        left_col.add_child(row)
    else:
        right_col.add_child(row)


func _clear_container(container: VBoxContainer) -> void:
    for child in container.get_children():
        # remove_child() first so the row stops counting toward the
        # container's minimum-size computation immediately — queue_free()
        # alone only defers deletion, so a caller that repopulates in the
        # same frame (every _open_staff_popup() call does) would see
        # get_contents_minimum_size() count both the outgoing and
        # incoming rows at once, inflating the popup's computed size.
        container.remove_child(child)
        child.queue_free()
