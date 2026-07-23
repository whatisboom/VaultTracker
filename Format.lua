local ADDON, ns = ...
local Format = {}
ns.Format = Format

local function has(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

-- "<prefix>, N items lo–hi" (collapsing to one ilvl or just the prefix).
function Format.rangeReason(prefix, min, max, count)
  local L = ns.L
  if count == 0 then return prefix end
  if count == 1 then return (L.REASON_RANGE_ONE):format(prefix, min) end
  if min == max then return (L.REASON_RANGE_FLAT):format(prefix, count, min) end
  return (L.REASON_RANGE):format(prefix, count, min, max)
end

-- The list marker glyph for an attention entry: "!" banked (red, urgent),
-- "-" time-pressure (amber).
function Format.marker(entry)
  if entry.severity == "red" then return "|cffff5555!|r" end
  return "|cfff2c24a-|r"
end

-- The right-hand reason text for one tooltip line.
-- banked dominates (urgent, separate axis); otherwise the slot fraction carries
-- the touched/incomplete state, so no "untouched"/"incomplete" words. `best` is
-- appended only when some reward is actually claimable. bankedRange reads whichever
-- period actually holds the banked slots (this session's live scan or a stale alt's
-- last known one), so a stale alt's banked loot reports the same way as a confirmed one.
function Format.tooltipReason(entry, char)
  local Derived = ns.Derived
  local L = ns.L
  if has(entry.reasons, "banked") then
    local min, max, count = Derived.bankedRange(char)
    if count == 0 then
      local period = Derived.currentPeriod(char)
      if period then min, max, count = Derived.periodRange(period) end
    end
    return Format.rangeReason(L.REASON_BANKED, min, max, count)
  end
  if has(entry.reasons, "incomplete") and entry.partials then
    return Format.nudgeText(entry.partials)
  end
  local period = Derived.currentPeriod(char)
  if not period then return "" end
  local unlocked, total = Derived.periodSlots(period)
  return (L.REASON_SLOTS):format(unlocked, total)
end

-- The per-track action phrase for a partial slot, e.g. "1 more raid boss".
function Format.partialPhrase(track, n)
  local L = ns.L
  if track == "raid" then return ((n == 1) and L.NUDGE_RAID_ONE or L.NUDGE_RAID):format(n) end
  if track == "dungeon" then return (L.NUDGE_DUNGEON):format(n) end
  return ((n == 1) and L.NUDGE_WORLD_ONE or L.NUDGE_WORLD):format(n)  -- world (incl. delves)
end

-- The full nudge line for a character: the partial phrases joined with commas.
function Format.nudgeText(partials)
  local out = {}
  for _, p in ipairs(partials) do
    out[#out + 1] = Format.partialPhrase(p.track, p.remaining)
  end
  return table.concat(out, ", ")
end

-- The roster Banked column cell: "ilvl" or "lo–hi" when multiple slots resolved to
-- different ilvls, or nil when there's nothing banked (caller renders the empty
-- dash). Slot count isn't shown inline (it's in the hover tooltip) — the cell is
-- just the ilvl a player would actually care about at a glance.
function Format.bankedColumn(min, max, count)
  local L = ns.L
  if count == 0 then return nil end
  if count == 1 or min == max then return (L.ROSTER_BANKED_FLAT):format(min) end
  return (L.ROSTER_BANKED_RANGE):format(min, max)
end

-- A "Xd Yh Zm" countdown from a second count, dropping leading zero units (a
-- 6-hour gap reads "6h 30m", not "0d 6h 30m"). Once the highest non-zero unit is
-- shown, lower units follow even when zero ("6d 0h 30m"). Sub-minute remainders
-- are truncated; zero is "0m".
function Format.countdown(secs)
  local L = ns.L
  local days = math.floor(secs / 86400)
  local hours = math.floor((secs % 86400) / 3600)
  local minutes = math.floor((secs % 3600) / 60)
  if days > 0 then
    return ("%s %s %s"):format(
      (L.COUNTDOWN_D):format(days), (L.COUNTDOWN_H):format(hours), (L.COUNTDOWN_M):format(minutes))
  elseif hours > 0 then
    return ("%s %s"):format((L.COUNTDOWN_H):format(hours), (L.COUNTDOWN_M):format(minutes))
  end
  return (L.COUNTDOWN_M):format(minutes)
end

-- The login chat-summary lines: one per character needing attention, or a single
-- "all caught up" line when the attention list is empty. A not-tracked character
-- (surfaced only because of banked loot) gets its name-realm muted, matching the
-- roster and minimap tooltip.
function Format.summary(list, chars)
  local L = ns.L
  if #list == 0 then
    return { ("|cff888888%s|r"):format(L.SUMMARY_DONE) }
  end
  local out = {}
  for _, e in ipairs(list) do
    local nameRealm = ("%s-%s"):format(e.name, e.realm)
    if not e.tracked then nameRealm = ("|cff6a6453%s|r"):format(nameRealm) end
    out[#out + 1] = (L.SUMMARY_LINE):format(Format.marker(e), nameRealm,
      Format.tooltipReason(e, chars[e.key]))
  end
  return out
end
