extends "res://dev_tests/test_base.gd"
# grain_tetrahedron.gd (2026-10-01) -- the Grain-branch counterpart of
# uonite_icosahedron.gd: a 4-faced host tetrahedron, one face per Mote
# (grain_assemble costs GRAIN_MOTES_PER_UNIT=4 mote_grains, game_context.gd),
# each revealed face stamped with a real tier-4 (Mote) lattice copy via the
# exact same technique uonite_icosahedron.gd already uses.
#
# What must hold:
#  - The 4 host vertices form an actual REGULAR tetrahedron: equal distance
#    from the origin (the `radius` export), and equal pairwise edge length.
#  - current_motes clamps to [0, 4], not [0, 20] -- a different cap than
#    the icosahedron's, matching this shape's own face count.
#  - The outer wireframe surface always exists; the per-Mote detail surface
#    only appears once at least one face is revealed.
#  - Revealing more faces never regresses geometry that was already correct
#    (a smoke check across every current_motes value from 0 to 4).

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame

	var inst: MeshInstance3D = load("res://grain_tetrahedron.gd").new()
	root.add_child(inst)
	await process_frame

	print("\n=== host geometry: a real regular tetrahedron ===")
	ok(inst.verts.size() == 4, "exactly 4 outer vertices (got %d)" % inst.verts.size())

	var dists: Array = []
	for v in inst.verts:
		dists.append(v.length())
	var all_dists_equal := true
	for d in dists:
		if not is_equal_approx(d, inst.radius):
			all_dists_equal = false
	ok(all_dists_equal, "every vertex sits at distance `radius` from the origin (got %s, radius=%s)" % [dists, inst.radius])

	var edge_lens: Array = []
	for i in range(4):
		for j in range(i + 1, 4):
			edge_lens.append((inst.verts[i] - inst.verts[j]).length())
	var all_edges_equal := true
	for e in edge_lens:
		if not is_equal_approx(e, edge_lens[0]):
			all_edges_equal = false
	ok(edge_lens.size() == 6, "6 pairwise edges checked (got %d)" % edge_lens.size())
	ok(all_edges_equal, "all 6 edges are the same length -- a REGULAR tetrahedron, not a skewed one (got %s)" % edge_lens)

	print("\n=== current_motes clamps to [0, 4], the tetrahedron's own face count ===")
	inst.current_motes = 20
	ok(inst.current_motes == 4, "an out-of-range value clamps DOWN to 4, not the icosahedron's 20 (got %d)" % inst.current_motes)
	inst.current_motes = -3
	ok(inst.current_motes == 0, "a negative value clamps up to 0 (got %d)" % inst.current_motes)

	print("\n=== mesh surfaces across the full reveal range ===")
	for n in range(0, 5):
		inst.current_motes = n
		var surfaces: int = inst.mesh.get_surface_count()
		if n == 0:
			ok(surfaces == 1, "0 revealed: only the outer wireframe surface exists (got %d surfaces)" % surfaces)
		else:
			ok(surfaces == 2, "%d revealed: outer wireframe + per-Mote detail surface both exist (got %d surfaces)" % [n, surfaces])
			var detail_arrays = inst.mesh.surface_get_arrays(1)
			var vcount: int = detail_arrays[Mesh.ARRAY_VERTEX].size()
			ok(vcount > 0, "%d revealed: the detail surface actually has vertices (got %d)" % [n, vcount])

	inst.queue_free()

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
