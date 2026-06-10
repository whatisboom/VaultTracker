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
