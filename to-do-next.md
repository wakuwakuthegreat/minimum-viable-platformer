# to-do-next

Follow-ups from the last review pass. Everything below is fresh scope, not a
rehash of what shipped in the earlier clusters.

## 1. Combo popups — non-blocking, off-center

- `combo_system.gd::_spawn_popup` puts labels in the middle of the screen and
  they can steal input from the pause / touch controls beneath them.
- Fix:
  - `label.mouse_filter = Control.MOUSE_FILTER_IGNORE` on both the popup and
    (if introduced) any wrapping Control.
  - Set `ComboSystem`'s CanvasLayer `mouse_filter` to IGNORE too so the layer
    itself never eats clicks.
  - Offset target position: for stomps, pin above the player head (world_pos +
    `Vector2(0, -180)` before the canvas transform). For air summaries, pin to
    the top-right corner (screen-space, e.g. `Vector2(viewport.x - 320, 120)`)
    instead of `player.global_position - (0,120)`.
- Verify: die while a combo popup is on screen; retry button must still be
  clickable. On mobile, jump button under the popup must still respond.

## 2. Font select — immediate randomization on purchase

- Currently the player has to open Settings and pick a font. Requested: buying
  the `font_select` upgrade should immediately change the default UI font to a
  random file from `assets/fonts/`.
- Approach: in `skills_db.gd::purchase` (or wherever purchases finalize), after
  `Global.grant(fkey)` for `font_select`, do:
  ```gdscript
  var fonts = _list_fonts_static()  # duplicate of settings.gd::_list_fonts
  if fonts.size() > 0:
      var pick = fonts[randi() % fonts.size()].get_file()
      Global.settings_cfg["font_choice"] = pick
      Global.save_state()
  ```
- Consider extracting the font enumeration into a shared helper (e.g.
  `FontRegistry.list()` autoload or a static in `ui_theme.gd`) so both
  Settings' dropdown and this purchase hook share one code path.
- Verify: fresh save → buy Font Select → back to main menu → title label uses
  a randomly chosen font.

## 3. Shop detail panel — owned toggle overflows

- When a skill is purchased the `_d_toggle` CheckBox with its long label
  ("Feature active (uncheck to disable without losing progress)") pushes the
  detail panel out of bounds. The Scroll wrap from cluster 4 helps vertically
  but the label text still clips horizontally.
- Fix:
  - `_d_toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART` and
    `size_flags_horizontal = SIZE_EXPAND_FILL`.
  - Consider shortening label to "Feature active" and moving the parenthetical
    into a small Label below it.
  - Verify all four detail label rows (`Name`, `Desc`, `Status`) fit at the
    narrowest panel width the layout allows.
- Also check that the polished CheckBox switch-icon renders inside the scroll
  content area (not clipped by the panel bounds).

## 4. Skill costs — depth-based exponential formula ✅ DONE

- Costs are currently hardcoded per-skill (2/3/4/5). User wants one central
  formula that makes deeper nodes cost exponentially more.
- Suggested implementation in `skills_db.gd`:
  ```gdscript
  const COST_BASE := 1.0
  const COST_MULT := 1.6
  const COST_ROUND := 1  # round to nearest N

  static func compute_cost(skill_id: String) -> int:
      var depth = _depth_from_root(skill_id)
      var raw = COST_BASE * pow(COST_MULT, depth)
      return max(1, int(round(raw / COST_ROUND) * COST_ROUND))

  static func _depth_from_root(skill_id: String) -> int:
      # BFS shortest path over `requires` back to ROOT_ID.
      ...
  ```
- Rewire `can_afford`, the shop UI cost badge, the tree-view badge, and
  `SkillsDB.purchase` to call `compute_cost(sid)` instead of reading
  `d["cost"]`.
- Leave the `cost` dict entries in place as fallback for skills that need
  bespoke pricing (e.g. UI = 1), or delete them and always compute.
- Verify: a leaf like `home_polish` (5 hops from root) costs meaningfully more
  than a first-tier like `hud` (1 hop).

## 5. Lose screen — buttons overflow when everything is unlocked

- `ui.tscn` `Box` (Buy UI, Retry, Shop, Menu, Exit) plus dynamically appended
  Replay / Highscore label / Seed label / Favourite button doesn't fit at
  1280×720 once every unlock is bought.
