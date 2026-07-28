class_name SlidePanelToggle
extends RefCounted
# Shared tween-construction boilerplate for edge-popout slide panels
# (journal/settings/ages/constellation) — extracted 2026-07-28. Each popout
# independently hand-rolled the same kill-stale-tween/create/tab-tween/
# parallel-panel-tween sequence in its open and close handlers. Doesn't own
# open/closed state or position-space choice (some popouts tween the tab
# via local "position:x" and the panel via "global_position:x" — the caller
# still decides that and computes any dynamic target), it only builds and
# returns the Tween.

static func run(tab_btn: Node, tab_prop: String, tab_target: float,
        panel: Node, panel_prop: String, panel_target: float,
        anim_time: float, existing_tween: Tween) -> Tween:
    if existing_tween:
        existing_tween.kill()
    var t := tab_btn.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    t.tween_property(tab_btn, tab_prop, tab_target, anim_time)
    t.parallel().tween_property(panel, panel_prop, panel_target, anim_time)
    return t
