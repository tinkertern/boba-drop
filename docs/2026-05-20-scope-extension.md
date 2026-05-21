# Boba Drop — Scope Extension (v1.1 polish + screen completion)

| | |
|---|---|
| **Date** | 2026-05-20 |
| **Author** | Producer (on Sarah's request after the 2-client playtest video) |
| **Context** | Day 4 of the 4-day sprint. Core gameplay loop is server-shipped and rendering. This doc captures everything still required to make the game *feel complete* for ship day Friday 2026-05-22 and for the portfolio / Roblox public listing. |
| **Scope** | Polish punch list (11 items) + new screens (main menu, settings, how-to-play, pause/leave-confirm, loading) + per-screen design specs + ship-day sequencing. |
| **Cut ladder** | If we run out of Friday, cut in this order: pre-piece preview → leaderboard → fancy visuals → soft-drop animation. *Never cut:* chain reactions, playable loop, GitHub push, gameplay clip. |

This doc complements (does not replace) `docs/design.md` and `docs/2026-05-19-implementation-plan.md`.

---

## A. Polish punch list

Each item carries: spec, file(s), animation timing, sound spec, fallback, owner, estimate.

### A1. Next-piece preview (queue pill)

**What:** A small queue widget showing the *next 2 pairs* the player will receive. Top-right corner of the play area, vertical stack of mini cup cards.

**Why:** Puyo is unplayable without it. Players need at least one piece of lookahead to plan column placement and chain setup. Roblox top falling-block games (Tetris-likes, Match-3s) all surface this.

**Where:** New `src/StarterGui/GameUI/NextPiecePreview.client.lua`. Top-right of screen, anchored at `UDim2.new(1, -16, 0, 16)`, size `UDim2.fromOffset(64, 144)`. Inside it: vertical UIListLayout with 2 mini-pair cards.

**Mini-pair card:** 56×64px cream rounded rect with two pearls stacked (pivot below, partner above — matches the spawn orientation). Pearls at 60% scale of full board pearls. Top of stack labelled "NEXT" in tiny GothamSSm/Bold 10px.

**Animation:**
- Match start: slide in from off-screen-right `(1, 16, 0, 16)` → `(1, -16, 0, 16)`, 0.3s Back/Out.
- On piece spawn: top card slides down, bottom card moves up, new pair fades in at bottom over 200ms (Quad/Out).

**Sound:** None on the preview itself. Sound is on lock (see A3).

**Server contract:**
- Server already has a piece queue in `Board:advance(n)`. We need the next 2 pieces *without consuming them*. Engineer needs to add a small RemoteEvent `NextPieceQueueUpdate { playerId, isLocal, queue = [{a, b}, {a, b}] }` fired on every spawn + initial round start. **Engineer dependency, ~15min.**
- Fallback if Engineer can't ship: render placeholder "NEXT" header with no pearls. The card still anchors the corner; we're not in a worse state than today.

**Owner:** Producer (client), Engineer (server contract).
**Estimate:** 90min including Engineer's piece.

---

### A2. Chain pop animation + sound

**What:** When a chain step pops, the popped pearls should scale-punch (1.0 → 1.4 → 0), fade to white, emit a soft "pop" sound, and (optional) a few small white particles. Multi-step chains stagger: step 1 pops, beat, step 2 pops, beat, step 3 pops.

**Why:** This is the *core feedback moment* of the entire game. Without it, pops are silent, invisible, and a 4-chain feels identical to a 2-chain.

**Where:** Modify `src/StarterGui/GameUI/BoardPlaceholder.client.lua` ChainCompleted handler. Engineer has shipped `event.steps[i].cellsPopped = [{row, col, color}, ...]` (commit `44e7003`) so we have per-step coordinates.

**Animation per popped pearl:**
1. T+0ms: scale from 1.0 → 1.4 over 80ms (Quad/Out). Background color tween → `PearlHighlight` (#FFFFFF).
2. T+80ms: scale 1.4 → 0 over 140ms (Quad/In), transparency 0 → 1.
3. T+220ms: destroy pearl, clear from `pearlByPos`.

**Per-step stagger:** Step `i` begins at `(i - 1) * 180ms`. So a 4-chain takes 4 × 180 = 720ms + 220ms tail = ~940ms total. After all steps complete, call `paintFromSnapshot(event.cells)` to settle gravity'd survivors.

**Sound:** `rbxassetid://6732690176` (Roblox library "Pop_Cute_01" placeholder; Sarah to swap for licensed asset later). One play per step, pitch-shifted up by `1.0 + (i - 1) * 0.1` so chain 2 is slightly higher than chain 1 — the classic Puyo escalation.

**Particles (optional, time-permitting):** 3 small white 8×8 Frames per popped pearl, ejected radially at 100px/200ms with `Linear/Out` easing, fading out. Skip if it's >30min to implement.

**Owner:** Producer.
**Estimate:** 2hr (1.5hr animation + 30min sound wiring).
**Dependency:** Engineer's `cellsPopped` ✅ shipped (`44e7003`).

---

### A3. Pearl-land impact (lock feedback)

**What:** When a piece locks, the two newly-locked pearls should briefly squish vertically (scale Y 1.0 → 1.15 → 1.0 → 0.9 → 1.0 over 180ms total, "bounce" feel). Plus a soft "tick" sound.

**Why:** Currently pieces just appear in their final position with zero impact feedback. Even cozy puzzles like Two Dots have a tactile "thunk" on placement.

**Where:** `src/StarterGui/GameUI/BoardPlaceholder.client.lua`, PieceLocked handler. After `paintFromSnapshot`, for each of `event.aRow/aCol` and `event.bRow/bCol`, find the just-painted pearl and run the bounce tween.

**Animation:**
- T+0ms: Y-scale 1.0 → 1.15, X-scale 1.0 → 0.92 (squash) over 60ms (Quad/Out).
- T+60ms: Y-scale 1.15 → 0.95, X-scale 0.92 → 1.05 over 60ms (Quad/In).
- T+120ms: settle to 1.0/1.0 over 60ms (Quad/Out).

**Sound:** Soft tick at low pitch (~0.7). Roblox library asset `rbxassetid://6732690176` lower-pitched. Same asset as pop, just pitched.

**Owner:** Producer.
**Estimate:** 45min.

---

### A4. Smooth falling animation (gravity tween)

**What:** Currently pieces teleport one cell per 0.8s gravity tick (`Constants.GRAVITY_BASE`). Tween the active pearls between cells so they visibly *fall* instead of jumping.

**Why:** A falling game should look like things are falling. The teleport-every-800ms cadence makes it feel like a turn-based puzzle, not real-time.

**Where:** `src/StarterGui/GameUI/BoardPlaceholder.client.lua` ActivePieceUpdate handler.

**Implementation:**
- Track the previous active piece position per pearl.
- On ActivePieceUpdate: instead of destroy + rebuild at new cell, *re-parent* the existing pearl Frames to the new cells AND tween their `Position` from the previous cell to the new cell over 120ms (Quad/Out). For input-driven moves (left/right/rotate), use 60ms to feel responsive.
- For hard-drop, skip the tween — the slam should feel instant.

**Edge case:** On rotation, the partner pearl jumps to a new column. Tween that too over 80ms.

**Fallback / risk:** Tweening across cells requires the pearl to *leave* its parent cell during the tween (or use AbsolutePosition + a floating overlay Frame). Simpler approach: paint pearls at the *correct cell* immediately, but visually offset their `Position` (UDim2) backward by one cell's worth, then tween Position to (0.5, 0, 0.5, 0). This keeps the cell-grid layout intact.

**Owner:** Producer.
**Estimate:** 2hr. Tricky — leave for Thursday morning.

---

### A5. Drop ghost

**What:** A faded outline of where the active piece will land if hard-dropped, painted in the destination cells.

**Why:** Aiming is hard in a 2D top-down grid. Tetris has it, modern Puyo has it. Reduces "I meant to put it in column 3" frustration.

**Where:** `src/StarterGui/GameUI/BoardPlaceholder.client.lua` ActivePieceUpdate handler. Compute the landing position client-side by ray-tracing down from the active piece until it hits the floor or another pearl.

**But:** Client doesn't have authoritative board state. We *could* derive it from the snapshot cached from the last PieceLocked/ChainCompleted event. That snapshot tells us which cells are occupied. We project the active piece downward through that snapshot.

**Visual:** Two pearl-outline Frames (transparent fill, `StrokeWarm` 2px stroke, no highlight). Same color as the active pearls but at `BackgroundTransparency = 0.7`. No corner radius difference.

**Update cadence:** Recompute on every ActivePieceUpdate.

**Owner:** Producer.
**Estimate:** 90min.

---

### A6. Match-end panel surfacing (verify + polish)

**What:** Confirm `MatchEnd.client.lua` fires on `onMatchEnd` and renders a panel showing winner, score, best chain, and Rematch / Leave buttons. Right now we have the scaffold but the gameplay video shows nothing after round end.

**Where:** `src/StarterGui/MatchEnd/MatchEnd.client.lua`. Audit + fix.

**Required panel content:**
- Result header: "*YOU WIN!*" / "*YOU LOSE*" / "*DRAW*" — Display font 64px, color CoralGradient on win, WarmCancel on loss, TextSoft on draw.
- Stat row 1: Final score (yours vs opponent's), count-up tween from 0 over 800ms.
- Stat row 2: Best chain (yours vs opponent's), e.g. "BEST CHAIN: 4x" with chain-gradient color.
- Buttons (bottom row, full-width pills): "REMATCH" (Mint, fires `RematchRequest`) and "LEAVE" (WarmCancel, fires `LeaveMatch`).
- Auto-leave countdown: "rematch window closes in 15s" subtitle with a thin progress bar tweening to zero.

**Animation:** Panel slides up from bottom over 400ms (Back/Out), stats count up sequentially with a soft "tick" sound per increment.

**Owner:** Producer.
**Estimate:** 90min audit + polish. Possibly less if MatchEnd scaffold is mostly there.

---

### A7. Opponent board side-by-side mini-view

**What:** Render a 60%-scale mirror of the opponent's board to the right of yours. Read-only, shows their pieces falling and stacking in real-time. No active-piece overlay (just locked state), no chain animations (just stat shifts on chain).

**Why:** Sarah explicitly called this out. Currently each client sees only its own cup, so it doesn't *feel* like a duel.

**Where:** New `src/StarterGui/GameUI/OpponentBoard.client.lua`. Anchored right of main board: main board re-anchored to `(0.35, 0, 0.5, 0)` size `(0.32, 0, 0.85, 0)`, opponent at `(0.7, 0, 0.5, 0)` size `(0.2, 0, 0.55, 0)`.

**Subscribes to:**
- PieceLocked where `isLocal == false` → paintFromSnapshot opponent's cells.
- ChainCompleted where `isLocal == false` → paintFromSnapshot opponent's cells (post-chain).
- GarbageIncoming where it's *outbound* from you → small "→ →" arrows arc from your board to theirs.

**Owner:** Producer.
**Estimate:** 2hr. Reuses ~70% of BoardPlaceholder logic. Could extract `BoardRenderer.lua` module if there's time; if not, copy-paste with the opponent-specific filtering.

---

### A8. Danger row pulse

**What:** The pink danger row (row 12) is currently always pink. It should be subtle by default (`Transparency = 0.85`, almost invisible) and pulse to bright pink + add a screen-edge red vignette as pearls approach.

**Why:** The danger zone has no *signal*. It looks like a decorative band, not a warning. Lose conditions need visible escalation.

**Where:** `src/StarterGui/GameUI/BoardPlaceholder.client.lua` PieceLocked + ChainCompleted handlers, after `paintFromSnapshot`. Compute the highest occupied row from the snapshot.

**Behavior:**
- Row ≤ 9: danger row transparency 0.85 (basically invisible).
- Row 10: transparency 0.65, gentle pulse Sine 2s loop.
- Row 11: transparency 0.4, faster pulse 1.2s loop.
- Row 12 (overlap): transparency 0.15, fast pulse 0.6s loop, screen-edge red vignette appears.

**Owner:** Producer.
**Estimate:** 45min.

---

### A9. Background ambient sound

**What:** Loop a soft lo-fi / boba-shop ambience under the game audio.

**Where:** New `src/StarterGui/Audio/AmbientLoop.client.lua` parented to ScreenGui. Use a single `Sound` instance, `Looped = true`, `Volume = 0.15`, start on PlayerAdded, never stop.

**Asset:** Roblox library lo-fi loop (Sarah to pick; I'll seed with a placeholder ID).

**Owner:** Producer.
**Estimate:** 30min including asset selection.

---

### A10. Score count-up tween

**What:** When score changes (chain resolves), tween the number from old value to new value over 600ms (Quad/Out) instead of snapping.

**Where:** `src/StarterGui/GameUI/ScoreDisplay.client.lua`. Listen for the existing ChainCompleted event's `scoreAdded`; tween TextLabel.Text via a value-driven RenderStepped or a NumberValue + GetPropertyChangedSignal.

**Owner:** Producer.
**Estimate:** 30min.

---

### A11. Floating "Nx CHAIN!" text on resolve

**What:** When a chain resolves (any chain ≥ 2), spawn a floating text label above the chain's center-of-mass that reads "*2x CHAIN!*" / "*3x CHAIN!*" / "*4x CHAIN!*" etc. with chain-gradient color, rises 40px upward over 800ms, fades out.

**Where:** Existing `src/StarterGui/GameUI/ChainCounter.client.lua` probably handles this already at a top-corner pill level. We need the *floating-above-board* variant. Either extend ChainCounter or add a new tiny script.

**Owner:** Producer.
**Estimate:** 45min.

---

## B. Screen inventory

### B.1 — Already in the build

| Screen | File | Status |
|---|---|---|
| Lobby (entry + tutorial card + queue pill + Themes button) | `src/StarterGui/Lobby/Lobby.client.lua` | Shipped |
| BoardPlaceholder (in-game board renderer) | `src/StarterGui/GameUI/BoardPlaceholder.client.lua` | Shipped, polish pending |
| ScoreDisplay (top-left pill) | `src/StarterGui/GameUI/ScoreDisplay.client.lua` | Shipped, count-up pending (A10) |
| ChainCounter (chain display pill) | `src/StarterGui/GameUI/ChainCounter.client.lua` | Shipped, floating variant pending (A11) |
| GarbagePreview (ice cubes incoming) | `src/StarterGui/GameUI/GarbagePreview.client.lua` | Shipped |
| CounterCancel (BLOCKED! pill) | `src/StarterGui/GameUI/CounterCancel.client.lua` | Shipped |
| MatchEnd (results panel) | `src/StarterGui/MatchEnd/MatchEnd.client.lua` | Scaffold, needs audit (A6) |
| Shop (Themes Game Pass modal) | `src/StarterGui/Shop/Shop.client.lua` | Shipped |
| Backdrop (cream full-screen) | `src/StarterGui/Backdrop/Backdrop.client.lua` | Shipped |
| UIStateController (screen routing) | `src/StarterGui/UIStateController.client.lua` | Shipped |

### B.2 — Missing screens / overlays

| Screen | Priority | Estimate | Why we need it |
|---|---|---|---|
| Main menu | LOW | 0 (skip) | Roblox auto-drops players into the experience, which is our "main menu." The lobby already plays this role with the Play / Themes / Tutorial card. Adding a separate splash screen is friction. **Decision: do not build.** |
| Settings panel | MEDIUM | 90min | Volume slider, music on/off, accessibility (high-contrast pearls toggle), credits link |
| How-to-play / controls overlay | HIGH | 60min | Tutorial card teaches the *concept*. Players also need an always-available "?" anywhere showing keyboard + touch controls. Especially since mobile uses tap-to-move. |
| Pause / leave-match confirm | HIGH | 45min | Player can currently quit mid-match by closing Roblox; we need an explicit "Leave match" with a confirm. Otherwise pressing back accidentally forfeits. |
| Loading screen | LOW | 0 (skip) | Roblox's default load screen is fine; ours would be cosmetic. Skip for ship. |
| Round-start countdown ("3-2-1") | MEDIUM | 60min | Currently match transitions from queue → playing with no buffer. A 3-2-1 GO! countdown lets players orient. |

---

## C. New screen design specs

### C.1 — Settings panel

**Trigger:** Gear icon top-right of Lobby (next to Themes button). NOT accessible mid-match.

**Layout:** Modal panel, 480×420 centered. Same scrim treatment as Shop (WarmDark @ 0.55).

**Components:**
- Title: "*SETTINGS*" Display 32px TextDark, top-center.
- Volume section: "MUSIC VOLUME" label + horizontal slider (0–100), default 50. Pill at thumb shows current %.
- Sound effects section: "SOUND FX" label + same slider. Default 70.
- Music toggle: "PLAY MUSIC" label + small toggle switch (mint when on, soft gray when off).
- Accessibility section: "HIGH CONTRAST PEARLS" toggle — replaces pearl pastels with saturated primaries for colorblind / low-vision players.
- Credits link: small text "*made by Sarah Yoon — 4-day Roblox sprint, 2026-05-19 → 22*" at bottom.
- Close (X) top-right.

**Sound persistence:** Use `player:SetAttribute("BobaDropMusicVolume", n)` etc., read by `AmbientLoop.client.lua` and pop-sound players. No DataStore (per-session is fine for v1).

### C.2 — How-to-play overlay

**Trigger:** "?" icon top-right of in-game HUD (replaces the debug "?" we already have). Pause-style: opens during play but doesn't pause the round (no pausing in 1v1 multiplayer).

**Layout:** Modal panel, 520×640. Scrolling content if needed.

**Sections (top to bottom):**
1. *Controls.* Two columns: left = keyboard (← →, Z/X rotate, ↓ soft drop, Space hard drop), right = touch (drag, tap to rotate, swipe down to drop).
2. *Goal.* "Match *4+ pearls* of the same color to *pop* them. Pop *chains* to send *ice cubes* to your opponent. First cup to *overflow* loses."
3. *Tips.* Three bullet tips: "*Chain reactions* score more than single pops." "*Counter incoming garbage* by chaining before it lands." "*Color rarities* are equal — don't hoard one color."
4. Close button.

### C.3 — Pause / leave-match confirm

**Trigger:** Same "?" or a small "leave" icon on the in-game HUD. Shows a small confirm modal.

**Layout:** Centered modal, 360×200.

**Content:**
- Title: "*LEAVE MATCH?*" 24px Display TextDark.
- Body: "Your opponent will win by forfeit." Body 14px TextSoft.
- Two buttons full-width row: "STAY" (Mint, cancel) and "LEAVE" (WarmCancel, fires `LeaveMatch` remote).

### C.4 — Round-start countdown

**Trigger:** Fired when `GameState` attribute transitions to `in_match` AND first PieceSpawned has not yet been received.

**Layout:** Full-screen overlay, centered.

**Behavior:**
1. T+0: "*3*" appears at scale 1.5, tweens to scale 1.0 over 200ms (Back/Out). Subtle pop sound.
2. T+1000: "*3*" fades out, "*2*" appears (same animation).
3. T+2000: "*1*" appears.
4. T+3000: "*GO!*" appears in chain-gradient, scale 1.8 → 1.0, louder pop, fades over 500ms.
5. Overlay self-destructs.

**Implementation note:** Server should NOT spawn the first piece for 3 seconds after the round starts so the countdown isn't racing the gameplay. **Engineer dependency**, but tiny (one `task.wait(3)` in `_startRoom` or `startRound`). Producer can build the countdown client-side independently and have it eat the first 3s of player input.

---

## D. Priority and sequencing

### D.1 Ship-day must-haves (CRITICAL — Wednesday EOD / Thursday AM)

These items, if missing, make the game feel broken or unplayable for the portfolio clip.

| # | Item | Owner | Estimate | Status |
|---|---|---|---|---|
| A6 | Match-end panel surfacing | Producer | 90min | Pending audit |
| A1 | Next-piece preview | Producer + Engineer (queue contract) | 90min | Engineer dep |
| A2 | Chain pop animation + sound | Producer | 2hr | Engineer's `cellsPopped` shipped ✅ |
| A3 | Pearl-land impact (lock feedback) | Producer | 45min | — |
| A11 | Floating Nx CHAIN! text | Producer | 45min | — |
| C.3 | Pause / leave-match confirm | Producer | 45min | — |

**Sub-total:** ~6.5hr of Producer time. Tight but doable Wed evening + Thursday morning.

### D.2 Strong-feel polish (HIGH — Thursday)

| # | Item | Owner | Estimate |
|---|---|---|---|
| A4 | Smooth falling animation | Producer | 2hr |
| A5 | Drop ghost | Producer | 90min |
| A7 | Opponent board side-by-side | Producer | 2hr |
| C.4 | Round-start countdown | Producer + Engineer (3s wait) | 90min |
| C.2 | How-to-play overlay | Producer | 60min |
| A8 | Danger row pulse | Producer | 45min |

**Sub-total:** ~8.5hr of Producer time. This is Thursday's slate.

### D.3 Cozy stretch (LOW — Friday morning, only if D.1 + D.2 clean)

| # | Item | Owner | Estimate |
|---|---|---|---|
| A9 | Background ambient sound | Producer | 30min |
| A10 | Score count-up tween | Producer | 30min |
| C.1 | Settings panel | Producer | 90min |

**Sub-total:** ~2.5hr.

### D.4 Cut-line items (will NOT build for v1.0)

- Separate "main menu" splash screen (lobby is the main menu — Roblox convention)
- Custom loading screen (Roblox default is fine)
- Leaderboard / persistent stats (out of cut ladder)
- Soft-drop visual animation (in cut ladder, deferred)
- Pre-piece preview *beyond next 2* (in cut ladder, defer to v1.1 if needed)
- Theme variety within active gameplay (Brown Sugar/Strawberry Milk/Matcha visual differences in-board — Game Pass cosmetic only, already surfaced in Shop)

### D.5 Cross-cutting risks

- **Engineer dependencies:** A1 needs the `NextPieceQueueUpdate` contract (~15min). C.4 needs server to delay first spawn by 3s. Both small, both should land tonight if Engineer has bandwidth.
- **Sound assets:** A2/A3/A9 use Roblox library placeholders. Sarah may want to swap for licensed audio. Doesn't block ship — placeholder sounds are good enough for the gameplay clip.
- **Mobile testing:** Producer has been testing at 1920×1080. Will validate every new screen at 414×896 (iPhone 14 portrait) before declaring done.

---

## E. What "shipped" means after this scope extension

Re-stating the §1 criteria from `design.md` with this doc's adds factored in:

1. ✅ Public Roblox URL — unchanged
2. ✅ Public GitHub repo with full README — unchanged
3. ✅ 30–60 second gameplay clip showing: piece dropping (smooth fall A4), chain pop (A2 animation visible), garbage cube (existing), counter cancel (existing), match-end panel (A6).
4. ✅ Premium Themes Pack Game Pass — unchanged

Plus, the game *visibly* contains:
- Next-piece preview surfacing (so the clip reads as "real game")
- Pop feedback (so chains feel like the core mechanic)
- An opponent's board (so it reads as 1v1, not single-player)
- A real match-end (so the clip has a clean ending)

---

## F. Open questions for Sarah

1. *Sound asset library:* OK to use Roblox library audio with placeholder IDs for v1, swap later? Or do you want me to surface specific Roblox toolbox sounds for your approval first?
2. *Opponent-board placement:* I'm proposing right-of-main. Some Puyo games put opponent's smaller and centered above. Preference?
3. *Round-start countdown:* 3-2-1-GO felt right or do you want a different cadence (e.g. just "GO!" no count)?
4. *Settings panel:* OK to skip for ship and add post-launch? It's the only D.3 item that adds a whole screen, not just a tween.
