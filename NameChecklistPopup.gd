class_name NameChecklistPopup
extends ChecklistPopup

## Emitted when a name row's check button is pressed.
signal name_check_pressed(record_idx: int, name_str: String, row: StaffPopupRow)
## Emitted when a name row's X button is pressed.
signal name_x_pressed(record_idx: int, name_str: String, row: StaffPopupRow)
## Emitted when a name row is right-clicked (protect toggle).
signal name_row_right_clicked(record_idx: int, name_str: String)


func add_name_row(name_str: String, state: int, label_color: Color) -> StaffPopupRow:
    var row: StaffPopupRow = _row_scene.instantiate()
    row.label_text = name_str
    row.show_count = false
    row.label_color = label_color
    row.set_visual_state(state)

    row.check_pressed.connect(func(): name_check_pressed.emit(current_record_idx, name_str, row))
    row.x_pressed.connect(func(): name_x_pressed.emit(current_record_idx, name_str, row))
    row.row_right_clicked.connect(func(): name_row_right_clicked.emit(current_record_idx, name_str))

    _add_row_to_columns(row)
    return row
