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

-- Minimal LibStub/AceLocale shim so the real locale file loads outside WoW.
local locales = {}
_G.LibStub = function(name)
  if name == "AceLocale-3.0" then
    return {
      NewLocale = function(_, app) locales[app] = locales[app] or {}; return locales[app] end,
      GetLocale = function(_, app) return locales[app] end,
    }
  end
end

local F = dofile("tests/fixtures.lua")
local ns = {}
loadModule("Locales/enUS.lua", ns)
loadModule("Locale.lua", ns)
loadModule("Derived.lua", ns)
loadModule("Attention.lua", ns)
loadModule("Format.lua", ns)

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

  eq(Derived.qualifies(0, 1), false, "qualifies: 0 best never qualifies even at line 1")
  eq(Derived.qualifies(2, 2), true, "qualifies: best == line")
  eq(Derived.qualifies(3, 2), true, "qualifies: best above line")
  eq(Derived.qualifies(1, 2), false, "qualifies: best below line")

  eq(Derived.effectiveLine(nil, "champion"), 2, "effectiveLine: nil inherits account default")
  eq(Derived.effectiveLine("hero", "champion"), 3, "effectiveLine: override wins")
  eq(Derived.effectiveLine("veteran", "myth"), 1, "effectiveLine: veteran override")
  eq(Derived.effectiveLine("off", "champion"), 2, "effectiveLine: 'off' falls back to default (handled by effectiveTracked)")

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

  local char = F.char({ weekId = 1000, period = partial })
  eq(Derived.currentPeriod(char), partial, "currentPeriod returns the current weekId period")

  -- periodKey: stable under sub-minute clock skew between the two integer clocks
  eq(Derived.periodKey(1000000, 100000), Derived.periodKey(1000001, 99999),
     "periodKey stable under 1s read skew (now +1, countdown -1)")
  eq(Derived.periodKey(1000000, 100000), Derived.periodKey(1000000, 99999),
     "periodKey stable under 1s countdown jitter")
  eq(Derived.periodKey(1000000, 100000), 495180, "periodKey snaps to minute grid minus a week")
  -- distinct weeks yield keys exactly one WEEK apart
  eq(Derived.periodKey(1000000, 100000 + 7*24*3600) - Derived.periodKey(1000000, 100000),
     7*24*3600, "consecutive periods are one WEEK apart")
