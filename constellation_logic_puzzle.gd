class_name ConstellationLogicPuzzle
extends RefCounted
# ================= CONSTELLATION LOGIC PUZZLE v2.0.0 =================
# Deductive (Zebra-style) clue generator + solver for the constellation
# pitch-assignment puzzle.
#
# v2.0.0: Full rewrite of solver and generator.
#   SOLVER: Replaced naive backtracking with forward-checking + MRV
#     (Minimum-Remaining-Values) heuristic. FC propagates domain
#     reductions immediately after every partial assignment, pruning
#     branches that would violate alldiff or comparison constraints
#     before recursing. MRV always picks the most-constrained unassigned
#     variable next, reducing branching factor dramatically. Result:
#     milliseconds per solve vs. seconds/timeouts for naive backtracking
#     at 15+ stars.
#   GENERATOR: generate_clues_by_primer_type samples and constructs one
#     clue at a time directly from ground truth, ranked by primer-category
#     entropic bias, cycling through all categories every pass until
#     Sequence and Name both solve uniquely — see that function's own doc
#     comment and the constellation_puzzle_sequential_generator_design
#     memory for the full history (this comment predates that redesign and
#     describes the old entropy-greedy-pool approach it replaced).
#   ASYNC: generate_clues_async() is a coroutine (call with await) that
#     yields to the engine every FRAME_BUDGET_MSEC milliseconds, keeping
#     the main thread responsive during background pre-generation.
#   CACHE: Serializes to/from Dictionary for save_manager.gd integration.
#     Caller is responsible for storing/loading the cache dict.
#
# PROBLEM SHAPE:
#   N stars, each with a FIXED, player-visible identity:
#     - name (generated once per constellation_id, same for all players)
#     - color (one of 4 categories, seeded per-player, visible at a glance)
#     - position in the line-graph (proximity, derived from line_pairs)
#   Each star fires exactly once in the melody (guaranteed by
#   constellation_overlay.gd's _build_correct_star_sequence). The ONE
#   unknown the player deduces is: which melody-step does each star fire
#   at (= pitch_rank_solution[star_index] = step index in correct_star_sequence).
#
# USAGE (async, pre-generation):
#   var puzzle := ConstellationLogicPuzzle.new()
#   puzzle.setup(star_count, line_pairs, correct_star_sequence,
#                player_seed, constellation_id)
#   await puzzle.generate_clues_async()   # yields between frames
#   var clues: Array[String] = puzzle.get_clue_texts()
#   var cache: Dictionary = puzzle.to_cache_dict()  # save this
#
# USAGE (restore from cache):
#   var puzzle := ConstellationLogicPuzzle.new()
#   puzzle.from_cache_dict(cache_dict)
#   var clues: Array[String] = puzzle.get_clue_texts()
# ========================================================================
 
 
enum StarColor { BLUE, WHITE, YELLOW_ORANGE, RED }
const COLOR_NAMES           := ["Blue", "White", "Yellow", "Red"]
const SEQ_WORD_EARLIER      := "earlier"
const SEQ_WORD_LATER        := "later"
const FRAME_BUDGET_MSEC     := 2       # max ms of work per frame during async gen
const MAX_CROSS_TRIM_ROUNDS := 10   # was 6 — bumped for the third (name) axis
                                        # rounds. Total clue count is non-increasing round
                                        # to round, so this is a defensive ceiling, not a
                                        # normally-hit limit.
const MAX_BACKTRACK_NODES := 50000   # hard ceiling on recursive nodes explored per
                                       # solve() call, shared across all three solvers.
                                       # Without this, a hard-to-disambiguate clue set
                                       # can make backtracking explore an exponential
                                       # number of partial assignments and hang the main
                                       # thread. This converts that failure mode into
                                       # "solve() returns fewer than cap solutions,"
                                       # which every caller already treats the same way
                                       # as genuinely-not-unique-yet.
var _backtrack_nodes_remaining: int = 0
var _pitch_solve_fast_path_count: int = 0
var _pitch_solve_backtrack_count: int = 0
var _pitch_unresolved_star_sum: int = 0
var _pitch_unresolved_star_samples: int = 0
const DIFFICULTY_JITTER_MAGNITUDE := 3.0   # +/- range added to difficulty scores per generation,
                                            # so clue-kind ORDER varies run-to-run, not just clue CONTENT.
# ── Single-match clue rationing, per characteristic ──────────────────────
# Each characteristic (sequence, proximity, ...) gets its OWN independent
# positive-single-match budget and negative-single-match budget, each
# floor(star_count / CHARACTERISTIC_DIVISOR). Multiple clue kinds describing
# the same characteristic (e.g. "ordinal_exact" and "ordinal_adjacent" both pin a Sequence
# position) draw from the SAME budget rather than each getting their own —
# that's what caught adj_seq flooding unchecked last pass despite exact
# being capped. To add a characteristic or reclassify a kind, edit the two
# dictionaries below only; no other code changes needed.
const CHARACTERISTIC_DIVISOR := 4
const ENTROPY_SHORTLIST_SIZE := 12
const PITCH_EXACT_MAX_SHARE := 0.5   # entropy-greedy will pick pitch_exact for the
                                       # overwhelming majority of picks left unchecked
                                       # (a direct pin is structurally more entropy-
                                       # efficient per-clue than any relational fact) —
                                       # this caps its SHARE of normal picks so other
                                       # pitch kinds get real representation, not just
                                       # Phase 8's "at least one" floor.
const PITCH_FLAVOR_CLUE_TARGET := 6  # 2026-07-19: Pitch is NOT meant to be solvable
                                       # from clues alone — players are expected to use
                                       # the Listen mechanic to assign pitches themselves
                                       # (standing design constraint, not a completeness
                                       # requirement). Pitch generation used to run an
                                       # entropy-greedy loop until _solve_pitch reported a
                                       # unique solution (driving 10-16+ tone_exact clues
                                       # per puzzle) — replaced with a small fixed budget
                                       # of the MOST informative picks as a reinforcement/
                                       # convenience layer, not a parallel full CSP solve.
const PRIMER_CATEGORY_MIN := 2
# _primer_category_min(cat), defined further down near
# PRIMER_CATEGORY_ENTROPIC_BIAS, scales this flat floor by the same bias
# table driving _attempts_for_category — a flat floor of 2 was letting
# _trim_sequence_pass legitimately strip Multi-Elimination back down to
# barely anything even when generation produced plenty, since 2 survivors
# (one unique_list_n, one tone_all_diff) technically satisfies "the
# category has 2 members" without giving the player much Multi-
# Elimination content at all.
const TAB_MIN := 4
const POS_SINGLE_MATCH_KINDS_BY_CHARACTERISTIC: Dictionary = {
    "sequence":             ["ordinal_exact", "ordinal_adjacent"],
    "sequence_offset":      ["ordinal_offset"],
    "sequence_primer":      ["ordinal_neither_nor", "ordinal_either_or", "ordinal_unaligned"],
    "relative_order":       ["ordinal_cmp"],
    "pitch_relative_order": ["tone_cmp"],
    "pitch_single":         ["tone_exact"],
    "proximity_extreme":    ["ordinal_extreme"],
    "proximity_count":      ["ordinal_count_before"],
}
const NEG_SINGLE_MATCH_KINDS_BY_CHARACTERISTIC: Dictionary = {
    "sequence":  ["ordinal_neg"],
    "proximity": ["proximity_neg_adjacent"],
    "pitch":     ["tone_neg"],
}
const NOTE_LETTER_NAMES: Array[String] = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
]
 
static func note_name_for_freq(freq: float) -> String:
    if freq <= 0.0:
        return "?"
    var semitones_from_a4: float = 12.0 * log(freq / 440.0) / log(2.0)
    var midi_note: int = int(round(semitones_from_a4)) + 69
    var letter: String = NOTE_LETTER_NAMES[((midi_note % 12) + 12) % 12]
    var octave: int = int(floor(midi_note / 12.0)) - 1
    return "%s%d" % [letter, octave]
 
 
static func _ordinal(n: int) -> String:
    var mod100: int = n % 100
    if mod100 >= 11 and mod100 <= 13:
        return "%dth note" % n
    match n % 10:
        1: return "%dst note" % n
        2: return "%dnd note" % n
        3: return "%drd note" % n
        _: return "%dth note" % n
 
 
# ── Puzzle state ─────────────────────────────────────────────────────────
var star_count: int = 0
var constellation_id: int = -1
var player_seed_used: int = 0          # stored so cache-validity check is possible
var proximity: Array[Array] = []       # proximity[i] = Array[int]
var star_degrees: Array[int] = []      # star_degrees[i] = proximity[i].size(), computed once
var _max_degree: int = 0
var _min_degree: int = 0
var star_colors: Array[int] = []       # star_colors[i] = StarColor int (visible, per-player)
var _color_sub_rank: Array[int] = []   # star_colors[i]-relative sub-rank (0,1,2.. -> "A","B","C") so any star is referenceable, not just singleton colors
var star_names: Array[String] = []     # star_names[i] = procedural name (per-constellation)
var pitch_rank_solution: Array[int] = [] # pitch_rank_solution[i] = melody step for star i
 
# ── Internal clue representation ─────────────────────────────────────────
# Clues are stored as plain Dictionaries rather than Callables so they
# can be serialized to the save cache. The solver reconstructs comparison
# predicates from the stored fields at solve-time.
# Schema:
#   comparison:  {"kind":"ordinal_cmp",     "a":int, "b":int, "a_gt_b":bool, "text":String}
#   adjacent-seq:{"kind":"ordinal_adjacent", "a":int, "b":int, "text":String}  (a fires immediately after b)
#   extreme:     {"kind":"ordinal_extreme", "s":int, "neighbors":[int,...], "want_lowest":bool, "text":String}
#   flavor:      {"kind":"flavor",  "text":String}
var _final_clues: Array[Dictionary] = []
var _generation_complete: bool = false
 
# ── Real-pitch + graph-distance data (known info, used for flavor clues only) ──
var star_pitch_index: Array[int] = []     # star_pitch_index[i] = pitch-table index for star i
var _pitch_sub_rank: Array[int] = []      # star_pitch_index[i]-relative sub-rank (0,1,2.. -> "A","B","C"), same purpose as _color_sub_rank
var _pitch_freqs: Array[float] = []       # this constellation's Hz table, indexed by pitch index
var _distances: Array[Array] = []         # _distances[a][b] = shortest graph-hop count, -1 if unreachable
var _final_identity_clues: Array[Dictionary] = []   # promoted dist_color/between identity anchors
var _alph_rank: Array[int] = []   # star_index -> alphabetical rank among star_names, 0..star_count-1
 
# ── Pitch CSP domain — parallel to the Sequence-rank domain above, but NOT
# alldiff: multiple stars can legitimately share a pitch class. ──────────
var pitch_count: int = 0                # distinct pitch classes = _pitch_freqs.size()
var _pitch_freq_rank: Array[int] = []   # pitch_index -> ascending-frequency rank, ties share a rank
var _final_pitch_clues: Array[Dictionary] = []
 
var _rng := RandomNumberGenerator.new()
var _difficulty_jitter_salt: int = 0
 
 
# ==================================================
# SETUP — call before generate_clues_async()
# ==================================================
func setup(p_star_count: int, line_pairs: Array, correct_star_sequence: Array,
        p_player_seed: int, p_constellation_id: int,
        name_theme: Dictionary = {}, p_star_pitch_index: Array = [],
        p_pitch_freqs: Array = []) -> void:
    star_count       = p_star_count
    constellation_id = p_constellation_id
    player_seed_used = p_player_seed
    _generation_complete = false
    _final_clues.clear()
    _final_pitch_clues.clear()
    _final_identity_clues.clear()
 
    # Offset seed so color assignment never shares RNG stream with
    # get_note_assignment() or ConstellationStarNamer.
    _rng.seed = p_player_seed ^ (p_constellation_id * 0x9E3779B9) ^ 0x4C50_5A5A
 
    _build_proximity(line_pairs)
    _compute_distances()
    _compute_star_degrees()
    _assign_colors_balanced()
    _color_sub_rank = _assign_sub_ranks_within_groups(star_colors)
    _set_pitch_ranks_from_sequence(correct_star_sequence)
    star_names = ConstellationStarNamer.generate_names(
        star_count, p_constellation_id, name_theme)
    _shuffle_star_names_for_player()

    star_pitch_index = []
    for v in p_star_pitch_index:
        star_pitch_index.append(int(v))
    _pitch_freqs = []
    for v in p_pitch_freqs:
        _pitch_freqs.append(float(v))
    _pitch_sub_rank = _assign_sub_ranks_within_groups(star_pitch_index)

    # Pitch CSP domain setup: distinct pitch-class count and a stable
    # ascending-frequency rank per pitch index (ties share a rank), used by
    # the pitch propagator for bound-consistency the same way star ranks are
    # used by the Sequence propagator.
    pitch_count = _pitch_freqs.size()
    _compute_pitch_freq_rank()
 
 
func _compute_pitch_freq_rank() -> void:
    _pitch_freq_rank = []
    _pitch_freq_rank.resize(pitch_count)
    var order: Array = []
    for p in pitch_count:
        order.append(p)
    order.sort_custom(func(a, b): return _pitch_freqs[a] < _pitch_freqs[b])
    var rank: int = 0
    for i in order.size():
        if i > 0 and not is_equal_approx(_pitch_freqs[order[i]], _pitch_freqs[order[i - 1]]):
            rank += 1
        _pitch_freq_rank[order[i]] = rank
 
 
func _compute_distances() -> void:
    _distances = []
    for i in star_count:
        var dist: Array = []
        dist.resize(star_count)
        for j in star_count:
            dist[j] = -1
        dist[i] = 0
        var queue: Array = [i]
        var qi: int = 0
        while qi < queue.size():
            var cur: int = queue[qi]
            qi += 1
            for n in proximity[cur]:
                var ni: int = int(n)
                if dist[ni] == -1:
                    dist[ni] = dist[cur] + 1
                    queue.append(ni)
        _distances.append(dist)
 
 
func _build_proximity(line_pairs: Array) -> void:
    proximity.clear()
    proximity.resize(star_count)
    for i in star_count:
        proximity[i] = []
    var i: int = 0
    while i < line_pairs.size() - 1:
        var a: int = int(line_pairs[i])
        var b: int = int(line_pairs[i + 1])
        if a >= 0 and a < star_count and b >= 0 and b < star_count:
            if not proximity[a].has(b):
                proximity[a].append(b)
            if not proximity[b].has(a):
                proximity[b].append(a)
        i += 2


func _compute_star_degrees() -> void:
    star_degrees.clear()
    _max_degree = 0
    _min_degree = star_count
    for i in star_count:
        var deg: int = proximity[i].size()
        star_degrees.append(deg)
        if deg > _max_degree:
            _max_degree = deg
        if deg < _min_degree:
            _min_degree = deg


func _assign_colors_balanced() -> void:
    var deck: Array[int] = []
    for i in star_count:
        deck.append(i % 4)
    for i in range(deck.size() - 1, 0, -1):
        var j: int = _rng.randi_range(0, i)
        var tmp: int = deck[i]
        deck[i] = deck[j]
        deck[j] = tmp
    star_colors = deck


static func _sub_rank_letter(n: int) -> String:
    # 0 -> "A", 1 -> "B", ... 25 -> "Z", 26 -> "AA", matching how star_count
    # is small enough that a single letter almost always suffices, but this
    # doesn't silently break if a group ever exceeds 26.
    var s: String = ""
    var v: int = n
    while true:
        s = char(65 + (v % 26)) + s
        @warning_ignore("integer_division")
        v = v / 26 - 1
        if v < 0:
            break
    return s


func _assign_sub_ranks_within_groups(values: Array) -> Array[int]:
    # Shared helper for any "one value shared by multiple stars" category
    # (Color, Pitch): groups stars by their value, shuffles each group with
    # the same seeded _rng already used for colors/names, and assigns each
    # star a stable position within its group — so "Blue-B" or "A4-C" is a
    # genuine, reproducible per-star identifier, not just a lucky singleton.
    var groups: Dictionary = {}
    for i in values.size():
        var v = values[i]
        if not groups.has(v):
            groups[v] = []
        groups[v].append(i)
    var sub_rank: Array[int] = []
    sub_rank.resize(values.size())
    for v in groups.keys():
        var members: Array = groups[v]
        _shuffle_array(members)
        for pos in members.size():
            sub_rank[int(members[pos])] = pos
    return sub_rank


func _shuffle_star_names_for_player() -> void:
    # The name POOL is fixed per constellation_id (lore — same set of names
    # for every player, per ConstellationStarNamer), but WHICH star gets
    # WHICH name must still be randomized per-player, same as color, or the
    # Name axis is solved once per constellation and memorized forever.
    for i in range(star_names.size() - 1, 0, -1):
        var j: int = _rng.randi_range(0, i)
        var tmp: String = star_names[i]
        star_names[i] = star_names[j]
        star_names[j] = tmp


func _set_pitch_ranks_from_sequence(correct_star_sequence: Array) -> void:
    pitch_rank_solution = []
    pitch_rank_solution.resize(star_count)
    for i in star_count:
        pitch_rank_solution[i] = -1
 
    # Record each star's FIRST-occurrence step. Some constellations reuse a
    # star across multiple melody steps (more steps than stars — e.g. Spark's
    # 16-step Hallelujah Chorus over 7 stars), so we rank stars by first-fire
    # ORDER rather than trusting raw step numbers. That keeps
    # pitch_rank_solution a clean 0..star_count-1 permutation no matter how
    # many times a star repeats later in the sequence.
    var first_step: Array = []
    first_step.resize(star_count)
    for i in star_count:
        first_step[i] = -1
 
    for step in correct_star_sequence.size():
        var star_idx: int = int(correct_star_sequence[step])
        if star_idx < 0 or star_idx >= star_count:
            continue
        if first_step[star_idx] == -1:
            first_step[star_idx] = step
 
    # Stars that never fire (shouldn't happen with valid content) sort last,
    # by star index, so malformed data degrades gracefully instead of crashing.
    var order: Array = []
    for i in star_count:
        order.append(i)
    order.sort_custom(func(a, b):
        var fa: int = first_step[a]
        var fb: int = first_step[b]
        if fa == -1 and fb == -1:
            return a < b
        if fa == -1:
            return false
        if fb == -1:
            return true
        return fa < fb)
 
    for rank in order.size():
        pitch_rank_solution[order[rank]] = rank
 
    var missing: bool = false
    for i in star_count:
        if first_step[i] == -1:
            missing = true
    if missing:
        push_warning("ConstellationLogicPuzzle [%d]: some stars never fire in correct_star_sequence — check puzzle_sequence content." % constellation_id)
 
# ==================================================
# ARC-CONSISTENCY PROPAGATION (fixed-point, no branching)
# ==================================================
# Runs before any backtracking is attempted. For puzzles where the clue set
# is already tight enough to fully determine the solution (the common case,
# since generate_clues_async() adds clues until unique), this alone proves
# uniqueness with zero search. Backtracking only runs as a fallback, seeded
# from these already-reduced domains rather than the full 0..N range.
 
func _init_possibility_grid() -> Array:
    var grid: Array = []
    for i in star_count:
        var row: Array = []
        row.resize(star_count)
        for r in star_count:
            row[r] = true
        grid.append(row)
    return grid
 
 
func _expand_clues_to_cmp(clues: Array[Dictionary]) -> Array[Dictionary]:
    var expanded: Array[Dictionary] = []
    for clue in clues:
        match clue["kind"]:
            "ordinal_cmp":
                expanded.append({"a": clue["a"], "b": clue["b"], "a_gt_b": clue["a_gt_b"]})
            "ordinal_chain":
                # Three-star chain (lo < mid < hi) decomposes into two plain
                # ordinal_cmp arcs — the bound-propagation machinery below
                # needs no new logic, just two entries instead of one.
                expanded.append({"a": clue["mid"], "b": clue["a"], "a_gt_b": true})
                expanded.append({"a": clue["b"], "b": clue["mid"], "a_gt_b": true})
            "ordinal_group_cmp_color":
                # One clause, one arc per (subject, same-colored target) pair:
                # the color CATEGORY multiplies the constraint, and merged
                # multi-subject clues (see _merge_group_cmp_kind) multiply it
                # again per subject — every subject independently satisfies
                # the same "before/after every target" relation.
                var s_first: bool = clue["s_first"]
                for gs in clue["subjects"]:
                    for t in clue["targets"]:
                        if s_first:
                            expanded.append({"a": int(t), "b": int(gs), "a_gt_b": true})
                        else:
                            expanded.append({"a": int(gs), "b": int(t), "a_gt_b": true})
            "ordinal_group_cmp_tone":
                var s_first2: bool = clue["s_first"]
                for gs2 in clue["subjects"]:
                    for t in clue["targets"]:
                        if s_first2:
                            expanded.append({"a": int(t), "b": int(gs2), "a_gt_b": true})
                        else:
                            expanded.append({"a": int(gs2), "b": int(t), "a_gt_b": true})
            "ordinal_extreme":
                var s: int = clue["s"]
                var want_lowest: bool = clue["want_lowest"]
                for n in clue["neighbors"]:
                    if want_lowest:
                        expanded.append({"a": int(n), "b": s, "a_gt_b": true})
                    else:
                        expanded.append({"a": s, "b": int(n), "a_gt_b": true})
    return expanded
 
 
func _propagate(possible: Array, cmp_clues: Array[Dictionary], adj_clues: Array[Dictionary],
        count_clues: Array[Dictionary]) -> bool:
    # Arc-consistency fixed-point pass. Mutates `possible` in place.
    # Returns false immediately on contradiction (a star with zero remaining ranks).
    var changed: bool = true
    while changed:
        changed = false
 
        # --- Comparison arcs: bound propagation via min/max, O(star_count) per arc. ---
        for clue in cmp_clues:
            var a: int = clue["a"]
            var b: int = clue["b"]
            var a_gt_b: bool = clue["a_gt_b"]
            var hi: int = a if a_gt_b else b
            var lo: int = b if a_gt_b else a
 
            var min_lo: int = -1
            for r in star_count:
                if possible[lo][r]:
                    if min_lo == -1:
                        min_lo = r
            if min_lo == -1:
                return false
 
            for r in star_count:
                if possible[hi][r] and r <= min_lo:
                    possible[hi][r] = false
                    changed = true
 
            var min_hi: int = -1
            var max_hi: int = -1
            for r in star_count:
                if possible[hi][r]:
                    if min_hi == -1:
                        min_hi = r
                    max_hi = r
            if min_hi == -1:
                return false
 
            for r in star_count:
                if possible[lo][r] and r >= max_hi:
                    possible[lo][r] = false
                    changed = true
 
        # --- Offset arcs: a fires exactly `offset` steps after b. adj_seq
        # clues omit "offset" (defaults to 1, original behavior unchanged);
        # offset_seq clues carry an explicit arbitrary offset. ---
        for clue in adj_clues:
            var a2: int = clue["a"]
            var b2: int = clue["b"]
            var off: int = int(clue.get("offset", 1))
            for r in star_count:
                if possible[a2][r]:
                    var br: int = r - off
                    var supported: bool = br >= 0 and br < star_count and possible[b2][br]
                    if not supported:
                        possible[a2][r] = false
                        changed = true
            for r in star_count:
                if possible[b2][r]:
                    var ar: int = r + off
                    var supported2: bool = ar >= 0 and ar < star_count and possible[a2][ar]
                    if not supported2:
                        possible[b2][r] = false
                        changed = true
 
        # --- Cardinality arcs (count_before): exactly k of s's neighbors fire
        # before s. Two directions: (a) prune ranks of s where the achievable
        # before-count can't hit k; (b) once s is pinned, force or forbid the
        # straddling neighbors as the count demands. ---
        for clue in count_clues:
            var s3: int = clue["s"]
            var k3: int = clue["k"]
            var nbrs: Array = clue["neighbors"]
 
            for r in star_count:
                if not possible[s3][r]:
                    continue
                var must_before: int = 0
                var can_before: int = 0
                for n in nbrs:
                    var mn: int = star_count
                    var mx: int = -1
                    for rr in star_count:
                        if possible[int(n)][rr]:
                            if rr < mn:
                                mn = rr
                            if rr > mx:
                                mx = rr
                    if mx == -1:
                        return false
                    if mx < r:
                        must_before += 1
                        can_before += 1
                    elif mn < r:
                        can_before += 1
                if must_before > k3 or can_before < k3:
                    possible[s3][r] = false
                    changed = true
 
            var s_count: int = 0
            var s_rank: int = -1
            for r in star_count:
                if possible[s3][r]:
                    s_count += 1
                    s_rank = r
            if s_count == 0:
                return false
            if s_count == 1:
                var must_before2: int = 0
                var straddlers: Array = []
                for n in nbrs:
                    var mn2: int = star_count
                    var mx2: int = -1
                    for rr in star_count:
                        if possible[int(n)][rr]:
                            if rr < mn2:
                                mn2 = rr
                            if rr > mx2:
                                mx2 = rr
                    if mx2 == -1:
                        return false
                    if mx2 < s_rank:
                        must_before2 += 1
                    elif mn2 < s_rank and mx2 >= s_rank:
                        straddlers.append(int(n))
                if must_before2 > k3 or must_before2 + straddlers.size() < k3:
                    return false
                if must_before2 == k3:
                    for n2 in straddlers:
                        for rr in s_rank:
                            if possible[n2][rr]:
                                possible[n2][rr] = false
                                changed = true
                elif must_before2 + straddlers.size() == k3:
                    for n2 in straddlers:
                        for rr in range(s_rank, star_count):
                            if possible[n2][rr]:
                                possible[n2][rr] = false
                                changed = true
 
        # --- Alldiff / uniqueness projection: a singleton star claims its rank exclusively. ---
        for i in star_count:
            var count_i: int = 0
            var only_r: int = -1
            for r in star_count:
                if possible[i][r]:
                    count_i += 1
                    only_r = r
            if count_i == 0:
                return false
            if count_i == 1:
                for j in star_count:
                    if j != i and possible[j][only_r]:
                        possible[j][only_r] = false
                        changed = true
 
    return true
 
 
func _all_singleton(possible: Array) -> bool:
    for i in star_count:
        var count_i: int = 0
        for r in star_count:
            if possible[i][r]:
                count_i += 1
        if count_i != 1:
            return false
    return true
 
 
func _extract_singleton_solution(possible: Array) -> Array:
    var solution: Array = []
    solution.resize(star_count)
    for i in star_count:
        for r in star_count:
            if possible[i][r]:
                solution[i] = r
                break
    return solution
 
 
func _possible_to_domains(possible: Array) -> Array:
    var domains: Array = []
    for i in star_count:
        var d: Array = []
        for r in star_count:
            if possible[i][r]:
                d.append(r)
        domains.append(d)
    return domains
 
 
# ==================================================
# SOLVER — arc-consistency propagation, with MRV fallback
# ==================================================
# Internal representation during solving: domains is an Array[Array[int]]
# (mutable copy per recursion level), assignment is Array[int] (-1 = unset).
# Returns Array of solutions found (each solution is an Array[int]).
# Stops after `cap` solutions — generation only needs "unique" vs "not".
 
func _apply_exact_clues(possible: Array, clues: Array[Dictionary]) -> bool:
    for clue in clues:
        if clue["kind"] != "ordinal_exact":
            continue
        var s: int = clue["s"]
        var r: int = clue["r"]
        if not possible[s][r]:
            return false
        for rr in star_count:
            if rr != r:
                possible[s][rr] = false
    return true
 
 
func _apply_negative_clues(possible: Array, clues: Array[Dictionary]) -> bool:
    for clue in clues:
        match clue["kind"]:
            "ordinal_neg":
                var s: int = clue["s"]
                var r: int = clue["r"]
                possible[s][r] = false
            "proximity_neg_adjacent":
                var s2: int = clue["s"]
                var r2: int = clue["r"]
                for n in proximity[s2]:
                    possible[int(n)][r2] = false
            "ordinal_neither_nor":
                var ns1: int = clue["s1"]
                var ns2: int = clue["s2"]
                var nr: int = clue["r"]
                possible[ns1][nr] = false
                possible[ns2][nr] = false
            "unique_list_n":
                for part in clue["participants"]:
                    if int(part["cat"]) == Category.SEQUENCE:
                        if str(part.get("sign", "pos")) == "neg":
                            # Negative form: excludes 1-2 ranks from THIS
                            # star's own domain (same shape as ordinal_neg)
                            # rather than excluding others from one exact
                            # rank — there's no single "dr" to sweep with.
                            var neg_star: int = int(part["star"])
                            for er in part.get("excluded_ranks", []):
                                possible[neg_star][int(er)] = false
                            continue
                        var dr: int = int(part["rank"])
                        var seq_star: int = int(part["star"])
                        for other in clue["participants"]:
                            if int(other["star"]) == seq_star:
                                continue
                            possible[int(other["star"])][dr] = false
    for i in star_count:
        var any_possible: bool = false
        for r in star_count:
            if possible[i][r]:
                any_possible = true
                break
        if not any_possible:
            return false
    return true
 
 
func _apply_range_clues(possible: Array, clues: Array[Dictionary]) -> bool:
    for clue in clues:
        match str(clue.get("kind", "")):
            "ordinal_range":
                var s: int = clue["s"]
                var lo: int = clue["lo"]
                var hi: int = clue["hi"]
                for r in star_count:
                    if r < lo or r > hi:
                        possible[s][r] = false
            "ordinal_either_or":
                var es: int = clue["s"]
                var r1: int = clue["r1"]
                var r2: int = clue["r2"]
                for r in star_count:
                    if r != r1 and r != r2:
                        possible[es][r] = false
            "ordinal_unaligned":
                var us1: int = clue["s1"]
                var us2: int = clue["s2"]
                var ur1: int = clue["r1"]
                var ur2: int = clue["r2"]
                for r in star_count:
                    if r != ur1 and r != ur2:
                        possible[us1][r] = false
                        possible[us2][r] = false
    for i in star_count:
        var any_left: bool = false
        for r in star_count:
            if possible[i][r]:
                any_left = true
                break
        if not any_left:
            return false
    return true
 
 
func _validate_count_clues(solution: Array, count_clues: Array[Dictionary]) -> bool:
    for clue in count_clues:
        var s: int = clue["s"]
        var k: int = clue["k"]
        var before: int = 0
        for n in clue["neighbors"]:
            if int(solution[int(n)]) < int(solution[s]):
                before += 1
        if before != k:
            return false
    return true
 
 
func _solve(clues: Array[Dictionary], cap: int = 2, rank_restriction: Array = []) -> Array:
    var expanded_cmp: Array[Dictionary] = _expand_clues_to_cmp(clues)
    var adj_clues: Array[Dictionary] = []
    var count_clues: Array[Dictionary] = []
    for clue in clues:
        if clue["kind"] == "ordinal_adjacent" or clue["kind"] == "ordinal_offset":
            adj_clues.append(clue)
        elif clue["kind"] == "ordinal_count_before":
            count_clues.append(clue)
 
    var possible: Array = _init_possibility_grid()
    if not rank_restriction.is_empty():
        for i in star_count:
            for r in star_count:
                if not rank_restriction[i][r]:
                    possible[i][r] = false
    if not _apply_exact_clues(possible, clues):
        return []
    if not _apply_negative_clues(possible, clues):
        return []
    if not _apply_range_clues(possible, clues):
        return []
    var consistent: bool = _propagate(possible, expanded_cmp, adj_clues, count_clues)
    if not consistent:
        return []
    # Phase 4: layer naked-subset on top (Sequence is alldiff — sound, see
    # _naked_subset_pass's guard). Can only resolve MORE puzzles via pure
    # propagation than before, reducing how often the backtracking fallback
    # below is needed — never changes the correctness of what it proves.
    var nb_changed: bool = true
    while nb_changed:
        nb_changed = false
        if _naked_subset_pass(possible, star_count, true):
            nb_changed = true
            if not _propagate(possible, expanded_cmp, adj_clues, count_clues):
                return []

    if _all_singleton(possible):
        var sol: Array = _extract_singleton_solution(possible)
        if not _validate_count_clues(sol, count_clues):
            return []
        return [sol]
 
    var solutions: Array = []
    var assignment: Array = []
    assignment.resize(star_count)
    for i in star_count:
        assignment[i] = -1
 
    var init_domains: Array = _possible_to_domains(possible)
    _backtrack_nodes_remaining = MAX_BACKTRACK_NODES
    _backtrack_fc(assignment, init_domains, expanded_cmp, adj_clues, count_clues, solutions, cap)
    return solutions
 
 
