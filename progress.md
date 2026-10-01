# Progress — Meta-Progression Overhaul

> Author note: this doc is the source of truth for *this* refactor. Update as work lands.

## 1. Goal

Reframe the game as a meta-progression sandbox: the player starts in the **rawest possible state** (primitive shapes, one flat-with-spikes level, no UI, no enemies, no juice). Every "feature" of the existing game becomes a purchasable skill in a shop unlocked via tokens earned by running. The actual moment-to-moment gameplay is unchanged — what changes is **how much of the game's polish and content is visible/active**.

## 2. Phased rollout

| Phase | What lands |
|---|---|
| 0 | progress.md + task list |
| 1 | Meta state (tokens, unlocks, save/load) in `Global` + `SkillsDB` autoload |
| 2 | UI theme system (placeholder + polished) and main entry router |
| 3 | Main menu (Play / Shop / Settings / Exit) with title |
| 4 | Shop scene with mouse-navigable skill tree |
| 5 | Settings scene |
| 6 | Reworked game-over UI (handles first-death "buy UI" prompt) |
| 7 | Level generator gated on unlocks (flat-only → spikes → enemies → procgen) |
| 8 | Player gated on juice/sprites/animations/zoom/shake |
| 9 | Efficient floor strips matching the screenshot's drawn yellow-green style |
| 10 | Improved debug overlay (always-on by default, toggleable, shows feature checklist) |
| 11 | Wire into project.godot and smoke-test |

## 3. Architecture

### 3.1 Meta state (lives in `Global`)

```
Global
├── tokens:   int           — currency
├── unlocked: Dictionary    — { "ui": true, "juice_squash": true, ... }
├── first_death_done: bool  — true once the player has seen the buy-UI prompt
├── settings_cfg: Dictionary
├── is_unlocked(feature_key) → bool
├── grant(feature_key)
├── save_state() / load_state()  → user://meta.dat
```

The very first run boots into the level directly (no entry router decoration, no menu). On the first death, the player gets **1 free token** and the bare "Buy UI" prompt. Buying it sets `unlocked.ui = true` and from then on the entry scene is the **main menu**.

### 3.2 Skills database (autoload `SkillsDB`)

Pure data. Each skill:
```
{
  id, name, desc, cost, requires:[], branch, tree_pos:Vector2,
  feature  ← string key looked up by gameplay code
}
```

Branches (root nodes radiate from `ui`):
- **UI** – ui → ui_polished
- **Juice** – juice_squash → camera_shake → tile_bounce → tear_effects
- **Graphics** – sprites → player_sprite → sprite_animations → parallax → particles → drawn_floors
- **Enemies** – enemies_basic → enemies_more → enemies_advanced → smashers
- **Level** – ramps → procgen → dynamic_zoom

Adding a new skill = appending a Dictionary to `SkillsDB.SKILLS`. UI and gating discover it automatically.

### 3.3 UI theme

```
ui_theme.gd  (static)
├── THEMES = { "placeholder": {…}, "polished": {…} }
├── apply(control_root, theme_name)  — recursively styles Buttons / Panels / Labels
├── current_theme() — reads Global.settings_cfg or defaults
```

Themes inject `StyleBoxFlat`/colors/font sizes into all child Controls. Placeholder is flat grey. Polished is warm cream/forest-green matching the screenshot palette with rounded corners, hover scale, shadow.

### 3.4 Entry router (`main.tscn` → `main.gd`)

- If `unlocked.ui` → load `main_menu.tscn`
- Else → load `leve.tscn`

This becomes the new `run/main_scene`.

### 3.5 Game-over rework

Game-over UI now has two modes:
- **Pre-UI mode** (drawn manually, no theme dependency): "You died. +1 token. [Buy UI]"
- **Normal mode**: "+N tokens. [Continue] [Shop] [Main Menu]"

If `unlocked.ui` is true on death, also offers a "Spend in Shop" shortcut.

### 3.6 Level generator gating

`level_generator.gd` now filters `TEMPLATES` through `_template_allowed(tmpl)`:
- Without `procgen`: only template index 0 + a hand-crafted spikes template.
- Without `enemies_basic`: strip any pattern char that maps to an enemy.
- Without `ramps`: strip `/` and `\\`.
- Without `smashers`: strip `T`.

This way the level always has *something*, just with fewer toys.

### 3.7 Player gating

`player.gd` checks `Global.is_unlocked()` before:
- `_squash_and_stretch` (juice_squash)
- `shake_camera` apply path (camera_shake)
- `anim.visible = true` & sprite frames (sprites / sprite_animations / player_sprite)
- `_update_dynamic_zoom` (dynamic_zoom)
- TearEffect on death (tear_effects)

When a feature is locked, the fallback is what the game already did in primitives mode.

