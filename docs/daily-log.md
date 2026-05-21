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

---

## 2026-05-20 (Day 2, Wed)

The day the game became a game. Networking + gameplay tick + a real board renderer landed in the morning; eleven layered polish items (D.1 + D.2 rows) shipped in the evening; Sarah ran multiple playtest cycles in between and we cleared a chain of marshalling bugs that made the board feel correct end-to-end. Closed the day with a 11-item scope extension doc plus publish-prep boilerplate, well-positioned for a Thursday polish pass and a Friday ship.

### Shipped

*Engineer lane:*
- Networking foundation: `Main.server.lua`, `RoomManager` (room lifecycle + matchmaking), `StateSync` (server-to-client event bus), `DisconnectHandler`
- Server gameplay tick: active piece state, input handling, lock to resolve to garbage drop loop (`e7f4df2`, `0a2a6ef`)
- `GameState` player attribute writes for screen state routing (`a1f412d`)
- `ActivePieceUpdate` event + dense board snapshots on `PieceLocked` / `ChainCompleted` (`11a0eea`)
- Race-fix: `RoomManager:onRoomReady` synchronous callback so `StateSync` subscribes before `gs:startRound()` (`2faeed7`)
- Dense board snapshots (`false` for empty cells) so Roblox's `#`-truncation can't drop sparse rows (`393b098`)
- `RoundStartCountdown` event + `ChainCompleted.garbageOut` field + 3s `_startRoom` delay (`a6c4fc0`)
- Neighbour-clear garbage rule: cubes adjacent to a popping color group are cleared (`0f55c5d`)
- Single-round match (`ROUNDS_TO_WIN` 2 to 1), every-chain-sends-garbage table tuned (`9f4ea20`, `bc5eb56`)
- Match-end payload enriched: scores, best chain, winner, loser (`7d61381`)

*Producer lane:*
- Premium Themes Pack Game Pass live at ID `1846258540`, 99 Robux; wired into `GamePasses` + `Shop`
- Shop modal complete: 3 theme cards, body description with theme-colored names, Buy + Close buttons
- Backdrop tone shifted to warm buttercream `#FAE2C0` after cream surfaces vanished against the original cream backdrop (`5dbbf50`)
- Tier-1 polish pass on Sarah's first screenshot critique: board cell visibility, tutorial / queue overlap, Themes enable affordance, Shop Buy accent (`f779647`)
- Round-2 critique pass: queue refactored to bottom-anchored pill, shop scrim warmed, tutorial verb recolored, Cancel changed to burnt-tan (`a37e530`)
- Text variety pass with RichText + strokes (`d970d6d`, `7e37128`)
- `UIStateController.client.lua` for screen routing across `lobby` / `matching` / `in_match` / `match_end` (`2576d49`)
- Rojo Folder vs ScreenGui name-collision fix (`daabb41`): iterate `GetChildren()` filtered by `IsA("ScreenGui")` instead of `FindFirstChild(name)`
- Real board renderer: `BoardPlaceholder` rebuilt as `ActivePieceUpdate` / `PieceLocked` / `ChainCompleted` subscriber (`109f124`, `e81489a`)
- Three-fix marshalling chain for sparse 2D tables (`9d4d910`, `0cfb1cc`, `1a6299d`, `f61c781`): separated locked / active pearl pools, string-key dictionary lookups, additive-snapshot renderer, post-chain gravity reconcile
- Critical polish row (D.1, six commits parallel): NEXT pill preview (`e4485ce`), A2 + A3 chain pop animation + lock squish (`17b7d2d`), A11 floating N-CHAIN! label (`71244e5`), C.3 PauseConfirm modal (`689e259`), A6 MatchEnd full rewrite (`57ce523`)
- Strong-feel polish row (D.2, four parallel): A4 + A5 + A8 smooth fall + drop ghost + danger row pulse (`878f595`, partial revert at `25f9d27`), A7 OpponentBoard mini-view (`19ffab7`), C.4 CountdownOverlay 3-2-1-GO! (`9d73dc5`), C.2 HowToPlay overlay (`efe7558`)
- Garbage attacker-side floating "to N ICE!" text + visual neighbour-clear animation + falling cubes from top (`7903c3f`, `188f2f4`, `031014f`)
- Disappear-reappear bug killed end-to-end with Engineer's dense snapshot
- README portfolio polish + `publish-prep.md` Roblox listing copy / asset specs / clip plan (`ad150b5`, `5b83d4e`)
- 11-item scope extension doc (`be5e039`) with 6 critical + 4 polish + 3 cozy items, file paths, animation timing, sound specs, owner, estimates

*Tests:* 59/59 Lune green at EOD across server logic and gameplay rules.

### Decisions

- Best-of-1 instead of multi-round. `ROUNDS_TO_WIN = 1` keeps the gameplay loop short and tight for the cozy mobile target.
- Every chain sends garbage. Garbage table tuned so even a 4-pop nudges the opponent's cup.
- Neighbour-clear rule on chain pops. Garbage cubes adjacent to popping color groups are cleared, rewarding deeper chain play.
- A4 smooth-fall tween reverted within the same day after Sarah caught invisible active pearls. Deferred to v1.1 with a reparent-safe approach.
- Renderer is additive from server snapshots. Cells absent from a snapshot are NOT destroyed by default; only `cellsPopped` (per step) drives destructive paints. Gravity-settle uses `reconcileLockedToSnapshot` against the post-chain snapshot.
- Pre-piece preview shipped at the top-right of the HUD, not as a separate prep stage. Two upcoming pairs visible, refresh-fades on update.
- HowToPlay opens via the in-match `?` pill, not as a forced first-time tutorial. Teaching happens through play.
- Pause modal asks Stay / Leave, not Resume / Quit. We don't actually pause gameplay; this is a confirm dialog for leaving a live match.

### Blockers

- Floating-pearl bug on PieceLocked: traced to Roblox marshalling sparse int-keyed tables as string-keyed dictionaries. Resolved end-of-day with the dense-snapshot + additive-renderer pair.
- Empty board on 2-client local test: race between `StateSync:_attachToRooms` polling and `gs:startRound()` firing. Resolved by `onRoomReady` callback.

### Tomorrow (Day 3, Thu 2026-05-21)

- Engineer: D.3 server hooks if needed for the Producer cozy row; otherwise on-call for any playtest bugs Sarah surfaces.
- Producer: cozy row (D.3) — A9 ambient music, A10 score count-up, C.1 settings panel — plus any iterative polish Sarah calls out. Daily-log Day 2 catchup. Code inspection pass for v1.1 deferrals.
