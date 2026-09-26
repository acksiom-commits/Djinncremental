extends RefCounted
# ============ CONSTELLATION CONTENT CERTIFIER ============
# Static checks on AUTHORED constellation data (the BUILT_IN defs in
# constellation_data.gd), for tooling only -- critical-pass review item 4,
# 2026-09-26.
#
# WHY THIS EXISTS. The runtime deliberately degrades gracefully on bad content
# rather than crash: _build_proximity() drops an out-of-range line endpoint,
# _set_sequence_ranks_from_order() ranks a star that never fires last "so
# malformed data degrades gracefully", ConstellationStarNamer falls back to
# "Star-N" when a theme pool is too small, the engine appends -1 for a melody
# note no star plays. That is the right policy for a live game and it is
# UNCHANGED. But it also means bad authoring never announces itself: it
# quietly ships as a slightly wrong puzzle. This turns each of those silent
# fallbacks into a named, reportable finding, so it fails loudly in the test
# suite and in a debug build, while production behaviour stays exactly as it
# was.
#
# Findings are {"code", "severity", "message"}. Codes are stable identifiers so
# allowlists can key on them.
#   ERROR  the runtime would silently degrade or misbehave on this content.
#   WARN   valid, but worth a human look (may well be intentional).
#
# Two reviewed allowlists live here, both keyed so that a STALE entry is itself
# a failure (see dev_tests/test_content_certification.gd):
#   PLACEHOLDERS     constellations whose content is not authored yet. Their
#                    errors are expected and reported, not failed on.
#   KNOWN_WARNINGS   warnings someone has looked at and accepted.

const SEV_ERROR: String = "error"
const SEV_WARN: String = "warn"

const MIN_STARS: int = 3        # Mutual Exclusion needs 3 participants
const MAX_STARS: int = 64
const AUDIBLE_MIN_HZ: float = 16.0
const AUDIBLE_MAX_HZ: float = 20000.0
## fixed_star_positions are points on the unit sphere.
const POSITION_LENGTH_TOLERANCE: float = 0.1

const _NamerScript = preload("res://constellation_star_namer.gd")

## id -> why its content is not certified yet.
const PLACEHOLDERS: Dictionary = {
    6: "The Djinn: no line_pairs, no fixed_star_positions, and a 15-step melody for 17 stars -- content not authored yet",
}

## "id:code" -> why the warning is accepted.
const KNOWN_WARNINGS: Dictionary = {
    "3:isolated_star": "The Bellows: stars 0-3 have no lines. INTENTIONAL (confirmed by the author 2026-09-26): they float free of the drawn figure.",
}


static func _finding(code: String, severity: String, message: String) -> Dictionary:
    return {"code": code, "severity": severity, "message": message}


static func _is_int(v) -> bool:
    return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and v == floorf(v))


static func _is_num(v) -> bool:
    return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


## The star each melody note lands on, exactly as
## ClickSequencePuzzleEngine._compute_correct_star_sequence picks it: the first
## star assigned that note which has not fired yet, else (all used) the first
## star with the note at all, else -1. Mirrored here so the certifier stays
## pure; test_content_certification checks it against the real engine.
static func correct_star_sequence(melody: Array, assignment: Array) -> Array:
    var result: Array = []
    var used: Array = []
    for step in melody.size():
        var pitch: int = int(melody[step]) if _is_int(melody[step]) else -1
        var best: int = -1
        for si in assignment.size():
            if int(assignment[si]) == pitch and not used.has(si):
                best = si
                break
        if best == -1:
            for si2 in assignment.size():
                if int(assignment[si2]) == pitch:
                    best = si2
                    break
        if best >= 0:
            used.append(best)
        result.append(best)
    return result


## Certify one def. `assignment` is the star -> note table the game would use
## (ConstellationData.get_note_assignment); only its multiset of notes matters
## for the checks below, so the per-player shuffle does not change the verdict.
static func certify(def: Dictionary, assignment: Array) -> Array:
    var out: Array = []
    var id: int = int(def.get("id", -1))

    if not _is_int(def.get("star_count")) or int(def["star_count"]) < MIN_STARS or int(def["star_count"]) > MAX_STARS:
        out.append(_finding("star_count_range", SEV_ERROR,
            "star_count %s is not an integer in %d..%d" % [str(def.get("star_count")), MIN_STARS, MAX_STARS]))
        return out   # everything below is measured against star_count
    var n: int = int(def["star_count"])

    _certify_lines(def, n, out)
    var note_count: int = _certify_notes(def, out)
    _certify_melody(def, n, note_count, assignment, out)
    _certify_positions(def, n, out)
    _certify_names(def, n, id, out)
    return out


