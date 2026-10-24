extends Node

# Bumped whenever a future patch changes the *shape* of the top-level save
# dict in a way older code can't already handle gracefully (a field rename,
# removal, or restructuring — not a plain new field, since every
# load_save_data() already treats a missing key as "use the default").
# load_game() reads this into loaded_save_format_version before dispatching
# to any subsystem; a version-gated migration step (mirroring the existing
# precedent at game_context.gd's _migrate_flat_volitions_to_slots(), which
# was keyed on key-presence before this field existed) belongs here, run
# once on the raw `data` dict before the per-subsystem load calls below.
# Nothing to migrate yet — this is the alpha's first save format.
const SAVE_FORMAT_VERSION: int = 1

## The save_format_version load_game() most recently read, or -1 before any
## load has happened. 0 means "predates this field" (every save written
## before this version stamp existed) — distinct from "field present but
## wrong-typed", which also falls back to 0 since there's nothing coherent
## to migrate from a value that isn't even the right type.
var loaded_save_format_version: int = -1

const SAVE_PATH := "user://djinncremental_save.json"
# Atomic-write scratch + rolling backup. See save_game() for the rotation
# invariant these enforce: at least one of {SAVE_PATH, BAK_PATH} is always a
# complete, valid save at every instant, so a crash/kill/power-loss mid-write
# can never destroy more than the most recent autosave cycle.
const TMP_PATH := "user://djinncremental_save.json.tmp"
const BAK_PATH := "user://djinncremental_save.json.bak"

# ── Save slots ────────────────────────────────────────────────────────
# Slot 1 IS the pre-slot save (SAVE_PATH/TMP_PATH/BAK_PATH above), so every
# save written before slots existed simply shows up as Slot 1 — no
# migration. Slots 2+ get their own primary/.tmp/.bak trio, each with the
# same atomic-rotation invariant as save_game() describes.
const SLOT_COUNT: int = 3
## The slot the running playthrough reads from and writes to. Every
## automatic save (timer, quit, age transition) targets this slot only.
var active_slot: int = 1
## Off = the game writes only when the player presses Save (plus the
## age-transition save, which RootUI's load-on-entry depends on — see
## autosave()). Defaults on so a first-time player can't lose progress.
var autosave_enabled: bool = true

# Device-level preferences, not part of any playthrough: which slot to
# boot into, and the autosave choice. Kept out of the save JSON on purpose —
# switching slots must not change them, and they have to be readable before
# any slot is loaded.
const SETTINGS_PATH := "user://djinncremental_settings.cfg"

signal game_loaded(offline_seconds: float)
signal save_reset()
## Emitted when BOTH the primary save and its backup exist but neither can be
## read/parsed. Saving is disabled (see _save_disabled) so the corrupt files
## are preserved for manual recovery instead of being clobbered by the next
## autosave. A UI handler can surface this to the player; even with no handler,
## the save-disable alone prevents the silent data loss that used to happen
## here (load would just start a fresh game, then autosave over the corruption).
signal save_load_failed()
## Emitted when the atomic-write rotation's final tmp->primary rename fails
## (locked by antivirus/cloud-sync, permissions, disk error, etc.) — the
## verified new save data is stranded in TMP_PATH and never went live.
## Not fatal on its own: the previous good save is untouched (rename never
## got that far), and the next autosave 60s later is a fresh, independent
## attempt that will likely succeed once the lock clears. A UI handler can
## surface this; even with no handler, at minimum it's now logged instead
## of silently discarded.
signal save_failed()
## Emitted by load_slot() when a NON-active slot's files exist but can't be
## read. Unlike save_load_failed this leaves saving enabled: the running
## game stays on its own slot, untouched, so there is nothing to protect.
signal slot_load_failed(slot: int)

## Set true only when load found existing-but-unreadable save files. While set,
## save_game() refuses to write, so nothing overwrites the corrupt files.
var _save_disabled: bool = false


