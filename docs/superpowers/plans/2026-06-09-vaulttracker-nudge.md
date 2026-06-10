# VaultTracker Nudge System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the VaultTracker addon from scratch — the data-layer scanner (per `VaultTracker-spec.md`) plus a non-intrusive minimap-icon nudge system that watches every character's Great Vault state account-wide.

**Architecture:** Ace3 addon. A pure, UI-free logic core (`Derived`, `Attention`) is unit-tested outside the game with plain Lua. The WoW-facing layer (`Scanner`, `Broker`, `Roster`, `Config`, `Core`) wires the game APIs, LibDBIcon minimap button, and AceConfig settings to that core. The bespoke `name-realm`-keyed cache lives untouched in AceDB's account-wide `global` scope.

**Tech Stack:** Lua 5.1 (WoW), Ace3 (AceAddon/AceDB/AceConfig/AceGUI/AceEvent/AceConsole/AceTimer), LibDataBroker-1.1, LibDBIcon-1.0. Tests run under standalone `lua`.

---

## File Structure

```
VaultTracker.toc        -- metadata, load order, SavedVariables, lib embeds
Libs/                   -- Ace3 + LibDataBroker-1.1 + LibDBIcon-1.0 + embeds.xml
Derived.lua             -- PURE: per-track/per-period derived values + eligibility rule
Attention.lua           -- PURE: cache + settings + secondsToReset -> attention list
Config.lua              -- AceDB defaults + AceConfig options table + slash registration
Scanner.lua             -- reads C_WeeklyRewards, writes cache entry, sets sticky eligibility
Broker.lua              -- LDB object, LibDBIcon button, badge color/count, tooltip, clicks
Roster.lua              -- AceGUI dashboard (left-click)
Core.lua                -- AceAddon bootstrap, event + timer registration, refresh
tests/
  run.lua               -- standalone test runner (asserts on Derived + Attention)
  fixtures.lua          -- hand-built cache/period fixtures shared by tests
```

**Module loading contract:** every `.lua` file starts with `local ADDON, ns = ...`. WoW passes `(addonName, addonTable)` as the file vararg. The pure modules attach themselves to `ns` (e.g. `ns.Derived = Derived`) and reference nothing global at load time, so the test harness can load them with `loadfile(path)("VaultTracker", ns)` and exercise them outside WoW.

---

### Task 1: Project scaffold — addon loads in game

**Files:**
- Create: `VaultTracker.toc`
- Create: `Libs/embeds.xml`
- Create: `Derived.lua`, `Attention.lua`, `Config.lua`, `Scanner.lua`, `Broker.lua`, `Roster.lua`, `Core.lua` (stubs)

- [ ] **Step 1: Fetch libraries into `Libs/`**

Download these libraries and place each project folder under `Libs/` (each is the folder named exactly as below containing its `.lua`/`.xml`):

- Ace3 (provides `LibStub`, `CallbackHandler-1.0`, `AceAddon-3.0`, `AceEvent-3.0`, `AceConsole-3.0`, `AceTimer-3.0`, `AceDB-3.0`, `AceGUI-3.0`, `AceConfig-3.0`) — https://www.curseforge.com/wow/addons/ace3/files (download latest, copy the inner lib folders).
- LibDataBroker-1.1 — https://www.curseforge.com/wow/addons/libdatabroker-1-1
- LibDBIcon-1.0 — https://www.curseforge.com/wow/addons/libdbicon-1-0

Resulting layout: `Libs/LibStub/LibStub.lua`, `Libs/AceAddon-3.0/AceAddon-3.0.xml`, `Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua`, etc.

- [ ] **Step 2: Write `Libs/embeds.xml`**

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/">
  <Include file="LibStub\LibStub.lua"/>
  <Include file="CallbackHandler-1.0\CallbackHandler-1.0.xml"/>
  <Include file="AceAddon-3.0\AceAddon-3.0.xml"/>
  <Include file="AceEvent-3.0\AceEvent-3.0.xml"/>
  <Include file="AceConsole-3.0\AceConsole-3.0.xml"/>
  <Include file="AceTimer-3.0\AceTimer-3.0.xml"/>
  <Include file="AceDB-3.0\AceDB-3.0.xml"/>
  <Include file="AceGUI-3.0\AceGUI-3.0.xml"/>
  <Include file="AceConfig-3.0\AceConfig-3.0.xml"/>
  <Include file="LibDataBroker-1.1\LibDataBroker-1.1.lua"/>
  <Include file="LibDBIcon-1.0\LibDBIcon-1.0.lua"/>
</Ui>
```

- [ ] **Step 3: Write `VaultTracker.toc`**

```
## Interface: 110200
## Title: VaultTracker
## Notes: Account-wide Great Vault nudge tracker
## Author: brandon
## Version: 0.1.0
## SavedVariables: VaultTrackerDB
## X-Category: Information

