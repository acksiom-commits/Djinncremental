extends Node
# ================= CONSTELLATION DATA v0.3.2 =================
# v0.3.2: Added 6th built-in constellation, The Djinn (id 5) — represents
#         the Player, themed around the vessel (Ring/Jar/Lamp/etc.) chosen
#         during the pre-game intro's training-period selection. Bonus key
#         "endowment_multiplier" reduces the Constellation Endowment
#         bottleneck directly (not yet wired into ProductionManager — data
#         placeholder only). fixed_star_positions/line_pairs pending one
#         art variant per vessel choice; puzzle_sequence has 15 of 17
#         required notes. Six built-ins total now (was five).
# v0.3.1  1st Constellation changed to The Archon, in Octant 0. Lore
#         altered. The Hourglass changed to 2nd Constellation in Octant 1.
#         We're going to spread the first 8 Constellations across 4 to 6
#         Octants to better create a sense of defined space in the pocket
#         dimension before the player graduates to the Mid-game and
#         establishes a fixed plane of Firmament to begin building
#         structures upon.
# v0.3.0: Puzzle system added. PUZZLE_NOTE_FREQS, PUZZLE_CALL_SEQUENCE,
#         PUZZLE_RESPONSE_FREQS, PUZZLE_SPARK_FRACTIONS constants.
#         get_note_assignment(), grant_puzzle_sparks() functions.
#         fixed_star_positions and bonus_levels support added.
#         Placeholder constellations 1-8 retained; id 2 is The Hourglass
#         (first fully designed constellation with puzzle interaction).
# v0.2.0: Added spark fraction, visual state, and display methods.
#         get_spark_fraction(), get_visual_state(), get_star_brightness(),
#         get_active_display_id(), set_display_constellation().
#         SPARK_CAP_BASE, THRESHOLD_STARS, THRESHOLD_ART constants added.
# v0.1.0: Initial implementation.
#
# Autoload: add as "ConstellationData" ABOVE GameContext.
#
# SLOT ALLOCATION:
#   IDs 0-15:  Built-in (narrative/lore, designed by dev)
#   IDs 16-31: Player-designed (personal customization)
#   IDs 32-47: Patron monthly (approved submissions)
#   IDs 48-63: Reserved (events, achievements, future use)
#
# OCTANTS (8 divisions of the unit sphere):
#   Each octant is defined by the sign of (x, y, z):
#   0: (+,+,+)  1: (-,+,+)  2: (+,-,+)  3: (-,-,+)
#   4: (+,+,-)  5: (-,+,-)  6: (+,-,-)  7: (-,-,-)
#
# UNLOCK CONDITIONS (string keys):
#   "always"                  — always unlocked
#   "achievement:KEY"         — unlocks when achievement KEY fires
#   "stat:FIELD >= N"         — polls GameContext.FIELD >= N
#   "stat:FIELD == N"         — polls GameContext.FIELD == N
#   "constellation:ID"        — requires constellation ID unlocked first
#
# BONUS KEYS (string keys read by ProductionManager):
#   ""                        — no passive bonus (mechanic-only unlock)
#   "sparks_summon_bonus"     — extra sparks per summon tick
#   "monad_compress_bonus"    — extra monads per compress tick
#   "archon_foci_bonus"       — extra archon foci (flat)
#   "purity_lock_slots"       — extra purity lock slots
#   "cooldown_multiplier"     — tiered cooldown reduction via bonus_levels
#   "endowment_multiplier"    — reduces Constellation Endowment bottleneck
#                                (data placeholder; not yet read by ProductionManager)
#
# MECHANIC UNLOCK KEYS (string keys read by ProductionManager):
#   ""                        — no mechanic unlock
#   "unlock_purity_sorting"   — enables purity-sorted compression
#   "unlock_tetrad_memory"    — Archon remembers last tetrad composition
#   "unlock_iota_targeting"   — allows targeting specific iota types
#   "unlock_spark_burst"      — new button: spend grain for spark burst
#   "unlock_archon_recall"    — Archon can replay any past dialogue
#   "unlock_uonite_training"  — Uonites gain experience from operations
#   "unlock_constellation_view" — enables ConstellationViewPanel UI
#
# PUZZLE FIELDS (optional, on constellations with puzzle_sequence):
#   "puzzle_sequence"         — Array of PUZZLE_NOTE_FREQS indices (call phrase)
#   "fixed_star_positions"    — Array of [x,y,z] float arrays (designed layout)
#   "bonus_levels"            — Dict mapping visual state to bonus multiplier value
 
 
# ==================================================
# SIGNALS
# ==================================================
signal constellation_unlocked(constellation_id: int)
signal active_constellation_changed(octant: int, constellation_id: int)
signal mechanic_unlocked(mechanic_key: String)
 
 
# ==================================================
# OCTANT DEFINITIONS
# ==================================================
const OCTANTS = [
    {"name": "Zenith-Forward-Right",  "dir": Vector3( 0.577,  0.577,  0.577)},
    {"name": "Zenith-Forward-Left",   "dir": Vector3(-0.577,  0.577,  0.577)},
    {"name": "Nadir-Forward-Right",   "dir": Vector3( 0.577, -0.577,  0.577)},
    {"name": "Nadir-Forward-Left",    "dir": Vector3(-0.577, -0.577,  0.577)},
    {"name": "Zenith-Back-Right",     "dir": Vector3( 0.577,  0.577, -0.577)},
    {"name": "Zenith-Back-Left",      "dir": Vector3(-0.577,  0.577, -0.577)},
    {"name": "Nadir-Back-Right",      "dir": Vector3( 0.577, -0.577, -0.577)},
    {"name": "Nadir-Back-Left",       "dir": Vector3(-0.577, -0.577, -0.577)},
]
 
 
# ==================================================
# BUILT-IN CONSTELLATION DEFINITIONS (IDs 1-16)
# ==================================================
# ── DEV SIZING CONSTRAINT ───────────────────────────────────────────────────
# Panel display area: 353 x 175 px (aspect ~2.017 : 1)
# fixed_star_positions are unit-sphere Vector3 [x, y, z] where z ≈ sqrt(1-x²-y²)
# To stay comfortably inside the panel with click margin, keep:
#   |x| ≤ 0.130   (horizontal spread)
#   |y| ≤ 0.055   (vertical spread)
# Exceeding these risks stars clipping the panel edge or overlapping UI borders.
# ────────────────────────────────────────────────────────────────────────────
 
