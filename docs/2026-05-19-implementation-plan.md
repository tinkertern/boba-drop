# Boba Drop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a 1v1 Puyo-Puyo-style Roblox game (Boba Drop) with chain reactions, garbage transfer, counter cancellation, and Game Pass monetization in 4 days (Tue 2026-05-19 → Fri 2026-05-22).

**Architecture:** Server-authoritative Roblox/Luau. Pure logic modules in `ReplicatedStorage/Shared/Logic/` (no Roblox runtime deps; Lune-testable). `Main.server.lua` bootstraps the live system. Rojo CLI syncs `src/` from disk into Studio. Bots own non-overlapping folders.

**Tech Stack:** Roblox Luau, Roblox Studio (Mac), Rojo (file sync), Lune (CLI test runner), git + GitHub, MarketplaceService for Game Pass.

**Reference spec:** `/Users/student/Documents/boba-drop/docs/design.md` (approved through Round 4 multi-role review).

---

## File Structure

Each file's responsibility, used as the authoritative reference during tasks.

### `default.project.json` (Rojo config, repo root)
Maps `src/` folders to Roblox instance tree. Specifies the `DataModel` shape.

### `lune.toml` (Lune config, repo root)
Configures Lune CLI test runner. Optional — `lune run path/to/script.luau` works without it.

### `tests/*.spec.lua` (Lune-runnable tests)
Pure-logic test scripts. Each one requires modules from `src/ReplicatedStorage/Shared/Logic/` and asserts behavior.

### Logic modules — owned by 🤖 Engineer, pure (no Roblox dependencies)
- `src/ReplicatedStorage/Shared/Logic/Constants.lua` — gameplay constants (board dims, garbage table, timings)
- `src/ReplicatedStorage/Shared/PieceTypes.lua` — color enum + dot patterns + shape fallbacks
- `src/ReplicatedStorage/Shared/Logic/Board.lua` — grid state, piece spawn with injected bag RNG, gravity, `peek(n)` for preview
- `src/ReplicatedStorage/Shared/Logic/MatchDetector.lua` — BFS flood-fill for 4+ same-color groups (pure function)
- `src/ReplicatedStorage/Shared/Logic/ChainResolver.lua` — synchronous pop → gravity → match loop; returns `{chainLength, totalPopped, colorsUsed}`
- `src/ReplicatedStorage/Shared/Logic/Scoring.lua` — pure scoring formula
- `src/ReplicatedStorage/Shared/Logic/GameState.lua` — round/match state machine. Sole writer for round/match state. Owns scores. Implements `resolveTick()`, `forfeitRound()`, pub/sub event interface.
- `src/ReplicatedStorage/Shared/Events.lua` — event names + payload-shape type annotations (joint reference)

### Networking — owned by 🤖 Engineer
- `src/ServerScriptService/Main.server.lua` — bootstrap. Wires up RoomManager, StateSync, DisconnectHandler.
- `src/ServerScriptService/Networking/RoomManager.lua` — session lifecycle. Sole writer for session/lobby state.
- `src/ServerScriptService/Networking/StateSync.lua` — subscribes to GameState pub/sub; emits RemoteEvents.
- `src/ServerScriptService/Networking/DisconnectHandler.lua` — phase-aware routing (in-round → GameState; post-match → RoomManager).
- `src/ReplicatedStorage/Remotes/*.model.json` — RemoteEvent Instances as Rojo model files.

### Client — owned by 🤖 Engineer
- `src/StarterPlayer/StarterPlayerScripts/InputHandler.client.lua` — keyboard + touch input → RemoteEvents.

### UI — owned by 🤖 Producer
- `src/ReplicatedStorage/Shared/UI/UIConstants.lua` — colors, fonts, durations, HUD z-order stack.
- `src/StarterGui/Lobby/*` — tutorial card, queue UI, themes button, invite link.
- `src/StarterGui/GameUI/*` — score, chain counter, garbage preview, preview cluster.
- `src/StarterGui/MatchEnd/*` — winner screen, rematch flow.
- `src/StarterGui/Shop/*` — Game Pass shop.

### Monetization — owned by 🤖 Producer
- `src/ServerScriptService/Monetization/GamePasses.lua` — cached ownership + purchase prompt + filtered listener.

---

## Day 0 — Mon 2026-05-18 evening setup (~2h)

Most of this is already complete from earlier work in this project (Game Engineer bot, repo init, design spec). Confirm the remaining items before starting Day 1.

### Task 0.1: Verify Roblox account capability

**Files:** none (external check)

- [ ] **Step 1:** Open https://create.roblox.com — log in as Sarah's primary account
- [ ] **Step 2:** Click "Creator Dashboard" → "Creations" → confirm there's no banner blocking Game Pass creation. Requirements: account age verified, ID verified for monetization payouts (the "Payout" gate isn't blocking; the "list a Game Pass" gate is what matters here).
- [ ] **Step 3:** Confirm purchaser-side Robux balance ≥100 Robux (Premium Themes Pack will be priced at 99 Robux for a clean test purchase)
- [ ] **Step 4:** If either is blocked, escalate per Risk #4: start ID verification immediately; in parallel, plan for the Fri-morning fallback (ship without Game Pass; criterion #4 fails but #1-3 still pass)

### Task 0.2: Install Rojo CLI and Studio plugin

**Files:** none (tools)

- [ ] **Step 1: Install Rojo CLI via Homebrew**

Run: `brew install rojo`
Expected: `rojo` available on PATH. Verify: `rojo --version` prints `Rojo 7.x.x` or higher.

- [ ] **Step 2: Install Rojo plugin in Studio**