Libs\embeds.xml
Derived.lua
Attention.lua
Config.lua
Scanner.lua
Broker.lua
Roster.lua
Core.lua
```

Note: set `## Interface:` to the installed client's build. In-game, run `/run print((select(4, GetBuildInfo())))` and use that number.

- [ ] **Step 4: Write stub module files**

Each of `Derived.lua`, `Attention.lua`, `Config.lua`, `Scanner.lua`, `Broker.lua`, `Roster.lua` starts as:

```lua
local ADDON, ns = ...
-- filled in a later task
```

`Core.lua`:

```lua
local ADDON, ns = ...

local VaultTracker = LibStub("AceAddon-3.0"):NewAddon("VaultTracker",
  "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0")
ns.addon = VaultTracker

function VaultTracker:OnInitialize()
  self:Print("VaultTracker loaded.")
end
```

- [ ] **Step 5: Verify it loads in game**

In WoW: enable VaultTracker at the character-select AddOns screen, log in, `/reload`.
Expected: chat prints `VaultTracker: VaultTracker loaded.` and no Lua errors.

- [ ] **Step 6: Commit**

```bash
git add VaultTracker.toc Libs Derived.lua Attention.lua Config.lua Scanner.lua Broker.lua Roster.lua Core.lua
git commit -m "feat: scaffold VaultTracker addon, loads in game"
```

---

### Task 2: Test harness

**Files:**
- Create: `tests/run.lua`
- Create: `tests/fixtures.lua`

- [ ] **Step 1: Write `tests/fixtures.lua`**

```lua
-- Reusable cache/period fixtures for tests. Pure data, no WoW globals.
local F = {}

-- A track is 3 tiers ascending by threshold.
local function track(t1, t2, t3) return { t1, t2, t3 } end
local function tier(threshold, progress, rewardIlvl)
  return { threshold = threshold, progress = progress, level = 0, rewardIlvl = rewardIlvl or 0 }
end
F.track, F.tier = track, tier

-- period with given progress per track
function F.period(raid, dungeon, world)
  return { tracks = { raid = raid, dungeon = dungeon, world = world } }
end

-- An untouched current period (all progress 0).
function F.untouchedPeriod()
  return F.period(
    track(tier(2,0), tier(4,0), tier(6,0)),
    track(tier(1,0), tier(4,0), tier(8,0)),
    track(tier(2,0), tier(4,0), tier(8,0)))
end

-- A fully maxed current period.
function F.maxedPeriod()
  return F.period(
    track(tier(2,2,272), tier(4,4,268), tier(6,6,264)),
    track(tier(1,1,272), tier(4,4,268), tier(8,8,264)),
    track(tier(2,2,272), tier(4,4,268), tier(8,8,264)))
end

-- A partial period: some slots unlocked, not all.
function F.partialPeriod()
  return F.period(
    track(tier(2,2,259), tier(4,0), tier(6,0)),
    track(tier(1,0), tier(4,0), tier(8,0)),
    track(tier(2,2,272), tier(4,2), tier(8,2)))
end

-- Build a character entry around a current period.
function F.char(opts)
  local weekId = opts.weekId or 1000
  return {
    name = opts.name or "Veyra",
    realm = opts.realm or "Fenris",
    class = opts.class or "PRIEST",
    ilvl = opts.ilvl or 148,
    hasPendingLoot = opts.hasPendingLoot or false,
    eligible = opts.eligible or false,
    eligibleAt = opts.eligibleAt,
    currentWeekId = weekId,
    periods = { [weekId] = opts.period or F.untouchedPeriod() },
  }
end

return F
```

- [ ] **Step 2: Write `tests/run.lua`**

```lua
-- Standalone test runner. Run: lua tests/run.lua
local passed, failed = 0, 0
local function eq(actual, expected, msg)
  if actual == expected then passed = passed + 1
  else failed = failed + 1
    print(("FAIL: %s\n  expected %s, got %s"):format(msg, tostring(expected), tostring(actual)))
  end
end

-- Load a WoW addon module the same way WoW does: chunk(addonName, ns).
local function loadModule(path, ns)
  local chunk = assert(loadfile(path))
  chunk("VaultTracker", ns)
end

local F = dofile("tests/fixtures.lua")
local ns = {}
loadModule("Derived.lua", ns)
loadModule("Attention.lua", ns)

-- ============ Derived tests filled in Task 3 ============
-- ============ Attention tests filled in Task 5 ============

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
```

- [ ] **Step 3: Run it (expect it to load but assert nothing yet)**

Run: `lua tests/run.lua`
Expected: prints `0 passed, 0 failed`, exits 0. (If `lua` is missing on macOS: `brew install lua`.)

- [ ] **Step 4: Commit**