# Nothing in this project previously saved on quit at all — the game relied
# entirely on the 60s autosave timer (root_ui.gd's _process()). A player who
# quits (via the OS window's close button, Alt+F4, etc.) before that timer
# has ever fired — trivially possible in the first minute of a brand-new
# game, e.g. mid-way through the very first Monad tutorial dialogue — has no
# save file at all yet, so the next load falls into load_game()'s legitimate
# "no save file found, starting fresh" branch. From the player's side that's
# indistinguishable from "reloading wiped my progress", even though nothing
# was actually lost that had ever been written. This notification is Godot's
# standard hook for "the OS asked this window to close" and runs synchronously
# before the engine proceeds to quit, so a blocking save_game() call here
# (no async/await anywhere in this function) completes before exit.
# Does NOT cover a direct get_tree().quit() call from in-game UI (e.g. the
# Settings panel's Quit button) — that bypasses this notification entirely;
# see root_ui.gd's quit_requested handler for that path's own save call.
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        autosave()


func _ready() -> void:
    _load_settings()


## Every save the game makes on its own (60s timer, quitting, one-shot
## checkpoints) goes through here so the Settings panel's Autosave toggle
## covers all of them. The age-transition saves in root_ui.gd/firmament_ui.gd
## deliberately call save_game() instead: RootUI reloads from disk on entry
## (_load_on_start), so skipping that save would roll the player back.
func autosave() -> void:
    if autosave_enabled:
        save_game()


## True after a reset of, or a new game in, the active slot (until the app
## restarts), or after a corrupt load. The Settings panel shows it so a
## player isn't left wondering why nothing is being written.
func saving_paused() -> bool:
    return _save_disabled


func set_autosave_enabled(on: bool) -> void:
    autosave_enabled = on
    _save_settings()


func save_game() -> void:
    _write_slot(active_slot)


## Writes the running game into `slot` and makes it the active slot ("save
## as"). The active slot only moves once the write has fully landed, so a
## refused or failed write leaves the game bound where it was.
func save_to_slot(slot: int) -> void:
    if _write_slot(slot):
        _set_active_slot(slot)