end
-- ============ Derived tests filled in Task 3 ============
local Attention = ns.Attention
do
  local HOUR = 3600
  local settings = {
    thresholdHours = 48,
    seriousness = "champion",
    triggers = { banked = true, untouched = true, incomplete = true },
  }
  local inWindow = 10 * HOUR     -- inside 48h
  local outWindow = 100 * HOUR   -- outside 48h
  -- bestTier=2 (champion) meets the champion default => tracked; 0 => untracked.

  -- banked loot on a tracked char: counts regardless of window
  local chars = {
    ["A-X"] = F.char({ name="A", realm="X", hasPendingLoot=true, bestTier=2,
                       period=F.maxedPeriod() }),
  }
  local list = Attention.build(chars, settings, outWindow)
  eq(#list, 1, "tracked banked counts outside window")
  eq(list[1].severity, "red", "banked is red severity")
  eq(list[1].reasons[1], "banked", "banked reason")

  -- banked loot on an UNtracked char is silent (off, or below the line)
  chars = {
    ["Off-X"] = F.char({ name="Off", realm="X", hasPendingLoot=true, trackTier="off",
                         bestTier=4, period=F.maxedPeriod() }),
    ["Low-X"] = F.char({ name="Low", realm="X", hasPendingLoot=true, bestTier=0,
                         period=F.maxedPeriod() }),
  }
  eq(#Attention.build(chars, settings, outWindow), 0, "untracked banked is silent")

  -- untouched tracked char inside window -> amber
  chars = {
    ["B-X"] = F.char({ name="B", realm="X", bestTier=2, period=F.untouchedPeriod() }),
  }
  eq(#Attention.build(chars, settings, inWindow), 1, "untouched tracked in-window counts")
  eq(#Attention.build(chars, settings, outWindow), 0, "untouched outside window does not count")

  -- untracked untouched char never counts (the bank-alt case)
  chars = {
    ["C-X"] = F.char({ name="C", realm="X", bestTier=0, period=F.untouchedPeriod() }),
  }
  eq(#Attention.build(chars, settings, inWindow), 0, "untracked untouched stays silent")

  -- incomplete (partial) tracked char inside window -> amber, reason incomplete
  chars = {
    ["D-X"] = F.char({ name="D", realm="X", bestTier=2, period=F.partialPeriod() }),
  }
  list = Attention.build(chars, settings, inWindow)
  eq(list[1].reasons[1], "incomplete", "partial tracked -> incomplete")

  -- maxed tracked char -> nothing
  chars = {
    ["E-X"] = F.char({ name="E", realm="X", bestTier=2, period=F.maxedPeriod() }),
  }
  eq(#Attention.build(chars, settings, inWindow), 0, "maxed needs no attention")

  -- a char both banked and untouched -> single entry, red, two reasons
  chars = {
    ["F-X"] = F.char({ name="F", realm="X", hasPendingLoot=true, bestTier=2,
                       period=F.untouchedPeriod() }),
  }
  list = Attention.build(chars, settings, inWindow)
  eq(#list, 1, "banked+untouched is one entry")
  eq(list[1].severity, "red", "banked+untouched is red")
  eq(#list[1].reasons, 2, "banked+untouched has two reasons")

  -- triggers toggle off suppresses (char is tracked so the trigger is what gates)
  local off = { thresholdHours = 48, seriousness = "champion",
                triggers = { banked=false, untouched=true, incomplete=true } }
  chars = { ["G-X"] = F.char({ name="G", realm="X", hasPendingLoot=true, bestTier=2,
                               period=F.maxedPeriod() }) }
  eq(#Attention.build(chars, off, inWindow), 0, "banked trigger off suppresses banked")

  -- summary: red beats amber, count is distinct chars
  chars = {
    ["H-X"] = F.char({ name="H", realm="X", hasPendingLoot=true, bestTier=2, period=F.maxedPeriod() }),
    ["I-X"] = F.char({ name="I", realm="X", bestTier=2, period=F.untouchedPeriod() }),
  }
  local s = Attention.summary(Attention.build(chars, settings, inWindow))
  eq(s.count, 2, "summary counts 2 chars")
  eq(s.color, "red", "summary color is red when any banked")

  -- sort comparator: red before amber, then by name ascending
  chars = {
    ["Zed-X"] = F.char({ name="Zed", realm="X", hasPendingLoot=true, bestTier=2, period=F.maxedPeriod() }),
    ["Bob-X"] = F.char({ name="Bob", realm="X", bestTier=2, period=F.untouchedPeriod() }),
    ["Ann-X"] = F.char({ name="Ann", realm="X", bestTier=2, period=F.untouchedPeriod() }),
  }
  list = Attention.build(chars, settings, inWindow)
  eq(list[1].name, "Zed", "sort: red entry first despite Z name")
  eq(list[1].severity, "red", "sort: first is red")
  eq(list[2].name, "Ann", "sort: amber by name, Ann before Bob")
  eq(list[3].name, "Bob", "sort: Bob last")

  -- window boundary + nil contract
  chars = { ["B-X"] = F.char({ name="B", realm="X", bestTier=2, period=F.untouchedPeriod() }) }
  eq(#Attention.build(chars, settings, 48 * HOUR), 1, "exactly 48h is inside window (inclusive)")
  eq(#Attention.build(chars, settings, nil), 0, "nil secondsToReset is out of window")

  -- untouched takes priority over incomplete: exactly one reason, not both
  chars = { ["U-X"] = F.char({ name="U", realm="X", bestTier=2, period=F.untouchedPeriod() }) }
  list = Attention.build(chars, settings, inWindow)
  eq(#list[1].reasons, 1, "untouched tracked has exactly one reason")
  eq(list[1].reasons[1], "untouched", "untouched, not incomplete")
end

-- ===== Presentation helpers (block meter, slot totals, banked best, tooltip) =====
do
  -- blockBar: quantize progress/threshold to `segments` filled glyphs
  eq(Derived.blockBar(0, 4, 4), "▱▱▱▱", "blockBar empty")
  eq(Derived.blockBar(2, 4, 4), "▰▰▱▱", "blockBar half (2/4)")
  eq(Derived.blockBar(2, 8, 4), "▰▱▱▱", "blockBar quarter (2/8)")
  eq(Derived.blockBar(1, 8, 4), "▰▱▱▱", "blockBar shows started even when <1 segment")
  eq(Derived.blockBar(4, 4, 4), "▰▰▰▰", "blockBar full")
  eq(Derived.blockBar(0, 0, 4), "▰▰▰▰", "blockBar guards threshold 0")

  -- periodSlots: unlocked / total across the 3 tracks
  local u, t = Derived.periodSlots(F.maxedPeriod())
  eq(u, 9, "periodSlots maxed unlocked"); eq(t, 9, "periodSlots maxed total")
  u, t = Derived.periodSlots(F.untouchedPeriod())
  eq(u, 0, "periodSlots untouched unlocked"); eq(t, 9, "periodSlots untouched total")
  u = Derived.periodSlots(F.partialPeriod())
  eq(u, 2, "periodSlots partial unlocked (raid1 + world1)")

  -- bankedBest: best ilvl across periods older than currentWeekId
  local banked = F.char({ weekId = 2000, period = F.untouchedPeriod() })
  banked.periods[1000] = F.maxedPeriod()  -- a prior banked period with detail
  eq(Derived.bankedBest(banked), 272, "bankedBest reads prior period detail")
  eq(Derived.bankedBest(F.char({ weekId = 2000, period = F.maxedPeriod() })), 0,
     "bankedBest 0 when no prior periods")

  -- tooltipReason
  local Format = ns.Format
  local bankedChar = F.char({ weekId = 2000, hasPendingLoot = true, period = F.untouchedPeriod() })
  bankedChar.periods[1000] = F.maxedPeriod()
  eq(Format.tooltipReason({ reasons = {"banked"} }, bankedChar), "banked loot, best 272",
     "tooltipReason banked with best")
  eq(Format.tooltipReason({ reasons = {"banked"} }, F.char({ hasPendingLoot = true, period = F.untouchedPeriod() })),
     "banked loot", "tooltipReason banked without known best")
  eq(Format.tooltipReason({ reasons = {"untouched"} }, F.char({ period = F.untouchedPeriod() })),
     "0/9", "tooltipReason untouched is just 0/9, no word")
  eq(Format.tooltipReason({ reasons = {"incomplete"} }, F.char({ period = F.partialPeriod() })),
     "2/9, best 272", "tooltipReason incomplete shows slots + best")

  -- summary: chat lines
  eq(Format.summary({}, {})[1], "|cff888888All caught up.|r", "summary empty -> all caught up")
  local sc = F.char({ name = "A", realm = "X", weekId = 1000, hasPendingLoot = true,
                      period = F.untouchedPeriod() })
  sc.periods[900] = F.maxedPeriod()  -- a banked prior period
  local sList = { { key = "A-X", name = "A", realm = "X", severity = "red", reasons = {"banked"} } }
  eq(Format.summary(sList, { ["A-X"] = sc })[1]:find("banked loot") ~= nil, true,
     "summary line mentions banked loot")
end

-- ===== Stale-character pruning =====
do
  local now = 1000000000
  local WEEK = 7 * 24 * 3600
  local chars = {
    ["Fresh-X"] = { lastScan = now },
    ["Old-X"]   = { lastScan = now - 6 * WEEK },
    ["Edge-X"]  = { lastScan = now - 4 * WEEK + 10 },  -- just inside the window
    ["None-X"]  = {},                                   -- never scanned
  }
  local stale = Derived.staleKeys(chars, now, 4)
  eq(stale["Old-X"], true, "staleKeys: 6wk old is stale")
  eq(stale["Fresh-X"], nil, "staleKeys: fresh is kept")
  eq(stale["Edge-X"], nil, "staleKeys: just inside window is kept")
  eq(stale["None-X"], true, "staleKeys: missing lastScan is stale")
  eq(Derived.staleKeys(chars, now, 4, "Old-X")["Old-X"], nil, "staleKeys respects keepKey")

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
end

-- ===== Countdown formatting (drop leading zero units, weekly 0..7d range) =====
do
  local Format = ns.Format
  eq(Format.countdown(6 * 86400 + 6 * 3600 + 30 * 60), "6d 6h 30m", "countdown days+hours+minutes")
  eq(Format.countdown(6 * 3600 + 30 * 60), "6h 30m", "countdown drops zero days")
  eq(Format.countdown(30 * 60), "30m", "countdown drops zero days+hours")
  eq(Format.countdown(6 * 86400 + 30 * 60), "6d 0h 30m", "countdown keeps middle zero hour")
  eq(Format.countdown(0), "0m", "countdown zero is 0m")
  eq(Format.countdown(86400 + 3599), "1d 0h 59m", "countdown truncates sub-minute")
end

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
