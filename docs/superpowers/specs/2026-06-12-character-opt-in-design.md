# Character Opt-In (Eligibility Rework) — Design

**Date:** 2026-06-12
**Status:** Approved design, pending implementation plan

## Context

Today `Scanner:Scan()` writes **every** character it runs on to the account cache
(`chars[key] = entry`, Scanner.lua:90), and `Derived.observeEligibility` marks a
character "eligible" the moment its vault period is "not untouched" — i.e. **any
tier with progress > 0** (Derived.lua:78). World quests and special assignments
trivially fill world tier 1, so any character you briefly log into gets counted,
and a low-effort alt (an M+2, a few world quests) pollutes the roster even though
you have no intention of pushing its vault.

We are replacing that with an **opt-in model**: a character only enters the DB once
it crosses two gates that signal "I'm actually playing this character for vault
rewards." This keeps the cache to characters worth tracking.

## The model

A character is **tracked** (persisted, counted, shown) once it satisfies **both**,
on any scan (login / `WEEKLY_REWARDS_UPDATE` / periodic). Opt-in is **sticky** —
once tracked, it stays tracked until auto-pruned for staleness.

1. **Level floor.** Character level ≥ a configurable minimum (`minLevel`), default =
   the current expansion max level read from the API. Excludes leveling alts
   outright, regardless of world-quest progress.
2. **Reward-ilvl bar.** The character has **earned** a vault reward whose item level
   is **strictly above** an ilvl bar (below).

Both gates must hold. Sub-floor characters never qualify; max-level characters that
only do trivial content never clear the bar.

### The ilvl bar: auto-derived default + manual raise

- **Auto baseline.** The season's **world-track tier-1 reward ilvl**, observed from
  the API and cached account-wide in `db.global` (`worldTier1Ilvl`), refreshed on
  every scan whenever a character has earned world tier 1. It self-updates each
  season. Until first observed this season, the baseline is unknown (0) and the bar
  falls back to "track all above the level floor," then corrects on first
  observation. The baseline cache updates **independently of whether the scanning
  character is itself tracked** (we always read the vault; we only gate persistence).
- **Manual raise.** A config value `trackBarOverride` (default 0 = auto) lets the user
  raise the bar above the auto baseline — e.g. above an M+2 reward — for a personal
  "don't care below this" line. The **effective bar = max(worldTier1Ilvl,
  trackBarOverride)**. Set the override back to 0 to return to pure auto.
- World-quest noise is excluded out of the box (auto baseline). Excluding low M+ like
  an M+2 alt is a deliberate manual raise, since M+2 is real dungeon content whose
  reward sits above world tier 1.

### Opt-in evaluation (pure)

A new pure function in `Derived` (unit-tested):

```
Derived.qualifies(level, minLevel, maxEarnedRewardIlvl, effectiveBar)
  -> level >= minLevel and maxEarnedRewardIlvl > effectiveBar
```

`maxEarnedRewardIlvl` = the max `rewardIlvl` across all earned slots of the current
period (0 if none earned). Stickiness wraps it:

```
Derived.observeTracked(prevTracked, level, minLevel, maxEarnedIlvl, bar)
  -> prevTracked or Derived.qualifies(...)
```

This **replaces** `Derived.observeEligibility` and the `entry.eligible` /
`entry.eligibleAt` fields (renamed to `entry.tracked` / `entry.trackedAt`).

## Changes by file

- **Scanner.lua** — after reading the period: (a) update `db.global.worldTier1Ilvl`
  from the world track's tier-1 earned reward ilvl; (b) compute `tracked` via
  `Derived.observeTracked` using `UnitLevel("player")`, the resolved level floor, the
  period's max earned reward ilvl, and the effective bar; (c) **only** `chars[key] =
  entry` when `tracked` (newly or already). Untracked characters are scanned (to feed
  the baseline) but not persisted.
- **Derived.lua** — add `qualifies` + `observeTracked` + a `maxEarnedIlvl(period)`
  helper; remove `observeEligibility`.
- **Config.lua** — two new options (localized): a level-floor input (`minLevel`, 0 =
  auto/max level) and a reward-ilvl raise (`trackBarOverride`, 0 = auto). Add defaults
  to `Config.defaults.global.settings`. Resolve the max-level default at runtime via
  the API.
- **Roster.lua** — every stored character is now tracked, so the dimmed "ineligible"
  styling and the `ROSTER_INELIGIBLE` tooltip line are removed (desaturation,
  grey name/ilvl, the `dim` branch). Attention glow still drives per-week urgency.
- **Locales/enUS.lua** — add option name/desc keys for the two settings; remove
  `ROSTER_INELIGIBLE`.
- **Attention.lua** — review: it now only ever sees tracked characters (untracked are
  never stored). Confirm no eligibility assumptions break; keep tests green.

## Config (new settings)

| Key | Type | Default | Meaning |
|---|---|---|---|
| `minLevel` | number | 0 (= current max level) | Level floor; below this a character is never tracked. |
| `trackBarOverride` | number | 0 (= auto) | Raises the reward-ilvl bar above the auto world-T1 baseline. |
| `worldTier1Ilvl` (in `db.global`, not a setting) | number | 0 | Cached season baseline; internal, refreshed on scan. |

## Migration

Characters already in the cache were added under the old "any progress" rule. Any
character already persisted is **grandfathered as `tracked = true`** on upgrade
(one-time migration over `db.global.characters`, also dropping the old `eligible` /
`eligibleAt` fields). The user's current cache holds only intended max-level
characters, so grandfathering is safe; `Clear cache` resets if desired.

## Open verification (in-game, no headless WoW)

- **Max-level API:** confirm `GetMaxLevelForPlayerExpansion()` (or the correct
  current call) returns the expansion cap; use it for the `minLevel` auto default.
- **World tier-1 reward ilvl:** confirm the world track's lowest tier exposes a
  readable `rewardIlvl` once earned (it should, via the existing
  `GetExampleRewardItemHyperlinks` → `GetDetailedItemLevelInfo` path).
- **Optional:** whether `GetExampleRewardItemHyperlinks` returns an ilvl for the
  *unearned* world-T1 slot (would let a fresh character derive the baseline without
  the account-wide cache). Not required — the cache covers it.

## Verification plan

- `lua tests/run.lua` — add unit tests for `qualifies` / `observeTracked` /
  `maxEarnedIlvl` (floor boundary, bar boundary strict-greater, stickiness,
  unknown-baseline fallback). Update/remove `observeEligibility` tests. Keep all green.
- `lua -e "assert(loadfile('X.lua'))"` on touched files.
- In-game `/reload`: only intended max-level characters appear; a world-quest-only
  alt does not get added; raising the ilvl bar drops a low-M+ alt; lowering to auto
  brings back the world-T1 baseline behavior. No dimmed rows remain.

## Out of scope

Per-character manual include/ignore toggle (the deferred per-character controls) —
the override here is a single account-wide ilvl bar, not a per-character list. Manual
per-character control stays queued.
