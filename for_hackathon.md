# RevenueCat Shipaton 2026 — Integration Plan

**Status:** game-side integration implemented (2026-08-26). Everything requiring
the RevenueCat dashboard, Play Console, the plugin binaries, or a real ad network
is still outstanding — see §3.5.
**Written:** 2026-08-26 · **Submission deadline:** 2026-09-30, 11:45pm PDT (~5 weeks)
**App:** Minimum Viable Platformer (Godot 4.5, `com.gunroar.minimumviableplatformer`)

---

## 1. Eligibility check

| Rule | Our position |
|---|---|
| Must use RevenueCat SDK for ≥1 in-app/web purchase, **or** serve RevenueCat Ads | Game-side integration done (§3.4). Still needs the plugin binaries, API keys and store products (§3.5) |
| Must be iOS / iPadOS / macOS / Android | Android. An `Android` export preset already exists (APK, gradle build **off**) |
| Must be **fully published** to App Store / Google Play / Samsung Galaxy Store by the deadline | Not published anywhere yet. This is the single hardest deadline item — Play review can take days |
| First public version released **during** the Submission Period (Jul 31 – Sep 30, 2026) | Likely fine. The existing web build (`minimum-viable-platformer.html`) is **not** an "eligible store" under the rules, which name only Apple, Google Play, and Samsung. A prior web release does not burn eligibility |
| Free trial **or** promo code for judges | Plan: keep the game free to play, generate Play promo codes for the paid unlock |
| Accessible from the United States | Set Play distribution to all countries incl. US |
| 1024×1024 icon | Have `minimum-viable-platformer.512x512.png` — needs a 1024 render |
| Screenshot 1179×2556, no device frame | Must capture on a portrait phone build. Note `project.godot` sets `window/handheld/orientation=4` — verify what that actually gives us on device |
| Demo video < 2 min on YouTube/Vimeo | To record |

**Blocking risk:** Google Play requires new *personal* developer accounts to run a closed test with 12 testers for 14 days before production access is granted. If the account is personal and recently created, **start that clock immediately** — it is the difference between shipping and not. Verify account type first; it decides the whole timeline.

---

## 2. Categories to target

Pick the ones where the game's existing design is already the argument. Ranked:

1. **Best Game Award** — primary. Judged on fun, unique progression/replayability, and "monetization fit that suits the genre."
2. **Catvertising Award** (RevenueCat Ads) — strongest thematic fit, see §4. The criteria explicitly reward ads that "help users access, unlock, or experience the app in a richer way." That is literally this game's premise.
3. **HAMM Award** — requires articulating pricing/packaging and conversion numbers. Cheap to enter once §4 exists.
4. **#BuildInPublic Award** — the largest non-grand prize pool ($30k/$20k/$10k) and the criteria state *audience size does not matter*. Highest expected value per hour of effort. Requires posting the dev journey tagged `#Shipaton` from now through Sep 30.
5. **RevenueCat Design Award** — plausible; the game already has tear effects, blood splats, screen FX, a combo system, adaptive sky.
6. **Next Gen Award** — only if you are currently an enrolled student with an academic email. If so this is a *far* easier path: no store release, no developer account, just a demo video plus a public open-source repo. **Check this first — it changes the entire plan.**

Grand Prize shortlisting is revenue-ranked; not realistic in five weeks. Not a target, though the RevenueCat dashboard reports whatever we make anyway.

---

## 3. Technical integration

### 3.1 The Godot 4.7 question

The `godotx_revenue_cat` README states Godot 4.7-stable. **Do not upgrade the engine on that basis without testing first.** The plugin is not a GDExtension — it is a prebuilt Android `.aar` and iOS `.xcframework` consumed through Godot's Android plugin v2 API and reached via `Engine.get_singleton("GodotxRevenueCat")`. That API has been stable since Godot 4.2, so there is a good chance it drops into 4.5 unchanged and the README simply reflects the version the demo project was built with.

**Do this before anything else (half a day, hard gate):**

