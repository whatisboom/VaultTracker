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
    text = ns.L.BROKER_LABEL,
    icon = "Interface\\Icons\\INV_Misc_QuestionMark",  -- guaranteed-render placeholder; theme once confirmed
    OnClick = function(_, button) Broker:OnClick(button) end,
    OnTooltipShow = function(tt) Broker:OnTooltip(tt) end,
  })
  DBIcon:Register("VaultTracker", self.obj, ns.db.global.settings.minimap)
  self:Update()
  self:ApplyThemedIcon()
end

-- Use the game's Great Vault artwork if any candidate atlas resolves on this
-- client (verified via GetAtlasInfo so it can never blank); else keep the icon.
local VAULT_ATLASES = {
  "GreatVault-32x32", "greatVault-32x32", "greatvault-32x32",
  "WeeklyRewards-32x32", "Vault-32x32",
}
function Broker:ApplyThemedIcon()
  local DBIcon = LibStub("LibDBIcon-1.0")
  local button = DBIcon.GetMinimapButton and DBIcon:GetMinimapButton("VaultTracker")
  if not (button and button.icon) then return end
  if C_Texture and C_Texture.GetAtlasInfo then
    for _, atlas in ipairs(VAULT_ATLASES) do
      if C_Texture.GetAtlasInfo(atlas) then
        button.icon:SetAtlas(atlas)
        -- LibDBIcon's default 17x17 top-left icon leaves the atlas art small with
        -- padding; enlarge and center it so the vault fills the minimap button.
        button.icon:SetSize(30, 30)
        button.icon:ClearAllPoints()
        button.icon:SetPoint("CENTER", button, "CENTER", 1, 0)
        return
      end
    end
  end
  -- no vault atlas on this client: the dataobject's guaranteed icon stays.
end

-- Compute the current attention list from live data.
function Broker:Current()
  return ns.Attention.build(
    ns.db.global.characters,
    ns.db.global.settings,
    C_DateAndTime.GetSecondsUntilWeeklyReset(), time())
end

function Broker:Update()
  if not self.obj then return end
  local list = self:Current()
  local s = ns.Attention.summary(list)
  local hasAttention = s.count > 0
  -- Color-only badge (no count on the minimap): tint by urgency, natural when idle.
  local c = hasAttention and (COLORS[s.color] or COLORS.none) or { 1, 1, 1 }

  -- LDB text/icon-color hint for bar displays; the minimap itself shows color only.
  self.obj.text = hasAttention and tostring(s.count) or ns.L.BROKER_LABEL
  self.obj.iconR, self.obj.iconG, self.obj.iconB = c[1], c[2], c[3]

  local DBIcon = LibStub("LibDBIcon-1.0")
  local button = DBIcon.GetMinimapButton and DBIcon:GetMinimapButton("VaultTracker")
  if button and button.icon then
    button.icon:SetVertexColor(c[1], c[2], c[3])
  end
end

function Broker:OnClick(button)
  if button == "RightButton" then
    ns.Config:Open()
  else
    ns.Roster:Toggle()
  end
end

local function classHex(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  return c and c.colorStr or "ffffffff"
end

function Broker:OnTooltip(tt)
  tt:AddLine("Vault Tracker")
  local chars = ns.db.global.characters
  local list = self:Current()
  if #list == 0 then
    -- Fresh install (nothing tracked yet) reads differently from an established
    -- account that is merely caught up this week.
    local msg = ns.Derived.anyTracked(chars) and ns.L.BROKER_NOTHING or ns.L.BROKER_FRESH
    tt:AddLine(msg, 0.6, 0.6, 0.6)
  else
    for _, e in ipairs(list) do
      -- "!" confirmed banked, "?" likely banked (inferred), "-" time-pressure
      local name = ("%s |c%s%s-%s|r"):format(ns.Format.marker(e), classHex(e.class), e.name, e.realm)
      local reason = ns.Format.tooltipReason(e, chars[e.key])
      local c = COLORS[e.severity] or COLORS.none
      tt:AddDoubleLine(name, reason, 1, 1, 1, c[1], c[2], c[3])
    end
  end
  local secs = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
  tt:AddLine((ns.L.BROKER_RESET):format(ns.Format.countdown(secs)), 0.5, 0.5, 0.5)
  tt:AddLine(ns.L.BROKER_FOOTER, 0.4, 0.4, 0.4)
end