```bash
git add tests/run.lua tests/fixtures.lua
git commit -m "test: add standalone Lua test harness and fixtures"
```

---

### Task 3: Derived module (pure)

**Files:**
- Modify: `Derived.lua`
- Test: `tests/run.lua`

- [ ] **Step 1: Write failing tests in `tests/run.lua`** (replace the `Derived tests` comment line)

```lua
local Derived = ns.Derived
do
  local untouched = F.untouchedPeriod()
  local partial = F.partialPeriod()
  local maxed = F.maxedPeriod()

  eq(Derived.slotsUnlocked(untouched.tracks.raid), 0, "slotsUnlocked untouched raid")
  eq(Derived.slotsUnlocked(partial.tracks.world), 1, "slotsUnlocked partial world (1 of 3)")
  eq(Derived.slotsUnlocked(maxed.tracks.dungeon), 3, "slotsUnlocked maxed dungeon")

  eq(Derived.xToNext(partial.tracks.world), 2, "xToNext partial world (4-2)")
  eq(Derived.xToNext(maxed.tracks.raid), nil, "xToNext maxed is nil")

  local ilvls = Derived.slotIlvls(partial.tracks.raid)
  eq(ilvls[1], 259, "slotIlvls raid slot1")
  eq(ilvls[2], 0, "slotIlvls raid slot2 (locked)")

  eq(Derived.bestIlvl(partial), 272, "bestIlvl partial = 272 (world slot1)")
  eq(Derived.isMaxed(maxed), true, "isMaxed maxed")
  eq(Derived.isMaxed(partial), false, "isMaxed partial")
  eq(Derived.isUntouched(untouched), true, "isUntouched untouched")
  eq(Derived.isUntouched(partial), false, "isUntouched partial")

  -- sticky eligibility: prev true stays true; else true iff any progress
  eq(Derived.observeEligibility(true, untouched), true, "eligibility sticky when prev true")
  eq(Derived.observeEligibility(false, untouched), false, "eligibility false when untouched + prev false")
  eq(Derived.observeEligibility(false, partial), true, "eligibility true on first progress")

  local char = F.char({ weekId = 1000, period = partial })
  eq(Derived.currentPeriod(char), partial, "currentPeriod returns the current weekId period")
end
```

- [ ] **Step 2: Run, verify failure**

Run: `lua tests/run.lua`
Expected: FAIL lines like `attempt to index field 'Derived' (a nil value)` or method-not-found.

- [ ] **Step 3: Implement `Derived.lua`**

```lua
local ADDON, ns = ...
local Derived = {}
ns.Derived = Derived

-- track: array of 3 tiers { threshold, progress, level, rewardIlvl }
function Derived.slotsUnlocked(track)
  local n = 0
  for _, tier in ipairs(track) do
    if tier.progress >= tier.threshold then n = n + 1 end
  end
  return n
end

function Derived.xToNext(track)
  for _, tier in ipairs(track) do
    if tier.progress < tier.threshold then
      return tier.threshold - tier.progress
    end
  end
  return nil
end

function Derived.slotIlvls(track)
  local out = {}
  for i, tier in ipairs(track) do
    out[i] = tier.rewardIlvl or 0
  end
  return out
end

-- period: { tracks = { raid=, dungeon=, world= } }
function Derived.bestIlvl(period)
  local best = 0
  for _, track in pairs(period.tracks) do
    for _, tier in ipairs(track) do
      if tier.progress >= tier.threshold and (tier.rewardIlvl or 0) > best then
        best = tier.rewardIlvl
      end
    end
  end
  return best
end

function Derived.isMaxed(period)
  for _, track in pairs(period.tracks) do
    for _, tier in ipairs(track) do
      if tier.progress < tier.threshold then return false end
    end
  end
  return true
end

function Derived.isUntouched(period)
  for _, track in pairs(period.tracks) do
    for _, tier in ipairs(track) do
      if tier.progress > 0 then return false end
    end
  end
  return true
end

-- Sticky per-season eligibility: once a character has shown any progress, it
-- stays eligible (so an untouched-this-week raider still nudges); a bank alt
-- that never progresses never becomes eligible.
function Derived.observeEligibility(prevEligible, currentPeriod)
  if prevEligible then return true end
  if not currentPeriod then return false end
  return not Derived.isUntouched(currentPeriod)
end

function Derived.currentPeriod(char)
  return char.periods and char.periods[char.currentWeekId] or nil
end
```

- [ ] **Step 4: Run, verify pass**

Run: `lua tests/run.lua`
Expected: all Derived assertions pass.

- [ ] **Step 5: Commit**

```bash
git add Derived.lua tests/run.lua
git commit -m "feat: add pure Derived module (slots, ilvls, maxed/untouched, eligibility)"
```

---

### Task 4: Attention module (pure)

**Files:**
- Modify: `Attention.lua`
- Test: `tests/run.lua`