- Fix:
  - Wrap `Center/Box` in a `ScrollContainer` with `custom_minimum_size = (560,
    600)` and `size_flags_vertical = SHRINK_CENTER`; ScrollContainer clamps to
    the viewport but scrolls beyond.
  - Tighten `Box` `theme_override_constants/separation` from 12 → 8.
  - Reduce dynamic label font sizes (18 → 16) for the seed / highscore rows.
- Alternative: split Retry / Replay-same into a compact HBox pair instead of
  two full-width stacked buttons.

## 6. Main menu — buttons overflow when everything is unlocked

- Buttons visible when fully unlocked:
  Daily · Play · Library · Shop · Stats · Settings · Exit (7 rows @ 64 px +
  separation = ~500 px). Squeezes with the polished title + subtitle above.
- Preferred fix (user's suggestion): once `stats_menu` is unlocked, move
  `Settings` into the TopBar as a gear icon next to `BestLabel`. Same could be
  done for Exit → small "×" corner button.
- Implementation notes:
  - Load a settings glyph (or use unicode "⚙") in a small `Button` sized
    `(48, 48)` with `flat = true`.
  - Hide the full-width Settings button from the main VBox when the icon is
    present, or remove `settings_btn` entirely and rebind on the icon.
  - Add a corresponding shortcut in `_input` so ui_cancel from menu still
    reaches Settings during dev.
- Verify at every unlock milestone: no button gets clipped, TopBar still
  readable, keyboard focus order still makes sense.

## Nice-to-have (deferred)

- Palette live-preview in Settings dropdown (currently only applies after
  reload for some scenes).
- Combo popup uses the currently selected UI font as a fallback when none of
  the funky trio is available (should already work, but add an assert).
- Adaptive-sky curve: currently linear stepping — could ease with `sin(t)` so
  the "midday" phase lingers longer than the transitions.
- Stats menu: paginate deaths_by_cause once it grows past ~10 entries.

---

# Cluster B — 2026-07-07 follow-ups

## B1. Skill tree — spread out and de-tangle layout ✅ DONE

- `skills_db.gd` `tree_pos` values crowd branches together and lines cross a
  lot. Re-space so each branch fans out radially with clear vertical gutters
  between siblings; target no crossing edges below depth 2.
- Keep the data-driven structure: layout still lives in `SKILLS[sid].tree_pos`
  so a designer can nudge single nodes without touching code. Add a top-of-file
  ASCII legend mapping branch → grid quadrant so future edits stay coherent.
- Verify by opening tree at 1280×720 with everything unlocked — no two node
  labels should overlap and no line should pass under a non-parent node.

## B2. Skill tree — dark text on node labels ✅ DONE

- `skill_tree_view.gd::_draw_node` currently uses `ring_col` (which becomes
  white when selected) for the icon glyph, and the label uses a dark brown on
  cream — that part is fine. Bug: the *icon* letters go white on selected
  nodes making them unreadable against light branch colours.
- Always draw icon glyph in dark ink (e.g. `Color(0.12, 0.08, 0.06)`),
  regardless of selection. Selection state stays on the ring only.
- Also audit the cost badge text and any tooltip labels — no light-on-light.

## B3. Settings cog — bigger button, real icon (not emoji) ✅ DONE

- Cluster 6 introduced the gear icon in TopBar sized (48,48) with unicode ⚙.
  Bump to (64,64) minimum and swap the unicode for one of the bundled icons.
- Recommended asset: `assets/icons/hands/delapouite/marble-tap.png` is not a
  cog — instead pick a gear-shaped icon. If none exists in `assets/icons/`,
  approve importing one (e.g. game-icons.net "cog" by Delapouite) rather than
  keeping the emoji. Fallback while sourcing: use `TextureButton` with a
  drawn-in-code cog (16-tooth polygon in `_draw`) so it scales cleanly.
- Also enlarge on hover (+8 px) so the affordance is obvious.

## B4. Skill tree — polished edges (bought via `main_menu_extras` or new skill) ✅ DONE

- `skill_tree_view.gd::_draw` draws `draw_line` straight-lines between nodes.
  When polished UI is unlocked, upgrade to:
  - Bezier curves (draw_polyline with a cubic interpolation between parent →
    child, control points offset perpendicular to the segment).
  - Subtle animated dashed pulse along active (purchased→purchased) edges
    using `Time.get_ticks_msec() * 0.001` as a phase.
  - Soft glow underlay by drawing the same polyline once wider + low-alpha.
- Guard behind `Global.is_unlocked("main_menu_extras")` (or a new
  `skill_tree_polish` skill if we want it separate).

## B5. Skill tree structure — data-first editability ✅ DONE (already dict-driven)

- Confirm `skills_db.gd::SKILLS` remains the single source of truth for id,
  name, desc, requires, branch, tree_pos, icon. It already is — good.
- Add a short header comment block documenting how to add a new skill in ≤6
  lines (dict literal + tree_pos advice + which branch colours exist).
- Consider extracting to a JSON/`.tres` resource later so non-coders can edit,
  but not now — GDScript dict is fine while iterating.

## B6. Skill tree — remove branch-colour legend at bottom ✅ DONE

- Cluster 6-era polish added a colour-key row along the bottom of the tree
  ("● UI  ● Juice  ● Camera  ● Shaders …"). User wants it gone; the branch
  colours are self-explanatory once nodes are drawn.
- Delete the legend draw block in `skill_tree_view.gd::_draw` (or wherever it
  was added; grep for "branch_col" near a horizontal loop). Also remove the
  hint pill's mention of colours if any.

## B7. Level Library — tabbed sections ✅ DONE

- Split `level_library.gd::_build_ui` output into three tabs using
  `TabContainer`:
  1. **Recent plays** — last N seeds, most recent first.
  2. **Favourites** — filter of `Global.level_library` where
     `entry.favorite == true`.
  3. **Community favourites** — empty placeholder ("Coming soon") for now.
- Seed entry / copy row stays above the tabs (persistent across tabs).
- Each row already has a ★ toggle — keep as-is, just make sure toggling in
  Recent moves the entry into Favourites tab on refresh.

## B8. Level Library — seed entry + copy ✅ DONE

- Entry row already exists at level_library.gd:65-90 ✅
- Add a **Copy seed** button next to each row that copies
  `Global.seed_to_code(seed_val)` to `DisplayServer.clipboard_set(...)`.
- Add a tiny toast ("Copied!") using a Label that fades in top-right for 1.2s.

## B9. Combos — unlockable skill + bounce gating ✅ DONE

- Add a new skill `combo_system` (branch: juice, requires: juice_squash or
  ui_polished) in `skills_db.gd`. Gate `combo_system.gd::notify_stomp` and
  `notify_airborne` behind `Global.is_unlocked("combo_system")` — bail early
  if not unlocked.
- The floating popup currently bounces via `tween_property` with `TRANS_BACK`.
  Only apply the bounce transition when `Global.is_unlocked("text_bounce")`
  (or existing juice-bounce skill). Otherwise fade+scale linearly.

## B10. Editable cost formula ✅ DONE (superseded by B11)

- `SkillsDB.compute_cost` + `COST_BASE`/`COST_MULT` constants already exist
  (skills_db.gd:21-31). Verify all UI paths call it — grep `d["cost"]` and
  `.get("cost"` and replace remaining reads with `SkillsDB.compute_cost(sid)`.
- Add a designer-facing note: "tweak COST_BASE / COST_MULT at the top of
  skills_db.gd to reshape the whole economy in one line."

## B11. Skill tree — path-based exponential pricing ✅ DONE

- Replace/augment `compute_cost` with a per-path table:
  `PATH_COSTS = [1, 2, 4, 10, 20, 50]` indexed by depth. Fall back to the last
  entry × 2 for depths beyond.
- Allow per-skill override via `SKILLS[sid]["cost_override"]` (respect first
  if present). Keeps root=1 (UI) and lets designers pin bespoke prices.
- Same depth calc as today (`_depth_from_root`).

## B12. Pinch / mousewheel zoom in skill tree ✅ DONE

- `skill_tree_view.gd::_gui_input` currently uses wheel for pan.
- Repurpose plain wheel to zoom (accumulate a `_zoom` float, clamp 0.4–2.0),
  keep shift+wheel horizontal pan. Multiply `GRID_SCALE` and `NODE_RADIUS` by
  `_zoom` when drawing/hit-testing.
- Pinch: detect two-finger `InputEventScreenTouch` — track two active touch
  indices, compute distance delta between them each frame, apply to `_zoom`.
- Zoom around the cursor (or pinch midpoint), not the corner — adjust
  `_camera_offset` so the point under the cursor stays fixed:
  `_camera_offset = cursor - (cursor - _camera_offset) * (new_zoom / old_zoom)`

## B13. Hide un-revealed skill nodes ✅ DONE

- In `_draw_node`, only draw a node if any of its `requires` chain has at
  least one purchased ancestor, OR the node itself is a root, OR its direct
  parent is purchased. Otherwise skip drawing + skip hit-test.
- Purchased-parent-only reveal is the cleanest rule ("further nodes hidden
  until parent revealed"). Add a subtle "???" ghost pip along the edge going
  off-screen so the player knows more exists.

## B14. Per-run score driven by combo total ✅ DONE

- Introduce `Global.current_run_score` (int). Reset in `main.gd` / level
  start.
- Every token earned = `1 * current_multiplier`. Every stomp adds a
  fixed base (e.g. 50) × multiplier. Distance milestones add flat chunks.
- Save best score per seed into `Global.level_library[i].best_score` and a
  global `Global.best_score_ever`. Show on lose screen and library rows.

## B15. Combo multiplier — time-based accumulation ✅ DONE

- Rework `combo_system.gd::notify_airborne` and `notify_stomp`:
  - Track continuous "in-combo" state (airborne OR within grace of last stomp).
  - `_multiplier` becomes a float; every 1.5 s of active combo adds +1
    (linear). Display as `x[int(mult)+1]` (so 1.5s = x2 total? — spec says
    1.5s = x1, 3s = x2, 15s = x10). Formula: `mult = floor(elapsed / 1.5)`.
  - Start displaying once `mult >= 1` (i.e. 1.5s elapsed) even without stomp.
- Stomp bonuses: bouncy-enemy stomp adds +2 to mult, super-bouncy adds +10.
  Enemies expose a `combo_bonus: int` (default 0) field on their scripts;
  read that in `notify_stomp(pos, combo_bonus)`.
- Popup layout: big `x[N]` in ka1 font (import if not present), with
  `total time in air %.1fs` in a smaller line below.

## B16. Combo — token-earn boost while active ✅ DONE

- While combo active, tokens tick faster. Cheapest wiring: the token
  spawn timer in `main.gd` (or wherever tokens are auto-emitted) reads
  `ComboSystem.current_multiplier()` and scales the interval by `1 /
  max(1, mult)`. Stops when combo ends.
- No retroactive multiplier on past tokens — only *while* combo is live.

## B17. HUD — `x[amount]` next to token counter ✅ DONE

- In `hud.gd` where the token label is drawn, add a sibling Label
  positioned to the right, using the "ka1" font (add to `assets/fonts/` if
  missing — pick a chunky arcade face if unavailable). Font size ~1.15× the
  token counter's own size.
- Only visible while `ComboSystem.current_multiplier() >= 1`.

## B18. Frame freeze on combo tick ✅ DONE

- When `_multiplier` increments, call a helper `ScreenFX.brief_freeze(0.06)`
  which uses `Engine.time_scale = 0.02; await get_tree().create_timer(...);
  Engine.time_scale = 1.0` — but wrap in an unscaled real-time timer so the
  freeze itself is short. Only fires if `Global.is_unlocked("frame_freeze")`
  (new skill or existing juice one).

## B19. "Beat your best" rainbow indicator ✅ DONE

- Left-edge vertical rotated label (rotation_degrees = -90) parented to
  `hud.tscn`. Two states:
  - "ALMOST!" — when current score reaches 90% of best (level or ever, prefer
    ever). Subtle single-hue bounce.
  - "NEW BEST!" — beat best. Rainbow (cycle hue by
    `Time.get_ticks_msec() * 0.001`), stronger scale bounce (0.95 ↔ 1.05).
- Priority: ever > per-level. Only one shown at a time.

## B20. Icon assets — sourcing map (for reference) — reference only

- Gear/cog for settings: prefer game-icons.net Delapouite/gear-hammer or
  cog-wheel if we can pull it into `assets/icons/`; interim use
  `assets/icons/hands/delapouite/marble-tap.png` is a poor fit — don't. Use a
  code-drawn polygon instead until a real cog lands.
- Combo/juice popups can pull from `assets/icons/fire/lorc/` (fire-punch,
  fire-dash) as decorative sparkles on x-milestones.
- Enemy "bouncy" tag icon: `assets/icons/shoes/delapouite/sonic-shoes.png`.
  Super-bouncy: `assets/icons/shoes/lorc/quake-stomp.png`.
- Level-library "Community" tab placeholder icon:
  `assets/icons/hands/delapouite/shaking-hands.png`.

