local ADDON, ns = ...
local Scanner = {}
ns.Scanner = Scanner

local TRACKS = {
  raid    = Enum.WeeklyRewardChestThresholdType.Raid,
  dungeon = Enum.WeeklyRewardChestThresholdType.Activities,
  world   = Enum.WeeklyRewardChestThresholdType.World,
}

-- Safely fetch an activity's example reward item link; nil on failure.
local function rewardLink(activityID)
  local ok, link = pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, activityID)
  if ok then return link end
  return nil
end

-- Reward item level from a link; 0 if unknown.
local function linkIlvl(link)
  if not link then return 0 end
  return C_Item.GetDetailedItemLevelInfo(link) or 0
end

-- Map a reward's "Upgrade Level: <Tier> x/y" line to an upgrade-track ordinal
-- (1-4); 0 if unreadable. Locale-safe: find the ItemUpgradeLevel tooltip line
-- (verified Enum.TooltipDataLineType.ItemUpgradeLevel == 32 on 12.x) and match the
-- localized tier name from ns.L. Anchoring to that line avoids matching "Myth"
-- inside the "Mythic+" line. No key-level/ilvl tables — the reward states its tier.
local UPGRADE_LINE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemUpgradeLevel) or 32
local TIER_BY_NAME
local function linkTier(link)
  if not link then return 0 end
  local data = C_TooltipInfo.GetHyperlink(link)
  if not data or not data.lines then return 0 end
  if not TIER_BY_NAME then
    local L = ns.L
    TIER_BY_NAME = { [L.TIER_VETERAN] = 1, [L.TIER_CHAMPION] = 2, [L.TIER_HERO] = 3, [L.TIER_MYTH] = 4 }
  end
  for _, line in ipairs(data.lines) do
    if line.type == UPGRADE_LINE and line.leftText then
      for name, ord in pairs(TIER_BY_NAME) do
        if line.leftText:find(name, 1, true) then return ord end
      end
    end
  end
  return 0
end

-- Read one track's tiers, sorted ascending by threshold (slot 1/2/3). Each earned
-- slot's reward link is fetched once and yields both its ilvl and its tier.
local function readTrack(thresholdType)
  local activities = C_WeeklyRewards.GetActivities(thresholdType) or {}
  local tiers = {}
  for _, a in ipairs(activities) do
    local link = (a.progress >= a.threshold) and rewardLink(a.id) or nil
    tiers[#tiers + 1] = {
      threshold = a.threshold,
      progress = a.progress,
      level = a.level or 0,
      raidString = a.raidString,  -- e.g. "1/8 Heroic" for raid tiers (nil otherwise)
      rewardIlvl = linkIlvl(link),
      rewardTier = linkTier(link),
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

  -- Period key = current period start, snapped to the minute grid so clock skew
  -- can't jitter the key and break the periods[key] overwrite (see Derived.periodKey).
  local now = time()
  local currentWeekId = Derived.periodKey(now, C_DateAndTime.GetSecondsUntilWeeklyReset())

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
  if specIndex then
    local _, specName, _, specIcon = GetSpecializationInfo(specIndex)
    entry.spec = specName
    entry.specIcon = specIcon
  else
    entry.spec, entry.specIcon = nil, nil
  end
  entry.ilvl = math.floor((select(2, GetAverageItemLevel())) or 0)
  entry.level = UnitLevel("player")
  entry.lastScan = now
  entry.hasPendingLoot = C_WeeklyRewards.HasAvailableRewards() and true or false
  entry.currentWeekId = currentWeekId
  entry.periods = entry.periods or {}
  entry.periods[currentWeekId] = period

  -- Season high-water reward tier: best earned tier seen this season, reset on M+
  -- season change (eligibility resets with it — re-earn after a season rollover).
  local season = C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason()
  if season and entry.bestTierSeason ~= season then
    entry.bestTier, entry.bestTierSeason, entry.eligible = 0, season, false
  end
  entry.bestTier = math.max(entry.bestTier or 0, Derived.bestEarnedTier(period))
  -- Sticky eligibility (presence in DB = source of truth): once the character has
  -- earned a reward at/above its line this season it stays tracked. effectiveTracked
  -- reads entry.eligible; it never drops live as the line changes.
  local line = Derived.effectiveLine(entry.trackTier, ns.db.global.settings.seriousness)
  entry.eligible = Derived.observeEligible(entry.eligible, entry.bestTier, line)
  entry.eligibleAt = nil  -- drop stale field

  -- Keep the current period + the single most-recent prior (banked) snapshot, drop
  -- older. Not gated on hasPendingLoot, so a transient post-reset false reading can't
  -- destroy last week's banked detail before the loot registers as available.
  Derived.prunePeriods(entry.periods, currentWeekId)

  -- Max-level persistence gate: only cache characters at the expansion cap, so
  -- leveling alts never enter the roster/attention. Cap-bump cleanup of characters
  -- stranded by a previous cap lives in Core:Prune (Derived.belowMaxKeys).
  if entry.level >= GetMaxLevelForPlayerExpansion() then
    chars[key] = entry
  end
  return entry
end