Open Roblox Studio → top toolbar → **Plugins** tab → **Plugins Folder** → quit Studio. Then run:

```bash
rojo plugin install
```

Expected: "Installed plugin to <plugins folder>". Restart Studio. The Rojo plugin should appear in the Plugins toolbar.

### Task 0.3: Install Lune CLI

**Files:** none (tool)

- [ ] **Step 1: Install Lune via Homebrew**

Run: `brew install lune`
Expected: `lune` available on PATH. Verify: `lune --version` prints `lune 0.8.x` or higher.

- [ ] **Step 2: Verify Lune can execute a trivial script**

Run: `echo 'print("hello from lune")' | lune run -`
Expected: stdout contains `hello from lune`. If this fails, Lune install needs troubleshooting before Day 1.

### Task 0.4: Push to GitHub

**Files:** `/Users/student/Documents/boba-drop/` (existing git repo)

- [ ] **Step 1: Create public GitHub repo** (manual; on github.com)

Browser: https://github.com/new → name `boba-drop` → public → no README/license (we already have one) → Create. Copy the SSH or HTTPS URL.

- [ ] **Step 2: Add remote and push**

```bash
cd /Users/student/Documents/boba-drop
git remote add origin git@github.com:<sarah-username>/boba-drop.git
git branch -M main
git push -u origin main
```

Expected: all 5 existing commits pushed; GitHub page shows `docs/design.md`, `README.md`, `.gitignore`.

- [ ] **Step 3: Update README with repo URL**

The repo URL is the primary portfolio artifact. Make sure the README references itself at the top.

### Task 0.5: Set up Producer bot

**Files:** `/Users/student/Documents/workspaces/producer/` (new), `/Users/student/Documents/workspaces/slack-channel/.env` (new vars)

- [ ] **Step 1: Create second Slack app**

Browser: https://api.slack.com/apps → Create New App from manifest → workspace → paste the same manifest used for Game Engineer (display name "Producer") → install → copy xapp + xoxb tokens.

- [ ] **Step 2: Duplicate bot directory**

```bash
cp -r /Users/student/Documents/workspaces/game-engineer /Users/student/Documents/workspaces/producer
```

- [ ] **Step 3: Write Producer's CLAUDE.md**

Producer has a different persona than Game Engineer. Replace `/Users/student/Documents/workspaces/producer/CLAUDE.md` with a Producer-focused prompt — owns schedule + UI + monetization + polish + daily-log, enforces "ship-something-daily," tracks Tue–Fri milestones.

(Full text of Producer CLAUDE.md is in §4.5 below. Copy it from there.)

- [ ] **Step 4: Update settings.local.json paths**

Edit `/Users/student/Documents/workspaces/producer/.claude/settings.local.json` — every occurrence of `game-engineer` becomes `producer`. The memory path slug `-Users-student-Documents-workspaces-game-engineer` becomes `-Users-student-Documents-workspaces-producer`.

- [ ] **Step 5: Add a second .env-style slot for Producer's Slack tokens**

The shared `slack-channel/.env` only supports one bot. For Producer, create `/Users/student/Documents/workspaces/producer/.env`:

```bash
SLACK_BOT_TOKEN=<producer-xoxb>
SLACK_APP_TOKEN=<producer-xapp>
SLACK_OWNER_USER=U09AWNG8R5Y
SLACK_OWNER_NAME=Sarah
SLACK_ALLOWED_USERS=U09AWNG8R5Y
SLACK_ALLOWED_BOT_USERS=U0B4H4WNBU3
PERMISSION_RELAY=true
PERMISSION_DM=<producer-dm-id>
JERRAI_PERMISSION_MODE=bypassPermissions
JERRAI_TMUX_SESSION=producer
```

Note: `SLACK_ALLOWED_BOT_USERS=U0B4H4WNBU3` is Game Engineer's bot UID — allows the two bots to interact in channels.

- [ ] **Step 6: Modify slack.ts to load .env from CWD**

