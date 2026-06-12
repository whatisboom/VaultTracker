# VaultTracker — working notes

A World of Warcraft **retail** addon: a Great Vault nudge tracker (minimap badge + tooltip, roster window, account-wide cache). This file is durable, non-code context for new sessions. Design detail lives in `VaultTracker-spec.md` (data layer) and `docs/superpowers/specs/` + `docs/superpowers/plans/`.

## How to work here
- **Discuss before implementing.** When the user asks a *question*, answer/discuss it — do not jump straight to editing files. Implementation follows agreement, not questions. (This was a repeated friction point.)
- **Never guess — verify.** WoW API names, `SOUNDKIT`/atlas/icon paths, AceConfig widths, library APIs: confirm against the API wiki, the vendored library source, or the running game before using. If it can't be verified, say so rather than guess. Several bugs came from guessed constant/path names.
- **Don't commit unless asked.** Iterative "get it working" phase — make changes on disk; the user stages/commits.
- **No headless WoW.** Verify with `lua tests/run.lua` (pure-logic unit tests) and `lua -e "assert(loadfile('X.lua'))"` (syntax). Everything visual/behavioral is confirmed by the user `/reload`-ing and screenshotting. `lua` is at `/opt/homebrew/bin/lua`.
- **Tone:** terse, direct, no sycophancy. The user reviews wording/grammar closely and prefers proper, concise English in UI labels.

## Project state (last session)
- **Nothing committed.** Local git repo, branch `feature/nudge-system`.
- **Libraries vendored under `Libs/`** (Ace3, LibDataBroker-1.1, LibDBIcon-1.0, LibSharedMedia-3.0) from canonical GitHub mirrors — **uncommitted**; the user vets supply-chain sources before committing.
- Retail interface version is **120005** (patch 12.x).
- Pure logic (`Derived`, `Attention`, `Format`) is TDD'd — 66 tests; keep them green.

## Decisions & gotchas (not obvious from code)
- **Vault events:** `PLAYER_ENTERING_WORLD`, `WEEKLY_REWARDS_UPDATE`, `WEEKLY_REWARDS_ITEM_CHANGED`. `WEEKLY_REWARDS_SHOW` is **not** a registerable event on 12.x.
- **Reward data loads async** — example hyperlinks / item info aren't ready the instant the event fires, so Core re-scans at +2s and +5s to resolve earned-slot ilvls.
- **Sounds use LibSharedMedia**, not engine `SOUNDKIT` (SOUNDKIT is a curated, partly-unverifiable name set — caused silent options).
- **Reward ilvls are read from the API, never computed** (`GetExampleRewardItemHyperlinks` → `GetDetailedItemLevelInfo`). No "key level → ilvl" tables, so the M+ reward cap (e.g. +10) needs no handling on our side. Tooltips matched the live vault exactly when verified.
- **World `level` meaning is unverified.** Dungeon `level` = M+ keystone; raid uses `raidString`; world slots intentionally show no source label until confirmed in-game.
- Each character scans only itself (API exposes the logged-in char only); other rows come from the account-wide cache and update when you log into them.

## Deferred / queued
- **Per-character control** options (mute / remove / override eligibility) — its own brainstorm conversation, explicitly split out.
- **Track-header icons** (Raid/Dungeon/World) — pending verified Great Vault atlas names (`GetAtlasInfo`-confirmed, text fallback).
- **World slot source label** — once `level`'s meaning is confirmed.
- **"Potential ilvl" for unearned slots** — the only feature that would need the reward-cap curve; explicitly not built.
