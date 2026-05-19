# Boba Drop — Design Spec

| | |
|---|---|
| **Project** | Boba Drop — 1v1 Puyo-Puyo-style falling-block duel on Roblox |
| **Owner** | Sarah Yoon |
| **Status** | Approved, ready for implementation plan |
| **Date** | 2026-05-18 (initial), 2026-05-19 (revised after multi-role review) |
| **Build window** | Tue 2026-05-19 → Fri 2026-05-22 |
| **Team** | Sarah + 2 Slack bots (Game Engineer, Producer) |

---

## 1. Shape

A 1v1 falling-block duel inspired by Puyo Puyo, themed as boba pearls dropping into clear cups. Pairs of colored pearls fall from above. Connect 4+ same-color pearls orthogonally to pop them. Pops cascade via gravity into chain reactions. Chains send "ice cube" garbage to the opponent's cup. First to overflow loses. Best of 3 rounds wins the match (first to 2 round wins).

- **Players per match:** exactly 2
- **Round length:** ~90 seconds average
- **Match length:** ~5 minutes (best of 3)
- **Platform:** Roblox (Mac dev, ships to all Roblox clients including mobile)
- **Target audience:** older teen / young adult Roblox players who enjoy puzzle and competitive games. **Not** algorithmically discoverable on Roblox (kid-skewing platform); this is portfolio-first, not a growth play.

### Definition of "shipped" (binary, testable on Sat 2026-05-23)

1. ✅ Public Roblox URL (`roblox.com/games/...`)
2. ✅ Public GitHub repo with README, gameplay GIF/clip embedded
3. ✅ 30–60 second gameplay clip with chain reaction + 1v1 garbage exchange, embedded in Sarah's portfolio site
4. ✅ Premium Themes Pack Game Pass listed; Sarah completes one end-to-end test purchase

### Monetization

One Game Pass at launch: **Premium Themes Pack** — three cosmetic themes (Brown Sugar Boba, Strawberry Milk, Matcha). Players in the same match each see their own theme on their own cup. Gameplay-neutral; cosmetic only.

**Success metric:** Game Pass purchase flow works end-to-end (Sarah self-purchases as a test). This is a proof-of-skill for monetization plumbing, not a revenue play. Realistic cosmetic-Game-Pass conversion on an unknown indie Roblox game is <1% of players, and Roblox takes 30%; revenue is not the goal here.

### Stretch goal (only if Fri opens up)

The Slack bots (Game Engineer and Producer) play the Roblox game as server-side simulated NPC opponents driven by their Slack-side logic via Roblox Open Cloud MessagingService. "My AI dev partners can also play the game they built." Portfolio-grade flex. (Not real Roblox accounts joining — simulated NPCs.)

---

## 2. Technical architecture

### Tools

| Tool | Purpose |
|---|---|
| Roblox Studio | Visual editor, scene assembly, playtest runtime |
| Rojo CLI + Studio plugin | Sync `.lua` files from disk into Studio in real time |
| Lune | CLI Luau test runner (runs MatchDetector unit tests on macOS without Studio) |
| VSCode | Editor for Luau source |
| git + GitHub remote | Source control. **GitHub remote is non-negotiable** (the portfolio artifact a hiring manager will click before anything else) |
| Game Engineer Slack bot (existing) | Gameplay logic in Luau |
| Producer Slack bot (new, set up Mon evening) | Schedule + UI + monetization + polish |

### Project structure