This is the only change needed inside the slack-channel repo (still allowed because `.env` files are gitignored, but slack.ts itself isn't). Actually — to avoid modifying the repo, an alternative is to run Producer with `cd producer && env $(cat .env | xargs) ... slack.ts`. Wrap this in a `start-producer.sh` script analogous to `start-game-engineer.sh`.

Create `/Users/student/Documents/workspaces/start-producer.sh` as a copy of `start-game-engineer.sh` with: SESSION_NAME="producer", BOT_DIR="$WORKSPACES_DIR/producer", and the env-loading line `set -a; source "$BOT_DIR/.env"; set +a` added before the `claude` invocation.

```bash
cp /Users/student/Documents/workspaces/start-game-engineer.sh /Users/student/Documents/workspaces/start-producer.sh
```

Then edit the new copy:
- `SESSION_NAME="producer"`
- `BOT_DIR="$WORKSPACES_DIR/producer"`
- Add before launch: `set -a; source "$BOT_DIR/.env"; set +a`

```bash
chmod +x /Users/student/Documents/workspaces/start-producer.sh
```

- [ ] **Step 7: Launch Producer**

```bash
/Users/student/Documents/workspaces/start-producer.sh
tail -f /Users/student/Documents/workspaces/slack-channel/jerrai.log
```

Expected log lines: `Slack connected: producer (U…)` and `Socket Mode: connected`.

- [ ] **Step 8: Create #boba-drop Slack channel + allow both bots**

In Slack: + Direct messages → create channel `boba-drop` → invite both bots via `/invite @Game Engineer` and `/invite @Producer`.

Then DM each bot: `!allow channel <C-id-of-boba-drop> Boba Drop project channel`.

### Task 0.6: Validate Rojo round-trip with Hello.lua

**Files:**
- Create: `/Users/student/Documents/boba-drop/default.project.json`
- Create: `/Users/student/Documents/boba-drop/src/ReplicatedStorage/Shared/Logic/Hello.lua`
- Create: `/Users/student/Documents/boba-drop/src/ServerScriptService/HelloTest.server.lua`

- [ ] **Step 1: Write default.project.json**

```json
{
  "name": "boba-drop",
  "tree": {
    "$className": "DataModel",
    "ServerScriptService": {
      "$path": "src/ServerScriptService"
    },
    "ReplicatedStorage": {
      "$path": "src/ReplicatedStorage"
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "StarterPlayerScripts": {
        "$path": "src/StarterPlayer/StarterPlayerScripts"
      }
    },
    "StarterGui": {
      "$path": "src/StarterGui"
    }
  }
}
```

- [ ] **Step 2: Write Hello.lua (sanity ModuleScript)**

```lua
-- src/ReplicatedStorage/Shared/Logic/Hello.lua
local Hello = {}

function Hello.greet(name)
    return "hello, " .. name
end

return Hello
```

- [ ] **Step 3: Write HelloTest.server.lua (sanity Script)**

```lua
-- src/ServerScriptService/HelloTest.server.lua
local Hello = require(game.ReplicatedStorage.Shared.Logic.Hello)
print(Hello.greet("Sarah"))
```

- [ ] **Step 4: Start Rojo CLI**

From `/Users/student/Documents/boba-drop/` in a terminal:

```bash
rojo serve
```

Expected: `Rojo server listening: http://localhost:34872`. Leave running.

- [ ] **Step 5: Connect Rojo plugin in Studio**

Open Studio → File → New → Baseplate → save the place as `boba-drop.rbxlx` outside the repo (e.g., `~/Documents/RobloxStudioPlaces/boba-drop.rbxlx`). In the Plugins toolbar → Rojo → Connect → it should auto-connect to localhost:34872 → status shows "Connected" + "Patched X instances."

- [ ] **Step 6: Play and verify**

In Studio → Play (F5 or the green Play button). In Output, you should see: `hello, Sarah`.

- [ ] **Step 7: Commit the bootstrap**

```bash
cd /Users/student/Documents/boba-drop
git add default.project.json src/
git commit -m "Day 0: bootstrap Rojo with Hello.lua sanity check"
git push
```

### Task 0.7: Pre-write resume bullet variants

**Files:**
- Create: `/Users/student/Documents/boba-drop/docs/resume-bullet-drafts.md`

- [ ] **Step 1: Write both variants**

```markdown
# Boba Drop — Resume Bullet Drafts

Selection deadline: Sat 2026-05-23 noon PT.

## Variant A — Shipped 1v1 with Game Pass (preferred)

Designed and shipped Boba Drop, a 1v1 Puyo-Puyo-style Roblox game with chain
reactions, garbage transfer with counter cancellation, and a published Game Pass
for cosmetic monetization, in 4 days using two AI pair-programmers via Slack.
Built server-authoritative networking in Luau with CLI-tested pure logic modules
(Lune) and Rojo file-sync; deployed to roblox.com/games/<id>.

## Variant B — Shipped single-player with Game Pass (fallback)

Designed and shipped Boba Drop, a single-player Puyo-Puyo-style Roblox puzzle
game with chain-reaction scoring and a published Game Pass for cosmetic
monetization, in 4 days using two AI pair-programmers via Slack. Built a daily-
challenge mode with deterministic seeds, CLI-tested pure logic modules (Lune),
and Rojo file-sync; deployed to roblox.com/games/<id>.
```

- [ ] **Step 2: Commit**

```bash
git add docs/resume-bullet-drafts.md
git commit -m "Day 0: resume bullet drafts (Variant A + B); select by Sat noon"
git push
```

---

## Day 1 — Tue 2026-05-19: Skeleton + Test Harness (~6h)

By end of day: pieces drop and stack on a Studio play column, keyboard + touch controls work, `lune run tests/MatchDetector.spec.lua` passes 8+ scenarios. **No matching/popping yet.**

### Task 1.1: Lune test harness + first assertion helper

**Files:**
- Create: `/Users/student/Documents/boba-drop/tests/_test_helpers.luau`
- Create: `/Users/student/Documents/boba-drop/tests/smoke.spec.luau`

- [ ] **Step 1: Write the test helper**

```lua
-- tests/_test_helpers.luau
-- Minimal describe/it wrapper around Luau's built-in assert.

local M = {}

local indent = ""
local failures = 0
local total = 0

function M.describe(name, fn)
    print(indent .. "▸ " .. name)
    indent = indent .. "  "
    fn()
    indent = indent:sub(1, -3)
end

function M.it(name, fn)
    total += 1
    local ok, err = pcall(fn)
    if ok then
        print(indent .. "✓ " .. name)
    else
        failures += 1
        print(indent .. "✗ " .. name .. " — " .. tostring(err))
    end
end

function M.assertEq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function M.assertDeepEq(actual, expected, msg)
    local function deepEq(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in a do
            if not deepEq(v, b[k]) then return false end
        end
        for k, v in b do
            if not deepEq(v, a[k]) then return false end
        end
        return true
    end
    if not deepEq(actual, expected) then
        error((msg or "") .. " deep mismatch", 2)
    end
end

function M.summary()
    print(string.format("\n%d/%d passed (%d failed)", total - failures, total, failures))
    if failures > 0 then
        error("test failures", 0)
    end
end

return M
```

- [ ] **Step 2: Write the smoke test**

```lua
-- tests/smoke.spec.luau
local t = require("./_test_helpers")

t.describe("smoke", function()
    t.it("the test helper works", function()
        t.assertEq(1 + 1, 2)
    end)
end)

t.summary()
```

- [ ] **Step 3: Run it**

```bash
cd /Users/student/Documents/boba-drop
lune run tests/smoke.spec.luau
```

Expected:
```
▸ smoke
  ✓ the test helper works

1/1 passed (0 failed)
```

- [ ] **Step 4: Commit**

```bash
git add tests/
git commit -m "Day 1: Lune test harness with describe/it/assertEq helpers"
git push
```

### Task 1.2: Constants module

**Files:**
- Create: `src/ReplicatedStorage/Shared/Logic/Constants.lua`

- [ ] **Step 1: Write Constants.lua**

```lua
-- src/ReplicatedStorage/Shared/Logic/Constants.lua
local Constants = {}

-- Board
Constants.BOARD_WIDTH = 6
Constants.BOARD_VISIBLE_HEIGHT = 12
Constants.BOARD_DANGER_ROWS = 2 -- rows above visible; overflow at row 13+
Constants.BOARD_TOTAL_HEIGHT = Constants.BOARD_VISIBLE_HEIGHT + Constants.BOARD_DANGER_ROWS

-- Match rule
Constants.MIN_MATCH_SIZE = 4

-- Pieces
Constants.NUM_COLORS = 4
Constants.COLORS = { "Brown", "Pink", "Green", "White" }

-- Timings (seconds)
Constants.LOCK_DELAY = 0.5
Constants.GRAVITY_BASE = 0.8
Constants.GRAVITY_RAMP_PER_30S = -0.05
Constants.GRAVITY_FLOOR = 0.2
Constants.SOFT_DROP_MULT = 8
Constants.AFK_PIECE_TIMEOUT = 15
Constants.GARBAGE_QUEUE_DELAY_PLACEMENTS = 2

-- Animation pacing
Constants.POP_TELL_DURATION = 0.25
Constants.GRAVITY_SETTLE_DURATION = 0.30
Constants.CHAIN_COUNTER_PERSIST = 1.0
Constants.GARBAGE_DROP_WARNING_LEAD = 0.5

-- Garbage table (chain length → cubes sent)
Constants.GARBAGE_TABLE = {
    [1] = 0,
    [2] = 1,
    [3] = 3,
    [4] = 6,
    [5] = 12,
}
Constants.GARBAGE_CAP = 24 -- for chain length 6+

-- Scoring multipliers
Constants.CHAIN_MULTIPLIER = { 1, 3, 6, 12, 24, 48, 96 } -- doubling
Constants.COLOR_BONUS = { 1, 2, 4, 8 } -- by distinct colors in the chain step

-- Network / disconnect
Constants.DISCONNECT_GRACE = 10
Constants.REMATCH_WINDOW = 15
Constants.REMATCH_LEAVE_COOLDOWN = 1
Constants.QUEUE_TIMEOUT = 60

-- Match
Constants.ROUNDS_TO_WIN = 2 -- best of 3

return Constants
```

- [ ] **Step 2: Commit**

```bash
git add src/ReplicatedStorage/Shared/Logic/Constants.lua
git commit -m "Day 1: Constants module — board, timings, garbage table, scoring multipliers"
git push
```

### Task 1.3: PieceTypes module

**Files:**
- Create: `src/ReplicatedStorage/Shared/PieceTypes.lua`
- Create: `tests/PieceTypes.spec.luau`

- [ ] **Step 1: Write the failing test first**

```lua
-- tests/PieceTypes.spec.luau
local t = require("./_test_helpers")
local PieceTypes = require("../src/ReplicatedStorage/Shared/PieceTypes")

t.describe("PieceTypes", function()
    t.it("exposes 4 colors in canonical order", function()
        t.assertEq(#PieceTypes.COLORS, 4)
        t.assertEq(PieceTypes.COLORS[1], "Brown")
        t.assertEq(PieceTypes.COLORS[2], "Pink")
        t.assertEq(PieceTypes.COLORS[3], "Green")
        t.assertEq(PieceTypes.COLORS[4], "White")
    end)

    t.it("assigns dot counts 1..4 to colors", function()
        t.assertEq(PieceTypes.dotCount("Brown"), 1)
        t.assertEq(PieceTypes.dotCount("Pink"), 2)
        t.assertEq(PieceTypes.dotCount("Green"), 3)
        t.assertEq(PieceTypes.dotCount("White"), 4)
    end)

    t.it("assigns distinct shape fallbacks per color", function()
        local shapes = {}
        for _, color in PieceTypes.COLORS do
            local s = PieceTypes.shape(color)
            assert(s, "shape missing for " .. color)
            assert(not shapes[s], "duplicate shape " .. s)
            shapes[s] = true
        end
    end)

    t.it("recognizes garbage as a special non-color", function()
        t.assertEq(PieceTypes.isGarbage("Garbage"), true)
        t.assertEq(PieceTypes.isGarbage("Brown"), false)
    end)
end)

t.summary()
```

- [ ] **Step 2: Run to verify failure**

```bash
lune run tests/PieceTypes.spec.luau
```

Expected: error about `../src/ReplicatedStorage/Shared/PieceTypes` not found.

- [ ] **Step 3: Implement PieceTypes.lua**

```lua
-- src/ReplicatedStorage/Shared/PieceTypes.lua
local PieceTypes = {}

PieceTypes.COLORS = { "Brown", "Pink", "Green", "White" }

local DOT_COUNTS = { Brown = 1, Pink = 2, Green = 3, White = 4 }
local SHAPES = { Brown = "square", Pink = "triangle", Green = "circle", White = "star" }

function PieceTypes.dotCount(color)
    return DOT_COUNTS[color]
end

function PieceTypes.shape(color)
    return SHAPES[color]
end

function PieceTypes.isGarbage(color)
    return color == "Garbage"
end

function PieceTypes.isValid(color)
    return DOT_COUNTS[color] ~= nil or color == "Garbage"
end

return PieceTypes
```

- [ ] **Step 4: Run to verify pass**

```bash
lune run tests/PieceTypes.spec.luau
```

Expected: `4/4 passed (0 failed)`.

- [ ] **Step 5: Commit**

```bash
git add src/ReplicatedStorage/Shared/PieceTypes.lua tests/PieceTypes.spec.luau
git commit -m "Day 1: PieceTypes module with dot counts + shape fallbacks + tests"
git push
```

### Task 1.4: Board.lua — grid, bag RNG, gravity, peek

**Files:**
- Create: `src/ReplicatedStorage/Shared/Logic/Board.lua`
- Create: `tests/Board.spec.luau`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/Board.spec.luau
local t = require("./_test_helpers")
local Board = require("../src/ReplicatedStorage/Shared/Logic/Board")
local Constants = require("../src/ReplicatedStorage/Shared/Logic/Constants")

local function newBoardWithSeed(seed)
    -- Board.new takes a context object; pass an injected RNG seed.
    return Board.new({ seed = seed })
end

t.describe("Board", function()
    t.it("starts empty", function()
        local b = newBoardWithSeed(1)
        for r = 1, Constants.BOARD_TOTAL_HEIGHT do
            for c = 1, Constants.BOARD_WIDTH do
                t.assertEq(b:cellAt(r, c), nil)
            end
        end
    end)

    t.it("dimensions are 6 wide × 14 tall (12 visible + 2 danger)", function()
        local b = newBoardWithSeed(1)
        t.assertEq(b.width, 6)
        t.assertEq(b.height, 14)
    end)

    t.it("peek(2) returns the next 2 pieces", function()
        local b = newBoardWithSeed(42)
        local upcoming = b:peek(2)
        t.assertEq(#upcoming, 2)
        for _, piece in upcoming do
            assert(piece.a and piece.b, "piece must have top (a) and bottom (b) colors")
        end
    end)

    t.it("same seed produces same piece sequence (determinism)", function()
        local b1, b2 = newBoardWithSeed(42), newBoardWithSeed(42)
        local p1, p2 = b1:peek(5), b2:peek(5)
        for i = 1, 5 do
            t.assertEq(p1[i].a, p2[i].a)
            t.assertEq(p1[i].b, p2[i].b)
        end
    end)

    t.it("different seeds produce different sequences", function()
        local b1, b2 = newBoardWithSeed(1), newBoardWithSeed(2)
        local p1, p2 = b1:peek(10), b2:peek(10)
        local anyDiff = false
        for i = 1, 10 do
            if p1[i].a ~= p2[i].a or p1[i].b ~= p2[i].b then
                anyDiff = true
                break
            end
        end
        assert(anyDiff, "10 piece prefixes should not be identical across seeds")
    end)

    t.it("bag refills after 16 pairs (all combos drawn)", function()
        local b = newBoardWithSeed(7)
        local first = b:peek(16)
        b:advance(16) -- consume 16 pairs
        local second = b:peek(16) -- next 16 from new bag
        -- Both bags contain the same 16 combinations (possibly different order)
        local function bagSet(pairs)
            local s = {}
            for _, p in pairs do s[p.a .. "/" .. p.b] = true end
            return s
        end
        local set1 = bagSet(first)
        local set2 = bagSet(second)
        for k in set1 do t.assertEq(set2[k], true, "missing pair " .. k .. " in refill") end
        for k in set2 do t.assertEq(set1[k], true, "missing pair " .. k .. " in original") end
    end)

    t.it("placeAt sets a cell", function()
        local b = newBoardWithSeed(1)
        b:placeAt(1, 1, "Brown")
        t.assertEq(b:cellAt(1, 1), "Brown")
    end)

    t.it("gravitySettle drops a floating cell to the floor", function()
        local b = newBoardWithSeed(1)
        b:placeAt(5, 3, "Pink") -- floating at row 5, col 3
        b:gravitySettle()
        t.assertEq(b:cellAt(5, 3), nil, "old position should be empty")
        t.assertEq(b:cellAt(1, 3), "Pink", "should be at row 1 (bottom)")
    end)

    t.it("gravitySettle preserves stacking order in a column", function()
        local b = newBoardWithSeed(1)
        b:placeAt(8, 2, "Brown")
        b:placeAt(5, 2, "Pink")
        b:placeAt(3, 2, "Green")
        b:gravitySettle()
        t.assertEq(b:cellAt(1, 2), "Green") -- lowest of the three placed → bottom
        t.assertEq(b:cellAt(2, 2), "Pink")
        t.assertEq(b:cellAt(3, 2), "Brown")
    end)
end)

t.summary()
```

- [ ] **Step 2: Run to verify failure**

```bash
lune run tests/Board.spec.luau
```

Expected: error about `Board` not found or `Board.new` not defined.

- [ ] **Step 3: Implement Board.lua**

```lua
-- src/ReplicatedStorage/Shared/Logic/Board.lua
local Constants = require("../Logic/Constants")
local PieceTypes = require("../PieceTypes")

local Board = {}
Board.__index = Board

-- Pure pseudo-RNG: linear congruential generator so we control seeding precisely
-- and Lune tests reproduce deterministically.
local function makeRng(seed)
    local state = seed % 2147483647
    if state <= 0 then state += 2147483646 end
    return function()
        state = (state * 16807) % 2147483647
        return state
    end
end

local function shuffledBag(rng)
    local bag = {}
    for _, a in Constants.COLORS do
        for _, b in Constants.COLORS do
            table.insert(bag, { a = a, b = b })
        end
    end
    -- Fisher-Yates
    for i = #bag, 2, -1 do
        local j = (rng() % i) + 1
        bag[i], bag[j] = bag[j], bag[i]
    end
    return bag
end

function Board.new(ctx)
    assert(ctx and ctx.seed, "Board.new requires ctx.seed (injected RNG seed)")
    local self = setmetatable({}, Board)
    self.width = Constants.BOARD_WIDTH
    self.height = Constants.BOARD_TOTAL_HEIGHT
    self.cells = {} -- cells[row][col] = colorName or nil
    for r = 1, self.height do
        self.cells[r] = {}
    end
    self._rng = makeRng(ctx.seed)
    self._bag = shuffledBag(self._rng)
    self._bagIndex = 1
    return self
end

function Board:_drawOne()
    if self._bagIndex > #self._bag then
        self._bag = shuffledBag(self._rng)
        self._bagIndex = 1
    end
    local piece = self._bag[self._bagIndex]
    self._bagIndex += 1
    return piece
end

function Board:peek(n)
    -- Non-destructive: return the next n pieces without consuming them.
    -- Snapshot index + bag state so we can restore.
    local result = {}
    local savedIndex = self._bagIndex
    local savedBag = table.clone(self._bag)
    for _ = 1, n do
        table.insert(result, self:_drawOne())
    end
    self._bagIndex = savedIndex
    self._bag = savedBag
    return result
end

function Board:advance(n)
    -- Destructive: consume n pieces from the bag.
    local result = {}
    for _ = 1, n do
        table.insert(result, self:_drawOne())
    end
    return result
end

function Board:cellAt(row, col)
    if row < 1 or row > self.height or col < 1 or col > self.width then return nil end
    return self.cells[row][col]
end

function Board:placeAt(row, col, color)
    assert(PieceTypes.isValid(color), "invalid color: " .. tostring(color))
    self.cells[row][col] = color
end

function Board:clearAt(row, col)
    self.cells[row][col] = nil
end

function Board:gravitySettle()
    for col = 1, self.width do
        local writeRow = 1
        for row = 1, self.height do
            local c = self.cells[row][col]
            if c ~= nil then
                if row ~= writeRow then
                    self.cells[writeRow][col] = c
                    self.cells[row][col] = nil
                end
                writeRow += 1
            end
        end
    end
end

return Board
```

- [ ] **Step 4: Run to verify pass**

```bash
lune run tests/Board.spec.luau
```

Expected: `9/9 passed (0 failed)`. If any fail, the most likely culprits are the bag-refill test (LCG state ordering) or gravity (off-by-one in row indices). Read the error message and fix the implementation, not the test.

- [ ] **Step 5: Commit**

```bash
git add src/ReplicatedStorage/Shared/Logic/Board.lua tests/Board.spec.luau
git commit -m "Day 1: Board module with bag RNG, peek/advance, placeAt, gravitySettle + tests"
git push
```

### Task 1.5: MatchDetector.lua — BFS flood-fill for 4+ same-color groups

**Files:**
- Create: `src/ReplicatedStorage/Shared/Logic/MatchDetector.lua`
- Create: `tests/MatchDetector.spec.luau`

- [ ] **Step 1: Write the failing test (8 scenarios)**

```lua
-- tests/MatchDetector.spec.luau
local t = require("./_test_helpers")
local Board = require("../src/ReplicatedStorage/Shared/Logic/Board")
local MatchDetector = require("../src/ReplicatedStorage/Shared/Logic/MatchDetector")

local function emptyBoard()
    return Board.new({ seed = 1 })
end

t.describe("MatchDetector", function()
    t.it("finds no matches on an empty board", function()
        local b = emptyBoard()
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 0)
    end)

    t.it("finds no matches for a 3-blob cluster (below threshold)", function()
        local b = emptyBoard()
        b:placeAt(1, 1, "Brown")
        b:placeAt(2, 1, "Brown")
        b:placeAt(1, 2, "Brown")
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 0)
    end)

    t.it("finds a single 4-blob group in an L shape", function()
        local b = emptyBoard()
        b:placeAt(1, 1, "Pink")
        b:placeAt(2, 1, "Pink")
        b:placeAt(3, 1, "Pink")
        b:placeAt(1, 2, "Pink")
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 1)
        t.assertEq(#groups[1].cells, 4)
        t.assertEq(groups[1].color, "Pink")
    end)

    t.it("finds two separate groups of the same color", function()
        local b = emptyBoard()
        -- Group 1: 4 Green in column 1
        for r = 1, 4 do b:placeAt(r, 1, "Green") end
        -- Group 2: 4 Green in column 6 (not adjacent to column 1)
        for r = 1, 4 do b:placeAt(r, 6, "Green") end
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 2)
        for _, g in groups do t.assertEq(g.color, "Green") end
    end)

    t.it("does not connect diagonally", function()
        local b = emptyBoard()
        -- 4 Brown in a diagonal: (1,1), (2,2), (3,3), (4,4) — should NOT match
        b:placeAt(1, 1, "Brown")
        b:placeAt(2, 2, "Brown")
        b:placeAt(3, 3, "Brown")
        b:placeAt(4, 4, "Brown")
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 0)
    end)

    t.it("ignores garbage cubes (they never form groups)", function()
        local b = emptyBoard()
        for r = 1, 5 do b:placeAt(r, 1, "Garbage") end
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 0)
    end)

    t.it("returns multiple groups of different colors in one scan", function()
        local b = emptyBoard()
        for r = 1, 4 do b:placeAt(r, 1, "White") end
        for c = 1, 4 do b:placeAt(8, c, "Pink") end
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 2)
        local colors = { groups[1].color, groups[2].color }
        table.sort(colors)
        t.assertEq(colors[1], "Pink")
        t.assertEq(colors[2], "White")
    end)

    t.it("finds a 5-blob group across a row-and-column corner", function()
        local b = emptyBoard()
        -- T shape: 4 across row 3, plus one above
        b:placeAt(3, 2, "Brown")
        b:placeAt(3, 3, "Brown")
        b:placeAt(3, 4, "Brown")
        b:placeAt(3, 5, "Brown")
        b:placeAt(4, 3, "Brown")
        local groups = MatchDetector.findGroups(b)
        t.assertEq(#groups, 1)
        t.assertEq(#groups[1].cells, 5)
    end)
end)

t.summary()
```

- [ ] **Step 2: Run to verify failure**

```bash
lune run tests/MatchDetector.spec.luau
```

Expected: error about `MatchDetector` not found.

- [ ] **Step 3: Implement MatchDetector.lua**

```lua
-- src/ReplicatedStorage/Shared/Logic/MatchDetector.lua
local Constants = require("../Logic/Constants")
local PieceTypes = require("../PieceTypes")

local MatchDetector = {}

-- Returns a list of groups, each { color = string, cells = { {row, col}, ... } }
-- A group is connected via orthogonal adjacency of the same color, size >= MIN_MATCH_SIZE.
-- Garbage cubes never form groups.
function MatchDetector.findGroups(board)
    local visited = {}
    for r = 1, board.height do visited[r] = {} end

    local results = {}

    local function key(r, c) return r * 100 + c end

    for startRow = 1, board.height do
        for startCol = 1, board.width do
            local color = board:cellAt(startRow, startCol)
            if color and not PieceTypes.isGarbage(color) and not visited[startRow][startCol] then
                -- BFS
                local queue = { { startRow, startCol } }
                local cells = {}
                visited[startRow][startCol] = true
                while #queue > 0 do
                    local cur = table.remove(queue, 1)
                    table.insert(cells, cur)
                    local r, c = cur[1], cur[2]
                    local neighbors = { { r + 1, c }, { r - 1, c }, { r, c + 1 }, { r, c - 1 } }
                    for _, n in neighbors do
                        local nr, nc = n[1], n[2]
                        if nr >= 1 and nr <= board.height and nc >= 1 and nc <= board.width then
                            if not visited[nr][nc] and board:cellAt(nr, nc) == color then
                                visited[nr][nc] = true
                                table.insert(queue, { nr, nc })
                            end
                        end
                    end
                end
                if #cells >= Constants.MIN_MATCH_SIZE then
                    table.insert(results, { color = color, cells = cells })
                end
            end
        end
    end

    return results
end

return MatchDetector
```

- [ ] **Step 4: Run to verify pass**

```bash
lune run tests/MatchDetector.spec.luau
```

Expected: `8/8 passed (0 failed)`.

- [ ] **Step 5: Commit**

```bash
git add src/ReplicatedStorage/Shared/Logic/MatchDetector.lua tests/MatchDetector.spec.luau
git commit -m "Day 1: MatchDetector with BFS flood-fill + 8 scenarios passing"
git push
```

### Task 1.6: InputHandler.client.lua — keyboard input

**Files:**
- Create: `src/ReplicatedStorage/Shared/Events.lua` (event name registry, called from client)
- Create: `src/StarterPlayer/StarterPlayerScripts/InputHandler.client.lua`

- [ ] **Step 1: Write Events.lua (event name registry — placeholder for now, expand on Day 3)**

```lua
-- src/ReplicatedStorage/Shared/Events.lua
-- Event name + payload-shape registry. Single source of truth.
local Events = {}

Events.Names = {
    -- Client → Server (input)
    InputMove = "InputMove",     -- payload: { direction = "left" | "right" }
    InputRotate = "InputRotate", -- payload: { direction = "cw" | "ccw" }
    InputSoftDrop = "InputSoftDrop", -- payload: { held = boolean }
    InputHardDrop = "InputHardDrop", -- payload: {}

    -- Server → Client (state) — populated Day 3
    PieceLocked = "PieceLocked",
    ChainCompleted = "ChainCompleted",
    GarbageIncoming = "GarbageIncoming",
    GarbageApplied = "GarbageApplied",
    RoundEnd = "RoundEnd",
    MatchEnd = "MatchEnd",
}

return Events
```

- [ ] **Step 2: Write InputHandler.client.lua**

```lua
-- src/StarterPlayer/StarterPlayerScripts/InputHandler.client.lua
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage.Shared.Events)

