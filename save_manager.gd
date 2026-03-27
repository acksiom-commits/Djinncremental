extends Node

var save_file_path: String = "user://djinncremental_save.json"

var resources: Dictionary = {}
var spinbox_assignments: Dictionary = {}
var purity_locks: Dictionary = {}
var refinements_completed: int = 0
var level: int = 1

signal game_loaded()
signal save_reset()

# ================== Helper function ==================
# Safely convert parsed JSON to Dictionary
func parse_result_as_dict(parse_result) -> Dictionary:
    if parse_result == null:
        push_error("Save file data is invalid JSON.")
        return {}
    if typeof(parse_result) != TYPE_DICTIONARY:
        push_error("Save file data is not a dictionary.")
        return {}
    return parse_result as Dictionary

# ================== PUBLIC METHODS ==================

func save_game() -> void:
    var save_data: Dictionary = {
        "resources": resources,
        "spinbox_assignments": spinbox_assignments,
        "purity_locks": purity_locks,
        "archon": {
            "refinements_completed": refinements_completed,
            "level": level
        }
    }

    var file := FileAccess.open(save_file_path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(save_data)) # static call
        file.close()
        print("Game saved successfully.")
    else:
        push_error("Failed to open save file for writing.")

func load_game() -> void:
    var file := FileAccess.open(save_file_path, FileAccess.READ)
    if not file:
        print("No save file found; starting fresh.")
        return

    var text := file.get_as_text()
    file.close()

    # Parse using static JSON method
    var parse_result = JSON.parse_string(text)

    # Use helper function to get a typed Dictionary
    var save_data: Dictionary = parse_result_as_dict(parse_result)

    # Load game state
    resources = save_data.get("resources", {}) as Dictionary
    spinbox_assignments = save_data.get("spinbox_assignments", {}) as Dictionary
    purity_locks = save_data.get("purity_locks", {}) as Dictionary

    var archon_data: Dictionary = save_data.get("archon", {}) as Dictionary
    refinements_completed = archon_data.get("refinements_completed", 0) as int
    level = archon_data.get("level", 1) as int

    emit_signal("game_loaded")
    print("Game loaded successfully.")

func reset_save() -> void:
    resources.clear()
    spinbox_assignments.clear()
    purity_locks.clear()
    refinements_completed = 0
    level = 1
    save_game()
    emit_signal("save_reset")
    print("Save reset complete.")