```
/Users/student/Documents/boba-drop/
├── default.project.json          # Rojo config — maps folders to Roblox instance tree
├── lune.toml                     # Lune test config
├── README.md                     # public-facing; embeds gameplay clip
├── .gitignore                    # ignores .rbxlx, build artifacts
├── docs/
│   ├── design.md                 # this file
│   ├── event-contract.md         # joint-owned: RemoteEvent names + payload shapes
│   └── daily-log.md              # daily progress notes
├── tests/
│   └── MatchDetector.spec.lua    # Lune-runnable unit tests
└── src/
    ├── ServerScriptService/
    │   ├── Main.server.lua       # 🤖 Engineer — bootstrap: creates RemoteEvents, starts RoomManager
    │   ├── Networking/           # 🤖 Engineer
    │   │   ├── RoomManager.lua       # 2-player matchmaking + match-level state machine
    │   │   ├── StateSync.lua         # board state replication (per-event, not per-frame)
    │   │   └── DisconnectHandler.lua # disconnect/reconnect/AFK rules
    │   └── Monetization/         # 🤖 Producer
    │       └── GamePasses.lua        # Premium Themes Pack: UserOwnsGamePassAsync, PromptGamePassPurchase
    ├── ReplicatedStorage/
    │   ├── Shared/Logic/         # 🤖 Engineer — pure ModuleScripts, testable from Lune
    │   │   ├── Board.lua             # grid state, piece spawn, bag-based RNG
    │   │   ├── MatchDetector.lua     # BFS flood-fill for 4+ same-color groups (PURE function)
    │   │   ├── ChainResolver.lua     # gravity → match → pop loop (synchronous, returns chain length)
    │   │   ├── GameState.lua         # round/match state machine; OWNS player scores
    │   │   └── Constants.lua         # 🤖 Engineer — gameplay constants (board dims, garbage table, timings)
    │   ├── Shared/UI/
    │   │   └── UIConstants.lua       # 🤖 Producer — UI-only constants (colors, fonts, animation durations)
    │   ├── Shared/PieceTypes.lua # 🤖 Engineer — color enum + visual icon mapping
    │   └── Remotes/              # joint — RemoteEvent Instances authored as .model.json
    │       └── *.model.json
    ├── StarterPlayer/StarterPlayerScripts/  # 🤖 Engineer
    │   └── InputHandler.client.lua          # local input → fires RemoteEvents
    └── StarterGui/               # 🤖 Producer
        ├── Lobby/                    # tutorial card, queue timer, cancel, Game Pass entry
        ├── GameUI/                   # score, chain counter, garbage preview, next-piece queue
        ├── MatchEnd/                 # winner screen with score recap + best chain
        └── Shop/                     # Game Pass detail/purchase UI
```

### Client/server authority + networking

