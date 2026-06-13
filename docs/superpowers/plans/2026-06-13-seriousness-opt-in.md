# Seriousness-Based Opt-In (Eligibility v2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace "any progress = eligible" with a reward-tier seriousness gate plus a max-level persistence gate, driven by an account default and per-character lines, tunable from the roster.

**Architecture:** Pure tier logic in `Derived` (TDD, no game), tier extraction + high-water mark + max-level gate in `Scanner`, a cap-bump cleanup sweep in `Core`, attention/roster gating on `effectiveTracked`, and new account settings in `Config`/`Locales`. The four in-game-only unknowns (reward-tier extraction, season key, max-level API, right-click menu API) are isolated into verification spikes that run before the code that depends on them.

**Tech Stack:** Lua, WoW retail API (12.x / interface 120005), Ace3 (AceDB/AceConfig/AceLocale), standalone `lua tests/run.lua` runner with `tests/fixtures.lua`.

**Spec:** `docs/superpowers/specs/2026-06-13-seriousness-opt-in-design.md`

---

## Phasing

- **Phase 1 — Pure logic (Tasks 1–5).** Purely **additive** new `Derived` functions, fully TDD-able now, no game. Break nothing; the addon still runs on the old `eligible` path until Phase 3 swaps callers. (`observeEligibility` is removed in Task 12, alongside its only caller in `Scanner` — removing it earlier would break the live addon.)
- **Phase 2 — Verification spikes (Tasks 7–10).** In-game `/reload` checks the user runs to pin down the four unknowns. Each produces a confirmed API call/value the later tasks consume. **Do not write final code for a spiked unknown until its spike is done.**
- **Phase 3 — Integration (Tasks 11–15).** Scanner, Core, Attention, Roster, Config/Locales — wired using the Phase-1 functions and Phase-2 confirmations.

## File Structure

- `Derived.lua` — add `TIER`, `bestEarnedTier`, `qualifies`, `effectiveLine`, `effectiveTracked`, `belowMaxKeys`; remove `observeEligibility`.
- `Scanner.lua` — per-slot `rewardTier`; `entry.bestTier` high-water + season reset; `entry.level`; max-level add-gate; drop `eligible`/`eligibleAt`.
- `Core.lua` — extend `Prune()` with the unconditional `belowMaxKeys` cap-bump sweep.
- `Attention.lua` — gate all reasons (banked included) on `effectiveTracked`.
- `Roster.lua` — `effectiveTracked` styling, `showIgnored` greyed path, right-click tier menu.
- `Config.lua` — `seriousness` + `showIgnored` settings, defaults, options.
- `Locales/enUS.lua` — setting/label/menu keys; remove `ROSTER_INELIGIBLE`.
- `tests/fixtures.lua` — `tier()` gains a `rewardTier` arg; `F.char` gains `bestTier`/`trackTier`, drops `eligible`.
- `tests/run.lua` — replace `observeEligibility` tests; add tier-logic + `belowMaxKeys` tests; update Attention tests to the new gate.

---

## Phase 1 — Pure logic

### Task 1: `Derived.TIER` + `bestEarnedTier`

**Files:**
- Modify: `Derived.lua` (add after `bestIlvl`, ~Derived.lua:55)
- Modify: `tests/fixtures.lua:6` (extend `tier` with `rewardTier`)
- Test: `tests/run.lua` (Derived `do` block, after line 56)

- [ ] **Step 1: Extend the fixture `tier` to carry a reward tier**

In `tests/fixtures.lua`, replace the `tier` function (line 6-8):

```lua
local function tier(threshold, progress, rewardIlvl, rewardTier)
  return {
    threshold = threshold, progress = progress, level = 0,
    rewardIlvl = rewardIlvl or 0, rewardTier = rewardTier or 0,
  }
end
```

(Existing callers omit `rewardTier` → defaults to 0; no other fixture edits needed.)

- [ ] **Step 2: Write the failing test**

In `tests/run.lua`, inside the first Derived `do` block (after line 56, before the `observeEligibility` lines), add:

```lua
  -- tier ordinals + best earned tier across all tracks
  eq(Derived.TIER.veteran, 1, "TIER veteran=1")
  eq(Derived.TIER.myth, 4, "TIER myth=4")
  -- a period where the highest *earned* slot carries rewardTier 3 (hero)
  local tp = F.period(
    F.track(F.tier(2,2,272,2), F.tier(4,4,268,3), F.tier(6,0,0,0)),  -- raid: champ, hero earned
    F.track(F.tier(1,1,272,1), F.tier(4,0,0,0), F.tier(8,0,0,0)),    -- dungeon: veteran earned
    F.track(F.tier(2,2,272,1), F.tier(4,2,0,0), F.tier(8,2,0,0)))    -- world: veteran earned
  eq(Derived.bestEarnedTier(tp), 3, "bestEarnedTier = 3 (hero, earned)")
  eq(Derived.bestEarnedTier(F.untouchedPeriod()), 0, "bestEarnedTier 0 when nothing earned")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL — `attempt to index a nil value (field 'TIER')` / `bestEarnedTier` nil.

- [ ] **Step 4: Implement in `Derived.lua`** (insert after `bestIlvl`, before `isMaxed`)

```lua
Derived.TIER = { veteran = 1, champion = 2, hero = 3, myth = 4 }

