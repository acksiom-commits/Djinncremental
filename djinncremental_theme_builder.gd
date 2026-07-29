extends Node
# ================= DJINNCREMENTAL THEME BUILDER v0.5.0 =================
# Run this script once to generate djinncremental_theme.tres
# Attach to ThemeBuilderPanel, run the scene, then detach the script.
#
# Theme is applied globally via:
# Project Settings -> GUI -> Theme -> Custom Theme
# pointing to res://djinncremental_theme.tres
#
# NOTE: regenerating from scratch (Theme.new()) produces a resource with
# no `uid`. The committed .tres carries uid://t7mug8aetm11 in its
# [gd_resource] header — after running this, reopen the project in the
# editor once so it rescans and reassigns a matching uid, or diff/patch
# the regenerated file in by hand (as was done for the DialogConfirmButton
# addition) instead of overwriting the committed file outright.
#
# CHANGELOG v0.5.0:
# - Synced all font sizes to 18 (Button/Label/LineEdit/ProgressBar/
#   RichTextLabel/SpinBox) and added default_font_size = 18 — these had
#   been hand-tuned directly in the editor's Theme inspector since v0.4.0
#   was last run, so the script no longer matched the live .tres. A
#   from-scratch regeneration would have silently reverted that tuning.
#   Every color/stylebox/margin value was diffed against the live
#   djinncremental_theme.tres and already matched exactly — font size was
#   the only drift.
# CHANGELOG v0.4.0:
# - Added "DialogConfirmButton" type variation, porting settings_popout.gd's
#   former per-instance _style_dialog_button() StyleBoxFlat construction.
# CHANGELOG v0.3.0:
# - LineEdit content margins top/bottom: 0 -> 6 (taller SpinBox arrows)
# - SpinBox minimum_grab_thickness: 28
# CHANGELOG v0.2.0:
# - RichTextLabel normal_font_size: 14 -> 16
# - Label font_size: 13 -> 16

# ===================== PALETTE ======================
# Panel backgrounds: dark purple-tinted
const BG_PRIMARY    = Color(0.07, 0.06, 0.10, 0.85)  # dark purple, 85% opaque
const BG_SECONDARY  = Color(0.10, 0.08, 0.14, 0.85)  # slightly lighter
const BG_HOVER      = Color(0.14, 0.11, 0.20, 0.95)  # hover state
const BG_PRESSED    = Color(0.05, 0.04, 0.08, 0.95)  # pressed state
const BG_DISABLED   = Color(0.06, 0.05, 0.09, 0.60)  # disabled

# Borders: subtle purple-grey
const BORDER_NORMAL  = Color(UIAccentColors.CREAM, 0.35)
const BORDER_FOCUS   = Color(UIAccentColors.CREAM, 0.90)
const BORDER_HOVER   = Color(UIAccentColors.CREAM, 0.60)

# Text
const TEXT_PRIMARY   = Color(0.92, 0.92, 0.95, 1.00)  # near-white
const TEXT_SECONDARY = Color(0.65, 0.63, 0.72, 1.00)  # muted
const TEXT_DISABLED  = Color(0.40, 0.38, 0.45, 1.00)

# Resource accent colors (matching icon spectrum)
const ACCENT_SPARKS   = Color(1.00, 1.00, 1.00, 1.00)  # white
const ACCENT_MONAD    = Color(0.80, 0.13, 0.13, 1.00)  # red
const ACCENT_TETRAD   = Color(0.88, 0.41, 0.00, 1.00)  # orange
const ACCENT_IOTA     = Color(0.93, 0.80, 0.00, 1.00)  # yellow
const ACCENT_MOTE     = Color(0.13, 0.67, 0.27, 1.00)  # green
const ACCENT_PARTICLE = Color(0.10, 0.42, 0.80, 1.00)  # blue
const ACCENT_GRAIN    = Color(0.47, 0.13, 0.80, 1.00)  # purple
const ACCENT_UONITE   = Color(0.80, 0.53, 0.00, 1.00)  # gold


