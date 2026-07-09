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
#   GENERATOR: Adjacency + extreme clues seed first (small set, propagate
#     best in FC), then color-comparison + adj-seq clues added one at a time,
#     checking uniqueness after each addition rather than after
#     every single addition. Color pool capped at MAX_COLOR_PAIRS_PER_DIR
#     per direction to keep pool size O(n) not O(n^2).
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
#     - position in the line-graph (adjacency, derived from line_pairs)
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
const COLOR_NAMES           := ["Blue", "White", "Yellow-Orange", "Red"]
const SEQ_WORD_EARLIER      := "earlier"
const SEQ_WORD_LATER        := "later"
const FRAME_BUDGET_MSEC     := 2       # max ms of work per frame during async gen
const MAX_COLOR_PAIRS_PER_DIR := 3     # color-comparison pool cap per direction
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
var adjacency: Array[Array] = []       # adjacency[i] = Array[int]
var star_colors: Array[int] = []       # star_colors[i] = StarColor int (visible, per-player)
var star_names: Array[String] = []     # star_names[i] = procedural name (per-constellation)
var pitch_rank_solution: Array[int] = [] # pitch_rank_solution[i] = melody step for star i

# ── Internal clue representation ─────────────────────────────────────────
# Clues are stored as plain Dictionaries rather than Callables so they
# can be serialized to the save cache. The solver reconstructs comparison
# predicates from the stored fields at solve-time.
# Schema:
#   comparison:  {"kind":"cmp",     "a":int, "b":int, "a_gt_b":bool, "text":String}
#   adjacent-seq:{"kind":"adj_seq", "a":int, "b":int, "text":String}  (a fires immediately after b)
#   extreme:     {"kind":"extreme", "s":int, "neighbors":[int,...], "want_lowest":bool, "text":String}
#   flavor:      {"kind":"flavor",  "text":String}
var _final_clues: Array[Dictionary] = []
var _generation_complete: bool = false

# ── Real-pitch + graph-distance data (known info, used for flavor clues only) ──
var star_pitch_index: Array[int] = []     # star_pitch_index[i] = pitch-table index for star i
var _pitch_freqs: Array[float] = []       # this constellation's Hz table, indexed by pitch index
var _distances: Array[Array] = []         # _distances[a][b] = shortest graph-hop count, -1 if unreachable
var _pitch_flavor_texts: Array[String] = []
var _distance_flavor_texts: Array[String] = []
var _between_flavor_texts: Array[String] = []
var _color_negation_texts: Array[Dictionary] = []   # [{"s":int, "text":String}, ...]
var _pitch_negation_texts: Array[Dictionary] = []   # [{"s":int, "text":String}, ...]

var _rng := RandomNumberGenerator.new()


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

    # Offset seed so color assignment never shares RNG stream with
    # get_note_assignment() or ConstellationStarNamer.
    _rng.seed = p_player_seed ^ (p_constellation_id * 0x9E3779B9) ^ 0x4C50_5A5A

    _build_adjacency(line_pairs)
    _compute_distances()
    _assign_colors_balanced()
    _set_pitch_ranks_from_sequence(correct_star_sequence)
    star_names = ConstellationStarNamer.generate_names(
        star_count, p_constellation_id, name_theme)

    star_pitch_index = []
    for v in p_star_pitch_index:
        star_pitch_index.append(int(v))
    _pitch_freqs = []
    for v in p_pitch_freqs:
        _pitch_freqs.append(float(v))


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
            for n in adjacency[cur]:
                var ni: int = int(n)
                if dist[ni] == -1:
                    dist[ni] = dist[cur] + 1
                    queue.append(ni)
        _distances.append(dist)


func _build_adjacency(line_pairs: Array) -> void:
    adjacency.clear()
    adjacency.resize(star_count)
    for i in star_count:
        adjacency[i] = []
    var i: int = 0
    while i < line_pairs.size() - 1:
        var a: int = int(line_pairs[i])
        var b: int = int(line_pairs[i + 1])
        if a >= 0 and a < star_count and b >= 0 and b < star_count:
            if not adjacency[a].has(b):
                adjacency[a].append(b)
            if not adjacency[b].has(a):
                adjacency[b].append(a)
        i += 2


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
            "cmp", "cmp_dist":
                expanded.append({"a": clue["a"], "b": clue["b"], "a_gt_b": clue["a_gt_b"]})
            "extreme":
                var s: int = clue["s"]
                var want_lowest: bool = clue["want_lowest"]
                for n in clue["neighbors"]:
                    if want_lowest:
                        expanded.append({"a": int(n), "b": s, "a_gt_b": true})
                    else:
                        expanded.append({"a": s, "b": int(n), "a_gt_b": true})
    return expanded