func _backtrack_fc(assignment: Array, domains: Array,
        cmp_clues: Array[Dictionary], adj_clues: Array[Dictionary],
        count_clues: Array[Dictionary], solutions: Array, cap: int) -> void:
    if solutions.size() >= cap:
        return
    _backtrack_nodes_remaining -= 1
    if _backtrack_nodes_remaining <= 0:
        if _backtrack_nodes_remaining == 0:
            push_warning("ConstellationLogicPuzzle [%d]: backtracking node budget exhausted (sequence) — aborting search early." % constellation_id)
            _backtrack_nodes_remaining -= 1
        return
 
    var var_idx: int = -1
    var best_size: int = star_count + 1
    for i in star_count:
        if assignment[i] == -1:
            var sz: int = domains[i].size()
            if sz < best_size:
                best_size = sz
                var_idx = i
 
    if var_idx == -1:
        # Leaf: forward checking doesn't track cardinality constraints, so
        # every complete assignment must pass count validation here before
        # it counts as a solution.
        if _validate_count_clues(assignment, count_clues):
            solutions.append(assignment.duplicate())
        return
 
    for val in domains[var_idx]:
        assignment[var_idx] = val
        var new_doms_result = _forward_check(var_idx, val, domains, cmp_clues, adj_clues)
        if new_doms_result != null:
            _backtrack_fc(assignment, new_doms_result, cmp_clues, adj_clues, count_clues, solutions, cap)
        assignment[var_idx] = -1
        if solutions.size() >= cap:
            return
 
 
func _forward_check(var_idx: int, val: int, domains: Array,
        cmp_clues: Array[Dictionary], adj_clues: Array[Dictionary]):
    # Returns a new domains Array with propagated reductions, or null on wipeout.
    var nd: Array = []
    for i in star_count:
        nd.append(domains[i].duplicate())
    nd[var_idx] = [val]
 
    # Alldiff: remove val from all other unassigned domains.
    for i in star_count:
        if i != var_idx:
            var idx: int = nd[i].find(val)
            if idx != -1:
                nd[i].remove_at(idx)
                if nd[i].is_empty():
                    return null
 
    # Comparison propagation for cmp clues touching var_idx.
    for clue in cmp_clues:
        var a: int = clue["a"]
        var b: int = clue["b"]
        var a_gt_b: bool = clue["a_gt_b"]
        if a == var_idx:
            var new_b: Array = []
            for v in nd[b]:
                if a_gt_b and v < val:
                    new_b.append(v)
                elif not a_gt_b and v > val:
                    new_b.append(v)
            if new_b.is_empty():
                return null
            nd[b] = new_b
        elif b == var_idx:
            var new_a: Array = []
            for v in nd[a]:
                if a_gt_b and v > val:
                    new_a.append(v)
                elif not a_gt_b and v < val:
                    new_a.append(v)
            if new_a.is_empty():
                return null
            nd[a] = new_a
 
    # Offset propagation: clue's "a" fires exactly "offset" steps after "b"
    # (offset defaults to 1 for adj_seq, explicit for offset_seq).
    for clue in adj_clues:
        var a: int = clue["a"]
        var b: int = clue["b"]
        var off2: int = int(clue.get("offset", 1))
        if a == var_idx:
            var new_b: Array = []
            for v in nd[b]:
                if v == val - off2:
                    new_b.append(v)
            if new_b.is_empty():
                return null
            nd[b] = new_b
        elif b == var_idx:
            var new_a: Array = []
            for v in nd[a]:
                if v == val + off2:
                    new_a.append(v)
            if new_a.is_empty():
                return null
            nd[a] = new_a

    return nd
 
 
# ==================================================
# PITCH SOLVER — parallel CSP domain, NOT alldiff (pitch values may repeat)
# ==================================================
 
func _init_pitch_possibility_grid() -> Array:
    var grid: Array = []
    for i in star_count:
        var row: Array = []
        row.resize(pitch_count)
        for p in pitch_count:
            row[p] = true
        grid.append(row)
    return grid
 
 
func _apply_pitch_exact_clues(possible: Array, clues: Array[Dictionary]) -> bool:
    for clue in clues:
        if clue["kind"] != "tone_exact":
            continue
        var s: int = clue["s"]
        var p: int = clue["p"]
        if not possible[s][p]:
            return false
        for pp in pitch_count:
            if pp != p:
                possible[s][pp] = false
    return true
 
 
func _apply_pitch_negative_clues(possible: Array, clues: Array[Dictionary]) -> bool:
    for clue in clues:
        if clue["kind"] != "tone_neg":
            continue
        var s: int = clue["s"]
        for p in clue.get("p_list", []):
            possible[s][int(p)] = false
    for i in star_count:
        var any_possible: bool = false
        for p in pitch_count:
            if possible[i][p]:
                any_possible = true
                break
        if not any_possible:
            return false
    return true
 
 
func _expand_pitch_clues_to_cmp(clues: Array[Dictionary]) -> Array[Dictionary]:
    var expanded: Array[Dictionary] = []
    for clue in clues:
        match clue["kind"]:
            "tone_cmp":
                expanded.append({"a": clue["a"], "b": clue["b"], "rel": clue["rel"]})
            "tone_group_eq":
                # Chain of equality arcs; transitivity through propagation
                # makes the full group equal.
                var stars: Array = clue["stars"]
                for i in range(stars.size() - 1):
                    expanded.append({"a": int(stars[i]), "b": int(stars[i + 1]), "rel": "eq"})
            "tone_extreme":
                var s: int = clue["s"]
                var rel: String = "lt" if clue["want_lowest"] else "gt"
                for n in clue["neighbors"]:
                    expanded.append({"a": s, "b": int(n), "rel": rel})
            "tone_group_cmp_color":
                var rel2: String = "lt" if clue["s_lower"] else "gt"
                for s2 in clue["subjects"]:
                    for t in clue["targets"]:
                        expanded.append({"a": int(s2), "b": int(t), "rel": rel2})
    return expanded
 
 
func _propagate_pitch(possible: Array, cmp_clues: Array[Dictionary]) -> bool:
    # Arc-consistency for the Pitch domain. Unlike Sequence, pitch values are
    # NOT alldiff — multiple stars can legitimately share a pitch class — so
    # there is no singleton-claims-exclusivity projection step here. Equality
    # arcs ("plays the same note as") are a real constraint shape the
    # Sequence propagator never needs, since rank never ties.
    var changed: bool = true
    while changed:
        changed = false
 
        for clue in cmp_clues:
            var a: int = clue["a"]
            var b: int = clue["b"]
            var rel: String = clue["rel"]
 
            if rel == "eq":
                for p in pitch_count:
                    if possible[a][p] and not possible[b][p]:
                        possible[a][p] = false
                        changed = true
                for p in pitch_count:
                    if possible[b][p] and not possible[a][p]:
                        possible[b][p] = false
                        changed = true
                continue
 
            var hi: int = a if rel == "gt" else b
            var lo: int = b if rel == "gt" else a
 
            var min_lo_rank: int = -1
            for p in pitch_count:
                if possible[lo][p]:
                    var fr: int = _pitch_freq_rank[p]
                    if min_lo_rank == -1 or fr < min_lo_rank:
                        min_lo_rank = fr
            if min_lo_rank == -1:
                return false
            for p in pitch_count:
                if possible[hi][p] and _pitch_freq_rank[p] <= min_lo_rank:
                    possible[hi][p] = false
                    changed = true
 
            var max_hi_rank: int = -1
            for p in pitch_count:
                if possible[hi][p]:
                    var fr2: int = _pitch_freq_rank[p]
                    if fr2 > max_hi_rank:
                        max_hi_rank = fr2
            if max_hi_rank == -1:
                return false
            for p in pitch_count:
                if possible[lo][p] and _pitch_freq_rank[p] >= max_hi_rank:
                    possible[lo][p] = false
                    changed = true
 
    return true
 
 
func _all_pitch_singleton(possible: Array) -> bool:
    for i in star_count:
        var count_i: int = 0
        for p in pitch_count:
            if possible[i][p]:
                count_i += 1
        if count_i != 1:
            return false
    return true
 
 
func _extract_pitch_singleton_solution(possible: Array) -> Array:
    var solution: Array = []
    solution.resize(star_count)
    for i in star_count:
        for p in pitch_count:
            if possible[i][p]:
                solution[i] = p
                break
    return solution


func _explain_pitch_propagation(clues: Array[Dictionary]) -> Dictionary:
    var expanded_cmp: Array[Dictionary] = _expand_pitch_clues_to_cmp(clues)
    var possible: Array = _init_pitch_possibility_grid()
    _apply_pitch_exact_clues(possible, clues)
    _apply_pitch_negative_clues(possible, clues)

    var step_log: Array = []
    var changed: bool = true
    while changed:
        changed = false
        for clue in expanded_cmp:
            var a: int = clue["a"]
            var b: int = clue["b"]
            var rel: String = clue["rel"]
            var before_a: int = _pitch_domain_size(possible, a)
            var before_b: int = _pitch_domain_size(possible, b)

            if rel == "eq":
                for p in pitch_count:
                    if possible[a][p] and not possible[b][p]:
                        possible[a][p] = false
                        changed = true
                for p in pitch_count:
                    if possible[b][p] and not possible[a][p]:
                        possible[b][p] = false
                        changed = true
            else:
                var hi: int = a if rel == "gt" else b
                var lo: int = b if rel == "gt" else a
                var min_lo_rank: int = _pitch_min_possible_rank(possible, lo)
                if min_lo_rank == -1:
                    return {"contradiction": true, "step_log": step_log}
                for p in pitch_count:
                    if possible[hi][p] and _pitch_freq_rank[p] <= min_lo_rank:
                        possible[hi][p] = false
                        changed = true
                var max_hi_rank: int = _pitch_max_possible_rank(possible, hi)
                if max_hi_rank == -1:
                    return {"contradiction": true, "step_log": step_log}
                for p in pitch_count:
                    if possible[lo][p] and _pitch_freq_rank[p] >= max_hi_rank:
                        possible[lo][p] = false
                        changed = true

            var after_a: int = _pitch_domain_size(possible, a)
            var after_b: int = _pitch_domain_size(possible, b)
            if after_a < before_a or after_b < before_b:
                step_log.append({"clue": clue, "star_a": a, "narrowed_a": before_a - after_a,
                    "star_b": b, "narrowed_b": before_b - after_b})

    var resolved: Array = []
    var unresolved: Array = []
    for s in star_count:
        if _pitch_domain_size(possible, s) == 1:
            resolved.append(s)
        else:
            unresolved.append(s)

    return {"contradiction": false, "resolved_via_propagation": resolved,
        "unresolved_after_propagation": unresolved, "step_log": step_log,
        "step_count": step_log.size()}


func _pitch_domain_size(possible: Array, star: int) -> int:
    var count: int = 0
    for p in pitch_count:
        if possible[star][p]:
            count += 1
    return count


func _pitch_min_possible_rank(possible: Array, star: int) -> int:
    var m: int = -1
    for p in pitch_count:
        if possible[star][p]:
            var fr: int = _pitch_freq_rank[p]
            if m == -1 or fr < m:
                m = fr
    return m


func _pitch_max_possible_rank(possible: Array, star: int) -> int:
    var m: int = -1
    for p in pitch_count:
        if possible[star][p]:
            var fr: int = _pitch_freq_rank[p]
            if fr > m:
                m = fr
    return m


func _pitch_possible_to_domains(possible: Array) -> Array:
    var domains: Array = []
    for i in star_count:
        var d: Array = []
        for p in pitch_count:
            if possible[i][p]:
                d.append(p)
        domains.append(d)
    return domains
 
 
func _possibility_grid_for_pitch_clues(clues: Array[Dictionary]):
    # Pitch-axis mirror of _possibility_grid_for_clues: front-end of
    # _solve_pitch (clue application + arc-consistency) without backtracking.
    var expanded_pcmp: Array[Dictionary] = _expand_pitch_clues_to_cmp(clues)
    var possible: Array = _init_pitch_possibility_grid()
    if not _apply_pitch_exact_clues(possible, clues):
        return null
    if not _apply_pitch_negative_clues(possible, clues):
        return null
    if not _propagate_pitch(possible, expanded_pcmp):
        return null
    return possible
 
 
func _possibility_grid_for_clues(clues: Array[Dictionary]):
    # Sequence-axis mirror of _possibility_grid_for_pitch_clues: front-end of
    # _solve (clue application + arc-consistency) without backtracking.
    var expanded_cmp: Array[Dictionary] = _expand_clues_to_cmp(clues)
    var adj_clues: Array[Dictionary] = []
    var count_clues: Array[Dictionary] = []
    for clue in clues:
        if clue["kind"] == "ordinal_adjacent" or clue["kind"] == "ordinal_offset":
            adj_clues.append(clue)
        elif clue["kind"] == "ordinal_count_before":
            count_clues.append(clue)

    var possible: Array = _init_possibility_grid()
    if not _apply_exact_clues(possible, clues):
        return null
    if not _apply_negative_clues(possible, clues):
        return null
    if not _apply_range_clues(possible, clues):
        return null
    # Phase 4: layer naked-subset (Sequence is alldiff, so this is sound —
    # see _naked_subset_pass's guard) on top of the legacy _propagate,
    # alternating until both reach a joint fixed point. _propagate already
    # handles cardinality (ordinal_count_before) correctly and runs to its
    # own fixed point first every time; naked-subset only ever runs on an
    # already-legacy-converged grid, so this can only find MORE valid
    # eliminations than before, never fewer or unsound ones.
    var nb_changed: bool = true
    while nb_changed:
        nb_changed = false
        if not _propagate(possible, expanded_cmp, adj_clues, count_clues):
            return null
        if _naked_subset_pass(possible, star_count, true):
            nb_changed = true
    return possible


func _remaining_entropy_for_clues(clues: Array[Dictionary]) -> float:
    var possible = _possibility_grid_for_clues(clues)
    if possible == null:
        return -1.0
    var entropy: float = 0.0
    for s in star_count:
        var domain_size: int = 0
        for r in star_count:
            if possible[s][r]:
                domain_size += 1
        if domain_size == 0:
            return -1.0
        entropy += log(float(domain_size)) / log(2.0)
    return entropy


func _remaining_entropy_for_pitch_clues(clues: Array[Dictionary]) -> float:
    var possible = _possibility_grid_for_pitch_clues(clues)
    if possible == null:
        return -1.0
    var entropy: float = 0.0
    for s in star_count:
        var domain_size: int = 0
        for p in pitch_count:
            if possible[s][p]:
                domain_size += 1
        if domain_size == 0:
            return -1.0
        entropy += log(float(domain_size)) / log(2.0)
    return entropy
 
 
## _rank_restriction_from_pitch_clues/_pitch_restriction_from_rank_clues were
## removed in Phase 4 of the 2026-07-18 refactor. Phase 2 had already fixed
## them to always return the fully-unrestricted grid — Pitch and Sequence
## are independently-seeded, uncorrelated axes (verified: star_pitch_index
## uses a separate RNG stream from pitch_rank_solution — see setup()), so no
## sound restriction between them was ever derivable without an explicit
## bridging clue, and any such clue is already a normal member of its own
## axis's clue set. With both functions permanently no-ops, their only call
## site (the cross-trim loop below) now passes [] directly — equivalent,
## and skips rebuilding a full unrestricted grid every round for nothing.
## See constellation_puzzle_csp_review_findings memory for the original bug
## this fixed (ground truth leaking into clue-trimming decisions).


# ==================================================
# UNIFIED CATEGORY GRID (Phase 3 of the 2026-07-18 refactor) — ADDITIVE.
# ==================================================
# One shared, generic engine for all 5 puzzle categories, replacing the
# pattern of maintaining near-duplicate propagators per axis (_propagate vs
# _propagate_pitch) and treating Color/Proximity as untracked side data.
# Not yet wired into generate_clues_async() — this section is self-contained
# and can be exercised/verified independently before Phase 4 migrates the
# live entropy/trim pipeline onto it.
#
# Two dimensions distinguish the 5 categories, and this section keeps them
# separate on purpose (established across the design conversation preceding
# this refactor):
#   (1) WHEN the player learns a star's value without solving: Color and
#       Degree/Proximity are painted on the map at a glance; Pitch is
#       revealed via listening OR deduced; Name and Sequence are only ever
#       deduced.
#   (2) Value SCARCITY structure (how many stars share a given value) is
#       universal across all 5 categories, not just the 3 "unsolved" ones —
#       Color and Degree have real scarce/common value splits too (verified
#       via _assign_colors_balanced()'s uneven leftover distribution and the
#       naturally skewed degree distributions read from line_pairs).
#
# CRITICAL BOUNDARY: this section has two kinds of function, and they must
# never be mixed. "Live domain" functions (_init_category_grid,
# _propagate_category, _naked_subset_pass) work ONLY from clue-derived
# possibility grids — never ground truth — and are safe to use for
# solve-time uniqueness verification. "Ground truth" functions
# (_category_ground_truth_value, _category_value_group_sizes) exist only for
# GENERATION-TIME clue-authoring and difficulty/entropy scoring, exactly
# like every existing pool-builder already reads star_colors/
# pitch_rank_solution/etc. to write truthful clue text. Using a ground-truth
# function's output to narrow a live possibility grid during trimming or
# uniqueness-checking would reintroduce the exact leak fixed in Phase 2.

enum Category { NAME, PITCH, SEQUENCE, COLOR, DEGREE }


func _category_domain_size(cat: int) -> int:
    match cat:
        Category.NAME, Category.SEQUENCE:
            return star_count
        Category.PITCH:
            return pitch_count
        Category.COLOR:
            return 4
        Category.DEGREE:
            return _max_degree + 1
    return 0


func _category_is_alldiff(cat: int) -> bool:
    return cat == Category.NAME or cat == Category.SEQUENCE


func _init_category_grid(cat: int) -> Array:
    var size: int = _category_domain_size(cat)
    var grid: Array = []
    for i in star_count:
        var row: Array = []
        row.resize(size)
        for v in size:
            row[v] = true
        grid.append(row)
    return grid


func _init_color_grid() -> Array:
    # Color is known from generation (painted on the map) — its grid starts
    # pre-collapsed to the singleton truth, same shape as any other category,
    # so the generic engine below never needs to special-case it.
    var grid: Array = _init_category_grid(Category.COLOR)
    for i in star_count:
        for v in 4:
            grid[i][v] = (v == star_colors[i])
    return grid


func _init_degree_grid() -> Array:
    # Degree stands in for the "Proximity" category's scalar, scarcity-
    # carrying value (see design conversation — hop-distance is pairwise,
    # not a single per-star value, so Degree is what gets a category slot).
    var grid: Array = _init_category_grid(Category.DEGREE)
    for i in star_count:
        for v in (_max_degree + 1):
            grid[i][v] = (v == star_degrees[i])
    return grid


func _value_rank(v: int, value_rank: Array) -> int:
    # value_rank remaps a raw domain index to a comparable ordering — needed
    # for Pitch (class index vs frequency rank); pass [] for categories
    # where the raw index already IS the comparable order (Sequence, Degree).
    if value_rank.is_empty():
        return v
    return value_rank[v]


func _category_domain_min_rank(grid: Array, dot: int, domain_size: int, value_rank: Array) -> int:
    var m: int = -1
    for v in domain_size:
        if grid[dot][v]:
            var r: int = _value_rank(v, value_rank)
            if m == -1 or r < m:
                m = r
    return m


func _category_domain_max_rank(grid: Array, dot: int, domain_size: int, value_rank: Array) -> int:
    var m: int = -1
    for v in domain_size:
        if grid[dot][v]:
            var r: int = _value_rank(v, value_rank)
            if r > m:
                m = r
    return m


func _naked_subset_pass(grid: Array, domain_size: int, alldiff: bool) -> bool:
    # Naked pair/triple elimination, generalizing the singleton-only
    # "alldiff claims exclusivity" projection already used elsewhere in this
    # file (K=1). If exactly K dots' remaining domains are all subsets of
    # the SAME K-sized value set, those K values are used up by exactly
    # those K dots and can be eliminated from every other dot's domain.
    # Bounded to K=2 (pairs) and K=3 (triples) — an exhaustive K=2..N search
    # is combinatorially expensive for no practical benefit; pairs/triples
    # catch the overwhelming majority of real cases in logic-grid solving.
    #
    # SOUNDNESS REQUIRES alldiff: the "K values are used up by exactly K
    # dots" argument only holds when each value can be claimed by at most
    # one dot. For a non-alldiff domain (Pitch, Color, Degree — multiple
    # dots CAN legitimately share a value), this technique is simply wrong:
    # a third dot sharing the same pitch as two others is completely valid,
    # and eliminating it would falsely rule out a real possibility. Guarded
    # here, not just at the call site, so misuse fails safe rather than
    # silently over-eliminating.
    if not alldiff:
        return false
    var changed_any: bool = false
    var domains: Array = []
    for d in star_count:
        var dom: Array = []
        for v in domain_size:
            if grid[d][v]:
                dom.append(v)
        domains.append(dom)

    # Naked pairs: two different dots share the identical 2-value domain.
    for d1 in star_count:
        if domains[d1].size() != 2:
            continue
        for d2 in range(d1 + 1, star_count):
            if domains[d2].size() != 2:
                continue
            if domains[d1][0] != domains[d2][0] or domains[d1][1] != domains[d2][1]:
                continue
            var v1: int = domains[d1][0]
            var v2: int = domains[d1][1]
            for d3 in star_count:
                if d3 == d1 or d3 == d2:
                    continue
                if grid[d3][v1]:
                    grid[d3][v1] = false
                    domains[d3].erase(v1)
                    changed_any = true
                if grid[d3][v2]:
                    grid[d3][v2] = false
                    domains[d3].erase(v2)
                    changed_any = true

    # Naked triples: three dots whose domains (each size 2 or 3) union to
    # exactly one 3-value set.
    for d1 in star_count:
        if domains[d1].size() < 2 or domains[d1].size() > 3:
            continue
        for d2 in range(d1 + 1, star_count):
            if domains[d2].size() < 2 or domains[d2].size() > 3:
                continue
            for d3 in range(d2 + 1, star_count):
                if domains[d3].size() < 2 or domains[d3].size() > 3:
                    continue
                var union_vals: Dictionary = {}
                for v in domains[d1]:
                    union_vals[v] = true
                for v in domains[d2]:
                    union_vals[v] = true
                for v in domains[d3]:
                    union_vals[v] = true
                if union_vals.size() != 3:
                    continue
                for d4 in star_count:
                    if d4 == d1 or d4 == d2 or d4 == d3:
                        continue
                    for v in union_vals.keys():
                        if grid[d4][v]:
                            grid[d4][v] = false
                            domains[d4].erase(v)
                            changed_any = true
    return changed_any


## ── Decomposed single-pass primitives (no internal while-loop, no
## contradiction check) — each does ONE round of narrowing and reports
## whether anything changed. _propagate_unified() below combines these into
## ONE joint fixed-point loop across ALL 5 categories at once, instead of
## converging each category separately and freezing it before the next
## starts. This is what actually lets a clue touching multiple categories
## (e.g. "Selion is more distant from Keriion than the 4th note star" — a
## Name constraint, anchored by a Sequence-picked reference, evaluated via
## Distance) be processed as one joint constraint rather than forced into a
## single "home axis" bucket the way _kind_home_array() does today.

func _apply_direct_category_arcs_once(grid: Array, domain_size: int,
        cmp_arcs: Array, eq_arcs: Array, offset_arcs: Array,
        value_rank: Array = []) -> bool:
    # One round of bound-consistency for arcs BOTH of whose endpoints are
    # dot indices within the SAME category's own domain (Sequence-Sequence,
    # Pitch-Pitch) — the shape _propagate/_propagate_pitch each implemented
    # separately. Returns false immediately on contradiction.
    var changed: bool = false

    for arc in cmp_arcs:
        var a: int = arc["a"]
        var b: int = arc["b"]
        var a_gt_b: bool = arc["a_gt_b"]
        var hi: int = a if a_gt_b else b
        var lo: int = b if a_gt_b else a

        var min_lo: int = _category_domain_min_rank(grid, lo, domain_size, value_rank)
        if min_lo == -1:
            return false
        for v in domain_size:
            if grid[hi][v] and _value_rank(v, value_rank) <= min_lo:
                grid[hi][v] = false
                changed = true

        var max_hi: int = _category_domain_max_rank(grid, hi, domain_size, value_rank)
        if max_hi == -1:
            return false
        for v in domain_size:
            if grid[lo][v] and _value_rank(v, value_rank) >= max_hi:
                grid[lo][v] = false
                changed = true

    for arc in eq_arcs:
        var a2: int = arc["a"]
        var b2: int = arc["b"]
        for v in domain_size:
            if grid[a2][v] and not grid[b2][v]:
                grid[a2][v] = false
                changed = true
        for v in domain_size:
            if grid[b2][v] and not grid[a2][v]:
                grid[b2][v] = false
                changed = true

    for arc in offset_arcs:
        var oa: int = arc["a"]
        var ob: int = arc["b"]
        var off: int = int(arc.get("offset", 1))
        for v in domain_size:
            if grid[oa][v]:
                var bv: int = v - off
                var supported: bool = bv >= 0 and bv < domain_size and grid[ob][bv]
                if not supported:
                    grid[oa][v] = false
                    changed = true
        for v in domain_size:
            if grid[ob][v]:
                var av: int = v + off
                var supported2: bool = av >= 0 and av < domain_size and grid[oa][av]
                if not supported2:
                    grid[ob][v] = false
                    changed = true

    return changed


func _apply_alldiff_projection_once(grid: Array, domain_size: int) -> bool:
    # Singleton-claims-exclusivity: reusable for BOTH Sequence and Name
    # (both alldiff), a single round.
    var changed: bool = false
    for i in star_count:
        var count_i: int = 0
        var only_v: int = -1
        for v in domain_size:
            if grid[i][v]:
                count_i += 1
                only_v = v
        if count_i == 1:
            for j in star_count:
                if j != i and grid[j][only_v]:
                    grid[j][only_v] = false
                    changed = true
    return changed


func _apply_cardinality_arcs_once(grid: Array, count_clues: Array) -> int:
    # Cardinality constraint (ordinal_count_before: "exactly k of s's
    # neighbors fire before s"). Ported verbatim from the legacy
    # _propagate's count_clues handling — Sequence-only, since this clue
    # kind doesn't exist on any other category. Closes the KNOWN GAP
    # _propagate_unified previously had (documented in
    # _verify_unified_grid_matches_legacy — puzzles containing
    # ordinal_count_before reported a false mismatch there, harmlessly,
    # since the live pipeline's _solve() always applied it correctly via
    # the untouched legacy _propagate; this makes the unified engine a
    # genuinely complete replacement instead of relying on that fallback).
    # Returns -1 on contradiction, 1 if anything changed, 0 otherwise —
    # tri-state instead of bool because a wipeout here must be reported
    # immediately, the same way the legacy code returns false mid-loop.
    var changed: bool = false
    for clue in count_clues:
        var s3: int = clue["s"]
        var k3: int = clue["k"]
        var nbrs: Array = clue["neighbors"]

        for r in star_count:
            if not grid[s3][r]:
                continue
            var must_before: int = 0
            var can_before: int = 0
            for n in nbrs:
                var mn: int = star_count
                var mx: int = -1
                for rr in star_count:
                    if grid[int(n)][rr]:
                        if rr < mn:
                            mn = rr
                        if rr > mx:
                            mx = rr
                if mx == -1:
                    return -1
                if mx < r:
                    must_before += 1
                    can_before += 1
                elif mn < r:
                    can_before += 1
            if must_before > k3 or can_before < k3:
                grid[s3][r] = false
                changed = true

        var s_count: int = 0
        var s_rank: int = -1
        for r in star_count:
            if grid[s3][r]:
                s_count += 1
                s_rank = r
        if s_count == 0:
            return -1
        if s_count == 1:
            var must_before2: int = 0
            var straddlers: Array = []
            for n in nbrs:
                var mn2: int = star_count
                var mx2: int = -1
                for rr in star_count:
                    if grid[int(n)][rr]:
                        if rr < mn2:
                            mn2 = rr
                        if rr > mx2:
                            mx2 = rr
                if mx2 == -1:
                    return -1
                if mx2 < s_rank:
                    must_before2 += 1
                elif mn2 < s_rank and mx2 >= s_rank:
                    straddlers.append(int(n))
            if must_before2 > k3 or must_before2 + straddlers.size() < k3:
                return -1
            if must_before2 == k3:
                for n2 in straddlers:
                    for rr in s_rank:
                        if grid[n2][rr]:
                            grid[n2][rr] = false
                            changed = true
            elif must_before2 + straddlers.size() == k3:
                for n2 in straddlers:
                    for rr in range(s_rank, star_count):
                        if grid[n2][rr]:
                            grid[n2][rr] = false
                            changed = true
    return 1 if changed else 0


func _category_has_empty_domain(grid: Array, domain_size: int) -> bool:
    for i in star_count:
        var any_left: bool = false
        for v in domain_size:
            if grid[i][v]:
                any_left = true
                break
        if not any_left:
            return true
    return false


## ── Cross-category ("Name-indirect") arcs — one side (or both) is a NAME
## SLOT, not a direct dot index. Name's domain values ARE dot identities
## (grid[dot][slot] — "could this dot hold this name"), fundamentally
## different from Pitch/Sequence/Color/Degree's domains (direct attribute
## values of a KNOWN dot) — so evaluating a Name-side endpoint requires
## resolving which candidate dots the slot could still refer to, then
## checking the OTHER endpoint's constraint using each candidate's OWN
## domain in whatever category that endpoint specifies. This generalizes
## the Phase 2 _name_arc_predicate pattern (kept untouched, still backing
## live production _solve_names()) to arbitrary category pairs and adds a
## Distance relation as a first-class arc kind rather than folding it into
## a per-star "Proximity" domain (Distance is inherently pairwise; Degree
## remains the actual per-star Proximity domain value, for the cases where
## a scalar genuinely fits — see design conversation).
func _cross_arc_predicate(arc: Dictionary, d1: int, d2: int, grids: Dictionary) -> bool:
    match str(arc["kind"]):
        "ordinal_cmp":
            var a_gt_b: bool = arc["a_gt_b"]
            var seq_grid: Array = grids[Category.SEQUENCE]
            if a_gt_b:
                return _category_domain_max_rank(seq_grid, d1, star_count, []) > _category_domain_min_rank(seq_grid, d2, star_count, [])
            else:
                return _category_domain_min_rank(seq_grid, d1, star_count, []) < _category_domain_max_rank(seq_grid, d2, star_count, [])
        "ordinal_adjacent":
            var seq_grid2: Array = grids[Category.SEQUENCE]
            for r2 in star_count:
                if seq_grid2[d2][r2] and r2 + 1 < star_count and seq_grid2[d1][r2 + 1]:
                    return true
            return false
        "ordinal_offset":
            var seq_grid3: Array = grids[Category.SEQUENCE]
            var off: int = int(arc["offset"])
            for r2 in star_count:
                if seq_grid3[d2][r2]:
                    var r1: int = r2 + off
                    if r1 >= 0 and r1 < star_count and seq_grid3[d1][r1]:
                        return true
            return false
        "tone_cmp":
            var pitch_grid: Array = grids[Category.PITCH]
            var rel: String = arc["rel"]
            if rel == "eq":
                for p in pitch_count:
                    if pitch_grid[d1][p] and pitch_grid[d2][p]:
                        return true
                return false
            elif rel == "gt":
                return _pitch_max_possible_rank(pitch_grid, d1) > _pitch_min_possible_rank(pitch_grid, d2)
            else:
                return _pitch_min_possible_rank(pitch_grid, d1) < _pitch_max_possible_rank(pitch_grid, d2)
        "proximity_dist_label":
            # Structural distance between two fixed dots — legitimate,
            # like color/degree, no ground-truth unknown involved.
            return _distances[d1][d2] == int(arc["dist"])
        "proximity_dist_cmp_name":
            # "n1 is MORE/LESS distant from n2 than a FIXED reference dot
            # is from n2" — the reference dot is baked in at generation
            # time from ground truth (same pattern as ordinal_group_cmp_
            # color's "targets" list), so evaluating it here is purely
            # structural (_distances lookup), never a live unknown.
            var ref_dot: int = int(arc["ref_dot"])
            var want_more: bool = bool(arc["want_more"])
            if want_more:
                return _distances[d1][d2] > _distances[ref_dot][d2]
            else:
                return _distances[d1][d2] < _distances[ref_dot][d2]
    return true


func _apply_cross_arcs_once(name_grid: Array, arcs: Array, grids: Dictionary) -> bool:
    var changed: bool = false
    for arc in arcs:
        var n1: int = arc["n1"]
        var n2: int = arc["n2"]
        for d1 in star_count:
            if not name_grid[d1][n1]:
                continue
            var supported: bool = false
            for d2 in star_count:
                if name_grid[d2][n2] and _cross_arc_predicate(arc, d1, d2, grids):
                    supported = true
                    break
            if not supported:
                name_grid[d1][n1] = false
                changed = true
        for d2 in star_count:
            if not name_grid[d2][n2]:
                continue
            var supported2: bool = false
            for d1 in star_count:
                if name_grid[d1][n1] and _cross_arc_predicate(arc, d1, d2, grids):
                    supported2 = true
                    break
            if not supported2:
                name_grid[d2][n2] = false
                changed = true
    return changed


