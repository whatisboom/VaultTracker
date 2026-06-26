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

  -- effectiveTracked: reads the stored sticky eligible flag, not live bestTier
  eq(Derived.effectiveTracked({ eligible = true, trackTier = nil }), true,
     "tracked: eligible flag set")
  eq(Derived.effectiveTracked({ eligible = false, trackTier = nil }), false,
     "tracked: not eligible")
  eq(Derived.effectiveTracked({ trackTier = nil }), false,
     "tracked: missing eligible treated as false")
  eq(Derived.effectiveTracked({ eligible = true, trackTier = "off" }), false,
     "tracked: 'off' is never tracked regardless of the flag")

  -- anyTracked: true iff at least one cached character is effectively tracked
  eq(Derived.anyTracked({}), false, "anyTracked: empty cache -> false")
  eq(Derived.anyTracked({ ["A-X"] = { eligible = false, trackTier = nil } }), false,
     "anyTracked: only an ineligible char -> false")
  eq(Derived.anyTracked({ ["A-X"] = { eligible = true, trackTier = "off" } }), false,
     "anyTracked: a lone 'off' char (even eligible) -> false")
  eq(Derived.anyTracked({
       ["A-X"] = { eligible = false, trackTier = nil },
       ["B-X"] = { eligible = true, trackTier = nil },
     }), true, "anyTracked: at least one tracked char -> true")

  -- observeEligible: sticky once true; becomes true the moment bestTier meets the line
  eq(Derived.observeEligible(true, 0, 4), true, "observeEligible sticky when prev true")
  eq(Derived.observeEligible(false, 3, 2), true, "observeEligible true on first qualify (hero >= champion)")
  eq(Derived.observeEligible(false, 1, 2), false, "observeEligible false below line + prev false")
  eq(Derived.observeEligible(nil, 0, 2), false, "observeEligible nil prev + nothing earned -> false")

  local char = F.char({ weekId = 1000, period = partial })
  eq(Derived.currentPeriod(char), partial, "currentPeriod returns the current weekId period")

  -- prunePeriods: keep current + most-recent prior, drop older (not gated on loot)
  local ps = { [3000] = maxed, [2000] = partial, [1000] = untouched }
  Derived.prunePeriods(ps, 3000)
  eq(ps[3000] ~= nil, true, "prune keeps current period")
  eq(ps[2000] ~= nil, true, "prune keeps the most-recent prior period")
  eq(ps[1000], nil, "prune drops older periods")
  local pcur = { [3000] = maxed }
  Derived.prunePeriods(pcur, 3000)
  eq(pcur[3000] ~= nil, true, "prune keeps a lone current period")

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

  -- confirmed banked loot surfaces regardless of eligibility, EXCEPT "off"
  chars = {
    ["Off-X"] = F.char({ name="Off", realm="X", hasPendingLoot=true, trackTier="off",
                         eligible=true, period=F.maxedPeriod() }),
  }
  eq(#Attention.build(chars, settings, outWindow), 0, "'off' banked is silent")
  chars = {
    ["Low-X"] = F.char({ name="Low", realm="X", hasPendingLoot=true, eligible=false,
                         period=F.maxedPeriod() }),
  }
  list = Attention.build(chars, settings, outWindow)
  eq(#list, 1, "below-line banked still surfaces (real loot)")
  eq(list[1].reasons[1], "banked", "...as banked")
  eq(list[1].severity, "red", "...red severity")

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

  -- actionable partial slot, tracked, inside window -> amber, reason incomplete + partials
  chars = {
    ["D-X"] = F.char({ name="D", realm="X", bestTier=2, period=F.nudgePeriod() }),
  }
  list = Attention.build(chars, settings, inWindow)
  eq(list[1].reasons[1], "incomplete", "actionable partial -> incomplete")
  eq(list[1].partials[1].track, "raid", "incomplete entry carries the partial track")
  eq(list[1].partials[1].remaining, 1, "incomplete entry carries remaining")

  -- not maxed but nothing close (dungeon 1/4 is 3 away, rest untouched) -> nothing
  local farPeriod = F.period(
    F.track(F.tier(2,0), F.tier(4,0), F.tier(6,0)),
    F.track(F.tier(1,1), F.tier(4,1), F.tier(8,1)),
    F.track(F.tier(2,0), F.tier(4,0), F.tier(8,0)))
  chars = {
    ["D2-X"] = F.char({ name="D2", realm="X", bestTier=2, period=farPeriod }),
  }
  eq(#Attention.build(chars, settings, inWindow), 0, "nothing within gap -> no nudge")

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

  -- bankedPeriod: the latest snapshot older than currentWeekId
  local banked = F.char({ weekId = 2000, period = F.untouchedPeriod() })
  banked.periods[900]  = F.partialPeriod()
  banked.periods[1000] = F.maxedPeriod()  -- newer prior period wins
  eq(Derived.bankedPeriod(banked), banked.periods[1000], "bankedPeriod picks latest prior")
  eq(Derived.bankedPeriod(F.char({ weekId = 2000, period = F.maxedPeriod() })), nil,
     "bankedPeriod nil when no prior periods")

  -- bankedRange: min, max, count of claimable banked slots
  local function rangeOf(period)
    local c = F.char({ weekId = 2000, period = F.untouchedPeriod() })
    c.periods[1000] = period
    return Derived.bankedRange(c)
  end
  local lo, hi, n = rangeOf(F.maxedPeriod())
  eq(lo, 264, "bankedRange maxed min"); eq(hi, 272, "bankedRange maxed max"); eq(n, 9, "bankedRange maxed count")
  lo, hi, n = rangeOf(F.partialPeriod())
  eq(lo, 259, "bankedRange partial min"); eq(hi, 272, "bankedRange partial max"); eq(n, 2, "bankedRange partial count")
  -- a single unlocked slot
  local oneSlot = F.period(
    F.track(F.tier(2,2,272), F.tier(4,0), F.tier(6,0)),
    F.track(F.tier(1,0), F.tier(4,0), F.tier(8,0)),
    F.track(F.tier(2,0), F.tier(4,0), F.tier(8,0)))
  lo, hi, n = rangeOf(oneSlot)
  eq(lo, 272, "bankedRange single min"); eq(hi, 272, "bankedRange single max"); eq(n, 1, "bankedRange single count")
  -- unlocked but no resolved ilvls -> no detail
  local noIlvl = F.period(
    F.track(F.tier(2,2,0), F.tier(4,4,0), F.tier(6,6,0)),
    F.track(F.tier(1,1,0), F.tier(4,4,0), F.tier(8,8,0)),
    F.track(F.tier(2,2,0), F.tier(4,4,0), F.tier(8,8,0)))
  lo, hi, n = rangeOf(noIlvl)
  eq(lo, 0, "bankedRange unresolved min"); eq(hi, 0, "bankedRange unresolved max"); eq(n, 0, "bankedRange unresolved count")
  lo, hi, n = Derived.bankedRange(F.char({ weekId = 2000, period = F.maxedPeriod() }))
  eq(n, 0, "bankedRange count 0 when no prior periods")

  -- a flat (all same ilvl) prior period for the flat-format checks below
  local flatPeriod = F.period(
    F.track(F.tier(2,2,272), F.tier(4,4,272), F.tier(6,6,272)),
    F.track(F.tier(1,1,272), F.tier(4,4,272), F.tier(8,8,272)),
    F.track(F.tier(2,2,272), F.tier(4,4,272), F.tier(8,8,272)))

  -- Format.bankedColumn: roster cell text
  local Format = ns.Format
  eq(Format.bankedColumn(259, 272, 2), "2: 259–272", "bankedColumn range")
  eq(Format.bankedColumn(272, 272, 9), "9: 272", "bankedColumn flat")
  eq(Format.bankedColumn(272, 272, 1), "1: 272", "bankedColumn single")
  eq(Format.bankedColumn(0, 0, 0), nil, "bankedColumn nil when none")

  -- tooltipReason: banked range / flat / single / none
  local bankedChar = F.char({ weekId = 2000, hasPendingLoot = true, period = F.untouchedPeriod() })
  bankedChar.periods[1000] = F.partialPeriod()
  eq(Format.tooltipReason({ reasons = {"banked"} }, bankedChar), "banked loot, 2 items 259–272",
     "tooltipReason banked range")
  local flatChar = F.char({ weekId = 2000, hasPendingLoot = true, period = F.untouchedPeriod() })
  flatChar.periods[1000] = flatPeriod
  eq(Format.tooltipReason({ reasons = {"banked"} }, flatChar), "banked loot, 9 items 272",
     "tooltipReason banked flat")
  local oneChar = F.char({ weekId = 2000, hasPendingLoot = true, period = F.untouchedPeriod() })
  oneChar.periods[1000] = oneSlot
  eq(Format.tooltipReason({ reasons = {"banked"} }, oneChar), "banked loot, 1 item 272",
     "tooltipReason banked single")
  eq(Format.tooltipReason({ reasons = {"banked"} }, F.char({ hasPendingLoot = true, period = F.untouchedPeriod() })),
     "banked loot", "tooltipReason banked without known detail")
  eq(Format.tooltipReason({ reasons = {"untouched"} }, F.char({ period = F.untouchedPeriod() })),
     "0/9", "tooltipReason untouched is just 0/9, no word")
  eq(Format.tooltipReason({ reasons = {"incomplete"}, partials = {{track="dungeon", remaining=1}} },
     F.char({ period = F.partialPeriod() })), "1 more Mythic+", "tooltipReason incomplete is the nudge action")

  -- summary: chat lines
  eq(Format.summary({}, {})[1], "|cff888888All caught up.|r", "summary empty -> all caught up")
  local sc = F.char({ name = "A", realm = "X", weekId = 1000, hasPendingLoot = true,
                      period = F.untouchedPeriod() })
  sc.periods[900] = F.maxedPeriod()  -- a banked prior period
  local sList = { { key = "A-X", name = "A", realm = "X", severity = "red", reasons = {"banked"} } }
  eq(Format.summary(sList, { ["A-X"] = sc })[1]:find("banked loot") ~= nil, true,
     "summary line mentions banked loot")
end

-- ===== Actionable partial-slot nudges =====
do
  local Derived = ns.Derived
  local Format = ns.Format
  local T = F.track
  local ti = F.tier

  -- partialSlot: remaining-to-next when partway in and within maxGap; nil otherwise
  local raid12 = T(ti(2,1), ti(4,1), ti(6,1))   -- 1/2 raid
  eq(Derived.partialSlot(raid12, 2), 1, "raid 1/2 -> 1 more")
  eq(Derived.partialSlot(raid12, 1), 1, "raid 1/2 within gap 1")
  eq(Derived.partialSlot(T(ti(2,2), ti(4,2), ti(6,2)), 2), 2, "raid 2 -> slot2 is 2/4, 2 more")
  eq(Derived.partialSlot(T(ti(2,3), ti(4,3), ti(6,3)), 2), 1, "raid 3 -> 1 more for slot2")
  -- the Sinlengua world case: slot1 done (2/2), slot2 reads 2/4 -> 2 more within gap 2
  eq(Derived.partialSlot(T(ti(2,2), ti(4,2), ti(8,2)), 2), 2, "world 2/4 -> 2 more (gap 2)")
  eq(Derived.partialSlot(T(ti(1,1), ti(4,1), ti(8,1)), 2), nil, "dungeon 1 -> slot2 is 1/4, 3 away (outside gap 2)")
  eq(Derived.partialSlot(T(ti(1,1), ti(4,1), ti(8,1)), 3), 3, "dungeon 1 -> 1/4 reachable at gap 3")
  eq(Derived.partialSlot(T(ti(1,2), ti(4,2), ti(8,2)), 1), nil, "dungeon 2/4 outside gap 1")
  eq(Derived.partialSlot(T(ti(1,5), ti(4,5), ti(8,5)), 3), 3, "dungeon 5/8 -> 3 more (gap 3)")
  eq(Derived.partialSlot(T(ti(1,5), ti(4,5), ti(8,5)), 2), nil, "dungeon 5/8 outside gap 2")
  eq(Derived.partialSlot(T(ti(1,8), ti(4,8), ti(8,8)), 3), nil, "dungeon maxed -> nil")
  eq(Derived.partialSlot(T(ti(2,0), ti(4,0), ti(8,0)), 3), nil, "untouched -> nil")

  -- partials: across tracks, in raid/dungeon/world order
  local period = F.period(
    T(ti(2,1), ti(4,1), ti(6,1)),   -- raid 1/2 -> 1
    T(ti(1,1), ti(4,1), ti(8,1)),   -- dungeon clean -> none
    T(ti(2,3), ti(4,3), ti(8,3)))   -- world 3 -> 1 more for slot2
  local parts = Derived.partials(period, 2)
  eq(#parts, 2, "two tracks have actionable partials")
  eq(parts[1].track, "raid", "raid listed first"); eq(parts[1].remaining, 1, "raid remaining")
  eq(parts[2].track, "world", "world listed second"); eq(parts[2].remaining, 1, "world remaining")

  -- partialPhrase: per-track wording, singular/plural
  eq(Format.partialPhrase("raid", 1), "1 more raid boss", "raid singular")
  eq(Format.partialPhrase("raid", 2), "2 more raid bosses", "raid plural")
  eq(Format.partialPhrase("dungeon", 1), "1 more Mythic+", "dungeon")
  eq(Format.partialPhrase("dungeon", 3), "3 more Mythic+", "dungeon plural-invariant")
  eq(Format.partialPhrase("world", 1), "1 more world activity", "world singular")
  eq(Format.partialPhrase("world", 3), "3 more world activities", "world plural")

  -- nudgeText joins phrases with commas
  eq(Format.nudgeText({{track="raid", remaining=1}, {track="world", remaining=2}}),
     "1 more raid boss, 2 more world activities", "nudgeText combines tracks")
end

-- ===== Nudge gate: track's earned tier vs the seriousness line =====
do
  local Derived = ns.Derived
  local Attention = ns.Attention
  local T, ti = F.track, F.tier

  -- trackEarnedTier: max earned rewardTier in one track, 0 if none
  eq(Derived.trackEarnedTier(T(ti(2,3,259,3), ti(4,0), ti(6,0))), 3, "trackEarnedTier reads earned slot")
  eq(Derived.trackEarnedTier(T(ti(2,1), ti(4,1), ti(6,1))), 0, "trackEarnedTier 0 when nothing earned")

  -- partialSlot gate: only nudge a track that's revealed a tier at/above the line
  local raidHero  = T(ti(2,3,259,3), ti(4,3,0,0), ti(6,3,0,0))  -- slot1 Hero earned, slot2 3/4
  local raidVet   = T(ti(2,3,243,1), ti(4,3,0,0), ti(6,3,0,0))  -- slot1 Veteran earned, slot2 3/4
  local raidFirst = T(ti(2,1), ti(4,1), ti(6,1))                -- 1/2, nothing earned
  eq(Derived.partialSlot(raidHero, 1, 2), 1, "earned Hero >= champion line -> nudge")
  eq(Derived.partialSlot(raidHero, 1, 4), nil, "earned Hero < myth line -> gated")
  eq(Derived.partialSlot(raidVet, 1, 2), nil, "earned Veteran < champion line -> gated")
  eq(Derived.partialSlot(raidFirst, 1, 2), nil, "no earned slot -> gated (first slot unknowable)")
  eq(Derived.partialSlot(raidFirst, 1), 1, "no line -> no gate (back-compat)")

  -- partials threads the line, dropping only gated tracks
  local period = F.period(
    raidVet,                                      -- earned Veteran -> gated at champion
    T(ti(1,3,272,4), ti(4,3,0,0), ti(8,3,0,0)),   -- dungeon slot1 Myth earned, slot2 3/4 -> nudge
    T(ti(2,0), ti(4,0), ti(8,0)))
  local parts = Derived.partials(period, 1, 2)
  eq(#parts, 1, "only the line-worthy track nudges")
  eq(parts[1].track, "dungeon", "dungeon (Myth) survives the gate")

  -- Attention end-to-end (champion line; char tracked via bestTier 4)
  local settings = { thresholdHours = 48, seriousness = "champion",
                     triggers = { banked = true, untouched = true, incomplete = true } }
  local inWindow = 10 * 3600
  local function attn(p)
    return Attention.build({ ["G-X"] = F.char({ name="G", realm="X", bestTier=4, period=p }) },
      settings, inWindow)
  end
  local function rp(raid) return F.period(raid, T(ti(1,0),ti(4,0),ti(8,0)), T(ti(2,0),ti(4,0),ti(8,0))) end
  eq(#attn(rp(raidFirst)), 0, "first-slot raid (nothing earned) is not nudged")
  eq(#attn(rp(raidVet)), 0, "earned-Veteran raid below line is not nudged")
  local l = attn(rp(raidHero))
  eq(#l, 1, "earned-Hero raid at/above line nudges")
  eq(l[1].reasons[1], "incomplete", "...as incomplete")
end

-- ===== Inferred ("likely banked") loot for stale alts =====
do
  local Derived = ns.Derived
  local Format = ns.Format
  local Attention = ns.Attention
  local WEEK = 7 * 24 * 3600

  -- periodRange: the shared helper bankedRange and the inference both build on
  local lo, hi, n = Derived.periodRange(F.partialPeriod())
  eq(lo, 259, "periodRange partial min"); eq(hi, 272, "periodRange partial max"); eq(n, 2, "periodRange partial count")

  -- likelyBanked: exactly one reset stale AND had unlocked slots when last seen
  local realWk = 600000
  eq(Derived.likelyBanked(F.char({ weekId = realWk - WEEK, period = F.partialPeriod() }), realWk), true,
     "stale by one week with unlocked slots -> likely")
  eq(Derived.likelyBanked(F.char({ weekId = realWk - WEEK, period = F.untouchedPeriod() }), realWk), false,
     "stale but nothing unlocked -> not likely")
  eq(Derived.likelyBanked(F.char({ weekId = realWk, period = F.partialPeriod() }), realWk), false,
     "scanned this week -> not likely")
  eq(Derived.likelyBanked(F.char({ weekId = realWk - 2 * WEEK, period = F.partialPeriod() }), realWk), false,
     "two resets stale -> not likely (loot likely cleared)")
  eq(Derived.likelyBanked(F.char({ weekId = realWk - WEEK, hasPendingLoot = true, period = F.partialPeriod() }), realWk),
     false, "confirmed pending loot is owned by the banked path, not inferred")

  -- tooltipReason for the inferred reason reads the stale current period
  local mc = F.char({ weekId = realWk - WEEK, period = F.partialPeriod() })
  eq(Format.tooltipReason({ reasons = {"maybebanked"} }, mc), "likely banked loot, 2 items 259–272",
     "tooltipReason maybebanked range")

  -- marker glyphs: "!" confirmed, "?" inferred, "-" time-pressure
  eq(Format.marker({ severity = "red", reasons = {"banked"} }), "|cffff5555!|r", "marker confirmed")
  eq(Format.marker({ severity = "amber", reasons = {"maybebanked"} }), "|cfff2c24a?|r", "marker inferred")
  eq(Format.marker({ severity = "amber", reasons = {"incomplete"} }), "|cfff2c24a-|r", "marker time-pressure")

  -- Attention.build wires the inference (folded into the banked trigger), amber
  local settings = { thresholdHours = 48, seriousness = "champion",
                     triggers = { banked = true, untouched = true, incomplete = true } }
  local NOW, sReset = 2000000, 200 * 3600       -- outside the 48h window -> isolate maybebanked
  local rwk = Derived.periodKey(NOW, sReset)
  local chars = {
    ["S-X"] = F.char({ name = "S", realm = "X", weekId = rwk - WEEK, bestTier = 3, period = F.partialPeriod() }),
  }
  local list = Attention.build(chars, settings, sReset, NOW)
  eq(#list, 1, "stale alt produces one attention entry")
  eq(list[1].reasons[1], "maybebanked", "inferred reason is maybebanked")
  eq(list[1].severity, "amber", "inferred banked is amber")
  eq(Attention.summary(list).color, "amber", "inferred banked badge is amber")
  eq(#Attention.build(chars, settings, sReset), 0, "no now arg -> inference off")
  eq(#Attention.build(chars, settings, nil, NOW), 0, "nil reset timer -> inference off (no misaligned weekId)")
  local off = { thresholdHours = 48, seriousness = "champion",
                triggers = { banked = false, untouched = true, incomplete = true } }
  eq(#Attention.build(chars, off, sReset, NOW), 0, "banked trigger off suppresses inference")
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
