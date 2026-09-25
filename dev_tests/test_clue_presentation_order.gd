extends "res://dev_tests/test_base.gd"
# The Clues display must not show clues in generation order, and the order it
# does show must be FIXED for a puzzle (clue numbers are shared handles, and
# the list is rebuilt on every repaint).

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _clue(t: String) -> Dictionary:
	return {"text": t, "cells": [], "search_terms": [], "disclosures": [], "characteristics": [], "chars": [], "form_id": 0}


func _texts(w) -> Array:
	var out: Array = []
	for c in w._all_final_clues_for_tabs():
		out.append(c["text"])
	return out


func run() -> void:
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	var w = host._widgets

	var gen: Array = []
	for i in range(24):
		gen.append(_clue("Clue number %02d." % i))
	host._form_clues_cache = gen.duplicate()

	print("=== scrambled relative to generation order ===")
	var a: Array = _texts(w)
	var gen_texts: Array = []
	for c in gen:
		gen_texts.append(c["text"])
	ok(a.size() == 24, "every clue is still shown (%d of 24)" % a.size())
	ok(a != gen_texts, "the shown order differs from generation order")
	var sorted_a: Array = a.duplicate()
	sorted_a.sort()
	ok(sorted_a == gen_texts, "it is a permutation: nothing dropped or duplicated")

	print("\n=== fixed per puzzle ===")
	ok(_texts(w) == a, "repainting gives the same order")
	var rev: Array = gen.duplicate()
	rev.reverse()
	host._form_clues_cache = rev
	ok(_texts(w) == a, "the order does not depend on how the cache is stored")

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