func _propagate(possible: Array, cmp_clues: Array[Dictionary], adj_clues: Array[Dictionary]) -> bool:
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

        # --- Immediate-adjacency arcs: a fires exactly one step after b. Needs
        # exact value lookups, not just bounds. ---
        for clue in adj_clues:
            var a2: int = clue["a"]
            var b2: int = clue["b"]
            for r in star_count:
                if possible[a2][r]:
                    var supported: bool = r > 0 and possible[b2][r - 1]
                    if not supported:
                        possible[a2][r] = false
                        changed = true
            for r in star_count:
                if possible[b2][r]:
                    var supported2: bool = r < star_count - 1 and possible[a2][r + 1]
                    if not supported2:
                        possible[b2][r] = false
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
        if clue["kind"] != "exact":
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
            "neg_exact":
                var s: int = clue["s"]
                var r: int = clue["r"]
                possible[s][r] = false
            "neg_adjacent":
                var s2: int = clue["s"]
                var r2: int = clue["r"]
                for n in adjacency[s2]:
                    possible[int(n)][r2] = false
    for i in star_count:
        var any_possible: bool = false
        for r in star_count:
            if possible[i][r]:
                any_possible = true
                break
        if not any_possible:
            return false
    return true


func _solve(clues: Array[Dictionary], cap: int = 2) -> Array:
    var expanded_cmp: Array[Dictionary] = _expand_clues_to_cmp(clues)
    var adj_clues: Array[Dictionary] = []
    for clue in clues:
        if clue["kind"] == "adj_seq":
            adj_clues.append(clue)

    var possible: Array = _init_possibility_grid()
    if not _apply_exact_clues(possible, clues):
        return []
    if not _apply_negative_clues(possible, clues):
        return []
    var consistent: bool = _propagate(possible, expanded_cmp, adj_clues)
    if not consistent:
        return []

    if _all_singleton(possible):
        return [_extract_singleton_solution(possible)]

    var solutions: Array = []
    var assignment: Array = []
    assignment.resize(star_count)
    for i in star_count:
        assignment[i] = -1

    var init_domains: Array = _possible_to_domains(possible)
    _backtrack_fc(assignment, init_domains, expanded_cmp, adj_clues, solutions, cap)
    return solutions


func _backtrack_fc(assignment: Array, domains: Array,
        cmp_clues: Array[Dictionary], adj_clues: Array[Dictionary],
        solutions: Array, cap: int) -> void:
    if solutions.size() >= cap:
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
        solutions.append(assignment.duplicate())
        return

    for val in domains[var_idx]:
        assignment[var_idx] = val
        var new_doms_result = _forward_check(var_idx, val, domains, cmp_clues, adj_clues)
        if new_doms_result != null:
            _backtrack_fc(assignment, new_doms_result, cmp_clues, adj_clues, solutions, cap)
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

    # Immediate-adjacency propagation: clue's "a" fires exactly one step after "b".
    for clue in adj_clues:
        var a: int = clue["a"]
        var b: int = clue["b"]
        if a == var_idx:
            var new_b: Array = []
            for v in nd[b]:
                if v == val - 1:
                    new_b.append(v)
            if new_b.is_empty():
                return null
            nd[b] = new_b
        elif b == var_idx:
            var new_a: Array = []
            for v in nd[a]:
                if v == val + 1:
                    new_a.append(v)
            if new_a.is_empty():
                return null
            nd[a] = new_a

    return nd


# ==================================================
# CLUE TEXT BUILDERS
# ==================================================

func _build_cmp_clue(a: int, b: int) -> Dictionary:
    var a_gt_b: bool = pitch_rank_solution[a] > pitch_rank_solution[b]
    var word: String = SEQ_WORD_LATER if a_gt_b else SEQ_WORD_EARLIER
    var text: String = "The %s fires %s than the %s." % [_ordinal(pitch_rank_solution[a] + 1), word, _ordinal(pitch_rank_solution[b] + 1)]
    return {"kind": "cmp", "a": a, "b": b, "a_gt_b": a_gt_b, "text": text}