const BUILT_IN = [
    
# ==================================================
# CONSTELLATION 1-1: KALEB, THE ARCHON
# ==================================================
    {
        "id": 0,
        "name": "The Archon",
        "designation": "KALEB",
        "octant": 0,
        "star_count": 15,
        "unlock": "achievement:first_prestige",
        "bonus_key": "bonus_volitions",
        "bonus_value": 1.0,
        "mechanic_key": "unlock_archon_titles",
        "bonus_levels": {"stars": 1, "lines": 2, "art": 3},
        "spark_cap":      75025,
        "line_threshold": 0.3819,   # 28,657 / 75,025
        "snap_horiz_stars": [0, 1],
        # Leveling snap_horiz_stars alone only fixes rotation mod 180° —
        # star 2 (the outer-triangle apex, "outer bottom apex" below) must
        # end up on the +Y (point-down) side after leveling, or the whirl
        # can settle upside-down. See get_canonical_display_basis().
        "snap_orient_check": {"star": 2, "axis": "y", "sign": 1},
        "puzzle_sequence": [8, 7, 6, 5, 4, 3, 2, 1, 0, 1, 2, 1, 0, 4, 9],
        "note_durations": [
            0.333, 0.167, 0.333, 0.167,          # Measure 1: F5 E5 D5 C#5
            0.333, 0.167, 0.333, 0.167,          # Measure 2: C5 B4 Bb4 A4
            0.100, 0.100, 0.100, 0.167, 0.100,  # Measure 3: G4 A4 Bb4 A4 G4
            0.333, 0.167,                         # Measure 4: C5 C6
        ],
        "note_freqs": [
            392.00,   # 0: G4
            440.00,   # 1: A4
            466.16,   # 2: Bb4
            493.88,   # 3: B4
            523.25,   # 4: C5
            554.37,   # 5: C#5
            587.33,   # 6: D5
            659.26,   # 7: E5
            698.46,   # 8: F5
            1046.50,  # 9: C6 — bright final punctuation
        ],
        "response_freqs": [
            349.23,  # F4
            392.00,  # G4
            440.00,  # A4
            466.16,  # Bb4
            523.25,  # C5
            440.00,  # A4
            349.23,  # F4
            293.66,  # D4
            523.25,  # C5
            493.88,  # B4
            466.16,  # Bb4
            440.00,  # A4
            392.00,  # G4
            349.23,  # F4
            174.61,  # F3
        ],
        
        "fixed_star_positions": [
            # Outer triangle
            [-0.100, -0.060,  0.993],  # 0: outer top-left
            [ 0.098, -0.057,  0.993],  # 1: outer top-right
            [ 0.002,  0.062,  0.998],  # 2: outer bottom apex
            # Left eye
            [-0.064, -0.046,  0.997],  # 3: left-eye top-left
            [-0.028, -0.047,  0.998],  # 4: left-eye top-right
            [-0.046, -0.020,  0.998],  # 5: left-eye bottom apex
            # Right eye
            [ 0.028, -0.045,  0.998],  # 6: right-eye top-left
            [ 0.064, -0.044,  0.997],  # 7: right-eye top-right
            [ 0.046, -0.017,  0.999],  # 8: right-eye bottom apex
            # Mouth (now its own 3-star downward triangle, like the eyes)
            [-0.023,  0.010,  0.9997], # 9:  mouth top-left
            [ 0.021,  0.010,  0.9997], # 10: mouth top-right
            [-0.001,  0.034,  0.9994], # 11: mouth bottom apex
            # Outer triangle edge midpoints (subdivide existing edges only,
            # triangle shape unchanged)
            [-0.001, -0.0585, 0.9983], # 12: midpoint of top edge (0-1)
            [ 0.050,  0.0025, 0.9987], # 13: midpoint of right edge (1-2)
            [-0.049,  0.001,  0.9988], # 14: midpoint of left edge (2-0)
        ],
        
        "line_pairs": [
            0,12, 12,1,   1,13, 13,2,   2,14, 14,0,   # outer triangle, subdivided by midpoints
            3,4,  4,5,  5,3,                            # left eye
            6,7,  7,8,  8,6,                            # right eye
            9,10, 10,11, 11,9,                          # mouth (self-contained triangle)
        ],
    },
 
# ==================================================
# CONSTELLATION 2-2: ALZIRO, THE SPARK
# ==================================================

    {
        "id": 1,
        "name": "The Spark",
        "designation": "ALZIRO",
        "octant": 1,
        "star_count": 16,
        "unlock": "achievement:second_prestige",
        "bonus_key": "sparks_multiplier",
        "bonus_value": 1.0,
        "mechanic_key": "",
        "snap_horiz_stars": [0, 8],
        "bonus_levels": {"stars": 1.5, "lines": 2.0, "art": 3.0},
        "spark_cap":      75025,
        "line_threshold": 0.3819,   # 28,657 / 75,025

        # Hallelujah Chorus (Handel's Messiah) — orchestral introduction,
        # 16 note-events over 16 stars (one star per note). Violin 1 melodic line,
        # before the full chorus enters in unison. 7 distinct pitch classes (D major).
        # puzzle_sequence indexes note_freqs; reveal order follows the actual melodic
        # contour so the tune becomes recognizable as the player progresses.
        "puzzle_sequence": [0, 1, 2, 1, 0, 3, 4, 3, 1, 4, 3, 5, 0, 1, 2, 6],
        "note_freqs": [
            293.66,  # 0: D4
            440.00,  # 1: A4
            493.88,  # 2: B4
            369.99,  # 3: F#4
            392.00,  # 4: G4
            329.63,  # 5: E4
            554.37,  # 6: C#5
        ],
        # TODO (Boss): response_freqs and note_durations not yet designed —
        # placeholders below, replace before this constellation ships.
        "note_durations": [
            0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25,
            0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25,
        ],
        "response_freqs": [
            293.66, 440.00, 493.88, 369.99, 392.00, 329.63, 554.37,
        ],

        "fixed_star_positions": [
            [-0.0232, -0.0007,  0.9997],  # 0:  left hub
            [-0.0367, -0.0163,  0.9992],  # 1:  upper-left mid
            [-0.0586, -0.0448,  0.9973],  # 2:  upper-left tip
            [-0.0649,  0.0045,  0.9979],  # 3:  left-chain mid (near hub)
            [-0.0972,  0.0044,  0.9953],  # 4:  left-chain mid (outer)
            [-0.1280,  0.0024,  0.9918],  # 5:  left-chain tip (far left)
            [-0.0315,  0.0188,  0.9993],  # 6:  lower-left mid
            [-0.0601,  0.0511,  0.9969],  # 7:  lower-left tip
            [ 0.0200, -0.0005,  0.9998],  # 8:  right hub
            [ 0.0330, -0.0189,  0.9993],  # 9:  upper-right mid
            [ 0.0505, -0.0523,  0.9974],  # 10: upper-right tip
            [ 0.0577, -0.0004,  0.9983],  # 11: right-chain mid (near hub)
            [ 0.0966,  0.0010,  0.9953],  # 12: right-chain mid (outer)
            [ 0.1280, -0.0007,  0.9918],  # 13: right-chain tip (far right)
            [ 0.0315,  0.0220,  0.9993],  # 14: lower-right mid
            [ 0.0497,  0.0523,  0.9974],  # 15: lower-right tip
        ],

        "line_pairs": [
            0,1,  1,2,             # left hub -> upper-left arm
            0,3,  3,4,  4,5,       # left hub -> left chain
            0,6,  6,7,             # left hub -> lower-left arm
            0,8,                   # left hub -> right hub (the connecting spine)
            8,9,  9,10,            # right hub -> upper-right arm
            8,11, 11,12, 12,13,    # right hub -> right chain
            8,14, 14,15,           # right hub -> lower-right arm
        ],
    },

# ==================================================
# CONSTELLATION 3-3: DRASIN, THE HOURGLASS
# ==================================================
 
    {
        "id": 2,
        "name": "The Hourglass",
        "designation": "DRASIN",
        "octant": 2,
        "star_count": 13,
        "unlock": "achievement:third_prestige",
        "bonus_key": "cooldown_multiplier",
        "bonus_value": 1.0,
        "mechanic_key": "",
        "snap_horiz_stars": [3, 9],
        "bonus_levels": {"stars": 0.5, "lines": 0.25, "art": 0.1},
        "sub_targets": [
            "monad_compress", "tetrad_assemble",
            "particle_compress", "iota_assemble", "mote_compress",
            "grain_assemble", "uonite_create"
        ],
        "spark_cap":      75025,
        "line_threshold": 0.3819,   # 28,657 / 75,025
        "puzzle_sequence": [0, 1, 2, 4, 6, 2, 6, 5, 1, 4, 3, 7, 4],
        "fixed_star_positions": [
            [-0.0056,  0.0042,  1.0000],  # 0:  center
            [-0.0311, -0.0106,  0.9995],  # 1:  top-left mid (near center)
            [-0.0654, -0.0304,  0.9974],  # 2:  top-left mid (outer)
            [-0.1002, -0.0350,  0.9943],  # 3:  top-left corner
            [-0.1002,  0.0381,  0.9942],  # 4:  bottom-left corner
            [-0.0668,  0.0313,  0.9973],  # 5:  bottom-left mid (outer)
            [-0.0314,  0.0195,  0.9993],  # 6:  bottom-left mid (near center)
            [ 0.0245, -0.0131,  0.9996],  # 7:  top-right mid (near center)
            [ 0.0636, -0.0322,  0.9975],  # 8:  top-right mid (outer)
            [ 0.1002, -0.0439,  0.9940],  # 9:  top-right corner
            [ 0.0999,  0.0439,  0.9940],  # 10: bottom-right corner
            [ 0.0665,  0.0393,  0.9970],  # 11: bottom-right mid (outer)
            [ 0.0228,  0.0171,  0.9996],  # 12: bottom-right mid (near center)
        ],

        "line_pairs": [
            0,1,  1,2,  2,3,       # center -> top-left arm -> corner
            0,6,  6,5,  5,4,       # center -> bottom-left arm -> corner
            3,4,                   # left corner-to-corner connector
            0,7,  7,8,  8,9,       # center -> top-right arm -> corner
            0,12, 12,11, 11,10,    # center -> bottom-right arm -> corner
            9,10,                  # right corner-to-corner connector
        ],
        "note_freqs": [
            246.94,  # 0: B3
            277.18,  # 1: C#4
            293.66,  # 2: D4
            311.13,  # 3: Eb4
            329.63,  # 4: E4
            349.23,  # 5: E#4 (F natural)
            369.99,  # 6: F#4
            261.63,  # 7: C4
        ],

        "response_freqs": [
            369.99, 415.30, 466.16, 493.88, 554.37,
            466.16, 554.37, 587.33, 466.16, 587.33,
            554.37, 466.16, 554.37
        ],
    },
    
    
# ==================================================
# CONSTELLATION 4-4: THE SATCHEL
# ==================================================

    {
        "id": 3,
        "name": "The Satchel",
        "designation": "HANLEE",
        "octant": 3,
        "star_count": 17,
        "unlock": "achievement:fourth_prestige",
        "bonus_key": "storage_multiplier",
        "bonus_value": 1.0,
        "mechanic_key": "",
        "snap_horiz_stars": [10, 15],
        # Star 16 (the strap chain's far end) must end up on the +X
        # (trailing right) side after leveling — see the Archon's
        # matching comment and get_canonical_display_basis().
        "snap_orient_check": {"star": 16, "axis": "x", "sign": 1},
        "bonus_levels": {"stars": 2.0, "lines": 3.0, "art": 3.0},
        "spark_cap":      75025,
        "line_threshold": 0.3819,   # 28,657 / 75,025

        # Debussy, Clair de Lune — opening 17 notes (events 0-16), the
        # phrase that ends right as it begins echoing itself (F4-G#4
        # recurs at event 16, then diverges). 7 distinct pitch classes.
        "puzzle_sequence": [0, 1, 0, 1, 0, 1, 2, 0, 3, 4, 5, 6, 2, 0, 5, 6, 0],
        "note_freqs": [
            349.23,  # 0: F4
            415.30,  # 1: G#4
            554.37,  # 2: C#5
            369.99,  # 3: F#4
            440.00,  # 4: A4
            523.25,  # 5: C5
            622.25,  # 6: D#5
        ],
        # Response phrase: events 17-32, the material between the first
        # echo of the opening and the next full cycle point.
        "response_freqs": [
            415.30, 466.16, 554.37, 523.25, 622.25, 554.37, 466.16,
            698.46, 554.37, 311.13, 369.99, 415.30, 523.25, 466.16,
            554.37, 523.25,
        ],
        # TODO (Boss): note_durations not yet designed — placeholder below.
        "note_durations": [
            0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25,
            0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25,
        ],

        "fixed_star_positions": [
            [ 0.0286,  0.0460, 0.9985],  # 0
            [-0.1106,  0.0460, 0.9928],  # 1
            [-0.1250,  0.0004, 0.9922],  # 2
            [ 0.0286, -0.0020, 0.9996],  # 3
            [ 0.0782,  0.0400, 0.9961],  # 4
            [-0.0090, -0.0272, 0.9996],  # 5
            [-0.0790, -0.0240, 0.9966],  # 6
            [ 0.0730, -0.0560, 0.9958],  # 7
            [-0.0510, -0.0011, 0.9987],  # 8
            [-0.0690,  0.0460, 0.9966],  # 9
            [-0.1010, -0.0440, 0.9939],  # 10
            [-0.0738, -0.0508, 0.9960],  # 11
            [-0.0310, -0.0528, 0.9981],  # 12
            [ 0.0230, -0.0508, 0.9984],  # 13
            [ 0.0730, -0.0200, 0.9971],  # 14
            [ 0.1090, -0.0240, 0.9938],  # 15
            [ 0.1250,  0.0100, 0.9921],  # 16
        ],

        "line_pairs": [
            1,2, 2,8, 8,3, 3,0, 0,9, 9,1,
            2,6, 6,5, 5,14, 14,3,
            4,0, 14,4,
            6,10, 10,11, 11,12, 12,13, 13,7, 7,15, 15,16, 16,14,
        ],
    },


# ==================================================
# CONSTELLATION 5-5: DAJALA, THE BELLOWS
# ==================================================

    {
        "id": 4,
        "name": "The Bellows",
        "designation": "DAJALA",
        "octant": 4,
        "star_count": 18,
        "unlock": "achievement:fifth_prestige",
        "bonus_key": "click_volition_multiplier",
        "bonus_value": 1.0,
        "mechanic_key": "",
        "snap_horiz_stars": [4, 9],
        # Star 4 (the nozzle tip) must end up on the +X (right) side
        # after leveling, matching the authored layout's own comment
        # below ("nozzle points right") — see the Archon's matching
        # comment and get_canonical_display_basis().
        "snap_orient_check": {"star": 4, "axis": "x", "sign": 1},
        "bonus_levels": {"stars": 1.5, "lines": 2.0, "art": 3.0},
        "spark_cap":      75025,
        "line_threshold": 0.3819,   # 28,657 / 75,025

        # Marriage of Figaro Overture (Mozart) — Clarinet in Bb part, first 18 notes.
        # Bb clarinet transposition applied (written pitch - 2 semitones = sounding pitch).
        # 7 distinct sounding pitches across 18 note-events.
        # notes-played = stars puzzle (same mechanic as The Satchel).
        # Index 0=G#3, 1=G3, 2=A#3, 3=C4, 4=C#4, 5=D#4, 6=D4
        "puzzle_sequence": [0, 1, 0, 1, 0, 0, 1, 0, 2, 3, 2, 3, 4, 5, 6, 5, 6, 5],
        "note_freqs": [
            207.65,  # 0: G#3
            196.00,  # 1: G3
            233.08,  # 2: A#3
            261.63,  # 3: C4
            277.18,  # 4: C#4
            311.13,  # 5: D#4
            293.66,  # 6: D4
        ],
        # Durations quadrupled from raw MIDI (0.1173s→0.4692, 0.2190s→0.8760)
        # so the repeating figure is memorable rather than flickering past.
        "note_durations": [
            0.4692, 0.4692, 0.4692, 0.4692, 0.8760,  # phrase 1: G#G G#G G#(long)
            0.4692, 0.4692, 0.4692,                   # phrase 2 start: G#G G#
            0.4692, 0.4692, 0.4692, 0.4692,           # ascending: A# C A# C
            0.4692, 0.4692, 0.4692, 0.4692, 0.4692,   # ascending cont.: C# D# D D# D
            0.8760,                                    # D#(long) — phrase close
        ],
        # Response: notes 18-42 of the Figaro overture (25 notes),
        # the chromatic descent and resolution back to G#3.
        "response_freqs": [
            311.13, 293.66, 311.13, 329.63, 349.23,  # D#4 D4 D#4 E4 F4
            311.13, 277.18, 261.63, 233.08, 220.00,  # D#4 C#4 C4 A#3 A3
            233.08, 261.63, 277.18, 261.63, 233.08,  # A#3 C4 C#4 C4 A#3
            207.65, 196.00, 207.65, 233.08, 207.65,  # G#3 G3 G#3 A#3 G#3
            196.00, 155.56, 174.61, 196.00, 207.65,  # G3 D#3 F3 G3 G#3(held resolve)
        ],

        # Bellows shape rotated 90° CW: nozzle points right, pleated left edge,
        # handle arms extend to upper-left and lower-left.
        # Stars 0-3: unconnected air particles streaming from nozzle tip.
        #   0,1: inline on center line rightward from tip.
        #   2,3: fork above/below star 1.
        # Stars 4-17: connected bellows body.
        #   4:     nozzle tip
        #   5,6:   shaft-far (top/bottom, near tip)
        #   7,8:   shaft-near (top/bottom, near valve)
        #   9,10:  valve/shoulder (top/bottom)
        #   11,12: handle ends (top/bottom, outermost left)
        #   13,17: pleat outer tips (top/bottom)
        #   14,16: pleat insets (top/bottom)
        #   15:    pleat center tip (leftmost point)
        "fixed_star_positions": [
            [ 0.1080,  0.0000, 0.9942],  #  0: air-1 — inline right of tip
            [ 0.1230,  0.0000, 0.9924],  #  1: air-2 — inline right of 0
            [ 0.1300,  0.0220, 0.9904],  #  2: air-3 — above-right of 1
            [ 0.1300, -0.0220, 0.9904],  #  3: air-4 — below-right of 1
            [ 0.0600,  0.0000, 0.9982],  #  4: nozzle tip
            [ 0.0440,  0.0110, 0.9990],  #  5: shaft-top-far
            [ 0.0440, -0.0110, 0.9990],  #  6: shaft-bot-far
            [ 0.0050,  0.0230, 0.9997],  #  7: shaft-top-near
            [ 0.0050, -0.0230, 0.9997],  #  8: shaft-bot-near
            [-0.0420,  0.0380, 0.9984],  #  9: valve-top
            [-0.0420, -0.0380, 0.9984],  # 10: valve-bot
            [-0.0984,  0.0480, 0.9940],  # 11: handle-top
            [-0.0984, -0.0480, 0.9940],  # 12: handle-bot
            [-0.0702,  0.0430, 0.9966],  # 13: pleat-tip1 (top) — midpoint of 9-11
            [-0.0459,  0.0180, 0.9988],  # 14: pleat-inset1
            [-0.0713,  0.0000, 0.9975],  # 15: pleat-tip2 (center)
            [-0.0459, -0.0180, 0.9988],  # 16: pleat-inset2
            [-0.0702, -0.0430, 0.9966],  # 17: pleat-tip3 (bottom) — midpoint of 10-12
        ],

        # Stars 0-3 are unconnected (air particles).
        # Connected outline: body top edge, body bottom edge, handle arms,
        # valve-to-pleat connections, pleat interior zigzag.
        # 14 line segments total.
        "line_pairs": [
            9,7,   7,5,   5,4,          # body top edge: valve→shaft-near→shaft-far→tip
            4,6,   6,8,   8,10,         # body bottom edge: tip→shaft-far→shaft-near→valve
            9,13,  13,11,               # top edge continues: valve→pleat-tip1→handle
            10,17, 17,12,               # bottom edge continues: valve→pleat-tip3→handle
            13,14, 14,15, 15,16, 16,17, # pleat interior zigzag
        ],
    },


# ==================================================
# CONSTELLATION 6-6: THE DJINN
# ==================================================
# The Player's own constellation. Themed around the vessel (Ring, Jar, Lamp,
# etc.) the player favored during the pre-game intro's training-period
# selection — one art/lore variant is intended per vessel choice, not yet
# designed. Bonus is meant to ease the Constellation Endowment bottleneck
# directly so Mid-Game reads as reasonably attainable. Designation "ENIGMA"
# is deliberate: the Djinn's true form is undecided at this stage of design.
#
# TODO (Boss): placeholder/incomplete —
#   - puzzle_sequence/note_freqs has only 15 of the 17 note-events star_count
#     needs; indices 15-16 are unwritten (source melody: C4 G4 C5 E4 G4 C5
#     C4 E5 G3 G4 C5 D#5 C4 D#4 G3).
#   - response_freqs below stores the "drums alternate C3/D3" percussion
#     pattern as given, but response_freqs elsewhere in this file is a
#     melodic echo phrase, not a drum voice — may deserve its own field
#     once a real percussion channel exists (see the unused `perc` voice on
#     PuzzleSequenceResource in puzzle_sequence_resource.gd). Array length
#     (17) is arbitrary/placeholder since no exact count was given.
#   - fixed_star_positions / line_pairs not yet designed — pending the
#     per-vessel art choice.
#   - unlock is "achievement:fifth_prestige", identical to The Bellows (id
#     4)'s unlock key — confirm whether that's intentional (parallel
#     unlock, different octant) or should instead key off the intro
#     vessel-choice event.

    {
        "id": 5,
        "name": "The Djinn",
        "designation": "ENIGMA",
        "octant": 5,
        "star_count": 17,
        "unlock": "achievement:fifth_prestige",
        "bonus_key": "endowment_multiplier",
        "bonus_value": 1.0,
        "mechanic_key": "",
        "snap_horiz_stars": [1, 2],
        "bonus_levels": {"stars": 1.5, "lines": 2.0, "art": 3.0},
        "spark_cap":      75025,
        "line_threshold": 0.3819,   # 28,657 / 75,025

        # 15 of 17 note-events (see TODO above).
        # C4 G4 C5 E4 G4 C5 C4 E5 G3 G4 C5 D#5 C4 D#4 G3
        "puzzle_sequence": [0, 1, 2, 3, 1, 2, 0, 4, 5, 1, 2, 6, 0, 7, 5],
        "note_freqs": [
            261.63,  # 0: C4
            392.00,  # 1: G4
            523.25,  # 2: C5
            329.63,  # 3: E4
            659.26,  # 4: E5
            196.00,  # 5: G3
            622.25,  # 6: D#5
            311.13,  # 7: D#4
        ],
        # TODO (Boss): placeholder durations, uniform until real timing is set.
        "note_durations": [
            0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25,
            0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25,
        ],
        # Drum voice: alternates C3/D3 consistently (see TODO above re: field fit).
        "response_freqs": [
            130.81, 146.83, 130.81, 146.83, 130.81, 146.83, 130.81,
            146.83, 130.81, 146.83, 130.81, 146.83, 130.81, 146.83,
            130.81, 146.83, 130.81,
        ],

        # fixed_star_positions / line_pairs: pending per-vessel art design.
    },


# IDs 6-16: reserved for future built-in constellations
]
 