1. Branch first.
2. Copy `addons/godotx_revenue_cat/` and `android/revenuecat/` into the project.
3. Project → Install Android Build Template. Flip `gradle_build/use_gradle_build` to `true` in the Android preset (currently `false`, `export_presets.cfg:69`) and set `export_format` to AAB for Play.
4. Enable the plugin, build a debug APK, and check that `Engine.has_singleton("GodotxRevenueCat")` returns true on a real device.
5. If it works on 4.5 → **skip the engine upgrade entirely.** If it fails, only then evaluate 4.7, and budget 2–3 days for regressions across the 40+ scripts here — particularly `tear_effect.gd`, the files in `shaders/`, and `leaderboard_service.gd`'s HTTP usage.

Fallback if the plugin refuses to cooperate: RevenueCat's REST API plus Google Play Billing through a thinner community billing plugin. Slower and worse — plan C only.

For **purchases** this plugin is the whole answer, and purchases alone satisfy the hackathon's SDK requirement. Its ad-side limits (§4.1) do not affect any of that.

### 3.2 New autoload: `iap_manager.gd`

Everything RevenueCat-related goes behind one wrapper so the game still runs in the editor, in web builds, and on desktop where the singleton does not exist. This matters: `main.tscn` and the whole dev loop must not break.

```
project.godot [autoload]
  IAP="*res://iap_manager.gd"     # LAST — needs Global's save + LeaderboardService's id
```

Responsibilities:

- `_ready()`: detect the singleton; if absent set `available = false` and no-op every call.
- `initialize(api_key, user_id, OS.is_debug_build())` with a `goog_...` key on Android.
- Cache `CustomerInfo` and expose `has_entitlement(id) -> bool` **synchronously** off that cache. The shop UI redraws constantly and cannot await.
- Signals out to the game: `entitlements_changed`, `purchase_succeeded(product_id)`, `purchase_failed(reason)`, `restore_finished`.
- Persist last-known entitlement state through `Global.save_state()` (`user://meta.dat`) so a cold start offline still honours a purchase. Treat that cache as advisory and re-sync on the next `customer_info_changed`.
- `login(user_id)` — the game already has a leaderboard identity in `leaderboard_service.gd`. Reuse that ID so purchases follow the player across reinstalls; otherwise every install is a fresh anonymous RevenueCat user.

**API key handling:** the `goog_` public SDK key is safe to ship, but keep it in one named const with a comment noting it is intentionally public, rather than scattered inline.

### 3.3 Touchpoints in existing code

| File | Change |
|---|---|
| `global.gd` | `is_unlocked()` / `gfx()` already gate every feature in the game. Add an entitlement-aware branch alongside the existing `debug_toggles.unlock_all` check — this is the cleanest possible seam and most of the work is already done |
| `shop.gd` | The skill-tree shop is the natural paywall surface. Add a store row and an "out of tokens?" state that calls into the paywall |
| `skills_db.gd` | Add IAP-backed entries, or a `premium: true` flag on a small set of cosmetic-only skills |
| `main_menu.gd` | "Restore Purchases" and "Manage Subscription" entries (both stores require these to be reachable) |
| `ui.gd` / `tutorial_death_overlay.gd` | The death screen is where a rewarded-ad revive offer lives |
| `settings.gd` | Restore / manage entry point, privacy policy link (Play requires one) |

### 3.4 What is implemented

| Piece | Where |
|---|---|
| RevenueCat wrapper: init, entitlements, purchase, paywall, restore, manage-subscription, rewarded-ad abstraction | `iap_manager.gd`, autoloaded as `IAP` (listed **last** — it reads Global's loaded save and LeaderboardService's `player_id` at `_ready`) |
| Entitlement seam + one-run trial unlocks | `global.gd` — `is_unlocked()`, `grant_trial_unlock()`, `is_trial_unlock()`, `owns_publisher_deal()`, `grant_ad_bonus_tokens()` |
| Publisher Deal end-of-run bonus (+50%) | `global.gd:on_player_death()`, beside the existing fast-mode and enemy-tier bonuses |
| Entitlement + trial persistence | `global.gd` save/load blob. `reset_progress()` clears trials but deliberately **never** clears entitlements |
| Paywall entry ("＋ Tokens") and "Watch to try for one run" | `shop.gd` |
| Run-end "Watch a sponsor spot → +N ★" | `ui.gd` |
| Restore Purchases / Manage Subscription | `settings.gd` |