func _build_adj_seq_clue(a: int, b: int) -> Dictionary:
    var text: String = "The %s fires immediately after the %s." % [_ordinal(pitch_rank_solution[a] + 1), _ordinal(pitch_rank_solution[b] + 1)]
    return {"kind": "adj_seq", "a": a, "b": b, "text": text}


func _build_extreme_clue(s: int) -> Dictionary:
    var neighbors: Array = adjacency[s]
    if neighbors.is_empty():
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
    return {"kind": "extreme", "s": s, "neighbors": nb_copy,
            "want_lowest": is_lowest, "text": text}


func _build_flavor_clue(s: int) -> Dictionary:
    var text: String = "%s shines %s." % [star_names[s], COLOR_NAMES[star_colors[s]]]
    return {"kind": "flavor", "text": text}


func _freq_for_star(s: int) -> float:
    if s < 0 or s >= star_pitch_index.size():
        return 0.0
    var pidx: int = star_pitch_index[s]
    if pidx < 0 or pidx >= _pitch_freqs.size():
        return 0.0
    return _pitch_freqs[pidx]


func _build_pitch_cmp_text(a: int, b: int) -> String:
    var fa: float = _freq_for_star(a)
    var fb: float = _freq_for_star(b)
    if is_equal_approx(fa, fb):
        return "%s plays the same note as %s." % [star_names[a], star_names[b]]
    var word: String = "higher" if fa > fb else "lower"
    return "%s plays a %s note than %s." % [star_names[a], word, star_names[b]]


func _join_names(names: Array) -> String:
    if names.size() == 1:
        return str(names[0])
    if names.size() == 2:
        return "%s and %s" % [names[0], names[1]]
    var result: String = ""
    for i in range(names.size() - 1):
        result += str(names[i])
        if i < names.size() - 2:
            result += ", "
    result += ", and %s" % names[names.size() - 1]
    return result


# ==================================================
# POOL BUILDERS
# ==================================================

func _build_adj_pool() -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    var i: int = 0
    while i < adjacency.size():
        for j in adjacency[i]:
            if int(j) > i:
                pool.append(_build_cmp_clue(i, int(j)))
        i += 1
    return pool


func _build_extreme_pool() -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    for s in star_count:
        var clue: Dictionary = _build_extreme_clue(s)
        if not clue.is_empty():
            pool.append(clue)
    return pool


func _build_color_pool() -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    var by_color: Array[Array] = [[], [], [], []]
    for s in star_count:
        by_color[star_colors[s]].append(s)
    for c1 in 4:
        for c2 in 4:
            if c1 == c2:
                continue
            var pairs: Array = []
            for a in by_color[c1]:
                for b in by_color[c2]:
                    pairs.append([a, b])
            # Shuffle then cap to keep pool O(n) not O(n^2).
            _shuffle_array(pairs)
            var count: int = 0
            for pair in pairs:
                if count >= MAX_COLOR_PAIRS_PER_DIR:
                    break
                pool.append(_build_cmp_clue(pair[0], pair[1]))
                count += 1
    return pool


func _build_adj_seq_pool() -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    var star_at_rank: Array = []
    star_at_rank.resize(star_count)
    for s in star_count:
        star_at_rank[pitch_rank_solution[s]] = s
    for r in range(star_count - 1):
        var b: int = star_at_rank[r]
        var a: int = star_at_rank[r + 1]
        pool.append(_build_adj_seq_clue(a, b))
    return pool


func _exact_desc_is_unique(subject: int, named_neighbor: int, color_c: int) -> bool:
    for t in star_count:
        if t == subject:
            continue
        if not adjacency[t].has(named_neighbor):
            continue
        var has_color_neighbor: bool = false
        for n in adjacency[t]:
            if int(n) != named_neighbor and star_colors[int(n)] == color_c:
                has_color_neighbor = true
                break
        if has_color_neighbor:
            return false
    return true


func _build_exact_pool() -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    for s in star_count:
        var neighbors: Array = adjacency[s]
        if neighbors.size() < 2:
            continue
        var found: bool = false
        for n1 in neighbors:
            if found:
                break
            for n2 in neighbors:
                if n1 == n2:
                    continue
                var color_c: int = star_colors[int(n2)]
                if not _exact_desc_is_unique(s, int(n1), color_c):
                    continue
                var text: String = "The %s is connected to %s and a %s star." % [
                    _ordinal(pitch_rank_solution[s] + 1), star_names[int(n1)], COLOR_NAMES[color_c].to_lower()]
                pool.append({"kind": "exact", "s": s, "r": pitch_rank_solution[s], "text": text})
                found = true
                break
    return pool


