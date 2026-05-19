# Boba Drop — Design Spec

| | |
|---|---|
| **Project** | Boba Drop — 1v1 Puyo-Puyo-style falling-block duel on Roblox |
| **Owner** | Sarah Yoon |
| **Status** | Approved through Round 2 multi-role review |
| **Date** | 2026-05-18 (initial), 2026-05-19 (revised Round 1 + Round 2) |
| **Build window** | Tue 2026-05-19 → Fri 2026-05-22 |
| **Team** | Sarah + 2 Slack bots (Game Engineer, Producer) |

---

## 1. Shape

A 1v1 falling-block duel inspired by Puyo Puyo, themed as boba pearls dropping into clear cups. Pairs of colored pearls fall from above. Connect 4+ same-color pearls orthogonally to pop them. Pops cascade via gravity into chain reactions. Chains send "ice cube" garbage to the opponent's cup. First to overflow loses. Best of 3 rounds (first to 2 wins).

- **Players per match:** exactly 2
- **Round length:** ~90 seconds average
- **Match length:** ~5 minutes (best of 3)
- **Platform:** Roblox (Mac dev, ships to all Roblox clients incl. mobile)
- **Target audience:** older teen / young adult Roblox players. **Not algorithmically discoverable** (Roblox skews kid-aged); this is portfolio-first.

### Definition of "shipped" (binary, testable Sat 2026-05-23)

1. ✅ Public Roblox URL (`roblox.com/games/...`)
2. ✅ Public GitHub repo with full README (sections defined in §4 Day 4)
3. ✅ 30–60 second gameplay clip showing 4-chain pop, garbage exchange, and counter cancellation, **publicly hosted at a URL Sarah can paste into a resume** (preferred location: portfolio site embed; fallback: YouTube unlisted)
4. ✅ Premium Themes Pack Game Pass listed; Sarah completes one end-to-end test purchase

### Monetization

One Game Pass at launch: **Premium Themes Pack** — three cosmetic themes (Brown Sugar Boba, Strawberry Milk, Matcha). Players in the same match each see their own theme on their own cup. Gameplay-neutral; cosmetic only.

**Success metric:** purchase flow works end-to-end (self-purchase test). Not a revenue play.

### Stretch goal

Slack bots play the game as server-side simulated NPC opponents driven via Open Cloud MessagingService. Only if 1v1 ships clean. Designed so the NPC driver swaps the input source via `RoomManager:applyInput(playerId, input)`, not a separate loop.

---

## 2. Technical architecture

### Tools

| Tool | Purpose |
|---|---|
| Roblox Studio | Visual editor, scene assembly, playtest runtime |
| Rojo CLI + Studio plugin | Sync `.lua` files from disk into Studio |
| Lune | CLI Luau test runner (macOS, no Studio needed) |
| VSCode | Editor for Luau source |
| git + **GitHub public remote** | Source control (non-negotiable; primary portfolio artifact) |
| Game Engineer Slack bot | Gameplay logic |
| Producer Slack bot | Schedule + UI + monetization + polish |

### Project structure