-- Max earned reward tier across all tracks of a period (0 if nothing earned).
-- Reads tier.rewardTier (set by Scanner from the reward's "Upgrade Level" line).
function Derived.bestEarnedTier(period)
  local best = 0
  for _, track in pairs(period.tracks) do
    for _, tier in ipairs(track) do
      if tier.progress >= tier.threshold and (tier.rewardTier or 0) > best then
        best = tier.rewardTier
      end
    end
  end
  return best
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: PASS (all tests, count increased).

- [ ] **Step 6: Commit**

```bash
git add Derived.lua tests/fixtures.lua tests/run.lua
git commit -m "feat: Derived.TIER and bestEarnedTier"
```

### Task 2: `Derived.qualifies`

**Files:**
- Modify: `Derived.lua`
- Test: `tests/run.lua` (Derived block)

- [ ] **Step 1: Write the failing test** (append to the Derived block additions)

```lua
  eq(Derived.qualifies(0, 1), false, "qualifies: 0 best never qualifies even at line 1")
  eq(Derived.qualifies(2, 2), true, "qualifies: best == line")
  eq(Derived.qualifies(3, 2), true, "qualifies: best above line")
  eq(Derived.qualifies(1, 2), false, "qualifies: best below line")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL — `qualifies` nil.

- [ ] **Step 3: Implement** (in `Derived.lua`, after `bestEarnedTier`)

```lua
-- True iff a character has earned something (bestTier > 0) at or above the line.
function Derived.qualifies(bestTier, line)
  return bestTier > 0 and bestTier >= line
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Derived.lua tests/run.lua
git commit -m "feat: Derived.qualifies"
```

### Task 3: `Derived.effectiveLine`

**Files:**
- Modify: `Derived.lua`
- Test: `tests/run.lua` (Derived block)

- [ ] **Step 1: Write the failing test**

```lua
  eq(Derived.effectiveLine(nil, "champion"), 2, "effectiveLine: nil inherits account default")
  eq(Derived.effectiveLine("hero", "champion"), 3, "effectiveLine: override wins")
  eq(Derived.effectiveLine("veteran", "myth"), 1, "effectiveLine: veteran override")
  eq(Derived.effectiveLine("off", "champion"), 2, "effectiveLine: 'off' falls back to default (handled by effectiveTracked)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL — `effectiveLine` nil.

- [ ] **Step 3: Implement** (in `Derived.lua`, after `qualifies`)

```lua
-- Resolve a character's tier line to an ordinal. nil (auto) -> account default.
-- Always returns an ordinal; "off" is handled by effectiveTracked, not here, so a
-- stray "off" falls back to the account default rather than erroring.
function Derived.effectiveLine(trackTier, accountDefault)
  local name = (trackTier and trackTier ~= "off") and trackTier or accountDefault
  return Derived.TIER[name] or Derived.TIER.champion
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Derived.lua tests/run.lua
git commit -m "feat: Derived.effectiveLine"
```

### Task 4: `Derived.effectiveTracked`

**Files:**
- Modify: `Derived.lua`
- Test: `tests/run.lua` (Derived block)

- [ ] **Step 1: Write the failing test**

```lua
  -- effectiveTracked: combines bestTier high-water with the effective line
  eq(Derived.effectiveTracked({ bestTier = 2, trackTier = nil }, "champion"), true,
     "tracked: champion best meets champion default")
  eq(Derived.effectiveTracked({ bestTier = 1, trackTier = nil }, "champion"), false,
     "tracked: veteran best below champion default")
  eq(Derived.effectiveTracked({ bestTier = 1, trackTier = "veteran" }, "champion"), true,
     "tracked: veteran override lets a veteran-best char in")
  eq(Derived.effectiveTracked({ bestTier = 2, trackTier = "hero" }, "champion"), false,
     "tracked: raising line to hero drops a champion-best char immediately")
  eq(Derived.effectiveTracked({ bestTier = 4, trackTier = "off" }, "champion"), false,
     "tracked: 'off' is never tracked regardless of bestTier")
  eq(Derived.effectiveTracked({ trackTier = nil }, "champion"), false,
     "tracked: missing bestTier treated as 0")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL — `effectiveTracked` nil.

- [ ] **Step 3: Implement** (in `Derived.lua`, after `effectiveLine`)

```lua
-- The display/attention gate: is this character currently tracked? Reads the
-- season high-water bestTier live against the effective line, so raising a line
-- drops the character immediately. "off" silences everywhere.
function Derived.effectiveTracked(entry, accountDefault)
  if entry.trackTier == "off" then return false end
  local line = Derived.effectiveLine(entry.trackTier, accountDefault)
  return Derived.qualifies(entry.bestTier or 0, line)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Derived.lua tests/run.lua
git commit -m "feat: Derived.effectiveTracked"
```

### Task 5: `Derived.belowMaxKeys` (cap-bump cleanup)

**Files:**
- Modify: `Derived.lua` (add near `staleKeys`, ~Derived.lua:113)
- Test: `tests/run.lua` (the stale-pruning `do` block, ~line 219)

- [ ] **Step 1: Write the failing test** (append inside the stale-pruning `do` block)

```lua
  -- belowMaxKeys: characters under the current cap (cap-bump cleanup)
  local lvlChars = {
    ["Max-X"]   = { level = 80 },
    ["Low-X"]   = { level = 70 },
    ["NoLvl-X"] = {},            -- grandfathered, no level yet
  }
  local below = Derived.belowMaxKeys(lvlChars, 80)
  eq(below["Low-X"], true, "belowMaxKeys: 70 < 80 is below")
  eq(below["Max-X"], nil, "belowMaxKeys: at cap is kept")
  eq(below["NoLvl-X"], nil, "belowMaxKeys: missing level is NOT below (kept)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL — `belowMaxKeys` nil.

- [ ] **Step 3: Implement** (in `Derived.lua`, after `staleKeys`)

```lua
-- Keys of cached characters now below the level cap (e.g. after an expansion
-- raised it). A missing entry.level is treated as not-below (grandfathered until
-- its first scan records a real level). Mirrors staleKeys.
function Derived.belowMaxKeys(characters, maxLevel)
  local out = {}
  for key, char in pairs(characters) do
    if char.level and char.level < maxLevel then out[key] = true end
  end
  return out
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Derived.lua tests/run.lua
git commit -m "feat: Derived.belowMaxKeys for cap-bump cleanup"
```

> **Note — removing `observeEligibility`:** its only caller is `Scanner` (Scanner.lua:79), so it is removed in **Task 12** (with its caller), not in Phase 1. The three `observeEligibility` assertions in `tests/run.lua:58-61` are deleted in that same task.

---

## Phase 2 — Verification spikes (in-game, no headless WoW)

Each spike is a `/reload` + a `/run` snippet the **user** executes and reports back. Record the confirmed result inline in the spec's "Open verification" section and in the dependent task before writing that task's code. Do **not** guess any API name that a spike is meant to confirm.

### Task 7: Spike — locale-safe reward-tier extraction

Confirms how to read a reward's upgrade tier ordinal (1–4) from an earned slot, locale-safely. Feeds Task 11.

- [ ] **Step 1: Get an earned reward's item link and dump its tooltip lines.** With at least one Great Vault slot earned, run in-game:

```lua
/run local id=C_WeeklyRewards.GetActivities(Enum.WeeklyRewardChestThresholdType.World)[1].id; local lk=C_WeeklyRewards.GetExampleRewardItemHyperlinks(id); local d=C_TooltipInfo.GetHyperlink(lk); for i,l in ipairs(d.lines) do print(i, l.type, (l.leftText or "")) end
```

- [ ] **Step 2: Identify the upgrade line.** Note the `type` value (an `Enum.TooltipDataLineType`) of the line whose text is the localized "Upgrade Level: <Tier> x/y". Record the enum name. If `C_TooltipInfo.GetHyperlink` returns nil/empty, fall back to the hidden-`GameTooltip:SetHyperlink` scan (spec §"Reading the tier").

- [ ] **Step 3: Confirm the four localized tier names** on this client (enUS: Veteran/Champion/Hero/Myth). Decide the mapping source: if the line `type` exposes a structured ordinal, use it (no name parsing); otherwise capture the four names for an addon-locale → ordinal map.

- [ ] **Step 4: Record outcome** in the spec and in Task 11 (the confirmed line `type` or global string, and whether name-parsing is needed). No commit (investigation only).

**RESULT (verified 2026-06-13, char "Gigantor"):** the upgrade line is **`line.type == 32`**, `leftText = "Upgrade Level: Myth 1/6"` on a 272 dungeon reward. No structured ordinal field — parse the localized tier name from the type-32 line and map via `L.TIER_*`. Must anchor to type 32: line "Mythic+" (type 0) would false-match a bare "Myth" search. Enum name for value 32: **`Enum.TooltipDataLineType.ItemUpgradeLevel`** (verified 2026-06-13). Task 11 uses `(Enum.TooltipDataLineType.ItemUpgradeLevel or 32)`.

### Task 8: Spike — current-season key for the high-water reset

Confirms an identifier that changes at season rollover, to reset `entry.bestTier`. Feeds Task 12.

- [ ] **Step 1: Probe candidate season APIs** in-game:

```lua
/run print("mplus", C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason())
/run print("pvp", C_PvP and C_PvP.GetActiveSeason and C_PvP.GetActiveSeason())
```

- [ ] **Step 2: Pick the stable per-season integer** that is available at login (does not require entering content). Record it.

- [ ] **Step 3: If none is reliably available, record the fallback decision:** no auto-reset; `entry.bestTier` persists until `Clear cache`. Update the spec's "Open verification" accordingly. No commit.

**RESULT (verified 2026-06-13):** `C_MythicPlus.GetCurrentSeason()` = `17`; `C_PvP.GetActiveSeason()` = nil. Use `<<SEASON>>` = `(C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason())` and key the reset on `entry.bestTierSeason`.

### Task 9: Spike — max-level API

Confirms the expansion cap call. Feeds Tasks 11 and 14.

- [ ] **Step 1: Confirm the call returns the current cap** in-game:

```lua
/run print(GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion(), GetMaxPlayerLevel and GetMaxPlayerLevel())
```

- [ ] **Step 2: Record which call returns the expansion cap** (expected `GetMaxLevelForPlayerExpansion()`); use it verbatim in Tasks 11 and 14. No commit.

**RESULT (verified 2026-06-13):** `GetMaxLevelForPlayerExpansion()` = `90` (= `GetMaxPlayerLevel()`). Use `GetMaxLevelForPlayerExpansion()`.

### Task 10: Spike — roster row right-click menu on 12.x

Confirms the context-menu API for the per-character tier menu. Feeds Task 13 (Roster).

- [ ] **Step 1: Verify `MenuUtil.CreateContextMenu`** with a radio group:

```lua
/run MenuUtil.CreateContextMenu(UIParent, function(_, root) root:CreateTitle("VT test"); root:CreateRadio("Champion", function() return false end, function() print("picked") end) end)
```

- [ ] **Step 2: Confirm a context menu appears and the callback fires.** Record the exact `MenuUtil`/`root` methods that work (title, radio, divider). Use them verbatim in Task 16. No commit.

**RESULT (verified 2026-06-13):** `MenuUtil.CreateContextMenu(owner, func)` opens at the cursor; `root:CreateTitle`, `root:CreateRadio(text, isSelected, onClick)` work and the onClick fires. Use these in Task 16 (Roster); `root:CreateDivider()` assumed available (same menu API).

---

## Phase 3 — Integration

### Task 11: Scanner — per-slot reward tier + `entry.level` + max-level add-gate

**Files:**
- Modify: `Scanner.lua:11-35` (add tier extraction; populate `rewardTier` in `readTrack`)
- Modify: `Scanner.lua:43-92` (`entry.level`; max-level add-gate; drop `eligible`/`eligibleAt`)

**Depends on:** Task 7 (extraction), Task 9 (max-level call). Use the confirmed line `type` / call from those spikes in place of the `<<CONFIRMED…>>` markers below.

- [ ] **Step 1: Add a locale-safe `rewardTier(itemLink)` helper** in `Scanner.lua` (after `rewardIlvl`, ~line 18). Using Task 7's result — example shape if a structured ordinal is **not** available and name-parsing is needed (replace `<<CONFIRMED_LINE_TYPE>>` and wire the locale map from Task 16):

```lua
-- Map a reward item's "Upgrade Level: <Tier> x/y" line to an ordinal (1-4); 0 if
-- unreadable. Locale-safe: locate the line by its tooltip line type (Task 7), then
-- map the localized tier name via ns.L tier names. 0 lets bestEarnedTier ignore it.
local TIER_BY_NAME = nil  -- built lazily from ns.L (Task 16 keys)
local function buildTierByName()
  local L = ns.L
  return { [L.TIER_VETERAN] = 1, [L.TIER_CHAMPION] = 2, [L.TIER_HERO] = 3, [L.TIER_MYTH] = 4 }
end
local function rewardTier(itemLink)
  if not itemLink then return 0 end
  local data = C_TooltipInfo.GetHyperlink(itemLink)
  if not data or not data.lines then return 0 end
  TIER_BY_NAME = TIER_BY_NAME or buildTierByName()
  for _, line in ipairs(data.lines) do
    if line.type == <<CONFIRMED_LINE_TYPE>> and line.leftText then
      for name, ord in pairs(TIER_BY_NAME) do
        if line.leftText:find(name, 1, true) then return ord end
      end
    end
  end
  return 0
end
```

> If Task 7 found a structured ordinal on the line, skip `TIER_BY_NAME` and return that ordinal directly — simpler and fully locale-safe.

- [ ] **Step 2: Populate `rewardTier` in `readTrack`.** In `Scanner.lua` the tier table (lines 25-31) gains one field:

```lua
    tiers[#tiers + 1] = {
      threshold = a.threshold,
      progress = a.progress,
      level = a.level or 0,
      raidString = a.raidString,
      rewardIlvl = (a.progress >= a.threshold) and rewardIlvl(a.id) or 0,
      rewardTier = (a.progress >= a.threshold)
        and rewardTier(C_WeeklyRewards.GetExampleRewardItemHyperlinks(a.id)) or 0,
    }
```

- [ ] **Step 3: Store `entry.level` and add the max-level add-gate.** In `Scanner:Scan()`, after `entry.ilvl = ...` (line 71) add:

```lua
  entry.level = UnitLevel("player")
```

Then replace the eligibility block (lines 78-81) — see Task 12 for the `bestTier` lines that go here — and replace the unconditional write `chars[key] = entry` (line 90) with a max-level gate:

```lua
  if entry.level >= GetMaxLevelForPlayerExpansion() then
    chars[key] = entry
  end
```

- [ ] **Step 4: Syntax check**

Run: `lua -e "assert(loadfile('Scanner.lua'))"`
Expected: no output. (Behaviour is verified in-game at Task 17 — `Scanner.lua` references live WoW globals, so it cannot run under the test harness.)

- [ ] **Step 5: Commit**

```bash
git add Scanner.lua
git commit -m "feat: scan reward tier, store level, gate persistence on max level"
```

### Task 12: Scanner — `entry.bestTier` high-water mark + season reset; remove `observeEligibility`

**Files:**
- Modify: `Scanner.lua` (the block where `eligible` used to live, lines 78-81)
- Modify: `Derived.lua:75-82` (delete `observeEligibility` — its only caller is replaced here)
- Modify: `tests/run.lua:58-61` (delete the three `observeEligibility` assertions + comment)

**Depends on:** Task 1 (`bestEarnedTier`), Task 8 (season key).

- [ ] **Step 0: Remove `observeEligibility`.** Delete the function (comment + body) at `Derived.lua:75-82`, and the three assertions at `tests/run.lua:58-61`:

```lua
  -- sticky eligibility: prev true stays true; else true iff any progress
  eq(Derived.observeEligibility(true, untouched), true, "eligibility sticky when prev true")
  eq(Derived.observeEligibility(false, untouched), false, "eligibility false when untouched + prev false")
  eq(Derived.observeEligibility(false, partial), true, "eligibility true on first progress")
```

- [ ] **Step 1: Replace the old eligibility block** (Scanner.lua:78-81) with the high-water update. Using Task 8's confirmed season call as `<<SEASON>>` (or omit the reset block if Task 8 chose the no-auto-reset fallback):

```lua
  -- Season high-water reward tier. Reset when the season changes (Task 8).
  local season = <<SEASON>>
  if season and entry.bestTierSeason ~= season then
    entry.bestTier, entry.bestTierSeason = 0, season
  end
  entry.bestTier = math.max(entry.bestTier or 0, Derived.bestEarnedTier(period))
  entry.eligible, entry.eligibleAt = nil, nil  -- drop old fields
```

> Fallback (Task 8 found no reliable season key): drop the `season`/reset lines; keep only the `math.max` high-water line and the field-drop. Document "no auto-reset; Clear cache to reset" in the spec.

- [ ] **Step 2: Syntax check + tests** (Derived + the test runner changed in Step 0)

Run: `lua -e "assert(loadfile('Scanner.lua'))" && lua -e "assert(loadfile('Derived.lua'))" && lua tests/run.lua`
Expected: no syntax output; tests PASS (the `observeEligibility` assertions are gone).

- [ ] **Step 3: Commit**

```bash
git add Scanner.lua Derived.lua tests/run.lua
git commit -m "feat: bestTier season high-water mark; remove observeEligibility"
```

### Task 13: Core — cap-bump cleanup sweep in `Prune()`

**Files:**
- Modify: `Core.lua:27-33` (`Prune`)

**Depends on:** Task 5 (`belowMaxKeys`), Task 9 (max-level call).

- [ ] **Step 1: Add the unconditional sweep** to `VaultTracker:Prune()`. Replace lines 27-33:

```lua
function VaultTracker:Prune()
  local chars = ns.db.global.characters
  -- Unconditional cap-bump cleanup: drop characters now below the level cap
  -- (e.g. after an expansion raised it). Independent of autoPrune.
  for key in pairs(ns.Derived.belowMaxKeys(chars, GetMaxLevelForPlayerExpansion())) do
    chars[key] = nil
  end
  -- Staleness pruning (opt-in).
  local s = ns.db.global.settings
  if not s.autoPrune then return end
  for key in pairs(ns.Derived.staleKeys(chars, time(), s.pruneWeeks)) do
    chars[key] = nil
  end
end
```

- [ ] **Step 2: Syntax check**

Run: `lua -e "assert(loadfile('Core.lua'))"`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add Core.lua
git commit -m "feat: cap-bump cleanup sweep in Prune"
```

### Task 14: Attention — gate all reasons on `effectiveTracked`

**Files:**
- Modify: `Attention.lua:30-44`
- Modify: `tests/fixtures.lua:41-54` (`F.char`: add `bestTier`/`trackTier`, drop `eligible`)
- Modify: `tests/run.lua:77-169` (Attention `do` block) — switch `eligible=` to `bestTier=`/`trackTier=`, add `seriousness` to settings

**Depends on:** Task 4 (`effectiveTracked`).

- [ ] **Step 1: Update `F.char`** in `tests/fixtures.lua` (lines 41-54):

```lua
function F.char(opts)
  local weekId = opts.weekId or 1000
  return {
    name = opts.name or "Veyra",
    realm = opts.realm or "Fenris",
    class = opts.class or "PRIEST",
    ilvl = opts.ilvl or 148,
    level = opts.level or 80,
    hasPendingLoot = opts.hasPendingLoot or false,
    bestTier = opts.bestTier or 0,
    trackTier = opts.trackTier,
    currentWeekId = weekId,
    periods = { [weekId] = opts.period or F.untouchedPeriod() },
  }
end
```

- [ ] **Step 2: Update the Attention test settings + char states** in `tests/run.lua`. In the Attention `do` block, give `settings` a default line and translate eligibility to tiers:

```lua
  local settings = {
    thresholdHours = 48,
    seriousness = "champion",
    triggers = { banked = true, untouched = true, incomplete = true },
  }
```

Then in that block replace every `eligible=true` with `bestTier=2` (meets champion default) and every `eligible=false` with `bestTier=0`. Specifically:
- Line ~89 (`A-X`, banked): `eligible=false` → `bestTier=0` **and** verify the new expectation in Step 4 (banked now requires tracked).
- Lines ~99, 112, 119, 125, 141, 150, 151, 160, 165: `eligible=true` → `bestTier=2`.
- Line ~106 (`C-X`, the bank-alt): `eligible=false` → `bestTier=0`.

- [ ] **Step 3: Update the banked-loot expectations** (behaviour change — banked is now gated). Replace the first banked test (lines 88-95) with:

```lua
  -- banked loot now requires the character be tracked (effectiveTracked)
  local chars = {
    ["A-X"] = F.char({ name="A", realm="X", hasPendingLoot=true, bestTier=2,
                       period=F.maxedPeriod() }),
  }
  local list = Attention.build(chars, settings, outWindow)
  eq(#list, 1, "tracked banked counts outside window")
  eq(list[1].severity, "red", "banked is red severity")
  eq(list[1].reasons[1], "banked", "banked reason")

  -- an untracked character with banked loot is silent (off / below line)
  chars = {
    ["Off-X"] = F.char({ name="Off", realm="X", hasPendingLoot=true, trackTier="off",
                         period=F.maxedPeriod() }),
    ["Low-X"] = F.char({ name="Low", realm="X", hasPendingLoot=true, bestTier=0,
                         period=F.maxedPeriod() }),
  }
  eq(#Attention.build(chars, settings, outWindow), 0, "untracked banked is silent")
```

Also update the "triggers toggle off" char (line 135) and summary/sort chars (lines 139-151) to include `bestTier=2` so they remain tracked.

- [ ] **Step 4: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL — Attention still reads `char.eligible`; tracked chars now untracked / banked ungated.

- [ ] **Step 5: Rewrite the Attention loop** in `Attention.lua` (lines 30-44):

```lua
  for key, char in pairs(characters) do
    if Derived.effectiveTracked(char, settings.seriousness) then
      if settings.triggers.banked and char.hasPendingLoot then
        add(key, char, "banked")
      end
      if inWindow then
        local period = Derived.currentPeriod(char)
        if period then
          if settings.triggers.untouched and Derived.isUntouched(period) then
            add(key, char, "untouched")
          elseif settings.triggers.incomplete and not Derived.isMaxed(period) then
            add(key, char, "incomplete")
          end
        end
      end
    end
  end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Attention.lua tests/fixtures.lua tests/run.lua
git commit -m "feat: gate all attention (banked included) on effectiveTracked"
```

### Task 15: Config + Locales — `seriousness`, `showIgnored`

**Files:**
- Modify: `Config.lua:8-18` (defaults), `Config.lua` options table (add dropdown + toggle)
- Modify: `Locales/enUS.lua` (add keys; remove `ROSTER_INELIGIBLE`)

- [ ] **Step 1: Add defaults** in `Config.lua` `settings` (after line 9 `thresholdHours = 48,`):

```lua
      seriousness = "champion",  -- account-default tier line: veteran/champion/hero/myth
      showIgnored = false,       -- roster: reveal untracked/ignored characters (greyed)
```

- [ ] **Step 2: Add locale keys** in `Locales/enUS.lua` (in the Options section, after line 8):

```lua
L.OPT_SERIOUSNESS       = "Track characters from"
L.OPT_SERIOUSNESS_DESC  = "Only count a character once it has earned a reward of at least this tier. Lower = track more alts; higher = only your serious characters."
L.OPT_SHOWIGNORED       = "Show ignored characters"
L.OPT_SHOWIGNORED_DESC  = "List untracked and ignored characters in the roster, greyed out."
L.TIER_VETERAN          = "Veteran"
L.TIER_CHAMPION         = "Champion"
L.TIER_HERO             = "Hero"
L.TIER_MYTH             = "Myth"
L.ROSTER_TRACKTIER      = "Track this character"
L.ROSTER_TRACK_AUTO     = "Auto (account default)"
L.ROSTER_TRACK_OFF      = "Off (ignore)"
L.ROSTER_IGNORED        = "Ignored"
```

- [ ] **Step 3: Remove `ROSTER_INELIGIBLE`** in `Locales/enUS.lua` (delete line 65).

- [ ] **Step 4: Add the AceConfig options** in `Config.lua`. Add a Reminders-area dropdown + a Data-area toggle (note the tier values are addon-internal keys, labels localized):

```lua
      seriousness = {
        type = "select", order = 1.05, width = 1.5, name = L.OPT_SERIOUSNESS,
        desc = L.OPT_SERIOUSNESS_DESC,
        values = { veteran = L.TIER_VETERAN, champion = L.TIER_CHAMPION,
                   hero = L.TIER_HERO, myth = L.TIER_MYTH },
        sorting = { "veteran", "champion", "hero", "myth" },
        get = function() return s.seriousness end,
        set = function(_, v) s.seriousness = v; ns.Broker:Update() end,
      },
      showIgnored = {
        type = "toggle", order = 35, width = "full", name = L.OPT_SHOWIGNORED,
        desc = L.OPT_SHOWIGNORED_DESC,
        get = function() return s.showIgnored end,
        set = function(_, v) s.showIgnored = v end,
      },
```

- [ ] **Step 5: Syntax check + tests** (tests load `Locales/enUS.lua`)

Run: `lua -e "assert(loadfile('Config.lua'))" && lua -e "assert(loadfile('Locales/enUS.lua'))" && lua tests/run.lua`
Expected: no syntax output; tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Config.lua Locales/enUS.lua
git commit -m "feat: seriousness + showIgnored settings and locale keys"
```

### Task 16: Roster — `effectiveTracked` styling, `showIgnored`, right-click tier menu

**Files:**
- Modify: `Roster.lua:85` (`setRowIcon` desaturation), `Roster.lua:121-139` (`sortedKeys` filtering), `Roster.lua:271-343` (`Refresh`: dim, tooltip line, right-click)

**Depends on:** Task 4 (`effectiveTracked`), Task 10 (menu API), Task 15 (locale keys).

- [ ] **Step 1: Replace `char.eligible` dimming** with `effectiveTracked`. In `setRowIcon` (line 85):

```lua
  tex:SetDesaturated(not ns.Derived.effectiveTracked(char, ns.db.global.settings.seriousness))
```

- [ ] **Step 2: Filter `sortedKeys` by tracked unless `showIgnored`.** In `Roster.lua` `sortedKeys` (lines 128-129), replace the key-collection loop:

```lua
  local show = ns.db.global.settings.showIgnored
  local default = ns.db.global.settings.seriousness
  local keys = {}
  for key, char in pairs(chars) do
    if show or ns.Derived.effectiveTracked(char, default) then keys[#keys + 1] = key end
  end
```

- [ ] **Step 3: Compute `dim` from tracked** in `Refresh` (line 281):

```lua
    local dim = not ns.Derived.effectiveTracked(char, ns.db.global.settings.seriousness)
```

- [ ] **Step 4: Replace the ineligible tooltip line** (line 296):

```lua
      if dim then GameTooltip:AddLine(ns.L.ROSTER_IGNORED, 0.6, 0.5, 0.4) end
```

- [ ] **Step 5: Add the right-click tier menu** on the name frame, using Task 10's confirmed `MenuUtil` methods. In `Refresh`, after the `nameFrame` `OnLeave` (line 299), register a right-click handler:

```lua
    row.nameFrame:SetScript("OnMouseUp", function(_, button)
      if button ~= "RightButton" then return end
      local cur = char.trackTier  -- nil | "veteran".."myth" | "off"
      MenuUtil.CreateContextMenu(row.nameFrame, function(_, root)
        root:CreateTitle(ns.L.ROSTER_TRACKTIER)
        local function entry(label, value)
          root:CreateRadio(label, function() return cur == value end, function()
            char.trackTier = value
            ns.Broker:Update()
            ns.Roster:Refresh()
          end)
        end
        entry(ns.L.ROSTER_TRACK_AUTO, nil)
        entry(ns.L.TIER_VETERAN,  "veteran")
        entry(ns.L.TIER_CHAMPION, "champion")
        entry(ns.L.TIER_HERO,     "hero")
        entry(ns.L.TIER_MYTH,     "myth")
        root:CreateDivider()
        entry(ns.L.ROSTER_TRACK_OFF, "off")
      end)
    end)
```

> Adjust `CreateContextMenu`/`CreateRadio`/`CreateDivider`/`CreateTitle` to the exact methods Task 10 confirmed if they differ on 12.x.

- [ ] **Step 6: Syntax check**

Run: `lua -e "assert(loadfile('Roster.lua'))"`
Expected: no output. (Roster uses live WoW frame APIs; behaviour is verified in-game at Task 17.)

- [ ] **Step 7: Commit**

```bash
git add Roster.lua
git commit -m "feat: roster tier styling, show-ignored, right-click tier menu"
```

### Task 17: Migration + full in-game verification

**Files:**
- Modify: `Core.lua` `OnInitialize` (add one-time migration) — optional if relying on self-correct.

- [ ] **Step 1: Add the one-time migration** in `Core.lua:OnInitialize` after `ns.db = self.db` (line 9):

```lua
  if not self.db.global.migratedSeriousnessV2 then
    local def = self.db.global.settings.seriousness or "champion"
    for _, c in pairs(self.db.global.characters) do
      c.bestTier = c.eligible and (ns.Derived.TIER[def] or 2) or 0
      c.trackTier = nil
      c.eligible, c.eligibleAt = nil, nil
    end
    self.db.global.migratedSeriousnessV2 = true
  end
```

- [ ] **Step 2: Syntax check + unit tests**

Run: `lua -e "assert(loadfile('Core.lua'))" && lua tests/run.lua`
Expected: no syntax output; tests PASS (final count well above the prior 66).

- [ ] **Step 3: In-game `/reload` verification** (user). Confirm each spec acceptance:
  - A sub-cap alt is never added to the cache.
  - A world-quest-only max-level alt no longer registers (Veteran < Champion).
  - Setting the account default to **Hero** drops a Champion alt, keeps a Hero one.
  - Right-click a row → **Off** silences it (roster + badge + sound); set a delve main → **Veteran** brings it back.
  - **Show ignored** lists untracked characters greyed.
  - Earned-slot tooltips/tier resolve to live-vault values for all three tracks.

- [ ] **Step 4: Commit**

```bash
git add Core.lua
git commit -m "feat: one-time migration to seriousness v2"
```

---

## Verification

- **Unit:** `lua tests/run.lua` green after every Phase-1 task and at Tasks 14, 15, 17. New coverage: `bestEarnedTier`, `qualifies`, `effectiveLine`, `effectiveTracked` (incl. line-raise drop and `"off"`), `belowMaxKeys` (incl. missing-level), and Attention gated on `effectiveTracked` (banked now requires tracked).
- **Syntax:** `lua -e "assert(loadfile('X.lua'))"` on every touched `.lua` (`Derived`, `Scanner`, `Core`, `Attention`, `Roster`, `Config`, `Locales/enUS`).
- **In-game:** the Task 17 `/reload` checklist (the only way to verify Scanner/Roster/Config behaviour — no headless WoW).

## Self-review notes

- Spec coverage: model gate #1 → Tasks 9/11/13; gate #2 → Tasks 1-4/11-12/14; per-char line → Tasks 4/16; persistence change → Tasks 11/13; config → Task 15; migration → Task 17; verification → Task 17. All spec sections map to a task.
- The four spec "Open verification" items are Tasks 7-10 and block exactly their dependents.
- Naming is consistent across tasks: `entry.bestTier`, `entry.trackTier`, `entry.level`, `rewardTier`, `effectiveTracked(entry, accountDefault)`, `belowMaxKeys(characters, maxLevel)`.