- [ ] **Step 1: Write failing tests in `tests/run.lua`** (replace the `Attention tests` comment line)

```lua
local Attention = ns.Attention
do
  local HOUR = 3600
  local settings = {
    thresholdHours = 48,
    triggers = { banked = true, untouched = true, incomplete = true },
  }
  local inWindow = 10 * HOUR     -- inside 48h
  local outWindow = 100 * HOUR   -- outside 48h

  -- banked loot: counts regardless of window or eligibility
  local chars = {
    ["A-X"] = F.char({ name="A", realm="X", hasPendingLoot=true, eligible=false,
                       period=F.maxedPeriod() }),
  }
  local list = Attention.build(chars, settings, outWindow)
  eq(#list, 1, "banked counts outside window")
  eq(list[1].severity, "red", "banked is red severity")
  eq(list[1].reasons[1], "banked", "banked reason")

  -- untouched eligible char inside window -> amber
  chars = {
    ["B-X"] = F.char({ name="B", realm="X", eligible=true, period=F.untouchedPeriod() }),
  }
  eq(#Attention.build(chars, settings, inWindow), 1, "untouched eligible in-window counts")
  eq(#Attention.build(chars, settings, outWindow), 0, "untouched outside window does not count")

  -- ineligible untouched char never counts (the bank-alt case)
  chars = {
    ["C-X"] = F.char({ name="C", realm="X", eligible=false, period=F.untouchedPeriod() }),
  }
  eq(#Attention.build(chars, settings, inWindow), 0, "ineligible untouched stays silent")

  -- incomplete (partial) eligible char inside window -> amber, reason incomplete
  chars = {
    ["D-X"] = F.char({ name="D", realm="X", eligible=true, period=F.partialPeriod() }),
  }
  list = Attention.build(chars, settings, inWindow)
  eq(list[1].reasons[1], "incomplete", "partial eligible -> incomplete")

  -- maxed eligible char -> nothing
  chars = {
    ["E-X"] = F.char({ name="E", realm="X", eligible=true, period=F.maxedPeriod() }),
  }
  eq(#Attention.build(chars, settings, inWindow), 0, "maxed needs no attention")

  -- a char both banked and untouched -> single entry, red, two reasons
  chars = {
    ["F-X"] = F.char({ name="F", realm="X", hasPendingLoot=true, eligible=true,
                       period=F.untouchedPeriod() }),
  }
  list = Attention.build(chars, settings, inWindow)
  eq(#list, 1, "banked+untouched is one entry")
  eq(list[1].severity, "red", "banked+untouched is red")
  eq(#list[1].reasons, 2, "banked+untouched has two reasons")

  -- triggers toggle off suppresses
  local off = { thresholdHours = 48, triggers = { banked=false, untouched=true, incomplete=true } }
  chars = { ["G-X"] = F.char({ name="G", realm="X", hasPendingLoot=true, period=F.maxedPeriod() }) }
  eq(#Attention.build(chars, off, inWindow), 0, "banked trigger off suppresses banked")

  -- summary: red beats amber, count is distinct chars
  chars = {
    ["H-X"] = F.char({ name="H", realm="X", hasPendingLoot=true, period=F.maxedPeriod() }),
    ["I-X"] = F.char({ name="I", realm="X", eligible=true, period=F.untouchedPeriod() }),
  }
  local s = Attention.summary(Attention.build(chars, settings, inWindow))
  eq(s.count, 2, "summary counts 2 chars")
  eq(s.color, "red", "summary color is red when any banked")
end
```

- [ ] **Step 2: Run, verify failure**

Run: `lua tests/run.lua`
Expected: FAIL — `Attention.build` is nil.

- [ ] **Step 3: Implement `Attention.lua`**

```lua
local ADDON, ns = ...
local Attention = {}
ns.Attention = Attention

local function hasReason(entry, reason)
  for _, r in ipairs(entry.reasons) do
    if r == reason then return true end
  end
  return false
end

-- characters: map "name-realm" -> char entry
-- settings: { thresholdHours, triggers = { banked, untouched, incomplete } }
-- secondsToReset: number or nil
function Attention.build(characters, settings, secondsToReset)
  local Derived = ns.Derived
  local inWindow = secondsToReset ~= nil
    and secondsToReset <= settings.thresholdHours * 3600
  local byChar = {}

  local function add(key, char, reason)
    local e = byChar[key]
    if not e then
      e = { key = key, name = char.name, realm = char.realm, class = char.class, reasons = {} }
      byChar[key] = e
    end
    e.reasons[#e.reasons + 1] = reason
  end

  for key, char in pairs(characters) do
    if settings.triggers.banked and char.hasPendingLoot then
      add(key, char, "banked")
    end
    if char.eligible and inWindow then
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

  local list = {}
  for _, e in pairs(byChar) do
    e.severity = hasReason(e, "banked") and "red" or "amber"
    list[#list + 1] = e
  end
  table.sort(list, function(a, b)
    if a.severity ~= b.severity then return a.severity == "red" end
    return a.name < b.name
  end)
  return list
end

function Attention.summary(list)
  local color = "none"
  for _, e in ipairs(list) do
    if e.severity == "red" then return { count = #list, color = "red" } end
    color = "amber"
  end
  return { count = #list, color = color }
end
```

