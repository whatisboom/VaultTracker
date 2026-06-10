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
