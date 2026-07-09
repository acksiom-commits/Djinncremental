extends Node
# ================= PUZZLE SYNTHS v2.0.0 =================
# Three-voice procedural synthesizer with sequence playback.
#
# Voices:
#   VoiceMelody     — FM synthesis: bell (star clicks), brass (ff), woodwind (p)
#   VoiceBass       — Trombone-saw with amplitude-brightness coupling
#   VoicePercussion — Filtered noise bursts for march accents
#
# API (called by constellation_overlay.gd):
#   play_bell_note(frequency)             — single star-click tone (melody voice)
#   play_thud()                           — silent-star percussive hit
#   play_sequence(seq, on_complete_cb)    — three-voice fanfare/reward playback
#   stop_sequence()                       — cancel any playing sequence
#
# Sequences are defined by PuzzleSequenceResource (.tres files).
# ============================================================

const SAMPLE_HZ: float = 44100.0
const BUFFER_LENGTH: float = 0.1

@export var amplitude: float = 0.4

# ── VOICE INDICES ───────────────────────────────────────────
const V_MELODY: int = 0
const V_BASS:   int = 1
const V_PERC:   int = 2

# ── VOICE STATE ─────────────────────────────────────────────
# Each entry: {player, playback, phase, phase_mod, freq, vel, time, active, timbre}
var _voices: Array = []

# ── SEQUENCER ───────────────────────────────────────────────
var _seq_generation: int = 0
var _current_beat_dur: float = 0.5
var _sequence_active: bool = false

# ── SOLVE LIGHTING ───────────────────────────────────────────────
signal sequence_note_played(frequency: float)

# ── TIMBRE PARAMETERS ──────────────────────────────────────
# FM synthesis: sample = sin(carrier_phase + index * sin(mod_phase))
# Changing mod_ratio and mod_index dramatically alters timbre.
const TIMBRE_BELL = {
    "mod_ratio": 2.76,    # Inharmonic — metallic bell character
    "mod_index": 3.5,
    "attack":    0.008,
    "sustain":   0.25,
    "release":   12.0,
    "brightness_coupling": 0.0,
}

const TIMBRE_BRASS = {
    "mod_ratio": 2.0,     # Strong 2nd harmonic (matches spectral data)
    "mod_index": 1.8,     # Moderate richness
    "attack":    0.045,   # Slower bloom like real brass
    "sustain":   0.5,
    "release":   6.0,
    "brightness_coupling": 3.0,  # Loud = much brighter (the "blat")
}

const TIMBRE_WOODWIND = {
    "mod_ratio": 3.0,     # Odd-harmonic emphasis
    "mod_index": 0.8,
    "attack":    0.035,
    "sustain":   0.5,
    "release":   6.0,
    "brightness_coupling": 0.5,
    "breath_mix": 0.06,
}

const TIMBRE_TROMBONE = {
    "mod_ratio": 2.0,     # Same 2nd harmonic as brass
    "mod_index": 1.4,     # Slightly warmer than trumpet brass
    "attack":    0.055,   # Even slower attack — trombone bloom
    "sustain":   0.55,
    "release":   5.0,
    "brightness_coupling": 2.2,  # Less blat than trumpet, still present
}

const TIMBRE_THUD = {
    "freq_a": 80.0,
    "freq_b": 93.0,
    "decay":  18.0,
    "ramp":   0.003,
}


# ==================================================
# LIFECYCLE
# ==================================================
func _ready() -> void:
    for i in 3:
        var player := AudioStreamPlayer.new()
        player.name = ["VoiceMelody", "VoiceBass", "VoicePercussion"][i]
        var gen := AudioStreamGenerator.new()
        gen.mix_rate = SAMPLE_HZ
        gen.buffer_length = BUFFER_LENGTH
        player.stream = gen
        player.volume_db = [0.0, -3.0, -4.0][i]
        add_child(player)
        _voices.append({
            "player":    player,
            "playback":  null,       # Set after play() + 1 frame
            "phase":     0.0,
            "phase_mod": 0.0,
            "freq":      0.0,
            "vel":       1.0,
            "time":      0.0,
            "active":    false,
            "timbre":    "bell",
            "noise_phase": 0.0,      # For perc / breath noise
        })
    call_deferred("_init_playbacks")