const PATRON_DATA_PATH = "res://data/patron_constellations.json"
 
 
# ==================================================
# SPARK FRACTION THRESHOLDS
# ==================================================
# stars:  fraction >= THRESHOLD_STARS  → stars visible
# lines:  fraction >= line_threshold   → connecting lines (per constellation)
# art:    fraction >= THRESHOLD_ART    → figure art visible
const THRESHOLD_STARS: float = 0.1457   # 10,946 / 75,025
const THRESHOLD_ART:   float = 0.85     # ~63,771 / 75,025
 
# DEV: SPARK_CAP_BASE is the TOTAL spark investment cap for a complete
# Early-game constellation — NOT a per-star figure. The Archon (10 stars)
# and a 5-star constellation share the same 75025 cap; star_count governs
# geometry only, not capacity. get_spark_cap() multiplies by star_count for
# later or custom constellations that are explicitly designed to scale — do
# NOT rely on that return value for Early-game built-in ids 0-15 unless
# their definition carries a custom "spark_cap" field that overrides it.
const SPARK_CAP_BASE:  float = 75025.0
 
 
# ==================================================
# PUZZLE CONSTANTS
# ==================================================
# 7 pitches for the HOTMK call phrase (A minor, octave 4-5).
# C and C# are treated as one star (C natural used throughout).
# Eb and D# are the same pitch — star clicked twice in sequence.
# Order: A, B, C, D, Eb/D#, E, F
const PUZZLE_NOTE_FREQS: Array = [
    246.94,   # 0: B3
    277.18,   # 1: C#4
    293.66,   # 2: D4
    311.13,   # 3: Eb4
    329.63,   # 4: E4
    349.23,   # 5: E#4  (F natural)
    369.99,   # 6: F#4
    261.63,   # 7: C4
]
 