- [ ] **Step 4: Run, verify pass**

Run: `lua tests/run.lua`
Expected: all assertions pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add Attention.lua tests/run.lua
git commit -m "feat: add pure Attention module (nudge triggers + summary)"
```

---

### Task 5: Config — AceDB defaults + options + slash

**Files:**
- Modify: `Config.lua`

- [ ] **Step 1: Implement `Config.lua`**

```lua
local ADDON, ns = ...
local Config = {}
ns.Config = Config

Config.defaults = {
  global = {
    characters = {},  -- bespoke cache, keyed by "name-realm" (see VaultTracker-spec.md)
    settings = {
      thresholdHours = 48,
      triggers = { banked = true, untouched = true, incomplete = true },
      minimap = { hide = false },
    },
  },
}

local function options()
  local s = ns.db.global.settings
  return {
    type = "group",
    name = "VaultTracker",
    args = {
      thresholdHours = {
        type = "range", order = 1, name = "Remind hours before reset",
        desc = "Untouched/incomplete vaults only nudge within this many hours of weekly reset.",
        min = 1, max = 168, step = 1,
        get = function() return s.thresholdHours end,
        set = function(_, v) s.thresholdHours = v; ns.Broker:Update() end,
      },
      banked = {
        type = "toggle", order = 2, name = "Nudge: unclaimed banked loot",
        get = function() return s.triggers.banked end,
        set = function(_, v) s.triggers.banked = v; ns.Broker:Update() end,
      },
      untouched = {
        type = "toggle", order = 3, name = "Nudge: untouched vault",
        get = function() return s.triggers.untouched end,
        set = function(_, v) s.triggers.untouched = v; ns.Broker:Update() end,
      },
      incomplete = {
        type = "toggle", order = 4, name = "Nudge: incomplete vault",
        get = function() return s.triggers.incomplete end,
        set = function(_, v) s.triggers.incomplete = v; ns.Broker:Update() end,
      },
      minimap = {
        type = "toggle", order = 5, name = "Show minimap icon",
        get = function() return not s.minimap.hide end,
        set = function(_, v)
          s.minimap.hide = not v
          local DBIcon = LibStub("LibDBIcon-1.0")
          if v then DBIcon:Show("VaultTracker") else DBIcon:Hide("VaultTracker") end
        end,
      },
    },
  }
end

function Config:Setup(addon)
  local AC = LibStub("AceConfig-3.0")
  AC:RegisterOptionsTable("VaultTracker", options)
  self.dialog = LibStub("AceConfigDialog-3.0")
  self.dialog:AddToBlizOptions("VaultTracker", "VaultTracker")
  addon:RegisterChatCommand("vt", function() Config:Open() end)
end

function Config:Open()
  self.dialog:Open("VaultTracker")
end
```

- [ ] **Step 2: Sanity-check Lua syntax outside the game**

Run: `lua -e "assert(loadfile('Config.lua'))" && echo OK`
Expected: prints `OK` (parses; it references WoW globals only inside functions called at runtime).

- [ ] **Step 3: Commit**

```bash
git add Config.lua
git commit -m "feat: add AceDB defaults and AceConfig settings panel"
```

---

### Task 6: Scanner — read vault, write cache, set eligibility

**Files:**
- Modify: `Scanner.lua`

Reads `C_WeeklyRewards` for the logged-in character and writes one cache entry per `VaultTracker-spec.md`. Track→enum mapping confirmed against the wiki: Raid=`Enum.WeeklyRewardChestThresholdType.Raid` (3), Dungeon=`.Activities` (1), World=`.World` (6).

- [ ] **Step 1: Implement `Scanner.lua`**

```lua
local ADDON, ns = ...
local Scanner = {}
ns.Scanner = Scanner

local TRACKS = {
  raid    = Enum.WeeklyRewardChestThresholdType.Raid,
  dungeon = Enum.WeeklyRewardChestThresholdType.Activities,
  world   = Enum.WeeklyRewardChestThresholdType.World,
}

-- Resolve a tier's reward item level. GetExampleRewardItemHyperlinks may return
-- an illustrative ilvl for unfilled slots (see spec open question); 0 if unknown.
local function rewardIlvl(activityID)
  local ok, upgrade, _ = pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, activityID)
  if not ok or not upgrade then return 0 end
  local ilvl = C_Item.GetDetailedItemLevelInfo(upgrade)
  return ilvl or 0
