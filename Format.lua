local ADDON, ns = ...
local Format = {}
ns.Format = Format

local function has(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

-- The right-hand reason text for one tooltip line.
-- banked dominates (urgent, separate axis); otherwise the slot fraction carries
-- the touched/incomplete state, so no "untouched"/"incomplete" words. `best` is
-- appended only when some reward is actually claimable.
function Format.tooltipReason(entry, char)
  local Derived = ns.Derived
  local L = ns.L
  if has(entry.reasons, "banked") then
    local best = Derived.bankedBest(char)
    if best > 0 then return (L.REASON_BANKED_BEST):format(best) end
    return L.REASON_BANKED
  end
  local period = Derived.currentPeriod(char)
  if not period then return "" end
  local unlocked, total = Derived.periodSlots(period)
  if unlocked == 0 then
    return (L.REASON_SLOTS):format(unlocked, total)
  end
  local best = Derived.bestIlvl(period)
  if best > 0 then
    return (L.REASON_SLOTS_BEST):format(unlocked, total, best)
  end
  return (L.REASON_SLOTS):format(unlocked, total)
end

-- The login chat-summary lines: one per character needing attention, or a single
-- "all caught up" line when the attention list is empty.
function Format.summary(list, chars)
  local L = ns.L
  if #list == 0 then
    return { ("|cff888888%s|r"):format(L.SUMMARY_DONE) }
  end
  local out = {}
  for _, e in ipairs(list) do
    local marker = (e.severity == "red") and "|cffff5555!|r" or "|cfff2c24a-|r"
    out[#out + 1] = (L.SUMMARY_LINE):format(marker, e.name, e.realm,
      Format.tooltipReason(e, chars[e.key]))
  end
  return out
end
