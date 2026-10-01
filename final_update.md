# Final update — story cuts, guided onboarding, Android launch prep

Version `1.0.0`, `version/code=1`. This is the last content update before the Android build.
Two systems were added (narrative cuts, forced onboarding) and the Android export gaps were closed
or documented below.

---

## 1. Story system

### New files

| File | What it is |
|---|---|
| `story_db.gd` | Autoload `StoryDB`. Pure data: the cast, every line, and the trigger rules. No presentation logic. |
| `story_cut.gd` | `CanvasLayer` (layer 210) that plays a cut. One block on screen at a time, typewriter, tap to advance. |

### The cast

`StoryDB.VOICES` maps a speaker id to font, size, colour, BBCode effect, typing speed and tick volume.
Bodies render in a `RichTextLabel` with `bbcode_enabled`, which is what buys the per-voice motion.

| `who` | Reads as | Look |
|---|---|---|
| `narrator` | The unreliable narrator | Terminus, off-white, still |
| `purple` | The thing that took your game | ka1, `#9926E6`, `[shake]`, glitch SFX + chromatic kick |
| `princess` | The pink one | orange juice 2.0, `#FF8FD0`, `[wave]` |
| `soul` | The trapped soul — insists the narrator lies | Nervous, `#6FD9D0`, `[pulse]`, forced lowercase |
| `sponsor` | Corporate onboarding voice | nasalization-rg, `#4FE0FF`, forced uppercase |
| `system` | Machine chrome | Terminus, grey, wrapped in `[ … ]` |

Characters answer each other inside a single cut — a scene is a list of blocks, each with its own
`who`, so an exchange is just consecutive blocks.

### When cuts fire

`StoryDB.pending(at)` returns the first unseen scene whose conditions match, or `{}`. Call sites:

- `player.gd` death path → `pending("death")`, plays before the game-over card
- `shop.gd` `_ready()` → `pending("shop_open")`
- `main_menu.gd` `_ready()` → `pending("menu_open")`
- `level_generator.gd` `_ready()` → `pending("run_start")`

Shipped scenes: `death_3/5/7/10/15/21/30/50/100` (escalating taunts), `dist_250/600/1200` (distance
milestones), `buy_procgen` / `buy_enemies` / `buy_coins` / `buy_leaderboard` (the purple entity
objects to you rebuilding its world), `return_gap` (you were away), `hoard_tokens` (unspent tokens
piling up — the narrator gets passive-aggressive). The last two are `once: false`, so they can
recur; everything else records its id in `Global.story_seen` and never repeats.

`pending()` returns `{}` while `Onboarding.is_active()`, so ambient cuts never talk over the guide.

### Adding dialog — one dict, no code

Append to `SCENES` in `story_db.gd`:

```gdscript
{
    "id": "death_42", "at": "death", "mode": "black",
    "when": {"deaths_at": [42]},
    "blocks": [
        {"who": "narrator", "text": "Forty-two. A number people find meaningful."},
        {"who": "soul",     "text": "he googled it"},
    ],
},
```

`at` — `death` | `shop_open` | `menu_open` | `run_start` | `guide` (guide scenes never auto-fire;
`onboarding.gd` asks for them by id).
`mode` — `black` (opaque lore cut) | `scrim` (dark wash, live scene stays readable behind).
`when` keys, all optional and AND-ed together: `deaths_at: [int]`, `distance_at_least: int`,
`purchased: "skill_id"`, `days_away_at_least: float`, `unspent_tokens_at_least: int`,
`requires_unlocked: "key"`, `not_unlocked: "key"`. Omit `when` entirely to fire on the next
matching `at`. `once: false` lets a scene repeat across sessions.

Adding a **character** is the same shape — one entry in `VOICES`, then use its key as a `who`:

```gdscript
"gremlin": {"name": "SOMETHING IN THE WALLS", "font": FONT_NERVOUS, "size": 24,
    "color": Color(0.8, 0.9, 0.3), "fx_open": "[tornado radius=3]", "fx_close": "[/tornado]",
    "speed": 0.04, "tick_db": -12.0},
```

Optional per-voice flags: `upper`, `lower`, `prefix`, `suffix`, `glitch` (adds the purple entity's
screen-tear treatment).

`intro_cold_open` is in `SCENES` as a worked reference and is not wired to a trigger — the actual
intro runs through `tutorial_screen.gd`'s `SLIDES`, which now carries the same `who` keys and pulls
its fonts and colours from `StoryDB.VOICES` so the intro and the later cuts read as one system.

<!--CONT-->

Also rewritten with the full cast: `tutorial_death_overlay.gd` (the first-death sequence) now runs
narrator → glitch → purple → princess → soul → narrator → unlock screen, keeping its original
glitch choreography.

---

## 2. Guided onboarding

### New files