# Call phrase (13 notes): A B C D E C Eb Eb D C D A F
const PUZZLE_CALL_SEQUENCE: Array = [0, 1, 2, 4, 6, 2, 6, 5, 1, 4, 3, 7, 4]
 
 
 
# Response/success motif (13 notes, played by the game on completion).
# ** VERIFY AGAINST THE GRIEG SCORE — approximate. **
# F  G  F  E  D  C#  D  B  C  A  D  C  A
const PUZZLE_RESPONSE_FREQS: Array = [
    369.99, # F#
    415.30, # G#
    466.16, # A#
    493.88, # B
    554.37, # C#
    466.16, # A#
    554.37, # C#
 
    587.33, # D
    466.16, # A#
    587.33, # D
 
    554.37, # C#
    466.16, # A#
    554.37  # C#
]
 
# Cumulative spark fraction targets after each puzzle completion.
# 1st solve → "stars" (cooldown ×0.5)
# 2nd solve → "lines" (cooldown ×0.25)
# 3rd solve → "art"   (cooldown ×0.1)
 
 
# ==================================================
# RUNTIME STATE
# ==================================================
var player_seed:            int        = 0
var active_per_octant:      Array      = [-1, -1, -1, -1, -1, -1, -1, -1]
var unlocked:               Array      = []
var player_constellations:  Array      = []
var patron_constellations:  Array      = []
var active_mechanic_unlocks: Array     = []
var _star_positions_cache:  Dictionary = {}
var _game_context:          Node       = null
var _last_selected_id:      int        = -1
var _puzzle_cache:          Dictionary = {}   # keyed by constellation_id string -> cache dict
 
 
# ==================================================
# READY
# ==================================================
func _ready() -> void:
    _game_context = get_node_or_null("/root/GameContext")
    _load_patron_constellations()


