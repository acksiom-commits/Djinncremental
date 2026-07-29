class_name PitchChecklistPopup
extends ChecklistPopup

## Emitted when a pitch row's check button is pressed.
signal pitch_check_pressed(record_idx: int, note_name: String, row: StaffPopupRow)
## Emitted when a pitch row's X button is pressed.
signal pitch_x_pressed(record_idx: int, note_name: String, row: StaffPopupRow)
## Emitted when a pitch row is right-clicked (protect toggle).
signal pitch_row_right_clicked(record_idx: int, note_name: String)


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

    _add_row_to_columns(row)
    return row
