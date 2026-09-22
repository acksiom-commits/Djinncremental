extends "res://dev_tests/test_base.gd"
# Sparks genbar bug (user-reported 2026-09-21): the bar reduced to 0%
# long before the actual Sparks pool was empty. Root cause: the genbar's
# fill fraction was NEVER derived from game_context.sparks at all -- it
# was a "does assigned workforce meet POTENTIAL downstream demand" health
# meter, decaying via `(potential_net / assign_f / 10.0) * delta * 100.0`.
# potential_net is a raw Sparks/sec rate (easily hundreds+ past the very
# early game); feeding that directly into a percent-per-second decay with
# only a flat /10 divisor collapses the bar to 0% in a fraction of a
# second at any realistic scale, regardless of how full the real pool is.
#
# Fixed: Sparks now gets its own branch using the actual pool and the
# REAL net drain rate (actual_drain - prod_per_sec, already computed as
# `net_drain`), mapped onto SPARKS_RUNWAY_REFERENCE_SECONDS of runway.
# Sparks has no storage cap (get_storage_total() excludes it), so a
# time-until-empty runway gauge is the correct fullness metric here, not
# a "current stock / cap" fraction the way capped resources could use.
#
# A bare root_ui.gd instance with real (fresh, not autoload) GameContext/
# ProductionManager/GameData collaborators injected -- same pattern as
# test_second_volition_gate.gd, since _update_bars() only touches gc/pm/
# game_data and the bars dict, nothing else RootUI.tscn would normally
# wire up. bars["sparks"] is populated with a bare ProgressBar/Label pair
# instead of going through _setup_bars()'s find_child() scene lookup.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var ui = load("res://root_ui.gd").new()
	var gc = load("res://game_context.gd").new()
	var pm = load("res://production_manager.gd").new()
	var gd_ = load("res://game_data.gd").new()
	ui.game_context      = gc
	ui.production_manager = pm
	ui.game_data          = gd_
	pm.gc        = gc
	pm.game_data = gd_

	var bar := ProgressBar.new()
	var lbl := Label.new()
	ui.bars["sparks"] = {"gen_bar": bar, "gen_lbl": lbl}

	# --- Scenario 1: draining pool, well short of empty -------------------
	# 10 Sparks/sec production, 4 monad_compress/sec at 5 sparks each = 20
	# Sparks/sec actual drain -> net_drain = 10/sec. With 150 Sparks
	# banked, that's 15 seconds of runway out of a 30-second reference ->
	# should read 50%, NOT 0%.
	gc.rates["sparks_summon"]  = BigNum.from_int(10)
	gc.rates["monad_compress"] = BigNum.from_int(4)
	gc.sparks = BigNum.from_int(150)
	ui._update_bars(0.016)
	print("  scenario 1: 150 sparks banked, net drain 10/s -> bar=%.1f%% (want 50%%)" % bar.value)
	ok(is_equal_approx(bar.value, 50.0), "bar reads a real fraction of runway, not collapsed to 0")

	# --- Scenario 2: same drain rate, pool nearly empty --------------------
	gc.sparks = BigNum.from_int(3)
	ui._update_bars(0.016)
	print("  scenario 2: 3 sparks banked, net drain 10/s -> bar=%.1f%%" % bar.value)
	ok(bar.value < 15.0, "bar correctly reads very low when the real pool is genuinely almost empty")

	# --- Scenario 3: pool is FULL, same tiny drain rate would have nuked
	# the OLD formula instantly (it never looked at sparks at all) --------
	gc.sparks = BigNum.from_int(100000)
	ui._update_bars(0.016)
	print("  scenario 3: 100,000 sparks banked, same net drain 10/s -> bar=%.1f%% (want 100%%)" % bar.value)
	ok(is_equal_approx(bar.value, 100.0),
		"a well-stocked pool reads full even under sustained drain, until it's actually close to empty")

	# --- Scenario 4: production comfortably meets/exceeds actual drain ----
	gc.rates["sparks_summon"]  = BigNum.from_int(50)
	gc.rates["monad_compress"] = BigNum.from_int(4)  # still 20/s drain
	gc.sparks = BigNum.from_int(1)
	ui._update_bars(0.016)
	print("  scenario 4: production (50/s) exceeds drain (20/s), pool=1 -> bar=%.1f%% (want 100%%)" % bar.value)
	ok(is_equal_approx(bar.value, 100.0),
		"bar reads full whenever production covers actual drain, regardless of current stock")

	# --- Scenario 5: a large assigned workforce (the old bug's trigger)
	# must NOT crash the bar to 0 the instant potential demand is high,
	# as long as the ACTUAL pool/drain relationship is healthy ------------
	gc.assignments["sparks_summon_volitions"] = 1
	gc.rates["sparks_summon"]  = BigNum.from_int(10)
	gc.rates["monad_compress"] = BigNum.from_int(4)
	gc.sparks = BigNum.from_int(150)
	ui._update_bars(0.016)
	print("  scenario 5: same as scenario 1 but with a large potential-demand workforce assigned -> bar=%.1f%%" % bar.value)
	ok(is_equal_approx(bar.value, 50.0),
		"bar is driven by the real pool/drain relationship, not by assigned-worker potential demand")

	ui.free()
	gc.free()
	pm.free()
	gd_.free()
	bar.free()
	lbl.free()
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
