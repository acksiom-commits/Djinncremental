extends PanelContainer
# ================= READOUTS PANEL v1.0.0 =================
# The direct readouts: Sparks, Uonites, Foci and Volitions, each a name row
# over a value row. Moved here from root_ui.gd's resource-row code (2026-11-04)
# so Firmament's copy of the panel shows the same, from one script on both
# pages. The rows are ResourceRow instances; root_ui.gd skips them (they carry
# the "readout" meta).

## Row node -> its resource key.
const ROWS := {
    "RowSparksLabelInstance":    "sparks_label",
    "RowUonitesLabelInstance":   "uonites_label",
    "RowFociLabelInstance":      "foci_label",
    "RowVolitionsLabelInstance": "volitions_label",
    "RowSparksValueInstance":    "sparks_value",
    "RowUonitesValueInstance":   "uonites_value",
    "RowFociValueInstance":      "foci_value",
    "RowVolitionsValueInstance": "volitions_value",
}

var _gc: Node = null
var _rows: Array = []


func _ready() -> void:
    _gc = get_node_or_null("/root/GameContext")
    for row_name in ROWS:
        var row: Node = find_child(row_name, true, false)
        if row and row.has_method("set_resource_key"):
            row.set_resource_key(ROWS[row_name])
            row.set_meta("readout", true)
            _rows.append(row)


func _process(_delta: float) -> void:
    if _gc and is_visible_in_tree():
        refresh()


func refresh() -> void:
    for row in _rows:
        match row.resource_key:
            "sparks_label":    row.set_label("[b]Sparks[/b]")
            "uonites_label":   row.set_label("[b]Uonites[/b]")
            "foci_label":      row.set_label("[b]Foci[/b]")
            "volitions_label": row.set_label("[b]Volitions[/b]")
            "sparks_value":
                row.set_label(fmt(_gc.sparks))
                var summoned: BigNum = _gc.totals_created.get("sparks_summoned", BigNum.zero())
                if not summoned.is_zero():
                    row.set_tooltip("Total summoned: " + summoned.to_display_string())
                else:
                    row.set_tooltip("")
            "uonites_value":
                var u_assigned  = _gc.get_total_uonites_assigned()
                var u_available = _gc.uonite.sub(u_assigned)
                row.set_label(fmt(u_available) + "/" + fmt(_gc.uonite))
            "foci_value":
                var f_assigned  = _gc.get_total_foci_assigned()
                var f_available = max(0, _gc.archon_foci - f_assigned)
                row.set_label(str(f_available) + "/" + str(_gc.archon_foci))
            "volitions_value":
                var bvps: int = _gc.get_bonus_volitions_per_slot()
                if bvps <= 0 or _gc.volition_slots.is_empty():
                    var v_assigned  = _gc.get_total_volitions_assigned()
                    var v_available = max(0, _gc.volitions - v_assigned)
                    row.set_label(str(v_available) + "/" + str(_gc.volitions))
                else:
                    var parts: Array[String] = []
                    var slot_count: int = _gc.volition_slots.size()
                    var display_cap: int = mini(slot_count, 2)
                    for si in display_cap:
                        var slot = _gc.volition_slots[si]
                        var p_free: int = 1 if slot["category"] == "" else 0
                        var c_free: int = _gc.get_free_children_in_slot(si)
                        var pair: String = str(p_free) + "/" + str(c_free)
                        if slot["category"] != "":
                            pair = "[color=#FFD730]" + pair + "[/color]"
                        parts.append(pair)
                    if slot_count > display_cap:
                        parts.append("+%d" % (slot_count - display_cap))
                    row.set_label(" | ".join(parts))


## Number text as root_ui.gd's _fmt() writes it: one decimal in scientific
## notation for large values.
static func fmt(value) -> String:
    if value == null:
        return "0"
    if value is BigNum:
        var s: String = value.to_display_string().to_lower()
        if "e" not in s:
            return str(int(value.to_float()))
        var parts = s.split("e")
        if parts.size() != 2:
            return s
        return "%.1fe%s" % [snapped(float(parts[0]), 0.1), parts[1]]
    if typeof(value) in [TYPE_FLOAT, TYPE_INT]:
        if abs(float(value)) >= 1e6 or abs(float(value)) <= 1e-4:
            return "%.1e" % float(value)
        return str(int(float(value)))
    return str(value)