func _build_cmp_dist_pool() -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    var pairs: Array = []
    for a in star_count:
        for b in star_count:
            if a != b:
                pairs.append([a, b])
    _shuffle_array(pairs)
    var cap: int = maxi(2, int(star_count / 3.0))
    var count: int = 0
    for pair in pairs:
        if count >= cap:
            break
        var a: int = pair[0]
        var b: int = pair[1]
        var third_candidates: Array = []
        for c in star_count:
            if c != a and c != b and _distances[a][c] > 0:
                third_candidates.append(c)
        if third_candidates.is_empty():
            continue
        var c: int = third_candidates[_rng.randi_range(0, third_candidates.size() - 1)]
        var d: int = _distances[a][c]
        var base: Dictionary = _build_cmp_clue(a, b)
        var word: String = "star" if d == 1 else "stars"
        var ref_text: String = _describe_star_reference(a, c, d)
        var text: String = "%s and is %d %s away from %s." % [
            String(base["text"]).trim_suffix("."), d, word, ref_text]
        pool.append({"kind": "cmp_dist", "a": a, "b": b, "a_gt_b": base["a_gt_b"],
                     "c": c, "dist": d, "text": text})
        count += 1
    return pool


func _build_neg_adjacent_pool() -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    var star_at_rank: Array = []
    star_at_rank.resize(star_count)
    for s in star_count:
        star_at_rank[pitch_rank_solution[s]] = s
    for s in star_count:
        var neighbor_set: Dictionary = {}
        for n in adjacency[s]:
            neighbor_set[int(n)] = true
        var candidates: Array = []
        for r in star_count:
            var holder: int = star_at_rank[r]
            if holder == s:
                continue
            if neighbor_set.has(holder):
                continue
            candidates.append(r)
        if candidates.is_empty():
            continue
        var r: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
        var text: String = "%s is not connected to the %s." % [star_names[s], _ordinal(r + 1)]
        if _rng.randi() % 2 == 0:
            var use_pitch: bool = _rng.randi() % 2 == 0
            if use_pitch:
                text = "%s and plays %s." % [text.trim_suffix("."), _describe_pitch_fragment(s)]
            else:
                text = "%s and is %s." % [text.trim_suffix("."), _describe_color_fragment(s)]
        pool.append({"kind": "neg_adjacent", "s": s, "r": r, "text": text})
    return pool


func _build_neg_exact_pool() -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    for s in star_count:
        var true_r: int = pitch_rank_solution[s]
        var wrong_candidates: Array = []
        for r in star_count:
            if r != true_r:
                wrong_candidates.append(r)
        if wrong_candidates.is_empty():
            continue
        var r: int = wrong_candidates[_rng.randi_range(0, wrong_candidates.size() - 1)]
        var base_text: String = "%s is not the %s." % [star_names[s], _ordinal(r + 1)]
        var attached: Dictionary = _attach_neighbor_fragment(base_text, s, "is connected to")
        pool.append({"kind": "neg_exact", "s": s, "r": r, "has_mix": attached["c"] != -1,
                     "c": attached["c"], "text": attached["text"]})
    return pool


func _build_neg_color_pool() -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    for s in star_count:
        var true_color: int = star_colors[s]
        var others: Array = []
        for c in 4:
            if c != true_color:
                others.append(c)
        _shuffle_array(others)
        var exclude_count: int = 1 + (_rng.randi() % 2)
        var excluded: Array = []
        for i in mini(exclude_count, others.size()):
            excluded.append(others[i])
        var names: Array = []
        for c in excluded:
            names.append(COLOR_NAMES[c].to_lower())
        var text: String
        if names.size() == 1:
            text = "%s is not %s." % [star_names[s], names[0]]
        else:
            text = "%s is neither %s nor %s." % [star_names[s], names[0], names[1]]
        pool.append({"s": s, "text": text})
    return pool


func _describe_color_fragment(star_idx: int) -> String:
    return "a %s star" % COLOR_NAMES[star_colors[star_idx]].to_lower()