func _propagate_unified(grids: Dictionary,
        seq_cmp_arcs: Array, seq_offset_arcs: Array,
        pitch_cmp_arcs: Array, pitch_eq_arcs: Array,
        cross_arcs: Array, enable_naked_subset: bool = true,
        seq_count_clues: Array = []) -> bool:
    # ONE combined fixed-point loop across all 5 categories, replacing the
    # pattern of converging Sequence, then Pitch, then Name as three
    # separate, sequentially-frozen passes. `grids` is a Dictionary keyed
    # by Category enum value -> that category's possibility grid; all 5
    # must be present (Color/Degree typically pre-collapsed singletons via
    # _init_color_grid()/_init_degree_grid()).
    #
    # seq_count_clues: ordinal_count_before cardinality constraints — was a
    # documented gap here (2026-07-18), closed via _apply_cardinality_arcs_once.
    var seq_grid: Array = grids[Category.SEQUENCE]
    var pitch_grid: Array = grids[Category.PITCH]
    var name_grid: Array = grids[Category.NAME]

    var changed: bool = true
    while changed:
        changed = false

        if _apply_direct_category_arcs_once(seq_grid, star_count, seq_cmp_arcs, [], seq_offset_arcs, []):
            changed = true
        if pitch_count > 0 and _apply_direct_category_arcs_once(pitch_grid, pitch_count, pitch_cmp_arcs, pitch_eq_arcs, [], _pitch_freq_rank):
            changed = true

        if not seq_count_clues.is_empty():
            var card_result: int = _apply_cardinality_arcs_once(seq_grid, seq_count_clues)
            if card_result == -1:
                return false
            elif card_result == 1:
                changed = true

        if _apply_alldiff_projection_once(seq_grid, star_count):
            changed = true
        if _apply_alldiff_projection_once(name_grid, star_count):
            changed = true

        if _apply_cross_arcs_once(name_grid, cross_arcs, grids):
            changed = true

        if enable_naked_subset:
            for cat in grids.keys():
                if not _category_is_alldiff(cat):
                    continue   # sound only for Sequence/Name — see _naked_subset_pass
                var g: Array = grids[cat]
                var size: int = _category_domain_size(cat)
                if _naked_subset_pass(g, size, true):
                    changed = true

        for cat in grids.keys():
            if cat == Category.PITCH and pitch_count == 0:
                continue   # domain_size 0 means "no pitch data", not "every star impossible"
            if _category_has_empty_domain(grids[cat], _category_domain_size(cat)):
                return false

    return true


## _category_ground_truth_value / _category_value_group_sizes deleted
## 2026-07-19 — their only caller was _sample_unique_list_n's old
## singleton-only Color/Degree/Pitch participant selection, which was
## replaced with plain per-star sampling (no singleton requirement — see
## _sample_unique_list_n's doc comment for why that was never actually
## needed for solving correctness).


func _verify_unified_grid_matches_legacy(seq_clues: Array[Dictionary], pitch_clues: Array[Dictionary]) -> Dictionary:
    # Manual cross-check, not wired into generation: confirms
    # _propagate_unified (naked-subset DISABLED, so this is an apples-to-
    # apples comparison) reaches the identical Sequence/Pitch possibility
    # grids as the existing, independently-implemented _propagate/
    # _propagate_pitch for the same clue set. Call this by hand (e.g. from
    # a debug console or a temporary print in generate_clues_async) against
    # a real generated puzzle's chosen/pitch_chosen before Phase 4 migrates
    # anything onto the new engine. ordinal_count_before (cardinality)
    # clues are now fully supported via _apply_cardinality_arcs_once — this
    # used to be a documented gap reported as an expected mismatch here;
    # it's closed as of 2026-07-18. Name-axis cross-arc predicates are
    # checked separately by _verify_cross_arc_predicates_match_legacy,
    # since the unified engine's Name handling only covers the arc layer so
    # far — the single-dot filters (_apply_one_name_filter) aren't merged
    # into it yet; that's remaining Phase 4 work.
    var report: Dictionary = {"sequence_matches": true, "pitch_matches": true, "mismatches": []}

    var legacy_seq = _possibility_grid_for_clues(seq_clues)
    var seq_cmp_arcs: Array = _expand_clues_to_cmp(seq_clues)
    var seq_offset_arcs: Array = []
    var seq_count_clues: Array = []
    for clue in seq_clues:
        if clue["kind"] == "ordinal_adjacent" or clue["kind"] == "ordinal_offset":
            seq_offset_arcs.append(clue)
        elif clue["kind"] == "ordinal_count_before":
            seq_count_clues.append(clue)

    var pitch_cmp_arcs: Array = []
    var pitch_eq_arcs: Array = []
    if pitch_count > 0:
        # _expand_pitch_clues_to_cmp uses a {"a","b","rel":"eq"|"gt"|"lt"}
        # shape — split into _propagate_unified's separate cmp_arcs
        # ({"a","b","a_gt_b"}) and eq_arcs ({"a","b"}) forms.
        for arc in _expand_pitch_clues_to_cmp(pitch_clues):
            var rel: String = str(arc["rel"])
            if rel == "eq":
                pitch_eq_arcs.append({"a": arc["a"], "b": arc["b"]})
            else:
                pitch_cmp_arcs.append({"a": arc["a"], "b": arc["b"], "a_gt_b": (rel == "gt")})

    # NOTE: deliberately untyped (no ": Array") — a variable explicitly
    # typed as Array cannot be reassigned null in GDScript.
    var new_seq = _init_category_grid(Category.SEQUENCE)
    var new_pitch = _init_category_grid(Category.PITCH)
    var contradiction: bool = false
    if not _apply_exact_clues(new_seq, seq_clues) or not _apply_negative_clues(new_seq, seq_clues) or not _apply_range_clues(new_seq, seq_clues):
        contradiction = true
    if pitch_count > 0 and (not _apply_pitch_exact_clues(new_pitch, pitch_clues) or not _apply_pitch_negative_clues(new_pitch, pitch_clues)):
        contradiction = true

    if not contradiction:
        var grids: Dictionary = {
            Category.SEQUENCE: new_seq,
            Category.PITCH: new_pitch,
            Category.NAME: _init_category_grid(Category.NAME),
            Category.COLOR: _init_color_grid(),
            Category.DEGREE: _init_degree_grid(),
        }
        # Phase 4: naked-subset is now ENABLED on both sides of this
        # comparison — _possibility_grid_for_clues (the "legacy" baseline
        # below) was updated in Phase 4 to layer naked-subset on top of
        # _propagate too, so disabling it here would compare an outdated
        # legacy behavior against the new engine and falsely report
        # mismatches. Pitch is unaffected either way (never alldiff, so
        # _propagate_unified's per-category naked-subset loop always skips
        # it regardless of this flag).
        if not _propagate_unified(grids, seq_cmp_arcs, seq_offset_arcs, pitch_cmp_arcs, pitch_eq_arcs, [], true, seq_count_clues):
            contradiction = true
        new_seq = grids[Category.SEQUENCE]
        new_pitch = grids[Category.PITCH]

    if (legacy_seq == null) != contradiction:
        report["sequence_matches"] = false
        report["mismatches"].append("sequence: contradiction mismatch (legacy_null=%s new_contradiction=%s)" % [str(legacy_seq == null), str(contradiction)])
    elif legacy_seq != null and not contradiction:
        for i in star_count:
            for v in star_count:
                if legacy_seq[i][v] != new_seq[i][v]:
                    report["sequence_matches"] = false
                    report["mismatches"].append("sequence[%d][%d]: legacy=%s new=%s" % [i, v, str(legacy_seq[i][v]), str(new_seq[i][v])])

    if pitch_count > 0:
        var legacy_pitch = _possibility_grid_for_pitch_clues(pitch_clues)
        if (legacy_pitch == null) != contradiction:
            report["pitch_matches"] = false
            report["mismatches"].append("pitch: contradiction mismatch (legacy_null=%s new_contradiction=%s)" % [str(legacy_pitch == null), str(contradiction)])
        elif legacy_pitch != null and not contradiction:
            for i in star_count:
                for v in pitch_count:
                    if legacy_pitch[i][v] != new_pitch[i][v]:
                        report["pitch_matches"] = false
                        report["mismatches"].append("pitch[%d][%d]: legacy=%s new=%s" % [i, v, str(legacy_pitch[i][v]), str(new_pitch[i][v])])

    return report


func _verify_cross_arc_predicates_match_legacy(seq_clues: Array[Dictionary], pitch_clues: Array[Dictionary]) -> Dictionary:
    # Manual cross-check for the NEW cross-arc predicate layer specifically:
    # confirms _cross_arc_predicate reproduces the identical per-pair
    # boolean as the legacy _name_arc_predicate for every ordinal_cmp/
    # ordinal_adjacent/ordinal_offset/tone_cmp arc derivable from the given
    # clue sets, across every (d1, d2) dot pair, using the SAME live
    # rank/pitch possibility grids as input to both. proximity_dist_label
    # and proximity_dist_cmp_name have no legacy equivalent to compare
    # against (they're new), so they're excluded from this check.
    var report: Dictionary = {"matches": true, "mismatches": []}
    var rank_possible = _possibility_grid_for_clues(seq_clues)
    if rank_possible == null:
        report["mismatches"].append("sequence clues already contradictory — cannot compare")
        return report
    var pitch_possible: Array = _init_pitch_possibility_grid()
    if pitch_count > 0:
        var pp = _possibility_grid_for_pitch_clues(pitch_clues)
        if pp == null:
            report["mismatches"].append("pitch clues already contradictory — cannot compare")
            return report
        pitch_possible = pp

    var grids: Dictionary = {Category.SEQUENCE: rank_possible, Category.PITCH: pitch_possible}
    var arcs: Array = _name_arcs_from_clues(seq_clues, pitch_clues, [])
    for arc in arcs:
        var kind: String = str(arc["kind"])
        if kind == "proximity_dist_label":
            continue
        for d1 in star_count:
            for d2 in star_count:
                var legacy_result: bool = _name_arc_predicate(arc, d1, d2, rank_possible, pitch_possible)
                var new_result: bool = _cross_arc_predicate(arc, d1, d2, grids)
                if legacy_result != new_result:
                    report["matches"] = false
                    report["mismatches"].append("%s(d1=%d,d2=%d): legacy=%s new=%s" % [kind, d1, d2, str(legacy_result), str(new_result)])
    return report


func _verify_naked_subset_soundness(seq_clues: Array[Dictionary], pitch_clues: Array[Dictionary]) -> Dictionary:
    # Oracle-based soundness check against a REAL generated puzzle: runs
    # _propagate_unified with naked-subset ENABLED (only ever applied to
    # Sequence/Name — see the alldiff guard in _naked_subset_pass) and
    # confirms the TRUE ground-truth value for every dot, in both alldiff
    # categories, is still possible afterward. Ground truth is used here
    # ONLY as a test oracle, never fed into the live solve (see CRITICAL
    # BOUNDARY note earlier in this section) — if naked-subset ever
    # eliminates the actual answer, that's a definitive unsoundness bug,
    # since a valid solution can never legitimately be ruled out.
    var report: Dictionary = {"sound": true, "violations": []}

    var seq_cmp_arcs: Array = _expand_clues_to_cmp(seq_clues)
    var seq_offset_arcs: Array = []
    var seq_count_clues: Array = []
    for clue in seq_clues:
        if clue["kind"] == "ordinal_adjacent" or clue["kind"] == "ordinal_offset":
            seq_offset_arcs.append(clue)
        elif clue["kind"] == "ordinal_count_before":
            seq_count_clues.append(clue)

    var pitch_cmp_arcs: Array = []
    var pitch_eq_arcs: Array = []
    if pitch_count > 0:
        for arc in _expand_pitch_clues_to_cmp(pitch_clues):
            var rel: String = str(arc["rel"])
            if rel == "eq":
                pitch_eq_arcs.append({"a": arc["a"], "b": arc["b"]})
            else:
                pitch_cmp_arcs.append({"a": arc["a"], "b": arc["b"], "a_gt_b": (rel == "gt")})

    var new_seq = _init_category_grid(Category.SEQUENCE)
    var new_pitch = _init_category_grid(Category.PITCH)
    if not _apply_exact_clues(new_seq, seq_clues) or not _apply_negative_clues(new_seq, seq_clues) or not _apply_range_clues(new_seq, seq_clues):
        report["sound"] = false
        report["violations"].append("sequence clues already contradictory before naked-subset could run — cannot test")
        return report
    if pitch_count > 0 and (not _apply_pitch_exact_clues(new_pitch, pitch_clues) or not _apply_pitch_negative_clues(new_pitch, pitch_clues)):
        report["sound"] = false
        report["violations"].append("pitch clues already contradictory before naked-subset could run — cannot test")
        return report

    var cross_arcs: Array = _name_arcs_from_clues(seq_clues, pitch_clues, [])
    var grids: Dictionary = {
        Category.SEQUENCE: new_seq,
        Category.PITCH: new_pitch,
        Category.NAME: _init_category_grid(Category.NAME),
        Category.COLOR: _init_color_grid(),
        Category.DEGREE: _init_degree_grid(),
    }

    if not _propagate_unified(grids, seq_cmp_arcs, seq_offset_arcs, pitch_cmp_arcs, pitch_eq_arcs, cross_arcs, true, seq_count_clues):
        report["sound"] = false
        report["violations"].append("propagation with naked-subset ENABLED found a contradiction on a clue set already proven unique — naked-subset over-eliminated something")
        return report

    var seq_grid: Array = grids[Category.SEQUENCE]
    for d in star_count:
        var true_rank: int = pitch_rank_solution[d]
        if not seq_grid[d][true_rank]:
            report["sound"] = false
            report["violations"].append("SEQUENCE: dot %d's true rank %d was eliminated" % [d, true_rank])

    var name_grid: Array = grids[Category.NAME]
    for d in star_count:
        # Ground truth: dot d's true name-slot is trivially d itself.
        if not name_grid[d][d]:
            report["sound"] = false
            report["violations"].append("NAME: dot %d's true name-slot was eliminated" % [d])

    return report


func _verify_naked_pair_synthetic() -> Dictionary:
    # Hand-constructed scenario, independent of any real constellation (per
    # the plan's Phase 3 verification criteria): 4 dots, two of them (0, 1)
    # restricted to the identical 2-value rank domain {0,1} via
    # ordinal_range clues — a textbook naked pair. Confirms ranks 0 and 1
    # get eliminated from dots 2/3, and dots 0/1's own domains are
    # untouched. Temporarily overrides star_count (restored before
    # returning) — safe because this runs synchronously with no `await`,
    # so nothing else can observe the change mid-call.
    var saved_star_count: int = star_count
    star_count = 4
    var synth_clues: Array[Dictionary] = [
        {"kind": "ordinal_range", "s": 0, "lo": 0, "hi": 1, "text": ""},
        {"kind": "ordinal_range", "s": 1, "lo": 0, "hi": 1, "text": ""},
    ]
    var grid: Array = _init_category_grid(Category.SEQUENCE)
    _apply_range_clues(grid, synth_clues)
    var changed: bool = _naked_subset_pass(grid, 4, true)

    var report: Dictionary = {"pass": true, "details": []}
    if not changed:
        report["pass"] = false
        report["details"].append("expected a change from the naked-pair pass, got none")
    if grid[2][0] or grid[2][1]:
        report["pass"] = false
        report["details"].append("dot 2 should have ranks 0,1 eliminated — has: %s" % [str(grid[2])])
    if grid[3][0] or grid[3][1]:
        report["pass"] = false
        report["details"].append("dot 3 should have ranks 0,1 eliminated — has: %s" % [str(grid[3])])
    if not (grid[2][2] and grid[2][3]):
        report["pass"] = false
        report["details"].append("dot 2 should retain ranks 2,3 — has: %s" % [str(grid[2])])
    if not (grid[3][2] and grid[3][3]):
        report["pass"] = false
        report["details"].append("dot 3 should retain ranks 2,3 — has: %s" % [str(grid[3])])
    if not (grid[0][0] and grid[0][1]) or grid[0][2] or grid[0][3]:
        report["pass"] = false
        report["details"].append("dot 0's own domain should stay exactly {0,1} — has: %s" % [str(grid[0])])
    if not (grid[1][0] and grid[1][1]) or grid[1][2] or grid[1][3]:
        report["pass"] = false
        report["details"].append("dot 1's own domain should stay exactly {0,1} — has: %s" % [str(grid[1])])

    star_count = saved_star_count
    return report


func _trim_sequence_pass(clues: Array[Dictionary], restriction: Array, frame_timer_box: Array) -> bool:
    # One full weakest-first sweep over `clues` (mutated in place), testing
    # removal against `restriction` (rank restriction from the pitch axis's
    # CURRENT clue set, or [] for none). Returns true if anything was removed.
    var removed_any: bool = false
    var idx: int = 0
    while idx < clues.size():
        if clues.size() <= 1:
            break
        var trial_clue: Dictionary = clues[idx]
        clues.remove_at(idx)
        var trial_solutions: Array = _solve(clues, 2, restriction)
        if trial_solutions.size() == 1:
            removed_any = true
        else:
            clues.insert(idx, trial_clue)
            idx += 1
        if Time.get_ticks_msec() - float(frame_timer_box[0]) >= FRAME_BUDGET_MSEC:
            await Engine.get_main_loop().process_frame
            frame_timer_box[0] = Time.get_ticks_msec()
    return removed_any
 
 
func _trim_pitch_pass(clues: Array[Dictionary], restriction: Array, frame_timer_box: Array) -> bool:
    var removed_any: bool = false
    var idx: int = 0
    while idx < clues.size():
        if clues.size() <= 1:
            break
        var trial_clue: Dictionary = clues[idx]
        clues.remove_at(idx)
        var trial_solutions: Array = _solve_pitch(clues, 2, restriction)
        if trial_solutions.size() == 1:
            removed_any = true
        else:
            clues.insert(idx, trial_clue)
            idx += 1
        if Time.get_ticks_msec() - float(frame_timer_box[0]) >= FRAME_BUDGET_MSEC:
            await Engine.get_main_loop().process_frame
            frame_timer_box[0] = Time.get_ticks_msec()
    return removed_any
 
 
func _score_name_clue_difficulty(clue: Dictionary) -> float:
    var base: float = 1.0
    match str(clue.get("kind", "")):
        "proximity_dist_color":
            base = 6.0
        "proximity_dist_tone":
            base = 6.0
        "proximity_dist_degree":
            base = 5.5
        "proximity_dist_label":
            base = 6.5
        "proximity_between":
            base = 5.0
        "label_extreme_ordinal_color":
            base = 4.0
        "color_neg":
            base = 2.0 + float(clue.get("excluded", []).size())
        "proximity_degree_exact":
            base = 1.5
        "proximity_degree_extreme":
            base = 2.0
        "proximity_degree_group_cmp_color":
            base = 1.0 + (float(clue.get("targets", []).size()) * 0.3)
        "color_exact":
            base = 7.0
        "proximity_dist_extreme":
            base = 5.5
        "proximity_dist_dual_cmp":
            base = 4.5
        "proximity_dist_offset":
            base = 5.5
    return base + _clue_difficulty_jitter(clue)
 
 
## ── Live-domain helpers for the Name axis' single-dot filters and arc
## predicates. All of these read LIVE possibility grids derived from the
## currently-chosen Sequence/Pitch clue sets (via _possibility_grid_for_clues/
## _possibility_grid_for_pitch_clues) — never pitch_rank_solution/
## star_pitch_index ground truth — so a dot is only ever excluded from a
## name-slot when PROVEN inconsistent with what the player's own Sequence/
## Pitch deductions have established so far from the clues alone. This is
## the standard "eliminate only when proven impossible" arc-consistency
## rule; it is sometimes weaker than an exhaustive per-value search would
## be, but it is always sound, and any residual slack is picked up by
## _solve_names' backtracking fallback, same as every other propagation
## pass in this file.
func _domain_min(grid: Array, dot: int, size: int) -> int:
    for v in size:
        if grid[dot][v]:
            return v
    return -1


func _domain_max(grid: Array, dot: int, size: int) -> int:
    for v in range(size - 1, -1, -1):
        if grid[dot][v]:
            return v
    return -1


func _domain_forced_value(grid: Array, dot: int, size: int) -> int:
    var found: int = -1
    for v in size:
        if grid[dot][v]:
            if found != -1:
                return -1   # more than one possibility left — not forced
            found = v
    return found


func _domain_any_in_range(grid: Array, dot: int, lo: int, hi: int) -> bool:
    for v in range(lo, hi + 1):
        if grid[dot][v]:
            return true
    return false


func _apply_one_name_filter(possible: Array, clue: Dictionary, rank_possible: Array, pitch_possible: Array) -> void:
    match str(clue.get("kind", "")):
        "ordinal_exact":
            var s: int = clue["s"]
            var r: int = clue["r"]
            for d in star_count:
                if not rank_possible[d][r]:
                    possible[d][s] = false
        "ordinal_range":
            var s: int = clue["s"]
            var lo: int = clue["lo"]
            var hi: int = clue["hi"]
            for d in star_count:
                if not _domain_any_in_range(rank_possible, d, lo, hi):
                    possible[d][s] = false
        "ordinal_neg":
            var s: int = clue["s"]
            var r: int = clue["r"]
            for d in star_count:
                if _domain_forced_value(rank_possible, d, star_count) == r:
                    possible[d][s] = false
        "ordinal_neither_nor":
            var ns1: int = clue["s1"]
            var ns2: int = clue["s2"]
            var nr: int = clue["r"]
            for d in star_count:
                if _domain_forced_value(rank_possible, d, star_count) == nr:
                    possible[d][ns1] = false
                    possible[d][ns2] = false
        "ordinal_either_or":
            var es: int = clue["s"]
            var er1: int = clue["r1"]
            var er2: int = clue["r2"]
            for d in star_count:
                if not rank_possible[d][er1] and not rank_possible[d][er2]:
                    possible[d][es] = false
        "ordinal_unaligned":
            var us1: int = clue["s1"]
            var us2: int = clue["s2"]
            var ur1: int = clue["r1"]
            var ur2: int = clue["r2"]
            for d in star_count:
                if not rank_possible[d][ur1] and not rank_possible[d][ur2]:
                    possible[d][us1] = false
                    possible[d][us2] = false
        "proximity_neg_adjacent":
            var s: int = clue["s"]
            var r: int = clue["r"]
            for d in star_count:
                var hit: bool = false
                for n in proximity[d]:
                    if _domain_forced_value(rank_possible, int(n), star_count) == r:
                        hit = true
                        break
                if hit:
                    possible[d][s] = false
        "ordinal_count_before":
            var s: int = clue["s"]
            var k: int = clue["k"]
            for d in star_count:
                var feasible: bool = false
                for rd in star_count:
                    if not rank_possible[d][rd]:
                        continue
                    var must_before: int = 0
                    var can_before: int = 0
                    for n in proximity[d]:
                        var ni: int = int(n)
                        var nmax: int = _domain_max(rank_possible, ni, star_count)
                        var nmin: int = _domain_min(rank_possible, ni, star_count)
                        if nmax == -1:
                            continue
                        if nmax < rd:
                            must_before += 1
                            can_before += 1
                        elif nmin < rd:
                            can_before += 1
                    if must_before <= k and k <= can_before:
                        feasible = true
                        break
                if not feasible:
                    possible[d][s] = false
        "ordinal_extreme":
            var s: int = clue["s"]
            var want_lowest: bool = clue["want_lowest"]
            for d in star_count:
                if proximity[d].is_empty():
                    possible[d][s] = false
                    continue
                var d_bound: int = _domain_min(rank_possible, d, star_count) if want_lowest else _domain_max(rank_possible, d, star_count)
                if d_bound == -1:
                    continue
                var feasible2: bool = true
                for n in proximity[d]:
                    var ni2: int = int(n)
                    if want_lowest:
                        var n_max: int = _domain_max(rank_possible, ni2, star_count)
                        if n_max == -1 or n_max <= d_bound:
                            feasible2 = false
                            break
                    else:
                        var n_min: int = _domain_min(rank_possible, ni2, star_count)
                        if n_min == -1 or n_min >= d_bound:
                            feasible2 = false
                            break
                if not feasible2:
                    possible[d][s] = false
        "ordinal_group_cmp_color":
            var subjects: Array = clue["subjects"]
            var s_first: bool = clue["s_first"]
            var targets: Array = clue["targets"]
            if targets.is_empty():
                return
            for d in star_count:
                var d_bound2: int = _domain_min(rank_possible, d, star_count) if s_first else _domain_max(rank_possible, d, star_count)
                if d_bound2 == -1:
                    continue
                var feasible3: bool = true
                for t in targets:
                    var ti: int = int(t)
                    if s_first:
                        var t_max: int = _domain_max(rank_possible, ti, star_count)
                        if t_max == -1 or t_max <= d_bound2:
                            feasible3 = false
                            break
                    else:
                        var t_min: int = _domain_min(rank_possible, ti, star_count)
                        if t_min == -1 or t_min >= d_bound2:
                            feasible3 = false
                            break
                if not feasible3:
                    for subj in subjects:
                        possible[d][int(subj)] = false
        "ordinal_group_cmp_tone":
            var subjects3: Array = clue["subjects"]
            var s_first3: bool = clue["s_first"]
            var targets3: Array = clue["targets"]
            if targets3.is_empty():
                return
            for d in star_count:
                var d_bound3: int = _domain_min(rank_possible, d, star_count) if s_first3 else _domain_max(rank_possible, d, star_count)
                if d_bound3 == -1:
                    continue
                var feasible4: bool = true
                for t in targets3:
                    var ti2: int = int(t)
                    if s_first3:
                        var t_max2: int = _domain_max(rank_possible, ti2, star_count)
                        if t_max2 == -1 or t_max2 <= d_bound3:
                            feasible4 = false
                            break
                    else:
                        var t_min2: int = _domain_min(rank_possible, ti2, star_count)
                        if t_min2 == -1 or t_min2 >= d_bound3:
                            feasible4 = false
                            break
                if not feasible4:
                    for subj3 in subjects3:
                        possible[d][int(subj3)] = false
        "color_exact":
            var s: int = clue["s"]
            var c: int = clue["c"]
            for d in star_count:
                if star_colors[d] != c:
                    possible[d][s] = false
        "proximity_dist_color":
            # NOTE: _build_dist_pool() (shared by dist_color/tone/degree/label)
            # writes the shared value under "val", not "c" — pre-existing bug,
            # same field-name mistake already found and fixed in
            # from_cache_dict; this call site was crashing on every actual
            # proximity_dist_color clue reaching _apply_one_name_filter.
            var s: int = clue["s"]
            var val: int = clue["val"]
            var dist: int = clue["dist"]
            for d in star_count:
                var found: bool = false
                for other in star_count:
                    if other != d and _distances[d][other] == dist and star_colors[other] == val:
                        found = true
                        break
                if not found:
                    possible[d][s] = false
        "color_neg":
            var s: int = clue["s"]
            var excluded: Array = clue.get("excluded", [])
            for d in star_count:
                if star_colors[d] in excluded:
                    possible[d][s] = false
        "unique_list_n":
            # Only the Name participant (if any) constrains this axis: it
            # asserts the star truly named star_names[subj] differs from
            # every other listed (already-known-physical) participant, so
            # none of those physical stars can be the true home of name
            # `subj`. The Sequence participant (if any) is handled
            # separately by the Sequence-axis possibility grid.
            for part in clue["participants"]:
                if int(part["cat"]) == Category.NAME:
                    var subj: int = int(part["star"])
                    for other in clue["participants"]:
                        if int(other["star"]) == subj:
                            continue
                        possible[int(other["star"])][subj] = false
        "label_extreme_ordinal_color":
            var s: int = clue["s"]
            var want_lowest_rank: bool = clue["want_lowest_rank"]
            var group: Array = clue["group"]
            if group.is_empty():
                return
            for d in star_count:
                var d_bound4: int = _domain_min(rank_possible, d, star_count) if want_lowest_rank else _domain_max(rank_possible, d, star_count)
                if d_bound4 == -1:
                    continue
                var feasible5: bool = true
                for t in group:
                    var ti3: int = int(t)
                    if ti3 == d:
                        continue
                    if want_lowest_rank:
                        var t_max3: int = _domain_max(rank_possible, ti3, star_count)
                        if t_max3 == -1 or t_max3 < d_bound4:
                            feasible5 = false
                            break
                    else:
                        var t_min3: int = _domain_min(rank_possible, ti3, star_count)
                        if t_min3 == -1 or t_min3 > d_bound4:
                            feasible5 = false
                            break
                if not feasible5:
                    possible[d][s] = false
        "tone_exact":
            var s: int = clue["s"]
            var p: int = clue["p"]
            for d in star_count:
                if not pitch_possible[d][p]:
                    possible[d][s] = false
        "tone_neg":
            var s: int = clue["s"]
            var p_list: Array = clue.get("p_list", [])
            for d in star_count:
                var forced_p: int = _domain_forced_value(pitch_possible, d, pitch_count)
                if forced_p != -1 and forced_p in p_list:
                    possible[d][s] = false
        "tone_extreme":
            var s: int = clue["s"]
            var want_lowest: bool = clue["want_lowest"]
            for d in star_count:
                if proximity[d].is_empty():
                    possible[d][s] = false
                    continue
                var d_rank_bound: int = _pitch_max_possible_rank(pitch_possible, d) if want_lowest else _pitch_min_possible_rank(pitch_possible, d)
                if d_rank_bound == -1:
                    continue
                var feasible6: bool = true
                for n in proximity[d]:
                    var ni3: int = int(n)
                    if want_lowest:
                        var n_rank_max: int = _pitch_max_possible_rank(pitch_possible, ni3)
                        if n_rank_max == -1 or n_rank_max <= d_rank_bound:
                            feasible6 = false
                            break
                    else:
                        var n_rank_min: int = _pitch_min_possible_rank(pitch_possible, ni3)
                        if n_rank_min == -1 or n_rank_min >= d_rank_bound:
                            feasible6 = false
                            break
                if not feasible6:
                    possible[d][s] = false
        "tone_group_cmp_color":
            var subjects4: Array = clue["subjects"]
            var s_lower: bool = clue["s_lower"]
            var targets4: Array = clue["targets"]
            if targets4.is_empty():
                return
            for d in star_count:
                # s_lower means THIS star's pitch is lower than every target's —
                # so the bound we need from d's own domain is its MAX possible
                # freq-rank (the best case for "still low enough").
                var d_rank_bound2: int = _pitch_max_possible_rank(pitch_possible, d) if s_lower else _pitch_min_possible_rank(pitch_possible, d)
                if d_rank_bound2 == -1:
                    continue
                var feasible7: bool = true
                for t in targets4:
                    var ti4: int = int(t)
                    if s_lower:
                        var t_rank_max: int = _pitch_max_possible_rank(pitch_possible, ti4)
                        if t_rank_max == -1 or t_rank_max <= d_rank_bound2:
                            feasible7 = false
                            break
                    else:
                        var t_rank_min: int = _pitch_min_possible_rank(pitch_possible, ti4)
                        if t_rank_min == -1 or t_rank_min >= d_rank_bound2:
                            feasible7 = false
                            break
                if not feasible7:
                    for subj4 in subjects4:
                        possible[d][int(subj4)] = false
        "tone_group_eq":
            # A joint "all these name-slots share one pitch" constraint can't
            # be soundly resolved as an independent per-dot filter (a dot's
            # own pitch domain says nothing about which OTHER dot ends up
            # bound to a fellow slot in the group). Left unfiltered here —
            # sound (never falsely eliminates), and the constraint is still
            # fully enforced on the Pitch axis itself via _propagate_pitch's
            # "eq" arcs, independent of Name-axis solving.
            pass
        "proximity_dist_tone":
            var s: int = clue["s"]
            var val: int = clue["val"]
            var dist: int = clue["dist"]
            for d in star_count:
                var found: bool = false
                for other in star_count:
                    if other != d and _distances[d][other] == dist and pitch_possible[other][val]:
                        found = true
                        break
                if not found:
                    possible[d][s] = false
        "proximity_dist_degree":
            var s: int = clue["s"]
            var val: int = clue["val"]
            var dist: int = clue["dist"]
            for d in star_count:
                var found: bool = false
                for other in star_count:
                    if other != d and _distances[d][other] == dist and star_degrees[other] == val:
                        found = true
                        break
                if not found:
                    possible[d][s] = false
        "proximity_dist_label":
            # References another NAME — the very unknown this whole grid is
            # solving for — so "star_names[other] == val" would leak the
            # true name↔dot mapping (same shape as the Pitch/Sequence leak).
            # Handled as a "proximity_dist_label" arc in _name_arcs_from_clues
            # instead: distance between two dots is purely structural (legit,
            # like color/degree), so the arc form is both correct and free.
            pass
        "proximity_degree_exact":
            var s: int = clue["s"]
            var degree: int = clue["degree"]
            for d in star_count:
                if star_degrees[d] != degree:
                    possible[d][s] = false
        "proximity_degree_group_cmp_color":
            var s: int = clue["s"]
            var targets: Array = clue["targets"]
            var s_more: bool = clue["s_more"]
            for d in star_count:
                var valid: bool = true
                for t in targets:
                    var t_deg: int = star_degrees[int(t)]
                    if s_more and star_degrees[d] <= t_deg:
                        valid = false
                        break
                    if not s_more and star_degrees[d] >= t_deg:
                        valid = false
                        break
                if not valid:
                    possible[d][s] = false
        "proximity_degree_extreme":
            var s: int = clue["s"]
            var is_most: bool = clue["is_most"]
            for d in star_count:
                if is_most and star_degrees[d] != _max_degree:
                    possible[d][s] = false
                elif not is_most and star_degrees[d] != _min_degree:
                    possible[d][s] = false
        "proximity_dist_extreme":
            # Fixed reference (ref) baked in at generation time — purely
            # structural _distances lookups, legitimate like color/degree.
            var s: int = clue["s"]
            var ref: int = clue["ref"]
            var want_least: bool = clue["want_least"]
            for d in star_count:
                if d == ref:
                    possible[d][s] = false
                    continue
                var ok: bool = true
                for other in star_count:
                    if other == ref or other == d:
                        continue
                    if want_least and _distances[other][ref] <= _distances[d][ref]:
                        ok = false
                        break
                    elif not want_least and _distances[other][ref] >= _distances[d][ref]:
                        ok = false
                        break
                if not ok:
                    possible[d][s] = false
        "proximity_dist_dual_cmp":
            var s: int = clue["s"]
            var ref_a: int = clue["ref_a"]
            var ref_b: int = clue["ref_b"]
            var farther_from_a: bool = clue["farther_from_a"]
            for d in star_count:
                if d == ref_a or d == ref_b:
                    possible[d][s] = false
                    continue
                var da: int = _distances[d][ref_a]
                var db: int = _distances[d][ref_b]
                var ok2: bool = (da > db) if farther_from_a else (da < db)
                if not ok2:
                    possible[d][s] = false
        "proximity_dist_offset":
            var s: int = clue["s"]
            var ref_a: int = clue["ref_a"]
            var ref_b: int = clue["ref_b"]
            var offset: int = clue["offset"]
            for d in star_count:
                if d == ref_a or d == ref_b:
                    possible[d][s] = false
                    continue
                if _distances[d][ref_a] - _distances[d][ref_b] != offset:
                    possible[d][s] = false
        _:
            pass   # cmp, adj_seq, pitch_cmp, between handled separately
 
 
