# Seriousness-Based Opt-In (Eligibility v2) — Design

**Date:** 2026-06-13
**Status:** Approved design, pending implementation plan
**Supersedes:** the eligibility mechanism in
[`2026-06-12-character-opt-in-design.md`](./2026-06-12-character-opt-in-design.md)
(reward-ilvl bar). See "Relationship to the prior spec" below.

## Context

Today `Derived.observeEligibility` (Derived.lua:78) marks a character "eligible" the
moment **any tier in any track** has progress > 0, sticky for the season. World tier 1
is trivially filled (a world quest, a single delve), so every alt you briefly play
leaks into the roster and the nudges. There is **no eligibility control in the options
panel at all**, and the user has many alts they don't want to hear about.

We want a character to register only once it earns rewards the user actually cares
about, expressed in the game's own language — the **reward gear tier** — with a single
"seriousness" default and a per-character line for the cases that vary.

## The seriousness axis: reward gear tier

The Great Vault rewards on every track resolve to one of four upgrade-track tiers:

```
Veteran (1)  <  Champion (2)  <  Hero (3)  <  Myth (4)
```

This is the one currency shared by all three tracks. Raid spans the full range
(LFR→Veteran, Normal→Champion, Heroic→Hero, Mythic→Myth); delves fill the lower rungs;
dungeons ladder up through the middle and top. So **a character's "seriousness" is the
best reward tier it has actually earned**, and the gate is simply *best earned tier ≥
the line*. World tier 1 (Veteran) falls below the default line on its own, so trivial
world activity never opts a character in — without any track-specific special-casing.

### Reading the tier (verified 2026-06-13, in-game)

Confirmed: a reward's tooltip carries a line `Upgrade Level: <Tier> <x>/<y>` (observed
`Upgrade Level: Veteran 1/6` on a world reward at item level 233 — which also confirms
**world tier 1 = Veteran**, below the Champion default, exactly as the model predicts).
So the tier is readable from the reward for **every earned slot, all three tracks**,
alongside the ilvl we already pull via `GetExampleRewardItemHyperlinks`. All tracks
(including world/delve) participate uniformly — **no deferred world work**.

Extraction must be **locale-safe** (the line text is localized). At implementation,
locate the upgrade line without parsing English — via the `C_TooltipInfo` line `type`
(`Enum.TooltipDataLineType`) or the game's upgrade-tooltip format global string — and
map the tier name to its ordinal through addon locale strings (four names:
Veteran/Champion/Hero/Myth), which we already maintain via AceLocale. See Open
Verification. The earlier-tried `TooltipUtil.SurfaceArgs` was nil in this client; a
hidden `GameTooltip:SetHyperlink` scan reads the lines reliably as a fallback to
`C_TooltipInfo`.

## The model

A character is **tracked** (counted in attention, shown in the default roster) when
**both** hold, evaluated live on every scan/refresh:

1. **Max-level persistence gate.** A character is written to the cache only while at the
   current expansion max level (`UnitLevel("player") >= GetMaxLevelForPlayerExpansion()`).
   This is a *persistence* gate applied at scan time, **not** a per-row display gate — a
   sub-cap character is never stored, so the roster/attention/badge never see it, and no
   level data threads into the tracked logic. (There is no `minLevel` setting; the rule is
   always "current max level.") Sub-cap characters left over from a previous expansion's
   cap are removed by the load-time cleanup sweep — see Persistence change.
2. **Seriousness gate.** Its season high-water reward tier meets the effective line
   (per-character override, else the account default).

### Stickiness via a high-water mark

Eligibility must persist across a week where the character hasn't earned anything *yet*
(that's exactly when we want to nudge it). We get that from a stored season high-water
mark rather than a sticky boolean:

```
entry.bestTier  -- max earned reward tier observed this season (0 if none)
```

Updated each scan: `entry.bestTier = max(entry.bestTier or 0, bestEarnedTier(thisWeek))`,
reset at season rollover. Because the gate reads `bestTier` live against the line,
**raising a character's line drops it immediately** (a sticky boolean couldn't do this)
— which is the whole point of per-character tuning.

### Pure functions (Derived)

```
Derived.TIER = { veteran = 1, champion = 2, hero = 3, myth = 4 }

Derived.bestEarnedTier(period)        -- max rewardTier across earned slots, all tracks; 0 if none
Derived.qualifies(bestTier, line)     -- bestTier > 0 and bestTier >= line
Derived.effectiveLine(trackTier, accountDefault)
                                      -- per-char override resolves to a tier ordinal;
                                      -- always returns an ordinal (never "off")
Derived.effectiveTracked(entry, accountDefault)
  -> entry.trackTier == "off"  -> false   -- the only place "off" is handled
     otherwise                 -> qualifies(entry.bestTier or 0, effectiveLine(...))
Derived.belowMaxKeys(characters, maxLevel)
                                      -- set of keys whose entry.level < maxLevel;
                                      -- a missing entry.level is NOT below (skipped)
                                      -- (cap-bump cleanup; mirrors Derived.staleKeys)
```