local function getRemote(name)
    return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name)
end

local moveRemote = getRemote(Events.Names.InputMove)
local rotateRemote = getRemote(Events.Names.InputRotate)
local softDropRemote = getRemote(Events.Names.InputSoftDrop)
local hardDropRemote = getRemote(Events.Names.InputHardDrop)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
        moveRemote:FireServer({ direction = "left" })
    elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
        moveRemote:FireServer({ direction = "right" })
    elseif input.KeyCode == Enum.KeyCode.Z then
        rotateRemote:FireServer({ direction = "ccw" })
    elseif input.KeyCode == Enum.KeyCode.X then
        rotateRemote:FireServer({ direction = "cw" })
    elseif input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.S then
        softDropRemote:FireServer({ held = true })
    elseif input.KeyCode == Enum.KeyCode.Space then
        hardDropRemote:FireServer({})
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.S then
        softDropRemote:FireServer({ held = false })
    end
end)

print("InputHandler (keyboard) ready")
```

- [ ] **Step 3: Save and let Rojo sync — verify in Studio**

In Studio Output you should see `InputHandler (keyboard) ready` on Play. The Remotes folder won't exist yet, so you'll see `WaitForChild` blocking — that's fine; the print just won't fire. We'll add Remotes on Day 3.

- [ ] **Step 4: Commit**

```bash
git add src/ReplicatedStorage/Shared/Events.lua src/StarterPlayer/StarterPlayerScripts/InputHandler.client.lua
git commit -m "Day 1: Events registry + InputHandler keyboard controls"
git push
```

### Task 1.7: Touch controls (on-screen buttons)

**Files:**
- Create: `src/StarterPlayer/StarterPlayerScripts/TouchControls.client.lua`

- [ ] **Step 1: Write TouchControls.client.lua**

```lua
-- src/StarterPlayer/StarterPlayerScripts/TouchControls.client.lua
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Events = require(ReplicatedStorage.Shared.Events)