static func _certify_lines(def: Dictionary, n: int, out: Array) -> void:
    var lp = def.get("line_pairs")
    if typeof(lp) != TYPE_ARRAY or (lp as Array).is_empty():
        out.append(_finding("no_lines", SEV_ERROR, "line_pairs is missing or empty -- the figure has no lines"))
        return
    var arr: Array = lp
    if arr.size() % 2 == 1:
        out.append(_finding("line_pairs_odd", SEV_ERROR,
            "line_pairs has an odd length (%d) -- the last endpoint is silently dropped" % arr.size()))
    var seen: Dictionary = {}
    var degree: Dictionary = {}
    var i: int = 0
    while i + 1 < arr.size():
        var a = arr[i]
        var b = arr[i + 1]
        i += 2
        if not _is_int(a) or not _is_int(b) or int(a) < 0 or int(a) >= n or int(b) < 0 or int(b) >= n:
            out.append(_finding("line_pairs_bounds", SEV_ERROR,
                "line %s-%s has an endpoint outside 0..%d -- it is silently dropped" % [str(a), str(b), n - 1]))
            continue
        var sa: int = int(a)
        var sb: int = int(b)
        if sa == sb:
            out.append(_finding("line_pairs_self_loop", SEV_ERROR, "line %d-%d joins a star to itself" % [sa, sb]))
            continue
        var key: String = "%d:%d" % [mini(sa, sb), maxi(sa, sb)]
        if seen.has(key):
            out.append(_finding("line_pairs_duplicate", SEV_ERROR, "line %d-%d is listed more than once" % [sa, sb]))
            continue
        seen[key] = true
        degree[sa] = int(degree.get(sa, 0)) + 1
        degree[sb] = int(degree.get(sb, 0)) + 1
    var isolated: Array = []
    for s in n:
        if not degree.has(s):
            isolated.append(s)
    if not isolated.is_empty():
        out.append(_finding("isolated_star", SEV_WARN,
            "%d star(s) have no line at all: %s" % [isolated.size(), str(isolated)]))


## Returns how many notes there are (0 when unusable).
static func _certify_notes(def: Dictionary, out: Array) -> int:
    var nf = def.get("note_freqs")
    if typeof(nf) != TYPE_ARRAY or (nf as Array).is_empty():
        out.append(_finding("note_freqs_empty", SEV_ERROR, "note_freqs is missing or empty -- there are no pitches"))
        return 0
    for f in (nf as Array):
        if not _is_num(f) or float(f) < AUDIBLE_MIN_HZ or float(f) > AUDIBLE_MAX_HZ:
            out.append(_finding("note_freqs_invalid", SEV_ERROR,
                "note_freqs holds %s, not a frequency in %d..%d Hz" % [str(f), int(AUDIBLE_MIN_HZ), int(AUDIBLE_MAX_HZ)]))
            break
    return (nf as Array).size()


static func _certify_melody(def: Dictionary, n: int, note_count: int, assignment: Array, out: Array) -> void:
    var melody = def.get("puzzle_sequence")
    if typeof(melody) != TYPE_ARRAY or (melody as Array).is_empty():
        out.append(_finding("melody_empty", SEV_ERROR, "puzzle_sequence is missing or empty -- there is no melody"))
        return
    var bad_note: bool = false
    for m in (melody as Array):
        if not _is_int(m) or int(m) < 0 or (note_count > 0 and int(m) >= note_count):
            out.append(_finding("melody_note_range", SEV_ERROR,
                "puzzle_sequence holds %s, not a note index in 0..%d" % [str(m), note_count - 1]))
            bad_note = true
            break
    if bad_note:
        return
    var seq: Array = correct_star_sequence(melody, assignment)
    var unplayed: Array = []
    var fired: Dictionary = {}
    for step in seq.size():
        if int(seq[step]) < 0:
            unplayed.append(int(melody[step]))
        else:
            fired[int(seq[step])] = true
    if not unplayed.is_empty():
        out.append(_finding("melody_note_unplayed", SEV_ERROR,
            "melody note(s) %s are played by no star -- the correct sequence would hold -1" % str(unplayed)))
    var never: Array = []
    for s in n:
        if not fired.has(s):
            never.append(s)
    if not never.is_empty():
        out.append(_finding("star_never_fires", SEV_ERROR,
            "%d star(s) never fire in the melody: %s -- they are ranked last by index (silent degradation)" % [never.size(), str(never)]))


