class_name RepeatChecklistPopup
extends ChecklistPopup

## Emitted when a repeat-count row's check button is pressed.
signal repeat_check_pressed(record_idx: int, value: int, row: StaffPopupRow)
## Emitted when a repeat-count row's X button is pressed.
signal repeat_x_pressed(record_idx: int, value: int, row: StaffPopupRow)
## Emitted when a repeat-count row is right-clicked (protect toggle).
signal repeat_row_right_clicked(record_idx: int, value: int)


func add_repeat_row(value: int, label_text: String, state: int, label_color: Color) -> StaffPopupRow:
    var row: StaffPopupRow = _row_scene.instantiate()
    row.label_text = label_text
    # No incidence count, unlike PitchChecklistPopup's add_pitch_row — the
    # true count of stars at this value is exactly the secret this axis is
    # built to withhold (see planned_repeat_count_axis_design.md). Same
    # show_count=false as NameChecklistPopup, for the same reason: neither
    # axis's per-value population size is safe to display.
    row.show_count = false
    row.label_color = label_color
    row.set_visual_state(state)

    row.check_pressed.connect(func(): repeat_check_pressed.emit(current_record_idx, value, row))
    row.x_pressed.connect(func(): repeat_x_pressed.emit(current_record_idx, value, row))
    row.row_right_clicked.connect(func(): repeat_row_right_clicked.emit(current_record_idx, value))

    _add_row_to_columns(row)
    return row
