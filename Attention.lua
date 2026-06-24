local ADDON, ns = ...
local Attention = {}
ns.Attention = Attention

local function hasReason(entry, reason)
  for _, r in ipairs(entry.reasons) do
    if r == reason then return true end
  end
  return false
end

-- characters: map "name-realm" -> char entry
-- settings: { thresholdHours, triggers = { banked, untouched, incomplete } }
-- secondsToReset: number or nil
-- now: epoch seconds (time()) or nil; enables the stale-alt "likely banked" inference
function Attention.build(characters, settings, secondsToReset, now)
  local Derived = ns.Derived
  local inWindow = secondsToReset ~= nil
    and secondsToReset <= settings.thresholdHours * 3600
  local realWeekId = now and Derived.periodKey(now, secondsToReset) or nil
  local byChar = {}

  local function add(key, char, reason)
    local e = byChar[key]
    if not e then
      e = { key = key, name = char.name, realm = char.realm, class = char.class, reasons = {} }
      byChar[key] = e
    end
    e.reasons[#e.reasons + 1] = reason
  end

  for key, char in pairs(characters) do
    -- "off" silences a character entirely. Otherwise confirmed banked loot surfaces
    -- regardless of eligibility (real, claimable loot you can lose); the inferred and
    -- soft reasons (likely-banked / untouched / incomplete) require the character be
    -- tracked (eligible).
    if char.trackTier ~= "off" then
      local tracked = Derived.effectiveTracked(char)
      if settings.triggers.banked then
        if char.hasPendingLoot then
          add(key, char, "banked")
        elseif tracked and realWeekId and Derived.likelyBanked(char, realWeekId) then
          add(key, char, "maybebanked")
        end
      end
      if tracked and inWindow then
        local period = Derived.currentPeriod(char)
        if period then
          if settings.triggers.untouched and Derived.isUntouched(period) then
            add(key, char, "untouched")
          elseif settings.triggers.incomplete then
            local line = Derived.effectiveLine(char.trackTier, settings.seriousness)
            local parts = Derived.partials(period, settings.nudgeGap or 1, line)
            if #parts > 0 then
              add(key, char, "incomplete")
              byChar[key].partials = parts
            end
          end
        end
      end
    end
  end

  local list = {}
  for _, e in pairs(byChar) do
    e.severity = hasReason(e, "banked") and "red" or "amber"
    list[#list + 1] = e
  end
  table.sort(list, function(a, b)
    if a.severity ~= b.severity then return a.severity == "red" end
    return a.name < b.name
  end)
  return list
end

function Attention.summary(list)
  local color = "none"
  for _, e in ipairs(list) do
    if e.severity == "red" then return { count = #list, color = "red" } end
    color = "amber"
  end
  return { count = #list, color = color }
end