# ==================================================
# SEED AND STAR POSITION GENERATION
# ==================================================
func set_player_seed(genesis: int) -> void:
    player_seed = genesis
    _star_positions_cache.clear()
 
 
func get_star_positions(constellation_id: int) -> Array:
    if _star_positions_cache.has(constellation_id):
        return _star_positions_cache[constellation_id]

    var def: Dictionary = get_constellation_def(constellation_id)
    if def.is_empty():
        return []

    var octant: int         = def.get("octant", 0)
    var center_dir: Vector3 = _get_constellation_center_dir(constellation_id, octant)
    var roll: float         = _get_constellation_roll(constellation_id)

    if def.has("fixed_star_positions"):
        # Fixed/designed constellations: author positions in local z-forward
        # space, then transform to the player's seeded world placement.
        var fixed_positions: Array = []
        for raw in def["fixed_star_positions"]:
            var local_pos: Vector3 = Vector3(raw[0], raw[1], raw[2]).normalized()
            fixed_positions.append(_apply_constellation_transform(local_pos, center_dir, roll))
        _star_positions_cache[constellation_id] = fixed_positions
        return fixed_positions

    # Procedural: scatter stars in a tight cluster around center_dir.
    # dot > 0.95 confines stars to within ~18° of center — distinct enough
    # to read as a cluster when multiple constellations share the same octant.
    var star_count: int = def.get("star_count", 5)
    var rng := RandomNumberGenerator.new()
    rng.seed = player_seed ^ (constellation_id * 2654435761)

    var positions: Array = []
    var attempts:  int   = 0
    while positions.size() < star_count and attempts < star_count * 20:
        attempts += 1
        var theta: float = rng.randf() * TAU
        var phi:   float = acos(rng.randf_range(-1.0, 1.0))
        var pos := Vector3(
            sin(phi) * cos(theta),
            cos(phi),
            sin(phi) * sin(theta)
        )
        if pos.dot(center_dir) > 0.95:
            positions.append(pos.normalized())

    _star_positions_cache[constellation_id] = positions
    return positions


