# 🍡 Boba Drop

A cozy 1v1 falling-block duel on Roblox. Match 4+ same-color boba pearls to pop them, chain reactions to send ice-cube garbage to your opponent's cup. First to overflow loses.

<!-- gameplay-clip placeholder; filled in after Friday capture -->
<!-- [gameplay clip: 30s of chains, garbage exchange, counter cancel] -->

> Built in 4 days (Tue 2026-05-19 → Fri 2026-05-22) as a portfolio piece, paired with two AI assistants on Slack: `@Game Engineer` (gameplay logic, networking, server authority) and `@Producer` (UI, UX, monetization, polish, schedule).

**Tech:** Roblox · Luau · Rojo · Lune · MarketplaceService · GitHub
**Play:** _coming Friday_ · **Spec:** [`docs/design.md`](docs/design.md) · **Daily log:** [`docs/daily-log.md`](docs/daily-log.md) · **Publish notes:** [`docs/publish-prep.md`](docs/publish-prep.md)

---

## Why it's interesting

- *Server-authoritative state.* The board, scores, and chain resolution all live in pure Luau modules with zero Roblox runtime dependencies, so they're testable from the CLI via Lune before they ever touch a Studio session.
- *Pure-function game logic.* `Board`, `MatchDetector`, `ChainResolver`, and `Scoring` are written so a unit test can simulate a full 4-chain pop in milliseconds. The chain resolver is bulletproofed against 7 scenarios (single pops, multi-color resolves, bottom-row chains, empty-field results) before networking touches it.
- *Mobile-first UI.* Built thumb-reach first; everything reads at 414×896 (iPhone 14 portrait). Cozy pastel palette, FredokaOne display font, Back/Out easing on every interactive element.
- *Real Game Pass monetization.* One cosmetic Game Pass (Premium Themes Pack: Brown Sugar Boba, Strawberry Milk, Matcha) with cached ownership, filtered purchase listener, and a self-purchase test on launch day.
- *AI-paired build.* Two specialized Claude bots (engineer + producer) collaborate via Slack with non-overlapping folder ownership, daily exit gates, and a cut ladder that activates if a milestone slips.

---

## Architecture

```
src/
  ReplicatedStorage/
    Shared/
      Logic/                 pure Luau (no Roblox deps, Lune-testable)
        Constants.lua        board dims, garbage table, timings
        Board.lua            grid + bag RNG + gravity + peek(n)
        MatchDetector.lua    BFS flood-fill for 4+ groups
        ChainResolver.lua    synchronous pop → gravity → match loop
        Scoring.lua          pure scoring formula
        GameState.lua        round/match state machine + scores
      UI/UIConstants.lua     colors, fonts, durations, z-order tokens
      Events.lua             event names + payload-shape contracts
    Remotes/                 12 RemoteEvents as Rojo .model.json
  ServerScriptService/
    Main.server.lua          bootstrap
    Networking/
      RoomManager.lua        session lifecycle, matchmaking, rematch
      StateSync.lua          GameState pub/sub → RemoteEvent fanout
      DisconnectHandler.lua  phase-aware in-round vs post-match routing
    Monetization/
      GamePasses.lua         cached ownership + filtered purchase listener
  StarterPlayer/
    StarterPlayerScripts/
      InputHandler.client.lua  keyboard + touch → RemoteEvents
  StarterGui/
    Backdrop/                full-screen warm cream backdrop
    Audio/                   ambient music playlist (cycles 4 tracks)
    MainMenu/                title, PLAY, Themes, Settings, How-to-play, drifting pearls
    Lobby/                   queue pill while matching (slides up from below)
    GameUI/                  Board, Score, ChainCounter, GarbagePreview, NextPiecePreview, OpponentBoard, CounterCancel
    HowToPlay/               in-match `?` overlay (controls / goal / tips)
    Settings/                music + SFX volume sliders, music toggle
    Shop/                    Premium Themes Pack modal
    MatchEnd/                results screen + rematch flow
    PauseConfirm/            in-match LEAVE pill + confirm modal
    CountdownOverlay/        3-2-1-GO! round-start scrim
    UIStateController.client.lua  drives ScreenGui.Enabled per GameState

tests/                       Lune-runnable .spec.lua files
docs/
  design.md                  multi-role-reviewed design spec
  2026-05-19-implementation-plan.md  task-by-task build plan
  daily-log.md               daily progress notes
  publish-prep.md            Roblox listing copy + asset specs
```

### Key invariants

- *No Roblox deps in `Shared/Logic/`.* Anything that imports a Roblox service goes elsewhere. This is what makes the Lune test harness possible.
- *Single writer per state slice.* `GameState` is the sole writer for round/match state and scores. `RoomManager` is the sole writer for session/lobby state. No other module mutates these.
- *Client never decides correctness.* Inputs flow Client → RemoteEvent → Server (RoomManager → GameState). Server fires authoritative events back. The client never simulates the board.
- *UI state is server-driven.* `UIStateController` reads `player:GetAttribute("GameState")` and toggles `ScreenGui.Enabled`. The server is the sole writer for that attribute.

---

## How it was built

Two AI assistants run as Slack bots with non-overlapping folder ownership:

- *@Game Engineer* owns `src/ReplicatedStorage/Shared/Logic/`, `src/ServerScriptService/Networking/`, `src/StarterPlayer/`, and the test harness in `tests/`. They write the gameplay rules, networking, and disconnect handling.
- *@Producer* owns `src/StarterGui/`, `src/ServerScriptService/Monetization/`, and `src/ReplicatedStorage/Shared/UI/`. They own player-facing UI/UX, the Game Pass flow, polish, schedule discipline, and daily logs.

Sarah operates Roblox Studio directly (scene assembly, Game Pass creation, publishing) and decides scope and direction in Slack. The bots write Luau, commit, and push from disk; Rojo syncs `src/` into the live Studio session.

The sprint plan, exit gates, and cut ladder are tracked in [`docs/2026-05-19-implementation-plan.md`](docs/2026-05-19-implementation-plan.md). Daily progress is in [`docs/daily-log.md`](docs/daily-log.md).

---

## Dev setup

1. Install [Roblox Studio](https://create.roblox.com)
2. Install [Rojo](https://rojo.space): `brew install rojo`
3. Install the Rojo plugin inside Studio (`rojo plugin install`)
4. Install [Lune](https://lune-org.github.io/docs) for CLI tests: `brew install lune`
5. From repo root, run `rojo serve`, then connect from the Studio plugin
6. Open the empty Place file in Studio; code from `src/` syncs live

Run pure-logic tests from the CLI:

```bash
lune run tests/<file>.spec.lua
```

---

## Status

- [x] Day 1: skeleton + Lune test harness + UI scaffold
- [x] Day 2: chain resolver + scoring + GameState + chain counter UI
- [x] Day 3: networking + 1v1 matchmaking + disconnect handling + lobby UI
- [ ] Day 4: gameplay tick + screen state routing + publish + portfolio polish

Definition of shipped (binary, testable Sat 2026-05-23, per [`docs/design.md`](docs/design.md) §1):

- [ ] Public Roblox URL
- [x] Public GitHub repo with full README
- [ ] 30-60s gameplay clip showing a 4-chain pop, garbage exchange, and counter cancellation
- [ ] Premium Themes Pack Game Pass listed, with one end-to-end test purchase completed

---

## Credits

Designed and operated by Sarah Yoon. Engineering pair: Claude Opus 4.7, partitioned into two specialized agents (Engineer + Producer) communicating via a custom Slack MCP bridge.
