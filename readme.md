# Minimum Viable Platformer — Developer Reference

> A procedurally generated, auto-running 2D platformer built in **Godot 4.4** (GL Compatibility renderer).
> This document is the authoritative reference for every file, every skill, and every system in the project.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Autoloads Reference](#2-autoloads-reference)
3. [Directory and File Reference](#3-directory-and-file-reference)
4. [Collision Layer Map](#4-collision-layer-map)
5. [Skill Tree — Full Listing](#5-skill-tree--full-listing)
6. [Combo System Deep-Dive](#6-combo-system-deep-dive)
7. [Audio System Deep-Dive](#7-audio-system-deep-dive)
8. [Screen FX Pipeline](#8-screen-fx-pipeline)
9. [Level Generation System](#9-level-generation-system)
10. [Meta-Progression and Save System](#10-meta-progression-and-save-system)
11. [How to Add a New Enemy](#11-how-to-add-a-new-enemy)
12. [How to Change or Add Controls](#12-how-to-change-or-add-controls)
13. [How to Add a New Obstacle](#13-how-to-add-a-new-obstacle)
14. [How to Add More Juice](#14-how-to-add-more-juice)
15. [How to Add Parallax Scrolling](#15-how-to-add-parallax-scrolling)
16. [How to Add More Menus](#16-how-to-add-more-menus)
17. [How to Add Custom Particle Effects](#17-how-to-add-custom-particle-effects)
18. [Debug Toggles Reference](#18-debug-toggles-reference)
19. [License](#19-license)

---

## 1. Project Overview

| Setting | Value |
|---|---|
| Engine | Godot 4.4 |
| Renderer | GL Compatibility (runs on web, mobile, desktop) |
| Viewport | 1280 × 720, canvas_items stretch mode |
| Main Scene | `leve.tscn` (note: intentional short name) |
| Entry Point | `level_generator.gd` runs inside `leve.tscn` |
| Autoloads | Global, SkillsDB, ScreenFX, DebugOverlay, ComboSystem, LeaderboardService, AudioManager |

**Core loop:** The player auto-runs right through a procedurally generated level (made of ASCII-art template blocks). They tap jump to survive obstacles, enemies, and pits. On death, tokens are awarded based on distance. Tokens spend in the shop (`shop.tscn`) to buy skills from a radial skill tree. Skills unlock new visual, gameplay, and difficulty features.

**"MVP builds itself" theme:** The game literally starts with no UI at all. The first upgrade you can buy is the UI itself. Everything unlocks progressively — primitives become sprites, silence becomes music, flat runs become complex layouts. New features should feel like they are being discovered, not just added.

---

## 2. Autoloads Reference

Autoloads are global singletons registered in `project.godot`. They are accessible from any script.

---

### `Global` (`global.gd`)

**Central data store and state machine for everything persistent.**

Key responsibilities:

| Responsibility | Details |
|---|---|
| Input map | `_initialize_input_map()` registers keyboard bindings at boot (left/right/jump/dash and stubs for run/latch/roll/twirl) |
| Tokens & spending | `tokens: int`, `spend(n)`, `grant(key)`, `is_unlocked(key)` |
| Skill unlock state | `unlocked: Dictionary` — maps feature key → bool. Persisted in `user://save.dat` |
| Run state | `last_run_distance`, `run_tokens_gained`, `current_run_score`, `current_run_seed`, `current_run_highest_combo` |
| All-time stats | `stats: Dictionary` — bucket counters (deaths, jumps, enemies stomped, etc.) |
| Level library | `level_library: Array` — saved seeds with distances and favourites |
| Settings | `settings_cfg: Dictionary` — volume, palette, sky colour, font, fast mode, etc. |
| Save/load | `save_state()` / `load_state()` — serialises unlocked + stats + library + settings to `user://save.dat` |
| Signals | `palette_changed` — emitted when the colour palette changes mid-run |
| Token multiplier | `token_multiplier` — product of enemy bonus (0–80%) and fast mode bonus |
| Palette tint | `palette_tint()` → Color; driven by `settings_cfg["palette"]` |

**Key methods used throughout the codebase:**

```gdscript
Global.is_unlocked("some_feature_key")  # returns bool
Global.gfx("some_feature_key")          # is_unlocked AND not use_primitives
Global.grant("feature_key")             # unlock a feature (does NOT deduct tokens)
Global.spend(n)                         # deduct n tokens; returns false if insufficient
Global.stat_add("key", n)              # add n to a stat counter
Global.stat_max("key", n)              # update a stat if n is a new max
Global.stat_bucket("key", sub, n)      # nested stat increment (e.g. seeds_visited)
Global.add_run_score(n)                # add n points to current run score
Global.on_player_death(dist)           # finalise run: compute + award tokens, save
Global.reset_run_state()               # clear per-run counters at run start
```

---

### `SkillsDB` (`skills_db.gd`)

**Data-only skill tree: definitions, costs, prerequisites, layout positions.**

- `SKILLS: Dictionary` — all skill entries (see §5 for the full listing).
- `compute_cost(skill_id)` — BFS depth-based cost. Depth 0=1tok, 1=3tok, 2=9tok … via `PATH_COSTS`.
- `prereqs_met(skill_id)` — checks all `requires` entries are in `Global.unlocked`.
- `purchase(skill_id)` — validates, deducts tokens, calls `Global.grant()`, runs hook.
- `get_tree_pos(skill_id)` — returns `Vector2` layout position (radial + force-directed relaxation; cached after first call).
- `BRANCH_COLORS`, `BRANCH_NAMES` — lookup tables used by the shop UI.

**Skill tree layout algorithm** (computed once on first shop open):
1. Seed radial positions: each branch owns an angular sector (see `BRANCH_ANGLES`). Nodes are placed at radii proportional to their depth from root.
2. Force-directed relaxation (260 iterations of Fruchterman-Reingold): spring attraction along edges, pairwise repulsion, weak pull toward the node's branch ray. Produces an organic graph where branches radiate clearly outward.

---

### `ScreenFX` (`screen_fx.gd`)

**Full-screen post-process shader stack. Layer 90.**

Each pass is a `ColorRect` with a `ShaderMaterial`. A `BackBufferCopy` node precedes each `ColorRect` so every pass reads the composited output of all previous passes (required in GL Compatibility where `hint_screen_texture` is only populated by the most recent BBC).

Pass order and feature key:

| Order | Feature Key | Shader File | Effect |
|---|---|---|---|
| 1 | `color_grading` | `shaders/color_grading.gdshader` | Warm filmic tint |
| 2 | `chromatic_aberration` | `shaders/chromatic.gdshader` | RGB channel split, edge-exaggerated |
| 3 | `fog_cover` | `shaders/fog_cover.gdshader` | Dark fog at screen bottom (Level only) |
| 4 | `vignette` | `shaders/vignette.gdshader` | Darkened corners |
| 5 | `crt_filter` | `shaders/crt.gdshader` | Scanlines + screen curvature (desktop/console only) |
| 6 | `wobble_shader` | `shaders/wobble.gdshader` | Vertical warp driven by player fall speed |
| 7 | `pixel_dither` | `shaders/pixel_dither.gdshader` | Bayer ordered dithering |
| 8 | `neon_glow` | `shaders/neon_glow.gdshader` | Additive glow bleed |

**UI rendering and post-processing:** ScreenFX is at CanvasLayer `layer = 90`. All in-game UI elements (HUD, pause menu, game-over overlay, main menu, shop, settings) are at `layer = 95`, rendering AFTER the full post-processing chain. This means chromatic aberration and all other screen effects never apply to UI text and panels.

**API:**
- `ScreenFX.kick_chromatic(amount, duration)` — briefly bumps aberration toward `CHROMATIC_MAX` then decays
- `ScreenFX.trigger_glitch(go_silent)` — max chromatic kick + glitch audio sequence
- `ScreenFX.wobble_intensity` — set each frame by `player.gd` from vertical velocity

---

### `ComboSystem` (`combo_system.gd`)

**Airtime + stomp combo multiplier and wind visual. Layer 80.**

Full details in §6. Key API:

- `ComboSystem.notify_airborne(is_air)` — called by `player.gd` on floor-state edge transitions
- `ComboSystem.notify_stomp(world_pos, combo_bonus)` — called by `player.gd` foot sensor on stomp
- `ComboSystem.reset()` — called on death and run start
- `ComboSystem.current_multiplier()` — current integer multiplier (0 if inactive)
- `ComboSystem.token_multiplier()` — `max(1, current_multiplier())` for token scaling

---

### `AudioManager` (`audio_manager.gd`)

**All sound effects and music. Layer managed internally.**

Full details in §7. Key API:

- `AudioManager.play(key, vol_db, pitch_var)` — one-shot SFX from pool
- `AudioManager.play_at(key, world_pos, vol_db)` — positional SFX (quieter off-screen)
- `AudioManager.play_music(key, fade)` — cross-fade music; keys: `"main_menu"`, `"gameplay"`, `"shop"`, `"glitch"`
- `AudioManager.stop_music(fade)` — fade out current music
- `AudioManager.set_wind_audio(active)` — fade wind loop in/out (gated by `"wind_effect"` skill)
- `AudioManager.play_glitch_sequence(go_silent)` — glitch SFX + glitch_song then silence
- `AudioManager.connect_ui_clicks(root)` — auto-wire all Button `pressed` → `"ui_click"` sound

Feature gates: `"sfx"` (one-shot SFX), `"music"` (background music), `"wind_effect"` (wind loop).

---

### `DebugOverlay` (`debug_overlay.gd`)

**FPS/velocity overlay drawn when `Global.debugText` is true. Layer 100.**

Automatically appears in the top-left corner. Iterates `Global.debug_toggles` to render checkbox controls.

---

### `LeaderboardService` (`leaderboard_service.gd`)

**Firebase Firestore leaderboard backend. Gated by `"leaderboard"` skill.**

- Submits and fetches per-seed scores.
- `player_id` — UUID stored in `Global.settings_cfg`. Auto-generated on first use.
- `get_player_name()` / `set_player_name(name)` — profile name stored locally.
- `submit_level_result(seed_code, player_id, name, score, distance, combo)` — sends to Firestore.
- `fetch_leaderboard(seed_code, callback)` — async fetch for the leaderboard view.

---

## 3. Directory and File Reference

### 3.1 Root Scripts

---

#### `level_generator.gd`

**Role:** Attached to the root Node2D in `leve.tscn`. Generates the entire level procedurally at run start.

**What it does:**

1. Chooses a seed (fixed starter seed before `procgen` unlock; random or stored seed after).
2. Iterates `level_width_blocks` (default 40) template slots, picking a random admissible template per slot.
3. Translates each template's ASCII pattern into spawned scenes: strips, spikes, entities.
4. After all tiles, spawns the player, attaches a Camera2D, and computes `base_zoom`.

**Template character map:**

| Char | Entity / Tile |
|---|---|
| `#` | Solid tile strip (3 tiles deep) |
| `a` | Abyss — no floor |
| `s` | Spike + 1-tile strip beneath it |
| `T` | Smasher |
| `f` | Frog |
| `F` | BigFrog |
| `b` | Bat |
| `B` | Bomb |
| `r` | Rock (spring launcher) |
| `k` | Kobold |
| `S` | Shooter cannon |
| `d` | Drill (Mole) |
| `j` | Jumper |

**Coin spawning** (when `"coins"` skill is owned): For each `.` cell above a floor `#` at least 2 rows below, 6% chance of spawning a coin. The spawn also rejects cells where a `#` exists 1–2 rows above in the same column — those cells would be inside the 3-tile-deep strip of an elevated platform.

**Entity gating** (`ENTITY_GATES`): each entity type is gated behind a feature key. Frogs/kobolds require `enemies_basic`; bats/big_frog require `enemies_more`; bombs/shooters/drills/jumpers require `enemies_advanced`; smashers require `smashers`. Spikes are always allowed.

**Template admissibility** (`_template_admissible`): before procgen is unlocked, only templates where all `#` characters appear in the bottom row are admitted (no stairs or elevated platforms). After unlock, the full library of ~60 templates is available.

---

#### `player.gd` (extends `PlatformerController2D`)

**Role:** Central character script. Extends the UPC addon's character body.

**Key behaviours:**

- **Auto-run**: `auto_momentum` ramps up to `run_speed` (600 px/s, or 820 px/s with sprint) via `auto_acceleration`. Simulates running by pressing/releasing the `"right"` action each frame.
- **Stun**: `stun_timer > 0` suppresses auto-run and bleeds momentum. Used for Rock knockback.
- **Foot sensor**: `Area2D` on collision mask 4, positioned 60 px below feet. On enemy hitbox overlap when `velocity.y > 50`, calls `enemy.stomp_by(self)`.
- **Body sensor**: `Area2D` on collision layer 8. Enemies detect this and call `player.die()`.
- **Death** (`die(is_fall, cause, instant_shatter)`): disables sensors, releases inputs, detaches camera, spawns blood splat. Fall death rotates sprite + poof particles; non-fall death flashes white then shatters with TearEffect.
- **ComboSystem integration**: calls `ComboSystem.notify_airborne()` on floor-state transitions and `ComboSystem.notify_stomp()` on stomp.
- **ScreenFX integration**: drives `ScreenFX.wobble_intensity` from vertical velocity each frame; calls `ScreenFX.kick_chromatic()` on stomp impact if unlocked.

**Feature flags** (resolved once in `_resolve_flags()` at `_ready()`):

| Flag | Skill Gate |
|---|---|
| `_use_sprite_player` | `player_sprite` |
| `_use_sprite_anims` | `sprite_animations` |
| `_use_juice` | `juice_squash` |
| `_use_shake` | `camera_shake` |
| `_use_zoom` | `dynamic_zoom` |
| `_use_tears` | `tear_effects` |
| `_use_particles` | `particles` |
| `_use_outline` | `outline` |
| `_use_double_jump` | `double_jump` |
| `_use_sprint` | `sprint` |
| `_use_wall_jump` | `wall_jump` |
| `_use_motion_trail` | `motion_trail` |
| `_use_footstep_dust` | `footstep_dust` |
| `_use_impact_freeze` | `impact_freeze` |
| `_use_hit_flash` | `hit_flash` |
| `_use_near_miss` | `near_miss_slowmo` |

---

#### `global.gd`

See §2 — Autoloads Reference.

---

#### `leve.tscn`

Root Node2D with `level_generator.gd` attached. Nearly empty; all content spawned at runtime.

---

#### `main.gd` / `main.tscn`

Entry point. Routes to `main_menu.tscn` if the `"ui"` skill is owned, or directly to `leve.tscn` if not (tutorial/first-run flow).

---

#### `main_menu.gd` / `main_menu.tscn`

Main menu CanvasLayer (`layer = 95`). Shows Play, Shop, Settings, Exit buttons. Library/Stats/Daily/Leaderboard buttons appear as their respective skills are unlocked.

---

#### `shop.gd` / `shop.tscn`

Skill tree shop CanvasLayer (`layer = 95`). Hosts a `skill_tree_view.gd` Control and a detail panel. A Recommend button cycles through purchasable skills in priority order.

---

#### `settings.gd` / `settings.tscn`

Settings CanvasLayer (`layer = 95`). Volume sliders, palette switcher, sky colour, font picker, fast mode toggle, debug mode toggle, and reset button.

---

#### `hud.gd` / `hud.tscn`

In-game HUD CanvasLayer (`layer = 95`, above ScreenFX). Shows distance, token count, personal best, combo multiplier chip, and a "ALMOST! / NEW BEST!" flag that sweeps in from the left edge.

---

#### `pause_menu.gd` / `pause_menu.tscn`

Pause CanvasLayer (`layer = 95`). Opens on Esc/Back. Offers Resume, Shop, Menu, Exit. Pauses the tree with `get_tree().paused = true`.

---

#### `ui.gd` / `ui.tscn`

Game-over overlay CanvasLayer (`layer = 95`). Two modes:
- **Pre-UI**: bare death message + Buy UI + Retry + Exit buttons.
- **Post-UI**: full stats card (distance, personal best, combo), seed strip (code + copy button + seed-best), profile strip (player name + edit), button rows (Replay/New/Shop and Menu/Exit/Leaderboard).

---

#### `blood_splat.gd` / `blood_canvas.gd`

Static utility (`BloodSplat`) for spawning circular splat decals on death. `blood_canvas.gd` holds a persistent 2D draw node that accumulates marks for the whole run (gated by `blood_marks` skill). Toggle in Settings.

---

#### `coin.gd` / `coin.tscn`

Collectible coin. Slowly bobs up and down. On player overlap: `Global.spend(-1)` (awards 1 token), plays coin SFX, queues free. Spawned by `level_generator.gd` when `"coins"` is owned.

---

#### `spike.gd` / `spike.tscn`

Static instant-kill `Area2D`. Kills player via `die()`, kills enemies via `die_torn()`, destroys smashers. Draws a triangle in primitives mode; loads `assets/spikes.png` otherwise.

---

#### `smasher.gd` / `smasher.tscn`

Ceiling hammer `Area2D`. State machine: `idle → falling → smashed → rising → idle`. Drops when the player enters `trigger_distance`. Kills anything on contact while falling. Triggers camera shake and chromatic kick. Destroyed by spike contact.

---

#### `tear_effect.gd`

Static utility class (`TearEffect`). Shatters any `Node2D` into RigidBody2D physics polygon pieces with optional texture UV sampling. Called as `TearEffect.apply(node, size, color, impulse, hard_points, type)`. Types: `"default"` (rectangle), `"circular"` (16-sided), `"logs"` (horizontal cuts only).

---

#### `tile_object.gd` / `tile_object.tscn`

Single 128×128 solid floor tile. `squash()` and `shake()` methods for juice feedback. `determine_exposed_sides()` hides interior borders. Draws a warm stone rect in primitives mode.

---

#### `tile_strip.gd` / `tile_strip.tscn`

Efficient horizontal run of N tiles as a single body. Used instead of individual `tile_object` nodes for performance. `length_tiles` controls width; `no_foliage` suppresses grass on elevated platforms.

---

#### `ramp.gd` / `ramp.tscn`

Triangular ramp `StaticBody2D`. `ramp_type = "up"` or `"down"`. Builds a `CollisionPolygon2D` at runtime. Currently excluded from all templates (ramps removed from active gameplay but left in codebase).

---

#### `skill_tree_view.gd`

`Control` node embedded inside `shop.tscn`. Renders the skill tree as a zoomable/pannable canvas: nodes are circles with icons, edges are bezier curves (with animated pulse if `skill_tree_polish` is owned), branch-coloured. Emits `skill_selected(id)` and `skill_purchased(id)` signals.

---

#### `skills_db.gd`

See §2 and §5.

---

#### `combo_system.gd`

See §6.

---

#### `audio_manager.gd`

See §7.

---

#### `screen_fx.gd`

See §8.

---

#### `leaderboard_view.gd` / `leaderboard_view.tscn`

Per-seed leaderboard screen. Fetches top-N scores from Firebase for the current seed code and displays them in a styled list. Opened from the game-over screen when `"leaderboard"` is owned.

---

#### `adaptive_sky.gd`

Node script instantiated by `level_generator.gd`. Drifts the sky colour and palette tint slowly over the run when `"adaptive_sky"` is owned.

---

#### `tutorial_screen.gd` / `tutorial_death_overlay.gd`

First-run tutorial. `tutorial_screen.gd` shows tap-through slides before the player can move. `tutorial_death_overlay.gd` appears on first death (when the tutorial run completes) with a brief onboarding message.

---

### 3.2 `enemies/` Directory

All enemies share the same structure. See §11 for how to add one.

| File | Class | Type | Behaviour |
|---|---|---|---|
| `base_enemy.gd` | `BaseEnemy` | CharacterBody2D | Shared base: gravity, hitbox, stomp, death |
| `frog.gd` | — | CharacterBody2D | Hops toward player when in range |
| `big_frog.gd` | — | CharacterBody2D | Larger frog, stronger hop |
| `bat.gd` | — | CharacterBody2D (gravity=0) | Dives on trigger |
| `kobold.gd` | — | CharacterBody2D | Patrols, reverses at edges/walls |
| `bomb.gd` | — | CharacterBody2D | Walks, pulses, explodes after 1 s |
| `rock.gd` | — | CharacterBody2D | Launches player high instead of dying; knockback on side touch |
| `shooter.gd` | — | StaticBody2D | Fires bullets at interval |
| `bullet.gd` | — | BaseEnemy (gravity=0) | Flies horizontally; destroys on wall; can be stomped |
| `drill.gd` | — | Area2D | Drops from ceiling; destroys tiles it hits |
| `jumper.gd` | — | CharacterBody2D | Like frog; stomping launches player to extreme height |

---

### 3.3 `assets/` Directory

```
assets/
├── animations/
│   ├── player/
│   │   ├── player_idle/   0–3.png    (4 frames, 160×220)
│   │   ├── player_run/    0–6.png    (7 frames)
│   │   ├── player_jump/   0–6.png    (7 frames)
│   │   ├── player_hurt_1/ 0–2.png    (3 frames)
│   │   └── player_hurt_2/ 0–2.png    (3 frames)
│   ├── frog_idle/         0.png      (1 frame)
│   ├── frog_jump/         0–3.png    (4 frames)
│   ├── bat/               0–3.png    (4 frames)
│   ├── kobold/            0–7.png    (8 frames)
│   ├── cannon/            0–15.png   (16 frames)
│   ├── bullet_bob/        0–3.png    (4 frames)
│   └── mole/              0–5.png    (6 frames)
├── smasher_sharp/
│   ├── normal.png
│   ├── angry.png
│   └── hurt.png
├── fonts/                 *.ttf / *.otf  (selectable via Font Select skill)
├── music/                 *.ogg  (main_menu, gameplay, shop, glitch tracks)
├── sounds/                *.ogg  (all SFX)
├── dirt_floor.png         (128×128 tile underside)
├── top_dirt_floor.png     (128×128 tile top-surface)
├── spikes.png
└── spikes_blood.png
```

All animation frames load at runtime via `load("res://assets/animations/...")`. Add new frames by placing numbered PNGs starting at 0.

---

### 3.4 `shaders/` Directory

| File | Used By | Effect |
|---|---|---|
| `chromatic.gdshader` | ScreenFX | RGB channel split |
| `color_grading.gdshader` | ScreenFX | Filmic tint |
| `crt.gdshader` | ScreenFX | Scanlines + curvature |
| `fog_cover.gdshader` | ScreenFX | Bottom fog (Level only) |
| `neon_glow.gdshader` | ScreenFX | Additive glow bleed |
| `outline.gdshader` | player AnimatedSprite2D | Ink outline |
| `pixel_dither.gdshader` | ScreenFX | Bayer dithering |
| `vignette.gdshader` | ScreenFX | Darkened corners |
| `wobble.gdshader` | ScreenFX | Vertical warp |

---

### 3.5 `addons/` Directory

#### `addons/UltimatePlatformerController.gd`

Third-party `PlatformerController2D` base class. `player.gd` extends this. Provides: acceleration/deceleration, coyote time, jump buffering, variable jump height, wall jump/slide/latch, multi-jump, dashing, crouching, rolling, ground pound, corner cutting, sprite flip, animation state machine.

---

## 4. Collision Layer Map

| Layer | Name | Used By |
|---|---|---|
| 1 | Solid tiles / floor | TileObject body, screen sensor mask, enemy movement mask |
| 2 | Enemy bodies | BaseEnemy body, Spike mask, Smasher mask |
| 4 | Enemy hitboxes | `$Hitbox` Area2D in every enemy; player foot sensor mask |
| 8 | Player body sensor | `_body_sensor` layer; `$Hitbox` mask in enemies |
| 3, 5–7 | (unused) | — |

---

## 5. Skill Tree — Full Listing

Cost formula: `PATH_COSTS = [1, 3, 9, 27, 81, 243]` by BFS depth from root (`"ui"`). Skills with `cost_override` ignore the formula. Skills marked **non-toggleable** cannot be disabled after purchase.

### Branch: Interface (UI)

| Skill ID | Name | Requires | Cost | Effect |
|---|---|---|---|---|
| `ui` | Unlock UI | — | 1 | ROOT. Adds main menu, shop, settings. **Non-toggleable.** |
| `hud` | In-Game HUD | ui | 2 | Distance + token counters during play. **Non-toggleable.** |
| `pause_menu` | Pause Menu | hud | 2 | Esc/Back pauses; access shop/menu mid-run |
| `ui_polished` | Polished UI | ui | 4 | Rounded panels, smooth hover animations, custom colours |
| `main_menu_extras` | Menu Polish | ui_polished | 3 | Animated title intro, button SFX hooks |
| `home_polish` | Nicer Home | main_menu_extras | 3 | Redesigns main menu layout and animations |
| `stats_menu` | Stats Menu | ui | 2 | Stats screen — playtime, jumps, longest run, etc. |
| `player_name` | Player Identity | stats_menu | 2 | Set profile name; required for leaderboards |
| `leaderboard` | Leaderboard | player_name | 3 | Per-seed global leaderboards via Firebase |
| `skill_tree_polish` | Skill Tree Polish | main_menu_extras | 2 | Bezier curves + animated pulse on active paths |
| `font_select` | Font Select | ui | 2 | Font picker in Settings |
| `debug_mode` | Debug Mode | hud | 5 | Debug Mode toggle in Settings; draws collision shapes |

### Branch: Juice

| Skill ID | Name | Requires | Cost | Effect |
|---|---|---|---|---|
| `juice_squash` | Squash & Stretch | ui | 2 | Player and floor squish on jump/land |
| `hit_flash` | Hit Flash | juice_squash | 1 | White flash on stomp or stun |
| `impact_freeze` | Impact Freeze | juice_squash + camera_shake | 2 | Brief time freeze on heavy impacts |
| `motion_trail` | Motion Trail | juice_squash + sprint | 2 | Trailing afterimage behind player |
| `footstep_dust` | Footstep Dust | juice_squash | 1 | Dust puffs while sprinting |
| `tear_effects` | Tear Effects | juice_squash | 3 | Things shatter into rigid-body pieces |
| `blood_splats` | Blood Splats | juice_squash | 2 | Circular splatter on death |
| `blood_marks` | Blood Stains | blood_splats | 2 | Persistent splat marks on the level floor |
| `combo_system` | Combo System | juice_squash | 4 | Airtime/stomp combo multiplier + xN popup |
| `combo_bounce` | Bouncy Combo Text | combo_system + main_menu_extras | 2 | Combo popups spring in with TRANS_BACK |
| `sfx` | Sound Effects | juice_squash | 3 | All in-game SFX |
| `music` | Music | sfx | 4 | Background music cross-fading between scenes |
| `wind_effect` | Wind Effect | combo_system + sfx | 3 | Wind lines + ambient wind roar at high combos |

### Branch: Camera FX

| Skill ID | Name | Requires | Cost | Effect |
|---|---|---|---|---|
| `camera_shake` | Camera Shake | ui | 2 | Camera shakes on big impacts |
| `dynamic_zoom` | Dynamic Zoom | camera_shake + parallax | 3 | Camera zooms out over wide gaps |
| `near_miss_slowmo` | Near-Miss Slow-Mo | impact_freeze | 3 | 30%-chance cinematic slow-mo near hazards |

### Branch: Graphics

| Skill ID | Name | Requires | Cost | Effect |
|---|---|---|---|---|
| `drawn_floors` | Drawn Floors | ui | 2 | Replaces primitive blocks with hand-drawn wavy platforms |
| `foliage` | Foliage | drawn_floors | 1 | Grass tufts on grounded platforms |
| `palette_switcher` | Palette Switcher | drawn_floors | 3 | Colour palette picker in Settings |
| `particles` | Particles | drawn_floors | 2 | Dust on landing, smoke on death, sparks on stomp |
| `player_sprite` | Player Sprite | drawn_floors | 2 | Character art replaces the rectangle |
| `sprite_animations` | Sprite Anims | player_sprite | 3 | Idle/run/jump/hurt animations |
| `parallax` | Parallax Backdrop | drawn_floors | 3 | Multi-layer scrolling background hills |
| `clouds` | Clouds | parallax | 2 | Soft drifting clouds |
| `sky_color` | Sky Colours | parallax | 2 | Sky colour picker in Settings |
| `adaptive_sky` | Adaptive Sky | sky_color | 3 | Colour/palette drifts over the run |

### Branch: Enemies

| Skill ID | Name | Requires | Cost | Bonus |
|---|---|---|---|---|
| `enemies_basic` | Basic Enemies | ui | 1 | Frogs + kobolds appear. +20% token gain. **Non-toggleable.** |
| `enemy_sprites` | Enemy Sprites | enemies_basic | 2 | Sprite art for enemies, spikes, smashers |
| `enemies_more` | More Enemies | enemies_basic | 2 | Bats + big frogs appear. +20% token gain (40% total). |
| `enemies_advanced` | Adv. Enemies | enemies_more | 3 | Bombs + shooters + drills + jumpers. +20% (60% total). |
| `smashers` | Smashers | enemies_more | 2 | Ceiling hammers appear. +20% (80% total). |
| `sprite_explosion` | Sprite Explosions | enemies_advanced + particles | 2 | Bombs use frame-animation explosion |

### Branch: Level

| Skill ID | Name | Requires | Cost | Effect |
|---|---|---|---|---|
| `procgen` | Full Procedural | ui | 4 | Full template library: stairs, platforms, combos. **Non-toggleable.** |
| `coins` | Coins | procgen | 3 | Coins appear in levels; collect for bonus tokens |
| `level_library` | Level Library | coins | 5 | Seeds saved; Replay button; favourites; per-seed bests |
| `daily_level` | Daily Level | level_library | 4 | One shared seed per calendar day |

### Branch: Moves

| Skill ID | Name | Requires | Cost | Effect |
|---|---|---|---|---|
| `sprint` | Sprint | ui | 2 | Higher top speed (820 px/s) |
| `double_jump` | Double Jump | sprint | 3 | Second jump in mid-air |
| `wall_jump` | Wall Jump | double_jump | 3 | Jump off walls during a slide |
| `fast_mode` | Fast Mode | sprint | 3 | Toggle in Settings: 1.35× speed + score bonus |

### Branch: Shaders

| Skill ID | Name | Requires | Cost | Effect |
|---|---|---|---|---|
| `vignette` | Vignette | ui_polished | 2 | Darkened corners |
| `chromatic_aberration` | Chromatic Aber. | vignette | 2 | RGB channel split (pulsed on impact/death) |
| `crt_filter` | CRT Filter | chromatic_aberration | 3 | Scanlines + screen curvature |
| `wobble_shader` | Air Warp | crt_filter | 3 | Screen warps during freefall |
| `color_grading` | Color Grading | drawn_floors | 2 | Warm filmic tint |
| `outline` | Sprite Outline | player_sprite | 2 | Dark ink outline around player |
| `fog_cover` | Fog Cover | vignette | 3 | Dark fog swallows the screen bottom |
| `pixel_dither` | Pixel Dither | crt_filter | 4 | Bayer ordered dithering |
| `neon_glow` | Neon Glow | chromatic_aberration | 4 | Additive glow halo on bright elements |

---

## 6. Combo System Deep-Dive

**File:** `combo_system.gd` — autoloaded CanvasLayer at layer 80.

### How Combos Work

The combo system rewards staying airborne and stomping enemies in a chain.

**Starting a combo:**
- Leaving the floor upward (jumping or being bounced) calls `notify_airborne(true)` → `_begin_combo()`.
- Stomping an enemy while not in a combo also starts one via `notify_stomp()`.

**Building the multiplier:**
- Every `COMBO_TICK_SECS` (1.5 seconds) of continuous combo time adds +1 to the multiplier.
- Stomping an enemy with a `combo_bonus` property adds instantly: regular enemies +0, bouncy/spring enemies +2, Jumper +10.
- Formula: `multiplier = floor(elapsed_seconds / 1.5) + stomp_bonus_total`.

**Ending a combo:**
- Landing on the floor ends the combo immediately via `notify_airborne(false)` → `_end_combo()`.
- If the player has been on the ground for more than 0.35 seconds without a stomp bonus, the combo ends.
- **X-stall rule**: if the player's world x position has not changed by more than 2 pixels for more than **0.5 seconds** while a combo is active, the combo ends. This prevents combos from persisting while the player is stuck against a wall.

**Token multiplier:**
- While a combo is active, `Global.token_multiplier` is scaled by `max(1, multiplier)`.
- Stomping mid-combo awards `50 × token_multiplier()` bonus points.

**Popups:**
- A persistent live `x{N} / {elapsed}s` label pins to the top-right and grows/jitters as the multiplier rises.
- Each multiplier tick spawns a bucketed praise word near the player (bucketed by multiplier tier: Fresh → Juicy → Sizzling → Developed → INFERNO).
- Stomps spawn a random stomp word ("STOMP!", "POW!", etc.) at the stomp position.
- New personal-best combos spawn a "NEW BEST!" banner.

**Color ramp:**
- x1–x2: warm yellow
- x3: orange
- x4: red
- x5+: rainbow hue cycling
- x6+: positional jitter on the live label

**Wind effect** (when `wind_effect` skill is owned):
- 14 `Line2D` nodes animate left-to-right across the screen when `multiplier > 3`.
- Lines fade in/out at screen edges, randomized speed and Y position.
- AudioManager fades in a wind ambient loop.

**Gating:** entire system is gated by `Global.is_unlocked("combo_system")`. `notify_airborne` and `notify_stomp` silently no-op if unowned.

---

## 7. Audio System Deep-Dive

**File:** `audio_manager.gd` — autoloaded.

### SFX Pool

`AudioManager` maintains a pool of `AudioStreamPlayer` nodes for one-shot effects. Each call to `play(key, vol_db, pitch_var)` picks an idle player from the pool (or the least-recently-used if all are busy), loads the sound keyed by `key`, applies volume and random pitch variation, and starts playback.

`play_at(key, world_pos, vol_db)` calculates attenuation based on how far `world_pos` is from the screen center and passes the adjusted volume to `play()`.

**Feature gate:** all SFX require the `"sfx"` skill. If not owned, `play()` and `play_at()` silently no-op.

### Music System

`play_music(key, fade_duration)` cross-fades to a new music track:
1. Fades out the current track over `fade_duration` seconds.
2. Starts the new track faded in over the same duration.
3. Loops the new track.

Music keys and their scenes:
| Key | Scene |
|---|---|
| `"main_menu"` | Main menu |
| `"gameplay"` | In-game level |
| `"shop"` | Shop / skill tree |
| `"glitch"` | Glitch sequence (precedes silence) |

**Feature gate:** `"music"` skill.

### Glitch Sequence

`play_glitch_sequence(go_silent)` is called by `ScreenFX.trigger_glitch()`:
1. Plays glitch SFX.
2. Cross-fades to the glitch music track.
3. After the glitch track plays through, fades to silence (if `go_silent = true`).

### Wind Loop

`set_wind_audio(active)` fades the wind ambient loop in or out. Called by `ComboSystem` when combo multiplier crosses `WIND_COMBO_THRESHOLD`. **Feature gate:** `"wind_effect"` skill.

### UI Click Wiring

`connect_ui_clicks(root)` recursively finds all `Button` nodes in `root` and connects their `pressed` signal to a `"ui_click"` one-shot sound. Called in `_ready()` of every menu CanvasLayer.

---

## 8. Screen FX Pipeline

**File:** `screen_fx.gd` — autoloaded CanvasLayer at layer 90.

### Architecture

Each pass uses a `BackBufferCopy` + `ColorRect` pair. In GL Compatibility, `hint_screen_texture` only receives data from the most recent BBC before the draw call. Without a per-pass BBC, every pass after the first would read stale/black data. `_add_pass()` inserts its own BBC so each effect sees the composited output of all prior effects.

### Pass Conditions

- All passes: require their feature key to be unlocked AND `Global.use_primitives = false`.
- `fog_cover`: additionally requires `current_scene.name == "Level"` (not shown in menus).
- `crt_filter`, `wobble_shader`, `pixel_dither`, `neon_glow`: skipped on lightweight targets (Web, Android, iOS).

### UI Layer Ordering

| Layer | Content |
|---|---|
| < 90 | Game world, backgrounds, ComboSystem wind lines + popups |
| 90 | ScreenFX (all post-processing passes) |
| 95 | All UI: HUD, pause, game-over, main menu, shop, settings |
| 100 | DebugOverlay |

UI at layer 95 renders AFTER ScreenFX, so chromatic aberration, CRT filter, vignette, etc. do NOT apply to any UI text, panels, or buttons.

### API

```gdscript
# Bump chromatic aberration amount then decay over duration seconds.
ScreenFX.kick_chromatic(amount: float = 0.022, duration: float = 0.35)

# Max chromatic kick + glitch audio + silence.
ScreenFX.trigger_glitch(go_silent: bool = true)

# Set each frame from player.gd to drive wobble_shader intensity.
ScreenFX.wobble_intensity = 0.0..1.0
```

---

## 9. Level Generation System

**File:** `level_generator.gd`

### Seed System

- **Before `procgen`**: `STARTER_SEED = 42024` is forced. Runs are identical so players can learn the layout.
- **After `procgen`**: If `current_seed == 0`, `rng.randomize()` picks a new seed in range `[0, 923521)` (= 31^4, keeping codes to 4 characters in `Global.SEED_ALPHABET`). Seeds can also be entered manually from the Level Library.

### Template Blocks

Each run places 40 template blocks (`level_width_blocks`) end-to-end. Blocks snap by matching the right-edge solid row of one block to the left-edge solid row of the next, creating seamless height transitions without constraint solving.

**Adding a new template:**
```gdscript
{ "pattern": [
	"..X.....",
	"........",
	"........",
	"########"
  ],
  "X": "my_new_enemy"
}
```
Then add `"my_new_enemy"` to `_spawn_entity()` and the `ENTITY_GATES` dict.

### Tile Strips

Rather than one `TileObject` per `#`, contiguous runs of `#` in a row are grouped into a single `TileStrip` spanning N tiles. Strips are 3 tile-heights deep. After all strips are placed, `_link_strip_neighbors()` suppresses shared interior outline borders on adjacent strips.

### Foliage Suppression

Foliage is suppressed on:
1. Strips where the row immediately below has empty/abyss cells (floating platform).
2. Strips where any row below the current one in the same block also contains `#` (stair steps).

This prevents grass from appearing on the sides of steps or mid-air on floating platforms.

### Entity Spawning

Entities are spawned in a second pass after all tiles. `_is_entity_allowed(entity_id)` checks `ENTITY_GATES[entity_id]` against `Global.is_unlocked()`. This means enemies simply don't appear if their tier isn't unlocked — no need to modify templates.

---

## 10. Meta-Progression and Save System

### Token Economy

Tokens are the only currency. They are awarded on death via `Global.on_player_death(distance_tiles)`:
- Base = `distance_tiles` × distance-per-token rate
- Multiplied by `Global.token_multiplier` (1.0 + enemy bonus up to 0.8 + fast mode bonus)
- Also multiplied by the live `ComboSystem.token_multiplier()` during the run

Tokens spent in the shop unlock skills. Bought skills are permanent; spending does not refund on death.

### Enemy Token Bonuses

Stacking multipliers from the enemy tier skills:
| Skill | Bonus |
|---|---|
| `enemies_basic` | +20% |
| `enemies_more` | +20% (40% total) |
| `enemies_advanced` | +20% (60% total) |
| `smashers` | +20% (80% total, maximum) |

### Save Data

`Global.save_state()` writes `user://save.dat` as a binary `var`. Contents:
- `unlocked: Dictionary` — feature key → bool
- `tokens: int`
- `stats: Dictionary` — all-time stat counters
- `level_library: Array` — seed entries with distance/favourite flag
- `settings_cfg: Dictionary` — all settings

`Global.load_state()` reads it back on boot.

### Tutorial Run

The very first run (`not Global.tutorial_seen`) is treated specially:
- `global.gd` activates a `fake_unlocks` array: temporarily grants a set of skills for the tutorial run so the first run feels more complete.
- On death, `tutorial_death_overlay.gd` shows an onboarding message instead of the normal game-over screen.
- After the tutorial run, `Global.tutorial_seen = true` is saved.

---

## 11. How to Add a New Enemy

### Step 1 — Create the scene

1. Duplicate `enemies/base_enemy.tscn` → `enemies/my_enemy.tscn`.
2. Scene tree:
   ```
   MyEnemy (CharacterBody2D)   ← root, with my_enemy.gd attached
   ├── CollisionShape2D         ← physics body collision
   └── Hitbox (Area2D)
	   └── CollisionShape2D     ← contact zone that kills the player
   ```

### Step 2 — Write the script

```gdscript
extends BaseEnemy

@export var my_speed: float = 200.0

func _ready() -> void:
	super._ready()
	tear_size  = Vector2(64, 64)
	tear_color = Color(1.0, 0.5, 0.0)
	var coll = $CollisionShape2D
	if coll and coll.shape is RectangleShape2D:
		coll.shape.size = Vector2(64, 64)

func _custom_process(delta: float) -> void:
	if not player: return
	var dir = sign(player.global_position.x - global_position.x)
	velocity.x = dir * my_speed

func _draw() -> void:
	if Global.use_primitives:
		draw_rect(Rect2(-32, -32, 64, 64), Color(1.0, 0.5, 0.0))
```

### Step 3 — Register in level_generator.gd

1. Preload scene: `@export var my_enemy_scene: PackedScene = preload("res://enemies/my_enemy.tscn")`
2. Add to `_spawn_entity()`: `"my_enemy": inst = my_enemy_scene.instantiate()`
3. Add to `ENTITY_GATES`: `"my_enemy": "enemies_basic"` (or whichever tier)
4. Add to `TEMPLATES` with a new character.

### Step 4 — Add sprite animation (optional)

```gdscript
if not Global.use_primitives:
	var anim = AnimatedSprite2D.new()
	var frames = SpriteFrames.new()
	frames.add_animation("walk")
	for f in range(8):
		var tex = load("res://assets/animations/my_enemy/" + str(f) + ".png")
		if tex: frames.add_frame("walk", tex)
	frames.set_animation_speed("walk", 12.0)
	frames.set_animation_loop("walk", true)
	anim.sprite_frames = frames
	anim.scale = Vector2(0.4, 0.4)
	add_child(anim)
	anim.play("walk")
```

### Step 5 — Override stomp behavior (optional)

```gdscript
func stomp_by(stomper: Node2D) -> void:
	if _is_dying: return
	die()
	stomper.set("velocity", Vector2(stomper.velocity.x, -1200))
	if stomper.has_method("shake_camera"):
		stomper.shake_camera(20.0, 0.4)
```

---

## 12. How to Change or Add Controls

Bindings are registered in `global.gd::_initialize_input_map()`. Change values in `input_configs`:

```gdscript
var input_configs: Dictionary = {
	"left":  KEY_LEFT,
	"right": KEY_RIGHT,
	"jump":  KEY_Z,
	"dash":  KEY_X,
}
```

**Adding a new action:**
1. Register in `global.gd`: `input_configs["glide"] = KEY_Q`
2. Use in `player.gd`: `if Input.is_action_pressed("glide"): velocity.y -= 200 * delta`

**Adding gamepad support:**
```gdscript
var joy_event = InputEventJoypadButton.new()
joy_event.button_index = JOY_BUTTON_A
InputMap.action_add_event("jump", joy_event)
```

---

## 13. How to Add a New Obstacle

### Option A — Static instant-kill area (like Spike)

```gdscript
extends Area2D
func _ready() -> void:
	body_entered.connect(_on_body_entered)
func _on_body_entered(body: Node2D) -> void:
	if body is BaseEnemy:
		body.die_torn(body.velocity)
	elif body.has_method("die"):
		body.die()
```

### Option B — Triggered falling obstacle (like Smasher)

1. Extend `Area2D`.
2. Add a downward `RayCast2D` for floor contact.
3. Use a `state` string + `match state:` in `_process()`.
4. Build a one-way top-cap `StaticBody2D` in `_ready()` so entities can stand on top.

### Option C — Moving platform

```gdscript
extends StaticBody2D
@export var move_distance: float = 400.0
@export var move_speed: float = 100.0
var _direction: int = 1
var _start_x: float
func _ready(): _start_x = global_position.x
func _physics_process(delta):
	global_position.x += _direction * move_speed * delta
	if abs(global_position.x - _start_x) > move_distance:
		_direction *= -1
```

### Option D — Projectile

Follow `bullet.gd`: extend `BaseEnemy` with `gravity_scale = 0`, constant horizontal velocity in `_custom_process()`, `die()` on `is_on_wall()`.

---

## 14. How to Add More Juice

### Camera shake from any entity

```gdscript
var players := get_tree().get_nodes_in_group("player")
if not players.is_empty() and players[0].has_method("shake_camera"):
	players[0].shake_camera(35.0, 0.45)
```

### Screen freeze on any impact

```gdscript
Engine.time_scale = 0.05
await get_tree().create_timer(0.04, true, false, true).timeout
Engine.time_scale = 1.0
```

The `true, false, true` arguments mean: `process_always=true`, `process_in_physics=false`, `ignore_time_scale=true` — so the timer fires at real-world time regardless of `time_scale`.

### Tile ripple on player landing

```gdscript
for tile in get_tree().get_nodes_in_group("solid_tiles"):
	if tile == self: continue
	var dist = tile.global_position.distance_to(global_position)
	if dist < 300:
		tile.shake(3.0 * (1.0 - dist / 300.0), 0.2)
```

### Chromatic kick from any code

```gdscript
if Global.is_unlocked("chromatic_aberration"):
	ScreenFX.kick_chromatic(0.022, 0.35)
```

### Runtime CPUParticles2D burst

```gdscript
var poof = CPUParticles2D.new()
poof.emitting = true
poof.one_shot = true
poof.amount = 30
poof.lifetime = 0.6
poof.explosiveness = 0.95
poof.spread = 180.0
poof.gravity = Vector2(0, 400)
poof.initial_velocity_min = 100.0
poof.initial_velocity_max = 350.0
poof.scale_amount_min = 5.0
poof.scale_amount_max = 15.0
poof.color = Color(0.4, 0.8, 1.0)
get_parent().add_child(poof)
poof.global_position = global_position
poof.finished.connect(poof.queue_free)
```

---

## 15. How to Add Parallax Scrolling

Add under the root `Node2D` in `leve.tscn` (before `level_generator.gd` spawns tiles):
```
ParallaxBackground
├── ParallaxLayer  (motion_scale = Vector2(0.1, 0.1))   ← far
├── ParallaxLayer  (motion_scale = Vector2(0.35, 0.0))  ← mid
└── ParallaxLayer  (motion_scale = Vector2(0.7, 0.0))   ← near
```

Set `motion_mirroring = Vector2(texture_width_px, 0)` on each layer for seamless looping.

---

## 16. How to Add More Menus

### New standalone scene

1. Create `my_screen.tscn` as a `CanvasLayer` with `layer = 95` set in `_ready()`.
2. Navigate to it: `get_tree().change_scene_to_file("res://my_screen.tscn")`.
3. Navigate back: `get_tree().change_scene_to_file("res://main_menu.tscn")`.

### Adding it to the main menu

In `main_menu.gd::_ready()`, create a button and connect it:
```gdscript
var my_btn = Button.new()
my_btn.text = "My Screen"
my_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://my_screen.tscn"))
$Root/Buttons.add_child(my_btn)
```

### Gating behind a skill

Wrap the button creation in `if Global.is_unlocked("my_skill"):`.

---

## 17. How to Add Custom Particle Effects

All existing particle bursts are created entirely in code — no `.tscn` files needed. See §14 for a CPUParticles2D burst template.

For **continuous emitters** (e.g. running sparks):
```gdscript
var sparks = CPUParticles2D.new()
sparks.amount = 8
sparks.lifetime = 0.3
sparks.one_shot = false
sparks.explosiveness = 0.0
add_child(sparks)
# Toggle each frame:
sparks.emitting = is_on_floor() and abs(velocity.x) > 200.0
```

For **GPU particles** (> ~200 particles), use `GPUParticles2D` + `ParticleProcessMaterial`. Note: not available on very old GL Compatibility hardware — provide a `CPUParticles2D` fallback.

---

## 18. Debug Toggles Reference

Access: `Global.debug_toggles.get("key", false)`. Toggle at runtime via the debug overlay when `Global.debugText = true`.

| Key | Default | Effect |
|---|---|---|
| `auto_restart` | false | Skips game-over UI; reloads scene immediately after death |
| `keep_seed` | false | With `auto_restart`, reloads the exact same level seed |
| `show_collisions` | false | All collision shapes drawn in green via `_draw()` / `queue_redraw()` |
| `unlock_all` | false | `SkillsDB.prereqs_met()` always returns true (buy anything) |

**Adding a new toggle:**
1. Add to `debug_toggles` dict in `global.gd`.
2. Check anywhere: `if Global.debug_toggles.get("my_flag", false):`
3. The debug overlay checkbox list auto-updates — no extra registration needed.

---

## 19. License

This project is open source and available under the [MIT License](LICENSE).

---

*Updated July 2026. Update whenever architecture or skill tree changes significantly.*
