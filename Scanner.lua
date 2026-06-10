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
  local ok, itemLink = pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, activityID)
  if not ok or not itemLink then return 0 end
  local ilvl = C_Item.GetDetailedItemLevelInfo(itemLink)
  return ilvl or 0
end

-- Read one track's tiers, sorted ascending by threshold (slot 1/2/3).
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

  -- Period key = start epoch of the current period = next reset minus one week.
  local secondsToReset = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
  local now = time()
  local WEEK = 7 * 24 * 3600
  local currentWeekId = (now + secondsToReset) - WEEK

  local period = { tracks = {
    raid = readTrack(TRACKS.raid),
    dungeon = readTrack(TRACKS.dungeon),
    world = readTrack(TRACKS.world),
  } }

  local entry = chars[key] or { periods = {} }
  entry.name = name
  entry.realm = realm
  entry.class = UnitClassBase("player")
  local specIndex = GetSpecialization and GetSpecialization()
  entry.spec = specIndex and select(2, GetSpecializationInfo(specIndex)) or nil
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
