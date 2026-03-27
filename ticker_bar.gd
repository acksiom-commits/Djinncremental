extends PanelContainer
# ================= TICKER BAR v0.1.0 =================
# Scrolling ticker that pauses briefly on each item.
# Sits in CanvasLayer above RootUI as a sibling.
# Content is driven by ticker_items array - easy to swap
# in Patreon/achievement data later without touching scroll logic.

# === CONFIGURATION ===
const TICKER_HEIGHT: int = 36
const SCROLL_SPEED: float = 120.0    # pixels per second during scroll
const PAUSE_DURATION: float = 2.0    # seconds to pause when item is centered
const SEPARATOR: String = "     ✦     " # between items during continuous scroll

# === CONTENT ===
# Placeholder content - replace with Patreon/achievement data later.
# Format: {"type": "tip"/"music"/"patron"/"achievement", "text": "..."}
var ticker_items: Array = [
    {"type": "tip",   "text": "Compress 5 Sparks into a Monad — Solid, Liquid, or Gas, chosen by fate."},
    {"type": "tip",   "text": "Assemble 4 Monads and 1 Spark into a Tetrad. Composition determines type."},
    {"type": "tip",   "text": "Fundaments require 4 of the same Monad type. Rarest and most powerful."},
    {"type": "tip",   "text": "Compress 5 Tetrads into an Iota. Type doesn't matter — quantity does."},
    {"type": "tip",   "text": "Archon Foci automate tasks. Assign them wisely — they're scarce early on."},
    {"type": "tip",   "text": "Volitions unlock deeper automation. Earned through Archon progression."},
    {"type": "tip",   "text": "Purity Locks hold resources in reserve for higher-tier crafting. Unlock them with Foci."},
    {"type": "tip",   "text": "20 Grains + 1 Spark creates a Uonite — the first great threshold."},
    {"type": "tip",   "text": "The Archon remembers things you've forgotten. Pay attention to its hints."},
    {"type": "music", "text": "♪ Now Playing: Check the Djinncremental Discord for this week's community playlist! ♪"},
    {"type": "tip",   "text": "Earth = 2 Solid + 1 Liquid + 1 Gas. Water = 2 Liquid + 1 Solid + 1 Gas. Air = 2 Gas + 1 Solid + 1 Liquid."},
    {"type": "tip",   "text": "Mud, Dust, and Cloud are Symmetrics — two pairs of the same type."},
    {"type": "tip",   "text": "Dirt, Sand, Haze, Mist, Ooze, and Foam are Medials — three of one, one of another."},
    {"type": "tip",   "text": "Mote Assembly costs 5 Sparks + 16 Monads + 4 Iotas. Plan your reserves."},
    {"type": "tip",   "text": "Grain Assembly costs 25 Sparks + 64 Monads + 16 Iotas + 4 Particles. Worth it."},
]

# === NODE REFERENCES ===
var label: RichTextLabel = null
var scroll_timer: Timer = null
var pause_timer: Timer = null

# === STATE ===
var current_index: int = 0
var scroll_offset: float = 0.0
var label_width: float = 0.0
var is_pausing: bool = false
var is_scrolling_in: bool = true   # true = scrolling in from right, false = scrolling out to left


# ==================================================
# READY
# ==================================================
func _ready() -> void:
    custom_minimum_size = Vector2(0, TICKER_HEIGHT)

    # Style the panel
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
    style.border_color = Color(0.3, 0.3, 0.5, 1.0)
    style.border_width_bottom = 1
    add_theme_stylebox_override("panel", style)

    # Anchor to top of screen, full width
    set_anchors_preset(Control.PRESET_TOP_WIDE)
    custom_minimum_size = Vector2(0, TICKER_HEIGHT)

    # Create the scrolling label
    label = RichTextLabel.new()
    label.bbcode_enabled = true
    label.fit_content = false
    label.scroll_active = false
    label.custom_minimum_size = Vector2(0, TICKER_HEIGHT)
    label.add_theme_font_size_override("normal_font_size", 14)
    label.add_theme_font_size_override("normal_font_size", 14)
    add_child(label)

    # Pause timer - fires when item is centered
    pause_timer = Timer.new()
    pause_timer.one_shot = true
    pause_timer.wait_time = PAUSE_DURATION
    pause_timer.timeout.connect(_on_pause_ended)
    add_child(pause_timer)

    _load_item(current_index)


# ==================================================
# PROCESS - SCROLL LOGIC
# ==================================================
func _process(delta: float) -> void:
    if is_pausing or label == null:
        return

    var screen_width: float = get_viewport_rect().size.x

    if is_scrolling_in:
        # Scroll in from right edge to center
        scroll_offset -= SCROLL_SPEED * delta
        var center_x = (screen_width - label_width) / 2.0
        label.position.x = max(center_x, screen_width + scroll_offset)

        if label.position.x <= center_x:
            label.position.x = center_x
            is_pausing = true
            pause_timer.start()
    else:
        # Scroll out to left edge
        scroll_offset -= SCROLL_SPEED * delta
        label.position.x = (get_viewport_rect().size.x - label_width) / 2.0 + scroll_offset

        if label.position.x + label_width < 0:
            _advance_item()


# ==================================================
# ITEM MANAGEMENT
# ==================================================
func _load_item(index: int) -> void:
    var item = ticker_items[index]
    var colored_text = _format_item(item)
    label.set("bbcode_text", colored_text)

    # Wait one frame for label to calculate its width
    await get_tree().process_frame
    label_width = label.get_content_width()
    if label_width <= 0:
        label_width = get_viewport_rect().size.x * 0.6  # fallback

    # Start from right edge
    scroll_offset = 0.0
    label.position.x = get_viewport_rect().size.x
    label.position.y = (TICKER_HEIGHT - label.size.y) / 2.0
    is_scrolling_in = true
    is_pausing = false


func _advance_item() -> void:
    current_index = (current_index + 1) % ticker_items.size()
    scroll_offset = 0.0
    is_scrolling_in = true
    is_pausing = false
    _load_item(current_index)


func _on_pause_ended() -> void:
    is_pausing = false
    is_scrolling_in = false
    scroll_offset = 0.0


# ==================================================
# FORMATTING
# ==================================================
func _format_item(item: Dictionary) -> String:
    match item.get("type", "tip"):
        "tip":
            return "[color=#aaddff][ TIP ][/color]  [color=#dddddd]" + item["text"] + "[/color]"
        "music":
            return "[color=#ffdd88]" + item["text"] + "[/color]"
        "patron":
            return "[color=#cc88ff][ PATRON ][/color]  [color=#ffffff]" + item["text"] + "[/color]"
        "achievement":
            return "[color=#ffaa44][ FIRST ][/color]  [color=#ffffff]" + item["text"] + "[/color]"
    return item.get("text", "")


# ==================================================
# PUBLIC API - for Patreon/achievement integration later
# ==================================================
func set_items(items: Array) -> void:
    ticker_items = items
    current_index = 0
    _load_item(current_index)

func add_item(item: Dictionary) -> void:
    ticker_items.append(item)

func insert_item_next(item: Dictionary) -> void:
    # Insert after current item for urgent announcements
    var insert_pos = (current_index + 1) % ticker_items.size()
    ticker_items.insert(insert_pos, item)
