class_name ArchaiLatticeGeometry
extends RefCounted
# ============= ARCHAI LATTICE GEOMETRY (shared) =============
# Pure Sierpinski corner+centroid lattice math -- extracted from
# archai_lattice.gd so a second consumer (uonite_icosahedron.gd's always-on
# Uonite display) can build the exact same Mote/Iota/Particle/Tetrad
# structure without a second copy of this recursion drifting out of sync.
# archai_lattice.gd itself still owns the tier-1..4 structure it builds --
# these are the same functions, just callable without a live node instance.
#
# Only the two kind-tags this recursion ever emits are defined here
# (MONAD_TBD for an unassigned corner/weld Monad, KIND_SPARK for a tier's
# own centroid). S/L/G typing of the MONAD_TBD slots is a presentation
# choice, left to each caller -- see archai_lattice.gd's _rebuild() for the
# reference implementation (random per unique position, RNG-seeded).

const MONAD_TBD := -1
const KIND_SPARK := 0


## Regular tetrahedron, edge `e`, first corner at the origin. Every component
## is linear in `e`: halving the edge halves the corner vectors, which the
## recursion below relies on.
static func tetra_corners(e: float) -> Array:
    return [
        Vector3(0.0, 0.0, 0.0),
        Vector3(e, 0.0, 0.0),
        Vector3(e * 0.5, 0.0, e * sqrt(3.0) * 0.5),
        Vector3(e * 0.5, e * sqrt(2.0 / 3.0), e * sqrt(3.0) / 6.0),
    ]


static func build_tetrad() -> Dictionary:
    var corners := tetra_corners(1.0)
    var pos: Array = []
    var kind: Array = []
    for c in corners:
        pos.append(c)
        kind.append(MONAD_TBD)
    pos.append((corners[0] + corners[1] + corners[2] + corners[3]) / 4.0)
    kind.append(KIND_SPARK)

    var edges: Array = []
    for i in range(4):
        for j in range(i + 1, 4):
            edges.append(Vector2i(i, j))
    for i in range(4):
        edges.append(Vector2i(4, i))

    return {"pos": pos, "kind": kind, "edges": edges, "corners": [0, 1, 2, 3]}


## One assembly step: 4 sub-units at the corners of a double-edge tetrahedron,
## welded at the 6 edge midpoints, plus a Spark at the centre joined to those
## 6. Welding is done by CORNER IDENTITY, never by comparing float positions
## -- position welding drifts at deeper tiers and silently splits shared
## Monads.
static func build_tier(t: int) -> Dictionary:
    if t <= 1:
        return build_tetrad()

    var sub := build_tier(t - 1)
    var sub_pos: Array = sub["pos"]
    var sub_kind: Array = sub["kind"]
    var sub_corners: Array = sub["corners"]

    var big_edge: float = pow(2.0, float(t - 1))
    var corners := tetra_corners(big_edge)

    var pos: Array = []
    var kind: Array = []
    var edges: Array = []

    # The 4 outer tips.
    var corner_idx: Array = []
    for i in range(4):
        corner_idx.append(pos.size())
        pos.append(corners[i])
        kind.append(MONAD_TBD)

    # The 6 shared Monads, at the big tetrahedron's edge midpoints. These are
    # also exactly the 6 vertices of the octahedral gap.
    var mid_idx := {}
    for i in range(4):
        for j in range(i + 1, 4):
            mid_idx[Vector2i(i, j)] = pos.size()
            pos.append((corners[i] + corners[j]) * 0.5)
            kind.append(MONAD_TBD)

    for ci in range(4):
        var offset: Vector3 = corners[ci] * 0.5
        var idx_remap := {}
        for j in range(4):
            var sc: int = sub_corners[j]
            if j == ci:
                idx_remap[sc] = corner_idx[ci]
            else:
                idx_remap[sc] = mid_idx[Vector2i(mini(ci, j), maxi(ci, j))]
        for vi in sub_pos.size():
            if idx_remap.has(vi):
                continue
            idx_remap[vi] = pos.size()
            pos.append((sub_pos[vi] as Vector3) + offset)
            kind.append(sub_kind[vi])
        for e in sub["edges"]:
            edges.append(Vector2i(idx_remap[e.x], idx_remap[e.y]))

    var spark_i := pos.size()
    pos.append((corners[0] + corners[1] + corners[2] + corners[3]) / 4.0)
    kind.append(KIND_SPARK)
    for i in range(4):
        for j in range(i + 1, 4):
            edges.append(Vector2i(spark_i, mid_idx[Vector2i(i, j)]))

    return {"pos": pos, "kind": kind, "edges": edges, "corners": corner_idx}