if not UserInputService.TouchEnabled then
    -- desktop; bail
    return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TouchControls"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local function safeAreaInset()
    -- GuiService:GetSafeZoneOffsets() returns inset rect; bottom inset is what matters here
    local _, bottomInset = GuiService:GetSafeZoneOffsets():Wait()
    return bottomInset or 0
end

local function makeButton(name, anchorX, sizePx)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Text = name
    btn.Size = UDim2.fromOffset(sizePx, sizePx)
    btn.Position = UDim2.new(anchorX, 0, 1, -sizePx - 20) -- 20 + safe-area gap
    btn.AnchorPoint = Vector2.new(0, 0)
    btn.BackgroundTransparency = 0.4
    btn.TextSize = 18
    btn.Parent = screenGui
    return btn
end

local SIZE = 64 -- comfortably above the 44pt minimum
local leftBtn   = makeButton("←", 0.05, SIZE)
local rightBtn  = makeButton("→", 0.20, SIZE)
local rotateCcw = makeButton("Z", 0.65, SIZE)
local rotateCw  = makeButton("X", 0.80, SIZE)
local hardBtn   = makeButton("⬇", 0.95, SIZE)

leftBtn.Position   = UDim2.new(0.05, 0, 1, -SIZE - 20)
rightBtn.Position  = UDim2.new(0.05, SIZE + 10, 1, -SIZE - 20)
rotateCcw.Position = UDim2.new(1, -2 * SIZE - 80, 1, -SIZE - 20)
rotateCw.Position  = UDim2.new(1, -SIZE - 70, 1, -SIZE - 20)
hardBtn.Position   = UDim2.new(0.45, -SIZE / 2, 1, -SIZE - 20)