end

-- Read one track's 3 tiers, sorted ascending by threshold (slot 1/2/3).
local function readTrack(thresholdType)
  local activities = C_WeeklyRewards.GetActivities(thresholdType) or {}
  local tiers = {}
  for _, a in ipairs(activities) do
    tiers[#tiers + 1] = {
      threshold = a.threshold,
      progress = a.progress,
      level = a.level or 0,
      rewardIlvl = (a.progress >= a.threshold) and rewardIlvl(a.id) or 0,
    }
  end
  table.sort(tiers, function(x, y) return x.threshold < y.threshold end)
  return tiers
end

local function characterKey()
  local name = UnitName("player")
  local realm = GetRealmName()
  return name .. "-" .. realm, name, realm
end

function Scanner:Scan()
  local Derived = ns.Derived
  local chars = ns.db.global.characters
  local key, name, realm = characterKey()

  local weekId = C_DateAndTime.GetServerTimeLocal
    and C_WeeklyRewards.GetWeeklyRewardTextureKitOffsets and nil or nil
  -- Period key = current weekly-reset epoch (period start). Derive from now + reset.
  local secondsToReset = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
  local now = time()
  local resetAt = now + secondsToReset
  local WEEK = 7 * 24 * 3600
  local currentWeekId = resetAt - WEEK  -- start of the current period

  local period = { tracks = {
    raid = readTrack(TRACKS.raid),
    dungeon = readTrack(TRACKS.dungeon),
    world = readTrack(TRACKS.world),
  } }

  local prev = chars[key]
  local entry = prev or { periods = {} }
  entry.name = name
  entry.realm = realm
  entry.class = select(2, UnitClass("player"))
  entry.spec = nil
  do
    local specIdx = GetSpecialization and GetSpecialization()
    if specIdx then entry.spec = select(2, GetSpecializationInfo(GetSpecializationInfoByID and 0 or specIdx)) end
  end
  entry.ilvl = math.floor((select(2, GetAverageItemLevel())) or 0)
  entry.lastScan = now
  entry.hasPendingLoot = C_WeeklyRewards.HasAvailableRewards() and true or false
  entry.currentWeekId = currentWeekId
  entry.periods = entry.periods or {}
  entry.periods[currentWeekId] = period

  -- Sticky eligibility.
  local nowEligible = Derived.observeEligibility(entry.eligible or false, period)
  if nowEligible and not entry.eligible then entry.eligibleAt = currentWeekId end
  entry.eligible = nowEligible

  -- Banked-period deletion rule (per spec): no pending loot => clear older periods.
  if not entry.hasPendingLoot then
    for wk in pairs(entry.periods) do
      if wk < currentWeekId then entry.periods[wk] = nil end
    end
  end

  chars[key] = entry
  return entry
end
```

Note on `spec`: keep it best-effort; if the spec-name resolution is awkward in-game, simplify to `entry.spec = nil` — it is display-only and not used by any trigger. Fix the exact spec-name call during the in-game smoke test (Task 9) if it errors.

- [ ] **Step 2: Syntax check**

Run: `lua -e "assert(loadfile('Scanner.lua'))" && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add Scanner.lua
git commit -m "feat: add Scanner writing per-character vault cache + sticky eligibility"
```

---

### Task 7: Broker — minimap icon, badge, tooltip, clicks

**Files:**
- Modify: `Broker.lua`

- [ ] **Step 1: Implement `Broker.lua`**

```lua
local ADDON, ns = ...
local Broker = {}
ns.Broker = Broker

local COLORS = {
  red   = { 1.0, 0.25, 0.25 },
  amber = { 1.0, 0.82, 0.25 },
  none  = { 0.6, 0.6, 0.6 },
}

function Broker:Setup(addon)
  local LDB = LibStub("LibDataBroker-1.1")
  local DBIcon = LibStub("LibDBIcon-1.0")

  self.obj = LDB:NewDataObject("VaultTracker", {
    type = "data source",
    text = "Vault",
    icon = "Interface\\Icons\\INV_Misc_Treasurechest_03",
    OnClick = function(_, button) Broker:OnClick(button) end,
    OnTooltipShow = function(tt) Broker:OnTooltip(tt) end,
  })
  DBIcon:Register("VaultTracker", self.obj, ns.db.global.settings.minimap)
  self:Update()
end

-- Compute the current attention list from live data.
function Broker:Current()
  return ns.Attention.build(
    ns.db.global.characters,
    ns.db.global.settings,
    C_DateAndTime.GetSecondsUntilWeeklyReset())
end

