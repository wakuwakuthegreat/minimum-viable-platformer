# Launch Checklist — Google Play

Everything needed to go from this repo to a live Play Store listing. The code is
release-ready; what's left is signing and uploading the build, and filling in the Play Console.

---

## 1. Build the release

- [ ] **Bump the version** before every upload. In `export_presets.cfg` (Android):
  `version/code` must go up by 1 with each upload (1, 2, 3…); `version/name` is what players see (`1.0.0`).
- [ ] **Release keystore** set in Project → Export → Android → Keystore → Release
  (`package/signed=true` is already on). **Back up the keystore and its password somewhere safe.**
  If you use Play App Signing (the default), this is your *upload* key, and a lost one can be reset
  through Play support. Without Play App Signing, losing it means you can never update the app.
- [ ] Export with **Export With Debug unchecked**. Several things depend on this:
  - the Settings screen hides **Unlock all**, **Debug overlay** and **Use new jump**
  - the in-game store stops faking availability on PC
  - the Get Tokens button only appears when the store SDK is actually present
- [ ] Export path is `./minimum-viable-platformer-v-0-0-1.aab`. Rename it per version so old builds aren't overwritten.
- [ ] **Target API level.** Leave `gradle_build/target_sdk` empty (Godot 4.7 defaults to a current level),
  but check Play's current requirement: Play Console → Policy → App content → Target API level.
- [ ] Test the exported `.aab` on a real phone (install through an internal testing track, see §4) and check:
  - [ ] the launcher icon (round and squircle masks both look right)
  - [ ] the store opens from the home screen's bottom-left button and from the Skill Tree's "＋ Tokens"
  - [ ] real prices appear on the store's Buy buttons (they come from Play, so they only show once products exist)
  - [ ] a test purchase of each pack credits tokens; the Publisher Deal flips to "Signed ✓"
  - [ ] Restore purchases works after uninstalling and reinstalling

## 2. In-app products (Play Console → Monetize → Products)

Play only lets you create products **after** a build with billing has been uploaded to any track.
The ids must match `iap_manager.gd` exactly:

| Product id          | Type                     | Suggested price | Grants |
|---------------------|--------------------------|-----------------|--------|
| `tokens_small`      | In-app, consumable       | $0.99           | 25 ★ |
| `tokens_large`      | In-app, consumable       | $2.99           | 90 ★ |
| `developer_support` | In-app, consumable       | $0.50           | 15 ★ (the Settings button says "$0.50") |
| `publisher_deal`    | In-app, non-consumable   | $3.99           | +50% tokens every run (entitlement `publisher_deal`) |

Then in **RevenueCat**:
- [ ] Attach all four products to the app.
- [ ] Create the entitlement `publisher_deal` and attach the `publisher_deal` product to it.
- [ ] Upload the Play service-account JSON (RevenueCat → Project settings → Google Play) so receipts validate.
- [ ] Add a license tester (Play Console → Settings → License testing) so your own test purchases aren't charged.

> If `publisher_deal` is ever made a subscription instead, the Settings screen's "Manage Subscription"
> button already covers Play's requirement to link to subscription management.

## 3. Store listing assets (Play Console → Grow → Store presence → Main store listing)

| Asset | Requirement | Status |
|-------|-------------|--------|
| App icon | 512×512 PNG, 32-bit, ≤ 1 MB | ✅ `store_listing/play_icon_512.png` |
| Feature graphic | 1024×500 PNG/JPG, **required** | ❌ make one (see below) |
| Phone screenshots | **2–8 required**, 16:9 or 9:16, each side 320–3840 px | ❌ capture (see below) |
| 7" / 10" tablet screenshots | Optional, but needed to be featured on tablets | optional |
| Promo video | Optional YouTube link | optional |

**Screenshots to capture** (landscape 1920×1080 looks best). Take them on a phone, or run the PC build at
1920×1080 and press F12 / use the OS screenshot tool. Aim for this sequence; it tells the game's whole joke in 6 images:
1. **The primitive start**: grey squares, no UI, "you died." Caption: *"It starts as a rectangle."*
2. **The Skill Tree** with a few branches open. Caption: *"Buy the game back, one feature at a time."*
3. **Mid-game run** with enemies, sprites and particles. Caption: *"Enemies pay better. They also kill you."*
4. **A story cut** (narrator / purple voice on screen). Caption: *"The narrator is lying to you."*
5. **Fully polished run**: combos, parallax sky, juice. Caption: *"…until it's a real platformer."*
6. **Leaderboard or Daily Level.** Caption: *"Daily seed. Global leaderboard. No excuses."*

**Feature graphic idea:** left half a flat grey primitive rectangle-player on a grey block, right half
the fully polished sprite on a warm parallax sky, with the title across the middle in the ka1 font.
It shows "before → after" in one image.

## 4. Listing text

**App name** (≤ 30 chars)
```
Minimum Viable Platformer
```

**Short description** (≤ 80 chars)
```
The game was lost. Die, earn tokens, and buy it back one feature at a time.
```