# ------------------------------------------------------------------
# Returns a seeded center direction for this constellation within
# its octant. Every player gets a unique sub-octant layout; every
# constellation within the same octant lands in a distinct position.
#
# max_spread (25°) keeps all positions at least 10° inside the
# octant boundary (~35.3° from octant center), preventing bleed
# across octant edges.
#
# TODO: When multiple constellations share an octant, add minimum-
# separation enforcement here before shipping 8-per-octant content.
# ------------------------------------------------------------------
func _get_constellation_center_dir(constellation_id: int, octant: int) -> Vector3:
    var rng := RandomNumberGenerator.new()
    rng.seed = player_seed ^ (constellation_id * 0x45D9F3B7)

    var octant_dir: Vector3 = OCTANTS[octant]["dir"]

    # Build a local tangent frame at the octant center direction
    var ref: Vector3     = Vector3.UP if absf(octant_dir.y) < 0.99 else Vector3.RIGHT
    var local_x: Vector3 = ref.cross(octant_dir).normalized()
    var local_y: Vector3 = octant_dir.cross(local_x).normalized()

    # Seeded polar coords: azimuth sweeps full circle, radius stays in safe zone
    var azimuth: float    = rng.randf() * TAU
    var max_spread: float = deg_to_rad(25.0)
    var radius: float     = rng.randf_range(0.0, max_spread)

    # Rotate octant_dir by radius toward the seeded azimuth direction
    var tangent: Vector3 = (cos(azimuth) * local_x + sin(azimuth) * local_y).normalized()
    return (cos(radius) * octant_dir + sin(radius) * tangent).normalized()


# ------------------------------------------------------------------
# Returns a seeded roll angle (0..TAU) around the constellation's
# center direction axis. Gives each player a uniquely-oriented
# shape for every constellation — even built-ins with fixed geometry.
# ------------------------------------------------------------------
func _get_constellation_roll(constellation_id: int) -> float:
    var rng := RandomNumberGenerator.new()
    rng.seed = player_seed ^ (constellation_id * 0x8DA6B343)
    return rng.randf() * TAU


# ------------------------------------------------------------------
# Transforms a star from local constellation space (authored with
# z ≈ 1 pointing forward) to world space, centering it on
# center_dir and applying the roll rotation around that axis.
# Preserves angular spread between stars, so panel display sizing
# constraints on fixed_star_positions remain valid after transform.
# ------------------------------------------------------------------
func _apply_constellation_transform(local_pos: Vector3, center_dir: Vector3, roll: float) -> Vector3:
    # Build the shortest-arc basis rotating (0,0,1) onto center_dir
    var from: Vector3 = Vector3(0.0, 0.0, 1.0)
    var basis: Basis
    var axis: Vector3 = from.cross(center_dir)
    if axis.length_squared() < 0.0001:
        # Parallel or antiparallel — handle both edge cases cleanly
        basis = Basis.IDENTITY if from.dot(center_dir) > 0.0 else Basis(Vector3.RIGHT, PI)
    else:
        basis = Basis(axis.normalized(), from.angle_to(center_dir))

    # Apply seeded roll around the center direction after placement
    basis = Basis(center_dir, roll) * basis

    return (basis * local_pos).normalized()


# ------------------------------------------------------------------
# Returns the "camera-to-world" basis that shows a constellation in its
# designed canonical orientation — the same basis both
# starfield_background.gd's snap_to_constellation() (whirl animation
# target) and constellation_study_overlay.gd's map projection use, so the
# two surfaces always agree.
#
# Leveling snap_horiz_stars only fixes rotation mod 180° — there are
# always two candidate rolls that both make that pair horizontal, one
# correct and one upside-down/mirrored. snap_orient_check (optional,
# added per-constellation only where the shape actually needs
# disambiguating — see e.g. the Archon's def) picks between them: a
# reference star must land on a specific side (+/-X or +/-Y) of the
# leveled view once the roll is applied, checked here via Basis/Vector3
# ops directly rather than hand-derived trig.
# ------------------------------------------------------------------
func get_canonical_display_basis(constellation_id: int) -> Basis:
    var positions: Array = get_star_positions(constellation_id)
    if positions.is_empty():
        return Basis.IDENTITY

    var centroid := Vector3.ZERO
    for pos in positions:
        centroid += pos as Vector3
    if centroid == Vector3.ZERO:
        return Basis.IDENTITY
    centroid = centroid.normalized()

    var from_dir := Vector3(0.0, 0.0, 1.0)
    var base_rot: Basis
    var base_axis: Vector3 = from_dir.cross(centroid)
    if base_axis.length_squared() < 0.0001:
        base_rot = Basis.IDENTITY if from_dir.dot(centroid) > 0.0 else Basis(Vector3.RIGHT, PI)
    else:
        base_rot = Basis(base_axis.normalized(), from_dir.angle_to(centroid))

    var def: Dictionary = get_constellation_def(constellation_id)
    var horiz_stars: Array = def.get("snap_horiz_stars", [])
    var roll_angle: float = 0.0
    if horiz_stars.size() == 2 and horiz_stars[0] < positions.size() and horiz_stars[1] < positions.size():
        var star_a: Vector3 = positions[horiz_stars[0]]
        var star_b: Vector3 = positions[horiz_stars[1]]
        var a_view: Vector3 = base_rot.inverse() * star_a
        var b_view: Vector3 = base_rot.inverse() * star_b
        var dy: float = b_view.y - a_view.y
        var dx: float = b_view.x - a_view.x
        var line_angle: float = atan2(dy, dx)
        roll_angle = line_angle
        if roll_angle > PI * 0.5:
            roll_angle -= PI
        elif roll_angle < -PI * 0.5:
            roll_angle += PI

        var check: Dictionary = def.get("snap_orient_check", {})
        if check.has("star") and int(check["star"]) < positions.size():
            var candidate: Basis = base_rot * Basis(Vector3(0.0, 0.0, 1.0), roll_angle)
            var ref_view: Vector3 = candidate.inverse() * (positions[int(check["star"])] as Vector3)
            var value: float = ref_view.y if str(check.get("axis", "y")) == "y" else ref_view.x
            var wanted_sign: int = int(check.get("sign", 1))
            if signf(value) != 0.0 and signf(value) != signf(float(wanted_sign)):
                roll_angle += PI

    return base_rot * Basis(Vector3(0.0, 0.0, 1.0), roll_angle)


# ==================================================
# CONSTELLATION LOOKUP
# ==================================================
func get_constellation_def(id: int) -> Dictionary:
    for c in BUILT_IN:
        if c["id"] == id:
            return c
    for c in player_constellations:
        if c["id"] == id:
            return c
    for c in patron_constellations:
        if c.get("approved", false) and c["id"] == id:
            return c
    return {}
 
 
func get_constellations_in_octant(octant: int) -> Array:
    var result: Array = []
    for c in BUILT_IN:
        if c["octant"] == octant and unlocked.has(c["id"]):
            result.append(c)
    for c in player_constellations:
        if c["octant"] == octant and unlocked.has(c["id"]):
            result.append(c)
    for c in patron_constellations:
        if c.get("approved", false) and c["octant"] == octant and unlocked.has(c["id"]):
            result.append(c)
    return result
 
 
