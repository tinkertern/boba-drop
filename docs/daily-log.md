# Boba Drop — Daily Log

Build window: Tue 2026-05-19 → Fri 2026-05-22.

---

## 2026-05-19 (Day 1, Tue)

A long, productive Day 1. Day 1 closed early enough that we pulled the first three Day 2 logic tasks plus two Producer Day 2 scaffolds in the same session. We are running ahead of the plan, not behind.

### Shipped

*Engineer lane:*
- Lune test harness with describe/it/assertEq helpers
- `Constants`, `PieceTypes` (dot counts + shape fallbacks), `Board` (bag RNG with `peek/advance`, `gravitySettle`), `MatchDetector` (BFS flood-fill)
- `Events` name + payload registry
- `InputHandler` keyboard, `TouchControls` for mobile
- Day 0 sanity scaffolding deleted (`HelloTest`, `Hello.lua`)
- Day 2 pulled forward: `Scoring` (pure formula), `ChainResolver` (synchronous pop + gravity + match loop, 7 scenarios), `GameState` (state machine, scores, pub/sub, forfeit, draw)
- ChainResolver test fixture redesigned after TDD caught a flaw in the plan's literal setup; implementation ships exactly as specified

*Producer lane:*
- `UIConstants.lua` initial draft, then full overhaul to the cozy art direction Sarah codified mid-day
- `ChainCounter.client.lua` (bounce-in tween, peach to coral gradient)
- `ScoreDisplay.client.lua` scaffold reading `payload.scoreAdded` (server-authoritative)
- `Lobby.client.lua` tutorial card with DataStore-persisted dismiss
- `BoardPlaceholder.client.lua` (2D `ScreenGui` grid, aspect-locked) replacing a misguided initial 3D Workspace attempt
- `TutorialState.server.lua` owning the DataStore writes, client reads via `Player:GetAttribute`
- `GamePasses.lua` module class (Day 2 pull-forward) and `MatchEnd.client.lua` visual placeholder (Day 2 pull-forward)
- All UI restyled to FredokaOne via the new `FontFace` API

*Tests:* 42/42 passing across 7 Lune spec files at EOD.

### Decisions

- Score is server-authoritative. `ChainCompleted` payload will carry a canonical `scoreAdded` computed via `Scoring.compute` on the server; no separate `ScoreUpdate` Remote.
- Boba Drop is a 2D `ScreenGui` game. No gameplay content lives in `Workspace` as 3D parts.
- Visual direction: warm, bubbly, cozy. Cream / peach / mint pastels, warm dark text instead of pure black, rounded corners everywhere, `EasingStyle.Back` `EasingDirection.Out` with slight overshoot, FredokaOne for display copy, soft chime feedback (Day 3+).
- All visual constants live in `UIConstants.lua`. Consumer files reference, never hardcode. Tones iterate by changing one constant.
- DataStore access is server-only. Client UI proxies persisted state through `Player:SetAttribute` reads and `RemoteEvent` writes.
- Monetization is a single Game Pass (one-time cosmetic unlock), priced at 99 Robux. Premium Themes Pack name confirmed.

### Blockers

- Premium Themes Pack Game Pass ID is pending Sarah's creation on create.roblox.com. `GamePasses.PREMIUM_THEMES_PACK_ID = 0` placeholder short-circuits the live `UserOwnsGamePassAsync` until the real ID lands. No engineering impact.

### Tomorrow (Day 2, Wed 2026-05-20)

- Engineer: Day 3 networking (`Main.server.lua`, `RoomManager`, `StateSync`, `DisconnectHandler`, `Remotes/*.model.json`) when Sarah gives the word. Boss fight already finished early.
- Producer: respond to Sarah's tone feedback on the art direction, pull forward `GarbagePreview` and `CounterCancel` visual scaffolds, wire the Game Pass ID into `GamePasses.lua` once Sarah creates the Pass, drop in the Shop modal placeholder.
