extends RefCounted
# ================= AGE SWITCH TURN v1.0.0 =================
# Switching ages turns the view across the sky (author, 2026-11-03). Each age's
# page sits a quarter turn along the sky from the last, later ages to the
# right: going Primordial -> Firmament the view turns right, so the stars and
# the Primordial page slide off to the left as Firmament comes in from the
# right; going back turns left. The pages slide one screen width while the sky
# turns, and the new page keeps the turned sky (handed over in memory, not
# saved), so it doesn't jump.
#
# Both pages are in the tree during the turn: the new one is loaded beside the
# old, which is cut off from game-wide signals, stops processing (its sky keeps
# drawing) and is freed at the end. Each page is a CanvasLayer (Firmament) or
# holds one (Primordial's Node2D); its offset slides the page, and its
# starfield and sky overlay are held still against it so only the turn moves
# the stars. The new page is drawn above the old for the turn, with its own
# sky hidden until the end. Anything mostly past the left or right edge when
# the turn starts (closed edge panels wait there) is hidden while the pages
# slide, and the new page's comes back afterwards.

## Ages in order, left to right across the sky.
const AGE_SCENES := ["res://RootUI.tscn", "res://FirmamentUI.tscn",
    "res://WorldUI.tscn", "res://CivilizationUI.tscn"]
const TURN: float = PI * 0.5
const DURATION: float = 1.2

## Page scenes already loaded, kept for the session so a switch never waits on
## loading one (Firmament ~250 ms, Primordial more; measured 2026-11-03).
static var _scenes: Dictionary = {}

## True while a switch builds the new page. The game's state is already live,
## so root_ui.gd then skips re-reading the save file on arrival (2026-11-04):
## nothing is saved at the click (the Ages panel saves when it opens), and the
## re-read put the save's Journal into the old page, which was still current.
static var arriving: bool = false


## Loads the pages next to `scene_path` in age order, if they exist, while
## that page is being built (its own load pause), so the first switch is quick.
## Keeps `scene_path` itself too: it is loaded already, so that costs nothing,
## and without it the next page would load it again during the switch back.
static func warm_neighbours(scene_path: String) -> void:
    var i: int = AGE_SCENES.find(scene_path)
    for j in [i, i - 1, i + 1]:
        if j >= 0 and j < AGE_SCENES.size() and ResourceLoader.exists(AGE_SCENES[j]):
            _scene(AGE_SCENES[j])


## Pages created ahead of a switch, not yet in the tree, by scene path. Creating
## a page's nodes (~75-125 ms) has no side effects until it is added, so the
## Ages tab does it on hover (2026-11-04) and the click only adds it. Adding
## runs its setup, which connects it to the game, so that stays at the click.
static var _prebuilt: Dictionary = {}
## Scene path -> the node that asked for it (its page's Ages tab).
static var _prebuilt_by: Dictionary = {}


## Creates the page at `scene_path` now, for `asker`, if it exists and isn't
## made already.
static func prepare(scene_path: String, asker: Node) -> void:
    if _prebuilt.has(scene_path) or not ResourceLoader.exists(scene_path):
        return
    var packed: PackedScene = _scene(scene_path)
    if packed:
        _prebuilt[scene_path] = packed.instantiate()
        _prebuilt_by[scene_path] = asker


## Frees the pages `asker` made ahead and didn't use. Its page's Ages tab calls
## this as the page goes, so none outlive the page they were made from, and a
## page made by the next page's tab during the turn is left alone.
static func release_prebuilt(asker: Node) -> void:
    for path in _prebuilt.keys():
        if _prebuilt_by.get(path) != asker:
            continue
        var n: Node = _prebuilt[path]
        if is_instance_valid(n) and not n.is_inside_tree():
            n.free()
        _prebuilt.erase(path)
        _prebuilt_by.erase(path)


static func _scene(path: String) -> PackedScene:
    if not _scenes.has(path):
        _scenes[path] = load(path) as PackedScene
    return _scenes[path]