function Broker:Update()
  if not self.obj then return end
  local list = self:Current()
  local s = ns.Attention.summary(list)
  local c = COLORS[s.color] or COLORS.none

  -- LDB text + icon color hint (used by bar displays).
  self.obj.text = (s.count > 0) and tostring(s.count) or "Vault"
  self.obj.iconR, self.obj.iconG, self.obj.iconB = c[1], c[2], c[3]

  -- Minimap button: tint icon + overlay a numeric badge.
  local DBIcon = LibStub("LibDBIcon-1.0")
  local button = DBIcon.GetMinimapButton and DBIcon:GetMinimapButton("VaultTracker")
  if button then
    if button.icon then button.icon:SetVertexColor(c[1], c[2], c[3]) end
    if not button.vtBadge then
      local fs = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 2)
      button.vtBadge = fs
    end
    button.vtBadge:SetText(s.count > 0 and tostring(s.count) or "")
  end
end

function Broker:OnClick(button)
  if button == "RightButton" then
    ns.Config:Open()
  else
    ns.Roster:Toggle()
  end
end

local REASON_TEXT = { banked = "banked loot", untouched = "untouched", incomplete = "incomplete" }

function Broker:OnTooltip(tt)
  tt:AddLine("VaultTracker")
  local list = self:Current()
  if #list == 0 then
    tt:AddLine("Nothing needs attention.", 0.6, 0.6, 0.6)
  else
    for _, e in ipairs(list) do
      local labels = {}
      for _, r in ipairs(e.reasons) do labels[#labels + 1] = REASON_TEXT[r] or r end
      local c = COLORS[e.severity] or COLORS.none
      tt:AddDoubleLine(e.name .. "-" .. e.realm, table.concat(labels, ", "),
        1, 1, 1, c[1], c[2], c[3])
    end
  end
  local secs = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
  tt:AddLine(("Reset in %dh %dm"):format(math.floor(secs / 3600), math.floor((secs % 3600) / 60)),
    0.5, 0.5, 0.5)
  tt:AddLine("Left-click: roster   Right-click: settings", 0.4, 0.4, 0.4)
end
```

Note: `DBIcon:GetMinimapButton` exists in current LibDBIcon-1.0; the `if button then` guard keeps the addon working (tooltip + LDB text still convey count) even on an older lib that lacks it.

- [ ] **Step 2: Syntax check**

Run: `lua -e "assert(loadfile('Broker.lua'))" && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add Broker.lua
git commit -m "feat: add LibDBIcon broker with badge, severity color, attention tooltip"
```

---

### Task 8: Roster — AceGUI dashboard

**Files:**
- Modify: `Roster.lua`

- [ ] **Step 1: Implement `Roster.lua`**

```lua
local ADDON, ns = ...
local Roster = {}
ns.Roster = Roster

local AceGUI = LibStub("AceGUI-3.0")
local TRACK_ORDER = { "raid", "dungeon", "world" }
local TRACK_LABEL = { raid = "Raid", dungeon = "Dungeon", world = "World" }

local function classColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.colorStr end
  return "ffffffff"
end

local function trackLine(track)
  local Derived = ns.Derived
  local dots = {}
  for i = 1, #track do
    dots[i] = (track[i].progress >= track[i].threshold) and "|cff33ff33O|r" or "|cff555555o|r"
  end
  local ilvls = Derived.slotIlvls(track)
  local parts = {}
  for i = 1, #ilvls do parts[i] = ilvls[i] > 0 and tostring(ilvls[i]) or "--" end
  return table.concat(dots, "") .. "  " .. table.concat(parts, " / ")
end

function Roster:Build()
  local Derived = ns.Derived
  local frame = AceGUI:Create("Frame")
  frame:SetTitle("VaultTracker — Roster")
  frame:SetLayout("List")
  frame:SetCallback("OnClose", function(widget) AceGUI:Release(widget); Roster.frame = nil end)
  self.frame = frame

  -- Sort: eligible first, then by name.
  local keys = {}
  for key in pairs(ns.db.global.characters) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    local ca, cb = ns.db.global.characters[a], ns.db.global.characters[b]
    if (ca.eligible or false) ~= (cb.eligible or false) then return ca.eligible and true or false end
    return (ca.name or a) < (cb.name or b)
  end)

  for _, key in ipairs(keys) do
    local char = ns.db.global.characters[key]
    local g = AceGUI:Create("InlineGroup")
    g:SetFullWidth(true)
    g:SetLayout("List")
    local pending = char.hasPendingLoot and "  |cffff4040[banked loot]|r" or ""
    local dim = char.eligible and "" or "|cff888888"
    g:SetTitle(("|c%s%s-%s|r  ilvl %d%s"):format(
      classColor(char.class), char.name or "?", char.realm or "?", char.ilvl or 0, pending))

    local period = Derived.currentPeriod(char)
    for _, tk in ipairs(TRACK_ORDER) do
      local lbl = AceGUI:Create("Label")
      lbl:SetFullWidth(true)
      local track = period and period.tracks[tk]
      local body = track and trackLine(track) or "no data"
      lbl:SetText(("%s%-8s|r  %s"):format(dim, TRACK_LABEL[tk], body))
      g:AddChild(lbl)
    end
    frame:AddChild(g)
  end
