# Djinncremental — project instructions

Read `docs/SYSDOC_overview.md` first for design intent and the system map; then read the
source for whatever you are about to touch. The doc is a map, not evidence.

## Core design intentions

- **Reduce menu switching** (author, 2026-10-28). A control the player needs while
  working in a popup or panel belongs where they are working, not only on a distant bar
  or another tab. When a setting or action is used from several surfaces, put it on each,
  backed by ONE shared setting/handler so every surface stays in step, and redraw in
  place rather than closing what the player is in. Prefer this over adding a tab, mode
  or menu hop. Example: the Constellation puzzle's `Classic / Checks` Entry switch, on
  the Markers bar and in the Star Map and Staff popups (`toggle_entry_mode()` in
  `constellation_puzzle_widgets.gd`). See SysDoc §1.