func _apply_name_single_dot_filters(possible: Array, seq_clues: Array[Dictionary], pitch_clues: Array[Dictionary], name_clues: Array[Dictionary], rank_possible: Array, pitch_possible: Array) -> bool:
    for clue in seq_clues:
        _apply_one_name_filter(possible, clue, rank_possible, pitch_possible)
    for clue in pitch_clues:
        _apply_one_name_filter(possible, clue, rank_possible, pitch_possible)
    for clue in name_clues:
        _apply_one_name_filter(possible, clue, rank_possible, pitch_possible)
    for i in star_count:
        var any_left: bool = false
        for j in star_count:
            if possible[i][j]:
                any_left = true
                break
        if not any_left:
            return false
    return true


func _name_slot_for_string(name_str: String) -> int:
    # Bookkeeping only — which fixed candidate-name SLOT has this label —
    # not a leak, since it never says which dot ends up holding that slot.
    for i in star_names.size():
        if star_names[i] == name_str:
            return i
    return -1


func _name_arcs_from_clues(seq_clues: Array[Dictionary], pitch_clues: Array[Dictionary], name_clues: Array[Dictionary]) -> Array:
    var arcs: Array = []
    for clue in seq_clues:
        var k: String = str(clue.get("kind", ""))
        if k == "ordinal_cmp":
            arcs.append({"n1": int(clue["a"]), "n2": int(clue["b"]), "kind": "ordinal_cmp", "a_gt_b": bool(clue["a_gt_b"])})
        elif k == "ordinal_adjacent":
            arcs.append({"n1": int(clue["a"]), "n2": int(clue["b"]), "kind": "ordinal_adjacent"})
        elif k == "ordinal_offset":
            arcs.append({"n1": int(clue["a"]), "n2": int(clue["b"]), "kind": "ordinal_offset", "offset": int(clue["offset"])})
    for clue in pitch_clues:
        if str(clue.get("kind", "")) == "tone_cmp":
            arcs.append({"n1": int(clue["a"]), "n2": int(clue["b"]), "kind": "tone_cmp", "rel": str(clue["rel"])})
    for clue in name_clues:
        if str(clue.get("kind", "")) == "proximity_dist_label":
            var target_slot: int = _name_slot_for_string(str(clue["val"]))
            if target_slot != -1:
                arcs.append({"n1": int(clue["s"]), "n2": target_slot, "kind": "proximity_dist_label", "dist": int(clue["dist"])})
    return arcs


func _name_arc_predicate(arc: Dictionary, d1: int, d2: int, rank_possible: Array, pitch_possible: Array) -> bool:
    # "Could this pair jointly satisfy the constraint" using the LIVE
    # Sequence/Pitch possibility domains — never pitch_rank_solution/
    # star_pitch_index ground truth. Support-exists, not ground-truth-true.
    match str(arc["kind"]):
        "ordinal_cmp":
            var a_gt_b: bool = arc["a_gt_b"]
            if a_gt_b:
                return _domain_max(rank_possible, d1, star_count) > _domain_min(rank_possible, d2, star_count)
            else:
                return _domain_min(rank_possible, d1, star_count) < _domain_max(rank_possible, d2, star_count)
        "ordinal_adjacent":
            for r2 in star_count:
                if rank_possible[d2][r2] and r2 + 1 < star_count and rank_possible[d1][r2 + 1]:
                    return true
            return false
        "ordinal_offset":
            var off: int = int(arc["offset"])
            for r2 in star_count:
                if rank_possible[d2][r2]:
                    var r1: int = r2 + off
                    if r1 >= 0 and r1 < star_count and rank_possible[d1][r1]:
                        return true
            return false
        "tone_cmp":
            var rel: String = arc["rel"]
            if rel == "eq":
                for p in pitch_count:
                    if pitch_possible[d1][p] and pitch_possible[d2][p]:
                        return true
                return false
            elif rel == "gt":
                return _pitch_max_possible_rank(pitch_possible, d1) > _pitch_min_possible_rank(pitch_possible, d2)
            else:
                return _pitch_min_possible_rank(pitch_possible, d1) < _pitch_max_possible_rank(pitch_possible, d2)
        "proximity_dist_label":
            # Structural — pure graph distance between two fixed dots, no
            # ground-truth unknown involved. Legitimate, like color/degree.
            return _distances[d1][d2] == int(arc["dist"])
    return true


func _name_arc_consistency(possible: Array, arcs: Array, rank_possible: Array, pitch_possible: Array) -> bool:
    var changed: bool = true
    while changed:
        changed = false
        for arc in arcs:
            var n1: int = arc["n1"]
            var n2: int = arc["n2"]
            for d1 in star_count:
                if not possible[d1][n1]:
                    continue
                var supported: bool = false
                for d2 in star_count:
                    if possible[d2][n2] and _name_arc_predicate(arc, d1, d2, rank_possible, pitch_possible):
                        supported = true
                        break
                if not supported:
                    possible[d1][n1] = false
                    changed = true
            for d2 in star_count:
                if not possible[d2][n2]:
                    continue
                var supported2: bool = false
                for d1 in star_count:
                    if possible[d1][n1] and _name_arc_predicate(arc, d1, d2, rank_possible, pitch_possible):
                        supported2 = true
                        break
                if not supported2:
                    possible[d2][n2] = false
                    changed = true
        for i in star_count:
            var any_left: bool = false
            for j in star_count:
                if possible[i][j]:
                    any_left = true
                    break
            if not any_left:
                return false
    return true
 
 
func _validate_between_clues(assignment: Array, between_clues: Array[Dictionary]) -> bool:
    for clue in between_clues:
        var mid_dot: int = assignment[int(clue["mid"])]
        var a_dot: int = assignment[int(clue["a"])]
        var b_dot: int = assignment[int(clue["b"])]
        if _distances[a_dot][mid_dot] + _distances[mid_dot][b_dot] != _distances[a_dot][b_dot]:
            return false
    return true
 
 
func _possibility_grid_for_name_clues(seq_clues: Array[Dictionary], pitch_clues: Array[Dictionary],
        name_clues: Array[Dictionary], rank_possible: Array, pitch_possible: Array):
    # Name-axis mirror of _possibility_grid_for_clues/_possibility_grid_for_
    # pitch_clues: the propagation-only prefix of _solve_names (single-dot
    # filters, arc consistency, naked-subset), stopping BEFORE backtracking.
    # Extracted out of _solve_names (which now calls this directly) so the
    # incremental resolved-star tracker (_refresh_resolved_stars) can reuse
    # the exact same logic instead of a second, drift-prone copy. Takes
    # already-computed rank_possible/pitch_possible since callers needing
    # all three grids together would otherwise compute Sequence/Pitch twice.
    var possible: Array = _init_possibility_grid()
    if not _apply_name_single_dot_filters(possible, seq_clues, pitch_clues, name_clues, rank_possible, pitch_possible):
        return null
    var arcs: Array = _name_arcs_from_clues(seq_clues, pitch_clues, name_clues)
    if not _name_arc_consistency(possible, arcs, rank_possible, pitch_possible):
        return null
    var nb_changed: bool = true
    while nb_changed:
        nb_changed = false
        if _naked_subset_pass(possible, star_count, true):
            nb_changed = true
            if not _name_arc_consistency(possible, arcs, rank_possible, pitch_possible):
                return null
    return possible


func _solve_names(seq_clues: Array[Dictionary], pitch_clues: Array[Dictionary], name_clues: Array[Dictionary], cap: int = 2) -> Array:
    # Live, leak-free front doors — never pitch_rank_solution/star_pitch_index
    # ground truth. If either axis's own clue set is already contradictory,
    # there's no valid world left to bind names against.
    var rank_possible = _possibility_grid_for_clues(seq_clues)
    if rank_possible == null:
        return []
    var pitch_possible: Array = _init_pitch_possibility_grid()
    if pitch_count > 0:
        var pp = _possibility_grid_for_pitch_clues(pitch_clues)
        if pp == null:
            return []
        pitch_possible = pp

    var possible = _possibility_grid_for_name_clues(seq_clues, pitch_clues, name_clues, rank_possible, pitch_possible)
    if possible == null:
        return []

    var between_clues: Array[Dictionary] = []
    for clue in name_clues:
        if str(clue.get("kind", "")) == "proximity_between":
            between_clues.append(clue)
 
    if _all_singleton(possible):
        var sol: Array = _extract_singleton_solution(possible)
        if not _validate_between_clues(sol, between_clues):
            return []
        return [sol]
 
    var solutions: Array = []
    var assignment: Array = []
    assignment.resize(star_count)
    for i in star_count:
        assignment[i] = -1
    var init_domains: Array = _possible_to_domains(possible)
    _backtrack_nodes_remaining = MAX_BACKTRACK_NODES
    _backtrack_fc_names(assignment, init_domains, between_clues, solutions, cap)
    return solutions
 
 
func _backtrack_fc_names(assignment: Array, domains: Array, between_clues: Array[Dictionary], solutions: Array, cap: int) -> void:
    if solutions.size() >= cap:
        return
    _backtrack_nodes_remaining -= 1
    if _backtrack_nodes_remaining <= 0:
        if _backtrack_nodes_remaining == 0:
            push_warning("ConstellationLogicPuzzle [%d]: backtracking node budget exhausted (names) — aborting search early." % constellation_id)
            _backtrack_nodes_remaining -= 1
        return
    var var_idx: int = -1
    var best_size: int = star_count + 1
    for i in star_count:
        if assignment[i] == -1:
            var sz: int = domains[i].size()
            if sz < best_size:
                best_size = sz
                var_idx = i
    if var_idx == -1:
        if _validate_between_clues(assignment, between_clues):
            solutions.append(assignment.duplicate())
        return
    for val in domains[var_idx]:
        assignment[var_idx] = val
        var new_doms = _forward_check(var_idx, val, domains, [], [])
        if new_doms != null:
            _backtrack_fc_names(assignment, new_doms, between_clues, solutions, cap)
        assignment[var_idx] = -1
        if solutions.size() >= cap:
            return
 
 
## _name_candidate_pool and _ensure_and_trim_names were deleted 2026-07-19
## — the last remnant of the pre-refactor Name generator (pre-built
## combinatorial pool, drained front-to-back with no category awareness).
## Every kind they used to build is now sample-then-constructed on demand
## by generate_clues_by_primer_type / _force_primer_coverage instead. See
## constellation_puzzle_sequential_generator_design memory for the history.
 
 
func _validate_pitch_all_diff_clues(solution: Array, clues: Array[Dictionary]) -> bool:
    for clue in clues:
        var stars: Array = clue["stars"]
        for i in stars.size():
            for j in range(i + 1, stars.size()):
                var si: int = int(stars[i])
                var sj: int = int(stars[j])
                if int(solution[si]) == int(solution[sj]):
                    return false
    return true


func _solve_pitch(clues: Array[Dictionary], cap: int = 2, pitch_restriction: Array = []) -> Array:
    var expanded_cmp: Array[Dictionary] = _expand_pitch_clues_to_cmp(clues)
    var all_diff_clues: Array[Dictionary] = []
    for clue in clues:
        if clue["kind"] == "tone_all_diff":
            all_diff_clues.append(clue)

    var possible: Array = _init_pitch_possibility_grid()
    if not pitch_restriction.is_empty():
        for i in star_count:
            for p in pitch_count:
                if not pitch_restriction[i][p]:
                    possible[i][p] = false
    if not _apply_pitch_exact_clues(possible, clues):
        return []
    if not _apply_pitch_negative_clues(possible, clues):
        return []
    var consistent: bool = _propagate_pitch(possible, expanded_cmp)
    if not consistent:
        return []

    if _all_pitch_singleton(possible):
        _pitch_solve_fast_path_count += 1
        var sol: Array = _extract_pitch_singleton_solution(possible)
        if not _validate_pitch_all_diff_clues(sol, all_diff_clues):
            return []
        return [sol]

    _pitch_solve_backtrack_count += 1
    var unresolved_count: int = 0
    for si in star_count:
        var domain_size: int = 0
        for p in pitch_count:
            if possible[si][p]:
                domain_size += 1
        if domain_size != 1:
            unresolved_count += 1
    _pitch_unresolved_star_sum += unresolved_count
    _pitch_unresolved_star_samples += 1
    var solutions: Array = []
    var assignment: Array = []
    assignment.resize(star_count)
    for i in star_count:
        assignment[i] = -1

    var init_domains: Array = _pitch_possible_to_domains(possible)
    _backtrack_nodes_remaining = MAX_BACKTRACK_NODES
    _backtrack_fc_pitch(assignment, init_domains, expanded_cmp, all_diff_clues, solutions, cap)
    return solutions


func _backtrack_fc_pitch(assignment: Array, domains: Array,
        cmp_clues: Array[Dictionary], all_diff_clues: Array[Dictionary], solutions: Array, cap: int) -> void:
    if solutions.size() >= cap:
        return
    _backtrack_nodes_remaining -= 1
    if _backtrack_nodes_remaining <= 0:
        if _backtrack_nodes_remaining == 0:
            push_warning("ConstellationLogicPuzzle [%d]: backtracking node budget exhausted (pitch) — aborting search early." % constellation_id)
            _backtrack_nodes_remaining -= 1
        return

    var var_idx: int = -1
    var best_size: int = pitch_count + 1
    for i in star_count:
        if assignment[i] == -1:
            var sz: int = domains[i].size()
            if sz < best_size:
                best_size = sz
                var_idx = i

    if var_idx == -1:
        if _validate_pitch_all_diff_clues(assignment, all_diff_clues):
            solutions.append(assignment.duplicate())
        return

    for val in domains[var_idx]:
        assignment[var_idx] = val
        var new_doms_result = _forward_check_pitch(var_idx, val, domains, cmp_clues)
        if new_doms_result != null:
            _backtrack_fc_pitch(assignment, new_doms_result, cmp_clues, all_diff_clues, solutions, cap)
        assignment[var_idx] = -1
        if solutions.size() >= cap:
            return
 
 
func _forward_check_pitch(var_idx: int, val: int, domains: Array,
        cmp_clues: Array[Dictionary]):
    # Returns a new domains Array with propagated reductions, or null on
    # wipeout. No alldiff step — pitch values may legitimately repeat.
    var nd: Array = []
    for i in star_count:
        nd.append(domains[i].duplicate())
    nd[var_idx] = [val]
 
    for clue in cmp_clues:
        var a: int = clue["a"]
        var b: int = clue["b"]
        var rel: String = clue["rel"]
        var val_rank: int = _pitch_freq_rank[val]
 
        if rel == "eq":
            if a == var_idx:
                var new_b: Array = []
                for v in nd[b]:
                    if is_equal_approx(_pitch_freqs[v], _pitch_freqs[val]):
                        new_b.append(v)
                if new_b.is_empty():
                    return null
                nd[b] = new_b
            elif b == var_idx:
                var new_a: Array = []
                for v in nd[a]:
                    if is_equal_approx(_pitch_freqs[v], _pitch_freqs[val]):
                        new_a.append(v)
                if new_a.is_empty():
                    return null
                nd[a] = new_a
            continue
 
        if a == var_idx:
            var new_b2: Array = []
            for v in nd[b]:
                var vr: int = _pitch_freq_rank[v]
                if rel == "gt" and vr < val_rank:
                    new_b2.append(v)
                elif rel == "lt" and vr > val_rank:
                    new_b2.append(v)
            if new_b2.is_empty():
                return null
            nd[b] = new_b2
        elif b == var_idx:
            var new_a2: Array = []
            for v in nd[a]:
                var vr2: int = _pitch_freq_rank[v]
                if rel == "gt" and vr2 > val_rank:
                    new_a2.append(v)
                elif rel == "lt" and vr2 < val_rank:
                    new_a2.append(v)
            if new_a2.is_empty():
                return null
            nd[a] = new_a2
 
    return nd
 
 
func _score_pitch_clue_difficulty(clue: Dictionary) -> float:
    var base: float = 1.0
    match clue.get("kind", ""):
        "tone_exact":
            base = 10.0
        "tone_extreme":
            base = 7.0
        "tone_neg":
            base = 6.0
        "tone_group_eq":
            base = 5.0 + (float(clue.get("stars", []).size()) * 0.5)
        "tone_group_cmp_color":
            base = 4.0 + (float(clue.get("targets", []).size()) * 0.8)
        "tone_cmp":
            var a2: int = clue.get("a", 0)
            var b2: int = clue.get("b", 0)
            var gap2: int = abs(_pitch_freq_rank[star_pitch_index[a2]] - _pitch_freq_rank[star_pitch_index[b2]])
            base = 2.0 + (float(gap2) * 0.5)
        "tone_all_diff":
            base = 6.0 + (float(clue.get("stars", []).size()) * 0.6)
    return base + _clue_difficulty_jitter(clue)
 
 
# ==================================================
# CLUE TEXT BUILDERS
# ==================================================
 
## _build_cmp_clue / _build_adj_seq_clue deleted 2026-07-19 — each had
## exactly one caller (the ordinal_cmp/ordinal_adjacent branches of
## _sample_and_build), so folded inline there directly rather than kept as
## single-use indirection.


func _build_extreme_clue(s: int) -> Dictionary:
    var neighbors: Array = proximity[s]
    if neighbors.is_empty():
        return {}
    var s_rank: int = pitch_rank_solution[s]
    if s_rank == 0 or s_rank == star_count - 1:
        # Global-extreme subjects trivially satisfy "extreme among neighbors"
        # regardless of which stars are actually adjacent — the claim adds
        # zero information beyond what the ordinal in the text already gives
        # away. Skip rather than generate a tautology.
        return {}
    var is_lowest: bool = true
    var is_highest: bool = true
    for n in neighbors:
        if pitch_rank_solution[n] < pitch_rank_solution[s]:
            is_lowest = false
        if pitch_rank_solution[n] > pitch_rank_solution[s]:
            is_highest = false
    if not is_lowest and not is_highest:
        return {}
    var word: String = "earliest" if is_lowest else "latest"
    var text: String = "The %s fires %s among all stars it connects to." % [_ordinal(pitch_rank_solution[s] + 1), word]
    var nb_copy: Array = []
    for n in neighbors:
        nb_copy.append(int(n))
    return {"kind": "ordinal_extreme", "s": s, "neighbors": nb_copy,
            "want_lowest": is_lowest, "text": text}
 
 
func _freq_for_star(s: int) -> float:
    if s < 0 or s >= star_pitch_index.size():
        return 0.0
    var pidx: int = star_pitch_index[s]
    if pidx < 0 or pidx >= _pitch_freqs.size():
        return 0.0
    return _pitch_freqs[pidx]
 
 
## _build_pitch_cmp_text deleted 2026-07-19 — folded inline into the
## tone_cmp branch of _sample_and_build (its one caller).
 
 
# ==================================================
# POOL BUILDERS
# ==================================================
 
## _build_proximity_cmp_pool / _build_extreme_pool / _build_color_pool /
## _build_degree_pool / _build_adj_seq_pool deleted 2026-07-19 — all
## superseded by sample-then-construct (_sample_and_build's ordinal_cmp/
## ordinal_extreme/ordinal_adjacent branches, _sample_degree_group_eq).
## _build_cmp_clue/_build_adj_seq_clue/_build_extreme_clue are still used
## directly by those branches.


func _exact_desc_is_unique(subject: int, named_neighbor: int, color_c: int) -> bool:
    for t in star_count:
        if t == subject:
            continue
        if not proximity[t].has(named_neighbor):
            continue
        var has_color_neighbor: bool = false
        for n in proximity[t]:
            if int(n) != named_neighbor and star_colors[int(n)] == color_c:
                has_color_neighbor = true
                break
        if has_color_neighbor:
            return false
    return true
 
 
## _build_range_pool / _build_group_cmp_pool / _build_seq_pitch_cmp_pool /
## _build_unique_list_pool / _build_count_before_pool /
## _build_neg_adjacent_pool / _build_neg_exact_pool / _build_degree_*_pool /
## _build_neither_nor_pool / _build_either_or_pool /
## _build_unaligned_pair_pool / _build_offset_seq_pool /
## _build_pitch_all_diff_pool deleted 2026-07-19 — all superseded by
## sample-then-construct (_sample_and_build's dispatch table, plus
## _sample_unique_list_n/_sample_degree_group_eq/etc.). _build_exact_pool
## was likewise deleted; ordinal_exact is now built by _sample_and_build
## directly using _exact_desc_is_unique above.


func _pair_already_related(a: int, b: int, chosen: Array[Dictionary]) -> bool:
    for c in chosen:
        var k: String = str(c.get("kind", ""))
        if k != "ordinal_cmp" and k != "ordinal_adjacent" and k != "ordinal_offset":
            continue
        var ca: int = int(c.get("a", -1))
        var cb: int = int(c.get("b", -1))
        if (ca == a and cb == b) or (ca == b and cb == a):
            return true
    return false


func _print_clue_breakdown_diagnostics(chosen: Array[Dictionary], pitch_chosen: Array[Dictionary], name_chosen: Array[Dictionary]) -> void:
    var tab_counts: Dictionary = {"Color": 0, "Sequence": 0, "Pitch": 0, "Proximity": 0}
    var primer_counts: Dictionary = {}

    # Not every kind maps onto a primer category — extreme/range/group_cmp/
    # count_before/neg_adjacent/dist_color/between/alph_extreme/pitch_extreme/
    # pitch_group_eq/pitch_group_cmp all predate the primer-coverage work and
    # fall to "Other/structural" honestly, rather than forcing a false match.
    var primer_map: Dictionary = {
        "ordinal_exact": "True", "tone_exact": "True",
        "ordinal_neg": "False", "tone_neg": "False",
        "tone_all_diff": "Multi-Elimination",
        "ordinal_neither_nor": "Neither/Nor", "color_neg": "Neither/Nor",
        "ordinal_either_or": "Either/Or",
        "ordinal_cmp": "Greater/Lesser (vague)", "tone_cmp": "Greater/Lesser (vague)", "ordinal_chain": "Greater/Lesser (vague)",
        "ordinal_offset": "Greater/Lesser (specific)", "ordinal_adjacent": "Greater/Lesser (specific)",
        "ordinal_unaligned": "Unaligned Pair",
    }

    tab_counts["NameClues"] = 0
    for clue in chosen:
        var kind: String = str(clue.get("kind", ""))
        for tab in _kind_ui_tabs(kind):
            if tab_counts.has(tab):
                tab_counts[tab] = int(tab_counts[tab]) + 1
        var primer_cat: String = str(primer_map.get(kind, "Other/structural"))
        primer_counts[primer_cat] = int(primer_counts.get(primer_cat, 0)) + 1

    for pclue in pitch_chosen:
        var pkind: String = str(pclue.get("kind", ""))
        for ptab in _kind_ui_tabs(pkind):
            if tab_counts.has(ptab):
                tab_counts[ptab] = int(tab_counts[ptab]) + 1
        var pprimer_cat: String = str(primer_map.get(pkind, "Other/structural"))
        primer_counts[pprimer_cat] = int(primer_counts.get(pprimer_cat, 0)) + 1

    for iclue in name_chosen:
        var ikind: String = str(iclue.get("kind", ""))
        for itab in _kind_ui_tabs(ikind):
            if tab_counts.has(itab):
                tab_counts[itab] = int(tab_counts[itab]) + 1
        var iprimer_cat: String = str(primer_map.get(ikind, "Other/structural"))
        primer_counts[iprimer_cat] = int(primer_counts.get(iprimer_cat, 0)) + 1

    print("[PUZZLE_TIMING %d] clue breakdown by UI tab: %s" % [constellation_id, str(tab_counts)])
    print("[PUZZLE_TIMING %d] clue breakdown by primer category: %s" % [constellation_id, str(primer_counts)])


func _kind_primer_category(kind: String) -> String:
    match kind:
        "ordinal_exact", "tone_exact", "color_exact":
            return "True"
        "ordinal_neg", "tone_neg":
            return "False"
        "tone_all_diff", "unique_list_n":
            return "Multi-Elimination"
        "ordinal_neither_nor", "color_neg":
            return "Neither/Nor"
        "ordinal_either_or":
            return "Either/Or"
        "ordinal_cmp", "tone_cmp", "proximity_dist_dual_cmp", "ordinal_chain":
            return "Greater/Lesser (vague)"
        "ordinal_offset", "ordinal_adjacent", "proximity_dist_offset":
            return "Greater/Lesser (specific)"
        "ordinal_unaligned":
            return "Unaligned Pair"
    return ""   # not primer-mapped — matches the diagnostic's "Other/structural" bucket


# Sequential-generator design (2026-07-19): initial static ranking of the 8
# primer categories by expected "entropic bias" — roughly, how many T/F grid
# intersections a typical clue of that category resolves. Derived from
# _score_clue_difficulty's base values (per the user's explicit direction to
# start from that as a proxy), using a "typical" mid-range parameter for
# variable-bonus kinds (e.g. ordinal_cmp's rank-gap, unique_list_n's N) since
# the real value varies per clue instance. Where a kind's base value differs
# between _score_clue_difficulty/_score_name_clue_difficulty/
# _score_pitch_clue_difficulty (pre-existing drift across those three, not
# something this table fixes), _score_clue_difficulty's value is preferred.
# THIS IS A STARTING PROXY, not a measured result — per-category values
# should be replaced with real observed elimination counts once the
# sequential generator has run enough live puzzles to measure them directly.
# Multi-Elimination ranks highest because unique_list_n's N-way shape
# integrates the most distinct stars per clue, which the user identified as
# the primary expected driver of entropic bias.
const PRIMER_CATEGORY_ENTROPIC_BIAS := {
    "Multi-Elimination":        11.0,  # unique_list_n (N~4): 5.0 + 4*1.5
    "True":                      8.7,  # avg(ordinal_exact 10.0, tone_exact 9.0, color_exact 7.0)
    "Greater/Lesser (specific)": 7.2,  # avg(ordinal_offset~8.1, ordinal_adjacent 8.0, proximity_dist_offset 5.5)
    "Unaligned Pair":            6.5,  # ordinal_unaligned
    "False":                     5.75, # avg(ordinal_neg 6.0, tone_neg 5.5)
    "Either/Or":                 5.5,  # ordinal_either_or
    "Greater/Lesser (vague)":    4.5,  # avg(ordinal_cmp~4.5 at typical gap, tone_cmp 4.5, proximity_dist_dual_cmp 4.5)
    "Neither/Nor":               4.25, # avg(ordinal_neither_nor 4.5, color_neg 4.0)
}


static func _primer_categories_by_entropic_bias() -> Array[String]:
    var cats: Array[String] = []
    for c in PRIMER_CATEGORY_ENTROPIC_BIAS.keys():
        cats.append(str(c))
    cats.sort_custom(func(a, b): return PRIMER_CATEGORY_ENTROPIC_BIAS[a] > PRIMER_CATEGORY_ENTROPIC_BIAS[b])
    return cats


## Phase 5 (2026-07-18): the single canonical clue-kind -> UI-tab mapping.
## Static because it's a pure function of `kind` with no instance state —
## constellation_study_overlay.gd calls this directly (same pattern already
## established for note_name_for_freq) instead of keeping its own copy.
## Fixed drift found when unifying: "ordinal_group_cmp_tone" was unmapped
## in the overlay's copy, "color_exact" disagreed (["Color"] here vs.
## ["Color","NameClues"] there — resolved to the NameClues-inclusive form,
## consistent with sibling kinds color_neg/proximity_dist_color), and the
## four proximity_degree_* kinds existed only in the overlay's copy.
static func _kind_ui_tabs(kind: String) -> Array[String]:
    match kind:
        "ordinal_exact", "ordinal_range", "ordinal_neg", "ordinal_cmp", "ordinal_adjacent", "ordinal_offset", "ordinal_neither_nor", "ordinal_either_or", "ordinal_unaligned", "ordinal_chain":
            return ["Sequence"]
        "ordinal_group_cmp_color":
            return ["Sequence", "Color"]
        "ordinal_group_cmp_tone":
            return ["Sequence", "Pitch"]
        "ordinal_extreme", "ordinal_count_before", "proximity_neg_adjacent":
            return ["Sequence", "Proximity"]
        "tone_exact", "tone_neg", "tone_cmp", "tone_group_eq":
            return ["Pitch"]
        "tone_extreme":
            return ["Pitch", "Proximity"]
        "tone_group_cmp_color":
            return ["Pitch", "Color"]
        "tone_all_diff":
            return ["Pitch", "NameClues"]
        "proximity_dist_color":
            return ["Color", "Proximity", "NameClues"]
        "proximity_between":
            return ["Proximity", "NameClues"]
        "color_neg":
            return ["Color", "NameClues"]
        "color_exact":
            return ["Color", "NameClues"]
        "label_extreme_ordinal_color":
            return ["Color", "NameClues", "Sequence"]
        "proximity_dist_extreme", "proximity_dist_dual_cmp", "proximity_dist_offset":
            return ["Proximity", "NameClues"]
        "proximity_degree_exact", "proximity_degree_group_eq", "proximity_degree_extreme", "proximity_degree_group_cmp_color":
            return ["Proximity"]
        "unique_list_n":
            return ["Sequence", "Color", "Proximity", "Pitch", "NameClues"]
    return []


func _kind_home_array(kind: String) -> String:
    # Which of chosen/pitch_chosen/name_chosen a candidate actually belongs
    # in — independent of which UI tab(s) it's being pulled in to satisfy.
    if kind.begins_with("pitch_") or kind.begins_with("tone_"):
        return "pitch"
    if kind == "proximity_dist_color" or kind == "proximity_between" or kind == "color_neg" or kind == "label_extreme_ordinal_color" \
    or kind == "proximity_dist_tone" or kind == "proximity_dist_degree" or kind == "proximity_dist_label" \
    or kind == "proximity_degree_exact" or kind == "proximity_degree_extreme" or kind == "proximity_degree_group_cmp_color" \
    or kind == "color_exact" \
    or kind == "proximity_dist_extreme" or kind == "proximity_dist_dual_cmp" or kind == "proximity_dist_offset":
        return "name"
    return "sequence"