# ==================================================
# UNLOCK SYSTEM
# ==================================================
func _unlock_constellation(id: int) -> void:
    if unlocked.has(id):
        return
    unlocked.append(id)
    # Ensure spark total key exists for this constellation
    if _game_context:
        var key := str(id)
        if not _game_context.constellation_spark_totals.has(key):
            _game_context.constellation_spark_totals[key] = 0.0
    emit_signal("constellation_unlocked", id)
    if _game_context:
        _game_context.ui_unlocks["constellation"] = true
        
    var def: Dictionary = get_constellation_def(id)
    var mechanic: String = def.get("mechanic_key", "")
    if mechanic != "" and not active_mechanic_unlocks.has(mechanic):
        active_mechanic_unlocks.append(mechanic)
        emit_signal("mechanic_unlocked", mechanic)
 
 
func on_achievement(key: String) -> void:
    for c in BUILT_IN:
        var condition: String = c.get("unlock", "")
        if condition == "achievement:" + key:
            _unlock_constellation(c["id"])
    if key == "archon_volition_constellation":
        _unlock_constellation(1)  # Unlock The Spark (id 1)
    if key == "no_archon_volition_constellation":
        _unlock_constellation(1)  # Unlock The Spark (id 1)
    _check_chain_unlocks()
 
 
func _check_chain_unlocks() -> void:
    for c in BUILT_IN:
        var condition: String = c.get("unlock", "")
        if condition.begins_with("constellation:"):
            var required_id: int = condition.split(":")[1].to_int()
            if unlocked.has(required_id):
                _unlock_constellation(c["id"])
 
 
func _check_stat_unlocks() -> void:
    if not _game_context:
        return
    for c in BUILT_IN:
        if unlocked.has(c["id"]):
            continue
        var condition: String = c.get("unlock", "")
        if not condition.begins_with("stat:"):
            continue
        var parts: Array = condition.substr(5).split(" ")
        if parts.size() < 3:
            continue
        var field:   String = parts[0]
        var op:      String = parts[1]
        var val:     float  = parts[2].to_float()
        if not _game_context.get(field) != null:
            continue
        var current: float = float(_game_context.get(field))
        var passes:  bool  = false
        if op == ">=" and current >= val:
            passes = true
        elif op == "==" and current == val:
            passes = true
        if passes:
            _unlock_constellation(c["id"])
 
 
# ==================================================
# SPARK FRACTION + VISUAL STATE
# ==================================================
func get_spark_cap(constellation_id: int) -> float:
    var def: Dictionary = get_constellation_def(constellation_id)
    if def.is_empty():
        return SPARK_CAP_BASE
    if def.has("spark_cap"):
        # DEV: Returns the explicit cap directly — NO star_count multiplication.
        # Every Early-game built-in constellation (ids 0–15) carries this field.
        # For The Archon: spark_cap = 75025, full stop. Not 75025 × 10.
        # star_count in the definition is a GEOMETRY-ONLY field (controls
        # procedural star placement). It has zero effect on spark capacity
        # for any constellation that defines spark_cap explicitly.
        return float(def["spark_cap"])
    # DEV: FALLBACK — only reached by future/custom constellations that
    # intentionally omit spark_cap and want capacity to scale with geometry.
    # Never applies to any built-in id 0–15.
    var star_count: int = def.get("star_count", 5)
    return SPARK_CAP_BASE * float(star_count)
 
 
func get_spark_fraction(constellation_id: int) -> float:
    if not _game_context:
        return 0.0
    var cap:   float = get_spark_cap(constellation_id)
    var total: float = _game_context.constellation_spark_totals.get(str(constellation_id), 0.0)
    var result: float = clamp(total / cap, 0.0, 1.0)
    return result
 
 
func get_visual_state(constellation_id: int) -> String:
    if not unlocked.has(constellation_id):
        return "dark"
    var fraction: float = get_spark_fraction(constellation_id)
    if fraction < THRESHOLD_STARS:
        return "dark"
    var def: Dictionary       = get_constellation_def(constellation_id)
    var line_threshold: float = def.get("line_threshold", 0.3)
    if fraction >= THRESHOLD_ART:
        return "art"
    if fraction >= line_threshold:
        return "lines"
    return "stars"
 
 
func get_star_brightness(constellation_id: int) -> float:
    var fraction: float = get_spark_fraction(constellation_id)
    if fraction < THRESHOLD_STARS:
        return 0.0
    var def: Dictionary       = get_constellation_def(constellation_id)
    var line_threshold: float = def.get("line_threshold", 0.3)
    return clamp(
        (fraction - THRESHOLD_STARS) / (line_threshold - THRESHOLD_STARS),
        0.0, 1.0)
 
 
# ==================================================
# ACTIVE CONSTELLATION MANAGEMENT
# ==================================================
func get_active_display_id() -> int:
    # Return the constellation the player most recently selected,
    # falling back to the first occupied octant if nothing selected yet.
    if _last_selected_id != -1:
        return _last_selected_id
    for i in range(8):
        if active_per_octant[i] != -1:
            return active_per_octant[i]
    return -1


func set_display_constellation(constellation_id: int) -> void:
    var def: Dictionary = get_constellation_def(constellation_id)
    if def.is_empty():
        return
    _last_selected_id = constellation_id
    var octant: int = def.get("octant", 0)
    set_active_constellation(octant, constellation_id)
 
 
func set_active_constellation(octant: int, constellation_id: int) -> void:
    if octant < 0 or octant > 7:
        return
    if not unlocked.has(constellation_id) and constellation_id != -1:
        return
    active_per_octant[octant] = constellation_id
    emit_signal("active_constellation_changed", octant, constellation_id)
    _rebuild_active_mechanics()
 
 
func _rebuild_active_mechanics() -> void:
    active_mechanic_unlocks.clear()
    for octant in range(8):
        var id: int = active_per_octant[octant]
        if id == -1:
            continue
        var def: Dictionary  = get_constellation_def(id)
        var mechanic: String = def.get("mechanic_key", "")
        if mechanic != "" and not active_mechanic_unlocks.has(mechanic):
            active_mechanic_unlocks.append(mechanic)
            emit_signal("mechanic_unlocked", mechanic)
 
 
# ==================================================
# BONUS QUERY
# ==================================================
func get_active_bonus(bonus_key: String) -> float:
    var total: float = 0.0
    for octant in range(8):
        var id: int = active_per_octant[octant]
        if id == -1:
            continue
        var def: Dictionary = get_constellation_def(id)
        if def.get("bonus_key", "") == bonus_key:
            total += def.get("bonus_value", 0.0)
    return total
 
 
func get_active_level_bonus(bonus_key: String) -> float:
    # cooldown_multiplier: lower is better (want minimum, base 1.0)
    # All other level bonuses: higher is better (want maximum, base 1.0)
    var minimize: bool = (bonus_key == "cooldown_multiplier")
    var best: float = 1.0
    for octant in range(8):
        var id: int = active_per_octant[octant]
        if id == -1:
            continue
        var def: Dictionary = get_constellation_def(id)
        if def.get("bonus_key", "") != bonus_key:
            continue
        if not def.has("bonus_levels"):
            continue
        if _game_context:
            var solve_key: String = "constellation_%d_solve_count" % id
            if _game_context.assignments.get(solve_key, 0) < 1:
                continue
            if not _game_context.has_volition_for_constellation(id):
                continue
        var state:  String     = get_visual_state(id)
        var levels: Dictionary = def["bonus_levels"]
        var val:    float      = levels.get(state, 1.0)
        if minimize:
            if val < best:
                best = val
        else:
            if val > best:
                best = val
    return best
 
 
