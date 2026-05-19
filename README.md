# 🍡 Boba Drop

A 1v1 Puyo-Puyo-style falling-block duel on Roblox. Match 4+ same-color boba pearls to pop them, chain reactions to send ice-cube garbage to your opponent's cup. First to overflow loses. Best of 3.

**Status:** in development (Tue 2026-05-19 → Fri 2026-05-22)
**Spec:** see [`docs/design.md`](docs/design.md)
**Built by:** Sarah Yoon, paired with two AI assistants on Slack (`@Game Engineer` and `@Producer`).

## Dev setup

1. Install [Roblox Studio](https://create.roblox.com)
2. Install [Rojo](https://rojo.space): `brew install rojo`
3. Install the Rojo plugin inside Studio
4. From repo root, run `rojo serve` and connect from the Studio plugin
5. Open the empty Place file in Studio; code from `src/` will sync live

## Project layout

```
src/
  ServerScriptService/   server-authoritative game logic + networking
  ReplicatedStorage/     shared data (constants, piece types, event names)
  StarterPlayer/         client input handler
  StarterGui/            lobby, in-game UI, shop UI
docs/
  design.md              full design spec
  daily-log.md           Producer bot's daily progress notes
```