The game runs unchanged with no store attached: `IAP.available` is false in the
editor, on desktop and on web, and every call degrades to a no-op. In debug
builds `show_rewarded()` simulates a successful ad after 0.4s so the full
offer → reward → grant path is testable today.

### 3.5 What is NOT done

- **Plugin binaries.** `addons/godotx_revenue_cat/` and `android/revenuecat/` are not in the repo, and the 4.5 compatibility spike in §3.1 has not been run.
- **API keys.** `API_KEY_ANDROID` / `API_KEY_IOS` in `iap_manager.gd` are empty; `IAP` refuses to initialise until they are filled in.
- **Products and offering.** Nothing exists in Play Console or the RevenueCat dashboard yet.
- **Real ads.** Bigger problem than first written — see §4.1. `show_rewarded()` is the seam an ad network plugs into; release builds currently report no fill rather than granting free rewards.
- **Death-screen revive.** Deliberately skipped. `player.gd:die()` shatters the player through `TearEffect` and has already awarded tokens by the time the card appears; there is no respawn path to resume a run, and building one blind is not worth the risk. The two safe placements (shop trial, run-end double) are in. Revisit only if a revive is worth the surgery.

### 3.6 Verification order

Register → create RevenueCat project → first **test** purchase → first Store API call → first **real** purchase. These are also the five Ship Kit milestones, so hitting them in order unlocks sponsor perks along the way. Do the test purchase against a Play internal-testing track with a licensed test account before touching production.

---

## 4. Monetization design

The game's premise is that you earn tokens to buy the game's own missing features — sprites, particles, enemies, sky colour. That joke *is* the product, and **paid mechanics must not undercut it.** Anything that reads as "pay to skip the game" kills the exact thing judges would score highest.

Three streams, deliberately mixed — HAMM criteria explicitly reward "a diverse mix of revenue streams rather than relying on a single one":

### 4.1 Reality check on "RevenueCat Ads" (verified 2026-08-26)

**RevenueCat is not an ad network.** Per their own docs, ad monetization "works
alongside your existing ad implementation — you're not replacing your ad SDK or
changing how ads are served, you're just adding tracking." Ads are actually
served by AdMob, AppLovin MAX, ironSource/LevelPlay or Unity Ads; RevenueCat
reports impressions and revenue next to your subscription data.

Two consequences:

1. **Godot is not on the supported list** — the listed SDKs are
   purchases-android, purchases-ios, purchases_flutter, purchases-unity and
   react-native-purchases. But the gap is narrower than that implies. The
   binaries `godotx_revenue_cat` already ships are new enough:

   | | Plugin bundles | Rewarded-ad tracking needs |
   |---|---|---|
   | Android | purchases-android 10.14.1 | 10.12.0+ |
   | iOS | purchases-ios 5.81.1 | 5.80.3+ |

   What is missing is only the Kotlin↔GDScript binding. The plugin exposes
   `initialize` / `fetch_offerings` / `fetch_products` / `purchase` / `login` /
   `logout` / `is_subscriber` / `has_entitlement` / `present_paywall` /
   `check_entitlement` / `restore_purchases` / `show_manage_subscriptions` —
   no ad methods. Adding them means forking the plugin, writing the Kotlin
   bindings and rebuilding the `.aar` via its `make build-android`.
2. **Ad money is AdMob money.** It is paid out through the AdMob/Google
   AdSense payments profile, entirely separate from Play Console IAP earnings.
   RevenueCat never touches it.

What this means for the Catvertising target: it is harder than §2 assumed.
A plausible route, needing verification before it is committed to:

- Serve rewarded ads through a community Godot AdMob plugin (e.g.
  poing-studios/godot-admob-android). This is the part that actually shows an ad.
- Grant the reward via AdMob **server-side verification** — enable SSV on the
  rewarded ad unit and point the callback at
  `https://api.revenuecat.com/v1/incoming-webhooks/admob-ssv-rewarded`. This is
  server-to-server, so it does **not** need a RevenueCat Godot binding, which is
  why the route is plausible at all.
- Impression-level revenue tracking is the only piece needing the forked plugin
  above — and it is the piece a Catvertising judge would actually be scoring.

Steps 1 and 2 give working rewarded ads with no native rebuild. Step 3 is the
expensive one; treat it as a stretch goal to start only once the store release
is done.