```
/Users/student/Documents/boba-drop/
├── default.project.json          # Rojo config
├── lune.toml                     # Lune test config
├── README.md                     # public-facing; structured per §4 Day 4
├── .gitignore
├── docs/
│   ├── design.md                 # this file
│   └── daily-log.md
├── tests/
│   ├── MatchDetector.spec.lua
│   ├── ChainResolver.spec.lua
│   └── Scoring.spec.lua
└── src/
    ├── ServerScriptService/
    │   ├── Main.server.lua       # 🤖 Engineer — bootstrap; instantiates RoomManager
    │   ├── Networking/           # 🤖 Engineer
    │   │   ├── RoomManager.lua       # session lifecycle (join/leave/pair); consumes GameState transitions
    │   │   ├── StateSync.lua         # subscribes to GameState pub/sub; emits RemoteEvents
    │   │   └── DisconnectHandler.lua # invokes GameState:forfeitRound() (single writer)
    │   └── Monetization/         # 🤖 Producer
    │       └── GamePasses.lua
    ├── ReplicatedStorage/
    │   ├── Shared/Logic/         # 🤖 Engineer — PURE ModuleScripts, Lune-testable
    │   │   ├── Board.lua             # grid + spawn + gravity; RNG seed INJECTABLE (not math.random direct)
    │   │   ├── MatchDetector.lua     # BFS flood-fill — pure fn
    │   │   ├── ChainResolver.lua     # synchronous: returns {chainLength, totalPopped, colorsUsed}
    │   │   ├── Scoring.lua           # pure: formula(popped, chainLen, colors) → score
    │   │   ├── GameState.lua         # OWNS round/match state + scores + match-end transition; emits domain events
    │   │   └── Constants.lua         # gameplay constants
    │   ├── Shared/UI/UIConstants.lua # 🤖 Producer — colors, fonts, durations, HUD z-order stack
    │   ├── Shared/PieceTypes.lua # 🤖 Engineer
    │   ├── Shared/Events.lua     # joint — ModuleScript exporting event names + payload-shape type annotations (replaces a separate doc; breaking changes are compile-visible)
    │   └── Remotes/              # 🤖 joint — RemoteEvent Instances as .model.json
    ├── StarterPlayer/StarterPlayerScripts/  # 🤖 Engineer
    │   └── InputHandler.client.lua          # local input → RemoteEvent fire
    └── StarterGui/               # 🤖 Producer
        ├── Lobby/, GameUI/, MatchEnd/, Shop/
```

### Module ownership invariants

- **`Shared/Logic/*` must not import from `ServerScriptService/*`.** This keeps logic pure and Lune-testable. Tired-Wednesday-night enforcement: a Lune test that fails if a logic module references a server-only path.
- **`GameState` is the sole writer for round/match state.** Both gameplay and disconnect paths funnel through `GameState:forfeitRound(playerId, reason)`. `RoomManager` *reads* `GameState` and orchestrates session-level networking, but does not mutate round state.
- **`StateSync` subscribes to `GameState` events** (pub/sub, e.g., `onChainResolved`, `onRoundEnd`, `onMatchEnd`). `GameState` never imports `StateSync`. Prevents circular deps.
- **Scoring lives in `Scoring.lua`**, not inside `ChainResolver` or `GameState`. `ChainResolver` returns raw counts; `Scoring.compute()` is a pure function; `GameState` applies the result. Each is independently testable.
- **Bag RNG seed is injected** into `Board` from `GameState` via a constructor / context object. No direct `math.random()` in logic modules. This makes Lune tests reproducible and enables the Daily Challenge stretch (deterministic daily seed).
- **Deterministic same-tick resolution** is codified as a single function `GameState:resolveTick()` with the order: P1 chain → P2 chain → garbage exchange → spawn checks. Refactors can't quietly reorder it.

### Client/server authority + networking

- **Server fully authoritative.** Client `InputHandler.client.lua` sends only input events (move L/R, rotate CCW/CW, soft drop, hard drop) via RemoteEvents. **Client never computes chain length, garbage amount, or end-of-game conditions.**
- Use **`RemoteEvent` for everything** — input from client, state broadcasts from server.
- Use **`RemoteFunction` only for one-off client→server queries** (specifically `UserOwnsGamePassAsync` checks). Never call `:InvokeClient()` from server.
- **RemoteEvent Instances** authored as `.model.json` files in `ReplicatedStorage/Remotes/` (live in place file, discoverable from both sides).
- Event names + payload shapes live in `ReplicatedStorage/Shared/Events.lua` (imported by both sides; one source of truth).
- **State replication cadence:** per-event (piece-locked, chain-completed with chain length, garbage-incoming, garbage-applied, round-end, match-end). Not per-frame.
- **MarketplaceService:** `UserOwnsGamePassAsync` cached per-session on `PlayerAdded`, pcall-wrapped. `PromptGamePassPurchase` + `PromptGamePassPurchaseFinished` listener that **filters by `gamePassId`** so cached-ownership doesn't get poisoned by stale events from other Game Passes (future-proofing).