func _write_slot(slot: int) -> bool:
    if _save_disabled:
        # A prior load found corrupt save files; writing now would overwrite
        # them and destroy any chance of manual recovery. Stay hands-off.
        return false
    # The opening vessel-selection screen is not part of a playthrough yet.
    # Saving from it (the window-close hook below does, unconditionally)
    # wrote a blank-vessel save, and intro_screen.gd treats any save on disk
    # as "returning player" and skips the screen on every launch after.
    var scene: Node = get_tree().current_scene if get_tree() else null
    if scene and scene.has_method("is_awaiting_vessel_choice") and scene.is_awaiting_vessel_choice():
        return false
    var gc:      Node = get_node_or_null("/root/GameContext")
    var cd:      Node = get_node_or_null("/root/ConstellationData")
    var adm:     Node = get_node_or_null("/root/ArchonDialogueManager")
    var ar:      Node = get_node_or_null("/root/AchievementRegistry")
    # JournalPopout is a scene node owned by the current age's UI scene, not
    # an autoload — reach it the same way root_ui.gd itself does.
    var journal: Node = null
    if get_tree().current_scene:
        journal = get_tree().current_scene.find_child("JournalPopout", true, false)
    if not gc:
        push_error("SaveManager: GameContext not found.")
        return false
    var save_path: String = slot_save_path(slot)
    var tmp_path:  String = save_path + ".tmp"
    var bak_path:  String = save_path + ".bak"
    var data: Dictionary = gc.get_save_data()
    if cd and cd.has_method("get_save_data"):
        data["constellation"] = cd.get_save_data()
    if adm and adm.has_method("get_save_data"):
        data["dialogue"] = adm.get_save_data()
    if ar and ar.has_method("get_save_data"):
        data["achievements"] = ar.get_save_data()
    if journal and journal.has_method("get_save_data"):
        data["journal"] = journal.get_save_data()
    data["save_timestamp"] = Time.get_unix_time_from_system()
    data["save_format_version"] = SAVE_FORMAT_VERSION

    # ── Atomic write ──────────────────────────────────────────────────
    # 1. Write the new save to a temp file. Until this fully succeeds the
    #    live save (save_path) is never touched, so a failure here leaves
    #    the existing good save completely intact.
    var json_text: String = JSON.stringify(data)
    var tmp := FileAccess.open(tmp_path, FileAccess.WRITE)
    if not tmp:
        push_error("SaveManager: could not open temp save file for writing.")
        return false
    tmp.store_string(json_text)
    tmp.close()

    # 2. Verify the temp file actually landed intact (catches a truncated
    #    write, a full disk, or a stringify that produced garbage) BEFORE
    #    we trust it enough to rotate the live save out. Never promote an
    #    unverified temp into the primary slot.
    if not _is_readable_save(tmp_path):
        push_error("SaveManager: temp save failed verification, keeping previous save.")
        return false

    # 3. Rotate. Preserve the current primary as the backup, THEN move the
    #    verified temp into the primary slot. Moving primary→bak first means
    #    the temp→primary rename below always has an absent destination (no
    #    non-atomic remove-then-rename window on Windows). If a crash lands
    #    in the tiny gap between these two renames, primary is momentarily
    #    absent but BAK_PATH holds the last-good save and TMP_PATH holds the
    #    new-good save — load() falls back to the backup either way.
    #
    #    None of these three calls' return values were checked before — a
    #    transient lock (antivirus/cloud-sync scanning the save folder is
    #    common on Windows, exactly what itch.io testers are likely to have
    #    running) could silently no-op a save with no error, no signal,
    #    nothing — the player would only find out when they next relaunch
    #    and their progress isn't there. Confirmed directly: rename_absolute
    #    returns OK (and actually overwrites) when the destination already
    #    exists, and a non-OK Error code when it genuinely can't complete —
    #    that return value just needs to be looked at.
    if FileAccess.file_exists(save_path):
        if FileAccess.file_exists(bak_path):
            var remove_err: Error = DirAccess.remove_absolute(bak_path)
            if remove_err != OK:
                # Not fatal by itself — rename_absolute overwrites an
                # existing destination fine, so still attempt the rotation.
                push_warning("SaveManager: could not remove stale backup (error %d), attempting rotation anyway." % remove_err)
        var to_backup_err: Error = DirAccess.rename_absolute(save_path, bak_path)
        if to_backup_err != OK:
            # Backup rotation failed but the primary is untouched — still
            # worth promoting the verified new save over it directly rather
            # than discarding a good write over one failed housekeeping
            # step; bak_path just ends up one cycle staler than usual.
            push_warning("SaveManager: could not rotate primary save to backup (error %d)." % to_backup_err)
    var to_primary_err: Error = DirAccess.rename_absolute(tmp_path, save_path)
    if to_primary_err != OK:
        push_error("SaveManager: could not promote new save into primary slot (error %d) — the new save is stranded in %s and never went live; the previous save is untouched." % [to_primary_err, tmp_path])
        emit_signal("save_failed")
        return false
    return true


func slot_save_path(slot: int) -> String:
    if slot == 1:
        return SAVE_PATH
    return "user://djinncremental_save_slot%d.json" % slot


## Presence only, same as has_existing_save() — says nothing about whether
## the files parse.
func slot_has_save(slot: int) -> bool:
    var path: String = slot_save_path(slot)
    return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


## Unix time the slot was last written, from the file's mtime rather than
## its save_timestamp field so the Settings panel never parses a whole save
## just to label a button. 0 = empty slot (or a filesystem with no mtimes).
func slot_saved_unix(slot: int) -> int:
    var path: String = slot_save_path(slot)
    for p in [path, path + ".bak"]:
        if FileAccess.file_exists(p):
            return int(FileAccess.get_modified_time(p))
    return 0


## Whether a playthrough already exists on disk — either file is enough
## (see save_game()'s own rotation comment: at least one of the two is
## always a complete, valid save). Doesn't attempt to READ or PARSE
## either file, just checks presence, so it can't itself throw the
## corrupt-save signal load_game() does; a genuinely corrupt-but-present
## save still counts as "existing" here; load_game() is what surfaces
## the corruption once actually loading is attempted. Used by
## intro_screen.gd to skip the vessel-selection sequence for a returning
## player instead of replaying it on every single launch. Checks the ACTIVE
## slot only: booting into an empty slot (see start_new_game_in_slot())
## is exactly how a new playthrough gets its vessel choice.
func has_existing_save() -> bool:
    return slot_has_save(active_slot)


