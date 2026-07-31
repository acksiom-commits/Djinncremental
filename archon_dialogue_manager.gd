extends Node

# ================== ARCHON DIALOGUE MANAGER v1.10.0 ==================
# v1.10.0: enqueue_study_panel_reveal() added — fires after the player's
#          first click on a constellation star in the main UI, revealing
#          ConstellationPanel's Study Constellation button. Placeholder
#          dialogue text, pending final narrative pass.
# v1.9.0: enqueue_tetrad_upgrade now emits sequence_complete("First Tetrad
#         Created") via dialogue_ended callback instead of immediately on
#         enqueue — prevents Volumition panel revealing at dialogue start.
# v1.8.0: Two bugfixes —
#         (1) _refresh_display: [reveal:...] tags now stripped from archon_text
#             unconditionally; signals still fire only on first show. Prevents
#             tag text appearing as literals after the player clicks "...".
#         (2) enqueue_dialogue: _notify_tween killed and notification state
#             reset on entry, preventing a finishing notification's deferred
#             _advance() callback from skipping or clearing the new dialogue.
# v1.7.0: [boss]...[/boss] inline tag added to _refresh_display.
# v1.6.0: enqueue_all_tetrads() added. _refresh_display() extended:
#         archon-side [reveal:...] tags now strip and fire ui_reveal_requested
#         when the line is first shown (not on player click). Player-side
#         reveals now support space-separated multi-key lists.
#         all_tetrads_done flag added.
# v1.5.0: enqueue_all_fundaments body replaced — previous content was an
#         accidental paste of enqueue_first_fundament's lines.
#         sequence_complete signal corrected from "First Fundament" to
#         "All Fundaments" to avoid duplicate Journal entries.
# v1.4.0  enqueue_first_volition renamed to enqueue_first_fundament.
#         Trigger moved to first Fundament Tetrad creation
# v1.3.0: _clear_dialogue() now sets both text and bbcode_text to ""
#         to ensure display clears regardless of RichTextLabel render
#         mode. Fade restored as separate auto-timer after clear:
#         after the last line is clicked away, a 5s timer starts and
#         fades the panel out if no new dialogue arrives.
# v1.2.0: Tutorial dialogue system, last-click-to-clear, pulse signals.
# v1.1.0: Removed award_refinement/ascendance system.
# v1.0.0: Fade-out on final dialogue line.
# v0.9.1: Supports null button (no ContinueButton needed).



const ARCHON_COLOR = "#aaddff"
var player_color: String = "#fff4dd"

var _label:  RichTextLabel = null
var _button: Button        = null

var dialogue_queue:   Array = []
var current_index:    int   = -1
var _showing_player:  bool  = false
var _has_player_half: bool  = false
var _tutorial_acknowledged: bool = false

var intro_done:                         bool = false
var second_monad_done:                  bool = false
var tetrad_upgrade_done:                bool = false
var all_monads_upgrade_done:            bool = false
var first_fundament_done:               bool = false
var first_non_fundament_done:           bool = false
var all_fundaments_done:                bool = false
var all_tetrads_done:                   bool = false
var first_particle_done:                bool = false
var first_grain_done:                   bool = false
var nineteenth_grain_done:              bool = false
var twentieth_grain_done:               bool = false
var first_prestige_done:                bool = false
var second_prestige_done:               bool = false
var third_prestige_done:                bool = false
var fourth_prestige_done:               bool = false
var fifth_prestige_done:                bool = false
var start_second_prestige_done:         bool = false
var archon_volition_constellation_done: bool = false
var no_archon_volition_constellation_done: bool = false
var spark_movement_done:                bool = false
var star_chase_done:                    bool = false
var tier1_archon_complete_done:         bool = false
var first_constellation_done:           bool = false
var constellation_panel_creation_done:  bool = false
var open_constellation_panel_done:      bool = false
var close_constellation_panel_done:     bool = false
var study_panel_reveal_done:            bool = false

var _name_entry_pending:     bool = false

var _fade_tween:       			Tween = null
var _fade_timer:       			float = 0.0
var _fade_countdown:   			bool  = false
var _tutorial_pending: 			bool  = false
var _tutorial_active:           bool  = false

var notification_queue: Array = []
var _notify_tween:     Tween = null
var _notify_timer:     float = 0.0
var _notify_countdown: bool  = false
var _in_notification:  bool  = false

var monad_panel_done: bool  = false
var monad_random_done: 			bool  = false



var _category_notified: Dictionary = {
    "fundament": false,
    "element":   false,
    "symmetric": false,
    "medial":    false,
}
var _all_tetrads_notified: bool = false

const FADE_DELAY:    float = 5.0
const FADE_DURATION: float = 1.5
const NOTIFY_DISPLAY_TIME:  float = 1.5
const NOTIFY_FADE_DURATION: float = 0.5

const CATEGORY_NOTIFY = "%s category complete: +1 Focus."
const ALL_TETRADS_NOTIFY = "All fifteen Tetrad varieties formed: +1 Focus."

signal expression_requested(expr_name: String, hold_duration: float)

signal dialogue_ended()
signal tutorial_dialogue_started()
signal tutorial_dialogue_cleared()
signal tutorial_dialogue_acknowledged()
signal monad_random_dialogue_ended()
signal second_monad_sequence_complete()

signal all_monads_sequence_complete()
signal first_particle_sequence_complete()
signal first_prestige_sequence_complete()
signal second_prestige_sequence_complete()
signal third_prestige_sequence_complete()
signal fourth_prestige_sequence_complete()
signal fifth_prestige_sequence_complete()
signal start_second_prestige_sequence_complete()
signal archon_volition_constellation_sequence_complete()
signal no_archon_volition_constellation_sequence_complete()
signal spark_movement_sequence_complete()
signal star_chase_sequence_complete()
signal tier1_archon_complete_sequence_complete()
signal uonite_name_requested()
signal first_constellation_sequence_complete()
signal constellation_panel_creation_sequence_complete()
signal open_constellation_panel_sequence_complete()
signal close_constellation_panel_sequence_complete()
signal study_panel_reveal_sequence_complete()

signal ui_reveal_requested(panel_key: String)
signal tetrad_category_complete(category_name: String)
signal all_tetrads_complete()
signal notification_shown(text: String)
signal sequence_complete(sequence_name: String, lines: Array)



# ==================================================
# SETUP
# ==================================================
func set_display_nodes(label: RichTextLabel, button: Button = null) -> void:
    _label  = label
    _button = button
    if _button and not _button.pressed.is_connected(_on_continue_pressed):
        _button.pressed.connect(_on_continue_pressed)
    _refresh_display()


# ==================================================
# PUBLIC INTERFACE
# ==================================================
func enqueue_dialogue(lines: Array, is_tutorial: bool = false) -> void:
    if _fade_tween:
        _fade_tween.kill()
        _fade_tween = null
    _fade_countdown = false
    _name_entry_pending = false
    _fade_timer     = 0.0
    # Kill any in-progress notification tween so its deferred _advance() callback
    # cannot fire after this dialogue starts — that would skip or clear line 1.
    if _notify_tween:
        _notify_tween.kill()
        _notify_tween = null
    _notify_countdown = false
    _notify_timer     = 0.0
    _in_notification  = false
    if _label:
        _label.modulate.a = 1.0

    if is_tutorial and not _tutorial_pending and not _tutorial_active:
        _tutorial_active  = true   # ← new guard; never cleared mid-sequence
        _tutorial_pending = true
        emit_signal("tutorial_dialogue_started")
    elif is_tutorial:
        _tutorial_pending = true   # re-arm pending for next clear, but no re-fire

    dialogue_queue += lines
    if current_index == -1:
        _advance()


func advance_dialogue() -> void:
    _on_continue_pressed()
    
    
func try_show_next_notification() -> void:
    if current_index == -1 and not _in_notification and dialogue_queue.is_empty():
        _advance()


# ==================================================
# INTERNAL — ADVANCE AND DISPLAY
# ==================================================
func _on_continue_pressed() -> void:
    if current_index < 0:
        return
    if _tutorial_pending and not _tutorial_acknowledged:
        _tutorial_acknowledged = true
        emit_signal("tutorial_dialogue_acknowledged")
    if _has_player_half and not _showing_player:
        _showing_player = true
        _refresh_display()
        return
    if _name_entry_pending:
        _name_entry_pending = false
        emit_signal("uonite_name_requested")
        return
    _advance()