### Source control

- `git init` + push to **public GitHub remote on Mon evening** (non-negotiable).
- Commits at every milestone.

---

## 3. Game design

### Playfield

- 6 wide × 12 tall cup + 2 rows above (danger zone)
- Settling above row 12 = overflow = round loss
- **Spawn-collision loss:** if the next piece's spawn cells are occupied, the player loses the round regardless of "settled" status

### Pieces + RNG

- Pairs of boba pearls (vertical default; rotate to horizontal)
- 4 colors with shape/icon differentiation (mandatory colorblind accessibility):
  - 🟫 Brown: 1 dot · 🩷 Pink: 2 dots · 🟢 Green: 3 dots · ⚪ White: 4 dots
  - At small render sizes (mobile opponent-cup pearls below ~20px), the dot cue is replaced by a **shape outline** (square / triangle / circle / star) so the secondary cue survives scale-down
- **Spawn RNG: shuffled-bag, identical-seed-per-round.** Each player draws from their **own independently-shuffled bag** of all 16 color-pair combinations. **Same seed for both players each round**, generated server-side via `Random.new()` and passed via the `GameState` bag context. Standard Puyo/Tetris-versus convention — both players see the same piece sequence so wins/losses are skill, not draw luck.

### Controls

**Keyboard:**
| Action | Effect |
|---|---|
| ← → | Move 1 column |
| Z | Rotate CCW |
| X | Rotate CW |
| ↓ (hold) | Soft drop (8× faster) |
| Space | Hard drop (snap to bottom) |

