-- Reusable cache/period fixtures for tests. Pure data, no WoW globals.
local F = {}

-- A track is 3 tiers ascending by threshold.
local function track(t1, t2, t3) return { t1, t2, t3 } end
local function tier(threshold, progress, rewardIlvl)
  return { threshold = threshold, progress = progress, level = 0, rewardIlvl = rewardIlvl or 0 }
end
F.track, F.tier = track, tier

-- period with given progress per track
function F.period(raid, dungeon, world)
  return { tracks = { raid = raid, dungeon = dungeon, world = world } }
end

-- An untouched current period (all progress 0).
function F.untouchedPeriod()
  return F.period(
    track(tier(2,0), tier(4,0), tier(6,0)),
    track(tier(1,0), tier(4,0), tier(8,0)),
    track(tier(2,0), tier(4,0), tier(8,0)))
end

-- A fully maxed current period.
function F.maxedPeriod()
  return F.period(
    track(tier(2,2,272), tier(4,4,268), tier(6,6,264)),
    track(tier(1,1,272), tier(4,4,268), tier(8,8,264)),
    track(tier(2,2,272), tier(4,4,268), tier(8,8,264)))
end

-- A partial period: some slots unlocked, not all.
function F.partialPeriod()
  return F.period(
    track(tier(2,2,259), tier(4,0), tier(6,0)),
    track(tier(1,0), tier(4,0), tier(8,0)),
    track(tier(2,2,272), tier(4,2), tier(8,2)))
end

-- Build a character entry around a current period.
function F.char(opts)
  local weekId = opts.weekId or 1000
  return {
    name = opts.name or "Veyra",
    realm = opts.realm or "Fenris",
    class = opts.class or "PRIEST",
    ilvl = opts.ilvl or 148,
    hasPendingLoot = opts.hasPendingLoot or false,
    eligible = opts.eligible or false,
    eligibleAt = opts.eligibleAt,
    currentWeekId = weekId,
    periods = { [weekId] = opts.period or F.untouchedPeriod() },
  }
end

return F