func _init_playbacks() -> void:
    for v in _voices:
        v["player"].play()
    await get_tree().process_frame
    for v in _voices:
        v["playback"] = v["player"].get_stream_playback()
        if not v["playback"]:
            push_warning("PuzzleSynths: playback null for %s" % v["player"].name)


func _process(_delta: float) -> void:
    for v in _voices:
        if not v["playback"]:
            continue
        if not v["active"]:
            _fill_silence(v)
        elif v["timbre"] == "thud":
            _fill_thud(v)
        elif v["timbre"] == "perc":
            _fill_perc(v)
        else:
            _fill_fm(v)


# ==================================================
# PUBLIC API
# ==================================================

## Single star-click tone (trombone timbre on melody voice).
func play_bell_note(frequency: float) -> void:
    _start_note(V_MELODY, frequency, 1.0, "trombone")


## Silent-star percussive thud.
func play_thud() -> void:
    var v = _voices[V_PERC]
    v["phase"]     = 0.0
    v["phase_mod"] = 0.0
    v["time"]      = 0.0
    v["freq"]      = 0.0
    v["vel"]       = 1.0
    v["active"]    = true
    v["timbre"]    = "thud"


## Stop any currently playing sequence.
func stop_sequence() -> void:
    _seq_generation += 1
    _sequence_active = false
    for v in _voices:
        v["active"] = false

## Play a three-voice sequence from a PuzzleSequenceResource.
## Optional callback called when all voices finish.
func play_sequence(seq: PuzzleSequenceResource, on_complete: Callable = Callable()) -> void:
    stop_sequence()
    _seq_generation += 1
    var gen: int = _seq_generation
    _sequence_active = true
    _current_beat_dur = seq.beat_duration()

    var melody_timbre: String = seq.melody_timbre if seq.melody_timbre else "brass"
    var bass_timbre:   String = seq.bass_timbre if seq.bass_timbre else "trombone"
    var perc_timbre:   String = seq.perc_timbre if seq.perc_timbre else "perc"

    _play_voice_coroutine(V_MELODY, seq.melody, melody_timbre, gen)
    _play_voice_coroutine(V_BASS,   seq.bass,   bass_timbre,   gen)
    _play_voice_coroutine(V_PERC,   seq.perc,   perc_timbre,   gen)

    var dur: float = seq.total_duration()
    await get_tree().create_timer(dur + 0.15).timeout
    if gen == _seq_generation:
        _sequence_active = false
        if on_complete.is_valid():
            on_complete.call()


# ==================================================
# SEQUENCER COROUTINE
# ==================================================
func _play_voice_coroutine(voice_idx: int, events: Array, timbre: String, gen: int) -> void:
    for event in events:
        if gen != _seq_generation:
            return

        var beats: float = event.get("beats", 1.0)
        var vel:   float = event.get("vel", 1.0)

        if event.has("note"):
            var note_name: String = event["note"]
            if note_name != "rest":
                var freq: float = note_to_freq(note_name)
                if freq > 0.0:
                    _start_note(voice_idx, freq, vel, timbre)
                    if voice_idx == V_MELODY:
                        sequence_note_played.emit(freq)
        elif event.has("hit"):
            _start_hit(voice_idx, vel)

        await get_tree().create_timer(beats * _current_beat_dur).timeout


# ==================================================
# NOTE CONTROL
# ==================================================
func _start_note(voice_idx: int, freq: float, vel: float, timbre: String) -> void:
    var v = _voices[voice_idx]
    v["phase"]     = 0.0
    v["phase_mod"] = 0.0
    v["time"]      = 0.0
    v["freq"]      = freq
    v["vel"]       = vel
    v["active"]    = true
    v["timbre"]    = timbre