func get_bonus_volition_grant() -> int:
    # Returns 0/1/2/3 Bonus Volitions per Normal Volition, sourced from the
    # Archon (id 0) — bonus_volitions is permanently exclusive to the Archon
    # by design, so this reads it directly rather than scanning all octants.
    # Requires: Archon active in its octant, solved, AND self-activated
    # (a Normal Volition assigned to the Archon itself).
    const ARCHON_ID: int = 0
    if active_per_octant[0] != ARCHON_ID:
        return 0
    var def: Dictionary = get_constellation_def(ARCHON_ID)
    if not def.has("bonus_levels"):
        return 0
    if _game_context:
        var solve_key: String = "constellation_%d_solve_count" % ARCHON_ID
        if _game_context.assignments.get(solve_key, 0) < 1:
            return 0
        if not _game_context.has_parent_volition_for_constellation(ARCHON_ID):
            return 0
    var state:  String     = get_visual_state(ARCHON_ID)
    var levels: Dictionary = def["bonus_levels"]
    return int(levels.get(state, 0))
 
 
func has_mechanic_unlock(mechanic_key: String) -> bool:
    return active_mechanic_unlocks.has(mechanic_key)
 
 
# ==================================================
# PUZZLE HELPERS
# ==================================================
func get_puzzle_hint_direction() -> Vector3:
    var target_id: int = get_active_display_id()
    if target_id == -1:
        return Vector3.ZERO
    var positions: Array = get_star_positions(target_id)
    if positions.is_empty():
        return Vector3.ZERO
    var centroid := Vector3.ZERO
    for pos in positions:
        centroid += pos
    return (centroid / float(positions.size())).normalized()
 
 
func get_note_freqs(constellation_id: int) -> Array:
    var def: Dictionary = get_constellation_def(constellation_id)
    return def.get("note_freqs", PUZZLE_NOTE_FREQS)
 
 
func get_response_freqs(constellation_id: int) -> Array:
    var def: Dictionary = get_constellation_def(constellation_id)
    return def.get("response_freqs", PUZZLE_RESPONSE_FREQS)
 
 
func get_note_assignment(constellation_id: int) -> Array:
    var def:        Dictionary = get_constellation_def(constellation_id)
    var freqs:      Array      = get_note_freqs(constellation_id)
    var star_count: int        = def.get("star_count", freqs.size())
    var puzzle_seq: Array      = def.get("puzzle_sequence", [])
    var assignment: Array      = []
    assignment.resize(star_count)

    if puzzle_seq.size() == star_count:
        # Use puzzle_sequence as assignment if it matches star count (Hourglass)
        for i in star_count:
            assignment[i] = puzzle_seq[i]
    elif star_count == freqs.size():
        # 1:1 star-to-pitch: use range (Archon, Spark)
        assignment = range(freqs.size())
    else:
        # More stars than pitches: round-robin assignment (Satchel)
        for i in star_count:
            assignment[i] = i % freqs.size()

    var rng := RandomNumberGenerator.new()
    rng.seed = player_seed ^ (constellation_id * 0x9E3779B9)
    for i in range(assignment.size() - 1, 0, -1):
        var j: int = rng.randi_range(0, i)
        var tmp    = assignment[i]
        assignment[i] = assignment[j]
        assignment[j] = tmp
    return assignment
 
 
# ==================================================
# PATRON CONSTELLATION LOADING
# ==================================================
func _load_patron_constellations() -> void:
    if not FileAccess.file_exists(PATRON_DATA_PATH):
        return
    var file = FileAccess.open(PATRON_DATA_PATH, FileAccess.READ)
    if not file:
        return
    var json := JSON.new()
    var err:   int = json.parse(file.get_as_text())
    file.close()
    if err != OK:
        push_warning("ConstellationData: failed to parse patron_constellations.json")
        return
    var data = json.get_data()
    if data is Array:
        patron_constellations = data
 
 
# ==================================================
# SAVE / LOAD
# ==================================================
func get_save_data() -> Dictionary:
    return {
        "player_seed":           player_seed,
        "active_per_octant":     active_per_octant,
        "last_selected_id":      _last_selected_id,
        "unlocked":              unlocked,
        "player_constellations": player_constellations,
        "puzzle_cache":          _puzzle_cache,
    }


func load_save_data(data: Dictionary) -> void:
    player_seed           = data.get("player_seed", randi())
    var _raw_apo = data.get("active_per_octant", [-1,-1,-1,-1,-1,-1,-1,-1])
    active_per_octant = []
    for v in _raw_apo:
        active_per_octant.append(int(v))
    _last_selected_id     = data.get("last_selected_id", -1)
    player_constellations = data.get("player_constellations", [])
    _star_positions_cache.clear()
    unlocked = []
    for id in data.get("unlocked", [0]):
        _unlock_constellation(id)
    _rebuild_active_mechanics()
    _puzzle_cache = data.get("puzzle_cache", {})


func get_puzzle_cache(p_constellation_id: int) -> Dictionary:
    var key: String = str(p_constellation_id)
    var untyped = _puzzle_cache.get(key, {})
    return untyped if typeof(untyped) == TYPE_DICTIONARY else {}


func set_puzzle_cache(p_constellation_id: int, cache_dict: Dictionary) -> void:
    _puzzle_cache[str(p_constellation_id)] = cache_dict


func clear_puzzle_cache(p_constellation_id: int) -> void:
    var key: String = str(p_constellation_id)
    if _puzzle_cache.has(key):
        _puzzle_cache.erase(key)


func get_puzzle_star_colors(p_constellation_id: int) -> Array:
    var cache: Dictionary = get_puzzle_cache(p_constellation_id)
    if cache.is_empty():
        return []
    var untyped = cache.get("star_colors", [])
    return untyped if typeof(untyped) == TYPE_ARRAY else []


func get_player_name_assignments(p_constellation_id: int) -> Array:
    var cache: Dictionary = get_puzzle_cache(p_constellation_id)
    if cache.is_empty():
        return []
    var untyped = cache.get("player_name_assignments", [])
    return untyped if typeof(untyped) == TYPE_ARRAY else []


func set_player_name_assignments(p_constellation_id: int, assignments: Array) -> void:
    var key: String = str(p_constellation_id)
    if not _puzzle_cache.has(key):
        return
    _puzzle_cache[key]["player_name_assignments"] = assignments


func get_player_puzzle_notes(p_constellation_id: int) -> Dictionary:
    var cache: Dictionary = get_puzzle_cache(p_constellation_id)
    if cache.is_empty():
        return {}
    var untyped = cache.get("player_puzzle_notes", {})
    return untyped if typeof(untyped) == TYPE_DICTIONARY else {}


func set_player_puzzle_notes(p_constellation_id: int, notes: Dictionary) -> void:
    var key: String = str(p_constellation_id)
    if not _puzzle_cache.has(key):
        return
    _puzzle_cache[key]["player_puzzle_notes"] = notes


# ==================================================
# PROCESS — stat-based unlock polling
# ==================================================
func _process(_delta: float) -> void:
    _check_stat_unlocks()