**Full description** (≤ 4000 chars)
```
Something took the game. All of it. The menus, the music, the colours, the enemies — gone. What's left is
a grey rectangle, a floor, and a narrator who insists this is fine.

You'll have to buy it all back.

HOW IT WORKS
• Run. Jump. Die. Every death pays out tokens — the further you get, the more you earn.
• Spend tokens in a sprawling Skill Tree of nearly 70 upgrades to rebuild the game around you.
• Start with the basics: a menu, a level generator, some enemies to kill you more efficiently.
• Work up to the good stuff: sprite art, animation, squash & stretch, particles, parallax skies,
  screen shake, a combo system, double jump, wall jump, colour grading, even a CRT filter.
• Every feature you buy visibly changes the game. You're not unlocking levels — you're building the platformer.

RISK PAYS
Harder enemies raise your payout. Bats, bombs, drills and shooters make every run more dangerous
and more profitable. Can you afford not to?

A STORY THAT DOESN'T TRUST ITSELF
A dry narrator, a sponsor who shouts, a princess who is mostly decorative, and a quiet voice in the save file
that says none of this is what it seems. Die enough and you'll hear all of them.

KEEP COMING BACK
• A new Daily Level every day, the same seed for everyone
• Global leaderboards for distance, score and combo
• Save and replay your favourite generated levels
• Full stats: deaths, jumps, playtime, longest combo

FAIR MONETIZATION
Everything in the game is earned by playing. Optional token packs only make it faster, and a
one-time Publisher Deal permanently boosts every run's payout. No ads.

Minimum Viable Platformer — a game you build one feature at a time.
```

**Category:** Game → Arcade (or Action). **Tags:** platformer, roguelite, casual, arcade, offline.

## 5. App content forms (Play Console → Policy → App content)

- [x] **Privacy policy URL**: https://gunroarcannon.github.io/minimum-viable-platformer-the-game/privacy.html
  (hosted from the repo's `gh-pages` branch; to edit it, change `index.html`/`privacy.html` on that branch). It covers:
  - leaderboard: player name, anonymous player id, scores (stored in Firebase / Firestore)
  - purchases: handled by Google Play and RevenueCat (purchase history tied to the anonymous id)
  - no ads, no analytics SDKs, no location, no contacts
- [ ] **Data safety** form. Declare it to match the policy:
  - *App activity → Other user-generated content* (player name, scores): collected, shared with no one, used for app functionality.
  - *Financial info → Purchase history*: collected (RevenueCat), app functionality.
  - *Device or other IDs*: collected (anonymous player id).
  - Data is encrypted in transit: **Yes**. Users can request deletion: provide an email.
- [ ] **Ads**: *No* (AdMob is in `addons/` but isn't enabled, and `IAP.ads_enabled()` returns false).
- [ ] **Content rating** questionnaire: cartoon violence (stomping enemies, blood-splat effect). Expect **PEGI 7 / ESRB Everyone 10+**.
  The blood-trail option is worth mentioning truthfully.
- [ ] **Target audience**: 13+ is simplest. If you pick an age group under 13, the Families policy applies and needs extra review.
- [ ] **Government apps / financial features / health**: all *No*.
- [ ] **In-app purchases**: *Yes*. Play shows "Contains in-app purchases" on the listing automatically.

## 6. Testing track, then production

- [ ] **Internal testing** first: upload the `.aab`, add your own Google account, install through the opt-in link.
  This is also the upload that unlocks product creation (§2).
- This is an **organisation account**, so the "12 testers for 14 days" closed-test rule does **not** apply.
  You can go from internal testing straight to production.
- [ ] Submit the production release for review. A first app from a new account can take anywhere from hours to
  about a week, so **submit as early as possible** (see §8 for the Shipaton deadline).

## 7. Housekeeping (optional, not blocking)

- The project root contains old web-export output (`minimum-viable-platformer.*.png/.js/.html`, `a.png`) and
  three ~95 MB `.aab`s. The `.aab`s aren't packed into the game, but the stray `.png`s are imported and
  exported. Moving the web output to its own folder trims the package a little.
- `icons/icon.png` (the 2048 px, 4.9 MB source) now has a `.gdignore` so it isn't packed into the game. The
  in-game, launcher and adaptive icons are generated from it into `assets/app_icon/`. To change the icon,
  replace `icons/icon.png` and regenerate those files at the same sizes (512, 192, 432 adaptive fg/bg).
- Adaptive icon monochrome layer (`launcher_icons/adaptive_monochrome_432x432`) is empty. It's only used by
  Android 13+ "themed icons"; add one later if you like.

## 8. RevenueCat Shipaton 2026 submission (Devpost)

**Deadline: Oct 1, 2026 @ 7:45am GMT+1.** The app must be *publicly live* on Google Play by then, and its
first release must fall inside Aug 1 – Sep 30. Play review time is the biggest risk, so upload to production first
and prepare the Devpost items below while it's in review.

- [ ] **Text description.** Reuse the full description from §4, plus a paragraph on the monetization design:
  the whole game is the joke "you buy the game back", the IAP only speeds it up, and the Publisher Deal is a
  permanent payout multiplier rather than a skip.
- [ ] **Demo video ≤ 2 minutes**, on a real phone, uploaded *public* to YouTube or Vimeo. Suggested cut:
  primitive start → first death → Buy UI → Skill Tree → buying enemies/sprites → polished run → store.
  - Music: the soundtrack is CC-BY, which is allowed, but put the credits in the video description.
- [ ] **Play Store URL** of the live listing.
- [ ] **1024×1024 icon**: ✅ `store_listing/icon_1024.png`
- [ ] **Screenshot at exactly 1179 × 2556, no device frame.** That's portrait, and the game is landscape. Options:
  take a 2556×1179 landscape screenshot and rotate it 90°, or compose a portrait image (title on top,
  landscape gameplay shot in the middle, tagline below). Rotating it is fastest.
- [ ] **Promo code or free trial for judges.** Play Console → Monetize → Promo codes → create codes for
  `publisher_deal` and a token pack, and paste them into the submission. Without this, judges can't test the purchases.