`effectiveTracked` stays purely tier-based — the max-level gate lives in persistence
(scan add-gate + load-time sweep), never in this function. This **replaces**
`Derived.observeEligibility` and the `entry.eligible` / `entry.eligibleAt` fields.

## Per-character line (replaces the old tri-state)

Per-character control is a **tier line**, not an on/off:
`entry.trackTier` ∈ `nil` (auto — use account default) | `"veteran"` | `"champion"` |
`"hero"` | `"myth"` | `"off"`. This subsumes the earlier Always/Ignore idea:

- `"veteran"` ≈ "track on basically anything" (the old "always").
- `"off"` = ignore everywhere, including banked-loot nudges (the old "never").
- `"hero"` / `"myth"` = "only bug me when this character is chasing the top."
- `nil` = inherit the account default.

"Does this character need Champion gear?" is literally setting its line. Driven from
the **roster** (the account-wide cache already lists every known character) via a
right-click menu on a row: **Auto / Veteran / Champion / Hero / Myth / Off**. A
character must have been logged into at least once to be in the cache — an inherent API
limit (we scan only the logged-in character), fine because you set it once from your main.

## Persistence change

`Scanner:Scan()` writes the scanned character to `chars[key]` (Scanner.lua:90), now
**gated on max level** — sub-cap characters are never written (the add-gate, model gate
#1). Every scan also records `entry.level` (a plain number), used only by the cleanup
sweep below. `bestTier` / `trackTier` are **display/attention gates**, not persistence
gates — every cached (max-level) character is kept so you can tune any of them from the
roster, but the default roster and attention only show `effectiveTracked` characters. A
roster **"Show ignored"** toggle reveals the rest (greyed). (This intentionally differs
from the prior spec's "don't persist untracked" rule, which would make per-character
tuning impossible to drive from the main.)

**Cleanup of sub-cap characters (cap-bump).** When a new expansion raises the cap, every
previously-max-level character is now below it. `VaultTracker:Prune()` (Core.lua:27,
called from `OnEnable`) runs a load-time, **once-per-session, unconditional** sweep:
`Derived.belowMaxKeys(chars, GetMaxLevelForPlayerExpansion())` → delete. This is separate
from — and not gated by — the existing `autoPrune` / `pruneWeeks` staleness prune (which
stays). Once per session at DB load is sufficient and cheapest: the cap can't change
mid-session, and `entry.level` only changes via scans (which re-add at-cap characters).
The add-gate prevents sub-cap characters mid-session; the sweep clears the ones stranded
by a cap increase. Each character returns once re-maxed and rescanned. Staleness pruning
is unchanged.

## Config (new settings)

Added to `Config.defaults.global.settings` (Config.lua:8):

| Key | Type | Default | Meaning |
|---|---|---|---|
| `seriousness` | string enum | `"champion"` | Account-default tier line (`veteran`/`champion`/`hero`/`myth`). |
| `showIgnored` | bool | `false` | Roster: reveal untracked/ignored characters (greyed). |

`trackTier` lives per-character on `chars[key]`, not in settings. There is **no
`minLevel` setting** — the max-level gate is a fixed rule (current expansion cap),
enforced in persistence, not a user knob. `entry.level` is stored per-character on
`chars[key]` for the cleanup sweep.

## Changes by file

- **Derived.lua** — add `TIER`, `bestEarnedTier`, `qualifies`, `effectiveLine`,
  `effectiveTracked`, `belowMaxKeys`; remove `observeEligibility`.
- **Scanner.lua** — resolve each earned slot's reward tier (next to the existing
  `rewardIlvl`); compute `bestEarnedTier`; update `entry.bestTier` high-water mark with
  season reset; store `entry.level`; drop `eligible`/`eligibleAt`. **Gate the write on
  max level**: only `chars[key] = entry` when `UnitLevel("player") >=
  GetMaxLevelForPlayerExpansion()` (the add-gate).
- **Core.lua** — extend `Prune()` (Core.lua:27) with an unconditional cap-bump sweep
  (`Derived.belowMaxKeys(chars, GetMaxLevelForPlayerExpansion())` → delete), in addition
  to the existing `autoPrune`-gated staleness prune. Runs once at `OnEnable`.
