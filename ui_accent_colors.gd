class_name UIAccentColors
extends RefCounted
# Shared "cream" UI accent color — extracted 2026-07-28. Used throughout
# custom _draw() calls (Control canvas drawing doesn't read from the
# project Theme) plus the Theme builder's own border colors. All 6
# consumers had independently hardcoded the same Color(0.92, 0.90, 0.85)
# RGB triple at different alphas, with no shared source.

const CREAM: Color = Color(0.92, 0.90, 0.85, 1.0)
