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

  -- sort comparator: red before amber, then by name ascending
  chars = {
    ["Zed-X"] = F.char({ name="Zed", realm="X", hasPendingLoot=true, period=F.maxedPeriod() }),
    ["Bob-X"] = F.char({ name="Bob", realm="X", eligible=true, period=F.untouchedPeriod() }),
    ["Ann-X"] = F.char({ name="Ann", realm="X", eligible=true, period=F.untouchedPeriod() }),
  }
  list = Attention.build(chars, settings, inWindow)
  eq(list[1].name, "Zed", "sort: red entry first despite Z name")
  eq(list[1].severity, "red", "sort: first is red")
  eq(list[2].name, "Ann", "sort: amber by name, Ann before Bob")
  eq(list[3].name, "Bob", "sort: Bob last")

  -- window boundary + nil contract
  chars = { ["B-X"] = F.char({ name="B", realm="X", eligible=true, period=F.untouchedPeriod() }) }
  eq(#Attention.build(chars, settings, 48 * HOUR), 1, "exactly 48h is inside window (inclusive)")
  eq(#Attention.build(chars, settings, nil), 0, "nil secondsToReset is out of window")

  -- untouched takes priority over incomplete: exactly one reason, not both
  chars = { ["U-X"] = F.char({ name="U", realm="X", eligible=true, period=F.untouchedPeriod() }) }
  list = Attention.build(chars, settings, inWindow)
  eq(#list[1].reasons, 1, "untouched eligible has exactly one reason")
  eq(list[1].reasons[1], "untouched", "untouched, not incomplete")
end

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