- **Server is fully authoritative.** Client `InputHandler.client.lua` sends only input events (move L/R, rotate CCW/CW, soft drop, hard drop) via RemoteEvents. **Client never computes chain length, garbage amount, or game-end conditions.**
- **Use `RemoteEvent` for everything.** Input from client → server. Authoritative state broadcasts from server → clients.
- **Use `RemoteFunction` only for one-off client-initiated ownership queries**, specifically `UserOwnsGamePassAsync` checks. Never call `:InvokeClient()` from the server (security hazard — malicious client can yield the server thread).
- **RemoteEvent Instances** live in `ReplicatedStorage/Remotes/` as `.model.json` Rojo files so they exist in the place file without runtime instantiation, and are discoverable from both server and client modules. Names are defined in `docs/event-contract.md` (joint-owned doc — both bots reference it; changes require updating it first).
- **State replication cadence:** per-event, not per-frame. Events: piece-locked, chain-completed (with chain length), garbage-incoming, garbage-applied, round-end, match-end. A 6×12 grid × 2 players × event-driven is well within Roblox's replication budget.
- **Deterministic same-tick resolution order:** Server resolves Player 1 chain → Player 2 chain → garbage exchange → spawn checks, every tick. Even an arbitrary fixed order is better than nondeterministic; this prevents same-input-different-outcome bugs.
- **MarketplaceService:** `UserOwnsGamePassAsync(userId, gamePassId)` for ownership (cached per-session in a server-side player table on `PlayerAdded`, wrapped in `pcall`). `PromptGamePassPurchase(player, gamePassId)` to open the purchase prompt. Listen on `PromptGamePassPurchaseFinished` for completion. No `ProcessReceipt` (that's for developer products, not Game Passes).

### How code flows in practice

```
   Slack DM in #boba-drop                Your VS Code              Roblox Studio
   ──────────────────────                ────────────              ─────────────
   You: "@Game Engineer add a       ┌──→ src/.../Board.lua
        soft-drop animation"        │    (Engineer edits ↑)
                                    │
   Engineer (in Slack thread):      │
   "On it 👀"                       │    Rojo CLI watches ──────→ Rojo plugin
   ...                              │    src/ for changes         applies change
   "Pushed. Try it now."  ─────────┘                              to live Place
                                                                       ↓
                                                                  You hit Play
```

Engineer also runs `lune run tests` from CLI to validate `MatchDetector` changes before pushing.

### Source control

- `git init` in `boba-drop/` on Mon evening
- **Push to a public GitHub remote on Mon evening** (non-negotiable; the URL goes in Sarah's portfolio)
- Both bots have `additionalDirectories` covering `/Users/student/Documents`
- `.gitignore` excludes `.rbxlx` (binary)
- Commits at every milestone; Producer drives end-of-day commits

---

## 3. Game design

### Playfield

- 6 wide × 12 tall cup (visible play area) + 2 extra rows above (danger zone)
- Settling above row 12 = overflow = round loss
- **Spawn-collision loss:** if the next piece's spawn cells are occupied (stack reaches the top), the player loses the round, regardless of "settled" status

### Pieces

- Pairs of boba pearls (2 connected vertically by default; rotate to horizontal)
- 4 colors with **shape/icon differentiation in addition to color** (mandatory accessibility — colorblind-safe):
  - 🟫 Brown: 1 dot
  - 🩷 Pink: 2 dots
  - 🟢 Green: 3 dots
  - ⚪ White: 4 dots
- **Spawn RNG: shuffled-bag system.** Bag contains all 16 possible color-pair combinations (4×4); when empty, refill and shuffle. Prevents color droughts that wreck chain construction.

### Controls

**Keyboard:**
| Action | Effect |
|---|---|
| ← → | Move 1 column |
| Z | Rotate CCW |
| X | Rotate CW |
| ↓ (hold) | Soft drop (8× faster) |
| Space | Hard drop (snap to bottom) |

**Touch (mobile/tablet — ~60% of Roblox audience):**
- On-screen buttons in thumb-reach zones (bottom-left for L/R movement, bottom-right for rotate + drop)
- Minimum 44pt touch targets
- Mobile layout: your cup dominant; opponent cup shrunk to ~30% size in upper corner
- Phone layout is not "side-by-side scaled down" — it's a different layout variant

### Timings (in `Constants.lua`)

| Constant | Value | Purpose |
|---|---|---|
| `LOCK_DELAY` | 0.5s | Slide adjustment window after piece touches a surface |
| `GRAVITY_BASE` | 0.8s/row | Starting drop interval |
| `GRAVITY_RAMP` | -0.05s every 30s | Speed-up; floor at 0.2s/row |
| `SOFT_DROP_MULT` | 8× | Falls 8× faster while holding ↓ |
| `GARBAGE_QUEUE_DELAY` | 2 piece placements | Drop garbage at end of the 2nd piece placement after queue (not 1st — gives counter mechanic room) |
| `AFK_PIECE_TIMEOUT` | 15s | Max per-piece placement time; exceeding it forfeits the round |

### Rotation rule

- **No wallkick in v1.** If rotation would collide with a wall or stack, rotation is rejected (no kick, no slide). Documented player-facing.

### Match rule + chains

- When a piece locks, scan for connected groups of 4+ same-color pearls (orthogonal only)
- All matched groups pop simultaneously (250ms scale-up + flash-white tell → vanish)
- 300ms gravity settle (pearls above fall) → re-scan
- If new 4+ groups formed, they pop → repeat
- Chain length counted
- `ChainResolver` is **synchronous** on the server (no `task.wait`); animation pacing happens client-side on cosmetic mirrors of the resolved state. This makes the resolver deterministic + testable.

### Scoring formula

```
score = popped_pearls × chain_multiplier × color_bonus

chain_multiplier: 1=1, 2=3, 3=6, 4=12, 5=24, ...  (doubling)
color_bonus:      1-color=1, 2-color=2, 3-color=4, 4-color=8
```

### Garbage table (re-tuned to keep duels alive)

| Chain length | Garbage sent |
|---|---|
| 1 | 0 |
| 2 | 1 |
| 3 | 3 |
| 4 | 6 |
| 5 | 12 |
| 6+ | 24 (cap) |

Counter cancellation rule: outgoing garbage subtracts from your queued incoming first. Cap on 6+ chains prevents one-shot rounds; the counter is mathematically viable from any state.

### Garbage drop semantics

- Garbage queues appear above the receiving player's field (visible cube-icon row that pulses faster as drop approaches; red flash + screen shake at 500ms before drop)
- Drops at the end of the **2nd** piece placement after queuing
- **Spawn collision:** if garbage drop would force a pearl/cube above row 12, the player overflows and loses
- **Garbage cubes are unmatchable.** Cubes participate in gravity (they fall and settle) but never pop. Adjacent chain pops don't clear adjacent cubes.

### Round + match flow

1. Both players spawn with empty fields, see each other's cup
2. Pieces drop simultaneously
3. First overflow loses the round
4. **Tiebreaker — same-tick simultaneous overflow:** player with the lower round score loses. If scores tied, the round is a draw and does not count toward best-of-3
5. "Round X to Player Y" banner for 3 seconds
6. Both fields clear, next round begins
7. Best of 3 (first to 2 round wins) → "Match Winner" screen → rematch / leave

### Match-end screen content

- Both players' final scores (this match)
- Each player's best chain achieved
- "Closest round: X pearls from overflow" (loser-side hook)
- **Rematch:** both players must press Rematch within 15s. If either presses Leave or times out, return both to lobby.

### Disconnect / AFK rules

- **Mid-round disconnect:** opponent wins the round after a 10s grace period (during which the disconnected player can come back). **No rejoin support in v1** — if grace expires, opponent advances.
- **Best-of-3 disconnect after round 1:** the disconnect counts as a forfeit of remaining rounds; opponent wins the match.
- **AFK softlock:** per-piece-placement 15s timeout. Exceeding it forfeits the round (no piece auto-placement; clean forfeit).

### Pre-piece preview

Show the next 2 pieces above the field. Required for skilled play.

### Lobby + queue UX

- "Play" / "Searching for opponent" with elapsed time counter
- **Cancel queue** button always available
- **60s queue timeout:** if no opponent matched, surface "Play vs CPU" (basic bot opponent that just stacks; even if cut, the prompt is still shown as "no one available right now") or "Copy invite link" (URL that takes a friend directly into a private match)
- **Tutorial card** on lobby (3 lines): "Match 4+ to pop. Chain pops send ice cubes. Don't overflow." Visible until dismissed; never blocks Play.

### Visual feedback spec

- **Pop sequence:** 250ms flash-white scale-up tell → pop → 300ms gravity settle → re-scan (these timings are fixed in `UIConstants.lua`)
- **Chain counter:** "Chain x3!" text appears with pop event; persists 1s after final pop in the chain
- **Garbage warning:** row of cube icons above field; pulses faster as drop approaches; red flash + screen shake at 500ms before drop
- **Counter cancellation:** when your outgoing chain offsets incoming garbage, cubes shatter at the field boundary with a "BLOCKED!" flash and audio sting

### Shop / monetization UI

- Persistent "Themes" button on lobby (visible on first load)
- Post-match prompt: after a loss, brief "Try a theme?" overlay with preview thumbnails (dismissible)
- Tapping either opens the Shop UI with the Premium Themes Pack details and purchase CTA

---

## 4. Schedule

Target: 6h/day average. All days have explicit exit criteria. If a day slips, follow the cut ladder in §5.

### Day 0 — Mon 2026-05-18 evening (~2h)

- Install Rojo CLI, Rojo Studio plugin, Lune CLI
- Initialize project: `boba-drop/` + `default.project.json` + `lune.toml` + `git init`
- **Push to public GitHub remote** (non-negotiable). Note repo URL.
- Author `docs/event-contract.md` placeholder + commit this `design.md`
- Set up Producer bot (clone Game Engineer setup, new Slack app, new tmux session)
- Create Slack channel `#boba-drop`, invite both bots, allow channel
- Pre-write resume bullet draft (2 versions: "shipped 1v1 with Game Pass" and "shipped single-player with Game Pass")
- **Validate Rojo mapping end-to-end:** write a trivial `Hello.lua` ModuleScript in `ReplicatedStorage/Shared/Logic/`, require it from `Main.server.lua`, hit Play, print "hello" in Output. If this works, the rest of Rojo works.

**Exit:** `@Game Engineer` and `@Producer` respond in `#boba-drop`. Trivial Rojo round-trip succeeds. GitHub URL saved.

### Day 1 — Tue (~6h) — Single-player skeleton + test harness

- **🤖 Engineer:** `Board.lua` (grid + piece spawn with bag RNG + gravity + lock delay), `InputHandler.client.lua` (keyboard + touch), `PieceTypes.lua` (4 colors with dot patterns), `Constants.lua` (all timings), `MatchDetector.lua` (pure function, no Roblox deps), `tests/MatchDetector.spec.lua` (Lune tests — 8+ scenarios incl. multi-color simultaneous match, bottom-row match, edge of board match)
- **🤖 Producer:** Studio scene assembly (camera, lighting, single play column placeholder), score-display + chain-counter GUI scaffold in StarterGui, lobby tutorial card, daily-log entry
- **👤 Sarah:** Build the play-column visual in Studio, playtest piece controls (keyboard + touch on phone), report input feel

**Exit:** Drop colored pearls, L/R/rotate/hard-drop, stack on floor and each other. Mobile touch controls work. Lock delay feels right. `lune run tests` shows MatchDetector passing 8+ scenarios. No matching/popping yet.

### Day 2 — Wed (~7h, the boss fight) ⚠️ — Chains + animation pacing

- **🤖 Engineer:** `ChainResolver.lua` (synchronous loop: pop → gravity → match → pop until stable; returns chain length + total popped + colors used), scoring formula, `GameState.lua` (owns player score; tracks chain count). Extend Lune tests to cover chain reactions (3-chain, simultaneous multi-color in same chain step, chain that empties field, chain that pops bottom row).
- **🤖 Producer:** Chain counter UI ("Chain x3!" with timing), pop animations (250ms flash + scale), gravity settle pacing (300ms), sound triggers, **watchdog**: 2h checkpoints on chain logic
- **👤 Sarah:** Run Lune tests, build manual chain setups in Studio, find edge cases, report bugs

**Exit:** 4-blob match pops on visible 250ms tell. Field re-settles in 300ms. Chain reactions display "Chain x3!". `lune run tests` passes 15+ scenarios. Single-player puzzle works end-to-end.

### Day 3 — Thu (~6h) — Networking, 1v1, disconnect handling

- **🤖 Engineer:** `Main.server.lua` (bootstrap), `RemoteEvents` authoring in Rojo `.model.json`, `RoomManager.lua` (2-player matchmaking + match state machine; owns match-end transition), `StateSync.lua` (event-driven board replication), garbage queue + counter cancellation + 2-piece delay, `DisconnectHandler.lua` (10s grace, AFK 15s timeout, simultaneous-overflow tiebreaker)
- **🤖 Producer:** Lobby UI (Searching / elapsed-time / Cancel / 60s timeout fallback / invite link), garbage preview row (pulse + red flash), counter-cancellation visual ("BLOCKED!"), best-of-3 round flow + round banner, match-end screen (scores + best chain + closest-round line), rematch flow (15s mutual confirm)
- **👤 Sarah:** Test 1v1 with friend or alt account on second device. Test disconnect (close one client mid-round). Test AFK (don't drop for 15s). Test rematch.

**Exit:** Full 1v1 match end-to-end. Garbage transfers. Counter cancels. Disconnect resolves correctly. AFK forfeits. Best-of-3 ends with match-end screen. Rematch works.

### Day 4 — Fri (~5h) — Polish, monetize, publish, portfolio

- **🤖 Engineer:** Bug-bash from Thu, performance pass if needed (object pooling for cubes/pearls)
- **🤖 Producer:** `GamePasses.lua` with `UserOwnsGamePassAsync` (cached, pcall'd, on PlayerAdded) and `PromptGamePassPurchase` + `PromptGamePassPurchaseFinished` listener; Shop UI on lobby + post-match prompt; publish prep (icon, thumbnail, description, age rating)
- **👤 Sarah:**
  - Source/make icon image
  - Final playtest with friend
  - **Record 30–60s gameplay clip** showing a chain reaction + garbage exchange + a counter cancellation
  - Click File → Publish to Roblox, set Public
  - Self-purchase Game Pass to validate flow
  - Embed clip in README.md and her portfolio site
  - Finalize resume bullet from the pre-written draft

**Exit:** All 4 "shipped" checkboxes from §1 are green.

### Parallelism + Producer's daily-log cadence

Bots own non-overlapping folders, so they work in parallel. Sarah is bottleneck on playtest+decide; realistic speedup ~1.5×.

**Daily-log is not manual.** Set a Slack scheduled reminder in `#boba-drop` at 5:45pm PT each day that pings `@Producer`: "Write today's daily-log.md entry from git log + the day's Slack thread." Producer commits the entry.

---

## 5. Risks + cut plan

### Risk register

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| 1 | Chain-resolve loop has edge-case bugs | High | Lune unit tests for `MatchDetector` and `ChainResolver` written Tue. Producer schedules 2h chain-stability checkpoints on Wed. Synchronous resolver = deterministic tests. |
| 2 | Roblox networking sync misbehaves | Moderate | Server fully authoritative. Clients send inputs only. RemoteEvents everywhere; RemoteFunction only for one-shot Game Pass ownership. Deterministic same-tick resolution order. |
| 3 | Roblox/Luau learning curve | Moderate | Day 1 starts with 30 min "Roblox for Unity devs" intro from Game Engineer covering instance tree, ServerScriptService vs ReplicatedStorage, `.server.lua`/`.client.lua` extensions, Luau vs C# differences. |
| 4 | Game Pass verification flow | Low | Start age/ID verification Mon evening; ships without Game Pass if needed (still meets shipped criteria 1-3 of 4). |
| 5 | Fatigue / motivation mid-week | Low | Daily exit criteria are small + demoable. Producer enforces ship-something-daily. |
| 6 | Mobile playtest never happens | Moderate | Build touch controls Tue, not Thu. Sarah tests on her own phone end of every day. |

### Cut ladder

```
End of TUE, behind?
  Cut: pre-piece preview, fancy piece visuals
  Keep: pieces drop and stack reliably, MatchDetector Lune tests pass

End of WED, chain logic broken?
  → PIVOT to single-player Puyo (this is a product pivot, not a feature cut)
  Repurpose Thu: high-score leaderboard + daily challenge mode (same seed for all players, daily ranking)
  Repurpose Fri: monetization + publish single-player
  Update resume bullet to "shipped single-player with Game Pass" variant

End of THU, networking broken?
  → PIVOT to single-player + leaderboard (same as Wed-broken fallback)
  Use Fri: polish, monetization, publish

Fri MORNING, scrambling?
  Cut: Game Pass monetization. Publish without it. (Shipped criteria 1-3 of 4 still met.)
  Keep: published playable game + GitHub + gameplay clip

Fri AFTERNOON, still broken?
  Cut: public publish. Set Roblox game to private/unlisted, share direct link.
  Keep: a finished build with GitHub repo + README + clip
```

### Non-negotiable

- ✅ Chain reactions work
- ✅ Game is playable start-to-finish
- ✅ Code is committed to git with README **and pushed to public GitHub remote**
- ✅ 30–60s gameplay clip exists, embedded in README

---

## 6. Stretch goals (only if Fri ≥4h free, AND core ships)

| Stretch | Effort | Why it'd be cool |
|---|---|---|
| All Clear bonus (clear entire field in 1 chain → +24 garbage extra) | ~1h | Skill reward, feels great |
| Daily Challenge (deterministic daily seed, leaderboard) | ~3h | Retention + sharing — also the Wed-broken fallback |
| AI opponent NPCs driven by Slack bots via Open Cloud MessagingService | ~4h | The portfolio flex narrative — only if 1v1 ships clean |
| Animated theme switching mid-play | ~1.5h | Pure juice |

---

## Open questions

None at design time after the Round-1 multi-role review. All decisions made; tunings can flex within `Constants.lua` during playtest. Specific function signatures and unit test cases live in the implementation plan (next document).