func _start_hit(voice_idx: int, vel: float) -> void:
    var v = _voices[voice_idx]
    v["phase"]       = 0.0
    v["phase_mod"]   = 0.0
    v["time"]        = 0.0
    v["freq"]        = 0.0
    v["vel"]         = vel
    v["active"]      = true
    v["timbre"]      = "perc"
    v["noise_phase"] = 0.0


# ==================================================
# DSP — FM SYNTHESIS (melody, brass, woodwind, trombone)
# ==================================================
func _fill_fm(v: Dictionary) -> void:
    var pb: AudioStreamGeneratorPlayback = v["playback"]
    var frames: int = pb.get_frames_available()
    if frames == 0:
        return

    var timbre_data: Dictionary
    match v["timbre"]:
        "bell":      timbre_data = TIMBRE_BELL
        "brass":     timbre_data = TIMBRE_BRASS
        "woodwind":  timbre_data = TIMBRE_WOODWIND
        "trombone":  timbre_data = TIMBRE_TROMBONE
        _:           timbre_data = TIMBRE_BELL

    var freq:       float = v["freq"]
    var vel:        float = v["vel"]
    var mod_ratio:  float = timbre_data["mod_ratio"]
    var mod_index:  float = timbre_data["mod_index"]
    var attack_dur: float = timbre_data["attack"]
    var sustain_dur:float = timbre_data["sustain"]
    var release_r:  float = timbre_data["release"]
    var bright_c:   float = timbre_data.get("brightness_coupling", 0.0)
    var breath_mix: float = timbre_data.get("breath_mix", 0.0)

    var phase:     float = v["phase"]
    var phase_mod: float = v["phase_mod"]
    var t:         float = v["time"]
    var np:        float = v["noise_phase"]

    var inv_hz: float = 1.0 / SAMPLE_HZ
    var freq_inc:     float = TAU * freq * inv_hz
    var mod_freq_inc: float = TAU * freq * mod_ratio * inv_hz

    for _i in frames:
        # ── Envelope ──
        var attack_env: float = clampf(t / attack_dur, 0.0, 1.0)
        var body_env: float
        if t < sustain_dur:
            body_env = 1.0 - (t / sustain_dur) * 0.12
        else:
            body_env = exp(-release_r * (t - sustain_dur))
        var env: float = attack_env * body_env * vel

        if body_env < 0.0004:
            v["active"] = false
            # Fill remaining with silence
            for _j in range(_i, frames):
                pb.push_frame(Vector2.ZERO)
            break

        # ── Amplitude-brightness coupling ──
        var effective_index: float = mod_index + bright_c * env

        # ── FM oscillator ──
        var modulator: float = sin(phase_mod) * effective_index
        var carrier:   float = sin(phase + modulator)

        # ── Soft clip ──
        var raw: float = carrier * env * amplitude
        var sample: float = raw / (1.0 + absf(raw) * 0.5)

        # ── Breath noise (woodwind only) ──
        if breath_mix > 0.0:
            # Simple hash-based noise — deterministic, cheap
            np += 1.0
            var noise: float = fmod(sin(np * 12345.6789) * 43758.5453, 1.0) * 2.0 - 1.0
            sample += noise * breath_mix * env

        pb.push_frame(Vector2(sample, sample))

        phase     += freq_inc
        phase_mod += mod_freq_inc
        t         += inv_hz

    # Wrap phases to prevent float drift
    if phase > TAU:
        phase = fmod(phase, TAU)
    if phase_mod > TAU:
        phase_mod = fmod(phase_mod, TAU)

    v["phase"]       = phase
    v["phase_mod"]   = phase_mod
    v["time"]        = t
    v["noise_phase"] = np