static func _certify_positions(def: Dictionary, n: int, out: Array) -> void:
    var fp = def.get("fixed_star_positions")
    if typeof(fp) != TYPE_ARRAY:
        out.append(_finding("positions_missing", SEV_ERROR, "fixed_star_positions is missing -- the stars have no places"))
        return
    if (fp as Array).size() != n:
        out.append(_finding("positions_count", SEV_ERROR,
            "fixed_star_positions has %d entries for %d stars" % [(fp as Array).size(), n]))
        return
    for p in (fp as Array):
        if typeof(p) != TYPE_ARRAY or (p as Array).size() != 3 or not _is_num(p[0]) or not _is_num(p[1]) or not _is_num(p[2]):
            out.append(_finding("positions_malformed", SEV_ERROR, "a fixed_star_positions entry is not three numbers"))
            return
        var plen: float = Vector3(float(p[0]), float(p[1]), float(p[2])).length()
        if absf(plen - 1.0) > POSITION_LENGTH_TOLERANCE:
            out.append(_finding("positions_off_sphere", SEV_ERROR,
                "a fixed_star_positions entry has length %.3f, not a point on the unit sphere" % plen))
            return


static func _certify_names(def: Dictionary, n: int, id: int, out: Array) -> void:
    var theme = def.get("name_theme")
    var names: Array = _NamerScript.generate_names(n, id, theme if typeof(theme) == TYPE_DICTIONARY else {})
    var fallback: int = 0
    var seen: Dictionary = {}
    for nm in names:
        if str(nm).begins_with("Star-"):
            fallback += 1
        seen[str(nm)] = true
    if fallback > 0:
        out.append(_finding("names_fallback", SEV_ERROR,
            "the name theme's pool is too small: %d of %d stars got a placeholder \"Star-N\" name" % [fallback, n]))
    if seen.size() != names.size():
        out.append(_finding("names_duplicate", SEV_ERROR, "the generated star names are not all distinct"))


## Certify every BUILT_IN def with the game's own note assignment, and sort the
## results by the two reviewed allowlists. Returns
##   {"errors": [], "warnings": [], "placeholders": [], "stale": []}
## where every entry is a finding plus an "id". `errors`/`warnings` are the
## UNEXPECTED ones; `stale` lists allowlist entries that no longer match
## anything (a placeholder that now certifies clean, a known warning that is
## gone) so the list cannot quietly rot.
static func report_builtin(cd) -> Dictionary:
    var report: Dictionary = {"errors": [], "warnings": [], "placeholders": [], "stale": [], "all": []}
    var seen_warning_keys: Dictionary = {}
    for def in cd.BUILT_IN:
        var d: Dictionary = def
        var id: int = int(d.get("id", -1))
        var findings: Array = certify(d, cd.get_note_assignment(id))
        var has_error: bool = false
        for f in findings:
            var item: Dictionary = (f as Dictionary).duplicate()
            item["id"] = id
            report["all"].append(item)
            if item["severity"] == SEV_ERROR:
                has_error = true
                if PLACEHOLDERS.has(id):
                    report["placeholders"].append(item)
                else:
                    report["errors"].append(item)
            else:
                var key: String = "%d:%s" % [id, str(item["code"])]
                seen_warning_keys[key] = true
                if not KNOWN_WARNINGS.has(key):
                    report["warnings"].append(item)
        if PLACEHOLDERS.has(id) and not has_error:
            report["stale"].append("placeholder %d now certifies clean -- remove it from PLACEHOLDERS" % id)
    for key in KNOWN_WARNINGS:
        if not seen_warning_keys.has(key):
            report["stale"].append("known warning %s no longer occurs -- remove it from KNOWN_WARNINGS" % key)
    return report