| File | What it is |
|---|---|
| `guide_finger.gd` | `CanvasLayer` (layer 215). The pointing hand + the input gate. |
| `onboarding.gd` | Autoload `Onboarding`. The forced first-run state machine. |

### The sequence

| Step | Screen | What happens |
|---|---|---|
| `buy_ui` | pre-UI game-over card (2nd death) | scrim cut → finger on **Buy UI** |
| `menu_shop` | main menu | congrats cut → finger on **Shop** |
| `shop_procgen` | shop | cut on *why procgen first* → tree pans to the node → finger on node → finger on **Buy** |
| `shop_enemies` | shop | cut on *enemies hurt but pay more* → pan → finger on node → **Buy** |
| `done` | — | never runs again |

The current step lives in `Global.onboard_step` and is saved, so the sequence survives the two scene
changes it crosses and an app kill mid-tutorial.

Each scene calls `Onboarding.attach(self, "<context>")` from `_ready()` — `"game_over_pre_ui"` from
`ui.gd`, `"main_menu"` from `main_menu.gd`, `"shop"` from `shop.gd`. Every other entry point no-ops.

### The rules you asked for, and where they live

- **Text advances one block at a time.** `story_cut.gd` shows a single block; a tap mid-typewriter
  completes that block, a tap when idle moves to the next, a tap on the last one closes the cut.
  Nothing is ever revealed all at once.
- **Finger appears on the last block.** `onboarding.gd` `await`s `cut.finished` before pointing.
- **Only the target is clickable.** `guide_finger.gd::_input()` calls
  `get_viewport().set_input_as_handled()` on every press outside the target rect, and lets presses
  inside fall through untouched. The finger node is added last under `get_tree().root`, so it sees
  `_input` first (Godot dispatches in reverse tree order). There is no invisible blocker rect, so the
  target keeps its normal hover and press feedback.
- **The shop pans to the target.** Reuses the existing `skill_tree_view.focus_on(sid)` (0.45 s tween
  to focus zoom); the finger waits 0.6 s for the pan to settle so it doesn't chase a moving node.
- **"If the node isn't unlocked that's a bug — don't point."** `onboarding.gd::_skill_ok()` refuses
  to point and `push_warning()`s if the skill is missing from `SkillsDB.SKILLS`, has unmet prereqs,
  is unaffordable, or isn't revealed in the tree; the step silently advances instead of locking the
  screen. Already-purchased targets skip without a warning — that is the normal path for a returning
  player.
- **The player can always afford the chain.** `Global._ensure_onboarding_funds()` runs on every death
  while onboarding is unfinished and floors the balance at `Global.onboarding_chain_cost()`, which
  sums live `SkillsDB.compute_cost()` for the unbought members of `Onboarding.CHAIN`
  (`ui`, `procgen`, `enemies_basic` — currently 1 + 1 + 1 = 3). It reads the real costs, so
  rebalancing the tree can't strand a new player.
- **Forced, no skip UI.** But nothing runs once the three skills are owned.

### Adjusting the finger art

`guide_finger.gd` has two tunables at the top:

```gdscript
const TIP_UV := Vector2(0.12, 0.02)          # where the fingertip sits inside the texture (0-1)
const DEFAULT_ANGLE := deg_to_rad(-114.0)    # which way the art points as authored (up-left)
```

`assets/pointing-finger.png` points up and to the left. If you redraw it pointing somewhere else,
change `DEFAULT_ANGLE`; if the tip lands off-target, nudge `TIP_UV`. The sprite pivots at the
fingertip, so those two constants are the whole calibration.

---

## 3. Changes to existing files

| File | Change |
|---|---|
| `project.godot` | `StoryDB` + `Onboarding` autoloads; `config/name` → "Minimum Viable Platformer"; added `config/version="1.0.0"` |
| `global.gd` | Persists `story_seen`, `onboard_step`, `last_played_unix`; computes `session_gap_days` on load; `onboarding_chain_cost()` + `_ensure_onboarding_funds()`; `reset_progress()` clears both new keys |
| `player.gd` | Death path plays a matching `pending("death")` cut before the game-over card |
| `ui.gd` | Pre-UI card attaches onboarding; post-UI hint line now pulls `StoryDB.taunt(cause, distance, deaths)`; Buy UI advances the step before the scene change |
| `main_menu.gd` | Attaches onboarding, plays `menu_open` cuts |
| `shop.gd` | Attaches onboarding, plays `shop_open` cuts, notifies `Onboarding` on a successful purchase |
| `skill_tree_view.gd` | Three public accessors — `screen_pos_of(sid)`, `node_screen_radius()`, `is_revealed(sid)` |
| `level_generator.gd` | Plays `run_start` cuts once the tutorial has been seen |
| `tutorial_screen.gd` | 3 slides → 6, each with a `who`; restyles per `StoryDB.VOICES` |
| `tutorial_death_overlay.gd` | Princess and soul beats after the purple entity's line |
| `export_presets.cfg` | See below |

