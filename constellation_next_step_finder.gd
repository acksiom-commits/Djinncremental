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