func _refresh_resolved_stars(seq_clues: Array[Dictionary], pitch_clues: Array[Dictionary],
        name_clues: Array[Dictionary], resolved: Dictionary) -> Dictionary:
    # Incremental propagation tracker (2026-07-19, per Bogaerts/Gamba/Guns
    # 2021's step-wise CSP-explanation framework — their greedy-explain
    # runs propagation to fixpoint and feeds each newly-derived fact back
    # before picking the next step; this is the same idea applied inside
    # generation instead of after it). A star counts as "resolved" only
    # once its Sequence-rank OR Name-slot domain has actually narrowed to a
    # single value via real propagation — not merely because some clue
    # happened to mention it. Replaces the old "touched = mentioned" proxy
    # (crude — a star could be named in five clues and still be logically
    # ambiguous, or resolved by cross-referencing without ever being the
    # PRIMARY subject of any one clue) with the genuine derived state,
    # reusing the exact propagation front-ends already trusted for final
    # verification (_possibility_grid_for_clues/_possibility_grid_for_
    # pitch_clues/_possibility_grid_for_name_clues), just run after every
    # committed clue instead of only once at the end. Pitch is
    # deliberately excluded from "resolved" — it isn't something clues
    # need to solve (players use Listen), so pitch_possible is computed
    # only because Name-binding's cross-axis filters need it, never
    # consulted for resolution status itself.
    #
    # Also returns whole-grid resolution status ({"seq_fully_resolved":
    # bool, "name_fully_resolved": bool}) — per-star "resolved" (used for
    # sampling bias) is a weaker signal than "every star's domain has
    # collapsed to one value via PURE propagation" (used as the actual
    # generation completion criterion — see generate_clues_by_primer_type):
    # a star can be individually resolved while others in the same grid
    # are still ambiguous.
    var rank_possible = _possibility_grid_for_clues(seq_clues)
    if rank_possible == null:
        return {"seq_fully_resolved": false, "name_fully_resolved": false}   # a contradiction here would mean a generated clue was unsound — every clue is ground-truth-true, so this should never actually trigger
    var pitch_possible: Array = _init_pitch_possibility_grid()
    if pitch_count > 0:
        var pp = _possibility_grid_for_pitch_clues(pitch_clues)
        if pp != null:
            pitch_possible = pp
    var name_possible = _possibility_grid_for_name_clues(seq_clues, pitch_clues, name_clues, rank_possible, pitch_possible)
    for s in star_count:
        if _domain_forced_value(rank_possible, s, star_count) != -1:
            resolved[s] = true
        elif name_possible != null and _domain_forced_value(name_possible, s, star_count) != -1:
            resolved[s] = true
    return {
        "seq_fully_resolved": _all_singleton(rank_possible),
        "name_fully_resolved": name_possible != null and _all_singleton(name_possible),
    }


func _commit_generated_clue(picked: Dictionary, chosen: Array[Dictionary], pitch_chosen: Array[Dictionary],
        name_chosen: Array[Dictionary], all_touched_stars: Dictionary, generated_texts: Dictionary) -> Dictionary:
    var home: String = _kind_home_array(str(picked.get("kind", "")))
    match home:
        "pitch":
            pitch_chosen.append(picked)
        "name":
            name_chosen.append(picked)
        _:
            chosen.append(picked)
    generated_texts[str(picked.get("text", ""))] = true
    return _refresh_resolved_stars(chosen, pitch_chosen, name_chosen, all_touched_stars)


func _all_generatable_kinds() -> Array[String]:
    var out: Array[String] = []
    out.append_array(PRIMER_ELIGIBLE_KINDS)
    out.append_array(STRUCTURAL_KINDS)
    return out


func _join_subject_names(names: Array) -> String:
    if names.size() == 1:
        return str(names[0])
    if names.size() == 2:
        return "%s and %s" % [names[0], names[1]]
    var head: String = ", ".join(names.slice(0, names.size() - 1))
    return "%s, and %s" % [head, names[names.size() - 1]]


func _group_cmp_merge_key(clue: Dictionary, direction_field: String) -> String:
    # Two group_cmp clues describe the exact same underlying relationship —
    # and so can be merged into one multi-subject sentence — iff they share
    # the identical target-star set AND the identical direction (s_first/
    # s_lower). Comparing the actual target star indices (not just "same
    # color" or "same pitch") is what makes this safe: it's the physical
    # group the constraint is about, independent of how it's described.
    var targets: Array = clue.get("targets", [])
    var sorted_targets: Array = targets.duplicate()
    sorted_targets.sort()
    return "%s|%s" % [str(sorted_targets), str(clue.get(direction_field))]


func _build_group_cmp_merged_text(kind: String, clue: Dictionary, subjects: Array) -> String:
    var names: Array = []
    for s in subjects:
        names.append(star_names[int(s)])
    var joined: String = _join_subject_names(names)
    var plural: bool = subjects.size() > 1
    var targets: Array = clue.get("targets", [])
    var ref_star: int = int(targets[0]) if not targets.is_empty() else 0
    match kind:
        "ordinal_group_cmp_color":
            var color_word: String = COLOR_NAMES[star_colors[ref_star]].to_lower()
            var verb: String = "fire" if plural else "fires"
            if bool(clue.get("s_first", true)):
                return "%s %s before every %s star." % [joined, verb, color_word]
            return "%s %s after every %s star." % [joined, verb, color_word]
        "ordinal_group_cmp_tone":
            var note_word: String = note_name_for_freq(_pitch_freqs[star_pitch_index[ref_star]])
            var verb2: String = "fire" if plural else "fires"
            if bool(clue.get("s_first", true)):
                return "%s %s before every star that plays %s." % [joined, verb2, note_word]
            return "%s %s after every star that plays %s." % [joined, verb2, note_word]
        "tone_group_cmp_color":
            var color_word2: String = COLOR_NAMES[star_colors[ref_star]].to_lower()
            var verb3: String = "play" if plural else "plays"
            if bool(clue.get("s_lower", true)):
                return "%s %s a lower note than every %s star." % [joined, verb3, color_word2]
            return "%s %s a higher note than every %s star." % [joined, verb3, color_word2]
    return str(clue.get("text", ""))


func _merge_group_cmp_kind(list: Array[Dictionary], kind: String, direction_field: String) -> void:
    var groups: Dictionary = {}   # merge_key -> Array[int] indices into list
    for i in list.size():
        if str(list[i].get("kind", "")) != kind:
            continue
        var key: String = _group_cmp_merge_key(list[i], direction_field)
        if not groups.has(key):
            groups[key] = []
        groups[key].append(i)

    var indices_to_remove: Array = []
    for key in groups.keys():
        var idxs: Array = groups[key]
        if idxs.size() < 2:
            continue
        var merged_subjects: Array = []
        for idx in idxs:
            for subj in (list[idx].get("subjects", []) as Array):
                if not merged_subjects.has(int(subj)):
                    merged_subjects.append(int(subj))
        var first_idx: int = int(idxs[0])
        list[first_idx]["subjects"] = merged_subjects
        list[first_idx]["text"] = _build_group_cmp_merged_text(kind, list[first_idx], merged_subjects)
        for j in range(1, idxs.size()):
            indices_to_remove.append(int(idxs[j]))

    indices_to_remove.sort()
    indices_to_remove.reverse()
    for idx in indices_to_remove:
        list.remove_at(idx)


func _merge_group_cmp_duplicates(chosen: Array[Dictionary], pitch_chosen: Array[Dictionary]) -> void:
    # Two independently-sampled group_cmp clues can end up describing the
    # exact same target group ("X fires before every star that plays G4"
    # and "Y fires before every star that plays G4") since each is sampled
    # without knowledge of the other. Rather than prevent this at sample
    # time (which would need the sampler to see the whole chosen list),
    # merge duplicates after generation into one multi-subject sentence —
    # a text-presentation fix, not a selection mechanism, so it doesn't
    # reintroduce the pool-then-filter pattern.
    _merge_group_cmp_kind(chosen, "ordinal_group_cmp_color", "s_first")
    _merge_group_cmp_kind(chosen, "ordinal_group_cmp_tone", "s_first")
    _merge_group_cmp_kind(pitch_chosen, "tone_group_cmp_color", "s_lower")


func _force_primer_coverage(chosen: Array[Dictionary], pitch_chosen: Array[Dictionary],
        name_chosen: Array[Dictionary], all_touched_stars: Dictionary, generated_texts: Dictionary) -> Dictionary:
    # REDUCED ROLE, 2026-07-19: generate_clues_by_primer_type's own loop now
    # pursues kind-floor AND primer-category-floor coverage directly, as
    # part of reaching "solved," using this exact same _attempt_construct/
    # _try_pick_for_category machinery — so Pass 1 and Pass 3 below should
    # find nothing left to do under normal operation (every kind already
    # seen or already given up on as genuinely infeasible for this
    # constellation, every primer category already at its floor). This
    # function is kept as a defensive safety net, not the mechanism that
    # achieves coverage — if its "forced" list is non-empty in a real run,
    # that's worth investigating as a sign the primary loop's own coverage
    # sweep missed something, not treated as expected/normal. Pass 2
    # (UI-tab floor) is the one piece not folded into the primary loop —
    # tab coverage is usually a side effect of kind+category coverage
    # (most kinds map to multiple tabs) but isn't explicitly pursued there.
    var forced: Array[String] = []
    var category_kinds: Dictionary = _category_kinds()
    var all_kinds: Array[String] = _all_generatable_kinds()

    var has_kind: Dictionary = {}
    for c in chosen:
        has_kind[str(c.get("kind", ""))] = true
    for c in pitch_chosen:
        has_kind[str(c.get("kind", ""))] = true
    for c in name_chosen:
        has_kind[str(c.get("kind", ""))] = true

    # ---- Pass 1: kind floor — every generatable kind gets at least one
    # representative if the constellation structure supports it at all.
    for kind in all_kinds:
        if has_kind.get(kind, false):
            continue
        var picked: Dictionary = _attempt_construct(kind, all_touched_stars, generated_texts)
        if not picked.is_empty():
            _commit_generated_clue(picked, chosen, pitch_chosen, name_chosen, all_touched_stars, generated_texts)
            has_kind[kind] = true
            forced.append("%s: forced (kind floor)" % kind)
        else:
            forced.append("%s: pool empty, could not force (constellation structure doesn't support it)" % kind)

    # ---- Pass 2: UI-tab floor, multi-membership aware ----
    var tab_kinds: Dictionary = {"Color": [], "Proximity": [], "Sequence": [], "Pitch": [], "NameClues": []}
    for kind in all_kinds:
        for tab in _kind_ui_tabs(kind):
            if tab_kinds.has(tab):
                tab_kinds[tab].append(kind)

    for tab in tab_kinds.keys():
        var current_count: int = 0
        for c in chosen:
            if tab in _kind_ui_tabs(str(c.get("kind", ""))):
                current_count += 1
        for c in pitch_chosen:
            if tab in _kind_ui_tabs(str(c.get("kind", ""))):
                current_count += 1
        for c in name_chosen:
            if tab in _kind_ui_tabs(str(c.get("kind", ""))):
                current_count += 1

        var candidate_kinds: Array = (tab_kinds[tab] as Array).duplicate()
        if candidate_kinds.is_empty():
            continue
        _shuffle_array(candidate_kinds)
        var attempts: int = 0
        var max_attempts: int = candidate_kinds.size() * 4
        while current_count < TAB_MIN and attempts < max_attempts:
            var kind2: String = candidate_kinds[attempts % candidate_kinds.size()]
            attempts += 1
            var picked2: Dictionary = _attempt_construct(kind2, all_touched_stars, generated_texts)
            if picked2.is_empty():
                continue
            _commit_generated_clue(picked2, chosen, pitch_chosen, name_chosen, all_touched_stars, generated_texts)
            current_count += 1
            forced.append("%s: forced (tab floor, %s)" % [kind2, tab])

        if current_count < TAB_MIN:
            forced.append("%s tab: only reached %d/%d, exhausted" % [tab, current_count, TAB_MIN])

    # ---- Pass 3: primer-category floor ----
    var primer_categories: Array[String] = ["True", "False", "Multi-Elimination", "Neither/Nor",
        "Either/Or", "Greater/Lesser (vague)", "Greater/Lesser (specific)", "Unaligned Pair"]

    for category in primer_categories:
        var cat_min: int = _primer_category_min(category)
        var current_count2: int = 0
        for c in chosen:
            if _kind_primer_category(str(c.get("kind", ""))) == category:
                current_count2 += 1
        for c in pitch_chosen:
            if _kind_primer_category(str(c.get("kind", ""))) == category:
                current_count2 += 1
        for c in name_chosen:
            if _kind_primer_category(str(c.get("kind", ""))) == category:
                current_count2 += 1

        while current_count2 < cat_min:
            var picked3: Dictionary = _try_pick_for_category(category, category_kinds, all_touched_stars, pitch_chosen, generated_texts)
            if picked3.is_empty():
                break
            _commit_generated_clue(picked3, chosen, pitch_chosen, name_chosen, all_touched_stars, generated_texts)
            current_count2 += 1
            forced.append("%s: forced (primer floor, %s)" % [str(picked3.get("kind", "")), category])

        if current_count2 < cat_min:
            forced.append("%s: only reached %d/%d, exhausted" % [category, current_count2, cat_min])

    return {"forced": forced}


## _build_color_exact_pool deleted 2026-07-19 — color_exact is now built by
## _sample_and_build directly.

## _build_neg_color_pool deleted 2026-07-19, along with the whole
## _color_negation_texts feature it fed (see field removal below and cache
## version bump) — confirmed dead: computed every generation, serialized
## to cache, deserialized into the overlay's _color_negation_cache, and
## never read again anywhere (not in get_clue_texts(), not displayed by
## the overlay). color_neg clues still exist as a normal generatable kind
## via _sample_and_build; this was a separate, always-on, unused duplicate.


func _compute_alph_rank() -> void:
    _alph_rank = []
    _alph_rank.resize(star_count)
    var order: Array = []
    for i in star_count:
        order.append(i)
    order.sort_custom(func(a, b): return star_names[a] < star_names[b])
    for rank in order.size():
        _alph_rank[order[rank]] = rank
 
 
## _build_alph_extreme_pool deleted 2026-07-19 — label_extreme_ordinal_color
## is now built by _sample_alph_extreme.


func _describe_color_fragment(star_idx: int) -> String:
    return "a %s star" % COLOR_NAMES[star_colors[star_idx]].to_lower()
 
 
func _describe_pitch_fragment(star_idx: int) -> String:
    var pitch_idx: int = star_pitch_index[star_idx] if star_idx < star_pitch_index.size() else 0
    var freq: float = _pitch_freqs[pitch_idx] if pitch_idx < _pitch_freqs.size() else 0.0
    return "a %s note" % note_name_for_freq(freq)
 
 
func _attach_neighbor_fragment(base_text: String, subject: int, verb: String) -> Dictionary:
    var neighbors: Array = proximity[subject]
    if neighbors.is_empty():
        return {"text": base_text, "c": -1}
    var n: int = int(neighbors[_rng.randi_range(0, neighbors.size() - 1)])
    var use_pitch: bool = _rng.randi() % 2 == 0
    var fragment: String = _describe_pitch_fragment(n) if use_pitch else _describe_color_fragment(n)
    var text: String = "%s and %s %s." % [base_text.trim_suffix("."), verb, fragment]
    return {"text": text, "c": n}
 
 
## _build_pitch_exact_pool / _build_pitch_neg_pool / _build_pitch_cmp_pool /
## _build_pitch_group_eq_pool / _build_pitch_extreme_pool /
## _build_pitch_group_cmp_pool / _build_dist_pool / _build_dist_color_pool /
## _build_dist_pitch_pool deleted 2026-07-19 — all superseded by
## sample-then-construct (_sample_and_build's tone_* branches,
## _sample_dist_kind + its 4 thin dispatchers). _build_pitch_cmp_text is
## still used directly by _build_tone_cmp_clue.


## _degree_dist_phrase deleted 2026-07-19 — folded into an inline lambda at
## its one call site (_sample_dist_degree), matching its three siblings
## (color/tone/label) which were already inline lambdas.
## _build_dist_degree_pool / _build_dist_extreme_pool /
## _build_dist_dual_cmp_pool / _build_dist_offset_pool /
## _build_dist_name_pool / _build_between_pool deleted 2026-07-19 — all
## superseded by sample-then-construct (_sample_dist_degree,
## _sample_dist_extreme, and the proximity_dist_dual_cmp/proximity_dist_
## offset/proximity_between branches of _sample_and_build/_sample_between).
## _degree_dist_phrase above is still used directly by _sample_dist_degree.


func _shuffle_array(arr: Array) -> void:
    for i in range(arr.size() - 1, 0, -1):
        var j: int = _rng.randi_range(0, i)
        var tmp = arr[i]
        arr[i] = arr[j]
        arr[j] = tmp
 
 
func _shuffle_dict_array(arr: Array[Dictionary]) -> void:
    for i in range(arr.size() - 1, 0, -1):
        var j: int = _rng.randi_range(0, i)
        var tmp: Dictionary = arr[i]
        arr[i] = arr[j]
        arr[j] = tmp
 
 
# ==================================================
# ASYNC GENERATION — yields to engine every FRAME_BUDGET_MSEC
# ==================================================
# Call with: await puzzle.generate_clues_async()
# Check puzzle.is_generation_complete() before reading get_clue_texts().
 
signal generation_complete(constellation_id: int)
 
func is_generation_complete() -> bool:
    return _generation_complete
 
 
func get_clue_texts(_include_flavor: bool = true) -> Array[String]:
    # v2.3.0: flavor is fully retired — every line returned is either a
    # solver-validated deduction clue or an identity anchor. The parameter
    # is kept only for call-site compatibility and is ignored.
    var texts: Array[String] = []
    for iclue in _final_identity_clues:
        texts.append(str(iclue.get("text", "")))
    for clue in _final_clues:
        texts.append(str(clue.get("text", "")))
    for pclue in _final_pitch_clues:
        texts.append(str(pclue.get("text", "")))
    return texts
 
 
func _clue_difficulty_jitter(clue: Dictionary) -> float:
    var key: String = "%d|%s" % [_difficulty_jitter_salt, JSON.stringify(clue)]
    var h: int = hash(key)
    var frac: float = float(abs(h) % 1000000) / 1000000.0   # 0.0..1.0
    return (frac - 0.5) * 2.0 * DIFFICULTY_JITTER_MAGNITUDE
 
 
func _score_clue_difficulty(clue: Dictionary, solution: Array[int]) -> float:
    var base: float = 1.0
    match clue.get("kind", ""):
        "ordinal_exact":
            base = 10.0
        "ordinal_adjacent":
            base = 8.0
        "ordinal_count_before":
            base = 7.5
        "ordinal_extreme":
            base = 7.0
        "ordinal_neg":
            base = 6.0
        "ordinal_range":
            var width: int = int(clue.get("hi", star_count - 1)) - int(clue.get("lo", 0)) + 1
            base = 5.0 + (float(star_count - width) * 0.25)
        "ordinal_offset":
            base = 7.5 + (float(abs(int(clue.get("offset", 1)))) * 0.3)
        "ordinal_unaligned":
            base = 6.5
        "ordinal_either_or":
            base = 5.5
        "ordinal_neither_nor":
            base = 4.5
        "ordinal_cmp":
            var star_a2: int = clue.get("a", 0)
            var star_b2: int = clue.get("b", 0)
            var gap2: int = abs(solution[star_a2] - solution[star_b2])
            base = 2.0 + (float(gap2) * 0.5)
        "ordinal_chain":
            # Two ordinal_cmp arcs bundled into one clue — scale off the
            # full lo-to-hi span, same gap-bonus shape as ordinal_cmp but a
            # higher base since it fixes the order of three stars at once.
            var chain_lo: int = clue.get("a", 0)
            var chain_hi: int = clue.get("b", 0)
            var chain_gap: int = abs(solution[chain_hi] - solution[chain_lo])
            base = 4.0 + (float(chain_gap) * 0.5)
        "ordinal_group_cmp_color":
            base = 4.0 + (float(clue.get("targets", []).size()) * 0.8)
        "ordinal_group_cmp_tone":
            base = 4.0 + (float(clue.get("targets", []).size()) * 0.8)
        "tone_exact":
            base = 9.0
        "tone_neg":
            base = 5.5
        "tone_cmp":
            base = 4.5
        "tone_group_eq":
            base = 3.5
        "tone_extreme":
            base = 7.0
        "tone_group_cmp_color":
            base = 4.0 + (float(clue.get("targets", []).size()) * 0.8)
        "tone_all_diff":
            base = 6.0
        "color_neg":
            base = 4.0
        "proximity_neg_adjacent":
            base = 5.0
        "proximity_dist_color", "proximity_dist_tone", "proximity_dist_degree", "proximity_dist_label":
            base = 8.5
        "proximity_between":
            base = 8.0
        "proximity_degree_exact":
            base = 5.0
        "proximity_degree_group_eq":
            base = 3.0
        "proximity_degree_extreme":
            base = 5.5
        "proximity_degree_group_cmp_color":
            base = 3.5 + (float(clue.get("targets", []).size()) * 0.8)
        "label_extreme_ordinal_color":
            base = 6.5
        "unique_list_n":
            # Scales with N — a 5-way clue eliminates 4 anchor dots from
            # the deduced rank at once, more information-dense than a
            # 3-way one.
            base = 5.0 + (float(clue.get("n", 3)) * 1.5)
    return base + _clue_difficulty_jitter(clue)


# ==================================================
# SEQUENTIAL/CHAINED GENERATOR — first pass, 2026-07-19
# ==================================================
# The user's redesign: rank primer CATEGORIES by entropic bias, generate one
# clue at a time in that ranked order, each new clue sharing exactly one
# star with the PREVIOUS clue (chaining, so the clue graph stays connected
# instead of producing islands), rerolling/skipping when a candidate adds no
# new information to the shared solving grid. This supersedes the old
# entropy-greedy-then-trim-then-force dance: nothing redundant is ever added
# in the first place, so there's no trim pass, and primer coverage happens
# by construction (every category gets tried) instead of a bolt-on forcing
# pass. See constellation_puzzle_sequential_generator memory for full design
# context and open scope notes.
#
# SEQUENCE AXIS ONLY for this first pass, and only one representative clue
# kind per primer category (True: ordinal_exact, False: ordinal_neg,
# Neither/Nor: ordinal_neither_nor, Either/Or: ordinal_either_or,
# Greater/Lesser vague: ordinal_cmp, Greater/Lesser specific: ordinal_offset,
# Unaligned Pair: ordinal_unaligned, Multi-Elimination: unique_list_n).
# Pitch/Name axis integration and full kind-taxonomy coverage are follow-up
# work once this core mechanic is validated in-game — see task tracking.
#
# The "redundancy check" and "saturation" condition both reuse the existing,
# already-correct _possibility_grid_for_clues/_solve rather than building a
# new grid representation: a candidate "adds information" if the Sequence
# possibility grid actually changes when it's added, and the loop stops once
# _solve reports a unique solution — exactly the shared-grid check the
# redesign calls for, without re-deriving what _possibility_grid_for_clues
# already computes correctly.

const SEQUENTIAL_GEN_STAR_FIELDS := {
    "ordinal_exact":            ["s", "n"],
    "ordinal_neg":              ["s"],
    "ordinal_neither_nor":      ["s1", "s2"],
    "ordinal_either_or":        ["s"],
    "ordinal_unaligned":        ["s1", "s2"],
    "ordinal_offset":           ["a", "b"],
    "ordinal_adjacent":         ["a", "b"],
    "ordinal_cmp":              ["a", "b"],
    "ordinal_chain":            ["a", "mid", "b"],
    "tone_exact":               ["s"],
    "tone_neg":                 ["s"],
    "tone_cmp":                 ["a", "b"],
    "color_exact":              ["s"],
    "color_neg":                ["s"],
    "proximity_dist_dual_cmp":  ["s", "ref_a", "ref_b"],
    "proximity_dist_offset":    ["s", "ref_a", "ref_b"],
    "proximity_degree_exact":           ["s"],
    "proximity_degree_extreme":         ["s"],
    "proximity_degree_group_cmp_color": ["s"],
    "proximity_degree_group_eq":        ["a", "b"],
    "proximity_dist_color":             ["s"],
    "proximity_dist_tone":              ["s"],
    "proximity_dist_degree":            ["s"],
    "proximity_dist_label":             ["s"],
    "proximity_dist_extreme":           ["s", "ref"],
    "proximity_between":                ["mid", "a", "b"],
    "label_extreme_ordinal_color":      ["s"],
    "ordinal_range":                    ["s"],
    "ordinal_extreme":                  ["s"],
    "ordinal_count_before":             ["s"],
    "proximity_neg_adjacent":           ["s"],
    "tone_extreme":                     ["s"],
}
const SEQUENTIAL_GEN_STAR_ARRAY_FIELDS := {
    # kinds whose star references live in an array field rather than fixed
    # scalar field names (unique_list_n's "participants" is handled
    # separately below since each entry is itself a sub-dictionary).
    # Kinds whose text mentions targets/neighbors/group only anonymously
    # (e.g. "fires before every red star," never naming which stars those
    # are) deliberately have NO array-field entry here — only the anchor
    # (already in the scalar table above, or "subjects" below) is actually
    # established for the player, matching the same principle already
    # applied to ordinal_exact's anonymous color-identifying neighbor.
    "tone_all_diff": "stars",
    "tone_group_eq": "stars",
    # group_cmp kinds moved here from the scalar table above: after the
    # merge pass (_merge_group_cmp_kind) combines same-target-group clues,
    # a single clue dict can name MULTIPLE subjects ("Selion and Nyxeai
    # fire before every star that plays G4"), so "subjects" is always an
    # array (even pre-merge, a single-element one) rather than a scalar "s".
    "ordinal_group_cmp_color": "subjects",
    "ordinal_group_cmp_tone": "subjects",
    "tone_group_cmp_color": "subjects",
}


func _clue_touches_stars(clue: Dictionary) -> Array:
    # Generic "which physical stars does this clue reference" extractor,
    # used for the chaining-overlap check. Table-driven; unique_list_n is
    # handled separately since its star list lives in "participants" (an
    # array of sub-dictionaries), not a flat field. Any kind not covered
    # returns an empty array (no known overlap — conservative, not unsound:
    # it just means that candidate can never satisfy chaining except as the
    # very first clue).
    var kind: String = str(clue.get("kind", ""))
    var touched: Array = []
    if kind == "unique_list_n":
        for part in clue.get("participants", []):
            touched.append(int(part["star"]))
        return touched
    if SEQUENTIAL_GEN_STAR_ARRAY_FIELDS.has(kind):
        var array_field: String = SEQUENTIAL_GEN_STAR_ARRAY_FIELDS[kind]
        for v in clue.get(array_field, []):
            touched.append(int(v))
        return touched
    var fields: Array = SEQUENTIAL_GEN_STAR_FIELDS.get(kind, [])
    for f in fields:
        if clue.has(f):
            touched.append(int(clue[f]))
    return touched


func _grids_equal(a: Array, b: Array) -> bool:
    if a.size() != b.size():
        return false
    for i in a.size():
        var row_a: Array = a[i]
        var row_b: Array = b[i]
        if row_a.size() != row_b.size():
            return false
        for j in row_a.size():
            if row_a[j] != row_b[j]:
                return false
    return true


func _clue_adds_information(candidate: Dictionary, all_touched_stars: Dictionary, generated_texts: Dictionary) -> bool:
    # Two-tier check. Early on, "touches a star nothing has mentioned yet"
    # is a cheap, correct proxy for "brings new information" — matches the
    # Used/Unused model directly. But that proxy only holds BEFORE every
    # star has appeared at least once; once all_touched_stars saturates
    # (typically within the first handful of clues, since each one touches
    # 2-3 stars), it would wrongly reject every subsequent candidate
    # forever, even though a real puzzle needs dozens of further clues that
    # relate ALREADY-touched stars in new ways (e.g. a comparison between
    # two stars both mentioned before, in a combination never stated yet).
    # So once no untouched star exists for this candidate, informativeness
    # falls back to "is this the exact same fact as one already generated" —
    # every clue's text is a deterministic function of the ground-truth
    # stars it was built from, so identical text means identical fact,
    # making text-dedup a sound (and cheap) proxy for "new relation."
    for s in _clue_touches_stars(candidate):
        if not all_touched_stars.has(s):
            return true
    return not generated_texts.has(str(candidate.get("text", "")))


const PRIMER_ELIGIBLE_KINDS: Array[String] = [
    "ordinal_exact", "tone_exact", "color_exact",
    "ordinal_neg", "tone_neg",
    "ordinal_neither_nor", "color_neg",
    "ordinal_either_or",
    "ordinal_cmp", "tone_cmp", "proximity_dist_dual_cmp", "ordinal_chain",
    "ordinal_offset", "ordinal_adjacent", "proximity_dist_offset",
    "ordinal_unaligned",
    "unique_list_n", "tone_all_diff",
]

const OTHER_STRUCTURAL_CATEGORY := "Other/Structural"

# Kinds with no primer-category home (_kind_primer_category returns "" for
# all of these) — previously these were ONLY reachable via the old
# pre-built _name_candidate_pool()/seq_pools_by_kind mechanism, drained by
# _ensure_and_trim_names/_force_primer_coverage with no sampling logic of
# their own. Now sample-then-construct like everything else
# (_sample_degree_exact etc.), and get a turn every pass via the
# OTHER_STRUCTURAL_CATEGORY pseudo-category below, so they're generated on
# the same footing as the 8 real primer categories instead of being a
# pool-drain afterthought.
const STRUCTURAL_KINDS: Array[String] = [
    "proximity_dist_color", "proximity_dist_tone", "proximity_dist_degree", "proximity_dist_label",
    "proximity_dist_extreme", "proximity_between", "label_extreme_ordinal_color",
    "ordinal_range", "ordinal_extreme", "ordinal_group_cmp_color", "ordinal_group_cmp_tone",
    "ordinal_count_before", "proximity_neg_adjacent",
    "tone_group_eq", "tone_extreme", "tone_group_cmp_color",
]
# Degree-as-a-primary-fact kinds (proximity_degree_exact/extreme/
# group_cmp_color/group_eq) are DELIBERATELY EXCLUDED from this list — per
# constellation_puzzle_proximity_clue_priority memory, Degree is excluded
# from the automated systematic architecture entirely and hand-tuned per
# constellation later (topology varies too much — e.g. The Archon has every
# star at degree 2, so Degree carries zero discriminating power there).
# _sample_degree_exact/_sample_degree_extreme/_sample_degree_group_cmp/
# _sample_degree_group_eq still exist below as scaffolding for that future
# hand-authoring tool, but are unreachable from the automated generator —
# not wired into STRUCTURAL_KINDS, not in _all_generatable_kinds(), never
# forced by Phase 8. proximity_dist_degree is NOT part of this exclusion —
# it's a Distance-family kind (same as dist_color/tone/label) that happens
# to use degree as an anonymous reference-star descriptor, and already
# self-limits structurally in low-variance topologies via its own
# uniqueness check, same as its three siblings.


func _category_kinds() -> Dictionary:
    # Derived from _kind_primer_category (the one canonical mapping) rather
    # than hand-duplicated, so this can never drift from it.
    var out: Dictionary = {}
    for kind in PRIMER_ELIGIBLE_KINDS:
        var cat: String = _kind_primer_category(kind)
        if cat == "":
            continue
        if not out.has(cat):
            out[cat] = []
        out[cat].append(kind)
    out[OTHER_STRUCTURAL_CATEGORY] = STRUCTURAL_KINDS.duplicate()
    return out


func _pick_from_domain(domain: Array, prefer_touched: bool, all_touched_stars: Dictionary, exclude: Dictionary) -> int:
    # The actual sampling step, per the corrected design: a clue is built
    # from directly-chosen cells, not filtered out of a pre-built list.
    # `domain` restricts candidates to stars that are already known (from
    # ground truth, computed by the caller) to be structurally valid for
    # whatever role is being filled — e.g. only real map-neighbors, only
    # stars reachable from an anchor, only ranks at least 2 apart — so the
    # caller never has to guess-then-reject. prefer_touched=true is the
    # "anchor" role (chain off something already established — falls back
    # to the untouched set when nothing's touched yet, i.e. the very first
    # clue); prefer_touched=false is the "fill" role (bring in fresh,
    # unused information). Falls back to the other set only when the
    # preferred one is empty (e.g. near the very end of generation, when
    # almost every star in the domain is already touched).
    var primary: Array = []
    var fallback: Array = []
    for s in domain:
        var si: int = int(s)
        if exclude.has(si):
            continue
        if all_touched_stars.has(si) == prefer_touched:
            primary.append(si)
        else:
            fallback.append(si)
    if not primary.is_empty():
        return primary[_rng.randi_range(0, primary.size() - 1)]
    if not fallback.is_empty():
        return fallback[_rng.randi_range(0, fallback.size() - 1)]
    return -1


func _pick_star(prefer_touched: bool, all_touched_stars: Dictionary, exclude: Dictionary) -> int:
    var all_stars: Array = []
    for s in star_count:
        all_stars.append(s)
    return _pick_from_domain(all_stars, prefer_touched, all_touched_stars, exclude)


## _build_tone_cmp_clue deleted 2026-07-19 (same session it was added in) —
## folded inline into the tone_cmp branch of _sample_and_build once it
## turned out to have exactly one caller, same as _build_pitch_cmp_text.


const UNIQUE_LIST_DISTANCE_CAT := -1
# Sentinel "cat" value for the self-referential Distance participant below —
# deliberately NOT a Category enum member. Adding a real Category.DISTANCE
# would risk being picked up by the shared unified-grid machinery elsewhere
# (_init_category_grid, Category-keyed dictionaries built via generic
# iteration) that Distance was never meant to participate in here; a plain
# sentinel gets the exact same "no propagation, just anchors a truthful
# descriptive slot" treatment that Color/Pitch/Degree participants already
# fall through to (see the unique_list_n branches in the two propagators
# below, which only special-case Category.SEQUENCE and Category.NAME).

