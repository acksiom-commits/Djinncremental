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
## column balancing. NOT derived from live get_child_count(): rebuilding
## columns (see _rebuild_columns) frees the old ones via queue_free(),
## which is deferred, so a rebuild that clears then immediately
## repopulates in the same frame would still see the outgoing rows in
## the count and split unevenly.
var _pitch_added_count: int = 0
var _color_added_count: int = 0
var _name_added_count: int = 0

## Column VBoxContainers, rebuilt on demand via set_*_column_count() —
## see that function's comment for why the column count is dynamic
## rather than a fixed 2.
var _pitch_columns: Array[VBoxContainer] = []
var _color_columns: Array[VBoxContainer] = []
var _name_columns:  Array[VBoxContainer] = []


@onready var _title_label: Label = %TitleLabel
@onready var _pitch_columns_box: HBoxContainer = %PitchColumns
@onready var _color_columns_box: HBoxContainer = %ColorColumns
@onready var _name_columns_box:  HBoxContainer = %NameColumns

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
    # Row content is cleared by set_*_column_count() rebuilding the
    # columns (called by _open_staff_popup() right after this) — nothing
    # left to free here beyond resetting the per-section counters.
    _pitch_added_count = 0
    _color_added_count = 0
    _name_added_count = 0


## Rebuilds a section's column layout to `count` columns, discarding
## whatever rows/columns it had before. Column count scales with content
## (see constellation_puzzle_widgets.gd's _staff_popup_column_count())
## instead of a fixed 2, so a section with many rows (e.g. Name, which
## scales with a constellation's star count) spreads wider instead of
## taller — keeps the popup from growing tall enough to cover the study
## panel's clue readout, and is needed anyway for constellations with
## more stars than fit nicely in 2 columns.
func _rebuild_columns(container: HBoxContainer, count: int) -> Array[VBoxContainer]:
    for child in container.get_children():
        # remove_child() first so the old rows/columns stop counting
        # toward minimum-size computation immediately — see the same
        # reasoning on the row-clearing fix this replaced.
        container.remove_child(child)
        child.queue_free()
    var columns: Array[VBoxContainer] = []
    for i in count:
        var col := VBoxContainer.new()
        col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        col.add_theme_constant_override("separation", 2)
        container.add_child(col)
        columns.append(col)
    return columns


func set_pitch_column_count(count: int) -> void:
    _pitch_columns = _rebuild_columns(_pitch_columns_box, count)


func set_color_column_count(count: int) -> void:
    _color_columns = _rebuild_columns(_color_columns_box, count)


func set_name_column_count(count: int) -> void:
    _name_columns = _rebuild_columns(_name_columns_box, count)


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

    _add_row_to_column_array(row, _pitch_columns, _pitch_added_count)
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

    _add_row_to_column_array(row, _color_columns, _color_added_count)
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

    _add_row_to_column_array(row, _name_columns, _name_added_count)
    _name_added_count += 1
    return row


func _add_row_to_column_array(row: StaffPopupRow, columns: Array[VBoxContainer], added_index: int) -> void:
    # Round-robin across however many columns this section currently has
    # (set via set_*_column_count(), driven by the caller's per-section
    # counter, not live get_child_count() — see that var's comment above).
    if columns.is_empty():
        return
    columns[added_index % columns.size()].add_child(row)