func load_game() -> void:
    if not get_node_or_null("/root/GameContext"):
        push_error("SaveManager: GameContext not found.")
        return

    # Try the primary save first, then the rolling backup. _read_save returns
    # null for a missing OR unparseable file, so this transparently recovers
    # from a torn primary write by loading the previous good save.
    var save_path: String = slot_save_path(active_slot)
    var data = _read_save(save_path)
    var source := "primary"
    if data == null:
        data = _read_save(save_path + ".bak")
        source = "backup"

    if data == null:
        # Distinguish "no save exists yet" (legitimate fresh start) from
        # "save files exist but are all unreadable" (real corruption). The
        # old code lumped these together and started a fresh game on
        # corruption — which the next autosave then wrote over the top of,
        # destroying any recovery chance. Now corruption halts loading and
        # disables saving so the files are preserved.
        if slot_has_save(active_slot):
            push_error("SaveManager: save AND backup are both unreadable — halting load and disabling saves to preserve the files for recovery.")
            _save_disabled = true
            emit_signal("save_load_failed")
            return
        push_warning("SaveManager: no save file found, starting fresh.")
        # Re-enable saving here — this is the "real restart completed"
        # signal reset_save() is waiting for (see its own comment). Also
        # covers the ordinary brand-new-player case, where _save_disabled
        # is already false and this is a no-op.
        _save_disabled = false
        emit_signal("game_loaded", 0.0)
        return

    if source == "backup":
        push_warning("SaveManager: primary save was unreadable, recovered from backup.")
    _apply_save_data(data)


## Switches the running game to another slot's playthrough, live — the same
## in-place load the Load button has always done, just from a different
## file. Returns false (and changes nothing) when the slot is empty or
## unreadable. Leaving a slot autosaves it first, so switching away loses
## nothing the 60s timer would have kept.
func load_slot(slot: int) -> bool:
    if slot == active_slot:
        load_game()
        return true
    var save_path: String = slot_save_path(slot)
    var data = _read_save(save_path)
    if data == null:
        data = _read_save(save_path + ".bak")
    if data == null:
        if slot_has_save(slot):
            push_error("SaveManager: slot %d's save and backup are both unreadable — not switching." % slot)
            emit_signal("slot_load_failed", slot)
        return false
    if not get_node_or_null("/root/GameContext"):
        push_error("SaveManager: GameContext not found.")
        return false
    autosave()
    _set_active_slot(slot)
    _apply_save_data(data)
    return true


## Binds the running game to an EMPTY slot and stops all saving until the
## app restarts — the same restart handshake reset_save() uses, since no
## autoload can rewind its in-memory state to a fresh game. On the next
## launch has_existing_save() is false, so the vessel choice plays and the
## new playthrough's first save lands in this slot. The game being left
## gets one last autosave into its own slot first.
func start_new_game_in_slot(slot: int) -> void:
    if slot != active_slot:
        autosave()
    _set_active_slot(slot)
    _save_disabled = true


func _apply_save_data(data: Dictionary) -> void:
    var gc:      Node = get_node_or_null("/root/GameContext")
    var cd:      Node = get_node_or_null("/root/ConstellationData")
    var adm:     Node = get_node_or_null("/root/ArchonDialogueManager")
    var ar:      Node = get_node_or_null("/root/AchievementRegistry")
    var journal: Node = null
    if get_tree().current_scene:
        journal = get_tree().current_scene.find_child("JournalPopout", true, false)

    var raw_version = data.get("save_format_version")
    loaded_save_format_version = int(raw_version) if (raw_version is int or raw_version is float) else 0
    # Version-gated migrations on the raw `data` dict (renamed/removed/
    # restructured fields, as opposed to a plain new field — see the
    # SAVE_FORMAT_VERSION comment) would run here, before any subsystem's
    # load_save_data() sees `data`. None exist yet.

    gc.load_save_data(data)
    # `data.get(key) is Dictionary` checks both "key present" and "value is
    # the right type" in one expression — replaces the old `data.has(key)`
    # check, which only verified the key existed. Each load_save_data()
    # below has a typed `data: Dictionary` parameter, and passing a wrong-
    # typed value (a corrupted save could put a String/Array there instead
    # of a nested object) hangs the engine at the call boundary rather than
    # raising a catchable error — confirmed directly — so it has to be
    # checked here, before the call, not inside the callee's own body.
    if cd and cd.has_method("load_save_data") and data.get("constellation") is Dictionary:
        cd.load_save_data(data["constellation"])
    if adm and adm.has_method("load_save_data") and data.get("dialogue") is Dictionary:
        adm.load_save_data(data["dialogue"])
    if ar and ar.has_method("load_save_data") and data.get("achievements") is Dictionary:
        ar.load_save_data(data["achievements"])
    if journal and journal.has_method("load_save_data") and data.get("journal") is Dictionary:
        journal.load_save_data(data["journal"])
    var raw_timestamp = data.get("save_timestamp")
    var timestamp: float = float(raw_timestamp) if (raw_timestamp is int or raw_timestamp is float) else -1.0
    var elapsed := 0.0
    if timestamp > 0.0:
        elapsed = Time.get_unix_time_from_system() - timestamp
    # A successful load of real save data is also a legitimate "restart
    # completed" signal — re-enable saving in case a prior session's reset
    # somehow left this disabled without the file actually being gone
    # (e.g. only the backup survived deletion). Ordinarily already false.
    _save_disabled = false
    emit_signal("game_loaded", elapsed)


