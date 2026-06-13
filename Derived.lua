local ADDON, ns = ...
local Derived = {}
ns.Derived = Derived

local WEEK = 7 * 24 * 3600

-- Stable period key for the current weekly-reward period.
-- now = epoch seconds (time()); secondsToReset = C_DateAndTime.GetSecondsUntilWeeklyReset().
-- The two terms reconstruct the next reset instant; we snap it to the minute
-- grid (weekly resets land on minute boundaries) so sub-minute skew between the
-- two integer clocks can't shift the key and break the periods[key] overwrite.
function Derived.periodKey(now, secondsToReset)
  local resetAt = now + (secondsToReset or 0)
  resetAt = math.floor((resetAt + 30) / 60) * 60
  return resetAt - WEEK
end

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

-- True iff a character has earned something (bestTier > 0) at or above the line.
function Derived.qualifies(bestTier, line)
  return bestTier > 0 and bestTier >= line
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

-- A quantized block meter for an unearned slot's progress toward its threshold.
-- Returns a string of `segments` glyphs: filled (U+25B0) then empty (U+25B1).
-- Any progress > 0 shows at least one filled segment ("started").
function Derived.blockBar(progress, threshold, segments)
  segments = segments or 4
  local frac = (threshold and threshold > 0) and (progress / threshold) or 1
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local filled = math.floor(frac * segments + 0.5)
  if progress and progress > 0 and filled == 0 then filled = 1 end
  if filled > segments then filled = segments end
  return string.rep("▰", filled) .. string.rep("▱", segments - filled)
end

-- Unlocked slot count and total slot count across all three tracks of a period.
function Derived.periodSlots(period)
  local unlocked, total = 0, 0
  for _, track in pairs(period.tracks) do
    total = total + #track
    unlocked = unlocked + Derived.slotsUnlocked(track)
  end
  return unlocked, total
end

-- Keys of characters not scanned within `weeks` (a set). `keepKey` is never
-- included (e.g. the current character). A missing lastScan counts as stale.
function Derived.staleKeys(characters, now, weeks, keepKey)
  local cutoff = now - weeks * 7 * 24 * 3600
  local out = {}
  for key, char in pairs(characters) do
    if key ~= keepKey and (char.lastScan or 0) < cutoff then
      out[key] = true
    end
  end
  return out
end

-- Best reward ilvl across banked (prior-period) snapshots; 0 if none have detail.
function Derived.bankedBest(char)
  local best = 0
  if not char.periods then return 0 end
  local current = char.currentWeekId or math.huge
  for wk, period in pairs(char.periods) do
    if wk < current then
      local b = Derived.bestIlvl(period)
      if b > best then best = b end
    end
  end
  return best
end
