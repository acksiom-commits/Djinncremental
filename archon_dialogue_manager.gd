extends Node

# ================== ARCHON DIALOGUE MANAGER v0.9.1 ==================
# Supports null button (no ContinueButton needed)

const ARCHON_COLOR = "#aaddff"
var player_color: String = "#fff4dd"

var _label: RichTextLabel = null
var _button: Button = null

var dialogue_queue: Array = []
var current_index: int = -1
var _showing_player: bool = false
var _has_player_half: bool = false

var level: int = 1
var refinements_completed: int = 0
var refinements_per_level: int = 100
var intro_done: bool = false
var monad_upgrade_done: bool = false
var tetrad_upgrade_done: bool = false

signal dialogue_ended()
signal level_up(new_level: int)


func set_display_nodes(label: RichTextLabel, button: Button = null) -> void:
    _label  = label
    _button = button

    if _button and not _button.pressed.is_connected(_on_continue_pressed):
        _button.pressed.connect(_on_continue_pressed)

    _refresh_display()


func enqueue_dialogue(lines: Array) -> void:
    dialogue_queue += lines
    if current_index == -1:
        _advance()


func advance_dialogue() -> void:
    _on_continue_pressed()


func _on_continue_pressed() -> void:
    if current_index < 0:
        return
    if _has_player_half and not _showing_player:
        _showing_player = true
        _refresh_display()
        return
    _advance()


func _advance() -> void:
    if dialogue_queue.is_empty():
        current_index = -1
        _showing_player = false
        _has_player_half = false
        _refresh_display()
        emit_signal("dialogue_ended")
        return

    current_index += 1
    if current_index >= dialogue_queue.size():
        current_index = dialogue_queue.size() - 1
        _showing_player = false
        _has_player_half = false
        _refresh_display()
        emit_signal("dialogue_ended")
        return

    var entry: String = dialogue_queue[current_index]
    _has_player_half = "||" in entry
    _showing_player = false
    _refresh_display()


func _refresh_display() -> void:
    if not _label:
        return

    if current_index < 0 or dialogue_queue.is_empty():
        _label.set("bbcode_text", "")
        if _button:
            _button.visible = false
        return

    var entry: String = dialogue_queue[current_index]
    var archon_text: String = entry
    var player_text: String = ""

    if "||" in entry:
        var parts = entry.split("||", true, 1)
        archon_text = parts[0]
        player_text = parts[1] if parts.size() > 1 else ""

    var bbcode = "[color=%s]%s[/color]" % [ARCHON_COLOR, archon_text]

    if _showing_player and player_text != "":
        bbcode += "\n\n[color=%s]%s[/color]" % [player_color, player_text]

    _label.set("bbcode_text", bbcode)

    if _button:
        _button.visible = true
        _button.text = "..." if (_has_player_half and not _showing_player) else "Continue"


func start_intro() -> void:
    if intro_done:
        return
    intro_done = true
    enqueue_dialogue([
        "Hiya Boss! Ready to get started?||WHO, ME? WAIT, START WHAT?",
        "Get started building your own. . .oh. They didn't highlight that.||HIGHLIGHT WHAT NOW? WAIT, BUILD WHAT, TOO?",
        "That you took the amnesia package after completing your Lessons, Boss. Sorry I didn't realize right away. . . even though it's not my fault. . .anyways, you decided not to remember all the personal stuff about your, er, Training time. . . ?||AND THE BUILDING PART?",
        "Well, you get to build your own world now, pretty much from scratch. And I'm your assigned Uonite assistant. Tutor and mentor now, too, I guess. Summon four Sparks and I'll show you the basics.||BUILDING MY OWN WORLD DOES SOUND APPEALING. . .I'LL TRY IT.",
        "That's the spirit! Let's make something great together!||ALL RIGHT, DIAL BACK THE ENTHUSIASM THERE A LITTLE, PLEASE.",
    ])


func enqueue_monad_upgrade() -> void:
    if monad_upgrade_done:
        return
    monad_upgrade_done = true
    enqueue_dialogue([
        "Hey, I think you got me Upgraded by forming that first Monad!||WHOA, I DID WHAT NOW?",
        "Qualified me for a Focus Upgrade! It's not usual for that to happen this soon, either. That's why I think you get the credit for it.||WHAT, JUST BY FORMING A MONAD?",
        "The most likely case is that you selected some kind of 'Faster Archon Upgrades' advantage while customizing your new reality.||OH? I SUPPOSE THAT DOES MAKE SENSE.",
        "Yes, but...I'm not saying it's exactly one-for-one across here, but Amnesia is usually taken as part of a trade-off for something preferred, so...thank you. Sincerely.||WELL, IF THAT'S THE CASE, YOU'RE CERTAINLY WELCOME.",
        "And the best part is, now I can do one more of a lot of things for you, automatically!||AUTOMATION? EXCELLENT! NOW YOU'RE TALKING MY LANGUAGE!",
    ])


func enqueue_tetrad_upgrade() -> void:
    if tetrad_upgrade_done:
        return
    tetrad_upgrade_done = true
    enqueue_dialogue([
        "Wait, [i]another[/i] Upgrade already, just for forming the first Tetrad? Sweet!||I HAVE TO AGREE. CLEARLY, I MADE A GOOD DECISION.",
        "Now I can automate three things at once!||HALF AGAIN AS FAST; I LIKE THAT. DO YOU THINK YOU'LL GET ANOTHER UPGRADE EACH FOR THE FIRST MOTES AND SO ON?",
        "It wouldn't surprise me!||GOOD. THIS JUST GOT A LOT LESS TEDIOUS THAN I FEARED.",
        "You and me both, Boss! Let's keep going!||YOU KNOW, I DO BELIEVE I'M ACTUALLY STARTING TO FEEL THE HYPE.",
    ])


func award_refinement(amount: int) -> void:
    refinements_completed += amount
    while refinements_completed >= refinements_per_level:
        refinements_completed -= refinements_per_level
        level += 1
        emit_signal("level_up", level)


func get_current_line() -> String:
    if current_index >= 0 and current_index < dialogue_queue.size():
        return dialogue_queue[current_index]
    return ""