### 3.8 Efficient drawn floors

Currently every `#` becomes its own `StaticBody2D` + `Sprite2D` + `Area2D` (3 deep per column!). For a 40-block level that is ~1200 nodes. Replace with **TileStrip**:

- Generator now scans each row, groups contiguous `#` chunks into one strip of length N tiles.
- `TileStrip` = single `StaticBody2D` with one `CollisionShape2D` sized `(N*128, 128*3)`.
- One `Node2D` child draws the strip in `_draw()` — when `drawn_floors` unlocked: wavy yellow-green grass top, dark scribbly outline, peach-toned earth fill. When locked: flat warm-stone primitive matching current look.
- Saves enormous node count + draw calls.
- Squash on land: scale the visual child briefly. Bounce on land if `tile_bounce` is unlocked.

### 3.9 Debug overlay

`debug_overlay.gd` is a `CanvasLayer` autoload-instanced by `main.gd` (and `leve.tscn`'s root). Always-on by default. Toggle with `F3`. Panel shows:

- FPS / mem / draw calls (RenderingServer)
- Player pos / vel / momentum / stun
- Unlock checklist (✓ / ✗ for every feature)
- Debug toggles checkboxes (auto_restart, keep_seed, show_collisions, …)
- Tokens

## 4. Files

| File | Status | Purpose |
|---|---|---|
| `progress.md` | NEW | this doc |
| `global.gd` | MOD | tokens + unlocks + save/load + feature query |
| `skills_db.gd` | NEW | data-only skills definition |
| `ui_theme.gd` | NEW | modular theme application |
| `main.gd` / `main.tscn` | NEW | entry router |
| `main_menu.gd` / `main_menu.tscn` | NEW | Play / Shop / Settings / Exit |
| `shop.gd` / `shop.tscn` | NEW | mouse-navigable skill tree |
| `settings.gd` / `settings.tscn` | NEW | audio/theme/debug |
| `ui.gd` / `ui.tscn` | MOD | first-death-aware game-over |
| `level_generator.gd` | MOD | feature gating + strip-based spawning |
| `player.gd` | MOD | gate juice/sprites/animations/shake/zoom/tear |
| `tile_strip.gd` / `tile_strip.tscn` | NEW | efficient drawn floor renderer |
| `tile_object.gd` | MOD | keep for spike-platform compatibility |
| `debug_overlay.gd` / `.tscn` | NEW | always-on diagnostics |
| `project.godot` | MOD | new main_scene + SkillsDB autoload |

## 5. Decisions / tradeoffs

- **No Godot plugins requested.** The skill tree and theme system are simple enough to do with built-in `Control` nodes and `Tween`s — adding a plugin would only slow iteration.
- **Local save only** (`user://meta.dat`). No cloud, no leaderboard right now.
- **Tokens are coarse** — 1 per 25 tile distance run + 1 free first-death. Tunable in `Global`.
- **Debug overlay defaults to ON** as the user explicitly requested. Pressing F3 hides it.

---

## 6. Iteration log

### 6.1 Round 2 — "buying stuff doesn't reflect; enemies missing; can't scroll shop; ramps shouldn't be a skill"

Root cause for the *visual* part of "buying stuff doesn't reflect": `Global.use_primitives` defaulted to `true`, which overrode every sprite-loading branch in player/enemies/spikes/smashers. Default flipped to `false`. New helper `Global.gfx(feature_key)` packages "no master primitives override AND unlock is owned".

**Changes**

- `global.gd` — `use_primitives` default `true → false`; added `gfx(feature_key) -> bool` helper.
- `skills_db.gd` — removed `ramps`; added `enemy_sprites` under `enemies_basic`; rewired `procgen` to require `ui` instead of `ramps`; repositioned enemy-branch nodes so they don't overlap.
- `level_generator.gd` — ramp glyphs (`/` `\`) are now unconditionally skipped (ramps removed from the game), and templates containing ramps are filtered out at the index-building step.
- `enemies/*.gd` + `spike.gd` + `smasher.gd` — replaced `Global.use_primitives` checks with `Global.gfx("enemy_sprites")` so sprite branches actually run when the unlock is owned. Player still gates on its own `player_sprite` key.
- `skill_tree_view.gd` — input rewritten:
  - left/middle drag-anywhere pans (click vs drag separated by a 6 px movement threshold)
  - mouse wheel = vertical, shift + wheel = horizontal, dedicated `MOUSE_BUTTON_WHEEL_LEFT/RIGHT`
  - touch via `InputEventScreenTouch` + `InputEventScreenDrag`
  - hint pill drawn in the top-left so the controls are discoverable
- `shop.gd` — title stays clean; nav hints live in the tree-view pill.

### 6.2 Round 3 — "camera weird on death; tiles don't show; ramps still in tree"

- `tile_strip.gd` — owner-strip race. The visual child had its `owner_strip` set *after* `add_child`, so its `_ready()` bailed before building geometry. Fixed by setting the property *before* `add_child`, plus a deferred `_late_build` fallback in `tile_strip_visual.gd` for safety.
- `player.gd` — camera now detaches from the player in **all** death modes (was fall-only). Shake timer zeroed, position smoothing disabled, camera made-current after re-parent. `_process` early-returns while `is_dead` so zoom/shake/redraw don't keep firing.
- (Ramps removal as above — confirmed gone from skills + generator.)

### 6.3 Round 4 — "enemies still missing; zoom never visible; remove bouncy; show bg; floor hides spikes"

- **Enemy template gating rewritten.** `_build_active_template_indices` no longer relies on a hardcoded `PRE_PROCGEN_INDICES` list. Instead `_template_admissible(tmpl)` rejects a template if it has ramps, or any of its entity glyphs map to a still-locked enemy, or (without `procgen`) it contains `#` above the bottom row. With this:
  - Buying `enemies_basic` immediately makes frog/kobold templates eligible — no procgen required.
  - `enemies_more` adds bat/big_frog; `enemies_advanced` adds bomb/shooter/drill/jumper/rock; `smashers` adds the smasher set.
  - `procgen` then layers in *layout* variety (stairs, elevated platforms, combos, multi-row pits).
- **Dynamic zoom** — mode-2 `intersect_shape` now adds `strip.length_tiles` per hit instead of `1`, since strips bundle many tiles into one body. Without this, the visible-tile count was always tiny → permanently zoomed out → no transition was ever observable.
- **`tile_bounce` removed.** Bouncy floor was redundant with the squash juice. `tile_strip.squash()` now gates on `juice_squash` so floors still squish when player juice is on.
- **In-game background.** New `game_bg.tscn` / `game_bg.gd` / `game_bg_layer.gd`. Lives on `layer = -100`, added once per run by the level generator before the gameplay UI. Three Control children with one shared script:
  - `sky` — always visible. Banded warm peach gradient (28 horizontal slices).
  - `far` — hills, motion_scale ≈ 0.10, only visible when `parallax` is unlocked.
  - `near` — hills, motion_scale ≈ 0.35, same gate.
  Cheap — only redraws when the camera's x changes; sky layer doesn't redraw at all after the first frame.
- **Floor was clipping spikes.** Reduced the grass band: `TOP_WAVE_AMP 14 → 6`, `grass_thick 22 → 10`, highlight wash `6 → 3`, `grass_top -8 → -2`. Spike spawn Y lifted by 14 px so its base sits clearly above the wavy grass band even at the highest wave peak.

### 6.5 Round 6 — "more skills, shaders, FX, common platformer features"

Big expansion. Skill tree roughly doubled; lots of new visual/feel features.

**Skills added** (8 branches now: ui / juice / camera / shaders / moves / graphics / enemies / level)

- *UI*: `hud`, `pause_menu`
- *Juice*: `hit_flash`, `motion_trail`, `footstep_dust`, `impact_freeze`
- *Shaders* (new branch): `vignette`, `chromatic_aberration`, `color_grading`, `crt_filter`, `outline`
- *Moves* (new branch): `sprint`, `double_jump`, `dash_move`, `wall_jump`
- *Graphics*: `clouds`, `foliage`
- *Level*: `coins`

**Code added**

- `shaders/vignette.gdshader`, `shaders/chromatic.gdshader`, `shaders/color_grading.gdshader`, `shaders/crt.gdshader` — all `hint_screen_texture`-based fullscreen post-process.
- `shaders/outline.gdshader` — per-sprite, 8-tap alpha dilation outline.
- `screen_fx.gd` autoload — CanvasLayer at `layer = 90`. Stacked fullscreen ColorRects, one per shader, toggled by unlock state. `ScreenFX.kick_chromatic(amount, duration)` for impact-driven chromatic pulses; decays automatically.
- `project.godot` — `ScreenFX` autoload registered.
- `hud.gd` / `hud.tscn` — top bar with distance / tokens / best, tokens pop-tween on change. Slides in on level start.
- `token_pop.gd` — static `TokenPop.spawn(parent, world_pos, amount)`. Used by coins; reusable elsewhere.
- `pause_menu.gd` / `pause_menu.tscn` — `process_mode = ALWAYS`, Esc toggles, scales in. Buttons: Resume / Shop / Main Menu / Quit.
- `coin.gd` / `coin.tscn` — procedurally drawn spinning gold disc with glint and outline, bobs and rotates. On player overlap: +token, TokenPop, spark burst. Spawn rule in `level_generator.gd`: 6% chance per empty cell that has a `#` somewhere below it; only when `coins` is unlocked.
- `game_bg_layer.gd` + `game_bg.gd` + `game_bg.tscn` — added "clouds" layer between sky and far hills. Cloud is 5 overlapping circles per puff, wraps horizontally, drifts on its own slow timer plus parallax-x. Gated by `clouds`.
- `tile_strip_visual.gd` — added foliage tufts. Three small blades + occasional yellow flower per tuft, deterministic from world x so adjacent strips agree. Gated by `foliage`.
- `level_generator.gd` — instantiates `hud`, `pause_menu`, coins, snaps shooter Y, etc.

**Player changes** (`player.gd`)

- New cached flags in `_resolve_flags()`: `_use_outline`, `_use_double_jump`, `_use_dash`, `_use_sprint`, `_use_wall_jump`, `_use_motion_trail`, `_use_footstep_dust`, `_use_impact_freeze`, `_use_hit_flash`.
- `_ready()` wires the addon: `jumps = 2`, `dashType = 1`, `wallJump = true`, `run_speed = 820` (sprint), then `_updateData()`.
- `_apply_outline_material()` — assigns the outline ShaderMaterial to the AnimatedSprite when both `player_sprite` and `outline` are owned.
- Motion trail — `Line2D` parented to the level (so it doesn't rotate with the player on death), recent N points pushed each frame, tapered width via `Curve`.
- Footstep dust — `CPUParticles2D` at the feet, continuous emitter toggled by `is_on_floor() && abs(velocity.x) > 220`.
- Impact freeze — `Engine.time_scale = 0.06` for 50 ms on stomp; reset by a one-shot tree timer using `ignore_time_scale = true`.
- Hit flash — edge-trigger on `stun_timer` rising from 0; tween `modulate` to white and back.
- Chromatic kick — stomp also calls `ScreenFX.kick_chromatic(0.020, 0.35)` when the shader is owned.

---

### 6.4 Round 5 — "camera branch; spike z + alignment; floor stitching; raise floor; shooters grounded; blood"

- **Skill tree restructure.** New `camera` branch ("Camera Effects") in `skills_db.gd`:
  - `camera_shake` — moved out of juice, now requires `ui` directly.
  - `dynamic_zoom` — moved out of level, requires `camera_shake`.
  - `tear_effects` — re-prereq'd to `juice_squash` (was `camera_shake`).
  - Branch colour `Color(0.70, 0.55, 0.95)` (lilac); branch name "Camera Effects".
- **Spike draws above floor.** Tile-strip visual `z_index = -10` so the grass band never paints over a spike base. (Spike x was already `tile_size.x * 0.5` centred — that was correct.)
- **Adjacent floors connect.** `tile_strip_visual.gd` now phases the grass wave by **world x** (`owner_strip.position.x + position.x + sample_x`), not strip-local `t`, so two adjacent strips meeting at the same world x produce the same wave value. Boundaries are seamless.
- **Floor graphic lifted.** Visual child's local position shifted up 6 px without touching the collision shape. Surface art now reads as slightly raised; player still stands on the same physics surface.
- **Shooters on top of ground.** Level generator snaps `shooter` Y at spawn time: scan the template downward from the shooter's row, find the first row with `#`/`s`, place the shooter one row above it.
- **Blood splats.** New `blood_splat.gd` (static `BloodSplat.apply(parent, pos, velocity)`):
  - Two CPUParticles2D bursts — wide splatter + narrow spurt.
  - Direction = `-velocity.normalized()` (trails away from impact); upward fallback.
  - Colour ramp 0.85/0.12/0.12 → 0.55/0.06/0.06 → fade-to-black.
  - Auto-frees on `finished`.
  - Gated by new `blood_splats` skill (juice branch, requires `juice_squash`, 2★).
  - Hooked into `BaseEnemy.die()` (with `impact_vel`) and `Player.die()` (with current `velocity`).
  - Parented to `get_parent()` so it survives the dying entity's `queue_free()` or `TearEffect`-induced hide.

---

## 7. Open / known-but-acceptable

- TileObject + ramp + ramp.tscn still exist in the project but are no longer instantiated anywhere. Left as dead code rather than delete-and-edit-scene-refs — harmless.
- `PRE_PROCGEN_INDICES` constant is no longer read; left in `level_generator.gd` as documentation of the original starter set.
- After buying skills in the shop, the active level scene won't reflect changes mid-run — the user has to return to the main menu and hit Play. This is the expected flow; no need for a hot-reload path.
- Settings still has a "Force primitives" toggle that maps directly to `Global.use_primitives`. It overrides every gate, useful for art-checking.
- No audio assets in the project — `master_volume` slider drives the AudioServer Master bus but there's nothing to play yet.