end

function Roster:Toggle()
  if self.frame then
    self.frame:Hide()  -- triggers OnClose -> Release
  else
    self:Build()
  end
end
```

- [ ] **Step 2: Syntax check**

Run: `lua -e "assert(loadfile('Roster.lua'))" && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add Roster.lua
git commit -m "feat: add AceGUI roster dashboard with per-track slot detail"
```

---

### Task 9: Core wiring — events, timer, refresh

**Files:**
- Modify: `Core.lua`

- [ ] **Step 1: Replace `Core.lua` with full wiring**

```lua
local ADDON, ns = ...

local VaultTracker = LibStub("AceAddon-3.0"):NewAddon("VaultTracker",
  "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0")
ns.addon = VaultTracker

function VaultTracker:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("VaultTrackerDB", ns.Config.defaults, true)
  ns.db = self.db
  ns.Config:Setup(self)
  ns.Broker:Setup(self)
end

function VaultTracker:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnVaultEvent")
  self:RegisterEvent("WEEKLY_REWARDS_UPDATE", "OnVaultEvent")
  self:RegisterEvent("WEEKLY_REWARDS_SHOW", "OnVaultEvent")
  -- Re-evaluate each minute so the badge lights up on crossing into the
  -- time window and the reset clock advances.
  self.refreshTimer = self:ScheduleRepeatingTimer(function() ns.Broker:Update() end, 60)
  self:OnVaultEvent()
end

function VaultTracker:OnVaultEvent()
  ns.Scanner:Scan()
  ns.Broker:Update()
end
```

- [ ] **Step 2: Syntax check**

Run: `lua -e "assert(loadfile('Core.lua'))" && echo OK`
Expected: `OK`.

- [ ] **Step 3: Run full pure test suite (regression)**

Run: `lua tests/run.lua`
Expected: all Derived + Attention assertions pass, exit 0.

- [ ] **Step 4: Commit**

```bash
git add Core.lua
git commit -m "feat: wire events, periodic refresh, and scan-on-event in Core"
```

---

### Task 10: In-game smoke test

**Files:** none (manual verification).

- [ ] **Step 1: Load and scan**

In WoW: `/reload`. Expected: no Lua errors; minimap icon appears (treasure chest).

- [ ] **Step 2: Verify scan wrote a cache entry**

Run in-game: `/run local d=VaultTrackerDB.global.characters; for k,v in pairs(d) do print(k, v.eligible, v.hasPendingLoot, v.ilvl) end`
Expected: an entry for the current character with sane ilvl. If you've done any vault activity this week, `eligible = true`.

- [ ] **Step 3: Verify time-window behavior**

Right-click icon → settings → set "Remind hours before reset" to 168 (max). Hover icon.
Expected: an untouched/incomplete eligible character now appears in the tooltip with an amber entry; badge shows a count. Set it back to 1 → the time-based entries drop off (banked entries, if any, remain red).

- [ ] **Step 4: Verify clicks**

Left-click icon → roster window opens listing characters with per-track dots + ilvls. Right-click → settings panel opens. `/vt` also opens settings.

- [ ] **Step 5: Verify bank-alt silence**

Confirm a never-progressed character (no vault activity this season) does not appear in the attention tooltip even within the window. (`eligible` should be `false` for it in the dump from Step 2.)

- [ ] **Step 6: Tag the version**

```bash
git add -A
git commit -m "chore: VaultTracker 0.1.0 nudge system complete" --allow-empty
git tag v0.1.0
```

---

## Self-Review Notes

- **Spec coverage:** minimap badge+tooltip (Task 7), three triggers (Task 4), configurable window default 48h (Tasks 5/4), left-click roster / right-click settings (Tasks 7/8/5), sticky eligibility via progress (Tasks 3/6), AceDB `global` cache unchanged (Tasks 5/6), data-layer scan per spec (Task 6), banked-period deletion rule (Task 6). All covered.
- **Incomplete definition:** v1 treats `incomplete = eligible AND in-window AND not maxed AND not untouched`. The spec's "realistically reachable slots" nuance (a slot you literally cannot fill anymore) is deferred — it would need run-availability data the API doesn't cleanly expose. Documented as a known simplification.
- **Known in-game fixups to expect:** exact `## Interface:` number (Task 1 Step 3), spec-name resolution in Scanner (Task 6 note), and `GetMinimapButton` availability (Task 7 note) are all guarded or have a verification command rather than being assumed silently.
- **Carried open questions** (from the data spec, display-fidelity only, not blocking): example-vs-exact reward ilvl, season-end eligibility reset, current-period readability while pending loot is true.
