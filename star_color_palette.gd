class_name StarColorPalette
extends Resource
# ================ STAR COLOR PALETTE v1.0.0 ================
# The 4 possible star colors (index-matched to the Blue/White/Yellow-
# Orange/Red ordering used throughout the constellation puzzle), shared
# between constellation_overlay.gd (draws the actual star map) and
# constellation_study_overlay.gd (draws the enlarged Study panel's star
# map) — extracted 2026-07-27, they'd each declared an identical
# STAR_COLORS_BY_IDX array independently, with no shared source, so a
# retune to one would silently drift from the other.

@export var by_idx: Array[Color] = [
    Color(0.45, 0.65, 1.00, 1.0),  # 0 BLUE
    Color(1.00, 1.00, 1.00, 1.0),  # 1 WHITE
    Color(1.00, 0.80, 0.30, 1.0),  # 2 YELLOW_ORANGE
    Color(1.00, 0.35, 0.25, 1.0),  # 3 RED
]
