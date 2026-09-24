extends CanvasLayer
# Standalone version of the Prestige/Expansion "universe compresses to
# white, then recedes" transition (root_ui.gd's _play_expansion_animation,
# Phase 1/Phase 2), usable by a caller whose OWN node is about to be freed
# mid-transition — intro_screen.gd's vessel-selection sequence needs the
# white-out to survive a change_scene_to_file() call, and a node parented
# under the scene being swapped out cannot survive that; a node parented
# directly under get_tree().root (a sibling of current_scene, not a child
# of it) does.
#
# Extends CanvasLayer, not ColorRect directly — RootUI.tscn's entire UI
# lives inside its own CanvasLayer (Node2D/CanvasLayer), and a
# CanvasLayer's `layer` value overrides z_index ENTIRELY: an item with no
# CanvasLayer ancestor (the base/default canvas) always draws BEHIND any
# CanvasLayer, no matter how high its own z_index is set. The first
# version of this overlay was a plain ColorRect added straight to
# get_tree().root, sitting in the base canvas — Phase 1 (still on the
# intro screen, which has no CanvasLayer of its own) looked fine, but the
# instant RootUI.tscn loaded, its CanvasLayer content rendered ON TOP of
# the overlay, hiding Phase 2's recede completely. Reported: "sits there
# and then instantly changes to the Main UI." A high `layer` value here
# (LAYER, below) guarantees this draws above ANY CanvasLayer either scene
# uses, not just RootUI's current one.
#
# Usage:
#   var overlay := preload("res://expansion_overlay.gd").new()
#   get_tree().root.add_child(overlay)
#   overlay.setup()
#   await overlay.warp_to_white(1.8)      # Phase 1
#   get_tree().change_scene_to_file(...)  # overlay survives this
#   ...
#   await overlay.recede_and_free(1.8)    # Phase 2, from whatever scene loaded next
#
# root_ui.gd's OWN in-game trigger (_play_expansion_animation) is
# deliberately left as its own separate implementation, not refactored
# onto this — it already works (its overlay is added as a sibling INSIDE
# RootUI's own CanvasLayer subtree, so it never had this problem), has
# its own click-position zoom/scale flourish this class doesn't need, and
# touching working code for a DRY-ness gain nobody asked for is exactly
# the kind of unscoped cleanup this project avoids.

const PENDING_REVEAL_GROUP: String = "pending_reveal_overlay"
const LAYER: int = 128

var _shader_mat: ShaderMaterial = null
var _rect: ColorRect = null


func setup() -> void:
    layer = LAYER
    _rect = ColorRect.new()
    _rect.color        = Color(1.0, 1.0, 1.0, 1.0)
    _rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    _shader_mat = ShaderMaterial.new()
    _shader_mat.shader = preload("res://expansion_transition.gdshader")
    _shader_mat.set_shader_parameter("distortion_strength", 0.0)
    _shader_mat.set_shader_parameter("white_amount",        0.0)
    _rect.material = _shader_mat
    add_child(_rect)
    add_to_group(PENDING_REVEAL_GROUP)


func warp_to_white(duration: float = 1.8) -> void:
    visible = true
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_method(
        func(v: float): _shader_mat.set_shader_parameter("distortion_strength", v),
        0.0, 1.5, duration
    ).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    tween.tween_method(
        func(v: float): _shader_mat.set_shader_parameter("white_amount", v),
        0.0, 1.0, duration
    ).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    await tween.finished


func recede_and_free(duration: float = 1.8) -> void:
    remove_from_group(PENDING_REVEAL_GROUP)
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_method(
        func(v: float): _shader_mat.set_shader_parameter("distortion_strength", v),
        1.5, 0.0, duration
    ).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    tween.tween_method(
        func(v: float): _shader_mat.set_shader_parameter("white_amount", v),
        1.0, 0.0, duration
    ).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    await tween.finished
    queue_free()