const UNIQUE_LIST_POSITIVE_BIAS := 0.7
# True-cell bias (2026-07-19) — see _attempts_for_category's comment for
# the full reasoning: positive/exact facts cascade via row/column alldiff
# exclusion, negative facts only ever cross out one cell, so an unbiased
# 50/50 coin flip here systematically overproduces low-information negative
# participants relative to their actual value. 0.7 is a starting proxy
# (matches the same "not yet measured, revisit once real puzzles show
# actual effect" caveat as PRIMER_CATEGORY_ENTROPIC_BIAS), not a tuned
# constant — applies to the Sequence/Color/Pitch/Distance sign coin flips
# in the four _unique_list_*_participant functions below.


func _unique_list_star_domain(used_stars: Dictionary) -> Array:
    var domain: Array = []
    for s in star_count:
        if not used_stars.has(s):
            domain.append(s)
    return domain


func _unique_list_name_participant(used_stars: Dictionary, all_touched_stars: Dictionary, prefer_touched: bool) -> Dictionary:
    var star: int = _pick_from_domain(_unique_list_star_domain(used_stars), prefer_touched, all_touched_stars, {})
    if star == -1:
        return {}
    return {"star": star, "cat": int(Category.NAME), "phrase": star_names[star]}


func _unique_list_sequence_participant(used_stars: Dictionary, all_touched_stars: Dictionary, prefer_touched: bool) -> Dictionary:
    var star: int = _pick_from_domain(_unique_list_star_domain(used_stars), prefer_touched, all_touched_stars, {})
    if star == -1:
        return {}
    var true_rank: int = pitch_rank_solution[star]
    var others: Array = []
    for r in star_count:
        if r != true_rank:
            others.append(r)
    # Positive: pins the exact rank (propagated in the Sequence-axis
    # possibility grid's unique_list_n case — excludes every OTHER listed
    # participant from holding this rank). Negative: excludes 1-2 ranks
    # from THIS star's own domain instead — the same shape as ordinal_neg,
    # just packaged as a unique_list_n participant. This was always meant
    # to exist alongside the positive form (the "is"/"is not" duality
    # every other primer category already has), not just the positive one.
    if others.is_empty() or _rng.randf() < UNIQUE_LIST_POSITIVE_BIAS:
        return {"star": star, "cat": int(Category.SEQUENCE), "sign": "pos",
            "phrase": "the star that fires the %s" % _ordinal(true_rank + 1), "rank": true_rank}
    _shuffle_array(others)
    var exclude_count: int = 1 + (_rng.randi() % mini(2, others.size()))
    var excluded: Array = []
    for i in mini(exclude_count, others.size()):
        excluded.append(int(others[i]))
    var ord_phrases: Array = []
    for r in excluded:
        ord_phrases.append(_ordinal(int(r) + 1))
    var phrase: String = ("a star that does not fire %s" % ord_phrases[0]) if ord_phrases.size() == 1 \
        else ("a star that does not fire %s or %s" % [ord_phrases[0], ord_phrases[1]])
    return {"star": star, "cat": int(Category.SEQUENCE), "sign": "neg", "excluded_ranks": excluded, "phrase": phrase}


func _unique_list_color_participant(used_stars: Dictionary, all_touched_stars: Dictionary, prefer_touched: bool) -> Dictionary:
    # No singleton requirement — see the const comment above and the big
    # doc comment on _sample_unique_list_n: Color contributes no
    # propagation of its own in a unique_list_n clue (positive OR
    # negative), so "a yellow star" / "a star that is not yellow" are both
    # perfectly valid, truthful participants regardless of how many stars
    # share that color. Constraint power comes from whichever Name/
    # Sequence participants are also in the clue.
    var star: int = _pick_from_domain(_unique_list_star_domain(used_stars), prefer_touched, all_touched_stars, {})
    if star == -1:
        return {}
    var true_color: int = star_colors[star]
    if _rng.randf() < UNIQUE_LIST_POSITIVE_BIAS:
        return {"star": star, "cat": int(Category.COLOR), "sign": "pos",
            "phrase": "a %s star" % COLOR_NAMES[true_color].to_lower()}
    var others: Array = []
    for c in 4:
        if c != true_color:
            others.append(c)
    _shuffle_array(others)
    var exclude_count: int = 1 + (_rng.randi() % 2)
    var excluded: Array = []
    for i in mini(exclude_count, others.size()):
        excluded.append(int(others[i]))
    var names: Array = []
    for c in excluded:
        names.append(COLOR_NAMES[c].to_lower())
    var phrase: String = ("a star that is not %s" % names[0]) if names.size() == 1 \
        else ("a star that is neither %s nor %s" % [names[0], names[1]])
    return {"star": star, "cat": int(Category.COLOR), "sign": "neg", "excluded_colors": excluded, "phrase": phrase}


func _unique_list_pitch_participant(used_stars: Dictionary, all_touched_stars: Dictionary, prefer_touched: bool) -> Dictionary:
    var star: int = _pick_from_domain(_unique_list_star_domain(used_stars), prefer_touched, all_touched_stars, {})
    if star == -1:
        return {}
    var p: int = star_pitch_index[star] if star < star_pitch_index.size() else 0
    var others: Array = []
    for pi in pitch_count:
        if pi != p:
            others.append(pi)
    if others.is_empty() or _rng.randf() < UNIQUE_LIST_POSITIVE_BIAS:
        return {"star": star, "cat": int(Category.PITCH), "sign": "pos",
            "phrase": "a star that plays %s" % note_name_for_freq(_pitch_freqs[p])}
    _shuffle_array(others)
    var exclude_count: int = 1 + (_rng.randi() % mini(2, others.size()))
    var excluded: Array = []
    for i in mini(exclude_count, others.size()):
        excluded.append(int(others[i]))
    var names: Array = []
    for pi in excluded:
        names.append(note_name_for_freq(_pitch_freqs[pi]))
    var phrase: String = ("a star that does not play %s" % names[0]) if names.size() == 1 \
        else ("a star that plays neither %s nor %s" % [names[0], names[1]])
    return {"star": star, "cat": int(Category.PITCH), "sign": "neg", "excluded_pitches": excluded, "phrase": phrase}


func _pick_false_distance(true_d: int) -> int:
    var candidates: Array = []
    for d in range(1, star_count):
        if d != true_d:
            candidates.append(d)
    if candidates.is_empty():
        return -1
    return int(candidates[_rng.randi_range(0, candidates.size() - 1)])


func _unique_list_distance_participant(used_stars: Dictionary, all_touched_stars: Dictionary, prefer_touched: bool, existing: Array) -> Dictionary:
    # Self-referential: measured against one of the OTHER participants
    # already in this same clue rather than an external fixed reference —
    # "a star N hops away from another star in this list," without saying
    # which one. Needs at least one existing participant to measure
    # against, so this must be resolved after at least one other slot.
    # Negative form asserts a FALSE distance value instead — still a true
    # statement (the real distance genuinely isn't that value), same
    # is/is-not duality as every other participant type here.
    if existing.is_empty():
        return {}
    var primary: Array = []
    var fallback: Array = []
    for s in star_count:
        if used_stars.has(s):
            continue
        if all_touched_stars.has(s) == prefer_touched:
            primary.append(s)
        else:
            fallback.append(s)
    _shuffle_array(primary)
    _shuffle_array(fallback)
    var domain: Array = primary + fallback
    var ref_order: Array = existing.duplicate()
    _shuffle_array(ref_order)
    var want_negative: bool = _rng.randf() >= UNIQUE_LIST_POSITIVE_BIAS
    for star in domain:
        for ref_part in ref_order:
            var ref_star: int = int(ref_part["star"])
            var d: int = _distances[star][ref_star]
            if d <= 0:
                continue
            if not want_negative:
                var word: String = "star" if d == 1 else "stars"
                return {"star": star, "cat": UNIQUE_LIST_DISTANCE_CAT, "sign": "pos", "dist": d,
                    "phrase": "a star %d %s away from another star in this list" % [d, word]}
            var false_d: int = _pick_false_distance(d)
            if false_d == -1:
                continue
            var word2: String = "star" if false_d == 1 else "stars"
            return {"star": star, "cat": UNIQUE_LIST_DISTANCE_CAT, "sign": "neg", "dist": false_d,
                "phrase": "a star that is not %d %s away from another star in this list" % [false_d, word2]}
    return {}


func _sample_unique_list_n(all_touched_stars: Dictionary) -> Dictionary:
    # Multivariate "unique list" clue — asserts N described entities are
    # all different physical stars. Only Name and Sequence participants
    # actually constrain solving (see the unique_list_n branches in
    # _apply_arc_consistency-style propagation and _apply_one_name_filter);
    # Color, Pitch, and Distance are all directly observable by the player
    # already (constellation_puzzle_category_facts_CHECK_FIRST memory), so
    # they don't need to uniquely pin down a specific star to be useful —
    # "a yellow star" or "a star four hops from another star in this list"
    # is a perfectly valid, truthful participant even when several stars
    # match that description. Degree is excluded entirely, consistent with
    # STRUCTURAL_KINDS (hand-tuned per constellation later, not automated).
    # Every slot samples directly from the current unused-star domain — no
    # pre-built per-category candidate list, matching the sample-then-
    # construct standard used everywhere else in this generator.
    const SLOT_TYPES := ["name", "sequence", "color", "pitch", "distance"]
    var slots: Array = SLOT_TYPES.duplicate()
    _shuffle_array(slots)
    if slots.has("distance"):
        slots.erase("distance")
        slots.append("distance")

    var take_n: int = 3 + (_rng.randi() % 3)
    slots = slots.slice(0, mini(take_n, slots.size()))

    var used_stars: Dictionary = {}
    var participants: Array = []
    var need_touched_one: bool = not all_touched_stars.is_empty()

    for slot in slots:
        var entry: Dictionary = {}
        match slot:
            "name":
                entry = _unique_list_name_participant(used_stars, all_touched_stars, need_touched_one)
            "sequence":
                entry = _unique_list_sequence_participant(used_stars, all_touched_stars, need_touched_one)
            "color":
                entry = _unique_list_color_participant(used_stars, all_touched_stars, need_touched_one)
            "pitch":
                entry = _unique_list_pitch_participant(used_stars, all_touched_stars, need_touched_one)
            "distance":
                entry = _unique_list_distance_participant(used_stars, all_touched_stars, need_touched_one, participants)
        if entry.is_empty():
            continue
        used_stars[int(entry["star"])] = true
        if need_touched_one and all_touched_stars.has(int(entry["star"])):
            need_touched_one = false
        participants.append(entry)

    if participants.size() < 3:
        return {}
    _shuffle_array(participants)

    var phrases: Array = []
    for part in participants:
        phrases.append(str(part["phrase"]))
    var n: int = phrases.size()
    var text: String
    match n:
        3:
            text = "%s, %s, and %s are all different stars." % phrases
        4:
            text = "%s, %s, %s, and %s are all different stars." % phrases
        _:
            text = "%s, %s, %s, %s, and %s are all different stars." % phrases
    text = text[0].to_upper() + text.substr(1)
    return {"kind": "unique_list_n", "n": n, "participants": participants.duplicate(true), "text": text}


func _sample_tone_all_diff(all_touched_stars: Dictionary) -> Dictionary:
    # Whether a given color group "all play different notes" is a fixed
    # fact about the constellation (size >= 3 and every member's pitch
    # distinct) — some colors will qualify and others won't, and no amount
    # of resampling changes that. Compute which colors qualify directly,
    # then restrict the anchor to a member of a qualifying group, instead
    # of picking any anchor and discovering afterward whether its color
    # happens to work.
    var qualifying_members: Array = []
    for c in 4:
        var scan_group: Array = []
        for t in star_count:
            if star_colors[t] == c:
                scan_group.append(t)
        if scan_group.size() < 3:
            continue
        var pitches: Dictionary = {}
        var all_distinct: bool = true
        for t in scan_group:
            var p: int = star_pitch_index[int(t)] if int(t) < star_pitch_index.size() else -1
            if pitches.has(p):
                all_distinct = false
                break
            pitches[p] = true
        if all_distinct:
            qualifying_members.append_array(scan_group)
    if qualifying_members.is_empty():
        return {}   # no color group in this constellation happens to have all-distinct pitches — a map fact
    var s: int = _pick_from_domain(qualifying_members, true, all_touched_stars, {})
    if s == -1:
        return {}
    var c: int = star_colors[s]
    var group: Array = []
    for t in star_count:
        if star_colors[t] == c:
            group.append(t)
    var names: Array = []
    for t in group:
        names.append(star_names[int(t)])
    var head: String = ", ".join(names.slice(0, names.size() - 1))
    var text: String = "%s, and %s all play different notes." % [head, names[names.size() - 1]]
    return {"kind": "tone_all_diff", "stars": group.duplicate(), "text": text}


func _sample_degree_exact(all_touched_stars: Dictionary) -> Dictionary:
    # Modal degree is a whole-constellation fact, not a per-anchor one —
    # compute it once, then restrict the anchor domain to stars that
    # actually differ from it (only those can support this clue at all).
    var freq: Dictionary = {}
    for s in star_count:
        var d: int = star_degrees[s]
        freq[d] = int(freq.get(d, 0)) + 1
    var modal_degree: int = -1
    var modal_count: int = -1
    for d in freq.keys():
        if int(freq[d]) > modal_count:
            modal_count = int(freq[d])
            modal_degree = int(d)
    var qualifying: Array = []
    for s in star_count:
        if star_degrees[s] != modal_degree:
            qualifying.append(s)
    if qualifying.is_empty():
        return {}
    var s: int = _pick_from_domain(qualifying, true, all_touched_stars, {})
    if s == -1:
        return {}
    var deg: int = star_degrees[s]
    var text: String
    if deg == 0:
        text = "%s has no connections to any other star." % star_names[s]
    else:
        var word: String = "connection" if deg == 1 else "connections"
        text = "%s has exactly %d %s." % [star_names[s], deg, word]
    return {"kind": "proximity_degree_exact", "s": s, "degree": deg, "text": text}


func _sample_degree_extreme(all_touched_stars: Dictionary) -> Dictionary:
    if star_count == 0 or _max_degree == _min_degree:
        return {}
    var max_stars: Array = []
    var min_stars: Array = []
    for s in star_count:
        if star_degrees[s] == _max_degree:
            max_stars.append(s)
        if star_degrees[s] == _min_degree:
            min_stars.append(s)
    var options: Array = []
    if max_stars.size() == 1:
        options.append({"s": int(max_stars[0]), "is_most": true})
    if min_stars.size() == 1:
        options.append({"s": int(min_stars[0]), "is_most": false})
    if options.is_empty():
        return {}
    var untouched_opts: Array = []
    var touched_opts: Array = []
    for opt in options:
        if all_touched_stars.has(int(opt["s"])):
            touched_opts.append(opt)
        else:
            untouched_opts.append(opt)
    var pool: Array = untouched_opts if not untouched_opts.is_empty() else touched_opts
    var chosen: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
    var s: int = int(chosen["s"])
    var is_most: bool = bool(chosen["is_most"])
    var text: String = "%s has more connections than any other star in the constellation." % star_names[s] if is_most \
        else "%s has fewer connections than any other star in the constellation." % star_names[s]
    return {"kind": "proximity_degree_extreme", "s": s, "is_most": is_most, "text": text}


func _sample_degree_group_cmp(all_touched_stars: Dictionary) -> Dictionary:
    var s: int = _pick_star(true, all_touched_stars, {})
    if s == -1:
        return {}
    var valid_options: Array = []
    for c in 4:
        if c == star_colors[s]:
            continue
        var color_targets: Array = []
        for t in star_count:
            if t != s and star_colors[t] == c:
                color_targets.append(t)
        if color_targets.size() < 2:
            continue
        var more_all: bool = true
        var fewer_all: bool = true
        for t in color_targets:
            var t_deg: int = star_degrees[int(t)]
            if star_degrees[s] <= t_deg:
                more_all = false
            if star_degrees[s] >= t_deg:
                fewer_all = false
        if more_all:
            valid_options.append({"c": c, "targets": color_targets, "s_more": true})
        elif fewer_all:
            valid_options.append({"c": c, "targets": color_targets, "s_more": false})
    if valid_options.is_empty():
        return {}
    var opt: Dictionary = valid_options[_rng.randi_range(0, valid_options.size() - 1)]
    var c: int = int(opt["c"])
    var targets: Array = opt["targets"]
    var s_more: bool = bool(opt["s_more"])
    var text: String = "%s has more connections than every %s star." % [star_names[s], COLOR_NAMES[c].to_lower()] if s_more \
        else "%s has fewer connections than every %s star." % [star_names[s], COLOR_NAMES[c].to_lower()]
    return {"kind": "proximity_degree_group_cmp_color", "s": s, "targets": (targets as Array).duplicate(), "s_more": s_more, "text": text}


func _sample_dist_kind(kind_name: String, attr_lookup: Callable, phrase_fn: Callable, all_touched_stars: Dictionary) -> Dictionary:
    # Mirrors the old _build_dist_pool's per-anchor logic exactly, just
    # scoped to ONE already-chosen anchor instead of looping over every
    # star to build a full pool. The global uniqueness scan (is this
    # distance+value pairing ambiguous anywhere else in the constellation)
    # is a genuine structural fact about the map that can't be skipped —
    # it's what makes "a Blue star" or "a star that plays A4" unambiguous.
    var s: int = _pick_star(true, all_touched_stars, {})
    if s == -1:
        return {}
    var seen_pairs: Dictionary = {}
    var candidates: Array = []
    for other in star_count:
        if other == s:
            continue
        var first_d: int = _distances[s][other]
        if first_d <= 0:
            continue
        var first_v = attr_lookup.call(other)
        var key: String = "%s_%d" % [str(first_v), first_d]
        if seen_pairs.has(key):
            continue
        seen_pairs[key] = true
        candidates.append([other, first_v, first_d])
    var untouched_cands: Array = []
    var touched_cands: Array = []
    for cand in candidates:
        if all_touched_stars.has(int(cand[0])):
            touched_cands.append(cand)
        else:
            untouched_cands.append(cand)
    _shuffle_array(untouched_cands)
    _shuffle_array(touched_cands)
    var ordered: Array = untouched_cands + touched_cands
    for cand in ordered:
        var v = cand[1]
        var d: int = int(cand[2])
        var unique_s: bool = true
        for other_s in star_count:
            if other_s == s:
                continue
            for other2 in star_count:
                if other2 == other_s:
                    continue
                if _distances[other_s][other2] == d and attr_lookup.call(other2) == v:
                    unique_s = false
                    break
            if not unique_s:
                break
        if unique_s:
            var word: String = "star" if d == 1 else "stars"
            var text: String = "%s is %d %s away from %s." % [star_names[s], d, word, phrase_fn.call(v)]
            return {"kind": kind_name, "s": s, "val": v, "dist": d, "text": text}
    return {}


func _sample_dist_color(all_touched_stars: Dictionary) -> Dictionary:
    return _sample_dist_kind("proximity_dist_color",
        func(i): return star_colors[i],
        func(v): return "a %s star" % COLOR_NAMES[int(v)].to_lower(),
        all_touched_stars)


func _sample_dist_tone(all_touched_stars: Dictionary) -> Dictionary:
    return _sample_dist_kind("proximity_dist_tone",
        func(i): return star_pitch_index[i],
        func(v): return "a star that plays %s" % note_name_for_freq(_pitch_freqs[int(v)]),
        all_touched_stars)


func _sample_dist_degree(all_touched_stars: Dictionary) -> Dictionary:
    return _sample_dist_kind("proximity_dist_degree",
        func(i): return star_degrees[i],
        func(v):
            var dv: int = int(v)
            if dv == 0:
                return "a star with no connections"
            return "a star with exactly %d %s" % [dv, ("connection" if dv == 1 else "connections")],
        all_touched_stars)


func _sample_dist_label(all_touched_stars: Dictionary) -> Dictionary:
    return _sample_dist_kind("proximity_dist_label",
        func(i): return star_names[i],
        func(v): return str(v),
        all_touched_stars)


func _sample_between(all_touched_stars: Dictionary) -> Dictionary:
    var mid: int = _pick_star(true, all_touched_stars, {})
    if mid == -1:
        return {}
    var candidates: Array = []
    for a in star_count:
        if a == mid:
            continue
        for b in star_count:
            if b == mid or a >= b:
                continue
            if _distances[a][b] <= 1:
                continue
            if _distances[a][mid] + _distances[mid][b] != _distances[a][b]:
                continue
            var da: int = _distances[a][mid]
            var db: int = _distances[mid][b]
            var unique_mid: bool = true
            for s in star_count:
                if s == a or s == b or s == mid:
                    continue
                if _distances[a][s] == da and _distances[s][b] == db:
                    unique_mid = false
                    break
            if unique_mid:
                candidates.append([a, b])
    if candidates.is_empty():
        return {}
    var untouched_cands: Array = []
    var touched_cands: Array = []
    for c in candidates:
        if not all_touched_stars.has(int(c[0])) or not all_touched_stars.has(int(c[1])):
            untouched_cands.append(c)
        else:
            touched_cands.append(c)
    var pool: Array = untouched_cands if not untouched_cands.is_empty() else touched_cands
    var chosen: Array = pool[_rng.randi_range(0, pool.size() - 1)]
    var a: int = int(chosen[0])
    var b: int = int(chosen[1])
    return {"kind": "proximity_between", "mid": mid, "a": a, "b": b,
        "text": "%s lies between %s and %s." % [star_names[mid], star_names[a], star_names[b]]}


func _sample_alph_extreme(all_touched_stars: Dictionary) -> Dictionary:
    var by_color: Array = [[], [], [], []]
    for s in star_count:
        by_color[star_colors[s]].append(s)
    var options: Array = []
    for c in 4:
        var group: Array = by_color[c]
        if group.size() < 2:
            continue
        var alph_first: int = group[0]
        for t in group:
            if _alph_rank[int(t)] < _alph_rank[alph_first]:
                alph_first = int(t)
        var alph_last: int = group[0]
        for t in group:
            if _alph_rank[int(t)] > _alph_rank[alph_last]:
                alph_last = int(t)
        var group_ranks: Array = []
        for t in group:
            group_ranks.append(pitch_rank_solution[int(t)])
        var min_rank: int = group_ranks.min()
        var max_rank: int = group_ranks.max()
        if pitch_rank_solution[alph_first] == min_rank:
            options.append({"s": alph_first, "group": group, "want_lowest_rank": true, "c": c})
        if pitch_rank_solution[alph_last] == max_rank:
            options.append({"s": alph_last, "group": group, "want_lowest_rank": false, "c": c})
    if options.is_empty():
        return {}
    var untouched_opts: Array = []
    var touched_opts: Array = []
    for opt in options:
        if all_touched_stars.has(int(opt["s"])):
            touched_opts.append(opt)
        else:
            untouched_opts.append(opt)
    var pool: Array = untouched_opts if not untouched_opts.is_empty() else touched_opts
    var chosen: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
    var c: int = int(chosen["c"])
    var want_lowest: bool = bool(chosen["want_lowest_rank"])
    var text: String = "Among the %s stars, the one whose name comes first alphabetically fires earliest." % COLOR_NAMES[c].to_lower() if want_lowest \
        else "Among the %s stars, the one whose name comes last alphabetically fires latest." % COLOR_NAMES[c].to_lower()
    return {"kind": "label_extreme_ordinal_color", "s": int(chosen["s"]), "group": (chosen["group"] as Array).duplicate(),
        "want_lowest_rank": want_lowest, "text": text}


func _sample_range(all_touched_stars: Dictionary) -> Dictionary:
    const MIN_WIDTH := 3
    var s: int = _pick_star(false, all_touched_stars, {})
    if s == -1:
        return {}
    var r: int = pitch_rank_solution[s]
    var first_k: int = maxi(MIN_WIDTH, r + 1)
    var last_k: int = maxi(MIN_WIDTH, star_count - r)
    if first_k <= last_k and first_k < star_count:
        return {"kind": "ordinal_range", "s": s, "lo": 0, "hi": first_k - 1,
            "text": "%s fires among the first %d notes." % [star_names[s], first_k]}
    elif last_k < first_k and last_k < star_count:
        return {"kind": "ordinal_range", "s": s, "lo": star_count - last_k, "hi": star_count - 1,
            "text": "%s fires among the last %d notes." % [star_names[s], last_k]}
    return {}


func _sample_extreme(all_touched_stars: Dictionary) -> Dictionary:
    var eligible: Array = []
    for s in star_count:
        if proximity[s].size() >= 2:
            eligible.append(s)
    if eligible.is_empty():
        return {}
    var s: int = _pick_from_domain(eligible, true, all_touched_stars, {})
    if s == -1:
        return {}
    return _build_extreme_clue(s)


func _sample_group_cmp_color(all_touched_stars: Dictionary) -> Dictionary:
    var s: int = _pick_star(true, all_touched_stars, {})
    if s == -1:
        return {}
    var valid_options: Array = []
    for c in 4:
        if c == star_colors[s]:
            continue
        var color_targets: Array = []
        for t in star_count:
            if t != s and star_colors[t] == c:
                color_targets.append(t)
        if color_targets.size() < 2:
            continue
        var before_all: bool = true
        var after_all: bool = true
        for t in color_targets:
            if pitch_rank_solution[s] > pitch_rank_solution[int(t)]:
                before_all = false
            else:
                after_all = false
        if before_all:
            valid_options.append({"targets": color_targets, "s_first": true, "c": c})
        elif after_all:
            valid_options.append({"targets": color_targets, "s_first": false, "c": c})
    if valid_options.is_empty():
        return {}
    var opt: Dictionary = valid_options[_rng.randi_range(0, valid_options.size() - 1)]
    var c: int = int(opt["c"])
    var targets: Array = opt["targets"]
    var s_first: bool = bool(opt["s_first"])
    var text: String = "%s fires before every %s star." % [star_names[s], COLOR_NAMES[c].to_lower()] if s_first \
        else "%s fires after every %s star." % [star_names[s], COLOR_NAMES[c].to_lower()]
    return {"kind": "ordinal_group_cmp_color", "subjects": [s], "targets": (targets as Array).duplicate(), "s_first": s_first, "text": text}


func _sample_group_cmp_tone(all_touched_stars: Dictionary) -> Dictionary:
    var s: int = _pick_star(true, all_touched_stars, {})
    if s == -1:
        return {}
    var valid_options: Array = []
    for p in pitch_count:
        if p == star_pitch_index[s]:
            continue
        var tone_targets: Array = []
        for t in star_count:
            if t != s and star_pitch_index[t] == p:
                tone_targets.append(t)
        if tone_targets.size() < 2:
            continue
        var before_all: bool = true
        var after_all: bool = true
        for t in tone_targets:
            if pitch_rank_solution[s] > pitch_rank_solution[int(t)]:
                before_all = false
            else:
                after_all = false
        if before_all:
            valid_options.append({"targets": tone_targets, "s_first": true, "p": p})
        elif after_all:
            valid_options.append({"targets": tone_targets, "s_first": false, "p": p})
    if valid_options.is_empty():
        return {}
    var opt: Dictionary = valid_options[_rng.randi_range(0, valid_options.size() - 1)]
    var chosen_p: int = int(opt["p"])
    var targets: Array = opt["targets"]
    var s_first: bool = bool(opt["s_first"])
    var text: String = "%s fires before every star that plays %s." % [star_names[s], note_name_for_freq(_pitch_freqs[chosen_p])] if s_first \
        else "%s fires after every star that plays %s." % [star_names[s], note_name_for_freq(_pitch_freqs[chosen_p])]
    return {"kind": "ordinal_group_cmp_tone", "subjects": [s], "targets": (targets as Array).duplicate(), "s_first": s_first, "text": text}


func _sample_count_before(all_touched_stars: Dictionary) -> Dictionary:
    var eligible: Array = []
    for s in star_count:
        var scan_nbrs: Array = proximity[s]
        if scan_nbrs.size() < 2:
            continue
        var scan_k: int = 0
        for n in scan_nbrs:
            if pitch_rank_solution[int(n)] < pitch_rank_solution[s]:
                scan_k += 1
        if scan_k == 0 or scan_k == scan_nbrs.size():
            continue
        eligible.append(s)
    if eligible.is_empty():
        return {}
    var s: int = _pick_from_domain(eligible, true, all_touched_stars, {})
    if s == -1:
        return {}
    var nbrs: Array = proximity[s]
    var k: int = 0
    var nb_copy: Array = []
    for n in nbrs:
        nb_copy.append(int(n))
        if pitch_rank_solution[int(n)] < pitch_rank_solution[s]:
            k += 1
    return {"kind": "ordinal_count_before", "s": s, "neighbors": nb_copy, "k": k,
        "text": "Exactly %d of %s's connected stars fire before it." % [k, star_names[s]]}


func _sample_neg_adjacent(all_touched_stars: Dictionary) -> Dictionary:
    var star_at_rank: Array = []
    star_at_rank.resize(star_count)
    for s in star_count:
        star_at_rank[pitch_rank_solution[s]] = s
    var eligible: Array = []
    for s in star_count:
        var neighbor_set: Dictionary = {}
        for n in proximity[s]:
            neighbor_set[int(n)] = true
        var has_candidate: bool = false
        for r in star_count:
            var holder: int = star_at_rank[r]
            if holder == s or neighbor_set.has(holder):
                continue
            has_candidate = true
            break
        if has_candidate:
            eligible.append(s)
    if eligible.is_empty():
        return {}
    var s: int = _pick_from_domain(eligible, false, all_touched_stars, {})
    if s == -1:
        return {}
    var neighbor_set2: Dictionary = {}
    for n in proximity[s]:
        neighbor_set2[int(n)] = true
    var candidates: Array = []
    for r in star_count:
        var holder: int = star_at_rank[r]
        if holder == s or neighbor_set2.has(holder):
            continue
        candidates.append(r)
    var r: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
    var text: String = "%s is not connected to the %s." % [star_names[s], _ordinal(r + 1)]
    if _rng.randi() % 2 == 0:
        var use_pitch: bool = _rng.randi() % 2 == 0
        if use_pitch:
            text = "%s and plays %s." % [text.trim_suffix("."), _describe_pitch_fragment(s)]
        else:
            text = "%s and is %s." % [text.trim_suffix("."), _describe_color_fragment(s)]
    return {"kind": "proximity_neg_adjacent", "s": s, "r": r, "text": text}


func _sample_tone_group_eq(all_touched_stars: Dictionary) -> Dictionary:
    var by_pitch: Dictionary = {}
    for s in star_count:
        var s_p: int = star_pitch_index[s] if s < star_pitch_index.size() else 0
        if not by_pitch.has(s_p):
            by_pitch[s_p] = []
        by_pitch[s_p].append(s)
    var qualifying_members: Array = []
    for p in by_pitch.keys():
        if (by_pitch[p] as Array).size() >= 2:
            qualifying_members.append_array(by_pitch[p])
    if qualifying_members.is_empty():
        return {}
    var anchor: int = _pick_from_domain(qualifying_members, true, all_touched_stars, {})
    if anchor == -1:
        return {}
    var p: int = star_pitch_index[anchor] if anchor < star_pitch_index.size() else 0
    var group: Array = by_pitch[p]
    var names: Array = []
    for s in group:
        names.append(star_names[int(s)])
    var text: String
    if group.size() == 2:
        text = "%s and %s play the same note." % [names[0], names[1]]
    else:
        var head: String = ", ".join(names.slice(0, names.size() - 1))
        text = "%s, and %s all play the same note." % [head, names[names.size() - 1]]
    return {"kind": "tone_group_eq", "stars": group.duplicate(), "text": text}


func _sample_tone_extreme(all_touched_stars: Dictionary) -> Dictionary:
    var eligible: Array = []
    for s in star_count:
        if proximity[s].size() >= 2:
            eligible.append(s)
    if eligible.is_empty():
        return {}
    var s: int = _pick_from_domain(eligible, true, all_touched_stars, {})
    if s == -1:
        return {}
    var nbrs: Array = proximity[s]
    var sp: int = star_pitch_index[s] if s < star_pitch_index.size() else 0
    var s_rank: int = _pitch_freq_rank[sp]
    var strictly_lowest: bool = true
    var strictly_highest: bool = true
    for n in nbrs:
        var np: int = star_pitch_index[int(n)] if int(n) < star_pitch_index.size() else 0
        var nr: int = _pitch_freq_rank[np]
        if nr <= s_rank:
            strictly_lowest = false
        if nr >= s_rank:
            strictly_highest = false
    var nb_copy: Array = []
    for n in nbrs:
        nb_copy.append(int(n))
    if strictly_lowest:
        return {"kind": "tone_extreme", "s": s, "neighbors": nb_copy, "want_lowest": true,
            "text": "%s plays the lowest note among the stars it connects to." % star_names[s]}
    elif strictly_highest:
        return {"kind": "tone_extreme", "s": s, "neighbors": nb_copy, "want_lowest": false,
            "text": "%s plays the highest note among the stars it connects to." % star_names[s]}
    return {}


