# Boba Drop — Design Spec

| | |
|---|---|
| **Project** | Boba Drop — 1v1 Puyo-Puyo-style falling-block duel on Roblox |
| **Owner** | Sarah Yoon |
| **Status** | Approved, ready for implementation plan |
| **Date** | 2026-05-18 |
| **Build window** | Tue 2026-05-19 → Fri 2026-05-22 |
| **Team** | Sarah + 2 Slack bots (Game Engineer, Producer) |

---

## 1. Shape

A 1v1 falling-block duel inspired by Puyo Puyo, themed as boba pearls dropping into clear cups. Pairs of colored pearls fall from above. Connect 4+ same-color pearls orthogonally to pop them. Pops cascade via gravity into chain reactions. Chains send "ice cube" garbage to the opponent's cup. First to overflow loses. Best of 3 rounds wins the match.

- **Players per match:** exactly 2
- **Round length:** ~90 seconds average
- **Match length:** ~5 minutes (best of 3)
- **Platform:** Roblox (Mac dev, ships to all Roblox clients)

### Monetization

One Game Pass at launch: **Premium Themes Pack** — three cosmetic themes (Brown Sugar Boba, Strawberry Milk, Matcha). Players in the same match each see their own theme on their own cup. Gameplay-neutral; cosmetic only.

### Stretch goal (only if Fri opens up)

The Slack bots (Game Engineer and Producer) join the Roblox game as AI opponents via Roblox Open Cloud — "my AI dev partners can also play the game they built." Portfolio-grade flex.

---

## 2. Technical architecture

### Tools

| Tool | Purpose |
|---|---|
| Roblox Studio | Visual editor, scene assembly, playtest runtime |
| Rojo CLI + Studio plugin | Sync `.lua` files from disk into Studio in real time |
| VSCode (or equivalent) | Edit Luau source |
| git | Source control (local-first; remote optional) |
| Game Engineer Slack bot (existing) | Gameplay logic in Luau |
| Producer Slack bot (new, set up Mon evening) | Schedule + UI + monetization + polish |

### Project structure

```
/Users/student/Documents/boba-drop/
├── default.project.json          # Rojo config — maps folders to Roblox instance tree
├── README.md
├── .gitignore                    # ignore .rbxlx (binary place file)
├── docs/
│   ├── design.md                 # this file
│   └── daily-log.md              # Producer bot's daily progress notes
└── src/
    ├── ServerScriptService/
    │   ├── GameLogic/            # Game Engineer owns
    │   │   ├── Board.lua             # grid state, piece spawn, gravity
    │   │   ├── MatchDetector.lua     # BFS flood-fill for 4+ same-color groups
    │   │   ├── ChainResolver.lua     # gravity → match → pop loop until stable
    │   │   └── GameState.lua         # state machine
    │   ├── Networking/           # Game Engineer owns
    │   │   ├── RoomManager.lua       # 2-player matchmaking
    │   │   └── StateSync.lua         # board-state replication
    │   └── Monetization/         # Producer owns
    │       └── GamePasses.lua        # Premium Themes Pack
    ├── ReplicatedStorage/Shared/ # Game Engineer owns
    │   ├── Constants.lua             # board dims, colors, garbage rates
    │   ├── PieceTypes.lua            # blob colors + garbage cubes
    │   └── RemoteEvents.lua          # event names
    ├── StarterPlayer/Scripts/    # Game Engineer owns
    │   └── InputHandler.lua          # local input → remote events
    └── StarterGui/               # Producer owns
        ├── Lobby/
        ├── GameUI/                   # score, chain counter, garbage preview
        └── Monetization/             # shop UI for the Game Pass
```

### How code flows in practice

1. Sarah DMs `@Game Engineer` (or `@Producer`) in `#boba-drop` with a task
2. Bot writes Luau files into `src/...` on disk
3. Rojo CLI (running locally in a terminal) detects the file change
4. Rojo Studio plugin receives the update over WebSocket and applies it to the live Place
5. Sarah hits Play in Studio to test
6. Sarah reports back in Slack; bot iterates

No copy/paste. No alt-tab between editor and Studio.

### Source control