**Touch (~60% of Roblox audience):**
- On-screen buttons in thumb-reach zones (L/R bottom-left, rotate + drop bottom-right)
- Minimum 44pt touch targets, with safe-area inset reservation (don't collide with iOS home indicator / Android gesture bar)
- Mobile layout variant: your cup dominant; opponent cup shrunk to ~30% in upper corner
- **Garbage warning row renders at min 24pt** regardless of opponent-cup scale (so warning is readable even on the shrunk opponent cup)

### Timings (in `Constants.lua`)

| Constant | Value | Purpose |
|---|---|---|
| `LOCK_DELAY` | 0.5s | Slide adjustment after touching a surface |
| `GRAVITY_BASE` | 0.8s/row | Starting drop interval |
| `GRAVITY_RAMP` | -0.05s every 30s | Floor at 0.2s/row |
| `SOFT_DROP_MULT` | 8× | While ↓ held |
| `GARBAGE_QUEUE_DELAY` | 2 piece placements | Counter window |
| `AFK_PIECE_TIMEOUT` | 15s | **Measured from piece spawn**, not last input. `LOCK_DELAY` refreshes do NOT reset this timer. Prevents grief-stalling. |

### Rotation rule

**No wallkick in v1.** Rotation into a wall/stack is rejected.

### Match rule + chains

- Piece locks → scan 4+ same-color orthogonal groups
- All matched groups pop simultaneously (250ms scale-up + flash-white tell → vanish)
- 300ms gravity settle → re-scan
- Repeat until stable; chain length counted
- `ChainResolver` runs **synchronously** on the server. Animation pacing is client-side cosmetic on top of the resolved state. Deterministic + Lune-testable.

### Scoring (computed by `Scoring.lua`, not by ChainResolver or GameState)

```
score = popped_pearls × chain_multiplier × color_bonus
chain_multiplier: 1=1, 2=3, 3=6, 4=12, 5=24, ...
color_bonus:      1-color=1, 2-color=2, 3-color=4, 4-color=8
```

### Garbage table (capped to keep duels alive)

| Chain length | Garbage sent |
|---|---|
| 1 | 0 |
| 2 | 1 |
| 3 | 3 |
| 4 | 6 |
| 5 | 12 |
| 6+ | 24 (cap) |

### Garbage semantics

- Outgoing garbage **subtracts from your incoming queue first** (counter cancellation)
- Drops at end of the **2nd** piece placement after queuing
- Cubes are unmatchable; participate in gravity; never pop; chain pops don't clear adjacent cubes
- **Drawn-round redo:** when a round ends in a draw, all queued (undelivered) garbage is **discarded** before the redo

### Round + match flow

1. Both players spawn empty, see each other's cup
2. Pieces drop simultaneously (same seed, independent bags)
3. First overflow = round loss
4. **Same-tick simultaneous overflow tiebreaker:** the player with the **lower round score at the start of this tick** loses. If still tied (same start-of-tick score), **Player 1 wins by deterministic order** (acknowledged P1-bias — fixed tiebreak is better than nondeterminism).
5. "Round X to Player Y" banner for 3s
6. Both fields clear, next round
7. Best of 3 → "Match Winner" screen → rematch / leave

### Match-end screen content

- Both players' final scores (this match)
- Each player's best chain
- "Closest round: X pearls from overflow"
- **Rematch:** both must press within 15s. Visible countdown ring. "Opponent: waiting / ready / left" status line. Leave button is disabled for the first 1s to prevent accidental taps.
- **Mid-rematch-window disconnect = treated as Leave** (no deadlock waiting for input)
- **Post-match "Try a theme?" prompt shows at most once per session**, not once per loss

### Disconnect / AFK rules

- **Mid-round disconnect:** opponent wins round after 10s grace. **No rejoin in v1.**
- **Garbage queued against a disconnected player is discarded** when grace expires. **Garbage queued *by* the disconnected player** at grace expiry is also discarded.
- **Best-of-3 disconnect after round 1:** forfeit of remaining rounds; opponent wins match.
- **AFK softlock:** per-piece 15s timeout from spawn (not from last input). Exceeding forfeits the round.

### Pre-piece preview

Show next 2 pieces in an anchored "preview cluster" frame (next-2-pieces + chain counter + score) so the mobile layout can move the whole cluster as one unit. Cluster never overlaps the shrunk opponent cup or garbage warning row.

### Lobby + queue UX

- "Play" → "Searching for opponent" with elapsed timer
- **Cancel queue** button always available
- **60s queue timeout** → fallback options: "Play vs CPU" (basic NPC opponent) or "Copy invite link" (private match URL)
- **Themes button is disabled while queue is active** — avoids the "match found mid-purchase-prompt" race
- **Tutorial card** on lobby (3 lines): "Match 4+ to pop. Chain pops send ice cubes. Don't overflow."
  - **Dismiss state persists** in player DataStore (returning players don't re-see it)
  - Explicit X button + tap-anywhere to dismiss; never blocks Play

### Visual feedback spec

- **Pop sequence:** 250ms flash-white scale-up tell → pop → 300ms gravity settle → re-scan
- **Chain counter:** "Chain x3!" appears with pop event; persists 1s after final pop
- **Garbage warning:** row of cube icons above field, pulses faster as drop approaches, red flash + screen shake at 500ms before drop
- **Counter cancellation:** cubes shatter at field boundary + "BLOCKED!" flash + audio sting
- **HUD z-order stack** (defined in `UIConstants.lua`): garbage warning > chain counter > round banner > tutorial > shop overlays. Counter-cancel "BLOCKED!" rendered in a different screen region from the chain counter to avoid overlap on simultaneous events.

### Shop / monetization UI

- Persistent "Themes" button on lobby
- Post-match "Try a theme?" overlay after a loss (max 1×/session)
- Both surface the Shop UI with Premium Themes Pack details + purchase CTA

---

## 4. Schedule

### Day 0 — Mon 2026-05-18 evening (~2h)

- Install Rojo CLI, Rojo Studio plugin, Lune CLI
- Initialize project, `git init`, **push to public GitHub remote** — save URL
- **Confirm Roblox account capability:** (a) Sarah's creator account can list Game Passes; (b) Sarah's purchaser account has Robux for self-purchase. If either is blocked → escalate per Risk #4; treat blocker as Day 0 dependency, not Day 4 surprise.
- Pre-write resume bullet drafts (Variant A: "shipped 1v1 with Game Pass"; Variant B: "shipped single-player with Game Pass"). **Variant selection deadline: Sat 2026-05-23 noon PT.**
- Spin up Producer bot, create `#boba-drop` Slack channel, allow channel for both bots
- **Validate Rojo mapping end-to-end:** trivial `Hello.lua` ModuleScript required from `Main.server.lua` prints "hello" on Play

**Exit:** Both bots respond in `#boba-drop`. Rojo round-trip works. GitHub URL saved. Account capability confirmed.

### Day 1 — Tue (~6h) — Skeleton + test harness

- **🤖 Engineer:** `Board.lua` (grid + bag RNG injection + gravity + lock delay), `InputHandler.client.lua` (keyboard + touch + safe-area), `PieceTypes.lua` (colors + dot pattern + shape-fallback), `Constants.lua`, `MatchDetector.lua` (pure fn), `tests/MatchDetector.spec.lua` (8+ scenarios)
- **🤖 Producer:** Studio scene assembly, score + chain-counter GUI scaffold, lobby tutorial card with persisted dismiss, daily-log entry
- **👤 Sarah:** Studio play-column build, playtest keyboard + touch on phone, input feel feedback

**Exit:** Drop, move, rotate, hard-drop. Mobile touch works. Lune `MatchDetector` tests passing 8+ scenarios.

### Day 2 — Wed (~7h, boss fight) ⚠️

- **🤖 Engineer:** `ChainResolver.lua` (sync loop), `Scoring.lua` (pure fn), `GameState.lua` (state + `resolveTick` + `forfeitRound` + pub/sub event interface), extend Lune tests for chain edge cases (multi-color same-step, bottom-row chain, empty-field chain, chain-during-falling)
- **🤖 Producer:** Chain counter UI + pop animations (250ms+300ms timing), sound triggers, 2h chain-stability checkpoints
- **👤 Sarah:** Run Lune tests, build chain setups in Studio, find edge cases

**Exit:** 4-blob match pops with 250ms tell, settles in 300ms, chains display "Chain x3!". Lune tests pass 15+ scenarios. Single-player loop works end-to-end.

### Day 3 — Thu (~6h) — Networking + 1v1

- **🤖 Engineer:** `Main.server.lua` (bootstrap), `Remotes/*.model.json`, `Events.lua` (event types), `RoomManager.lua` (matchmaking + session lifecycle; consumes GameState events), `StateSync.lua` (subscribes to GameState events; emits RemoteEvents per-event), garbage queue + counter, `DisconnectHandler.lua` (10s grace, AFK 15s, draw-round queue discard, mid-rematch-disconnect-as-Leave)
- **🤖 Producer:** Lobby UI (queue + 60s timeout + cancel + invite link + Themes-disabled-while-queued), garbage preview (pulse + red flash + screen shake), counter-cancel "BLOCKED!" visual, best-of-3 round flow, match-end screen (scores + best chain + closest round), rematch countdown + opponent-status line + 1s leave cooldown, preview-cluster anchored frame
- **👤 Sarah:** Test 1v1 with friend or alt account. Test disconnect mid-round. Test AFK. Test rematch. Test mid-rematch disconnect. Test queue cancel.

**Exit:** Full 1v1 end-to-end. All disconnect/AFK/draw/rematch paths verified.

### Day 4 — Fri (~5h) — Polish, monetize, publish, portfolio

- **🤖 Engineer:** Bug-bash from Thu, performance pass if needed
- **🤖 Producer:** `GamePasses.lua` (cached + pcall + filtered by gamePassId + PromptGamePassPurchaseFinished listener), Shop UI on lobby + post-match (≤1×/session), publish prep (icon, thumbnail, description, age rating)
- **👤 Sarah:**
  - Source/make icon image
  - Final playtest
  - **Record 30–60s gameplay clip** — opens on a 4-chain pop in first 5 seconds with "Chain x4!" visible, then garbage exchange, then counter cancellation. Money shot at the front because hiring managers don't watch past 5s.
  - Click File → Publish to Roblox, set Public
  - Self-purchase Game Pass to validate flow
  - **Finalize README** with these sections:
    1. **What it is** (one-paragraph elevator pitch + embedded clip)
    2. **Tech stack** (Roblox, Luau, Rojo, Lune, GitHub Actions if any)
    3. **Architecture diagram** (the module ownership tree from §2)
    4. **Notable design choices** (server-authoritative model, deterministic resolution order, bag RNG)
    5. **Known limitations** (no wallkick, no rejoin, no friend invites past Fri)
    6. **What I'd build next** (rollback netcode, more game modes, replays)
  - Embed clip in README

**Exit:** All 4 "shipped" checkboxes from §1 are green.

### Sat 2026-05-23 — Post-ship checklist (~30 min)

The build is half the artifact; distribution is the other half.

- [ ] LinkedIn post drafted + published (15-second teaser clip embedded for same-day algorithm boost)
- [ ] Repo pinned on GitHub profile
- [ ] Project added to resume PDF
- [ ] Project added to portfolio site's "Projects" list
- [ ] Resume-bullet variant chosen by Sat noon PT (Variant A or B from Day 0)

### Parallelism + Producer's daily-log cadence

Bots own non-overlapping folders → parallel work. Sarah bottleneck on decisions → ~1.5× speedup.

**Daily-log via Slack scheduled reminder.** `#boba-drop` channel reminder at 5:45pm PT each day pings `@Producer`: "Write today's daily-log.md entry from git log + the day's Slack thread." Producer commits.

---

## 5. Risks + cut plan

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| 1 | Chain-resolve edge-case bugs | High | Lune unit tests Tue+Wed. Producer 2h Wed checkpoints. Synchronous resolver = deterministic. |
| 2 | Roblox networking sync misbehaves | Moderate | Server fully authoritative. RemoteEvents everywhere; RemoteFunction only for ownership. Deterministic same-tick order in `GameState:resolveTick`. |
| 3 | Roblox/Luau learning curve | Moderate | Day 1 30 min "Roblox for Unity devs" intro from Engineer. |
| 4 | Game Pass account capability blocked | Low (caught Mon) | Day 0 verifies both creator-side listing and purchaser-side Robux. If blocked, escalate: get account verified, or ship without Game Pass and hit 3/4 of "shipped" criteria. |
| 5 | Fatigue mid-week | Low | Daily exit criteria small + demoable. |
| 6 | Mobile playtest skipped | Moderate | Touch controls Tue (not Thu). Sarah tests on phone end of every day. |
| 7 | Portfolio site embed not ready | Moderate | Fallback: YouTube unlisted URL counts for shipped-criterion #3. |

### Cut ladder

```
End of TUE behind?
  Cut: pre-piece preview, fancy piece visuals
  Keep: stacking, MatchDetector Lune tests passing

End of WED chain logic broken?
  → PIVOT to single-player Puyo (product pivot, not feature cut)
  Repurpose Thu: leaderboard + Daily Challenge (deterministic daily seed)
  Repurpose Fri: monetize + publish single-player
  Switch resume bullet to Variant B

End of THU networking broken?
  → Same pivot
  Use Fri: polish + monetize + publish

Fri MORNING scrambling?
  Cut: Game Pass — ship 3/4 of shipped-criteria

Fri AFTERNOON still broken?
  Cut: public publish → private/unlisted
  Keep: README + GitHub + clip
```

### Non-negotiable

- ✅ Chain reactions work
- ✅ Game playable start-to-finish
- ✅ Code committed AND pushed to public GitHub
- ✅ 30–60s gameplay clip exists at a publicly-accessible URL
- ✅ Resume bullet finalized by Sat noon PT

---

## 6. Stretch goals

| Stretch | Effort | Notes |
|---|---|---|
| All Clear bonus | ~1h | Skill reward |
| Daily Challenge (deterministic daily seed, leaderboard) | ~3h | Also the Wed-broken fallback target |
| AI opponent NPCs via Open Cloud | ~4h | Designed to swap input source via `RoomManager:applyInput()`; not a separate loop |
| Animated theme switching mid-play | ~1.5h | Juice |

---

## Open questions

None at design time after Round-2 review. Tuning flexes in `Constants.lua` during playtest.