func _advance() -> void:
    if not dialogue_queue.is_empty():
        current_index += 1
        if current_index >= dialogue_queue.size():
            current_index = dialogue_queue.size() - 1
            _clear_dialogue()
            return
        var entry: String = dialogue_queue[current_index]

        # --- Expression tag parsing ---
        var expr_regex := RegEx.new()
        expr_regex.compile("^\\[expr:([a-z_]+)(?:,([\\.0-9]+))?\\]")
        var m := expr_regex.search(entry)
        if m:
            var expr_name: String = m.get_string(1)
            var hold_dur: float = float(m.get_string(2)) if m.get_string(2) != "" else 1.2
            emit_signal("expression_requested", expr_name, hold_dur)
            entry = entry.substr(m.get_end())
            dialogue_queue[current_index] = entry
        # --- Name entry tag: set flag, fall through to normal dialogue flow ---
        if "[name_entry]" in entry:
            entry = entry.replace("[name_entry]", "")
            dialogue_queue[current_index] = entry
            _name_entry_pending = true


        _has_player_half  = "||" in entry
        _showing_player   = false
        _in_notification  = false
        _refresh_display()
        return
    if not notification_queue.is_empty():
        var entry: String = notification_queue.pop_front()
        _in_notification  = true
        if _label:
            _label.modulate.a = 1.0
            _label.set("bbcode_text", "[color=%s]%s[/color]" % [ARCHON_COLOR, entry])
            emit_signal("notification_shown", entry)
        if _button:
            _button.visible = false
        _notify_timer     = 0.0
        _notify_countdown = true
        return
    _clear_dialogue()
    
func _on_monad_random_ended() -> void:
    dialogue_ended.disconnect(_on_monad_random_ended)
    emit_signal("monad_random_dialogue_ended")
    
    
func _on_second_monad_ended() -> void:
    dialogue_ended.disconnect(_on_second_monad_ended)
    emit_signal("second_monad_sequence_complete")
    
    
func _on_all_monads_ended() -> void:
    dialogue_ended.disconnect(_on_all_monads_ended)
    emit_signal("all_monads_sequence_complete")
    
    
func _on_tetrad_upgrade_ended() -> void:
    dialogue_ended.disconnect(_on_tetrad_upgrade_ended)
    emit_signal("sequence_complete", "First Tetrad Created", [])


func _on_first_particle_ended() -> void:
    dialogue_ended.disconnect(_on_first_particle_ended)
    emit_signal("first_particle_sequence_complete")
    
    
func _on_first_prestige_ended() -> void:
    dialogue_ended.disconnect(_on_first_prestige_ended)
    emit_signal("first_prestige_sequence_complete")

    
func _on_second_prestige_ended() -> void:
    dialogue_ended.disconnect(_on_second_prestige_ended)
    emit_signal("second_prestige_sequence_complete")


func _on_third_prestige_ended() -> void:
    dialogue_ended.disconnect(_on_third_prestige_ended)
    emit_signal("third_prestige_sequence_complete")


func _on_fourth_prestige_ended() -> void:
    dialogue_ended.disconnect(_on_fourth_prestige_ended)
    emit_signal("fourth_prestige_sequence_complete")

func _on_fifth_prestige_ended() -> void:
    dialogue_ended.disconnect(_on_fifth_prestige_ended)
    emit_signal("fifth_prestige_sequence_complete")


func _on_start_second_prestige_ended() -> void:
    dialogue_ended.disconnect(_on_start_second_prestige_ended)
    emit_signal("start_second_prestige_sequence_complete")


func _on_spark_movement_ended() -> void:
    dialogue_ended.disconnect(_on_spark_movement_ended)
    emit_signal("spark_movement_sequence_complete")
    
    
func _on_star_chase_ended() -> void:
    dialogue_ended.disconnect(_on_star_chase_ended)
    emit_signal("star_chase_sequence_complete")


func _on_tier1_archon_complete_ended() -> void:
    dialogue_ended.disconnect(_on_tier1_archon_complete_ended)
    emit_signal("tier1_archon_complete_sequence_complete")


func _on_study_panel_reveal_ended() -> void:
    dialogue_ended.disconnect(_on_study_panel_reveal_ended)
    emit_signal("study_panel_reveal_sequence_complete")

    
func _on_first_constellation_ended() -> void:
    dialogue_ended.disconnect(_on_first_constellation_ended)
    emit_signal("first_constellation_sequence_complete")

    
func _on_constellation_panel_creation_ended() -> void:
    dialogue_ended.disconnect(_on_constellation_panel_creation_ended)
    emit_signal("constellation_panel_creation_sequence_complete")
    
    
func _on_open_constellation_panel_ended() -> void:
    dialogue_ended.disconnect(_on_open_constellation_panel_ended)
    emit_signal("open_constellation_panel_sequence_complete")
    
    
func _on_close_constellation_panel_ended() -> void:
    dialogue_ended.disconnect(_on_close_constellation_panel_ended)
    emit_signal("close_constellation_panel_sequence_complete")


func _on_archon_volition_constellation_ended() -> void:
    dialogue_ended.disconnect(_on_archon_volition_constellation_ended)
    emit_signal("archon_volition_constellation_sequence_complete")


func _on_no_archon_volition_constellation_ended() -> void:
    dialogue_ended.disconnect(_on_no_archon_volition_constellation_ended)
    emit_signal("no_archon_volition_constellation_sequence_complete")
    
    
func notify_tetrad_created(variety_key: String, triggered_dict: Dictionary) -> void:
    notification_queue.append("%s Tetrad: +1 Focus." % variety_key.capitalize())

    var category_map = {
        "fundament": ["adaemant", "aquae", "aethyr"],
        "element":   ["earth", "water", "air"],
        "symmetric": ["mud", "dust", "cloud"],
        "medial":    ["dirt", "sand", "haze", "mist", "ooze", "foam"],
    }
    for cat in category_map:
        if _category_notified[cat]:
            continue
        var all_done = true
        for v in category_map[cat]:
            if not triggered_dict.get(v, false):
                all_done = false
                break
        if all_done:
            _category_notified[cat] = true
            notification_queue.append(CATEGORY_NOTIFY % cat.capitalize())
            emit_signal("tetrad_category_complete", cat)

    if not _all_tetrads_notified:
        var all_done = true
        for v in triggered_dict:
            if not triggered_dict[v]:
                all_done = false
                break
        if all_done:
            _all_tetrads_notified = true
            notification_queue.append(ALL_TETRADS_NOTIFY)
            emit_signal("all_tetrads_complete")

    if current_index == -1 and not _in_notification and dialogue_queue.is_empty():
        _advance()


func _clear_dialogue() -> void:
    current_index          = -1
    _showing_player        = false
    _has_player_half       = false
    _tutorial_acknowledged = false
    _name_entry_pending = false
    dialogue_queue.clear()
    if _label:
        _label.set("bbcode_text", "")
        _label.text = ""
    if _button:
        _button.visible = false
    if _tutorial_pending:
        _tutorial_pending = false
        emit_signal("tutorial_dialogue_cleared")
    else:
        _tutorial_active = false
    emit_signal("dialogue_ended")


