extends Node

# ================== PURITY LOCK MANAGER v0.6.2.10 ==================
# ================== Handles lock states ==================

# Dictionary to track lock state for each resource key
var locks: Dictionary = {}

# === PUBLIC INTERFACE ===

# Check if a resource is locked
func is_locked(resource_key: String) -> bool:
    if locks.has(resource_key):
        return locks[resource_key]
    return false

# Toggle a resource's lock state
func toggle_lock(resource_key: String) -> void:
    var current_state = is_locked(resource_key)
    locks[resource_key] = not current_state
    emit_signal("lock_changed", resource_key, locks[resource_key])

# Explicitly set a lock state
func set_lock(resource_key: String, locked: bool) -> void:
    locks[resource_key] = locked
    emit_signal("lock_changed", resource_key, locked)

# === SIGNALS ===
signal lock_changed(resource_key: String, locked: bool)

func get_icon_name(resource_key: String) -> String:
    return "Lock" if is_locked(resource_key) else "Unlock"
