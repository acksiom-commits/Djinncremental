extends Node

const SAVE_PATH := "user://djinncremental_save.json"

signal game_loaded(offline_seconds: float)
signal save_reset()


func save_game() -> void:
    var gc:  Node = get_node_or_null("/root/GameContext")
    var cd:  Node = get_node_or_null("/root/ConstellationData")
    var adm: Node = get_node_or_null("/root/ArchonDialogueManager")
    var ar:  Node = get_node_or_null("/root/AchievementRegistry")
    if not gc:
        push_error("SaveManager: GameContext not found.")
        return
    var data: Dictionary = gc.get_save_data()
    if cd and cd.has_method("get_save_data"):
        data["constellation"] = cd.get_save_data()
    if adm and adm.has_method("get_save_data"):
        data["dialogue"] = adm.get_save_data()
    if ar and ar.has_method("get_save_data"):
        data["achievements"] = ar.get_save_data()
    data["save_timestamp"] = Time.get_unix_time_from_system()
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if not file:
        push_error("SaveManager: could not open save file for writing.")
        return
    file.store_string(JSON.stringify(data))
    file.close()


func load_game() -> void:
    var gc:  Node = get_node_or_null("/root/GameContext")
    var cd:  Node = get_node_or_null("/root/ConstellationData")
    var adm: Node = get_node_or_null("/root/ArchonDialogueManager")
    var ar:  Node = get_node_or_null("/root/AchievementRegistry")
    if not gc:
        push_error("SaveManager: GameContext not found.")
        return
    if not FileAccess.file_exists(SAVE_PATH):
        push_warning("SaveManager: no save file found, starting fresh.")
        emit_signal("game_loaded", 0.0)
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if not file:
        push_error("SaveManager: could not open save file for reading.")
        return
    var text := file.get_as_text()
    file.close()
    var data = JSON.parse_string(text)
    if typeof(data) != TYPE_DICTIONARY:
        push_error("SaveManager: save file is corrupt.")
        emit_signal("game_loaded", 0.0)
        return
    gc.load_save_data(data)
    if cd and cd.has_method("load_save_data") and data.has("constellation"):
        cd.load_save_data(data["constellation"])
    if adm and adm.has_method("load_save_data") and data.has("dialogue"):
        adm.load_save_data(data["dialogue"])
    if ar and ar.has_method("load_save_data") and data.has("achievements"):
        ar.load_save_data(data["achievements"])
    var timestamp: float = float(data.get("save_timestamp", -1.0))
    var elapsed := 0.0
    if timestamp > 0.0:
        elapsed = Time.get_unix_time_from_system() - timestamp
    emit_signal("game_loaded", elapsed)


func reset_save() -> void:
    if FileAccess.file_exists(SAVE_PATH):
        DirAccess.remove_absolute(SAVE_PATH)
    emit_signal("save_reset")
