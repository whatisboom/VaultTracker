local ADDON, ns = ...
local Broker = {}
ns.Broker = Broker

local COLORS = {
  red   = { 1.0, 0.25, 0.25 },
  amber = { 1.0, 0.82, 0.25 },
  none  = { 0.6, 0.6, 0.6 },
}

function Broker:Setup(addon)
  local LDB = LibStub("LibDataBroker-1.1")
  local DBIcon = LibStub("LibDBIcon-1.0")

  self.obj = LDB:NewDataObject("VaultTracker", {
    type = "data source",
    text = "Vault",
    icon = "Interface\\Icons\\INV_Misc_Treasurechest_03",
    OnClick = function(_, button) Broker:OnClick(button) end,
    OnTooltipShow = function(tt) Broker:OnTooltip(tt) end,
  })
  DBIcon:Register("VaultTracker", self.obj, ns.db.global.settings.minimap)
  self:Update()
end

-- Compute the current attention list from live data.
function Broker:Current()
  return ns.Attention.build(
    ns.db.global.characters,
    ns.db.global.settings,
    C_DateAndTime.GetSecondsUntilWeeklyReset())
end

function Broker:Update()
  if not self.obj then return end
  local list = self:Current()
  local s = ns.Attention.summary(list)
  local c = COLORS[s.color] or COLORS.none

  -- LDB text + icon color hint (used by bar displays).
  self.obj.text = (s.count > 0) and tostring(s.count) or "Vault"
  self.obj.iconR, self.obj.iconG, self.obj.iconB = c[1], c[2], c[3]

  -- Minimap button: tint icon + overlay a numeric badge.
  local DBIcon = LibStub("LibDBIcon-1.0")
  local button = DBIcon.GetMinimapButton and DBIcon:GetMinimapButton("VaultTracker")
  if button then
    if button.icon then button.icon:SetVertexColor(c[1], c[2], c[3]) end
    if not button.vtBadge then
      local fs = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 2)
      button.vtBadge = fs
    end
    button.vtBadge:SetText(s.count > 0 and tostring(s.count) or "")
  end
end

function Broker:OnClick(button)
  if button == "RightButton" then
    ns.Config:Open()
  else
    ns.Roster:Toggle()
  end
end

local REASON_TEXT = { banked = "banked loot", untouched = "untouched", incomplete = "incomplete" }

function Broker:OnTooltip(tt)
  tt:AddLine("VaultTracker")
  local list = self:Current()
  if #list == 0 then
    tt:AddLine("Nothing needs attention.", 0.6, 0.6, 0.6)
  else
    for _, e in ipairs(list) do
      local labels = {}
      for _, r in ipairs(e.reasons) do labels[#labels + 1] = REASON_TEXT[r] or r end
      local c = COLORS[e.severity] or COLORS.none
      tt:AddDoubleLine(e.name .. "-" .. e.realm, table.concat(labels, ", "),
        1, 1, 1, c[1], c[2], c[3])
    end
  end
  local secs = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
  tt:AddLine(("Reset in %dh %dm"):format(math.floor(secs / 3600), math.floor((secs % 3600) / 60)),
    0.5, 0.5, 0.5)
  tt:AddLine("Left-click: roster   Right-click: settings", 0.4, 0.4, 0.4)
end