func _ready() -> void:
    build_theme()
    print("Theme built and saved. Detach this script from ThemeBuilderPanel now.")


func build_theme() -> void:
    var theme = Theme.new()
    theme.default_font_size = 18

    # ================================================
    # PANEL CONTAINER
    # ================================================
    var panel_style = _make_stylebox(BG_PRIMARY, BORDER_NORMAL, 1, 6)
    theme.set_stylebox("panel", "PanelContainer", panel_style)

    # ================================================
    # PANEL (plain Panel node)
    # ================================================
    var plain_panel = _make_stylebox(BG_PRIMARY, BORDER_NORMAL, 1, 4)
    theme.set_stylebox("panel", "Panel", plain_panel)

    # ================================================
    # BUTTONS — base style
    # ================================================
    var btn_normal   = _make_stylebox(BG_SECONDARY, BORDER_NORMAL,  1, 4)
    var btn_hover    = _make_stylebox(BG_HOVER,     BORDER_HOVER,   1, 4)
    var btn_pressed  = _make_stylebox(BG_PRESSED,   BORDER_FOCUS,   1, 4)
    var btn_disabled = _make_stylebox(BG_DISABLED,  BORDER_NORMAL,  1, 4)
    var btn_focus    = _make_stylebox(Color(0,0,0,0), BORDER_FOCUS, 2, 4)

    theme.set_stylebox("normal",   "Button", btn_normal)
    theme.set_stylebox("hover",    "Button", btn_hover)
    theme.set_stylebox("pressed",  "Button", btn_pressed)
    theme.set_stylebox("disabled", "Button", btn_disabled)
    theme.set_stylebox("focus",    "Button", btn_focus)

    theme.set_color("font_color",          "Button", TEXT_PRIMARY)
    theme.set_color("font_hover_color",    "Button", TEXT_PRIMARY)
    theme.set_color("font_pressed_color",  "Button", TEXT_PRIMARY)
    theme.set_color("font_disabled_color", "Button", TEXT_DISABLED)
    theme.set_font_size("font_size", "Button", 18)

    # ================================================
    # DIALOG CONFIRM BUTTON — type variation for confirmation-dialog
    # buttons (e.g. settings_popout.gd's Reset confirmation OK/Cancel).
    # Ported from settings_popout.gd's former _style_dialog_button(),
    # which hand-built these StyleBoxFlats at runtime per-instance
    # instead of going through the shared Theme. Only normal/hover/
    # pressed + font_color/font_hover_color are set here, matching what
    # that function used to override — disabled/focus/font_pressed_color
    # still fall through to the base "Button" type above, same as before.
    # ================================================
    theme.set_type_variation("DialogConfirmButton", "Button")

    var dcb_normal  = _make_stylebox(Color(0.12, 0.09, 0.22, 0.95), Color(0.4, 0.28, 0.62, 0.9), 1, 4)
    var dcb_hover   = _make_stylebox(Color(0.18, 0.13, 0.30, 0.96), Color(0.55, 0.38, 0.80, 1.0), 1, 4)
    var dcb_pressed = _make_stylebox(Color(0.25, 0.18, 0.42, 1.0),  Color(0.65, 0.45, 0.90, 1.0), 1, 4)
    for sb in [dcb_normal, dcb_hover, dcb_pressed]:
        sb.content_margin_left   = 16
        sb.content_margin_right  = 16
        sb.content_margin_top    = 8
        sb.content_margin_bottom = 8

    theme.set_stylebox("normal",  "DialogConfirmButton", dcb_normal)
    theme.set_stylebox("hover",   "DialogConfirmButton", dcb_hover)
    theme.set_stylebox("pressed", "DialogConfirmButton", dcb_pressed)
    theme.set_color("font_color",       "DialogConfirmButton", Color(0.82, 0.82, 0.95, 1.0))
    theme.set_color("font_hover_color", "DialogConfirmButton", Color(1.0, 1.0, 1.0, 1.0))

    # ================================================
    # LABEL
    # ================================================
    theme.set_color("font_color",        "Label", TEXT_PRIMARY)
    theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
    theme.set_font_size("font_size",     "Label", 18)

    # ================================================
    # RICH TEXT LABEL
    # ================================================
    theme.set_color("default_color",        "RichTextLabel", TEXT_PRIMARY)
    theme.set_font_size("normal_font_size", "RichTextLabel", 18)
    theme.set_stylebox("normal", "RichTextLabel",
        _make_stylebox(Color(0,0,0,0), Color(0,0,0,0), 0, 0))

    # ================================================
    # SPINBOX
    # ================================================
    var spin_style = _make_stylebox(BG_PRIMARY, BORDER_NORMAL, 1, 3)
    theme.set_stylebox("normal", "SpinBox", spin_style)
    theme.set_color("font_color", "SpinBox", TEXT_PRIMARY)
    theme.set_font_size("font_size", "SpinBox", 18)
    theme.set_constant("minimum_grab_thickness", "SpinBox", 28)

    # ================================================
    # LINE EDIT (SpinBox inner field)
    # Vertical content margins make the SpinBox taller,
    # which in turn makes the arrow buttons larger and
    # easier to click — critical for accessibility and
    # the game's forgiving-click design philosophy.
    # ================================================
    var le_normal = _make_stylebox(BG_PRIMARY,   BORDER_NORMAL, 1, 3)
    var le_focus  = _make_stylebox(BG_SECONDARY, BORDER_FOCUS,  1, 3)
    le_normal.content_margin_top    = 6
    le_normal.content_margin_bottom = 6
    le_focus.content_margin_top     = 6
    le_focus.content_margin_bottom  = 6
    theme.set_stylebox("normal", "LineEdit", le_normal)
    theme.set_stylebox("focus",  "LineEdit", le_focus)
    theme.set_color("font_color",          "LineEdit", TEXT_PRIMARY)
    theme.set_color("font_selected_color", "LineEdit", TEXT_PRIMARY)
    theme.set_color("selection_color",     "LineEdit", ACCENT_GRAIN)
    theme.set_color("cursor_color",        "LineEdit", TEXT_PRIMARY)
    theme.set_font_size("font_size",       "LineEdit", 18)

    # ================================================
    # PROGRESS BAR
    # ================================================
    var pb_bg   = _make_stylebox(BG_PRIMARY,  BORDER_NORMAL,  1, 2)
    var pb_fill = _make_stylebox(ACCENT_MOTE, Color(0,0,0,0), 0, 2)
    theme.set_stylebox("background", "ProgressBar", pb_bg)
    theme.set_stylebox("fill",       "ProgressBar", pb_fill)
    theme.set_color("font_color",    "ProgressBar", TEXT_PRIMARY)
    theme.set_font_size("font_size", "ProgressBar", 18)

    # ================================================
    # MARGIN CONTAINER — transparent
    # ================================================
    theme.set_constant("margin_left",   "MarginContainer", 6)
    theme.set_constant("margin_right",  "MarginContainer", 6)
    theme.set_constant("margin_top",    "MarginContainer", 6)
    theme.set_constant("margin_bottom", "MarginContainer", 6)

    # ================================================
    # SAVE
    # ================================================
    var err = ResourceSaver.save(theme, "res://djinncremental_theme.tres")
    if err == OK:
        print("Theme saved to res://djinncremental_theme.tres")
    else:
        push_error("Failed to save theme: " + str(err))


# ================================================
# HELPER — creates a StyleBoxFlat cleanly
# ================================================
func _make_stylebox(bg: Color, border: Color, border_width: int, corner_radius: int) -> StyleBoxFlat:
    var s = StyleBoxFlat.new()
    s.bg_color = bg
    s.border_color = border
    s.border_width_left   = border_width
    s.border_width_right  = border_width
    s.border_width_top    = border_width
    s.border_width_bottom = border_width
    s.corner_radius_top_left     = corner_radius
    s.corner_radius_top_right    = corner_radius
    s.corner_radius_bottom_left  = corner_radius
    s.corner_radius_bottom_right = corner_radius
    s.anti_aliasing = true
    return s