func _describe_pitch_fragment(star_idx: int) -> String:
    var pitch_idx: int = star_pitch_index[star_idx] if star_idx < star_pitch_index.size() else 0
    var freq: float = _pitch_freqs[pitch_idx] if pitch_idx < _pitch_freqs.size() else 0.0
    return "a %s note" % note_name_for_freq(freq)


func _attach_neighbor_fragment(base_text: String, subject: int, verb: String) -> Dictionary:
    var neighbors: Array = adjacency[subject]
    if neighbors.is_empty():
        return {"text": base_text, "c": -1}
    var n: int = int(neighbors[_rng.randi_range(0, neighbors.size() - 1)])
    var use_pitch: bool = _rng.randi() % 2 == 0
    var fragment: String = _describe_pitch_fragment(n) if use_pitch else _describe_color_fragment(n)
    var text: String = "%s and %s %s." % [base_text.trim_suffix("."), verb, fragment]
    return {"text": text, "c": n}


func _build_neg_pitch_pool() -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    for s in star_count:
        var true_pitch: int = star_pitch_index[s] if s < star_pitch_index.size() else 0
        var others: Array = []
        for p in _pitch_freqs.size():
            if p != true_pitch:
                others.append(p)
        if others.is_empty():
            continue
        _shuffle_array(others)
        var exclude_count: int = 1 + (_rng.randi() % mini(2, others.size()))
        var excluded: Array = []
        for i in mini(exclude_count, others.size()):
            excluded.append(others[i])
        var names: Array = []
        for p in excluded:
            names.append(note_name_for_freq(_pitch_freqs[p]))
        var text: String
        if names.size() == 1:
            text = "%s does not play %s." % [star_names[s], names[0]]
        else:
            text = "%s plays neither %s nor %s." % [star_names[s], names[0], names[1]]
        pool.append({"s": s, "text": text})
    return pool


func _build_pitch_flavor_pool() -> Array[String]:
    var texts: Array[String] = []

    var by_pitch: Dictionary = {}
    for s in star_count:
        var pidx: int = star_pitch_index[s] if s < star_pitch_index.size() else -1
        if pidx < 0:
            continue
        if not by_pitch.has(pidx):
            by_pitch[pidx] = []
        by_pitch[pidx].append(s)
    var pitch_keys: Array = by_pitch.keys()
    _shuffle_array(pitch_keys)
    for pidx in pitch_keys:
        var group: Array = by_pitch[pidx]
        if group.size() < 2:
            continue
        var names: Array = []
        for s in group:
            names.append(star_names[s])
        texts.append("%s all play the same note." % _join_names(names))

    var pairs: Array = []
    for s1 in star_count:
        for s2 in star_count:
            if s1 < s2 and not is_equal_approx(_freq_for_star(s1), _freq_for_star(s2)):
                pairs.append([s1, s2])
    _shuffle_array(pairs)
    var cap: int = maxi(2, int(star_count / 4.0))
    var count: int = 0
    for pair in pairs:
        if count >= cap:
            break
        texts.append(_build_pitch_cmp_text(pair[0], pair[1]))
        count += 1
    return texts


func _describe_star_reference(from_star: int, target_star: int, dist: int) -> String:
    if _rng.randf() < 0.4:
        var color_idx: int = star_colors[target_star]
        var matches: Array = []
        for s in star_count:
            if s != from_star and star_colors[s] == color_idx and _distances[from_star][s] == dist:
                matches.append(s)
        if matches.size() == 1:
            return "a %s star" % COLOR_NAMES[color_idx].to_lower()
    return star_names[target_star]


func _build_distance_flavor_pool() -> Array[String]:
    var texts: Array[String] = []
    var pairs: Array = []
    for a in star_count:
        for b in star_count:
            if a < b and _distances[a][b] > 0:
                pairs.append([a, b])
    _shuffle_array(pairs)
    var cap: int = maxi(2, int(star_count / 4.0))
    var count: int = 0
    for pair in pairs:
        if count >= cap:
            break
        var a: int = pair[0]
        var b: int = pair[1]
        var d: int = _distances[a][b]
        var word: String = "star" if d == 1 else "stars"
        var target_text: String = _describe_star_reference(a, b, d)
        texts.append("%s is %d %s away from %s." % [star_names[a], d, word, target_text])
        count += 1
    return texts


