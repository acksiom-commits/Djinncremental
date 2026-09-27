extends RefCounted
## NEXT-STEP FINDER (Sequence axis) -- hint tiers 3 and 4 of the ZebraTutor
## ladder.
##
## Question answered: "given what the PLAYER'S board already says, does this
## one clue let them rule something out RIGHT NOW?" That is the actionability
## the tier-2 predicate (clue_indices_with_something_to_give) explicitly does
## not promise -- a clue can have unrecorded content yet need another fact
## first. Here a clue only yields a step if propagating it, on top of the
## player's own candidate positions, removes a candidate the board still has.
##
## Pure logic, deliberately: it takes a solver instance (only for
## _propagate_only, i.e. constraint propagation and NEVER the backtracking
## fallback -- a step justified by "the solver tried it" is not something a
## player can follow), the player's star-by-rank candidate grid, and the
## clue's Sequence facts. It reads no overlay state and no ground truth, so
## it cannot leak anything the board plus the clue do not already entail.
## The overlay-facing wrapper lives in constellation_puzzle_deduction.gd.
##
## Cells, not stars: the result is a set of (star, rank) cells, as in the
## solver's own grid. Turning a cell into a sentence happens at the display
## edge only. See matrix_up_lint_ENFORCED.
##
## SEQUENCE ONLY for now. Name needs the Sequence solution to resolve and
## Colour/Pitch have no explainer at all; those are later phases.


## `solver`: any ConstellationLogicPuzzle whose star_count is set.
## `player_grid`: star_count x star_count bools, true = the player's board
## still allows that star at that rank (all true = the player knows nothing).
## `facts`: the clue's Sequence-CSP facts (disclosures minus the value kinds).
##
## Returns {"consistent": bool, "eliminated": [[star, rank], ...],
## "resolved": [[star, rank], ...]}. `eliminated` are cells the board still
## allowed that the clue (with the board) rules out, beyond what the board
## already forces by itself; `resolved` are stars that thereby drop to exactly
## one rank, as [star, that_rank]. Inconsistent (a contradiction between the
## board and the clue) returns no steps: a contradiction is not a hint.
static func step_for_facts(solver, player_grid: Array, facts: Array) -> Dictionary:
    var none: Dictionary = {"consistent": false, "eliminated": [], "resolved": []}
    var typed: Array[Dictionary] = []
    for f in facts:
        if f is Dictionary:
            typed.append(f)
    if typed.is_empty():
        return none
    # A typed local, not a `[]` literal: an untyped literal passed to a typed
    # Array[Dictionary] parameter through a dynamic ref silently aborts the
    # whole script.
    var no_facts: Array[Dictionary] = []
    var base: Dictionary = solver._propagate_only(no_facts, player_grid)
    if not bool(base["consistent"]):
        return none
    var with_clue: Dictionary = solver._propagate_only(typed, player_grid)
    if not bool(with_clue["consistent"]):
        return none
    var p0: Array = base["possible"]
    var p1: Array = with_clue["possible"]
    var eliminated: Array = []
    var resolved: Array = []
    for s in p0.size():
        var left0: int = 0
        var left1: int = 0
        var last_rank: int = -1
        for r in (p0[s] as Array).size():
            if bool(p0[s][r]):
                left0 += 1
                if not bool(p1[s][r]):
                    eliminated.append([s, r])
            if bool(p1[s][r]):
                left1 += 1
                last_rank = r
        if left1 == 1 and left0 > 1:
            resolved.append([s, last_rank])
    return {"consistent": true, "eliminated": eliminated, "resolved": resolved}