func _refresh_display() -> void:
    if not _label:
        return
    if current_index < 0 or dialogue_queue.is_empty():
        _label.set("bbcode_text", "")
        if _button:
            _button.visible = false
        return

    var entry: String       = dialogue_queue[current_index]
    var archon_text: String = entry
    var player_text: String = ""

    if "||" in entry:
        var parts = entry.split("||", true, 1)
        archon_text = parts[0]
        player_text = parts[1] if parts.size() > 1 else ""
    
    # ── [uonite_name] substitution ──
    var gc := get_node_or_null("/root/GameContext")
    var resolved_name: String = gc.uonite_name if gc and gc.uonite_name != "" else "???"
    archon_text = archon_text.replace("[uonite_name]", resolved_name)
    player_text  = player_text.replace("[uonite_name]", resolved_name)

    # ── Archon-side reveals: always strip tags from display text; fire signals
    #    only when archon text is first shown (not again when player side opens).
    var arv_re := RegEx.new()
    arv_re.compile("\\[reveal:([a-z_][a-z_ ]*)\\]")
    if not _showing_player:
        for m in arv_re.search_all(archon_text):
            for key in m.get_string(1).split(" ", false):
                emit_signal("ui_reveal_requested", key)
    archon_text = arv_re.sub(archon_text, "", true)

    # ── [boss]...[/boss] inline tag: renders the Boss's voice in player_color
    #    mid-archon-text, letting a full exchange fit in one dialogue window.
    archon_text = archon_text \
        .replace("[boss]",  "[color=%s]" % player_color) \
        .replace("[/boss]", "[/color]")

    var bbcode = "[color=%s]%s[/color]" % [ARCHON_COLOR, archon_text]
    if _showing_player and player_text != "":
        # ── Player-side reveals: multi-key [reveal:key1 key2 ...] anchored at line start
        var prv_re := RegEx.new()
        prv_re.compile("^\\[reveal:([a-z_][a-z_ ]*)\\]")
        var pm := prv_re.search(player_text)
        if pm:
            for key in pm.get_string(1).split(" ", false):
                emit_signal("ui_reveal_requested", key)
            player_text = player_text.substr(pm.get_end())
        bbcode += "\n\n[color=%s]%s[/color]" % [player_color, player_text]

    _label.set("bbcode_text", bbcode)
    _label.scroll_to_line(_label.get_line_count() - 1)

    # Auto-advance non-tutorial single lines
    if not _tutorial_pending and not _tutorial_active and not _has_player_half:
        _fade_timer    = 0.0
        _fade_countdown = true
        if _button:
            _button.visible = false

    if _button:
        _button.visible = true
        _button.text    = "..." if (_has_player_half and not _showing_player) else "Continue"


# ==================================================
# PROCESS — auto-fade countdown after dialogue ends
# ==================================================
func _process(delta: float) -> void:
    if not _label:
        return
    if _notify_countdown:
        _notify_timer += delta
        if _notify_timer >= NOTIFY_DISPLAY_TIME:
            _notify_countdown = false
            if _notify_tween:
                _notify_tween.kill()
            _notify_tween = create_tween()
            _notify_tween.tween_property(_label, "modulate:a", 0.0, NOTIFY_FADE_DURATION) \
                .set_trans(Tween.TRANS_SINE) \
                .set_ease(Tween.EASE_IN)
            _notify_tween.tween_callback(func():
                _in_notification = false
                if _label: _label.modulate.a = 1.0
                _advance()
            )
        return
    if _fade_countdown:
        _fade_timer += delta
        if _fade_timer >= FADE_DELAY:
            _fade_countdown = false
            _start_fade()


func _start_fade() -> void:
    if not _label:
        return
    if _fade_tween:
        _fade_tween.kill()
    _fade_tween = create_tween()
    _fade_tween.tween_property(_label, "modulate:a", 0.0, FADE_DURATION) \
        .set_trans(Tween.TRANS_SINE) \
        .set_ease(Tween.EASE_IN)