---

## 4. Android — what was changed

| Setting | Was | Now | Why |
|---|---|---|---|
| `permissions/internet` | `false` | **`true`** | **Real shipped bug.** `leaderboard_service.gd` talks to Firestore over `HTTPRequest`. Without this permission every request fails silently on device — the leaderboard would have looked broken in production with no error. |
| `version/name` | `""` | `"1.0.0"` | Play Console rejects an empty version name |
| `package/name` | `""` | `"Minimum Viable Platformer"` | This is the launcher label under the icon |
| `user_data_backup/allow` | `false` | `true` | `user://meta.dat` holds all meta-progression. With backup off, a phone transfer wipes every token and unlock the player earned. |
| `application/config/version` | absent | `"1.0.0"` | Single place to read the build version from at runtime |
| `application/config/name` | `minimum-viable-platformer` | `Minimum Viable Platformer` | Shows in the window title and crash reports |

Left alone deliberately: `version/code=1` (correct for the first upload — bump it for **every**
subsequent Play upload, it must strictly increase), `architectures` (arm64-v8a + armeabi-v7a is the
right pair; Play requires the 64-bit slice), `screen/immersive_mode=true`, and
`package/unique_name="com.gunroar.minimumviableplatformer"` (once published this can never change).

---

## 5. Android — what you still have to do yourself

These need your accounts, files or a device. None can be done from the repo.

### 5.1 Release keystore — do this first, and back it up

```
keytool -genkeypair -v -keystore mvp-release.keystore -alias mvp \
        -keyalg RSA -keysize 2048 -validity 10000
```

Point Godot at it in **Editor → Editor Settings → Export → Android** (debug keystore) and in the
preset's *Keystore → Release* fields (or set `credentials/release_keystore` via env vars in CI).

**Keep this file and its passwords forever.** If you lose the keystore you cannot ship an update to
the same listing, ever — the app is orphaned and players have to reinstall a new one. Store a copy
somewhere that is not this machine. Do **not** commit it; add `*.keystore` and `*.jks` to
`.gitignore`.

If you'd rather not carry that risk, opt into **Play App Signing** when you create the listing —
Google holds the app signing key and you only manage an upload key that can be reset.

### 5.2 Android build template

Install it once via **Project → Install Android Build Template**, and install the Android SDK +
JDK 17 that Godot 4.4 expects (**Editor Settings → Export → Android** → *Android SDK Path*).

**The Play Store needs an AAB, and an AAB needs the gradle build.** Both are currently off:
`gradle_build/use_gradle_build=false` and `gradle_build/export_format=0` (APK). For a store upload,
set:

```
gradle_build/use_gradle_build=true
gradle_build/export_format=1        # 1 = AAB
gradle_build/min_sdk=""            # leave blank to inherit Godot 4.4's default (24), or set explicitly
gradle_build/target_sdk=""         # same — Play requires a recent target API level
```

Leave both off if you only want an APK to sideload for testing; that path is faster and needs no
Android SDK beyond the template. Flipping gradle on is also what you'd need for any plugin
(ads, IAP, Play Games), none of which this build uses.

### 5.3 Icons

All four icon fields are empty, so the build falls back to the Godot robot:

- `launcher_icons/main_192x192` — 192×192 PNG
- `launcher_icons/adaptive_foreground_432x432` — 432×432, art inside the centre 264×264 safe zone
- `launcher_icons/adaptive_background_432x432` — 432×432, usually a flat colour
- `launcher_icons/adaptive_monochrome_432x432` — 432×432 silhouette (Android 13+ themed icons)

Play also needs a **512×512 store icon** and a **1024×500 feature graphic**, uploaded in the console,
not in the export preset. `icon.svg` in the repo is the Godot default — replace it too.

### 5.4 Play Store listing

- Short description (80 chars) and full description (4000)
- At least **2 phone screenshots**; landscape, since `window/handheld/orientation=4` is sensor-landscape
- Content rating questionnaire — cartoon spikes and a mildly menacing purple entity; expect PEGI 7 / ESRB E10+
- **Data safety form** — see below, this is where the leaderboard matters
- Target audience and ads declaration (there are no ads)

### 5.5 Privacy policy — required, because the leaderboard collects data

`leaderboard_service.gd` sends to Firestore (`gigs-6f94d`):

- a **display name** the player types in
- their **score, distance and level seed**
- a **player id** derived from `OS.get_unique_id()`, persisted in settings

That last one is a persistent device identifier, which means Play's Data safety form must declare it
and you must host a privacy policy at a public URL before the listing can go live. A GitHub Pages
page is enough. It has to state what is collected, that it's stored in Google Firestore, that it's
used for the leaderboard only, that it isn't sold, and how a player can request deletion (give an
email address).

