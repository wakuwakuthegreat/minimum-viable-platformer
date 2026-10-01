# Collision / Parry / Death Map

How the player interacts with hazards after the collision + parry rework.

## Collision layers
- **Layer 1** — solid tiles (floor/walls) **and** the player `CharacterBody2D`. The
  player physically collides with layer 1 only, so it walks on tiles and passes
  *through* enemy bodies (which live on layer 2).
- **Layer 2** — enemy bodies (`BaseEnemy`), `Smasher`, `Spike`.
- **Layer 4** — enemy `Hitbox` Area2D (detects the player body sensor).
- **Layer 8** — player body sensor Area2D (detected by hitboxes and coins).

## Stomp vs. hit (the single source of truth)
`player.is_stomp_on(other_y)` → `true` only when the player is **descending**
(`velocity.y > 40`) **and** its centre is **clearly above** the other body's
centre (≥ 30 px). Only **stompable** enemies (`base_enemy`, `bomb`) consult it:
- stomp → the foot sensor bounces the player, no death.
- anything else (side contact, or something dropping onto the head) → **lethal**.

**Spikes, drills and smashers are NOT stompable.** Landing on them kills — they
never consult `is_stomp_on`. (A smasher's flat top is still safe to stand on, but
that is handled by a one-way `StaticBody2D` + an explicit "standing on top"
guard, not by the stomp rule.)

## Edge-triggered vs. continuous contact
`Area2D.body_entered` / `area_entered` only fire on the FRAME an overlap begins.
An overlap that already existed — an idle drill the player is standing inside
when it starts to drop, an enemy that spawned on the player, a hazard whose
monitoring was toggled — is silently missed, so the hazard "passes through."
Every hazard therefore ALSO polls its current overlaps **every frame**:
- `base_enemy._check_player_contact()` — re-runs the hitbox hit logic.
- `spike._process` / `smasher._process` — `get_overlapping_bodies()`.
- `drill._process` — `overlaps_body(player)`.
This makes contact **level-triggered**, closing the pass-through holes.

## Parry flow
1. **Look-ahead scan** (`player._scan_for_parry`, every physics frame): a box
   reaching *ahead of* and *around* the player (forward + upward, to catch
   descending smashers/drills) checks the `hazards` group. When a threatening
   hazard first enters the box, the parry window opens **before** contact.
   `_parry_seen` prevents re-offering the same hazard while it stays in the box.
2. **Window** (`try_open_parry_window`): time drops to 0.15, a golden "!" flashes.
3. **Contact during an open window**: every hazard checks
   `_parry_window_timer > 0` and *skips the kill*, letting the window resolve —
   so a hazard is only ever passed through **after a successful parry**.
4. **Jump pressed** → `_execute_parry`:
   - **bomb** → `parry_detonate()` (explodes with knockback/visuals but cannot
     kill the parrying player) + launch the player **up**.
   - **stomp-style** parry on a stompable enemy → destroy it.
   - **smasher / drill / spike / side hit** → launch the player **up** and
     `_deflect_and_phase` the hazard (disables its Area2D monitoring / enemy
     Hitbox for ~1.1 s) so the player passes cleanly through.
   - a **backflip** flourish plays.
   - the cinematic camera punches in, hitstops, then `_begin_parry_slowmo`
     drops time and `_process` eases it back to 1.0 over ~0.9 s wall-clock —
     the "camera slows then speeds back up" beat.
5. **Window lapses with no parry** (`_tick_parry`): if the attacker is still on
   top of the player (`_attacker_in_contact`) the hit lands → die; if the player
   dodged clear, no penalty.

## Hazard entry points
- `base_enemy._on_hitbox_area_entered` — frog, big_frog, kobold, bat, jumper,
  shooter, rock.
- `bomb._bomb_contact` (from hitbox + body_entered).
- `smasher._on_body_entered` → `_hit_player`.
- `drill._on_body_entered` → `_hit_player`.
- `spike._on_body_entered`.

All of them: skip on genuine stomp → skip if a window is open → otherwise open a
last-chance window → otherwise kill.