- **Attention.lua** — gate on `Derived.effectiveTracked(entry, settings.seriousness)`
  instead of `char.eligible` (Attention.lua:34). Note the `banked` branch is currently
  *outside* the eligibility check (Attention.lua:31) — it must move **under**
  `effectiveTracked` so ignored/untracked characters produce no attention at all, banked
  included.
- **Roster.lua** — replace `eligible`/`dim` styling with `effectiveTracked`; default
  view shows tracked only; add the `showIgnored` greyed path and the right-click
  **Auto / Veteran / Champion / Hero / Myth / Off** menu writing `trackTier` + refresh.
- **Config.lua** — add the two settings (`seriousness`, `showIgnored`) + defaults; add a
  seriousness dropdown and a "show ignored" checkbox to the AceConfig options (localized).
  No `minLevel` option.
- **Locales/enUS.lua** — keys for the two settings, the four tier labels, and the
  right-click menu; remove `ROSTER_INELIGIBLE` (replace with an "Ignored" line where
  relevant).

## Migration

One-time over `db.global.characters`: for each entry, set `bestTier` = the account
default tier (`champion`) if it was `eligible`, else 0; set `trackTier = nil`; drop
`eligible` / `eligibleAt`. Grandfathered characters thus stay tracked under the default
line and **self-correct to their true tier on the next scan** of that character.
`Clear cache` resets if desired.

Grandfathered entries have no `entry.level` yet, so `belowMaxKeys` must treat a **missing
`entry.level` as not-below** (skip, don't prune) — they keep their slot until the next
scan records a real level. This is safe: the existing cache holds only intended max-level
characters. After the first scan each entry carries a real `entry.level` and the cap-bump
sweep applies normally.

## Fallback (unlikely — tier readability confirmed; retained for reference)

If reward-tier reading regressed, infer the tier from content instead of the reward item:

- **Raid** maps cleanly and permanently: LFR→Veteran, Normal→Champion, Heroic→Hero,
  Mythic→Myth (from the stable DifficultyID, not the localized `raidString`).
- **Dungeon / delve** have no stable content→tier mapping (the key-level and delve-tier
  brackets drift per season — the ilvl-table smell we avoid). In the fallback, gate on
  **raid tier only**, and **defer dungeon/delve/world** to a later "tier inference"
  effort. Delve/dungeon-only mains are then covered by a per-character `"veteran"` line.

Decide this at implementation time from the verification result; the primary design
assumes readability.

## Open verification (in-game, no headless WoW)

- **Reward tier readability** — ✅ verified 2026-06-13 (`Upgrade Level: Veteran 1/6` on
  a 233 world reward). Remaining: finalize the **locale-safe** extraction — confirm the
  `C_TooltipInfo` line `type` for the upgrade line (or the upgrade-tooltip format global
  string), and add the four tier-name locale strings.
- **Season key for the high-water reset.** Identify a current-season identifier (e.g. a
  Mythic+ season API) to reset `bestTier`. Fallback: no auto-reset; rely on `Clear cache`.
- **Max-level API** — confirm `GetMaxLevelForPlayerExpansion()` returns the current
  expansion cap on 12.x. Now **load-bearing**: it gates both the scan add-gate and the
  cap-bump cleanup sweep (not just a default).
- **Roster right-click menu** on a row frame on 12.x (`MenuUtil` or equivalent).

## Verification plan

- `lua tests/run.lua` — unit-test `bestEarnedTier` (max across earned slots, 0 when
  none), `qualifies` (tier boundary, `> 0` requirement), `effectiveLine` /
  `effectiveTracked` (override precedence, `"off"`, account-default inheritance, the
  high-water-mark live re-evaluation when the line rises). Add `belowMaxKeys` (returns
  sub-cap keys; empty when all at cap; a missing `entry.level` is never returned). Update
  the banked-loot test: banked now requires `effectiveTracked`. Replace
  `observeEligibility` tests. Keep green.
- `lua -e "assert(loadfile('X.lua'))"` on every touched file.
- In-game `/reload`: a sub-cap alt is never added to the cache; a world-quest-only
  max-level alt no longer registers (Veteran < Champion); setting the account default to
  `hero` drops a Champion alt and keeps a Hero one; right-click **Off** silences a
  character (roster + badge + sound); setting a delve main to **Veteran** brings it back;
  **Show ignored** lists the rest greyed. (A true cap bump can't be exercised without an
  expansion launch — the `belowMaxKeys` unit test covers that logic.)

## Out of scope

- Tier inference for dungeon/delve/world (only relevant in the Fallback) — deferred there.
- Custom non-tier seriousness thresholds.
- Any "potential ilvl" / reward-curve modeling — explicitly never built.