func _build_between_flavor_pool() -> Array[String]:
    var texts: Array[String] = []
    var candidates: Array = []
    for mid in star_count:
        for a in star_count:
            for b in star_count:
                if a == mid or b == mid or a >= b:
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
                    candidates.append([mid, a, b])
    _shuffle_array(candidates)
    var cap: int = maxi(1, int(star_count / 6.0))
    var count: int = 0
    for c in candidates:
        if count >= cap:
            break
        texts.append("%s lies between %s and %s." % [star_names[c[0]], star_names[c[1]], star_names[c[2]]])
        count += 1
    return texts


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


func get_clue_texts(include_flavor: bool = true) -> Array[String]:
    var texts: Array[String] = []
    if include_flavor:
        for s in star_count:
            texts.append(_build_flavor_clue(s)["text"])
        for t in _pitch_flavor_texts:
            texts.append(t)
        for t in _distance_flavor_texts:
            texts.append(t)
        for t in _between_flavor_texts:
            texts.append(t)
    for clue in _final_clues:
        if clue["kind"] != "flavor":
            texts.append(clue["text"])
    return texts


func _score_clue_difficulty(clue: Dictionary, solution: Array[int]) -> float:
    match clue.get("kind", ""):
        "exact":
            return 10.0
        "adj_seq":
            return 8.0
        "extreme":
            return 7.0
        "neg_exact":
            return 6.0
        "neg_adjacent":
            return 5.0
        "cmp_dist":
            var star_a: int = clue.get("a", 0)
            var star_b: int = clue.get("b", 0)
            var gap: int = abs(solution[star_a] - solution[star_b])
            return 2.5 + (float(gap) * 0.5)
        "cmp":
            var star_a2: int = clue.get("a", 0)
            var star_b2: int = clue.get("b", 0)
            var gap2: int = abs(solution[star_a2] - solution[star_b2])
            return 2.0 + (float(gap2) * 0.5)
    return 1.0


