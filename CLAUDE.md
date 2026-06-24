# VaultTracker — working notes

A World of Warcraft **retail** addon: a Great Vault nudge tracker (minimap badge + tooltip, roster window, account-wide cache). Durable, non-code context for new sessions. Design detail lives in `VaultTracker-spec.md` (data layer) and `docs/superpowers/specs/` + `docs/superpowers/plans/`.

## How to work here
- **Discuss before implementing.** When the user asks a *question*, answer/discuss it — don't jump to editing. Implementation follows agreement.
- **Never guess — verify.** WoW API names, atlas/icon paths, AceConfig widths, library APIs: confirm against the API wiki, vendored library source, or the running game. If it can't be verified, say so. Several bugs came from guessed names.
- **The user directs commits and releases** — don't self-initiate; commit/tag/publish on their say-so.
- **Dev/live split.** Repo lives at `~/projects/VaultTracker`. Deploy to the live game folder (`/Applications/World of Warcraft/_retail_/Interface/AddOns/VaultTracker`) with `./deploy.sh` (rsync; preserves the live `Libs/`), then the user `/reload`s.
- **No headless WoW.** `lua tests/run.lua` (pure-logic units) and `lua -e "assert(loadfile('X.lua'))"` (syntax); `lua` is at `/opt/homebrew/bin/lua`. Everything visual/behavioral is confirmed by the user `/reload`-ing and screenshotting.
- **Tone:** terse, direct, no sycophancy. The user reviews UI wording/grammar closely — prefer proper, concise English in labels.

## Project state
- **Released.** On `main`, pushed to `github.com/whatisboom/VaultTracker`, published to CurseForge (project `1572774`). Current tag **v0.2.2**.
- Interface version **120007** (WoW 12.0.7).
- **Libs vendored on disk** under `Libs/` but gitignored (only `Libs/embeds.xml` is tracked); fetched and embedded at build time via `.pkgmeta` `externals` — never committed, by design.
- Pure logic (`Derived`, `Attention`, `Format`) is TDD'd — **91 tests**; keep them green.

## Build & release
- **Tag-driven.** Pushing a `vX.Y.Z` tag fires a GitHub webhook → CurseForge packages server-side (BigWigs packager reads `.pkgmeta`, substitutes `@project-version@`). Tag name sets the channel (no "alpha"/"beta" ⇒ release). The project builds on **tags only**, so untagged pushes don't publish.
- `.pkgmeta` `ignore` keeps dev files out of the package (`docs`, `tests`, `CLAUDE.md`, `VaultTracker-spec.md`, `deploy.sh`); dotfiles are auto-pruned by the packager.
- **No API for the CurseForge description/About page** — that's a manual web edit.

## Decisions & gotchas (not obvious from code)
- **Eligibility = "seriousness", and it's STICKY (opt-in; presence in the DB is the source of truth).** A character becomes tracked the first time it earns a reward whose tier ≥ the effective line (`entry.trackTier` per-character, else the account `seriousness` default; Veteran<Champion<Hero<Myth), and **stays tracked** thereafter — stored as `entry.eligible`, set by `Derived.observeEligible` in Scanner, read by `Derived.effectiveTracked` (which no longer recomputes live). Reset only on M+ **season** change (re-earn after a rollover) or by wiping SavedVariables. Changing the account threshold does **not** auto-drop characters — it prompts "Reset / Keep". A per-character override change re-evaluates that one character immediately. The tier is read from each reward's tooltip `ItemUpgradeLevel` line (`Enum.TooltipDataLineType.ItemUpgradeLevel == 32`), locale-safe via the tier-name locale strings — no content→tier tables.
- **Confirmed banked loot ignores eligibility** — any character with `hasPendingLoot` surfaces it (chat/tooltip/roster, red) regardless of tracked state; only an explicit `trackTier == "off"` mutes it. The inferred/soft reasons (likely-banked, untouched, close-to-unlock) still require eligibility.
- **Vault events:** `PLAYER_ENTERING_WORLD`, `WEEKLY_REWARDS_UPDATE`, `WEEKLY_REWARDS_ITEM_CHANGED`. `WEEKLY_REWARDS_SHOW` is **not** registerable on 12.x.
- **Reward data loads async** — hyperlinks/item info aren't ready when the event fires, so `OnVaultEvent` re-scans at +2s and +5s to resolve earned-slot ilvls/tiers.
- **Reward ilvls/tiers are read from the API, never computed** (`GetExampleRewardItemHyperlinks` → `GetDetailedItemLevelInfo`; tier from the tooltip line). No "key level → ilvl" tables.
- **Sounds use LibSharedMedia**, not engine `SOUNDKIT` (SOUNDKIT names are partly unverifiable — caused silent options).
- **World `level` meaning is unverified.** Raid uses `raidString` (rendered as "Defeat N … Bosses" by filling its `%d` with the slot threshold); world slots show no source label until confirmed in-game.
- Each character scans only itself (the API exposes only the logged-in char); other rows come from the account-wide cache and update when you log into them.

## Deferred / queued
- **Track-header icons** (Raid/Dungeon/World) — pending verified Great Vault atlas names (`GetAtlasInfo`-confirmed, text fallback).
- **World slot source label** — once `level`'s meaning is confirmed.
- **"Potential ilvl" for unearned slots** — would need the reward-cap curve; explicitly not built.