Also lock down the **Firestore security rules** before launch. If the default test-mode rules are
still active, anyone can read and overwrite every score in the database — and those rules expire on
a timer, which would take the leaderboard down without warning.

### 5.6 Pre-upload smoke test on a real device

1. Export a **release** APK, install on a phone (`adb install -r`), not just the editor.
2. Cold start with no save: intro cut → first death sequence → second death shows the finger on
   **Buy UI** → confirm taps elsewhere on the card do nothing → buy → menu congrats + finger on
   **Shop** → shop pans to Procgen, finger on node, finger on Buy → same for Basic Enemies → finger
   gone, shop fully interactive. Confirm you never had to grind for tokens.
3. Confirm the leaderboard actually submits (this is the internet-permission fix — it silently failed
   before).
4. Kill the app mid-onboarding and relaunch — it must resume on the same step.
5. Background the app during a run, return, confirm audio resumes and nothing is stuck paused.
6. Test on a tall phone (20:9). The stretch mode is `canvas_items` / `expand`, so the finger rects
   are computed in viewport space and follow — but `ui.gd` reflows its card by viewport width, so
   confirm the finger still lands on the button there and not only at 1280×720.
7. Check the back button (`ui_back`) on every screen — Android's gesture back maps to it.

### 5.7 Housekeeping before you ship

- `debug_overlay.gd` and `Global.debug_toggles` (`unlock_all`) — make sure there is no path to them
  in a release build.
- Several `print()` calls remain across gameplay scripts. They're harmless but noisy in `logcat`.
- `.gitignore` was extended this update to cover `*.keystore`, `*.jks`, `keystore.properties`,
  `*.apk` and `*.aab`. The `android/` build-template directory was already ignored.
- `export_presets.cfg` **is** tracked. Never put keystore passwords in it — Godot writes release
  credentials to `.godot/export_credentials.cfg`, which already exists here and is covered by the
  `.godot/` ignore rule. Confirm it stays out of `git status` before you push.

---

## 6. Verification status

**A Godot parse check has not been run.** Godot is not on `PATH` here; the only engine binary on this
machine is `Downloads\Godot_v4.3-stable_win64.exe`, and this project declares
`config/features=PackedStringArray("4.4", ...)`. Running `--check-only` under 4.3 against a 4.4
project reports version-mismatch noise rather than real script errors, so it would have been a
misleading green light. **Open the project in Godot 4.4 once before exporting** — autoload and
GDScript errors surface immediately in the editor's Errors panel.

What *was* verified, by reading the files:

- Both autoloads are registered in `project.godot` (`StoryDB`, `Onboarding`) and resolve to files that exist.
- Every symbol the new code reaches for across a script boundary exists at its call site:
  `Global.{story_seen, onboard_step, last_played_unix, session_gap_days, last_run_distance,
  last_death_cause, tokens, stats, unlocked}`; `SkillsDB.{SKILLS, compute_cost, is_purchased,
  prereqs_met, can_afford, purchase, get_tree_pos, get_feature_key, ROOT_ID}`;
  `AudioManager.play` keys `tick` / `ui_click` / `glitch_sfx`.
- Every node the finger targets is a real script variable on its host — `ui.gd::btn_buy_ui`,
  `main_menu.gd::shop_btn`, `shop.gd::tree_view`, `shop.gd::d_buy` — so the `host.get("…")`
  lookups in `onboarding.gd` resolve.
- The skill ids the guide walks (`ui`, `procgen`, `enemies_basic`) all exist in `SkillsDB.SKILLS`.
- All five fonts and `assets/pointing-finger.png` exist on disk.
- Signal ordering in the shop: `shop.gd` connects `tree_view.skill_selected` in `_ready()` before
  `Onboarding` connects its own handler, so the detail panel (and `d_buy.disabled = false`) refreshes
  before the finger tries to point at Buy.
- Pause bookkeeping across back-to-back cuts: `story_cut.gd::_close()` restores `get_tree().paused`
  *before* emitting `finished`, so the next cut in a chain reads the correct prior state.

Four defects were found and fixed during that pass: an ambient cut that could fire underneath the
finger (`Onboarding._running`, set synchronously before the first `await`); keyboard panning escaping
the input gate (`Input.is_action_pressed()` polling ignores `set_input_as_handled()` — now guarded by
`Onboarding.is_active()` in `skill_tree_view.gd::_process`); a literal `[` in the `system` voice that
the BBCode parser would have swallowed (`[lb]`); and `get_total_character_count()` returning 0 before
shaping, which collapsed the typewriter into an instant reveal (now falls back to raw string length).

The cold-start run in §5.6 step 2 is the real test. To repeat it, delete
`%APPDATA%\Godot\app_userdata\minimum-viable-platformer\meta.dat`.

