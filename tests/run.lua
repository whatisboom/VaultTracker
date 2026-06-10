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
end
-- ============ Derived tests filled in Task 3 ============
-- ============ Attention tests filled in Task 5 ============

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