- `git init` in `boba-drop/` on Mon evening
- Both bots have `additionalDirectories` covering `/Users/student/Documents`, so they can read/write to the repo without further config
- `.gitignore` excludes the `.rbxlx` (binary, not git-friendly)
- Commits encouraged at every milestone (Producer bot can drive this)

---

## 3. Game design

### Playfield

- Each player has a **6 wide × 12 tall** cup (visible play area)
- 2 extra rows above (danger zone)
- Pearl/cube settling above row 12 = overflow = round loss

### Pieces

- Pairs of boba pearls (2 pearls connected vertically; rotate to horizontal)
- 4 colors: 🟫 Brown, 🩷 Pink, 🟢 Green, ⚪ White
- 4 colors is Puyo Puyo's standard sweet spot

### Controls

| Action | Effect |
|---|---|
| ← → | Move 1 column |
| Z | Rotate CCW |
| X | Rotate CW |
| ↓ (hold) | Soft drop (8× faster) |
| Space | Hard drop (snap to bottom) |

### Match rule

- When a piece locks, scan for connected groups of 4+ same-color pearls (orthogonal adjacency only)
- All matched groups pop simultaneously
- Pearls above popped groups fall (gravity)
- Re-scan after settling — if new 4+ groups formed, they pop too → **chain reaction**
- Repeat until field is stable
- Track chain length for scoring + garbage

### Scoring formula

```
score = popped_pearls × chain_multiplier × color_bonus

chain_multiplier: 1=1, 2=3, 3=6, 4=12, 5=24, ...  (doubling per chain step)
color_bonus:      1-color=1, 2-color=2, 3-color=4, 4-color=8
```

### Garbage (duel mechanic)

When a chain triggers, send ice cubes (gray, unmatchable) to opponent:

| Chain length | Garbage sent |
|---|---|
| 1 | 0 |
| 2 | 2 |
| 3 | 6 |
| 4 | 14 |
| 5 | 30 |
| 6+ | 60+ (round-ending) |

### Counter / chain-back mechanic

- Incoming garbage queues above your field — visible
- Garbage drops at the end of your next piece placement (not instantly)
- If you trigger your own chain before the garbage drops, your outgoing garbage subtracts from the incoming queue first
- This is the spicy "chain back NOW or die" loop that makes Puyo great

### Round flow

1. Both players spawn with empty fields, see each other's mirror cup
2. Pieces drop simultaneously
3. First overflow loses the round
4. "Round X to Player Y" banner for 3 seconds
5. Both fields clear, next round begins
6. Best of 3 (first to 2 round wins) → "Match Winner" screen → rematch / leave

### Pre-piece preview

Show the next 2 pieces above the field. Standard Puyo convention; required for skilled play.

---

## 4. Schedule

Target: 6h/day average. All days have explicit exit criteria. If a day slips, follow the cut ladder in §5.

### Day 0 — Mon 2026-05-18 evening (~1.5h)

- Install Rojo CLI + Rojo plugin in Studio
- Initialize project: `boba-drop/` + `default.project.json` + `git init` + empty `src/` folders + commit this `design.md`
- Set up Producer bot (clone Game Engineer setup, new Slack app, new tmux session)
- Create Slack channel `#boba-drop`, invite both bots, `!allow channel <CID>` for each

**Exit:** `@Game Engineer` and `@Producer` both respond in `#boba-drop`. Empty `src/` syncs into Studio via Rojo with no errors.

### Day 1 — Tue (~6h) — Single-player skeleton

- **Game Engineer:** `Board.lua` (grid + piece spawn + gravity), `InputHandler.lua`, `PieceTypes.lua`
- **Producer:** Studio scene assembly (camera, lighting, single play column placeholder), score-display GUI scaffold, daily-log entry
- **Sarah:** Build the play-column visual in Studio, playtest piece controls, report input feel

**Exit:** A player can drop colored blob pairs, move L/R, rotate, hard-drop. Pieces stack on the floor and on each other. No matching yet.

### Day 2 — Wed (~7h, the boss fight) ⚠️