# ==================================================
# DSP — PERCUSSION (noise burst)
# ==================================================
func _fill_perc(v: Dictionary) -> void:
    var pb: AudioStreamGeneratorPlayback = v["playback"]
    var frames: int = pb.get_frames_available()
    if frames == 0:
        return

    var vel: float = v["vel"]
    var t:   float = v["time"]
    var np:  float = v["noise_phase"]
    var inv_hz: float = 1.0 / SAMPLE_HZ

    for _i in frames:
        var env: float = exp(-22.0 * t) * clampf(t / 0.002, 0.0, 1.0)
        if env < 0.0004:
            v["active"] = false
            for _j in range(_i, frames):
                pb.push_frame(Vector2.ZERO)
            break

        np += 1.0
        var noise: float = fmod(sin(np * 12345.6789) * 43758.5453, 1.0) * 2.0 - 1.0
        # Band-pass character: mix pitched noise with pure noise
        var pitched: float = sin(TAU * 180.0 * t + noise * 2.5)
        var raw: float = (noise * 0.5 + pitched * 0.5) * env * vel * amplitude * 0.6
        var sample: float = raw / (1.0 + absf(raw) * 0.4)

        pb.push_frame(Vector2(sample, sample))
        t += inv_hz

    v["time"]        = t
    v["noise_phase"] = np


# ==================================================
# DSP — THUD (silent star hit — from v1.0)
# ==================================================
func _fill_thud(v: Dictionary) -> void:
    var pb: AudioStreamGeneratorPlayback = v["playback"]
    var frames: int = pb.get_frames_available()
    if frames == 0:
        return

    var phase: float = v["phase"]
    var t:     float = v["time"]
    var inv_hz: float = 1.0 / SAMPLE_HZ

    for _i in frames:
        var env: float = exp(-TIMBRE_THUD["decay"] * t) * clampf(t / TIMBRE_THUD["ramp"], 0.0, 1.0)
        if env < 0.0005:
            v["active"] = false
            for _j in range(_i, frames):
                pb.push_frame(Vector2.ZERO)
            break

        var s: float = (
            sin(TAU * TIMBRE_THUD["freq_a"] * t + phase) * 0.5
            + sin(TAU * TIMBRE_THUD["freq_b"] * t + phase * 1.17) * 0.4
        ) * env * amplitude * 0.55
        pb.push_frame(Vector2(s, s))

        phase += TAU * TIMBRE_THUD["freq_a"] * inv_hz
        t     += inv_hz

    if phase > TAU:
        phase = fmod(phase, TAU)

    v["phase"] = phase
    v["time"]  = t


# ==================================================
# DSP — SILENCE FILL
# ==================================================
func _fill_silence(v: Dictionary) -> void:
    var pb: AudioStreamGeneratorPlayback = v["playback"]
    var frames: int = pb.get_frames_available()
    for _i in frames:
        pb.push_frame(Vector2.ZERO)


# ==================================================
# NOTE NAME → FREQUENCY LOOKUP
# ==================================================
# Equal temperament, A4 = 440 Hz.
# Accepts: "C4", "C#4", "Db4", "Bb5", "F#3", etc.
# Returns 0.0 on parse failure.

const _SEMITONE_MAP: Dictionary = {
    "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
}

static func note_to_freq(note_name: String) -> float:
    if note_name.is_empty():
        return 0.0

    var letter: String = note_name[0].to_upper()
    if not _SEMITONE_MAP.has(letter):
        push_warning("PuzzleSynths: unrecognized note letter '%s' in '%s'" % [letter, note_name])
        return 0.0

    var semitone: int = _SEMITONE_MAP[letter]
    var accidental: int = 0
    var octave_str: String = ""

    for i in range(1, note_name.length()):
        var c: String = note_name[i]
        if c == "#":
            accidental += 1
        elif c == "b":
            accidental -= 1
        else:
            octave_str += c

    if octave_str.is_empty() or not octave_str.is_valid_int():
        push_warning("PuzzleSynths: no valid octave in note '%s'" % note_name)
        return 0.0

    var octave: int = octave_str.to_int()
    var midi: int = (octave + 1) * 12 + semitone + accidental
    return 440.0 * pow(2.0, (midi - 69.0) / 12.0)