## NAME AXIS. The grid is name x star: grid[name][star] is true while the
## player's board still allows that name on that map star. `constraints` are
## per-name restrictions already resolved against what the PLAYER knows (the
## caller's job -- see ConstellationPuzzleDeduction._name_constraints_for_clue):
##   {"row": name, "allowed": [stars]}    the name is one of these stars
##   {"row": name, "excluded": [stars]}   the name is none of these stars
##   {"row": name, "other": name2, "same": bool, "group_of": [group per star]}
##                                        the two names sit on stars of the SAME
##                                        (or DIFFERENT) group; group_of[star] is
##                                        that star's group as the PLAYER knows
##                                        it, -1 = not known (wildcard)
## Names and stars are both alldiff, so the same elimination that closes the
## Sequence grid closes this one (solver._alldiff_eliminate).
##
## Same contract as step_for_facts: eliminations are those the constraints
## cause BEYOND what the board already forces by itself; `resolved` are names
## that thereby drop to exactly one star, as [name, that_star]; a contradiction
## returns no step.
static func step_for_sets(solver, player_grid: Array, constraints: Array) -> Dictionary:
    var none: Dictionary = {"consistent": false, "eliminated": [], "resolved": []}
    if constraints.is_empty():
        return none
    var base: Array = _copy_grid(player_grid)
    if not solver._alldiff_eliminate(base):
        return none
    var with_clue: Array = _copy_grid(base)
    var pairs: Array = []
    for c in constraints:
        var row: int = int(c["row"])
        if row < 0 or row >= with_clue.size():
            continue
        if c.has("other"):
            pairs.append(c)
            continue
        if c.has("allowed"):
            var keep: Dictionary = {}
            for s in c["allowed"]:
                keep[int(s)] = true
            for col in (with_clue[row] as Array).size():
                if not keep.has(col):
                    with_clue[row][col] = false
        else:
            for s2 in c.get("excluded", []):
                if int(s2) >= 0 and int(s2) < (with_clue[row] as Array).size():
                    with_clue[row][int(s2)] = false
    # Pair constraints and the name x star elimination feed each other, so run
    # both to a joint fixpoint.
    var moving: bool = true
    while moving:
        if not solver._alldiff_eliminate(with_clue):
            return none
        moving = false
        for pc in pairs:
            if _apply_pair(with_clue, int(pc["row"]), int(pc["other"]), bool(pc["same"]), pc["group_of"]):
                moving = true
    var eliminated: Array = []
    var resolved: Array = []
    for r in base.size():
        var left0: int = 0
        var left1: int = 0
        var last: int = -1
        for col2 in (base[r] as Array).size():
            if bool(base[r][col2]):
                left0 += 1
                if not bool(with_clue[r][col2]):
                    eliminated.append([r, col2])
            if bool(with_clue[r][col2]):
                left1 += 1
                last = col2
        if left1 == 1 and left0 > 1:
            resolved.append([r, last])
    return {"consistent": true, "eliminated": eliminated, "resolved": resolved}


static func _copy_grid(grid: Array) -> Array:
    var out: Array = []
    for row in grid:
        out.append((row as Array).duplicate())
    return out


## One pass of a pair constraint over the name x star grid: removes from `row`
## every star that has no admissible partner star left for `other`. A star whose
## group is unknown (-1) is never removed (it might match anything), and the two
## names are on different stars, so a star is never its own partner. Sound for
## the same reason the rest of this is: it only removes what cannot hold.
## Returns whether anything changed.
static func _apply_pair(grid: Array, row: int, other: int, same: bool, group_of: Array) -> bool:
    var changed: bool = false
    var n: int = (grid[row] as Array).size()
    for s in n:
        if not bool(grid[row][s]):
            continue
        var g: int = int(group_of[s])
        if g < 0:
            continue
        var any_partner: bool = false
        var all_same_group: bool = true
        for t in n:
            if t == s or not bool(grid[other][t]):
                continue
            any_partner = true
            var gt: int = int(group_of[t])
            if gt < 0 or gt != g:
                all_same_group = false
        var doomed: bool
        if same:
            # Needs a partner in the same group; a wildcard partner counts.
            var has_match: bool = false
            for t2 in n:
                if t2 == s or not bool(grid[other][t2]):
                    continue
                var g2: int = int(group_of[t2])
                if g2 < 0 or g2 == g:
                    has_match = true
                    break
            doomed = not has_match
        else:
            # Different group: dead only when EVERY remaining partner is
            # known to share this star's group.
            doomed = any_partner and all_same_group
        if doomed:
            grid[row][s] = false
            changed = true
    return changed