func generate_clues_async(_manual_clue_count: int = -1) -> void:
    _generation_complete = false
    _final_clues.clear()

    var t_total_start: float = Time.get_ticks_msec()

    var adj_pool: Array[Dictionary] = _build_adj_pool()
    var extreme_pool: Array[Dictionary] = _build_extreme_pool()
    var color_pool: Array[Dictionary] = _build_color_pool()
    var adjseq_pool: Array[Dictionary] = _build_adj_seq_pool()
    var exact_pool: Array[Dictionary] = _build_exact_pool()
    var cmp_dist_pool: Array[Dictionary] = _build_cmp_dist_pool()
    var neg_exact_pool: Array[Dictionary] = _build_neg_exact_pool()
    var neg_adjacent_pool: Array[Dictionary] = _build_neg_adjacent_pool()

    _shuffle_dict_array(adj_pool)
    _shuffle_dict_array(extreme_pool)
    _shuffle_dict_array(color_pool)
    _shuffle_dict_array(adjseq_pool)
    _shuffle_dict_array(exact_pool)
    _shuffle_dict_array(cmp_dist_pool)
    _shuffle_dict_array(neg_exact_pool)
    _shuffle_dict_array(neg_adjacent_pool)

    _color_negation_texts = _build_neg_color_pool()
    _pitch_negation_texts = _build_neg_pitch_pool()

    print("[PUZZLE_TIMING %d] pools: adj=%d extreme=%d color=%d adjseq=%d exact=%d cmp_dist=%d neg_exact=%d neg_adj=%d" % [
        constellation_id, adj_pool.size(), extreme_pool.size(),
        color_pool.size(), adjseq_pool.size(), exact_pool.size(), cmp_dist_pool.size(),
        neg_exact_pool.size(), neg_adjacent_pool.size()])

    # Phase 1: seed with adjacency + extreme clues — small set, propagate best.
    var chosen: Array[Dictionary] = []
    for c in adj_pool:
        chosen.append(c)
    for c in extreme_pool:
        chosen.append(c)

    # Phase 2 candidates: color + adj-seq clues merged into one pool, sorted
    # highest-information-first. Single-clue injection stops the instant
    # uniqueness is reached, so low-value clues are often never added at all —
    # not just trimmed later.
    var candidate_pool: Array[Dictionary] = []
    candidate_pool.append_array(exact_pool)
    candidate_pool.append_array(cmp_dist_pool)
    candidate_pool.append_array(neg_exact_pool)
    candidate_pool.append_array(neg_adjacent_pool)
    candidate_pool.append_array(color_pool)
    candidate_pool.append_array(adjseq_pool)
    candidate_pool.sort_custom(func(clue_a, clue_b):
        return _score_clue_difficulty(clue_a, pitch_rank_solution) > _score_clue_difficulty(clue_b, pitch_rank_solution))

    var pool_idx: int = 0
    var frame_timer: float = Time.get_ticks_msec()

    var solve_call_count: int = 0
    var solve_total_msec: float = 0.0
    var solve_max_msec: float = 0.0

    var safety_cap: int = candidate_pool.size() + 10
    var safety_counter: int = 0
    var unique: bool = false

    var t_phase2_start: float = Time.get_ticks_msec()

    while not unique:
        safety_counter += 1
        if safety_counter > safety_cap:
            push_warning("ConstellationLogicPuzzle [%d]: safety cap hit during generation." % constellation_id)
            break

        var t_solve: float = Time.get_ticks_msec()
        var solutions: Array = _solve(chosen, 2)
        var solve_dt: float = Time.get_ticks_msec() - t_solve
        solve_call_count += 1
        solve_total_msec += solve_dt
        if solve_dt > solve_max_msec:
            solve_max_msec = solve_dt

        if solutions.size() == 1:
            unique = true
            break

        if pool_idx < candidate_pool.size():
            chosen.append(candidate_pool[pool_idx])
            pool_idx += 1
        else:
            push_warning("ConstellationLogicPuzzle [%d]: pool exhausted before unique solution." % constellation_id)
            break

        if Time.get_ticks_msec() - frame_timer >= FRAME_BUDGET_MSEC:
            await Engine.get_main_loop().process_frame
            frame_timer = Time.get_ticks_msec()

    var phase2_dt: float = Time.get_ticks_msec() - t_phase2_start
    print("[PUZZLE_TIMING %d] PHASE2 (gen): %.0fms, %d solve calls, total_solve=%.0fms, max_single_solve=%.0fms, clues=%d" % [
        constellation_id, phase2_dt, solve_call_count, solve_total_msec, solve_max_msec, chosen.size()])

    # Phase 3: tiered trim. Sort ascending (weakest clues first) and trim
    # forward from index 0, so simple/redundant clues get tested for removal
    # before high-value ones — biasing the final set toward the interesting clues.
    var t_phase3_start: float = Time.get_ticks_msec()
    var trim_solve_count: int = 0
    var trim_solve_max: float = 0.0

    chosen.sort_custom(func(clue_a, clue_b):
        return _score_clue_difficulty(clue_a, pitch_rank_solution) < _score_clue_difficulty(clue_b, pitch_rank_solution))

    var trim_idx: int = 0
    while trim_idx < chosen.size():
        if chosen.size() <= 1:
            break

        var trial_clue: Dictionary = chosen[trim_idx]
        chosen.remove_at(trim_idx)

        var t_trim_solve: float = Time.get_ticks_msec()
        var trial_solutions: Array = _solve(chosen, 2)
        var trim_dt: float = Time.get_ticks_msec() - t_trim_solve
        trim_solve_count += 1
        if trim_dt > trim_solve_max:
            trim_solve_max = trim_dt

        if trial_solutions.size() == 1:
            pass   # still unique without it — leave it out, don't advance trim_idx
        else:
            chosen.insert(trim_idx, trial_clue)
            trim_idx += 1

        if Time.get_ticks_msec() - frame_timer >= FRAME_BUDGET_MSEC:
            await Engine.get_main_loop().process_frame
            frame_timer = Time.get_ticks_msec()

    var phase3_dt: float = Time.get_ticks_msec() - t_phase3_start
    print("[PUZZLE_TIMING %d] PHASE3 (trim): %.0fms wall, %d solve calls, max_single_solve=%.0fms, final_clues=%d" % [
        constellation_id, phase3_dt, trim_solve_count, trim_solve_max, chosen.size()])

    _final_clues = chosen

    # Flavor pools built once, after real clues are locked in, then cached
    # as plain text so they don't re-randomize on every from_cache_dict load.
    _pitch_flavor_texts = _build_pitch_flavor_pool()
    _distance_flavor_texts = _build_distance_flavor_pool()
    _between_flavor_texts = _build_between_flavor_pool()

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
        "version":          3,
        "constellation_id": constellation_id,
        "player_seed_used": player_seed_used,
        "star_count":       star_count,
        "star_colors":      star_colors.duplicate(),
        "star_names":       star_names.duplicate(),
        "pitch_rank_solution": pitch_rank_solution.duplicate(),
        "final_clues":      _final_clues.duplicate(true),
        "pitch_flavor_texts":    _pitch_flavor_texts.duplicate(),
        "distance_flavor_texts": _distance_flavor_texts.duplicate(),
        "between_flavor_texts":  _between_flavor_texts.duplicate(),
        "color_negation_texts": _color_negation_texts.duplicate(true),
        "pitch_negation_texts": _pitch_negation_texts.duplicate(true),
        "generation_complete": _generation_complete,
    }