local function getRemote(name)
    return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name)
end

local moveRemote     = getRemote(Events.Names.InputMove)
local rotateRemote   = getRemote(Events.Names.InputRotate)
local hardDropRemote = getRemote(Events.Names.InputHardDrop)

leftBtn.MouseButton1Click:Connect(function() moveRemote:FireServer({ direction = "left" }) end)
rightBtn.MouseButton1Click:Connect(function() moveRemote:FireServer({ direction = "right" }) end)
rotateCcw.MouseButton1Click:Connect(function() rotateRemote:FireServer({ direction = "ccw" }) end)
rotateCw.MouseButton1Click:Connect(function() rotateRemote:FireServer({ direction = "cw" }) end)
hardBtn.MouseButton1Click:Connect(function() hardDropRemote:FireServer({}) end)

print("TouchControls ready")
```

- [ ] **Step 2: Commit**

```bash
git add src/StarterPlayer/StarterPlayerScripts/TouchControls.client.lua
git commit -m "Day 1: TouchControls — on-screen buttons in thumb-reach zones, ≥44pt"
git push
```

### Task 1.8: Day-1 exit checkpoint

**Files:** none

- [ ] **Step 1: Smoke run all tests**

```bash
cd /Users/student/Documents/boba-drop
lune run tests/smoke.spec.luau
lune run tests/PieceTypes.spec.luau
lune run tests/Board.spec.luau
lune run tests/MatchDetector.spec.luau
```

Expected: every test file prints "X/X passed (0 failed)".

- [ ] **Step 2: Open Studio + Rojo serve, play, sanity-check**

- Rojo serve still running from earlier; if not: `rojo serve`
- Studio Play → no red errors in Output
- `InputHandler (keyboard) ready` prints
- On mobile testing pass-through (if Sarah can test on phone via Roblox app): touch controls appear in bottom corners

- [ ] **Step 3: Push final Day-1 commit if anything new**

```bash
git status
# if clean, no commit needed
git push
```

- [ ] **Step 4: Producer writes the daily log (via Slack reminder at 5:45pm PT)**

In `#boba-drop`, DM `@Producer`: "Write today's daily-log.md entry from git log + the day's Slack thread." Producer commits the entry.

**Day-1 exit gate:** Pieces can be defined and stacked logically (gravity test passes), MatchDetector finds all 8 scenarios correctly, input handlers are wired up (will activate on Day 3 when Remotes exist). Lune harness is solid for the harder Day-2 work.

---

(Days 2–4 follow in subsequent sections of this document — see "Day 2", "Day 3", "Day 4" below. Same structure: TDD where applicable, full code in every step, exact commands, commit at the end of each task.)
