class_name PuzzleSequenceResource
extends Resource
# ================= PUZZLE SEQUENCE RESOURCE v1.0.0 =================
# Defines a multi-voice musical sequence for constellation puzzle events.
# Each constellation references two of these: solve_fanfare, completion_reward.
#
# Create .tres files via Inspector: New Resource → PuzzleSequenceResource
# Or generate from AI sheet-music scanning and save via ResourceSaver.
#
# VOICE ARRAYS:
#   Each voice is an Array of Dictionaries. Each dict is one note event:
#     {"note": "Bb4", "beats": 1.5, "vel": 1.0}   — pitched note
#     {"note": "rest", "beats": 0.5}                — silence
#     {"hit": "snare", "beats": 1.0, "vel": 0.8}   — percussion hit
#
# TIMING:
#   Duration in seconds = (beats / tempo_bpm) * 60.0
#   A quarter note at 120 BPM = 0.5 seconds.
#
# NOTE NAMES:
#   Standard: C0–B8, with sharps (C#4) and flats (Db4) both accepted.
#   Lookup handled by PuzzleSynths — this resource stores strings only.
# ===================================================================


@export var tempo_bpm: float = 120.0

## Top numerator of time signature (e.g. 6 for 6/8)
@export var time_sig_top: int = 4

## Bottom denominator of time signature (e.g. 8 for 6/8)
@export var time_sig_bottom: int = 4

## Timbre for melody voice: "bell", "brass", "woodwind", "trombone"
@export var melody_timbre: String = "brass"

## Timbre for bass voice (maps to the "bass" array in the .tres)
@export var bass_timbre: String = "trombone"

## Timbre for perc voice (maps to the "perc" array — can be pitched or percussion)
@export var perc_timbre: String = "perc"

## Melody voice — carries the main theme
@export var melody: Array[Dictionary] = []

## Bass voice — root notes, oom-pah patterns, pedal tones
@export var bass: Array[Dictionary] = []

## Percussion voice — rhythmic hits and accents
@export var perc: Array[Dictionary] = []


## Returns duration of one beat in seconds at this resource's tempo.
func beat_duration() -> float:
    return 60.0 / tempo_bpm


## Returns total duration of a voice array in seconds.
func voice_duration(voice: Array[Dictionary]) -> float:
    var total_beats: float = 0.0
    for event in voice:
        total_beats += event.get("beats", 0.0)
    return total_beats * beat_duration()


## Returns the longest voice duration (sequence total length).
func total_duration() -> float:
    return maxf(voice_duration(melody),
        maxf(voice_duration(bass), voice_duration(perc)))