func _sample_tone_group_cmp_color(all_touched_stars: Dictionary) -> Dictionary:
    var s: int = _pick_star(true, all_touched_stars, {})
    if s == -1:
        return {}
    var sp: int = star_pitch_index[s] if s < star_pitch_index.size() else 0
    var s_rank: int = _pitch_freq_rank[sp]
    var valid_options: Array = []
    for c in 4:
        if c == star_colors[s]:
            continue
        var color_targets: Array = []
        for t in star_count:
            if t != s and star_colors[t] == c:
                color_targets.append(t)
        if color_targets.size() < 2:
            continue
        var lower_all: bool = true
        var higher_all: bool = true
        for t in color_targets:
            var tp: int = star_pitch_index[int(t)] if int(t) < star_pitch_index.size() else 0
            var t_rank: int = _pitch_freq_rank[tp]
            if s_rank >= t_rank:
                lower_all = false
            if s_rank <= t_rank:
                higher_all = false
        if lower_all:
            valid_options.append({"targets": color_targets, "s_lower": true, "c": c})
        elif higher_all:
            valid_options.append({"targets": color_targets, "s_lower": false, "c": c})
    if valid_options.is_empty():
        return {}
    var opt: Dictionary = valid_options[_rng.randi_range(0, valid_options.size() - 1)]
    var c: int = int(opt["c"])
    var targets: Array = opt["targets"]
    var s_lower: bool = bool(opt["s_lower"])
    var text: String = "%s plays a lower note than every %s star." % [star_names[s], COLOR_NAMES[c].to_lower()] if s_lower \
        else "%s plays a higher note than every %s star." % [star_names[s], COLOR_NAMES[c].to_lower()]
    return {"kind": "tone_group_cmp_color", "subjects": [s], "targets": (targets as Array).duplicate(), "s_lower": s_lower, "text": text}


func _sample_dist_extreme(all_touched_stars: Dictionary) -> Dictionary:
    var ref: int = _pick_star(true, all_touched_stars, {})
    if ref == -1:
        return {}
    var min_dist: int = -1
    var min_star: int = -1
    var min_tied: bool = false
    var max_dist: int = -1
    var max_star: int = -1
    var max_tied: bool = false
    for s in star_count:
        if s == ref:
            continue
        var d: int = _distances[s][ref]
        if d < 0:
            continue
        if min_dist == -1 or d < min_dist:
            min_dist = d
            min_star = s
            min_tied = false
        elif d == min_dist:
            min_tied = true
        if max_dist == -1 or d > max_dist:
            max_dist = d
            max_star = s
            max_tied = false
        elif d == max_dist:
            max_tied = true
    var options: Array = []
    if min_star != -1 and not min_tied:
        options.append({"s": min_star, "want_least": true})
    if max_star != -1 and not max_tied:
        options.append({"s": max_star, "want_least": false})
    if options.is_empty():
        return {}
    var untouched_opts: Array = []
    var touched_opts: Array = []
    for opt in options:
        if all_touched_stars.has(int(opt["s"])):
            touched_opts.append(opt)
        else:
            untouched_opts.append(opt)
    var pool: Array = untouched_opts if not untouched_opts.is_empty() else touched_opts
    var chosen: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
    var s: int = int(chosen["s"])
    var want_least: bool = bool(chosen["want_least"])
    var text: String = "%s is the star closest to %s." % [star_names[s], star_names[ref]] if want_least \
        else "%s is the star farthest from %s." % [star_names[s], star_names[ref]]
    return {"kind": "proximity_dist_extreme", "s": s, "ref": ref, "want_least": want_least, "text": text}


func _sample_degree_group_eq(all_touched_stars: Dictionary) -> Dictionary:
    var by_degree: Dictionary = {}
    for s in star_count:
        var s_deg: int = star_degrees[s]
        if not by_degree.has(s_deg):
            by_degree[s_deg] = []
        by_degree[s_deg].append(s)
    var qualifying_members: Array = []
    for deg in by_degree.keys():
        if (by_degree[deg] as Array).size() >= 2:
            qualifying_members.append_array(by_degree[deg])
    if qualifying_members.is_empty():
        return {}
    var a: int = _pick_from_domain(qualifying_members, true, all_touched_stars, {})
    if a == -1:
        return {}
    var deg: int = star_degrees[a]
    var group: Array = by_degree[deg]
    var partner_domain: Array = []
    for t in group:
        if int(t) != a:
            partner_domain.append(int(t))
    if partner_domain.is_empty():
        return {}
    var b: int = _pick_from_domain(partner_domain, false, all_touched_stars, {a: true})
    if b == -1:
        return {}
    var word: String = "connection" if deg == 1 else "connections"
    var lo: int = mini(a, b)
    var hi: int = maxi(a, b)
    return {"kind": "proximity_degree_group_eq", "a": lo, "b": hi, "degree": deg,
        "text": "%s and %s have the same number of connections (%d %s)." % [star_names[lo], star_names[hi], deg, word]}


func _sample_and_build(kind: String, all_touched_stars: Dictionary) -> Dictionary:
    # One clue, built directly from stars chosen right now via _pick_star —
    # never scanned out of a pre-built combinatorial list. Ground truth is
    # read at the moment of construction, so every returned dict is valid
    # by construction; {} means this specific kind/star combo doesn't
    # satisfy that kind's own structural requirement (e.g. no adjacent-rank
    # predecessor, or an offset too small to phrase), not "already used."
    match kind:
        "ordinal_exact":
            # Anchor domain: only stars with >=2 neighbors can possibly
            # support this template at all (need a named neighbor plus a
            # separate one to source the color from) — restrict up front
            # rather than sampling any star and discovering it can't work.
            var exact_anchors: Array = []
            for cand in star_count:
                if proximity[cand].size() >= 2:
                    exact_anchors.append(cand)
            if exact_anchors.is_empty():
                return {}
            var s: int = _pick_from_domain(exact_anchors, true, all_touched_stars, {})
            if s == -1:
                return {}
            # For THIS specific anchor, compute every (n, color) pairing
            # that genuinely satisfies the uniqueness requirement directly
            # from ground truth, then choose among those — never guess a
            # neighbor and check afterward.
            var valid_options: Array = []
            for n1 in proximity[s]:
                for n2 in proximity[s]:
                    if n1 == n2:
                        continue
                    var cc: int = star_colors[int(n2)]
                    if _exact_desc_is_unique(s, int(n1), cc):
                        valid_options.append([int(n1), cc])
            if valid_options.is_empty():
                return {}   # this anchor's neighborhood genuinely can't phrase this clue — a map fact, not a bad guess
            var untouched_options: Array = []
            var touched_options: Array = []
            for opt in valid_options:
                if all_touched_stars.has(int(opt[0])):
                    touched_options.append(opt)
                else:
                    untouched_options.append(opt)
            var option_pool: Array = untouched_options if not untouched_options.is_empty() else touched_options
            var chosen_opt: Array = option_pool[_rng.randi_range(0, option_pool.size() - 1)]
            var n: int = int(chosen_opt[0])
            var color_c: int = int(chosen_opt[1])
            var text: String = "The %s is connected to %s and a %s star." % [
                _ordinal(pitch_rank_solution[s] + 1), star_names[n], COLOR_NAMES[color_c].to_lower()]
            return {"kind": "ordinal_exact", "s": s, "r": pitch_rank_solution[s], "n": n, "text": text}
        "tone_exact":
            var s2: int = _pick_star(false, all_touched_stars, {})
            if s2 == -1:
                return {}
            var p: int = star_pitch_index[s2] if s2 < star_pitch_index.size() else 0
            return {"kind": "tone_exact", "s": s2, "p": p, "text": "%s plays %s." % [star_names[s2], _describe_pitch_fragment(s2)]}
        "color_exact":
            var s3: int = _pick_star(false, all_touched_stars, {})
            if s3 == -1:
                return {}
            var c3: int = star_colors[s3]
            return {"kind": "color_exact", "s": s3, "c": c3, "text": "%s is a %s star." % [star_names[s3], COLOR_NAMES[c3].to_lower()]}
        "ordinal_neg":
            var s4: int = _pick_star(false, all_touched_stars, {})
            if s4 == -1:
                return {}
            var true_r: int = pitch_rank_solution[s4]
            var wrong: Array = []
            for r in star_count:
                if r != true_r:
                    wrong.append(r)
            if wrong.is_empty():
                return {}
            var r4: int = wrong[_rng.randi_range(0, wrong.size() - 1)]
            var base_text: String = "%s is not the %s." % [star_names[s4], _ordinal(r4 + 1)]
            var attached: Dictionary = _attach_neighbor_fragment(base_text, s4, "is connected to")
            return {"kind": "ordinal_neg", "s": s4, "r": r4, "has_mix": attached["c"] != -1, "c": attached["c"], "text": attached["text"]}
        "tone_neg":
            var s5: int = _pick_star(false, all_touched_stars, {})
            if s5 == -1:
                return {}
            var true_pitch: int = star_pitch_index[s5] if s5 < star_pitch_index.size() else 0
            var others: Array = []
            for p2 in pitch_count:
                if p2 != true_pitch:
                    others.append(p2)
            if others.is_empty():
                return {}
            _shuffle_array(others)
            var exclude_count: int = 1 + (_rng.randi() % mini(2, others.size()))
            var excluded: Array = []
            for i in mini(exclude_count, others.size()):
                excluded.append(others[i])
            var names5: Array = []
            for p3 in excluded:
                names5.append(note_name_for_freq(_pitch_freqs[p3]))
            var text5: String
            if names5.size() == 1:
                text5 = "%s does not play %s." % [star_names[s5], names5[0]]
            else:
                text5 = "%s plays neither %s nor %s." % [star_names[s5], names5[0], names5[1]]
            var p_list: Array = []
            for p4 in excluded:
                p_list.append(int(p4))
            return {"kind": "tone_neg", "s": s5, "p_list": p_list, "text": text5}
        "ordinal_neither_nor":
            var s1n: int = _pick_star(true, all_touched_stars, {})
            if s1n == -1:
                return {}
            var s2n: int = _pick_star(false, all_touched_stars, {s1n: true})
            if s2n == -1:
                return {}
            var candidates_r: Array = []
            for r5 in star_count:
                if r5 != pitch_rank_solution[s1n] and r5 != pitch_rank_solution[s2n]:
                    candidates_r.append(r5)
            if candidates_r.is_empty():
                return {}
            var r6: int = candidates_r[_rng.randi_range(0, candidates_r.size() - 1)]
            return {"kind": "ordinal_neither_nor", "s1": s1n, "s2": s2n, "r": r6,
                "text": "Neither %s nor %s fires %s." % [star_names[s1n], star_names[s2n], _ordinal(r6 + 1)]}
        "color_neg":
            var s6c: int = _pick_star(false, all_touched_stars, {})
            if s6c == -1:
                return {}
            var true_color: int = star_colors[s6c]
            var others2: Array = []
            for c2 in 4:
                if c2 != true_color:
                    others2.append(c2)
            _shuffle_array(others2)
            var exclude_count2: int = 1 + (_rng.randi() % 2)
            var excluded2: Array = []
            for i2 in mini(exclude_count2, others2.size()):
                excluded2.append(others2[i2])
            var names2: Array = []
            for c4 in excluded2:
                names2.append(COLOR_NAMES[c4].to_lower())
            var text2: String
            if names2.size() == 1:
                text2 = "%s is not %s." % [star_names[s6c], names2[0]]
            else:
                text2 = "%s is neither %s nor %s." % [star_names[s6c], names2[0], names2[1]]
            return {"kind": "color_neg", "s": s6c, "excluded": excluded2.duplicate(), "text": text2}
        "ordinal_either_or":
            var s7: int = _pick_star(false, all_touched_stars, {})
            if s7 == -1:
                return {}
            var r_true: int = pitch_rank_solution[s7]
            var others3: Array = []
            for r7 in star_count:
                if r7 != r_true:
                    others3.append(r7)
            if others3.is_empty():
                return {}
            var r_decoy: int = others3[_rng.randi_range(0, others3.size() - 1)]
            var r1e: int = mini(r_true, r_decoy)
            var r2e: int = maxi(r_true, r_decoy)
            return {"kind": "ordinal_either_or", "s": s7, "r1": r1e, "r2": r2e,
                "text": "%s fires either %s or %s." % [star_names[s7], _ordinal(r1e + 1), _ordinal(r2e + 1)]}
        "ordinal_cmp":
            var a: int = _pick_star(true, all_touched_stars, {})
            if a == -1:
                return {}
            var b: int = _pick_star(false, all_touched_stars, {a: true})
            if b == -1:
                return {}
            var a_gt_b: bool = pitch_rank_solution[a] > pitch_rank_solution[b]
            var cmp_word: String = SEQ_WORD_LATER if a_gt_b else SEQ_WORD_EARLIER
            return {"kind": "ordinal_cmp", "a": a, "b": b, "a_gt_b": a_gt_b,
                "text": "%s fires %s than %s." % [star_names[a], cmp_word, star_names[b]]}
        "ordinal_chain":
            var cs1: int = _pick_star(true, all_touched_stars, {})
            if cs1 == -1:
                return {}
            var cs2: int = _pick_star(false, all_touched_stars, {cs1: true})
            if cs2 == -1:
                return {}
            var cs3: int = _pick_star(false, all_touched_stars, {cs1: true, cs2: true})
            if cs3 == -1:
                return {}
            var ranked: Array = [cs1, cs2, cs3]
            ranked.sort_custom(func(x, y): return pitch_rank_solution[x] < pitch_rank_solution[y])
            var c_lo: int = int(ranked[0])
            var c_mid: int = int(ranked[1])
            var c_hi: int = int(ranked[2])
            var chain_text: String
            match _rng.randi() % 3:
                0:
                    chain_text = "%s fires after %s but before %s." % [star_names[c_mid], star_names[c_lo], star_names[c_hi]]
                1:
                    chain_text = "%s fires before %s, which fires before %s." % [star_names[c_lo], star_names[c_mid], star_names[c_hi]]
                _:
                    chain_text = "%s fires after %s, which fires after %s." % [star_names[c_hi], star_names[c_mid], star_names[c_lo]]
            return {"kind": "ordinal_chain", "a": c_lo, "mid": c_mid, "b": c_hi, "text": chain_text}
        "tone_cmp":
            var a2: int = _pick_star(true, all_touched_stars, {})
            if a2 == -1:
                return {}
            var b2: int = _pick_star(false, all_touched_stars, {a2: true})
            if b2 == -1:
                return {}
            var fa: float = _freq_for_star(a2)
            var fb: float = _freq_for_star(b2)
            var rel: String = "eq"
            var tone_cmp_text: String
            if is_equal_approx(fa, fb):
                tone_cmp_text = "%s plays the same note as %s." % [star_names[a2], star_names[b2]]
            else:
                rel = "gt" if fa > fb else "lt"
                var tone_word: String = "higher" if fa > fb else "lower"
                tone_cmp_text = "%s plays a %s note than %s." % [star_names[a2], tone_word, star_names[b2]]
            return {"kind": "tone_cmp", "a": a2, "b": b2, "rel": rel, "text": tone_cmp_text}
        "proximity_dist_dual_cmp":
            var s8: int = _pick_star(true, all_touched_stars, {})
            if s8 == -1:
                return {}
            # References must be in s8's own connected component (distance
            # >= 0) — only such stars have a comparable distance at all.
            var reachable8: Array = []
            for cand in star_count:
                if cand != s8 and _distances[s8][cand] >= 0:
                    reachable8.append(cand)
            if reachable8.is_empty():
                return {}
            var ref_a: int = _pick_from_domain(reachable8, false, all_touched_stars, {s8: true})
            if ref_a == -1:
                return {}
            var da: int = _distances[s8][ref_a]
            # ref_b must have a DIFFERENT distance from s8 than ref_a does —
            # restrict its domain to that directly, so da == db (the one
            # case where "farther/closer" is genuinely inexpressible) can
            # never even be sampled.
            var ref_b_domain: Array = []
            for cand in reachable8:
                if cand != ref_a and _distances[s8][cand] != da:
                    ref_b_domain.append(cand)
            if ref_b_domain.is_empty():
                return {}   # every other reachable star ties s8-ref_a's distance — a real map fact
            var ref_b: int = _pick_from_domain(ref_b_domain, false, all_touched_stars, {s8: true, ref_a: true})
            if ref_b == -1:
                return {}
            var db: int = _distances[s8][ref_b]
            var farther_from_a: bool = da > db
            var text4: String
            if farther_from_a:
                text4 = "%s is farther from %s than from %s." % [star_names[s8], star_names[ref_a], star_names[ref_b]]
            else:
                text4 = "%s is closer to %s than to %s." % [star_names[s8], star_names[ref_a], star_names[ref_b]]
            return {"kind": "proximity_dist_dual_cmp", "s": s8, "ref_a": ref_a, "ref_b": ref_b, "farther_from_a": farther_from_a, "text": text4}
        "ordinal_offset":
            var a3: int = _pick_star(true, all_touched_stars, {})
            if a3 == -1:
                return {}
            # b's domain is ranks at least 2 away from a's rank (offsets of
            # 0/1 aren't phrased by this template — 0 is impossible for a
            # distinct star, 1 overlaps ordinal_adjacent's wording) —
            # computed directly rather than sampled-and-rejected.
            var a3_rank: int = pitch_rank_solution[a3]
            var b3_domain: Array = []
            for cand in star_count:
                if cand != a3 and absi(pitch_rank_solution[cand] - a3_rank) >= 2:
                    b3_domain.append(cand)
            if b3_domain.is_empty():
                return {}   # a3's rank has no partner 2+ apart — only possible on tiny constellations
            var b3: int = _pick_from_domain(b3_domain, false, all_touched_stars, {})
            if b3 == -1:
                return {}
            var offset: int = a3_rank - pitch_rank_solution[b3]
            var word: String = "later" if offset > 0 else "earlier"
            return {"kind": "ordinal_offset", "a": a3, "b": b3, "offset": offset,
                "text": "%s fires exactly %d notes %s than %s." % [star_names[a3], absi(offset), word, star_names[b3]]}
        "ordinal_adjacent":
            # Only ranks >= 1 have a predecessor at all — exclude rank 0
            # from the anchor domain directly rather than sampling it and
            # discovering it doesn't work.
            var adj_anchors: Array = []
            for cand in star_count:
                if pitch_rank_solution[cand] >= 1:
                    adj_anchors.append(cand)
            if adj_anchors.is_empty():
                return {}
            var a4: int = _pick_from_domain(adj_anchors, true, all_touched_stars, {})
            if a4 == -1:
                return {}
            var r_a: int = pitch_rank_solution[a4]
            var star_at_rank: Array = []
            star_at_rank.resize(star_count)
            for s9 in star_count:
                star_at_rank[pitch_rank_solution[s9]] = s9
            var b4: int = star_at_rank[r_a - 1]
            return {"kind": "ordinal_adjacent", "a": a4, "b": b4,
                "text": "%s fires immediately after %s." % [star_names[a4], star_names[b4]]}
        "proximity_dist_offset":
            var s10: int = _pick_star(true, all_touched_stars, {})
            if s10 == -1:
                return {}
            var reachable10: Array = []
            for cand in star_count:
                if cand != s10 and _distances[s10][cand] >= 0:
                    reachable10.append(cand)
            if reachable10.is_empty():
                return {}
            var ref_a2: int = _pick_from_domain(reachable10, false, all_touched_stars, {s10: true})
            if ref_a2 == -1:
                return {}
            var da2: int = _distances[s10][ref_a2]
            var ref_b2_domain: Array = []
            for cand in reachable10:
                if cand != ref_a2 and _distances[s10][cand] != da2:
                    ref_b2_domain.append(cand)
            if ref_b2_domain.is_empty():
                return {}
            var ref_b2: int = _pick_from_domain(ref_b2_domain, false, all_touched_stars, {s10: true, ref_a2: true})
            if ref_b2 == -1:
                return {}
            var db2: int = _distances[s10][ref_b2]
            var offset2: int = da2 - db2
            var word2: String = "farther" if offset2 > 0 else "closer"
            var mag: int = absi(offset2)
            var unit: String = "star" if mag == 1 else "stars"
            return {"kind": "proximity_dist_offset", "s": s10, "ref_a": ref_a2, "ref_b": ref_b2, "offset": offset2,
                "text": "%s is exactly %d %s %s from %s than from %s." % [star_names[s10], mag, unit, word2, star_names[ref_a2], star_names[ref_b2]]}
        "ordinal_unaligned":
            var s1u: int = _pick_star(true, all_touched_stars, {})
            if s1u == -1:
                return {}
            var s2u: int = _pick_star(false, all_touched_stars, {s1u: true})
            if s2u == -1:
                return {}
            var r1u: int = pitch_rank_solution[s1u]
            var r2u: int = pitch_rank_solution[s2u]
            var lo: int = mini(r1u, r2u)
            var hi: int = maxi(r1u, r2u)
            return {"kind": "ordinal_unaligned", "s1": s1u, "s2": s2u, "r1": lo, "r2": hi,
                "text": "Of %s and %s, one fires %s and the other %s." % [star_names[s1u], star_names[s2u], _ordinal(lo + 1), _ordinal(hi + 1)]}
        "unique_list_n":
            return _sample_unique_list_n(all_touched_stars)
        "tone_all_diff":
            return _sample_tone_all_diff(all_touched_stars)
        "proximity_degree_exact":
            return _sample_degree_exact(all_touched_stars)
        "proximity_degree_extreme":
            return _sample_degree_extreme(all_touched_stars)
        "proximity_degree_group_cmp_color":
            return _sample_degree_group_cmp(all_touched_stars)
        "proximity_dist_color":
            return _sample_dist_color(all_touched_stars)
        "proximity_dist_tone":
            return _sample_dist_tone(all_touched_stars)
        "proximity_dist_degree":
            return _sample_dist_degree(all_touched_stars)
        "proximity_dist_label":
            return _sample_dist_label(all_touched_stars)
        "proximity_between":
            return _sample_between(all_touched_stars)
        "label_extreme_ordinal_color":
            return _sample_alph_extreme(all_touched_stars)
        "ordinal_range":
            return _sample_range(all_touched_stars)
        "ordinal_extreme":
            return _sample_extreme(all_touched_stars)
        "ordinal_group_cmp_color":
            return _sample_group_cmp_color(all_touched_stars)
        "ordinal_group_cmp_tone":
            return _sample_group_cmp_tone(all_touched_stars)
        "ordinal_count_before":
            return _sample_count_before(all_touched_stars)
        "proximity_neg_adjacent":
            return _sample_neg_adjacent(all_touched_stars)
        "tone_group_eq":
            return _sample_tone_group_eq(all_touched_stars)
        "tone_extreme":
            return _sample_tone_extreme(all_touched_stars)
        "tone_group_cmp_color":
            return _sample_tone_group_cmp_color(all_touched_stars)
        "proximity_dist_extreme":
            return _sample_dist_extreme(all_touched_stars)
        "proximity_degree_group_eq":
            return _sample_degree_group_eq(all_touched_stars)
    return {}


const CONSTRUCT_RETRY_LIMIT := 10

func _attempt_construct(kind: String, all_touched_stars: Dictionary, generated_texts: Dictionary) -> Dictionary:
    # Every branch of _sample_and_build restricts its own sampling domain to
    # combinations ground truth already guarantees are structurally valid
    # (real neighbors, same connected component, ranks far enough apart,
    # etc.) — so a single call very rarely comes back empty. The few
    # remaining {} cases are ones where the specific ANCHOR drawn happens
    # to have no valid completion at all (e.g. ordinal_exact's anchor has
    # neighbors, but none of them yields a color-unique pairing) — a fact
    # about that particular star, not a guess gone wrong. A handful of
    # retries just tries a different anchor; it is not scanning a stale
    # candidate list the way the old pool-based picker did.
    for attempt in CONSTRUCT_RETRY_LIMIT:
        var cand: Dictionary = _sample_and_build(kind, all_touched_stars)
        if cand.is_empty():
            continue
        if _clue_adds_information(cand, all_touched_stars, generated_texts):
            return cand
    return {}


func _try_pick_for_category(cat: String, category_kinds: Dictionary, all_touched_stars: Dictionary, pitch_chosen: Array[Dictionary], generated_texts: Dictionary) -> Dictionary:
    var kinds: Array = (category_kinds.get(cat, []) as Array).duplicate()
    _shuffle_array(kinds)
    for kind in kinds:
        if _kind_home_array(str(kind)) == "pitch" and pitch_chosen.size() >= PITCH_FLAVOR_CLUE_TARGET:
            continue
        var picked: Dictionary = _attempt_construct(str(kind), all_touched_stars, generated_texts)
        if not picked.is_empty():
            return picked
    return {}


func _attempts_for_category(cat: String) -> int:
    # True-cell bias (2026-07-19, per the user's earlier-anticipated design
    # requirement): in an alldiff grid, True/exact cells are vastly
    # outnumbered by False ones (1 True per row vs N-1 False), and a
    # negative fact only ever crosses out one cell, never cascading the
    # way a positive/exact fact does (see the row/column exclusion
    # example worked through with the user). Giving every primer category
    # the same one-attempt-per-pass treatment, regardless of how much
    # information its clues actually carry, systematically overproduces
    # low-value negation clues relative to high-value exact ones — this is
    # what the user flagged needed a bias fix before I'd noticed the
    # symptom myself. Scale attempts-per-pass by the SAME
    # PRIMER_CATEGORY_ENTROPIC_BIAS table already used for ranking order,
    # so high-information categories (Multi-Elimination, True, Greater/
    # Lesser specific, Unaligned Pair) get multiple tries per pass while
    # weak ones (False, Either/Or, Greater/Lesser vague, Neither/Nor) stay
    # at one — no new tuning invented, just reusing the existing measure.
    if not PRIMER_CATEGORY_ENTROPIC_BIAS.has(cat):
        return 1   # Other/Structural — not in the entropic-bias table yet
    var bias: float = float(PRIMER_CATEGORY_ENTROPIC_BIAS[cat])
    return maxi(1, int(round(bias / 4.0)))


func _primer_category_min(cat: String) -> int:
    # Same reasoning as _attempts_for_category, applied to the SURVIVING
    # floor after trimming instead of the attempt rate during generation:
    # a flat PRIMER_CATEGORY_MIN=2 let _trim_sequence_pass legitimately
    # strip Multi-Elimination back to barely anything (2 total, split
    # across unique_list_n and tone_all_diff) even when generation
    # produced a dozen-plus candidates, since 2 technically satisfies "the
    # category isn't empty." Scale the floor itself by the same bias
    # table: Multi-Elimination and True get a materially higher floor,
    # everything else keeps the original minimum.
    if not PRIMER_CATEGORY_ENTROPIC_BIAS.has(cat):
        return PRIMER_CATEGORY_MIN
    var bias: float = float(PRIMER_CATEGORY_ENTROPIC_BIAS[cat])
    return maxi(PRIMER_CATEGORY_MIN, int(round(bias / 3.0)))


const KIND_GIVEUP_ATTEMPTS := 8
# After this many failed _attempt_construct calls for a kind (spread across
# passes, not consecutive), treat it as structurally infeasible for THIS
# constellation instance (e.g. proximity_dist_degree on a uniform-degree
# map) and stop requiring it for coverage — matches the existing "pool
# empty, could not force" acknowledgment Phase 8 used to log, just reached
# by direct repeated attempts instead of a pre-built pool being empty.


func generate_clues_by_primer_type() -> Dictionary:
    # Replaces THREE separate axis-specific generators (Sequence's old
    # entropy-greedy loop, Pitch's old entropy-greedy loop, Name's
    # "_ensure_and_trim_names add-until-unique" loop) with ONE primer-
    # ranked, chained pick loop drawing candidates from all three
    # characteristics at once. Per the corrected design: there is no
    # pre-built candidate pool here at all. Each pick directly SAMPLES
    # specific stars (preferring one already-touched "anchor" plus
    # untouched "fill" stars) and constructs exactly one clue from ground
    # truth on the spot (_attempt_construct/_sample_and_build) — nothing is
    # ever built in bulk and then filtered down.
    #
    # Repeats ranked passes over all 8 categories (plus OTHER_STRUCTURAL_
    # CATEGORY, appended last — the 18 non-primer kinds like ordinal_range/
    # proximity_dist_color/tone_extreme that used to be pool-drain-only
    # backfill get a turn every pass too now, on the same footing, just at
    # lower priority since the entropic ranking table doesn't cover them).
    #
    # CORRECTED, 2026-07-19: a first attempt at folding coverage into this
    # loop made it wait for full coverage before ever setting solved=true —
    # but the ranked-category pass below has no "already have enough" check
    # (it never needed one, since it used to stop the instant solvability
    # was reached). Left running for extra passes waiting on coverage, it
    # kept blindly adding MORE category-driven clues every single pass
    # (up to ~9 per pass, unbounded — there are O(n^2) distinct ordinal_
    # unaligned/either_or/offset facts alone), ballooning the clue count
    # into the hundreds. That, in turn, made the _solve()/_solve_names()
    # backtracking calls this same loop depends on to DETECT solvability
    # slower and more likely to exhaust MAX_BACKTRACK_NODES before
    # confirming uniqueness — a self-defeating spiral: not-yet-detected-
    # solved caused more clues, more clues made solved harder to detect.
    # Confirmed in a real run: seq=405, name=133, solved=false after all 60
    # passes, yet the SAFETY NET at the end (using the exact same
    # accumulated clues) found it genuinely unique — the puzzle WAS solved,
    # the loop just never found out because it kept over-generating while
    # waiting to find out.
    #
    # Fix: two phases, not one blended loop. PHASE A is the original
    # behavior verbatim — ranked-category pass, calling _solve/_solve_names
    # after every single pick, stopping the INSTANT both are unique. PHASE
    # B runs only once Phase A actually succeeded, and does ONLY the
    # coverage/primer-floor sweeps — no ranked-category pass, so no
    # unbounded per-pass growth, and critically NO solver calls at all,
    # since adding more true clues can only ever preserve uniqueness once
    # reached (monotonic — a true fact never un-narrows the solution
    # space), so there's nothing left to verify. Phase B is bounded by
    # kind-count × KIND_GIVEUP_ATTEMPTS + category-count × attempts, a
    # small, fast, fixed amount of work, not a runaway loop.
    var t_start: float = Time.get_ticks_msec()
    var category_order: Array[String] = _primer_categories_by_entropic_bias()
    category_order.append(OTHER_STRUCTURAL_CATEGORY)
    var category_kinds: Dictionary = _category_kinds()
    var all_kinds: Array[String] = _all_generatable_kinds()
    var seq_chosen: Array[Dictionary] = []
    var pitch_chosen: Array[Dictionary] = []
    var name_chosen: Array[Dictionary] = []
    var all_touched_stars: Dictionary = {}   # star_index -> true (set)
    var generated_texts: Dictionary = {}     # text -> true — the post-saturation dedup gate
    var order_log: Array[String] = []
    var has_kind_seen: Dictionary = {}
    var solved: bool = false

    const MAX_TOTAL_PASSES := 60
    const MAX_FAIL_STREAK := 5

    # ---- PHASE A: reach solvability ----
    # CORRECTED, 2026-07-19: completion is now "every cell resolved by pure
    # propagation" (via _refresh_resolved_stars/_commit_generated_clue's
    # returned seq_fully_resolved/name_fully_resolved), not "_solve()/
    # _solve_names() eventually prove uniqueness via backtracking." Those
    # aren't the same thing — backtracking search can confirm a unique
    # answer even when propagation alone left the grid open (it just tries
    # every remaining possibility and finds one survivor), which means a
    # puzzle could ship needing an "assume and check for contradiction"
    # step a human wouldn't necessarily think to take. Per Bogaerts/Gamba/
    # Guns's own ZebraTutor results, well-built clue sets should resolve
    # via pure propagation ~85-90% of the time, with backtracking-style
    # reasoning needed only rarely — so backtracking is demoted below to a
    # safety-net fallback, not the primary completion signal.
    var fail_streak: int = 0
    var pass_num: int = 0
    var seq_fully_resolved: bool = false
    var name_fully_resolved: bool = false
    while not solved and pass_num < MAX_TOTAL_PASSES and fail_streak < MAX_FAIL_STREAK:
        pass_num += 1
        var pass_made_progress: bool = false
        for cat in category_order:
            var attempts_this_cat: int = _attempts_for_category(cat)
            for _attempt_i in attempts_this_cat:
                if solved:
                    break
                var picked: Dictionary = _try_pick_for_category(cat, category_kinds, all_touched_stars, pitch_chosen, generated_texts)
                if picked.is_empty():
                    continue
                pass_made_progress = true
                var picked_kind: String = str(picked.get("kind", ""))
                has_kind_seen[picked_kind] = true
                var home: String = _kind_home_array(picked_kind)
                var resolution: Dictionary = _commit_generated_clue(picked, seq_chosen, pitch_chosen, name_chosen, all_touched_stars, generated_texts)
                order_log.append("%s [%s]: %s" % [cat, home, str(picked.get("text", ""))])
                seq_fully_resolved = bool(resolution.get("seq_fully_resolved", false))
                name_fully_resolved = bool(resolution.get("name_fully_resolved", false))
                if seq_fully_resolved and name_fully_resolved:
                    solved = true
            if solved:
                break
        if solved:
            break
        fail_streak = 0 if pass_made_progress else fail_streak + 1

    # Safety-net fallback: propagation alone never fully closed the grid
    # within the pass budget — check whether the puzzle is ALREADY
    # uniquely determined via one contradiction-style step (backtracking
    # search trying the remaining candidates directly) before giving up.
    # This should be rare; logged distinctly so it's visible how often the
    # generator is actually leaning on it.
    var solved_via_backtracking_fallback: bool = false
    if not solved:
        if _solve(seq_chosen, 2).size() == 1 and _solve_names(seq_chosen, pitch_chosen, name_chosen, 2).size() == 1:
            solved = true
            solved_via_backtracking_fallback = true

    # ---- PHASE B: top up coverage only — bounded, no solver calls ----
    if solved:
        for kind in all_kinds:
            if has_kind_seen.get(kind, false):
                continue
            var kind_attempts: int = 0
            while kind_attempts < KIND_GIVEUP_ATTEMPTS:
                kind_attempts += 1
                if _kind_home_array(kind) == "pitch" and pitch_chosen.size() >= PITCH_FLAVOR_CLUE_TARGET:
                    break
                var picked2: Dictionary = _attempt_construct(kind, all_touched_stars, generated_texts)
                if picked2.is_empty():
                    continue
                has_kind_seen[kind] = true
                _commit_generated_clue(picked2, seq_chosen, pitch_chosen, name_chosen, all_touched_stars, generated_texts)
                order_log.append("%s [coverage %s]: %s" % [kind, _kind_home_array(kind), str(picked2.get("text", ""))])
                break

        for cat in category_order:
            if cat == OTHER_STRUCTURAL_CATEGORY:
                continue
            var cat_count: int = 0
            for c in seq_chosen:
                if _kind_primer_category(str(c.get("kind", ""))) == cat:
                    cat_count += 1
            for c in pitch_chosen:
                if _kind_primer_category(str(c.get("kind", ""))) == cat:
                    cat_count += 1
            for c in name_chosen:
                if _kind_primer_category(str(c.get("kind", ""))) == cat:
                    cat_count += 1
            var cat_min: int = _primer_category_min(cat)
            var attempts: int = 0
            var max_attempts: int = maxi(KIND_GIVEUP_ATTEMPTS, cat_min * 3)
            while cat_count < cat_min and attempts < max_attempts:
                attempts += 1
                var picked3: Dictionary = _try_pick_for_category(cat, category_kinds, all_touched_stars, pitch_chosen, generated_texts)
                if picked3.is_empty():
                    break
                has_kind_seen[str(picked3.get("kind", ""))] = true
                _commit_generated_clue(picked3, seq_chosen, pitch_chosen, name_chosen, all_touched_stars, generated_texts)
                order_log.append("%s [primer floor]: %s" % [cat, str(picked3.get("text", ""))])
                cat_count += 1

    var dt: float = Time.get_ticks_msec() - t_start
    print("[PRIMER_GEN %d] %.0fms, seq=%d pitch=%d name=%d clues, solved=%s (passes=%d), via_backtracking_fallback=%s" % [
        constellation_id, dt, seq_chosen.size(), pitch_chosen.size(), name_chosen.size(), str(solved), pass_num, str(solved_via_backtracking_fallback)])
    for line in order_log:
        print("[PRIMER_GEN %d]   %s" % [constellation_id, line])
    var infeasible_kinds: Array[String] = []
    for kind in all_kinds:
        if not has_kind_seen.get(kind, false):
            infeasible_kinds.append(kind)
    if not infeasible_kinds.is_empty():
        print("[PRIMER_GEN %d] kinds never achieved (structurally infeasible for this constellation): %s" % [
            constellation_id, str(infeasible_kinds)])
    if not solved:
        push_error("ConstellationLogicPuzzle [%d]: STILL NOT UNIQUE after primer-type generation (seq=%d, name=%d) — puzzle unsolvable as configured." % [
            constellation_id, seq_chosen.size(), name_chosen.size()])
    return {"seq": seq_chosen, "pitch": pitch_chosen, "name": name_chosen}


