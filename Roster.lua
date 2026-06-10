local ADDON, ns = ...
local Roster = {}
ns.Roster = Roster

local AceGUI = LibStub("AceGUI-3.0")
local TRACK_ORDER = { "raid", "dungeon", "world" }
local TRACK_LABEL = { raid = "Raid", dungeon = "Dungeon", world = "World" }

local function classColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.colorStr end
  return "ffffffff"
end

local function trackLine(track)
  local dots = {}
  for i = 1, #track do
    dots[i] = (track[i].progress >= track[i].threshold) and "|cff33ff33O|r" or "|cff555555o|r"
  end
  local ilvls = ns.Derived.slotIlvls(track)
  local parts = {}
  for i = 1, #ilvls do parts[i] = ilvls[i] > 0 and tostring(ilvls[i]) or "--" end
  return table.concat(dots, "") .. "  " .. table.concat(parts, " / ")
end

function Roster:Build()
  local Derived = ns.Derived
  local frame = AceGUI:Create("Frame")
  frame:SetTitle("VaultTracker — Roster")
  frame:SetLayout("Fill")
  frame:SetCallback("OnClose", function(widget) AceGUI:Release(widget); Roster.frame = nil end)
  self.frame = frame

  -- A single ScrollFrame fills the window so a long roster scrolls.
  local scroll = AceGUI:Create("ScrollFrame")
  scroll:SetLayout("List")
  frame:AddChild(scroll)

  -- Sort: eligible first, then by name.
  local keys = {}
  for key in pairs(ns.db.global.characters) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    local ca, cb = ns.db.global.characters[a], ns.db.global.characters[b]
    if (ca.eligible or false) ~= (cb.eligible or false) then return ca.eligible and true or false end
    return (ca.name or a) < (cb.name or b)
  end)

  for _, key in ipairs(keys) do
    local char = ns.db.global.characters[key]
    local g = AceGUI:Create("InlineGroup")
    g:SetFullWidth(true)
    g:SetLayout("List")
    local pending = char.hasPendingLoot and "  |cffff4040[banked loot]|r" or ""
    local dim = char.eligible and "" or "|cff888888"
    g:SetTitle(("|c%s%s-%s|r  ilvl %d%s"):format(
      classColor(char.class), char.name or "?", char.realm or "?", char.ilvl or 0, pending))

    local period = Derived.currentPeriod(char)
    for _, tk in ipairs(TRACK_ORDER) do
      local lbl = AceGUI:Create("Label")
      lbl:SetFullWidth(true)
      local track = period and period.tracks[tk]
      local body = track and trackLine(track) or "no data"
      lbl:SetText(("%s%-8s|r  %s"):format(dim, TRACK_LABEL[tk], body))
      g:AddChild(lbl)
    end
    scroll:AddChild(g)
  end
end

function Roster:Toggle()
  if self.frame then
    AceGUI:Release(self.frame)
    self.frame = nil
  else
    self:Build()
  end
end