# ==================================================
# DIALOGUES
# ==================================================
func start_intro() -> void:
    if intro_done:
        return
    intro_done = true
    var lines = [
        "Hiya Boss! Ready to get started?||WHO, ME? WAIT, START WHAT?",
        "Get started building your own...oh. \n\nThey didn't highlight that.||HIGHLIGHT WHAT NOW? WAIT, BUILD WHAT, TOO?",
        "That you took the Amnesia forfeit after completing your Lessons, Boss. \n\nSorry I didn't realize right away...[font_size=14]even though it's not my fault[/font_size]...anyways, you decided not to remember all the personal stuff about your, er, Training time...?||AND THE BUILDING PART?",
        "Well, now you get a private dimension to build your own world in, basically from nothing. And I'm your assigned Archon assistant, Kaleb. Tutor and mentor now, too, I guess. \n\nSummon five Sparks and I'll start showing you the basics.||WAIT. FIRST, WHAT ARE THESE 'SPARKS'?.",
        "Sparks are the ultimate quanta of reality, Boss - indivisible, unitary essences of identity and free will. Nothing material [i]can[/i] exist without that attached to it.||I SEE. \n\nWELL, BUILDING MY OWN WORLD DOES SOUND APPEALING. . .I'LL TRY IT.",
        "That's the spirit! Let's make something great together!||ALL RIGHT, DIAL BACK THE ENTHUSIASM THERE A LITTLE, PLEASE.",
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Introduction", lines)

func enqueue_monad_panel_dialogue() -> void:
    if monad_panel_done:
        return
    monad_panel_done = true
    var lines = [
        "Okay, five Sparks summoned...\n\n...that'll do...I suppose...\n\n...if it has to....||HAR. HAR. HAR. \n\nI SAID 'A LITTLE', KALEB, NOT 'GO FULL EMO'.",
        "Just calibrating! Honest! I totally wasn't engaging in, um...facetious compliance. Really, I swear. \n\nI'll dial it back up a few notches.||SURE. \n\nI CAN PRACTICALLY HEAR YOU SMIRKING, YOU KNOW.",
        "I'm certain I haven't the faintest idea what you mean. \n\nAnyways, now that we've got at least five Sparks, we can create your first Monad - the smallest form of physical matter in your new dimension. Exciting! A milestone!||HRM. ALL RIGHT, I CAN'T ARGUE WITH THAT. IT DOES SEEM SIGNIFICANT.",
        "Finish this conversation and press that Monad button and we'll enter a new era!||WHY CAN'T I JUST PRESS IT NOW?",
        "Because I can either talk directly to you or run the interface for you, Boss; I can't do both. Yet. I'll get there eventually; I'll grow in capability as your new dimension does.||FAIR ENOUGH. HERE WE GO.",
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Kaleb Introduces Himself", lines)

func enqueue_monad_random_dialogue(first_type: String) -> void:
    if monad_random_done:
        return
    monad_random_done = true
    if not dialogue_ended.is_connected(_on_monad_random_ended):
        dialogue_ended.connect(_on_monad_random_ended)
    var all_types = ["Solid", "Liquid", "Gas"]
    var type_display = first_type.capitalize()
    var others = all_types.filter(func(t): return t != type_display)
    var line1 = "There we go! Your first Monad. I'd call it cute...if it wasn't too tiny to see. \n\nUhh...anyways! This one's a %s type - the others are %s and %s. But there's something more important than that, some really good news!||AND WHAT WOULD THAT BE?" % [type_display, others[0], others[1]]
    var lines = [
        line1,
        "You got me a Refinement by forming that first Monad!||WHOA, I DID WHAT NOW?",
        "Qualified me for a Focus increase! See the Foci Counter in the display over to the left? It's not usual for that to happen this soon, either. That's why I think you get the credit for it.||WHAT, JUST BY FORMING A MONAD?",
        "The most likely case is that you selected some kind of 'Faster Archon Upgrades' advantage while customizing your new pocket dimension.||OH? I SUPPOSE THAT DOES MAKE SENSE.",
        "Yes, but...I'm not saying it's exactly one-for-one across here, but Amnesia is usually taken as part of a trade-off for something preferred, so...thank you. Sincerely.||WELL, IF THAT'S THE CASE, YOU'RE CERTAINLY WELCOME.",
        "And the best part is, now I can do one more of a lot of things for you, automatically!||AUTOMATION? EXCELLENT! NOW YOU'RE TALKING MY LANGUAGE!",
        "In that case, I'll bring up the Allocation Wheel right away, too! And then you can assign my Foci to Summoning more Sparks, and later, creating more Production Resources!||AH - NOW I'M STARTING TO SEE THE BENEFITS OF YOUR POSITIVE ATTITUDE.",
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "First Monad Created", lines)

func enqueue_second_monad() -> void:
    if second_monad_done:
        return
    second_monad_done = true
    if not dialogue_ended.is_connected(_on_second_monad_ended):
        dialogue_ended.connect(_on_second_monad_ended)
    var lines = [
        "What the - [i]another[/i] Refinement? Did you pick one Refinement and Focus [i]per Monad type?[/i] Per [i]resource[/i] type!? Madness! I mean, I love it, it's great for me, but - wow, you really went all in on improving me.||APPARENTLY I DID. I MUST HAVE THOUGHT IT WOULD PAY OFF.",
        "Oh, it will, I promise you. You might even have sped up my Ascension rate - seriously, at this point I'd be more surprised if you didn't.||AND ASCENSIONS MEAN WHAT FOR US?",
        "They mean faster acquisition of Volitions for me - which increases my ability to do more complicated tasks, like locking resource production, and changing Uonite allocation around, and augmenting your manual Production.||HUH. I THINK IT'S TIME YOU EXPLAINED THESE TERMS. PAST TIME, EVEN.",
        "Right! So, a Volition is an increase in my ability to take more complex actions. You can assign both Foci and Volitions one-for-one to automatically Summon Sparks and produce resources like Monads, and assembling those into Tetrads, and compressing those into Particles, and so on for Iotas, Motes, and Grains.||THAT SOUNDS LIKE A LONG PRODUCTION CHAIN.",
        "Well, we [i]are[/i] starting almost literally from nothing here, Boss. But it's not as bad as it sounds, because we can eventually use Grains to create Uonites, which are the smallest form of active intelligence that can be used for automation.||AHA - AND THEN THEY'LL TAKE OVER MORE OF THE PRODUCTION LOAD FOR US, SO WE CAN FOCUS ON BUILDING MY WORLD.",
        "Yep, that's the plan! [i]And[/i] I can use my Volitions to duplicate most of your actions, one-for-one! So assign those new Foci, and let's find out just how much you invested in my improvement - how about you keep making Monads until we have one of each type, and I'll bring up the Tetrad panel?||AGREED - WE SHOULD CHECK THAT NEXT.",
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Second Monad Type", lines)

func enqueue_all_monads_upgrade() -> void:
    if all_monads_upgrade_done:
        return
    all_monads_upgrade_done = true
    if not dialogue_ended.is_connected(_on_all_monads_ended):
        dialogue_ended.connect(_on_all_monads_ended)
    var lines = [
        "One more refinement for the last Monad type AND another Refinement for one each of all three? Wow, you really went all in on upgrading me!||IT SEEMS I DID. GOOD JOB, FORMER SELF.",
        "At this point I'm pretty sure I'll get another for completing each Tetrad Category as well as all Tetrads.||ANOTHER...TWENTY FOCI? EXCELLENT. AT THIS RATE, I'LL BE ABLE TO JUST KICK BACK AND LET YOU DO [i]ALL[/i] THE WORK.",
        "Yeah! That would be. . .hey now, wait a minute! That's not right!||IT WOULD FEEL RIGHT TO ME.",
        "Are you teasing me? You better be teasing me! I'm not getting paid for this, you know - I'm an Intern Archon, I'm here for the work experi. . .oh. \n\nOh no.||DO YOU SEE ME OVER HERE NOT BEING SMUG? \n\nBECAUSE THIS IS ME OVER HERE NOT BEING SMUG.",
        "[expr:spock_right,3.0]Yes, I definitely wouldn't call your behavior...'smug.' \n\nI might call it something [i]else[/i], but no, not 'smug'.||UH...HUH. \n\nNOTE TO SELF: CHECK LATER WHETHER I TOOK A 'SASSYPANTS ARCHON' FORFEIT TOO.",
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "All Monad Types", lines)

func enqueue_tetrad_upgrade(variety_key: String = "") -> void:
    if tetrad_upgrade_done:
        return
    tetrad_upgrade_done = true
    var variety_display = variety_key.capitalize() if variety_key != "" else "first"
    var lines = [
        "Wait, [i]another[/i] Refinement [i]AND[/i] my first Ascension, already? Just for forming the first %s Tetrad? Sweet!||I HAVE TO AGREE. CLEARLY, I MADE A GOOD DECISION." % variety_display,
        "Or...the Ascension could be for achieving five Refinements...hmm, yes, that makes more sense. I'll bet it's that instead. And if you [i]really[/i] piled on the upgrades for me, the next one should come at twenty-five Refinements, then a hundred and twenty-five, and so on.||EXPONENTIAL POWERS OF FIVE? I THINK I'M SEEING A PATTERN HERE. WHAT ABOUT REFINEMENT MILESTONES, THEN?",
        "Oh, those are almost certainly slower. Well, relatively slower - we're going to make a [i]lot[/i] resources, after all. \n\nLike, a [i]lot[/i] of a lot. Soo...maybe by powers of one hundred, per resource?||GOOD. THIS JUST GOT A LOT LESS TEDIOUS THAN I FEARED.",
        "You and me both, Boss! Let's keep going!||YOU KNOW, I DO BELIEVE I'M ACTUALLY STARTING TO FEEL THE HYPE.",
        "Then how about we use the Lock function to assemble one each of the Fundament Tetrads next?||THE WHAT? OH, RIGHT; YOU MENTIONED THAT EARLIER - 'LOCKING RESOURCE PRODUCTION'.",
        "Yes, that! We can stockpile and filter resources with it. Just tap on one of the Monad types and my Volition will be assigned to lock those out of Tetrad assembly. Then you can keep assembling Tetrads with the other two types until you have four or more of the locked type and none of the others, unlock that first type again, and make a Fundament Tetrad from them.||OR, IF I HAVE THOSE FOUR OR MORE AND ONLY SOME OF ONE OTHER, I CAN JUST LOCK THOSE OTHERS OUT INSTEAD OF USING THEM.",
        "Good thinking, Boss! Let's do it!||NOT QUITE YET, KALEB; THERE'S ONE MORE THING. WHAT'S THAT NEW 'VOLUMITIONS' OPTION UNDER THE READOUTS TO THE LEFT?",
        "Heh...right. Sorry about that - I'll try to not get so distracted. Remember when I told you I can use my Volitions to duplicate your actions? That's the selector and counter for that. Every Volition you assign to it increases your Summon, Compression, Assembly, and Creation actions by one.||AND THEREFORE YOU CALL THEM...'VOLUMITIONS'. \n\nEH, GOOD ENOUGH.",
        "Gosh, thank you so much, Boss! I'm so glad you like it!||YOUR SARCASM FILLS ME WITH PRIDE. LET'S GET BACK TO WORK.",
    ]
    if not dialogue_ended.is_connected(_on_tetrad_upgrade_ended):
        dialogue_ended.connect(_on_tetrad_upgrade_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "First Tetrad Created", lines)

func enqueue_first_fundament(variety_key: String = "") -> void:
    if first_fundament_done:
        return
    first_fundament_done = true
    var variety_display = variety_key.capitalize() if variety_key != "" else "Fundament"
    var lines = [
        "And there it is, your first %s Tetrad. \n\nPity it's going to be consumed along with everything else when we Expand the dimension.||WHAT? WHY?" % variety_display,
        "Oh, sorry; I hadn't gotten to explaining that yet. Yes, we need to collapse the dimension in order to create Uonites. But then we just Expand it again, only bigger. How much bigger depends on how many Sparks we had left when we collapsed it. Right now, we can only store just under a thousand made resources. Here, let me bring up the Stoctagon.||[reveal:stoctagon]THE WHAT NOW? OH. HEH. THAT'S ALMOST CLEVER.",
        "[i]Almost?[/i] Ehhh...fine, I'll take it. Anyway, that's where we store our Primordial resources, and it's another use for Volitions. I can assign them to watch over the Stoctagon and trigger the production of higher-tier resources when it's full. Otherwise, the chain just shuts down.||AND BY 'THEM' YOU MEAN THEY ONLY WORK ONE-FOR-ONE THERE TOO, DON'T YOU.",
        "You catch on quick! Yes, two Volitions assigned to the Stoctagon, two resources made at a time, and so on. Except Uonites, of course - the more Expansions we've done, the more of those we'll be able to create at once. But you probably upgraded that as well.||YES, I PROBABLY DID. I CAN SEE WHERE THIS IS GOING - WE'RE [i]NEVER[/i] GOING TO HAVE ENOUGH VOLITIONS, ARE WE?",
        "Likely not, but there are ways around that limit. For example, later on we'll be able to upgrade sufficiently experienced Uonites, and they'll be able to stand in as replacements for Foci and Volitions.||THAT'S GOOD. NOW TELL ME ABOUT THESE TETRAD CATEGORIES.",
        "Uh...they're not actually important yet. But they will be! A certain percentage of Fundaments in higher-tier resources will prevent them from being consumed when we Expand, for example.||I'LL TAKE YOUR WORD FOR IT. BUT RIGHT NOW, IT'S JUST GOOD FOR TRICKLE PRODUCTION WHEN THE STORAGE IS FULL?",
        "[i]And[/i] swapping Uonites around...when we. Um. Finally have some. Yes. But later, when we have Tools, and Appliances, and so on, I'll be able to use and operate them myself! And oversee tetrad production to achieve specific material goals. And things like that.||AH, THAT IS VERY GOOD, THEN. THERE'S NO USE IN IMPROVING YOU AND NOT TAKING ADVANTAGE OF IT, AFTER ALL.",
        "... \n\nYou really are utterly shameless, aren't you.",
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "First Fundament", lines)
    
    
func enqueue_first_non_fundament(variety_key: String = "") -> void:
    if first_non_fundament_done:
        return
    first_non_fundament_done = true
    var variety_display = variety_key.capitalize() if variety_key != "" else "Tetrad"
    var lines = [
        "Orrr you could complete the %s Category first instead of the Fundaments? \n\nWhich is fine! I don't judge.||YES. I'M A REBEL BORN AND RAISED. BEAR WITNESS TO THE GLORY OF MY CONTRARIAN INDEPENDENCE." % variety_display,
        "O...kay? Well, the important part is finding out that yes, I'm probably getting a Focus for each Category we complete, too.||GOOD. WHAT'S NEXT?",
        "Let's make at least one of each Tetrad variety to get to twenty-four Refinements, and I'll unlock the rest of the Production Resources so we can find out if my Ascensions come at powers of five or not.||AND THEN WE CAN GRIND OUR WAY OUT TO ONE HUNDRED OF A MONAD TYPE TO CHECK THE REFINEMENTS MILESTONE.",
        "Yes, and then to ten thousand of a type, which would be...times three, carry the one...about 13 Grains. So that'll happen well before creating our first Uonite, which takes twenty Grains. [i]And[/i] it will expand the Stoctagon a little, depending on how many Sparks we've accumulated at that moment.||TO BE CLEAR: YOU MEAN NOT ALL SPARKS OVER TIME, BUT JUST THE ONES WE HAVE RIGHT THEN?",
        "Correct. All the Phlogiston of the Sparks that is locked up in the material resources consumed is used to create the Uonite. A fraction of the Sparks still floating around accelerate the Expansion process, making this dimension a little bigger.||AND WHAT HAPPENS TO THE OTHER SPARKS?",
        "Oh, they go off to be useful somewhere else - not back into the Void, if that's your concern. The Upper Management handles that for us - they have to get [i]some[/i] benefit out of all this, after all.||SO IT'S LITERALLY A LABOR TAX. WONDERFUL. \n\nOH WELL. AT LEAST IT'S BETTER THAN JUST DUMPING THEM BACK INTO THE ABYSS.",
        "Aw, you [i]do[/i] care! I knew you had a heart of g...go...gol...of something other than cold black iron, under that grumpy exterior.||... \n\nI CAN'T REPLACE YOU WITH A NEW ARCHON, CAN I.",
        "Nope, we're stuck with each other! Until you move on to another project, that is. New project, new Archon. And I'll get assigned a new position. And, uh, hopefully a promotion.||OH? TO WHAT? DO YOU HAVE CAREER PLANS?",
        "No actual plans; I'm still finding out where I fit best. I could go over to the security side and shoot for Subaltern Archon, or I could build on the Production experience I'm gaining here and grow into a Stockturn Archon.||UH...HUH. \n\nWHY DO I GET THE FEELING THERE'S A JOKE I'M MISSING HERE?",
        "Gosh, I have no idea. I can't imagine why. \n\nAnyways, on to completing the creation of all Tetrad varieties at least once!||HRRMGH. \n\nFINE.",
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", variety_key.capitalize() + " Category", lines)

    
func enqueue_all_fundaments() -> void:
    if all_fundaments_done:
        return
    all_fundaments_done = true
    var lines = [
        "Yes! One of all Fundaments made equals bonus Focus! Let's make at least one of each Tetrad variety to get to twenty-four Refinements, and I'll unlock the rest of the Production Resources so we can find out if my Ascensions come at powers of five or not.||AND THEN WE CAN GRIND OUR WAY OUT TO ONE HUNDRED OF A MONAD TYPE TO CHECK THE REFINEMENTS MILESTONE.",
        "Yes, and then to ten thousand of a type, which would be...times three, carry the one...about 13 Grains. So that'll happen well before creating our first Uonite, which takes twenty Grains. [i]And[/i] it will expand the Stoctagon a little, depending on how many Sparks we've accumulated at that moment.||TO BE CLEAR: YOU MEAN NOT ALL SPARKS OVER TIME, BUT JUST THE ONES WE HAVE RIGHT THEN?",
        "Correct. All the Phlogiston of the Sparks that is locked up in the material resources consumed is used to create the Uonite. A fraction of the Sparks still floating around accelerate the Expansion process, making this dimension a little bigger.||AND WHAT HAPPENS TO THE OTHER SPARKS?",
        "Oh, they go off to be useful somewhere else - not back into the Void, if that's your concern. The Upper Management handles that for us - they have to get [i]some[/i] benefit out of all this, after all.||SO IT'S LITERALLY A LABOR TAX. WONDERFUL. \n\nOH WELL. AT LEAST IT'S BETTER THAN JUST DUMPING THEM BACK INTO THE ABYSS.",
        "Aw, you [i]do[/i] care! I knew you had a heart of g...go...gol...of something other than cold black iron, under that grumpy exterior.||... \n\nI CAN'T REPLACE YOU WITH A NEW ARCHON, CAN I.",
        "Nope, we're stuck with each other! Until you move on to another project, that is. New project, new Archon. And I'll get assigned a new position. And, uh, hopefully a promotion.||OH? TO WHAT? DO YOU HAVE CAREER PLANS?",
        "No actual plans; I'm still finding out where I fit best. I could go over to the security side and shoot for Subaltern Archon, or I could build on the Production experience I'm gaining here and grow into a Stockturn Archon.||UH...HUH. \n\nWHY DO I GET THE FEELING THERE'S A JOKE I'M MISSING HERE?",
        "Gosh, I have no idea. I can't imagine why. \n\nAnyways, on to completing the creation of all Tetrad varieties at least once!||HRRMGH. \n\nFINE.",
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "All Fundaments", lines)


func enqueue_all_tetrads() -> void:
    if all_tetrads_done:
        return
    all_tetrads_done = true
    # Line 1 of the original text had four ||splits; split into two entries
    # so the system's single-split parser handles each exchange correctly.
    var lines = [
        "All Tetrad varieties assembled! \n\nHere we go, Marster! The Moment of Truth!\n\nThe Juncture of Criticality!||KALEB....",
        "The Apex of Procedural Inevitability!||KALEB!",
        "[font_size=14][i]Egor knows not this 'Kaleb', Marster[/i][/font_size] \n\nThe Terminal Threshold of Non-Reversibility! \n\nThe Definitive Ultimate Convergence of All Teleological Vectors!||OH, FOR THE LOVE OF MARTY FELDMAN...EGOR, JUST [i]PULL THE BLASTED SWITCH ALREADY![/i]",
        "Yesh, Marster![reveal:particle]\n\nTap it! Tap it! Hurry!||... \n\nYOU'RE LUCKY I'M SO CURIOUS MYSELF.",
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "All Tetrads", lines)
    
func enqueue_first_particle() -> void:
    if first_particle_done:
        return
    first_particle_done = true
    var lines = [
        "[i]YESSS![/i] Two Volitions! I'm getting Ascendancies at every [i]power-of-five Refinements![/i] \n\nThank you [i]so much,[/i] Boss!||HUZZAH. WHOOPEE. \n\nNOW GET BACK TO GRINDING.",
        "Right away, Boss! Here, I'll bring up the rest of the Production Chain, and the Generation Bars, so you can keep track of the Chain's resource flow at a glance.||THAT'LL DO, ARCHON. THAT'LL DO. \n\nLET'S GET TO WORK.",
    ]
    if not dialogue_ended.is_connected(_on_first_particle_ended):
        dialogue_ended.connect(_on_first_particle_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "First Particle", lines)
    

func enqueue_first_grain() -> void:
    if first_grain_done:
        return
    first_grain_done = true
    var lines = [
        "Our first Grain! We're over the threshold - just nineteen more and we can Expand!||TWENTY GRAINS PER EXPANSION? WHAT IF WE HAVE MORE?",
        "No, twenty per Uonite - and right now, just one Uonite per Expansion. So any extra Grains would just be consumed, this time. But the more Expansions we've done, the more Uonites we can Create each Expansion. And if you have enough Sparks stocked up beforehand, the Stoctagon gets bigger afterwards, too! ||THAT MAKES SENSE. YOU DID SAY WE'RE GOING TO BE MAKING A [i]LOT[/i] OF RESOURCES, EVENTUALLY.",
        "We sure are! We've got a whole world to build here!||AND FLOATING AROUND IN SPACE CHATTING ISN'T GOING TO GET IT DONE FOR US, SO LET'S GET BACK TO PUTTING IN THE WORK."
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "First Grain", lines)


func enqueue_nineteenth_grain() -> void:
    if nineteenth_grain_done:
        return
    nineteenth_grain_done = true
    var lines = [
        "Almost there, Boss! Just one more Grain to go - our first Expansion, our first Uonite! I'm so excited! Aren't you excited? Come on, be excited!||HMM...I'LL SETTLE FOR BEING AMUSED, I THINK.",
        "Ugh, fine. I guess that's the best I can expect...||I HEARD THAT UNSPOKEN 'FROM YOU', KALEB. \n\nWELL, THAT'S ALL RIGHT, THOUGH. YOU CAN BE EXCITED ENOUGH FOR BOTH OF US.",
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Nineteenth Grain", lines)


func enqueue_twentieth_grain() -> void:
    if twentieth_grain_done:
        return
    twentieth_grain_done = true
    var lines = [
        "Twenty Grains stocked, Boss! It's time for our first Expansion!||THAT WAS A LOT OF PRODUCTION FOR JUST ONE UONITE.",
        "Ugh, no kidding. [font_size=14]And I did most of it, too.[/font_size] \n\nBut look on the bright side! Things will start moving faster soon. And I'll probably get another Focus each for the first Uonite and Expansion.||TRUE ENOUGH, AND IT WOULDN'T SUPRISE ME EITHER.",
        "Then let's GOOOOOOO!||I'LL ADMIT IT, I'M LOOKING FORWARD TO THIS. OH, AND KALEB?",
        "Yes, Boss?||GOOD WORK. SEE YOU ON THE FLIPSIDE, PARTNER.",
        "[font_size=14]...wait...what?[/font_size]",
    ]
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Twentieth Grain", lines)


func enqueue_first_prestige() -> void:
    if first_prestige_done:
        return
    first_prestige_done = true
    var lines = [
        "Aaaaand we're back! Everything all right, Boss? You didn't get anything pinched off anywhere?||WHAT? NO, I DIDN'T GET ANYTHING PINCH- WAIT, THAT CAN HAPPEN!?",
        "Mmmmaybe? I mean, it [i]is[/i] an infinitely big cosmos...anyways, never mind that; look! Our first Uonite! I'm so proud! \n\n...[i]sniff[/i]... \n\nIt's a great achievement, it's wonderful.||IT'S MORE HELP. PUT IT TO WORK.",
        "Hey, there's more to life than labor, you know! Can't you take a moment to just enjoy this? It's our first minion! We have a minion!||I AM ENJOYING IT. I'LL ENJOY IT EVEN MORE WHEN IT'S DOING SOMETHING PRODUCTIVE.",
        "Goodness me. Can't we...I don't know...oh! Wait! Can I name it! Let me name it! We'll call it...'Kevin'!||NO.",
        "How about 'Bob'?||EVEN MORE 'NO'.",
        "'Stuart'?||ARE YOU [i]TRYING[/i] TO GET US SUED?",
        "Of course not! I categorically refuse and deny any such slanderous accusations with the strongest of emphasis!||GOOD.",
        "... \n\n'Otto'?||CLEVER, BUT STILL NO. HE'S ONE OF THEM TOO.",
        "Well, drat.||HMMM. \n\nALL RIGHT, 'DRAT' IS ACCEPTABLE.",
        "Absolutely not! We're not naming our first minion 'Drat'! That's just cruel.||NO, THAT WAS JUST A JOKE, KALEB. GIVE ME A MINUTE, I'LL PICK SOMETHING BETTER.[name_entry]",
        "Ehhh...good enough. Welcome to the business, [uonite_name]!||YES, WELCOME ABOARD. \n\nNOW LET'S GET YOU TO WORK.",
        "Aaaaand we're right back to the usual old Boss again.",
    ]
    if not dialogue_ended.is_connected(_on_first_prestige_ended):
        dialogue_ended.connect(_on_first_prestige_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "First Prestige", lines)
    

func enqueue_spark_movement() -> void:
    if spark_movement_done:
        return
    spark_movement_done = true
    var lines = [
        "Hey Boss? Have you noticed anything odd about how the Sparks are moving?||ODD HOW?",
        "Some of them seem to be...drifting. Like something's pulling them in a specific direction.||PULLING THEM WHERE?",
        "That's what I'd like to find out! But the effect is so faint I can barely track it. Could you stockpile about three thousand Sparks? I need a bigger sample to pin down the direction.||THREE THOUSAND? THAT'S A LOT OF SPARKS JUST SITTING THERE.",
        "I know, but I've got a hunch about this, Boss. Something's out there.||...FINE. THREE THOUSAND.",
    ]
    if not dialogue_ended.is_connected(_on_spark_movement_ended):
        dialogue_ended.connect(_on_spark_movement_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Spark Movement", lines)


func enqueue_first_constellation() -> void:
    if first_constellation_done:
        return
    first_constellation_done = true
    var lines = [
        "Ooo[i]oo[/i]ooh, [i]that's[/i] interesting!||WHAT IT IS NOW?",
        "Gee, you're always so wary of anything new! Some changes can be good, you know.||KALEB. \n\nFEWER PERSONAL REMARKS AND MORE [i]INFORMATIVE[/i] ONES.",
        "Yes, Boss. Some of the new unused Sparks are going straight back to where some of the previous ones were resting. As if they're forming a...Constellation, I guess?||HMM. SHOW ME.",
        "Uhhh, well...it's sort of over thataway and a little...how do I put it...um, Boss, we really don't have landmarks yet. We don't even have [i]land[/i] yet. To, er, mark. Or - well, I suppose this thing counts as one?||NOT HELPING, KALEB. \n\nNO, WAIT - YOU SAID SOME SPARKS ARE ATTRACTED TO IT?",
        "Yess...? Oh! That could work! Manually Summon some Sparks and see if they give you a direction?||YES, THAT'S WHAT I'M THINKING.",
        "And it's some pretty good thinking! Try it, try it! Give it at least a dozen taps!||HERE GOES.",
    ]
    if not dialogue_ended.is_connected(_on_first_constellation_ended):
        dialogue_ended.connect(_on_first_constellation_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "First Constellation", lines)
    
    
func enqueue_constellation_panel_creation() -> void:
    if constellation_panel_creation_done:
        return
    constellation_panel_creation_done = true
    var lines = [
        "Ha! It's working! But...the Constellation's only attracting a tiny little trickle of new Sparks.||HMM. CAN WE SPEED THAT UP SOMEHOW?",
        "Uhhh, let me think...Foci? And then I'd have to...oh, yes; that could work. Just need to...there!||SOUNDS PROMISING.",
        "I've added a new interface element on the lower left, check it out!||THAT WAS QUICK. LET'S SEE WHAT YOU'VE GOT.",
    ]
    if not dialogue_ended.is_connected(_on_constellation_panel_creation_ended):
        dialogue_ended.connect(_on_constellation_panel_creation_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Constellation Panel Created", lines)
    
    
func enqueue_open_constellation_panel() -> void:
    if open_constellation_panel_done:
        return
    open_constellation_panel_done = true
    var lines = [
        "Um, it's still very basic...just a label at the top, and the counter controls for Foci and Volitions. Every one of those you assign will guide a Spark to the Constellation. \n\nThen Multi-buttons from the Allocation Wheel and IGNORE and ENDOW buttons for on/off.||GOOD. SIMPLE AND EFFICIENT.",
        "And the extra space is for more controls and information later. So, Boss? Will that do?||YES. WELL DONE, KALEB.",
        "Oh. Uh...thanks!||DON'T SOUND SO SURPRISED. INTERFACE DESIGN IS CLEARLY ONE OF YOUR APEX SKILLS.",
        "O...kay? \n\nBoss, are you feeling alright?||I'M FINE. YOUR ABILITY TO HANDLE POSITIVE FEEDBACK COULD USE SOME IMPROVEMENT, THOUGH.",
        "Ah. Whew, you had me a little worried there.||SO COULD YOUR INTRUSIVE-THOUGHTS-TO-SPEECH FILTER.",
        "[font_size=14]ahem[/font_size] \n\nYes, Boss.",
    ]
    if not dialogue_ended.is_connected(_on_open_constellation_panel_ended):
        dialogue_ended.connect(_on_open_constellation_panel_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Constellation Panel Opened", lines)
    
    
func enqueue_tier1_archon_complete() -> void:
    if tier1_archon_complete_done:
        return
    tier1_archon_complete_done = true
    var lines = [
        "Oh...oh my goodness...is that - it's [i]me[/i]! It's a happy little [i]me![/i]||HEH, SO IT IS. CONGRATULATIONS.",
        "Thanks, Boss! Huh...and now that its stars are all full up with Sparks, they're kind of...vibrating? Weird. What's up with that?||HUH. I WONDER IF...EH, WHY NOT. I'LL TRY TAPPING THEM.",
        "Your turn for a hunch? Sure, let's try it out! Oh, ||HERE WE GO.",
    ]
    if not dialogue_ended.is_connected(_on_tier1_archon_complete_ended):
        dialogue_ended.connect(_on_tier1_archon_complete_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Tier 1 Archon Complete", lines)


func enqueue_study_panel_reveal() -> void:
    if study_panel_reveal_done:
        return
    study_panel_reveal_done = true
    var lines = [
        "Imma charging my laser!||YOU DO YOU, BRO.",
        "Study Panel Button Activate!||AND I'LL FORM THE HEAD.",
    ]
    if not dialogue_ended.is_connected(_on_study_panel_reveal_ended):
        dialogue_ended.connect(_on_study_panel_reveal_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Study Panel Reveal", lines)


func enqueue_star_chase() -> void:
    if star_chase_done:
        return
    star_chase_done = true
    var lines = [
        "Boss, trying to keep it centered looks hugely annoying. Can I add a positioning element to the new interface? Something that holds the whole interface in place while you're dealing with this?||ANOTHER GOOD IDEA. DO IT.",
    ]
    if not dialogue_ended.is_connected(_on_star_chase_ended):
        dialogue_ended.connect(_on_star_chase_ended)
    enqueue_dialogue(lines, true)


func enqueue_end_first_prestige() -> void:
    if second_prestige_done:
        return
    second_prestige_done = true
    var lines = [
        "Second Expansion ready! Hoping for a new Constellation, Boss? Maaaybe one representing you? I'm sure you're not at [i]alll[/i] jealous the Sparks created one for me first....||YOU'RE RIGHT, I'M NOT. I PREFER FUNCTION OVER FORM. SO AS LONG AS IT'S SUFFICIENTLY USEFUL, I'LL BE SATISFIED. \n\nASSUMING THERE IS ANOTHER.",
        "That's...actually what I should have suspected, isn't it.||YES.",
        "Right. So...we can do that second Expansion now, or we could build up another twenty Grains and Create two Uonites at once this time. Up to you!",
    ]
    if not dialogue_ended.is_connected(_on_second_prestige_ended):
        dialogue_ended.connect(_on_second_prestige_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "End First Prestige", lines)


func enqueue_start_second_prestige() -> void:
    if start_second_prestige_done:
        return
    start_second_prestige_done = true
    var lines = [
        "Squishy! That didn't wrinkle me, did I? Can you see any wrinkles?||NO, KALEB, YOU DON'T HAVE ANY WRINKLES. MORE IMPORTANTLY, DO WE HAVE ANY NEW CONSTELLATIONS?",
        "It will take a little while to find out, Boss. We'll need some free Sparks roaming around first. I'm about twice as good at tracking and herding them now, so say...fifteen hundred stocked up this time?||GOOD IMPROVEMENT. \n\nALL RIGHTY, THEN; GIT YERSELF A' WRANGLIN', SPARKBOY.",
        "... \n\nReally? \n\nFine. I shall go now and yee my haw. Whoopee.",
    ]
    if not dialogue_ended.is_connected(_on_start_second_prestige_ended):
        dialogue_ended.connect(_on_start_second_prestige_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Start Second Prestige", lines)


func enqueue_third_prestige() -> void:
    if third_prestige_done:
        return
    third_prestige_done = true
    var lines = [
        "Hourglass placeholder dialogue",
    ]
    if not dialogue_ended.is_connected(_on_third_prestige_ended):
        dialogue_ended.connect(_on_third_prestige_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Third Prestige", lines)


func enqueue_fourth_prestige() -> void:
    if fourth_prestige_done:
        return
    fourth_prestige_done = true
    var lines = [
        "Satchel placeholder dialogue",
    ]
    if not dialogue_ended.is_connected(_on_fourth_prestige_ended):
        dialogue_ended.connect(_on_fourth_prestige_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Fourth Prestige", lines)


func enqueue_fifth_prestige() -> void:
    if fifth_prestige_done:
        return
    fifth_prestige_done = true
    var lines = [
        "Stoker placeholder dialogue",
    ]
    if not dialogue_ended.is_connected(_on_fifth_prestige_ended):
        dialogue_ended.connect(_on_fifth_prestige_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Fifth Prestige", lines)


func enqueue_archon_volition_constellation() -> void:
    if archon_volition_constellation_done:
        return
    archon_volition_constellation_done = true
    var lines = [
        "[X] Constellation is hogging all the free Sparks, Boss; I'm adding the selector for a new one anyways",
    ]
    if not dialogue_ended.is_connected(_on_archon_volition_constellation_ended):
        dialogue_ended.connect(_on_archon_volition_constellation_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "Archon Volition Constellation", lines)


func enqueue_no_archon_volition_constellation() -> void:
    if no_archon_volition_constellation_done:
        return
    no_archon_volition_constellation_done = true
    var lines = [
        "Oooh, I think Two Constellations are attracting Sparks, Boss; I'm adding the selector for the new one",
    ]
    if not dialogue_ended.is_connected(_on_no_archon_volition_constellation_ended):
        dialogue_ended.connect(_on_no_archon_volition_constellation_ended)
    enqueue_dialogue(lines, true)
    emit_signal("sequence_complete", "No Archon Volition Constellation", lines)


#func enqueue_close_constellation_panel() -> void:
    #if close_constellation_panel_done:
        #return
    #close_constellation_panel_done = true
    #var lines = [
        #"So, Boss? Will that do?||YES. WELL DONE, KALEB.",
        #"Oh. Uh...thanks!||DON'T SOUND SO SURPRISED. INTERFACE DESIGN IS CLEARLY ONE OF YOUR APEX SKILLS.",
        #"O...kay? \n\nBoss, are you feeling alright?||I'M FINE. YOUR ABILITY TO HANDLE POSITIVE FEEDBACK COULD USE SOME IMPROVEMENT, THOUGH.",
        #"Ah. Whew, you had me a little worried there.||SO COULD YOUR INTRUSIVE-THOUGHTS-TO-SPEECH FILTER.",
        #"[font_size=14]ahem[/font_size] \n\nYes, Boss.",
    #]
    #if not dialogue_ended.is_connected(_on_close_constellation_panel_ended):
        #dialogue_ended.connect(_on_close_constellation_panel_ended)
    #enqueue_dialogue(lines, true)
    #emit_signal("sequence_complete", "Constellation Panel Review", lines)
    
    
# ===================== POKE DIALOGUES =====================
const POKE_DIALOGUES: Array = [
    "Ehhh...it's not headpats, but it'll do.",
    "I'm not ticklish, you know.",
    "Stop it, I'm gonna discharge!\n\nDon't!\n\nDon't, dooon't!",
    "Enough with the poking already!",
    "Am I going to have to message Nonhuman Resources about this?",
    "boss\n\nwat r u doin\n\nboss\n\nstahp",
    "Boss, I'm warning you now...if you keep doing that, I'll put myself in Time Out.",
    "Okay, you asked for it.\n\nAnd remember, you wanted this.",
]

const POKE_TIER_STARTS: Array = [1, 4, 10, 19, 31, 46, 64, 85, 109, 136, 166]
# Index:                         T1  T2  T3  T4  T5  T6  T7  T8   T9  T10  T11

func get_poke_response(poke_count: int, reentry_threshold: int) -> Dictionary:
    # Returns { "dialogue": String, "shiver": bool, "wiggle": bool, "tantrum": bool }
    # Empty dialogue string = no dialogue this click.

    # Reentry grind: Kaleb is silent until threshold is met
    if reentry_threshold > 0 and poke_count < reentry_threshold:
        return { "dialogue": "", "shiver": false, "wiggle": false, "tantrum": false }

    var tier: int = 1
    for i in range(POKE_TIER_STARTS.size() - 1, -1, -1):
        if poke_count >= POKE_TIER_STARTS[i]:
            tier = i + 1
            break

    var do_shiver:  bool   = tier >= 2
    var do_wiggle:  bool   = tier >= 3
    var do_tantrum: bool   = tier >= 11
    var dialogue:   String = ""

    # Dialogue fires only on the FIRST click of its tier
    if tier >= 4 and tier <= 11:
        var dialogue_index: int = tier - 4  # tier 4 = index 0, tier 11 = index 7
        if poke_count == POKE_TIER_STARTS[tier - 1]:
            dialogue = POKE_DIALOGUES[dialogue_index]

    return { "dialogue": dialogue, "shiver": do_shiver, "wiggle": do_wiggle, "tantrum": do_tantrum }
    
    

func get_current_line() -> String:
    if current_index >= 0 and current_index < dialogue_queue.size():
        return dialogue_queue[current_index]
    return ""
    
    
func get_save_data() -> Dictionary:
    return {
        "intro_done":                           intro_done,
        "second_monad_done":                    second_monad_done,
        "tetrad_upgrade_done":                  tetrad_upgrade_done,
        "all_monads_upgrade_done":              all_monads_upgrade_done,
        "first_fundament_done":                 first_fundament_done,
        "first_non_fundament_done":             first_non_fundament_done,
        "all_fundaments_done":                  all_fundaments_done,
        "all_tetrads_done":                     all_tetrads_done,
        "first_particle_done":                  first_particle_done,
        "first_grain_done":                     first_grain_done,
        "nineteenth_grain_done":                nineteenth_grain_done,
        "twentieth_grain_done":                 twentieth_grain_done,
        "first_prestige_done":                  first_prestige_done,
        "second_prestige_done":                 second_prestige_done,
        "third_prestige_done":                  third_prestige_done,
        "fourth_prestige_done":                 fourth_prestige_done,
        "fifth_prestige_done":                  fifth_prestige_done,
        "start_second_prestige_done":           start_second_prestige_done,
        "archon_volition_constellation_done":   archon_volition_constellation_done,
        "no_archon_volition_constellation_done": no_archon_volition_constellation_done,
        "spark_movement_done":                  spark_movement_done,
        "first_constellation_done":             first_constellation_done,
        "constellation_panel_creation_done":    constellation_panel_creation_done,
        "open_constellation_panel_done":        open_constellation_panel_done,
        "close_constellation_panel_done":       close_constellation_panel_done,
        "star_chase_done":                      star_chase_done,
        "tier1_archon_complete_done":           tier1_archon_complete_done,
        "study_panel_reveal_done":              study_panel_reveal_done,
        "monad_panel_done":         monad_panel_done,
        "monad_random_done":        monad_random_done,
        "category_notified":        _category_notified.duplicate(),
        "all_tetrads_notified":     _all_tetrads_notified,
    }

func _coerce_bool(val, default: bool) -> bool:
    # Every field below is a typed `bool` property; assigning a wrong-typed
    # value from a corrupted-but-parseable save straight into it hangs the
    # engine rather than raising a catchable error (confirmed elsewhere
    # this session), so each read needs a type check before the assignment,
    # not just a null check — the old `_fgd != null` pattern here defended
    # against a missing key but not a wrong-type one.
    if typeof(val) == TYPE_BOOL:
        return val
    return default


func load_save_data(data: Dictionary) -> void:
    intro_done              = _coerce_bool(data.get("intro_done"),                false)
    second_monad_done       = _coerce_bool(data.get("second_monad_done"),         false)
    tetrad_upgrade_done     = _coerce_bool(data.get("tetrad_upgrade_done"),       false)
    all_monads_upgrade_done = _coerce_bool(data.get("all_monads_upgrade_done"),   false)
    first_fundament_done    = _coerce_bool(data.get("first_fundament_done"),      false)
    first_non_fundament_done = _coerce_bool(data.get("first_non_fundament_done"), false)
    all_fundaments_done     = _coerce_bool(data.get("all_fundaments_done"),       false)
    all_tetrads_done        = _coerce_bool(data.get("all_tetrads_done"),          false)
    first_particle_done     = _coerce_bool(data.get("first_particle_done"),       false)

    first_grain_done      = _coerce_bool(data.get("first_grain_done"),      false)
    nineteenth_grain_done = _coerce_bool(data.get("nineteenth_grain_done"), false)
    twentieth_grain_done  = _coerce_bool(data.get("twentieth_grain_done"),  false)

    first_prestige_done     = _coerce_bool(data.get("first_prestige_done"),       false)
    second_prestige_done    = _coerce_bool(data.get("second_prestige_done"),      false)
    third_prestige_done     = _coerce_bool(data.get("third_prestige_done"),        false)
    fourth_prestige_done    = _coerce_bool(data.get("fourth_prestige_done"),       false)
    fifth_prestige_done     = _coerce_bool(data.get("fifth_prestige_done"),        false)
    start_second_prestige_done = _coerce_bool(data.get("start_second_prestige_done"), false)
    archon_volition_constellation_done = _coerce_bool(data.get("archon_volition_constellation_done"), false)
    no_archon_volition_constellation_done = _coerce_bool(data.get("no_archon_volition_constellation_done"), false)
    spark_movement_done     = _coerce_bool(data.get("spark_movement_done"),       false)
    star_chase_done         = _coerce_bool(data.get("star_chase_done"),           false)
    tier1_archon_complete_done  = _coerce_bool(data.get("tier1_archon_complete_done"),  false)
    study_panel_reveal_done     = _coerce_bool(data.get("study_panel_reveal_done"),     false)
    first_constellation_done = _coerce_bool(data.get("first_constellation_done"), false)
    constellation_panel_creation_done = _coerce_bool(data.get("constellation_panel_creation_done"), false)
    open_constellation_panel_done = _coerce_bool(data.get("open_constellation_panel_done"), false)

    # close_constellation_panel_done = data.get("close_constellation_panel_done", false)

    monad_panel_done        = _coerce_bool(data.get("monad_panel_done"),          false)
    monad_random_done       = _coerce_bool(data.get("monad_random_done"),         false)
    if data.has("category_notified"):
        for key in data["category_notified"]:
            if _category_notified.has(key):
                _category_notified[key] = _coerce_bool(data["category_notified"][key], false)
    _all_tetrads_notified   = _coerce_bool(data.get("all_tetrads_notified"),     false)
