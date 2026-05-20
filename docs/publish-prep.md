# Boba Drop — Publish Prep

Source of truth for Roblox creator dashboard fields and visual asset specs. Use this when filling out the experience listing before Friday's publish.

---

## 1. Game listing copy

### Title (max 50 chars)
**Boba Drop**

### Subtitle / tagline (50 chars)
Cozy 1v1 boba puzzle. Pop pearls. Send ice. Don't overflow.

### Short description (one-liner, used in feed cards)
A cozy 1v1 boba pearl puzzle duel. Match four, chain, and send garbage to your opponent's cup.

### Long description (Roblox cap: ~1000 chars, aim ~600)

> Two cups. Two players. One winner.
>
> Pairs of colored boba pearls drop into your cup. Line up four or more of the same color to pop them, then watch the gravity cascade trigger chain reactions that flood your opponent's cup with ice cubes. Counter their pressure by chaining back. First cup to overflow loses.
>
> Best of three rounds, about five minutes a match. Built for phones and desktop. Cute, fast, and just mean enough to be fun.
>
> *Features*
> • Real-time 1v1 matchmaking
> • Chain reactions and counter-cancel garbage
> • Cozy pastel art with bubbly motion
> • Free to play, optional Premium Themes Pack (Brown Sugar, Strawberry Milk, Matcha)

### Tags / genre
- Primary genre: **Puzzle**
- Sub-genre: **Casual**
- Search tags: `boba`, `puzzle`, `1v1`, `puyo`, `matching`, `cozy`, `cute`, `multiplayer`, `mobile`, `chain`

---

## 2. Experience Guidelines (Roblox age rating)

Recommended rating: **Minimal (All Ages)**

Justification for each content descriptor:
- *Violence*: None. The garbage system is "ice cubes" stacking up. No combat visuals, no characters harmed.
- *Crude humor*: None.
- *Blood and gore*: None.
- *Romance*: None.
- *Profanity*: None. No in-game chat in v1.
- *Alcohol, drugs, gambling*: None. The Game Pass is fixed-price cosmetics, not loot boxes.
- *Free-form user creation*: None.
- *Realistic interactive depictions*: None.

Set the **Suitable for All Ages** checkbox. Decline all content descriptors.

---

## 3. Visual assets

### Game icon — required
- **Size:** 512×512 px minimum, **1024×1024 recommended** (Roblox upscales)
- **Format:** PNG, no transparency (Roblox flattens)
- **Subject:** a single clear cup overflowing with boba pearls. Brown, pink, and green pearls visible. Cup sits on the Boba Drop cream backdrop (`#FAE2C0`).
- **Style:** rounded, flat-shaded, bubbly stroke outlines, no realistic gradients.
- **Readability check:** must be recognizable as "cup with pearls" at 64×64 thumbnail size.
- **Producer commit `a88d503`** already shipped a programmatically generated Game Pass icon; reuse the same visual vocabulary but with a wider zoom (cup, not just pearls).

### Thumbnails — up to 10, first 3 carry the most weight
Aim for **3 polished thumbnails**, 1920×1080:

1. *Hero shot.* Two cups side by side, mid-chain. One cup has a 3+ chain popping with motion lines. Score counter visible. Caption overlay: *"Chain. Send. Win."*
2. *Cozy vibe shot.* Single cup, fully stacked with a rainbow of pearls, framed by the cream backdrop. No UI chrome. Caption: *"Cozy puzzle duel."*
3. *Theme variety shot.* Three cups in a row, each in a different theme color palette (Brown Sugar / Strawberry Milk / Matcha) to advertise the Premium Themes Pack. Caption: *"Three themes. One Game Pass."*

### Screenshot list — optional, supports the listing
Capture these from Studio with the new UIStateController in `lobby` and `in_match` states:

1. Lobby with tutorial card visible (`?` button toggled on)
2. Queue pill mid-search ("4s")
3. In-match early game (cups partially filled)
4. Mid-chain (highlight one cup with the chain counter popping)
5. Match-end results screen
6. Shop modal showing the three themes

---

## 4. Gameplay clip (criterion #3 of "shipped")

- **Length:** 30–60 seconds
- **Required beats** (per `design.md` §1):
  1. A 4-chain pop on one side
  2. Garbage exchange (ice cubes traveling from popper to opponent)
  3. Counter cancellation (opponent chains back, blocking incoming garbage)
- **Hosting:** portfolio site embed preferred; YouTube unlisted as fallback
- **Aspect:** 16:9 desktop capture or 9:16 mobile capture (decide Friday based on which reads better)

### Capture process (Friday)
1. Studio → Play → record with QuickTime (`Cmd + Shift + 5`) at 60fps
2. Edit in iMovie or QuickTime trim — title card 2s, gameplay ~40s, end card 5s
3. Export 1080p H.264 mp4
4. Upload to chosen host, paste URL into README + portfolio

---

## 5. Open Cloud / Creator Dashboard checklist

Before pressing publish:
- [ ] Experience is set to **Public** (not Private)
- [ ] **Suitable for All Ages** ✅
- [ ] Experience name: **Boba Drop**
- [ ] Description pasted from §1
- [ ] Tags entered from §1
- [ ] Icon uploaded (1024×1024)
- [ ] At least 1 thumbnail uploaded (target 3)
- [ ] Premium Themes Pack Game Pass visible on the experience page (already live, ID `1846258540`)
- [ ] Robux pricing on Game Pass: **99 R$** (already set)
- [ ] One end-to-end test purchase completed by Sarah on her secondary account (criterion #4 of "shipped")

---

## 6. README portfolio polish (sibling task)

Track here so it doesn't get lost. README needs (per `design.md` §4 Day 4):
- [ ] Hero gif or video embed at the top
- [ ] One-paragraph intro that names the genre, the gimmick, and the tech
- [ ] Architecture section linking `design.md`
- [ ] Daily log link
- [ ] Game Pass screenshot
- [ ] Public Roblox URL once live
- [ ] Tech badges (Roblox, Luau, Rojo, Lune, GitHub Actions if applicable)

---

## 7. Risks / blockers

- *Icon and thumbnails are visual deliverables.* I can write specs and draft programmatic icon variants, but final art is Sarah's call. If she wants to draw them by hand, that takes Friday morning time. If she's okay with programmatic generation, I can spin a Lune script that renders all three thumbnails from `UIConstants` palette values.
- *ID verification on Roblox account.* Per `Risk #4` in the plan, account must be ID-verified to list paid Game Passes. The Game Pass is already live (`1846258540`), so this gate has cleared.
- *Gameplay clip depends on real gameplay being playable.* Engineer's Day 4 gameplay tick loop must land before Friday afternoon for the clip to be capturable.
