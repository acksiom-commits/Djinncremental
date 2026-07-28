class_name PuzzleStateColors
extends Resource
# ================ PUZZLE STATE COLORS v1.0.0 ================
# Shared color palette for constellation-puzzle deduction UI state
# (confirmed/eliminated/protected/neutral clue coloring). Extracted
# 2026-07-27 from ~25 duplicate Color(...) literals scattered across
# constellation_puzzle_widgets.gd, constellation_puzzle_deduction.gd,
# constellation_study_overlay.gd, constellation_fork_puzzle.gd, and
# StaffPopupRow.gd — the same handful of colors independently retyped
# in each file. One shared .tres instance (puzzle_state_colors.tres,
# at project root) is now the single Inspector-editable source; every
# consumer does `const STATE_COLORS := preload("res://puzzle_state_colors.tres")`
# instead of hand-typing the RGBA values.

@export var confirmed: Color = Color(0.3, 1.0, 0.4, 1.0)
@export var eliminated: Color = Color(1.0, 0.35, 0.25, 1.0)
@export var soft_eliminated: Color = Color(0.45, 0.40, 0.55, 1.0)
@export var protected: Color = Color(1.0, 0.0, 1.0, 1.0)
@export var neutral: Color = Color(0.82, 0.78, 0.92, 1.0)
@export var muted: Color = Color(0.55, 0.50, 0.65, 1.0)
@export var unresolved_fallback: Color = Color(0.2, 0.9, 0.2, 1.0)