func generate_clues_async(_manual_clue_count: int = -1) -> void:
    _generation_complete = false
    _final_clues.clear()
    _final_pitch_clues.clear()
    _final_identity_clues.clear()
    _difficulty_jitter_salt = _rng.randi()
 
    var t_total_start: float = Time.get_ticks_msec()

    # Every clue kind (all 35 of them — 17 primer-mapped + 18 structural)
    # is now sample-then-constructed on demand by generate_clues_by_primer_type
    # and _force_primer_coverage. There is no pre-built pool of any kind
    # here anymore — see constellation_puzzle_sequential_generator_design
    # memory for the full history of why that used to exist and why it
    # doesn't now.
    _compute_alph_rank()

    # TEMPORARY DEBUG — verifying a player-reported concern about whether
    # proximity_dist_dual_cmp/offset/extreme could compare stars across
    # disconnected graph components (they shouldn't be able to — all three
    # pool builders check _distances >= 0 before ever constructing a clue).
    # Prints every star's name grouped by connected component so this can
    # be verified directly instead of re-tracing a deduction chain. Safe
    # to remove once confirmed.
    var component_of_dbg: Array = []
    component_of_dbg.resize(star_count)
    for i_dbg in star_count:
        component_of_dbg[i_dbg] = -1
    var next_component_dbg: int = 0
    for i_dbg in star_count:
        if component_of_dbg[i_dbg] != -1:
            continue
        for j_dbg in star_count:
            if _distances[i_dbg][j_dbg] != -1:
                component_of_dbg[j_dbg] = next_component_dbg
        next_component_dbg += 1
    var component_report_dbg: Dictionary = {}
    for i_dbg in star_count:
        var comp_dbg: int = component_of_dbg[i_dbg]
        if not component_report_dbg.has(comp_dbg):
            component_report_dbg[comp_dbg] = []
        component_report_dbg[comp_dbg].append(star_names[i_dbg])
    print("[PUZZLE_TIMING %d] DEBUG connected components (star name -> group): %s" % [constellation_id, str(component_report_dbg)])
 
    # ==================================================
    # PHASE 2/3/4 — UNIFIED PRIMER-TYPE GENERATION (2026-07-19)
    # ==================================================
    # Sequence, Pitch, and Name no longer have separate generators. One
    # primer-ranked, chained pick loop (generate_clues_by_primer_type) draws
    # candidates from all three characteristics at once, per primer
    # category — matching _kind_primer_category's existing cross-
    # characteristic groupings (e.g. "True" already spans ordinal_exact +
    # tone_exact + color_exact together), plus the OTHER_STRUCTURAL_CATEGORY
    # pseudo-category for the 18 kinds with no primer-category home. The
    # axis-specific SOLVERS (_solve / _solve_pitch / _solve_names) are
    # unchanged; only the SELECTION process is unified. Every kind is
    # sampled and constructed on demand — nothing is pre-built here.
    var frame_timer: float = Time.get_ticks_msec()
    var t_gen_start: float = Time.get_ticks_msec()
    var gen_result: Dictionary = generate_clues_by_primer_type()
    var chosen: Array[Dictionary] = gen_result["seq"]
    var pitch_chosen: Array[Dictionary] = gen_result["pitch"]
    var name_chosen: Array[Dictionary] = gen_result["name"]
    var gen_dt: float = Time.get_ticks_msec() - t_gen_start
    print("[PUZZLE_TIMING %d] PHASE2/4 (primer-type gen): %.0fms, seq=%d pitch=%d name=%d" % [
        constellation_id, gen_dt, chosen.size(), pitch_chosen.size(), name_chosen.size()])
    if pitch_count > 0:
        var pitch_explain: Dictionary = _explain_pitch_propagation(pitch_chosen)
        print("[PUZZLE_TIMING %d] Pitch propagation-only resolution: %d/%d stars, unresolved=%s" % [
            constellation_id, pitch_explain["resolved_via_propagation"].size(), star_count,
            str(pitch_explain["unresolved_after_propagation"])])
    else:
        print("[PUZZLE_TIMING %d] pitch_count=0, skipping Pitch CSP phase." % constellation_id)

    # ==================================================
    # PHASE 3/5/7 — CROSS-AXIS TRIM FIXPOINT. Alternates full weakest-first
    # sweeps of the sequence, pitch, and name clue sets, each one leaning on
    # the OTHER axes' current (already-trimmed-this-round) clue sets. Repeats
    # until a full round removes nothing from any side.
    # ==================================================
    var t_phase357_start: float = Time.get_ticks_msec()
    var cross_trim_round: int = 0
    var frame_timer_box: Array = [frame_timer]
 
    chosen.sort_custom(func(clue_a, clue_b):
        return _score_clue_difficulty(clue_a, pitch_rank_solution) < _score_clue_difficulty(clue_b, pitch_rank_solution))
    if pitch_count > 0:
        pitch_chosen.sort_custom(func(clue_a, clue_b):
            return _score_pitch_clue_difficulty(clue_a) < _score_pitch_clue_difficulty(clue_b))
 
    # name_chosen already populated above by generate_clues_by_primer_type;
    # _compute_alph_rank() already called above too — not repeating either.
    # There is no more name_pool to build or report on — every Name-axis
    # kind is sampled on demand now, same as Sequence and Pitch.

    while cross_trim_round < MAX_CROSS_TRIM_ROUNDS:
        cross_trim_round += 1
        var round_changed: bool = false

        # Phase 4: the cross-axis restriction functions that used to feed
        # _trim_sequence_pass/_trim_pitch_pass are gone — they were fixed in
        # Phase 2 to always return "no restriction" (Pitch and Sequence are
        # provably independent; no sound restriction was ever derivable
        # between them — see constellation_puzzle_csp_review_findings),
        # making them pure no-ops. Passing [] directly is equivalent and
        # skips rebuilding a full unrestricted grid every round for nothing.
        if await _trim_sequence_pass(chosen, [], frame_timer_box):
            round_changed = true

        # _trim_pitch_pass skipped, 2026-07-19: it shrinks a clue set by
        # checking "still uniquely solvable after removing this clue?",
        # which only makes sense when pitch is aiming for uniqueness. Pitch
        # is now a small fixed-budget flavor layer (PITCH_FLAVOR_CLUE_TARGET)
        # with no uniqueness goal — there's nothing to trim, and running this
        # check drives _solve_pitch's backtracking search against an
        # intentionally under-constrained clue set, blowing its node budget
        # for no benefit.

        # _ensure_and_trim_names removed, 2026-07-19: it was the last
        # remaining piece of the pre-refactor Name generator (plain
        # front-to-back pool drain, no primer-category awareness at all —
        # see constellation_puzzle_sequential_generator_design memory for
        # why that was a problem). generate_clues_by_primer_type's own
        # completion check already requires Name-uniqueness before it stops
        # trying, and _force_primer_coverage (below) now uses the same
        # sample-then-construct primitives for any remaining backfill — so
        # there is nothing left for a separate name-trim step to do.

        if not round_changed:
            break

    if cross_trim_round >= MAX_CROSS_TRIM_ROUNDS:
        push_warning("ConstellationLogicPuzzle [%d]: cross-axis trim hit MAX_CROSS_TRIM_ROUNDS without reaching a fixpoint." % constellation_id)

    frame_timer = float(frame_timer_box[0])
    var phase357_dt: float = Time.get_ticks_msec() - t_phase357_start
    print("[PUZZLE_TIMING %d] PHASE3/5/7 (cross-axis trim, 3-way): %.0fms wall, %d rounds, final_seq_clues=%d, final_pitch_clues=%d, final_name_clues=%d" % [
        constellation_id, phase357_dt, cross_trim_round, chosen.size(), pitch_chosen.size(), name_chosen.size()])

    # Phase 8 needs the same resolved-star + dedup state the primary
    # generator tracked internally — reconstruct it from the clues that
    # actually survived trimming rather than threading it out of
    # generate_clues_by_primer_type, so Phase 8 stays decoupled from the
    # primary loop's internals. Uses the same _refresh_resolved_stars
    # propagation-based check as the primary loop, not the old "mentioned"
    # proxy, so Phase 8's rare fallback activity reasons about the array
    # identically to normal generation.
    var coverage_touched_stars: Dictionary = {}
    var coverage_generated_texts: Dictionary = {}
    _refresh_resolved_stars(chosen, pitch_chosen, name_chosen, coverage_touched_stars)
    for c in chosen:
        coverage_generated_texts[str(c.get("text", ""))] = true
    for c in pitch_chosen:
        coverage_generated_texts[str(c.get("text", ""))] = true
    for c in name_chosen:
        coverage_generated_texts[str(c.get("text", ""))] = true

    var coverage_report: Dictionary = _force_primer_coverage(chosen, pitch_chosen, name_chosen, coverage_touched_stars, coverage_generated_texts)
    print("[PUZZLE_TIMING %d] PHASE8 (primer coverage): forced=%s" % [
        constellation_id, str(coverage_report["forced"])])

    # Merge any group_cmp clues (ordinal_group_cmp_color/tone, tone_group_
    # cmp_color) that ended up describing the same target group with
    # different subjects — two independently-sampled clues like "Selion
    # fires before every star that plays G4" and "Nyxeai fires before every
    # star that plays G4" become one "Selion and Nyxeai fire before..."
    # sentence. Run after Phase 8 since its kind/tab/primer-floor forcing
    # can itself introduce a fresh duplicate.
    _merge_group_cmp_duplicates(chosen, pitch_chosen)

    _print_clue_breakdown_diagnostics(chosen, pitch_chosen, name_chosen)

    _final_clues = chosen
    _final_pitch_clues = pitch_chosen
    _final_identity_clues = name_chosen
 
    var kind_counts: Dictionary = {}
    for clue in chosen:
        var kc: String = str(clue.get("kind", ""))
        kind_counts[kc] = int(kind_counts.get(kc, 0)) + 1
    print("[PUZZLE_TIMING %d] final sequence composition: %s" % [constellation_id, str(kind_counts)])
 
    var pitch_kind_counts: Dictionary = {}
    for pclue in pitch_chosen:
        var pkc: String = str(pclue.get("kind", ""))
        pitch_kind_counts[pkc] = int(pitch_kind_counts.get(pkc, 0)) + 1
    print("[PUZZLE_TIMING %d] final pitch composition: %s" % [constellation_id, str(pitch_kind_counts)])
 
    # ==================================================
    # SAFETY NET — re-verify each axis is unique from its OWN clue set alone,
    # with no cross-axis restriction help at all (the cross-axis restriction
    # functions that used to risk over-trimming were removed entirely in
    # Phase 4 — see the comment above _trim_sequence_pass's call site). This
    # check exists so any future regression, or any other unforeseen
    # over-trim, gets caught here rather than shipping an ambiguous puzzle.
    # Logged unconditionally, clean or not.
    # ==================================================
    var seq_final_solutions: Array = _solve(chosen, 2)
    var seq_final_unique: bool = seq_final_solutions.size() == 1
    if not seq_final_unique:
        push_error("ConstellationLogicPuzzle [%d]: SAFETY NET — sequence clue set is not unique on its own (%d solutions found)." % [constellation_id, seq_final_solutions.size()])

    # NOTE: pitch is deliberately NOT required to be uniquely clue-solvable
    # (see PITCH_FLAVOR_CLUE_TARGET) — players use the Listen mechanic for
    # Pitch. Every pitch clue is built directly from ground truth
    # (star_pitch_index), so a valid solution is guaranteed to exist by
    # construction — there is nothing to SEARCH for here, only a
    # propagation-level sanity check (catches a genuine builder bug, which
    # would show up as a contradiction even before backtracking). Even
    # cap=1 backtracking still exhausted the node budget against a very
    # under-constrained clue set (as few as 2 clues for 15 stars) and
    # returned a false "inconsistent" when it just gave up early — using
    # the propagation-only grid instead avoids backtracking entirely for
    # this check.
    var pitch_final_consistent: bool = true
    if pitch_count > 0:
        pitch_final_consistent = _possibility_grid_for_pitch_clues(pitch_chosen) != null

    var name_final_solutions: Array = _solve_names(chosen, pitch_chosen, name_chosen, 2)
    var name_final_unique: bool = name_final_solutions.size() == 1
    if not name_final_unique:
        push_error("ConstellationLogicPuzzle [%d]: SAFETY NET — name binding is not unique (%d solutions found)." % [constellation_id, name_final_solutions.size()])

    print("[PUZZLE_TIMING %d] SAFETY NET: seq_unique=%s pitch_consistent=%s name_unique=%s" % [
        constellation_id, str(seq_final_unique), str(pitch_final_consistent), str(name_final_unique)])

    # TEMPORARY — Phase 3 verification only. Confirms _propagate_unified
    # reaches the identical possibility grids as the legacy _propagate/
    # _propagate_pitch, and _cross_arc_predicate matches legacy
    # _name_arc_predicate, for this real generated puzzle's clue sets,
    # before Phase 4 migrates anything onto the new engine. Safe to remove
    # once confirmed clean across a few constellations.
    var unified_grid_check: Dictionary = _verify_unified_grid_matches_legacy(chosen, pitch_chosen)
    print("[PUZZLE_TIMING %d] PHASE3 unified-grid verification: seq_matches=%s pitch_matches=%s mismatches=%s" % [
        constellation_id, str(unified_grid_check["sequence_matches"]), str(unified_grid_check["pitch_matches"]),
        str(unified_grid_check["mismatches"])])
    var cross_arc_check: Dictionary = _verify_cross_arc_predicates_match_legacy(chosen, pitch_chosen)
    print("[PUZZLE_TIMING %d] PHASE3 cross-arc predicate verification: matches=%s mismatches=%s" % [
        constellation_id, str(cross_arc_check["matches"]), str(cross_arc_check["mismatches"])])
    var naked_subset_check: Dictionary = _verify_naked_subset_soundness(chosen, pitch_chosen)
    print("[PUZZLE_TIMING %d] PHASE3 naked-subset soundness (oracle, real puzzle): sound=%s violations=%s" % [
        constellation_id, str(naked_subset_check["sound"]), str(naked_subset_check["violations"])])
    var naked_pair_synth_check: Dictionary = _verify_naked_pair_synthetic()
    print("[PUZZLE_TIMING %d] PHASE3 naked-pair synthetic test: pass=%s details=%s" % [
        constellation_id, str(naked_pair_synth_check["pass"]), str(naked_pair_synth_check["details"])])

    var total_dt: float = Time.get_ticks_msec() - t_total_start
    print("[PUZZLE_TIMING %d] TOTAL wall time: %.0fms" % [constellation_id, total_dt])

    _generation_complete = true
    emit_signal("generation_complete", constellation_id)
 
 
# ==================================================
# CACHE SERIALIZATION
# ==================================================
# Clue Dictionaries are plain data (no Callables) so they serialize
# cleanly to JSON via save_manager.gd's existing flow.
 
func to_cache_dict() -> Dictionary:
    return {
        "version":          13,
        "constellation_id": constellation_id,
        "player_seed_used": player_seed_used,
        "star_count":       star_count,
        "star_colors":      star_colors.duplicate(),
        "star_degrees":     star_degrees.duplicate(),
        "star_names":       star_names.duplicate(),
        "pitch_rank_solution": pitch_rank_solution.duplicate(),
        "final_clues":      _final_clues.duplicate(true),
        "generation_complete": _generation_complete,
        "pitch_count":      pitch_count,
        "pitch_freq_rank":  _pitch_freq_rank.duplicate(),
        "final_pitch_clues": _final_pitch_clues.duplicate(true),
        "final_identity_clues": _final_identity_clues.duplicate(true),
    }


func from_cache_dict(data: Dictionary) -> bool:
    # version 11, 2026-07-19: dropped color_negation_texts — confirmed dead
    # (computed and cached but never actually read by the overlay).
    # version 12, same day: ordinal_group_cmp_color/tone and
    # tone_group_cmp_color switched from a single "s" field to a "subjects"
    # array, to support merging same-target-group clues into one sentence
    # naming multiple subjects (_merge_group_cmp_kind).
    # version 13, same day: unique_list_n participants gained "sign"
    # ("pos"/"neg") plus per-sign fields (excluded_ranks/excluded_colors/
    # excluded_pitches/dist) — Sequence/Color/Pitch/Distance participants
    # can now be negative facts ("a star that does not fire 4th or 6th"),
    # not just positive ones. Old cached puzzles are invalidated below and
    # regenerated; no migration needed for any of these bumps since
    # nothing was reading the old fields correctly across them.
    if data.get("version", 0) != 13:
        push_warning("ConstellationLogicPuzzle: cache version mismatch, ignoring cached data.")
        return false
    constellation_id     = int(data.get("constellation_id", -1))
    player_seed_used     = int(data.get("player_seed_used", 0))
    star_count           = int(data.get("star_count", 0))
    _generation_complete = bool(data.get("generation_complete", false))
 
    star_colors = []
    for v in data.get("star_colors", []):
        star_colors.append(int(v))

    star_degrees = []
    for v in data.get("star_degrees", []):
        star_degrees.append(int(v))

    star_names = []
    for v in data.get("star_names", []):
        star_names.append(str(v))
 
    pitch_rank_solution = []
    for v in data.get("pitch_rank_solution", []):
        pitch_rank_solution.append(int(v))
 
    pitch_count = int(data.get("pitch_count", 0))
    _pitch_freq_rank = []
    for v3 in data.get("pitch_freq_rank", []):
        _pitch_freq_rank.append(int(v3))
 
    _final_clues = []
    for raw_clue in data.get("final_clues", []):
        var clue: Dictionary = {}
        var kind: String = str(raw_clue.get("kind", ""))
        clue["kind"] = kind
        clue["text"] = str(raw_clue.get("text", ""))
        match kind:
            "ordinal_cmp":
                clue["a"]      = int(raw_clue.get("a", 0))
                clue["b"]      = int(raw_clue.get("b", 0))
                clue["a_gt_b"] = bool(raw_clue.get("a_gt_b", false))
            "ordinal_chain":
                clue["a"]   = int(raw_clue.get("a", 0))
                clue["mid"] = int(raw_clue.get("mid", 0))
                clue["b"]   = int(raw_clue.get("b", 0))
            "ordinal_adjacent":
                clue["a"] = int(raw_clue.get("a", 0))
                clue["b"] = int(raw_clue.get("b", 0))
            "ordinal_extreme":
                clue["s"]           = int(raw_clue.get("s", 0))
                clue["want_lowest"] = bool(raw_clue.get("want_lowest", true))
                var nb: Array = []
                for v in raw_clue.get("neighbors", []):
                    nb.append(int(v))
                clue["neighbors"] = nb
            "ordinal_exact":
                clue["s"] = int(raw_clue.get("s", 0))
                clue["r"] = int(raw_clue.get("r", 0))
                clue["n"] = int(raw_clue.get("n", -1))
            "ordinal_range":
                clue["s"]  = int(raw_clue.get("s", 0))
                clue["lo"] = int(raw_clue.get("lo", 0))
                clue["hi"] = int(raw_clue.get("hi", 0))
            "ordinal_group_cmp_color":
                var subj: Array = []
                for v in raw_clue.get("subjects", []):
                    subj.append(int(v))
                clue["subjects"] = subj
                var gts: Array = []
                for v in raw_clue.get("targets", []):
                    gts.append(int(v))
                clue["targets"] = gts
                clue["s_first"] = bool(raw_clue.get("s_first", true))
            "ordinal_group_cmp_tone":
                var subj2: Array = []
                for v in raw_clue.get("subjects", []):
                    subj2.append(int(v))
                clue["subjects"] = subj2
                var gts2: Array = []
                for v in raw_clue.get("targets", []):
                    gts2.append(int(v))
                clue["targets"] = gts2
                clue["s_first"] = bool(raw_clue.get("s_first", true))
            "ordinal_count_before":
                clue["s"] = int(raw_clue.get("s", 0))
                var cnb: Array = []
                for v in raw_clue.get("neighbors", []):
                    cnb.append(int(v))
                clue["neighbors"] = cnb
                clue["k"] = int(raw_clue.get("k", 0))
            "ordinal_neg":
                clue["s"]       = int(raw_clue.get("s", 0))
                clue["r"]       = int(raw_clue.get("r", 0))
                clue["has_mix"] = bool(raw_clue.get("has_mix", false))
                clue["c"]       = int(raw_clue.get("c", -1))
            "proximity_neg_adjacent":
                clue["s"] = int(raw_clue.get("s", 0))
                clue["r"] = int(raw_clue.get("r", 0))
            "color_exact":
                clue["s"] = int(raw_clue.get("s", 0))
                clue["c"] = int(raw_clue.get("c", 0))
            "ordinal_neither_nor":
                clue["s1"] = int(raw_clue.get("s1", 0))
                clue["s2"] = int(raw_clue.get("s2", 0))
                clue["r"]  = int(raw_clue.get("r", 0))
            "ordinal_either_or":
                clue["s"]  = int(raw_clue.get("s", 0))
                clue["r1"] = int(raw_clue.get("r1", 0))
                clue["r2"] = int(raw_clue.get("r2", 0))
            "ordinal_unaligned":
                clue["s1"] = int(raw_clue.get("s1", 0))
                clue["s2"] = int(raw_clue.get("s2", 0))
                clue["r1"] = int(raw_clue.get("r1", 0))
                clue["r2"] = int(raw_clue.get("r2", 0))
            "ordinal_offset":
                clue["a"]      = int(raw_clue.get("a", 0))
                clue["b"]      = int(raw_clue.get("b", 0))
                clue["offset"] = int(raw_clue.get("offset", 0))
            "unique_list_n":
                clue["n"] = int(raw_clue.get("n", 3))
                var uparts: Array = []
                for vp in raw_clue.get("participants", []):
                    var vp_dict: Dictionary = vp as Dictionary
                    var part: Dictionary = {
                        "star": int(vp_dict.get("star", 0)),
                        "cat": int(vp_dict.get("cat", 0)),
                        "phrase": str(vp_dict.get("phrase", "")),
                    }
                    if vp_dict.has("rank"):
                        part["rank"] = int(vp_dict.get("rank", 0))
                    if vp_dict.has("sign"):
                        part["sign"] = str(vp_dict.get("sign", "pos"))
                    if vp_dict.has("excluded_ranks"):
                        var er: Array = []
                        for v in vp_dict.get("excluded_ranks", []):
                            er.append(int(v))
                        part["excluded_ranks"] = er
                    if vp_dict.has("excluded_colors"):
                        var ec: Array = []
                        for v in vp_dict.get("excluded_colors", []):
                            ec.append(int(v))
                        part["excluded_colors"] = ec
                    if vp_dict.has("excluded_pitches"):
                        var ep: Array = []
                        for v in vp_dict.get("excluded_pitches", []):
                            ep.append(int(v))
                        part["excluded_pitches"] = ep
                    if vp_dict.has("dist"):
                        part["dist"] = int(vp_dict.get("dist", 0))
                    uparts.append(part)
                clue["participants"] = uparts
        _final_clues.append(clue)
 
    _final_pitch_clues = []
    for raw_pclue in data.get("final_pitch_clues", []):
        var pclue: Dictionary = {}
        var pkind: String = str(raw_pclue.get("kind", ""))
        pclue["kind"] = pkind
        pclue["text"] = str(raw_pclue.get("text", ""))
        match pkind:
            "tone_exact":
                pclue["s"] = int(raw_pclue.get("s", 0))
                pclue["p"] = int(raw_pclue.get("p", 0))
            "tone_neg":
                pclue["s"] = int(raw_pclue.get("s", 0))
                var plist: Array = []
                for v4 in raw_pclue.get("p_list", []):
                    plist.append(int(v4))
                pclue["p_list"] = plist
            "tone_cmp":
                pclue["a"]   = int(raw_pclue.get("a", 0))
                pclue["b"]   = int(raw_pclue.get("b", 0))
                pclue["rel"] = str(raw_pclue.get("rel", "eq"))
            "tone_group_eq":
                var pst: Array = []
                for v5 in raw_pclue.get("stars", []):
                    pst.append(int(v5))
                pclue["stars"] = pst
            "tone_extreme":
                pclue["s"] = int(raw_pclue.get("s", 0))
                var pnb: Array = []
                for v6 in raw_pclue.get("neighbors", []):
                    pnb.append(int(v6))
                pclue["neighbors"] = pnb
                pclue["want_lowest"] = bool(raw_pclue.get("want_lowest", true))
            "tone_group_cmp_color":
                var psubj: Array = []
                for v9 in raw_pclue.get("subjects", []):
                    psubj.append(int(v9))
                pclue["subjects"] = psubj
                var pgt: Array = []
                for v7 in raw_pclue.get("targets", []):
                    pgt.append(int(v7))
                pclue["targets"] = pgt
                pclue["s_lower"] = bool(raw_pclue.get("s_lower", true))
            "tone_all_diff":
                var pstars: Array = []
                for v8 in raw_pclue.get("stars", []):
                    pstars.append(int(v8))
                pclue["stars"] = pstars
        _final_pitch_clues.append(pclue)
 
    _final_identity_clues = []
    for raw_iclue in data.get("final_identity_clues", []):
        var iclue: Dictionary = {}
        var ikind: String = str(raw_iclue.get("kind", ""))
        iclue["kind"] = ikind
        iclue["text"] = str(raw_iclue.get("text", ""))
        match ikind:
            # NOTE: _build_dist_pool() (shared by dist_color/tone/degree/label)
            # writes the shared value under "val", not "c" — this branch used
            # to read the wrong key and silently reconstruct val=0 every time.
            "proximity_dist_color", "proximity_dist_tone", "proximity_dist_degree":
                iclue["s"]    = int(raw_iclue.get("s", 0))
                iclue["val"]  = int(raw_iclue.get("val", 0))
                iclue["dist"] = int(raw_iclue.get("dist", 0))
            "proximity_dist_label":
                iclue["s"]    = int(raw_iclue.get("s", 0))
                iclue["val"]  = str(raw_iclue.get("val", ""))
                iclue["dist"] = int(raw_iclue.get("dist", 0))
            "proximity_between":
                iclue["mid"] = int(raw_iclue.get("mid", 0))
                iclue["a"]   = int(raw_iclue.get("a", 0))
                iclue["b"]   = int(raw_iclue.get("b", 0))
            "color_exact":
                iclue["s"] = int(raw_iclue.get("s", 0))
                iclue["c"] = int(raw_iclue.get("c", 0))
            "color_neg":
                iclue["s"] = int(raw_iclue.get("s", 0))
                var iexcl: Array = []
                for v9 in raw_iclue.get("excluded", []):
                    iexcl.append(int(v9))
                iclue["excluded"] = iexcl
            "label_extreme_ordinal_color":
                iclue["s"] = int(raw_iclue.get("s", 0))
                var igrp: Array = []
                for v10 in raw_iclue.get("group", []):
                    igrp.append(int(v10))
                iclue["group"] = igrp
                iclue["want_lowest_rank"] = bool(raw_iclue.get("want_lowest_rank", true))
            "proximity_degree_exact":
                iclue["s"] = int(raw_iclue.get("s", 0))
                iclue["degree"] = int(raw_iclue.get("degree", 0))
            "proximity_degree_extreme":
                iclue["s"] = int(raw_iclue.get("s", 0))
                iclue["is_most"] = bool(raw_iclue.get("is_most", true))
            "proximity_degree_group_cmp_color":
                iclue["s"] = int(raw_iclue.get("s", 0))
                var itgt: Array = []
                for v11 in raw_iclue.get("targets", []):
                    itgt.append(int(v11))
                iclue["targets"] = itgt
                iclue["s_more"] = bool(raw_iclue.get("s_more", true))
            "proximity_dist_extreme":
                iclue["s"] = int(raw_iclue.get("s", 0))
                iclue["ref"] = int(raw_iclue.get("ref", 0))
                iclue["want_least"] = bool(raw_iclue.get("want_least", true))
            "proximity_dist_dual_cmp":
                iclue["s"] = int(raw_iclue.get("s", 0))
                iclue["ref_a"] = int(raw_iclue.get("ref_a", 0))
                iclue["ref_b"] = int(raw_iclue.get("ref_b", 0))
                iclue["farther_from_a"] = bool(raw_iclue.get("farther_from_a", true))
            "proximity_dist_offset":
                iclue["s"] = int(raw_iclue.get("s", 0))
                iclue["ref_a"] = int(raw_iclue.get("ref_a", 0))
                iclue["ref_b"] = int(raw_iclue.get("ref_b", 0))
                iclue["offset"] = int(raw_iclue.get("offset", 0))
        _final_identity_clues.append(iclue)
 
    return star_count > 0 and _generation_complete
 
 
# ==================================================
# VALIDATION HELPER
# ==================================================
func check_solution(candidate: Array) -> bool:
    if candidate.size() != star_count:
        return false
    for i in star_count:
        if int(candidate[i]) != pitch_rank_solution[i]:
            return false
    return true