func reset_save() -> void:
    reset_slot(active_slot)


## Deletes one slot's files. Only resetting the ACTIVE slot needs the
## restart handshake below — another slot's files aren't what the running
## game writes to, so deleting them leaves this session's saving alone.
func reset_slot(slot: int) -> void:
    # Return values checked for the same reason as save_game()'s rotation
    # (see its comment): a transient lock (antivirus/cloud-sync on Windows)
    # can silently no-op a delete with no error otherwise. Warn so it's at
    # least visible in the logs.
    var save_path: String = slot_save_path(slot)
    for suffix in ["", ".bak", ".tmp"]:
        var path: String = save_path + suffix
        if FileAccess.file_exists(path):
            var err: Error = DirAccess.remove_absolute(path)
            if err != OK:
                push_warning("SaveManager: could not remove %s on reset (error %d)." % [path, err])
    if slot != active_slot:
        return
    # Reset does NOT touch any autoload's live in-memory state (game_context,
    # archon_dialogue_manager, etc. keep running with the pre-reset session's
    # values) — nothing anywhere listens for the save_reset signal to clear
    # them either. So "Reset" only actually takes effect once the player
    # restarts the app and boots into a genuinely fresh set of autoloads.
    # Disabling saves here (instead of the old `_save_disabled = false`) is
    # what makes that gap safe: without it, EITHER the 60s autosave timer OR
    # (since the save-on-quit fix) literally any quit path would write the
    # still-loaded pre-reset state straight back into the file this just
    # deleted, making Reset look like it silently did nothing. load_game()
    # re-enables saving once a real restart completes — see the
    # `_save_disabled = false` sites in it and _apply_save_data().
    _save_disabled = true
    emit_signal("save_reset")


func _set_active_slot(slot: int) -> void:
    active_slot = slot
    _save_settings()


func _load_settings() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SETTINGS_PATH) != OK:
        return   # first launch: slot 1, autosave on
    var raw_slot = cfg.get_value("save", "active_slot", 1)
    active_slot = clampi(int(raw_slot) if (raw_slot is int or raw_slot is float) else 1, 1, SLOT_COUNT)
    var raw_auto = cfg.get_value("save", "autosave", true)
    autosave_enabled = raw_auto if raw_auto is bool else true


func _save_settings() -> void:
    var cfg := ConfigFile.new()
    cfg.load(SETTINGS_PATH)   # keep any other keys; missing file is fine
    cfg.set_value("save", "active_slot", active_slot)
    cfg.set_value("save", "autosave", autosave_enabled)
    var err: Error = cfg.save(SETTINGS_PATH)
    if err != OK:
        push_warning("SaveManager: could not write %s (error %d)." % [SETTINGS_PATH, err])


# Reads and parses a save file. Returns the parsed Dictionary, or null if the
# file is missing, unreadable, or not a valid JSON object. Shared by load_game()
# (recovery fallback) and _is_readable_save() (post-write verification).
func _read_save(path: String):
    if not FileAccess.file_exists(path):
        return null
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return null
    var text := file.get_as_text()
    file.close()
    var parsed = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return null
    return parsed


func _is_readable_save(path: String) -> bool:
    return _read_save(path) != null