## Switches from the current page to `scene_path`, turning the view.
static func run(tree: SceneTree, scene_path: String) -> void:
    var old_scene: Node = tree.current_scene
    var packed: PackedScene = _scene(scene_path)
    var old_layer: CanvasLayer = _layer_of(old_scene)
    if packed == null or old_layer == null:
        tree.change_scene_to_file(scene_path)
        return
    var dir: float = 1.0 if AGE_SCENES.find(scene_path) > AGE_SCENES.find(old_scene.scene_file_path) else -1.0
    var width: float = tree.root.get_visible_rect().size.x

    var old_sky: Array = _sky_of(old_layer)
    var old_sf: Node = old_layer.get_node_or_null("ColorRect")
    # The Journal (History and Notices) lives on the page, so it is handed on.
    var journal: Dictionary = _journal_data(old_scene)
    # The old page goes quiet before the new one loads, so the new page's
    # arrival (its dialogue, journal entries, reveals) reaches only the new page.
    _detach(tree, old_scene)
    old_scene.process_mode = Node.PROCESS_MODE_DISABLED
    for n in old_sky:
        n.process_mode = Node.PROCESS_MODE_ALWAYS
    var start: Basis = Basis.IDENTITY
    if old_sf and old_sf.has_method("set_turning"):
        start = old_sf.get_effective_view_matrix()
        old_sf.set_turning(true)

    var new_scene: Node = _prebuilt.get(scene_path)
    _prebuilt.erase(scene_path)
    _prebuilt_by.erase(scene_path)
    if not is_instance_valid(new_scene):
        new_scene = packed.instantiate()
    arriving = true
    tree.root.add_child(new_scene)
    var new_layer: CanvasLayer = _layer_of(new_scene)
    var new_layer_index: int = 0
    var restore: Array = []
    if new_layer:
        new_layer.offset.x = dir * width
        new_layer_index = new_layer.layer
        new_layer.layer = old_layer.layer + 1
        for n in _sky_of(new_layer):
            if n.visible:
                n.visible = false
                restore.append(n)
    # One frame for the new page to lay out and place its edge panels, and to
    # run its deferred arrival (root_ui.gd's _load_on_start reads `arriving`).
    await tree.process_frame
    arriving = false
    _hand_on_journal(journal, new_scene)
    if new_layer:
        restore.append_array(_hide_offside(new_layer, width))
    _hide_offside(old_layer, width)

    var step := func(t: float) -> void:
        var x: float = -dir * width * t
        old_layer.offset.x = x
        if new_layer:
            new_layer.offset.x = x + dir * width
        for n in old_sky:
            n.position.x = -x
        if old_sf and old_sf.has_method("set_view_matrix"):
            old_sf.set_view_matrix(start * Basis(Vector3.UP, dir * TURN * t))
    step.call(0.0)

    var tween: Tween = tree.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tween.tween_method(step, 0.0, 1.0, DURATION)
    tween.tween_callback(func() -> void:
        if new_layer:
            new_layer.offset.x = 0.0
            new_layer.layer = new_layer_index
            var new_sf: Node = new_layer.get_node_or_null("ColorRect")
            if new_sf and new_sf.has_method("set_view_matrix"):
                new_sf.set_view_matrix(start * Basis(Vector3.UP, dir * TURN))
        for n in restore:
            if is_instance_valid(n):
                n.visible = true
        tree.current_scene = new_scene
        old_scene.queue_free())


## The page's CanvasLayer: the scene itself, or its first CanvasLayer child.
static func _layer_of(scene: Node) -> CanvasLayer:
    if scene is CanvasLayer:
        return scene
    if scene:
        for c in scene.get_children():
            if c is CanvasLayer:
                return c
    return null


## The page's Journal contents (History "sequences" and Notices
## "notifications"), as SaveManager saves them; {} if it has no Journal.
static func _journal_data(scene: Node) -> Dictionary:
    var j: Node = scene.find_child("JournalPopout", true, false) if scene else null
    if j and j.has_method("get_save_data"):
        return (j.get_save_data() as Dictionary).duplicate(true)
    return {}


## Puts the old page's Journal into the new page's, followed by anything the new
## page added on arrival (its own dialogue, Notices).
static func _hand_on_journal(carried: Dictionary, new_scene: Node) -> void:
    var j: Node = new_scene.find_child("JournalPopout", true, false)
    if carried.is_empty() or not j or not j.has_method("load_save_data"):
        return
    var arrived: Dictionary = j.get_save_data()
    var merged: Dictionary = {}
    for key in ["sequences", "notifications"]:
        var list: Array = []
        list.append_array(carried.get(key, []))
        list.append_array(arrived.get(key, []))
        merged[key] = list
    j.load_save_data(merged)


## Disconnects every game-wide (autoload) signal from the old page and takes
## the dialogue display back from it. It is being freed; until then it must not
## react to anything, or the new page's arrival dialogue shows on the old page.
static func _detach(tree: SceneTree, old_scene: Node) -> void:
    var adm: Node = tree.root.get_node_or_null("ArchonDialogueManager")
    if adm and adm.has_method("set_display_nodes"):
        adm.set_display_nodes(null, null)
    for autoload in tree.root.get_children():
        if autoload == old_scene:
            continue
        for sig in autoload.get_signal_list():
            for c in autoload.get_signal_connection_list(sig["name"]):
                var target: Object = (c["callable"] as Callable).get_object()
                if target is Node and (target == old_scene or old_scene.is_ancestor_of(target)):
                    autoload.disconnect(sig["name"], c["callable"])


## Hides each visible Control on the layer that is mostly past the left or right
## edge of the screen (closed edge panels wait there), outermost first, and
## returns them. Only the horizontal span counts: some page roots run past the
## bottom of the window.
static func _hide_offside(layer: CanvasLayer, width: float) -> Array:
    var hidden: Array = []
    var stack: Array = layer.get_children()
    while not stack.is_empty():
        var n: Node = stack.pop_back()
        if n is Control and (n as Control).visible:
            var r: Rect2 = (n as Control).get_global_rect()
            var on_screen: float = minf(r.end.x, width) - maxf(r.position.x, 0.0)
            if r.size.x > 0.0 and on_screen < r.size.x * 0.5:
                n.visible = false
                hidden.append(n)
                continue
        stack.append_array(n.get_children())
    return hidden


## The parts of a page that belong to the sky: its starfield and the overlay
## that draws constellations on it.
static func _sky_of(layer: CanvasLayer) -> Array:
    var out: Array = []
    for nm in ["ColorRect", "ConstellationOverlay"]:
        var n: Node = layer.get_node_or_null(nm)
        if n is CanvasItem:
            out.append(n)
    return out
