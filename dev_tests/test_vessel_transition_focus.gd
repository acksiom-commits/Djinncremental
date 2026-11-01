extends "res://dev_tests/test_base.gd"
# The intro's transition compresses toward the chosen Vessel, not the middle.
#
# What must hold:
#  - Each vessel's focus lands inside that vessel's own slot on screen.
#  - The overlay hands that focus to the shader, and with no focus given it
#    stays in the middle, which is what the in-game Oscillation relies on.
#
# Headless never runs a shader, so what the focus LOOKS like isn't covered here.

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame
	# Never added to the tree: its _ready leaves for RootUI when a save exists.
	var intro = load("res://intro_screen.gd").new()
	intro.size = Vector2(1280, 720)
	intro._populate_shapes()
	intro._update_shape_layout()

	print("=== each vessel's focus sits in its own slot ===")
	var keys: Array = intro.VESSEL_ORDER
	for i in keys.size():
		var uv: Vector2 = intro._vessel_focus_uv(keys[i])
		var left: float = float(i) / float(keys.size())
		ok(uv.x > left and uv.x < left + 1.0 / float(keys.size()) and uv.y > intro.TEXT_TOP_FRACTION and uv.y < 1.0,
			"%s focuses at %s" % [keys[i], uv])
	ok(intro._vessel_focus_uv("no such vessel") == Vector2(0.5, 0.5), "an unknown vessel falls back to the middle")

	print("\n=== the overlay passes the focus to the shader ===")
	var aimed = load("res://expansion_overlay.gd").new()
	aimed.setup(Vector2(0.2, 0.6))
	ok(aimed._shader_mat.get_shader_parameter("focus") == Vector2(0.2, 0.6), "a given focus reaches the shader")
	var plain = load("res://expansion_overlay.gd").new()
	plain.setup()
	ok(plain._shader_mat.get_shader_parameter("focus") == Vector2(0.5, 0.5), "no focus means the middle")
	aimed.free()
	plain.free()
	intro.free()

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
