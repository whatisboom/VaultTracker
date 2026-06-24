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

-- Activities remaining to finish the lowest unmet slot, when it's started (some
-- progress) and within `maxGap` of unlocking. nil for untouched (lowest unmet slot
-- has no progress), maxed, or a partial still farther than maxGap. Progress is the
-- cumulative count the API/UI shows for that slot (each activity counts toward every
-- higher slot), so a world slot reading 2/4 returns 2. Whether a slot whose count
-- equals a lower slot's threshold nudges is decided purely by maxGap (e.g. 2/4 is in
-- reach at gap 2; dungeon 1/4 is 3 away, so it stays quiet).
function Derived.partialSlot(track, maxGap, line)
  -- Gate (mirrors the seriousness gate): only nudge a track once it has revealed a
  -- tier at/above the line by EARNING a slot. The reward of an unearned slot is
  -- unknowable until earned, so a track with nothing earned (its first slot) never
  -- nudges. nil `line` = no gate (back-compat).
  if Derived.trackEarnedTier(track) < (line or 0) then return nil end
  for _, tier in ipairs(track) do
    if tier.progress < tier.threshold then
      local remaining = tier.threshold - tier.progress
      if tier.progress > 0 and remaining <= maxGap then return remaining end
      return nil
    end
  end
  return nil
end

-- Max earned reward tier within a single track (0 if nothing earned). Reveals the
-- difficulty the character is running in that track this week.
function Derived.trackEarnedTier(track)
  local best = 0
  for _, tier in ipairs(track) do
    if tier.progress >= tier.threshold and (tier.rewardTier or 0) > best then
      best = tier.rewardTier
    end
  end
  return best
end

local PARTIAL_ORDER = { "raid", "dungeon", "world" }

-- Actionable partial slots across a period's tracks, in display order:
-- { { track = "raid", remaining = 1 }, ... }. Empty when nothing is close.
function Derived.partials(period, maxGap, line)
  local out = {}
  for _, tk in ipairs(PARTIAL_ORDER) do
    local track = period.tracks[tk]
    if track then
      local remaining = Derived.partialSlot(track, maxGap, line)
      if remaining then out[#out + 1] = { track = tk, remaining = remaining } end
    end
  end
  return out
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

-- Resolve a character's tier line to an ordinal. nil (auto) -> account default.
-- Always returns an ordinal; "off" is handled by effectiveTracked, not here, so a
-- stray "off" falls back to the account default rather than erroring.
function Derived.effectiveLine(trackTier, accountDefault)
  local name = (trackTier and trackTier ~= "off") and trackTier or accountDefault
  return Derived.TIER[name] or Derived.TIER.champion
end

-- The display/attention gate: is this character currently tracked? Reads the stored
-- sticky `eligible` flag (set by Scanner once the character earned a reward at/above
-- its line; reset on season rollover; presence in the DB is the source of truth).
-- "off" silences everywhere regardless of the flag.
function Derived.effectiveTracked(entry)
  return entry.trackTier ~= "off" and entry.eligible == true
end

-- Sticky eligibility: once true it stays true; otherwise becomes true the moment
-- bestTier meets the line. Scanner folds this in on each scan. Explicit changes
-- (account threshold dialog, per-character override) recompute non-stickily via
-- qualifies(bestTier, effectiveLine(...)).
function Derived.observeEligible(prev, bestTier, line)
  return prev == true or Derived.qualifies(bestTier or 0, line)
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

function Derived.currentPeriod(char)
  return char.periods and char.periods[char.currentWeekId] or nil
end

-- Retain the current period and the single most-recent prior (banked) snapshot; drop
-- anything older. Mutates `periods` in place. Pruning is NOT tied to hasPendingLoot:
-- the first scan after a reset can briefly read it false before reward data loads,
-- which would destroy last week's banked detail. The banked display is gated on
-- hasPendingLoot, so a retained-but-claimed period never shows.
function Derived.prunePeriods(periods, currentWeekId)
  local prior = nil
  for wk in pairs(periods) do
    if wk < currentWeekId and (not prior or wk > prior) then prior = wk end
  end
  for wk in pairs(periods) do
    if wk ~= currentWeekId and wk ~= prior then periods[wk] = nil end
  end
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

-- The latest banked (prior-period) snapshot, or nil. The game holds only the most
-- recent week's unclaimed loot, so the highest weekId below currentWeekId is what's
-- actually sitting in the vault.
function Derived.bankedPeriod(char)
  if not char.periods then return nil end
  local current = char.currentWeekId or math.huge
  local bestWk, bestPeriod = nil, nil
  for wk, period in pairs(char.periods) do
    if wk < current and (not bestWk or wk > bestWk) then bestWk, bestPeriod = wk, period end
  end
  return bestPeriod
end

-- min, max, count of a period's claimable reward ilvls (unlocked slots with a
-- resolved rewardIlvl). Returns 0, 0, 0 when none resolve.
function Derived.periodRange(period)
  local min, max, count = math.huge, 0, 0
  for _, track in pairs(period.tracks) do
    for _, tier in ipairs(track) do
      if tier.progress >= tier.threshold and (tier.rewardIlvl or 0) > 0 then
        local il = tier.rewardIlvl
        if il < min then min = il end
        if il > max then max = il end
        count = count + 1
      end
    end
  end
  if count == 0 then return 0, 0, 0 end
  return min, max, count
end

-- min, max, count of the latest banked period's claimable ilvls; 0,0,0 when none.
function Derived.bankedRange(char)
  local period = Derived.bankedPeriod(char)
  if not period then return 0, 0, 0 end
  return Derived.periodRange(period)
end

-- Heuristic: an alt probably has unclaimed loot we can't confirm. True when the
-- character hasn't been scanned since the most recent reset (its cached period is
-- exactly one week stale) yet had unlocked slots when last seen. Limited to one
-- missed reset, since the game only holds the most recent week's unclaimed loot.
-- Excludes characters with confirmed pending loot (the "banked" path owns those).
-- realWeekId = Derived.periodKey(now, secondsToReset).
function Derived.likelyBanked(char, realWeekId)
  if char.hasPendingLoot then return false end
  local cwk = char.currentWeekId
  if not cwk or (realWeekId - cwk) ~= WEEK then return false end
  local period = char.periods and char.periods[cwk]
  if not period then return false end
  return (Derived.periodSlots(period)) > 0
end