**Decision needed:** if that verification does not land quickly, drop
Catvertising and put the time into Best Game + #BuildInPublic, both of which are
already reachable with the purchase integration alone. Do not let the ad work
eat the weeks that the store release needs.

### 4.2 The three streams

**A. Rewarded ads — opt-in, diegetic** *(Catvertising entry, contingent on §4.1)*

Frame ads in-fiction as sponsorship funding for the development studio. Placements:

- *Death screen:* "Take a sponsor deal to continue this run?" — one revive, once per run.
- *Shop:* "Watch a sponsor spot → unlock this feature for one run only." The player gets a free trial of, say, Particles before committing tokens. Genuinely additive, and it doubles as an upsell demo.
- *Run end:* optional 2× on `run_tokens_gained`.

Never interstitial, never forced. The pitch to judges writes itself: the game is *about* funding development, so an ad is a narrative event rather than an interruption.

Note the death-screen placement is the *run-end double*, not a revive — see §3.5.

**B. Non-consumable "Publisher Deal" — one-time, ~$4.99** *(primary revenue)*

- Permanent token multiplier, stacking with the existing `enemy_bonus` in `global.gd`'s `add_tokens()`.
- Removes the ad prompts for players who would rather pay than watch.
- Cosmetic-only exclusives: extra palettes for `palette_switcher`, an alternate player sprite.

Crucially it must **not** unlock the skill tree wholesale. Multiplier + cosmetics + ad removal is the right shape — it respects the progression that is the actual game.

**C. Consumable token packs — ~$0.99 / $2.99** *(secondary)*

Small packs only, deliberately priced so grinding stays clearly viable. These exist to catch the impulse buyer at the shop's "not enough tokens" moment, not to carry the business.

**Paywall:** use the native `present_paywall()` UI for v1. It is a day of work against a week for a custom paywall, and the design budget is better spent on the game itself. If the Design Award becomes a serious target, revisit with a custom in-engine paywall styled to match `ui_theme.gd`.

**Offering structure:** one `default` offering, three packages, one entitlement (`publisher_deal`). Keep it small — every extra product is another Play Console form.

---

## 5. Store release checklist

- Play Console: listing, content rating, data safety form, privacy policy URL. The data safety form must declare the Firestore traffic in `leaderboard_service.gd`.
- Products created in Play Console **and** mapped in RevenueCat before the first test purchase.
- Signed AAB; bump `version/code` from `1` (`export_presets.cfg:80`).
- Closed testing track → production. Start early.
- Promo codes generated for judges.
- Assets: 1024×1024 icon, at least one screenshot at exactly 1179×2556 unframed, feature graphic.

---

## 6. Five-week timeline

| Week | Work |
|---|---|
| **Aug 26 – Sep 1** | Verify Play account type; start the 14-day closed test clock if it applies. Prove the plugin runs on Godot 4.5. Create the Play listing and the RevenueCat project. Begin `#Shipaton` build-in-public posts |
| **Sep 2 – Sep 8** | `iap_manager.gd` plus the entitlement seam in `global.gd`. Products in Play Console and RevenueCat. First test purchase |
| **Sep 9 – Sep 15** | RevenueCat Ads: death-screen revive, shop trial, run-end 2×. Paywall wired into `shop.gd`. Restore and manage-subscription in `main_menu.gd` / `settings.gd` |
| **Sep 16 – Sep 22** | Ship to production. First real purchase. Balance pass on the token economy with the multiplier live. Store assets and screenshots |
| **Sep 23 – Sep 29** | Demo video. Devpost writeups, one per category — Best Game needs gameplay/art/monetization-fit prose, Catvertising needs the ad-integration argument, HAMM needs pricing plus numbers. Buffer for Play review |
| **Sep 30** | Submit. Do not plan anything else for this day |

---

## 7. Open questions

1. **Are you currently an enrolled student with an academic email?** If yes, the Next Gen Award needs no store release and no developer account, which removes the riskiest half of this plan. Answer this before starting anything.
2. Is the Play developer account personal or organization, and how old is it? Decides whether the 14-day closed test applies.
3. Has the game ever been publicly listed on Apple, Google Play, or Samsung? (Believed no — the web build does not count.)
4. iOS as well, or Android only? Android only is the right call at five weeks; iOS doubles the store work and adds a $99/yr account plus its own review queue.