func from_cache_dict(data: Dictionary) -> bool:
    if data.get("version", 0) != 3:
        push_warning("ConstellationLogicPuzzle: cache version mismatch, ignoring cached data.")
        return false
    constellation_id     = int(data.get("constellation_id", -1))
    player_seed_used     = int(data.get("player_seed_used", 0))
    star_count           = int(data.get("star_count", 0))
    _generation_complete = bool(data.get("generation_complete", false))

    star_colors = []
    for v in data.get("star_colors", []):
        star_colors.append(int(v))

    star_names = []
    for v in data.get("star_names", []):
        star_names.append(str(v))

    pitch_rank_solution = []
    for v in data.get("pitch_rank_solution", []):
        pitch_rank_solution.append(int(v))

    _pitch_flavor_texts = []
    for v in data.get("pitch_flavor_texts", []):
        _pitch_flavor_texts.append(str(v))

    _distance_flavor_texts = []
    for v in data.get("distance_flavor_texts", []):
        _distance_flavor_texts.append(str(v))

    _between_flavor_texts = []
    for v in data.get("between_flavor_texts", []):
        _between_flavor_texts.append(str(v))

    _color_negation_texts = []
    for v in data.get("color_negation_texts", []):
        var entry: Dictionary = v as Dictionary
        _color_negation_texts.append({"s": int(entry.get("s", 0)), "text": str(entry.get("text", ""))})
    _pitch_negation_texts = []
    for v2 in data.get("pitch_negation_texts", []):
        var entry2: Dictionary = v2 as Dictionary
        _pitch_negation_texts.append({"s": int(entry2.get("s", 0)), "text": str(entry2.get("text", ""))})

    _final_clues = []
    for raw_clue in data.get("final_clues", []):
        var clue: Dictionary = {}
        var kind: String = str(raw_clue.get("kind", ""))
        clue["kind"] = kind
        clue["text"] = str(raw_clue.get("text", ""))
        match kind:
            "cmp":
                clue["a"]      = int(raw_clue.get("a", 0))
                clue["b"]      = int(raw_clue.get("b", 0))
                clue["a_gt_b"] = bool(raw_clue.get("a_gt_b", false))
            "adj_seq":
                clue["a"] = int(raw_clue.get("a", 0))
                clue["b"] = int(raw_clue.get("b", 0))
            "extreme":
                clue["s"]           = int(raw_clue.get("s", 0))
                clue["want_lowest"] = bool(raw_clue.get("want_lowest", true))
                var nb: Array = []
                for v in raw_clue.get("neighbors", []):
                    nb.append(int(v))
                clue["neighbors"] = nb
            "exact":
                clue["s"] = int(raw_clue.get("s", 0))
                clue["r"] = int(raw_clue.get("r", 0))
            "cmp_dist":
                clue["a"]      = int(raw_clue.get("a", 0))
                clue["b"]      = int(raw_clue.get("b", 0))
                clue["a_gt_b"] = bool(raw_clue.get("a_gt_b", false))
                clue["c"]      = int(raw_clue.get("c", 0))
                clue["dist"]   = int(raw_clue.get("dist", 0))
            "neg_exact":
                clue["s"]       = int(raw_clue.get("s", 0))
                clue["r"]       = int(raw_clue.get("r", 0))
                clue["has_mix"] = bool(raw_clue.get("has_mix", false))
                clue["c"]       = int(raw_clue.get("c", -1))
            "neg_adjacent":
                clue["s"] = int(raw_clue.get("s", 0))
                clue["r"] = int(raw_clue.get("r", 0))
        _final_clues.append(clue)

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