- **Game Engineer:** `MatchDetector.lua` (BFS), `ChainResolver.lua` (gravity → match → pop until stable), scoring
- **Producer:** Chain counter UI ("Chain x3!"), pop animations, sound triggers, **watchdog**: 2h checkpoints on chain logic
- **Sarah:** Aggressive testing — manual chain setups, edge cases (e.g., simultaneous multi-color pops, bottom-row chains), bug reports

**Exit:** A 4-blob match pops. Field re-settles. New 4-groups chain. Score updates. Chain length displays. Single-player puzzle works end-to-end.

### Day 3 — Thu (~6h) — 2-player + garbage

- **Game Engineer:** `RoomManager.lua` (matchmake), `StateSync.lua`, garbage queue + counter mechanic
- **Producer:** Lobby UI (Play / Waiting / Ready), garbage preview above field, win/lose screen, best-of-3 round flow
- **Sarah:** Test 1v1 with a friend (or alt Roblox account on a second device), find sync bugs

**Exit:** Two real players, one match. Chains send garbage. Counter cancellation works. Round/match end conditions correct.

### Day 4 — Fri (~5h) — Polish + monetize + publish

- **Game Engineer:** Bug-bash from Thu, performance pass (object pooling if needed)
- **Producer:** `GamePasses.lua` (Premium Themes Pack — 3 themes), shop UI, publish prep (icon, thumbnail, description, age rating)
- **Sarah:** Source/make icon image, final playtest, click File → Publish to Roblox, set Public

**Exit:** Game live at a `roblox.com/games/...` URL. Premium Themes Pack purchasable. Friends can join.

### Parallelism note

Bots own non-overlapping folders, so they work in parallel. Sarah is still the bottleneck (playtest + decide). Realistic speedup ~1.5×, not 2×.

---

## 5. Risks + cut plan

### Risk register

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| 1 | Chain-resolve loop has edge-case bugs (gravity settle, simultaneous multi-color, bottom-row chain) | High | Unit tests for `MatchDetector` written Tue, before integration. Producer schedules 2h chain-stability checkpoints on Wed. If broken at 6pm Wed, escalate per cut ladder. |
| 2 | Roblox networking sync misbehaves between 2 players | Moderate | Server is authoritative. Clients only send inputs. Use RemoteEvents for cosmetic, RemoteFunctions for state. |
| 3 | Roblox/Luau learning curve (Sarah is new to platform) | Moderate | Day 1 starts with 30 min "Roblox for Unity devs" intro from Game Engineer. Bots explain as they write. |
| 4 | Game Pass verification flow blocks monetization | Low | Start verification Mon evening. Game still ships without Game Pass if needed. |
| 5 | Fatigue / motivation mid-week | Low | Daily exit criteria are small and demoable. Producer enforces "ship-something-today" each evening. |

### Cut ladder

```
End of TUE, behind?
  Cut: pre-piece preview, fancy piece visuals
  Keep: pieces drop and stack reliably

End of WED, chain logic broken?
  Cut: 2-player entirely. Ship single-player Puyo.
  Repurpose Thu: high-score leaderboard + polish
  Repurpose Fri: monetization + publish single-player

End of THU, networking broken?
  Cut: 1v1 mode. Ship single-player.
  Use Fri for: leaderboard, polish, monetization, publish

Fri MORNING, scrambling?
  Cut: Game Pass monetization. Publish without it.
  Keep: a published, playable game

Fri AFTERNOON, still broken?
  Cut: public publish. Leave as private/unlisted, share link in portfolio.
  Keep: a finished build
```

### Non-negotiable

- Chain reactions work
- Game is playable start-to-finish (loop closes)
- Code is committed to git with a README

---

## 6. Stretch goals (only if Fri ≥4h free)

| Stretch | Effort | Why it'd be cool |
|---|---|---|
| All Clear bonus (clear entire field in 1 chain → +30 garbage) | ~1h | Tiny add, rewards skilled play, feels great |
| Daily Challenge mode (same seed for everyone, leaderboard) | ~3h | Retention + sharing hook |
| AI opponents via Open Cloud (Slack bots play the game) | ~4h | The portfolio flex |
| Animated theme switching mid-play | ~1.5h | Pure juice |

---

## Open questions / decisions still TBD

None at design time. All in scope, all approved by owner. Specific filenames, function signatures, and unit test cases live in the implementation plan (next document).
