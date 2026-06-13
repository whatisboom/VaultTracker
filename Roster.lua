local ADDON, ns = ...
local Roster = {}
ns.Roster = Roster

local function classColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  return c and c.colorStr or "ffffffff"
end

-- One slot's text: earned + known ilvl -> green ilvl; earned + unresolved -> ready-check;
-- unearned -> muted progress fraction.
local READY_CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13|t"

local function slotText(tier, dim)
  if tier.progress >= tier.threshold then
    local il = tier.rewardIlvl or 0
    if il > 0 then return ("|cff%s%d|r"):format(dim and "6f6f6f" or "38d13e", il) end
    return READY_CHECK
  end
  return ("|cff%s%d/%d|r"):format(dim and "5a5444" or "9a8f73", tier.progress, tier.threshold)
end

-- Layout: column x-offsets from the frame's left; tracks hold 3 fixed-width slots.
local COLS_X = { name = 40, ilvl = 160, raid = 208, dungeon = 330, world = 452 }
local TRACKS = { "raid", "dungeon", "world" }
local TRACK_LABEL = { raid = ns.L.TRACK_RAID, dungeon = ns.L.TRACK_DUNGEON, world = ns.L.TRACK_WORLD }
local HEADERS = {
  { key = "name", text = ns.L.ROSTER_COL_NAME }, { key = "ilvl", text = ns.L.ROSTER_COL_ILVL },
  { key = "raid", text = ns.L.TRACK_RAID }, { key = "dungeon", text = ns.L.TRACK_DUNGEON }, { key = "world", text = ns.L.TRACK_WORLD },
}
local FRAME_W   = 588
local ROW_INSET = 8
local ROW_H     = 22
local ICON_X    = 16
local NAME_W    = 116
local SLOT_W    = 40
local SLOT_PAD  = 6                  -- right-edge padding for right-aligned slot numbers
local ILVL_R    = COLS_X.ilvl + 30   -- ilvl column right edge (frame-relative)
-- Vertical separators: x at each group boundary (ilvl|raid, raid|dungeon, dungeon|world).
local SEP_X = {
  (ILVL_R + COLS_X.raid) / 2,
  (COLS_X.raid + 3 * SLOT_W + COLS_X.dungeon) / 2,
  (COLS_X.dungeon + 3 * SLOT_W + COLS_X.world) / 2,
}
local HEAD_Y    = -42
local ROW0_Y    = -64

-- Row background highlight: per-severity colour and intensity (alpha). The current
-- character glows gold; an attention character glows red/amber. When the logged-in
-- character also needs attention, the row fades from its attention colour to gold.
local GLOW_COLOR = {
  red     = { 0.85, 0.12, 0.12 },
  amber   = { 0.85, 0.65, 0.12 },
  current = { 1.0,  0.82, 0.0  },  -- gold, matches the "ffd100" ilvl text
}
local GLOW_ALPHA = { red = 0.14, amber = 0.10, current = 0.14 }

-- glow is white; SetGradient filters it. Equal stops = solid fill, differing = fade.
local function setGlow(tex, c1, a1, c2, a2)
  tex:SetGradient("HORIZONTAL",
    CreateColor(c1[1], c1[2], c1[3], a1),
    CreateColor(c2[1], c2[2], c2[3], a2))
  tex:Show()
end

local function ago(ts)
  if not ts then return ns.L.TIME_NEVER end
  local s = time() - ts
  if s < 3600 then return (ns.L.TIME_M):format(math.max(1, math.floor(s / 60))) end
  if s < 86400 then return (ns.L.TIME_H):format(math.floor(s / 3600)) end
  return (ns.L.TIME_D):format(math.floor(s / 86400))
end

local function setRowIcon(tex, char)
  if char.specIcon then
    tex:SetTexture(char.specIcon)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  elseif char.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[char.class] then
    tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    local c = CLASS_ICON_TCOORDS[char.class]
    tex:SetTexCoord(c.left or c[1], c.right or c[2], c.top or c[3], c.bottom or c[4])
  else
    tex:SetTexture(134400); tex:SetTexCoord(0, 1, 0, 1)  -- INV_Misc_QuestionMark
  end
  tex:SetDesaturated(not char.eligible)
  tex:Show()
end

-- Tooltip content for one slot. World omits a "source" line until `level` is verified.
local function fillSlotTooltip(tt, tk, tier, idx)
  tt:AddLine((ns.L.ROSTER_SLOT):format(TRACK_LABEL[tk], idx), 1, 0.82, 0)
  if tier.progress >= tier.threshold then
    if tk == "dungeon" and (tier.level or 0) > 0 then
      tt:AddLine((ns.L.ROSTER_MPLUS):format(tier.level), 1, 1, 1)
    elseif tk == "raid" and tier.raidString then
      tt:AddLine(tier.raidString, 1, 1, 1)
    end
    if (tier.rewardIlvl or 0) > 0 then
      tt:AddLine((ns.L.ROSTER_REWARD):format(tier.rewardIlvl), 0.4, 0.85, 0.4)
    else
      tt:AddLine(ns.L.ROSTER_REWARD_PENDING, 0.7, 0.7, 0.7)
    end
  else
    tt:AddLine((ns.L.ROSTER_PROGRESS):format(tier.progress, tier.threshold), 1, 1, 1)
    tt:AddLine((ns.L.ROSTER_UNLOCK_MORE):format(tier.threshold - tier.progress), 0.85, 0.65, 0.2)
    if tk == "raid" and tier.raidString then
      tt:AddLine(ns.L.ROSTER_THISWEEK .. tier.raidString, 0.7, 0.7, 0.7)
    end
  end
end

local function attentionMap()
  local m = {}
  for _, e in ipairs(ns.Attention.build(ns.db.global.characters, ns.db.global.settings,
      C_DateAndTime.GetSecondsUntilWeeklyReset())) do
    m[e.key] = e.severity
  end
  return m
end

local function sortedKeys(attn)
  local chars = ns.db.global.characters
  local function rank(key)
    if attn[key] == "red" then return 0 end
    if attn[key] == "amber" then return 1 end
    return 2
  end
  local keys = {}
  for key in pairs(chars) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    local ca, cb = chars[a], chars[b]
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    local ia, ib = ca.ilvl or 0, cb.ilvl or 0
    if ia ~= ib then return ia > ib end
    return (ca.name or a) < (cb.name or b)
  end)
  return keys
end

local function resetText()
  local secs = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
  return (ns.L.ROSTER_RESETS):format(math.floor(secs / 86400), math.floor((secs % 86400) / 3600))
end

function Roster:CreateFrame()
  local f = CreateFrame("Frame", "VaultTrackerRosterFrame", UIParent, "BackdropTemplate")
  f:SetSize(FRAME_W, 120)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -12)
  title:SetText(ns.L.ROSTER_TITLE)

  f.countdown = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.countdown:SetPoint("TOPLEFT", 16, -16)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  tinsert(UISpecialFrames, "VaultTrackerRosterFrame")

  for _, h in ipairs(HEADERS) do
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetText(h.text)
    if h.key == "name" then
      fs:SetPoint("TOPLEFT", COLS_X.name, HEAD_Y)
    elseif h.key == "ilvl" then
      fs:SetPoint("TOPRIGHT", f, "TOPLEFT", ILVL_R, HEAD_Y); fs:SetJustifyH("RIGHT")
    else  -- track headers: centred over their three slots
      fs:SetPoint("TOP", f, "TOPLEFT", COLS_X[h.key] + SLOT_W * 1.5, HEAD_Y)
    end
  end

  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(1, 1, 1, 0.10)
  rule:SetPoint("TOPLEFT", 14, HEAD_Y - 16)
  rule:SetPoint("TOPRIGHT", -14, HEAD_Y - 16)
  rule:SetHeight(1)

  -- Vertical separators bracketing the three track groups. On their own layer above
  -- the rows so the row stripe/glow doesn't wash them out.
  local sepLayer = CreateFrame("Frame", nil, f)
  sepLayer:SetAllPoints()
  sepLayer:SetFrameLevel(f:GetFrameLevel() + 5)
  for _, x in ipairs(SEP_X) do
    local sep = sepLayer:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.14)
    sep:SetWidth(1)
    sep:SetPoint("TOP", f, "TOPLEFT", x, HEAD_Y + 6)
    sep:SetPoint("BOTTOM", f, "BOTTOMLEFT", x, 12)
  end

  f:SetScript("OnUpdate", function(self, elapsed)
    self._t = (self._t or 5) + elapsed
    if self._t > 20 then self._t = 0; self.countdown:SetText(resetText()) end
  end)

  f.rows = {}
  f:Hide()
  return f
end

local function acquireRow(f, i)
  local row = f.rows[i]
  if row then return row end
  row = CreateFrame("Frame", nil, f)
  row:SetSize(FRAME_W - ROW_INSET * 2, ROW_H)
  row:SetPoint("TOPLEFT", ROW_INSET, ROW0_Y - (i - 1) * ROW_H)
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self) self.hl:Show() end)
  row:SetScript("OnLeave", function(self) self.hl:Hide() end)

  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints(); row.stripe:SetColorTexture(1, 1, 1, 0.025)

  row.glow = row:CreateTexture(nil, "BORDER")
  row.glow:SetAllPoints(); row.glow:SetColorTexture(1, 1, 1, 1); row.glow:Hide()

  row.hl = row:CreateTexture(nil, "ARTWORK")
  row.hl:SetAllPoints(); row.hl:SetColorTexture(1, 1, 1, 0.07); row.hl:Hide()

  row.icon = row:CreateTexture(nil, "OVERLAY")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", ICON_X - ROW_INSET, 0)

  -- name: a hoverable frame for the character tooltip
  row.nameFrame = CreateFrame("Frame", nil, row)
  row.nameFrame:SetSize(NAME_W, ROW_H)
  row.nameFrame:SetPoint("LEFT", COLS_X.name - ROW_INSET, 0)
  row.nameFrame:EnableMouse(true)
  row.nameText = row.nameFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.nameText:SetPoint("LEFT")
  row.nameText:SetJustifyH("LEFT")

  row.ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.ilvlText:SetPoint("RIGHT", row, "LEFT", ILVL_R - ROW_INSET, 0)
  row.ilvlText:SetJustifyH("RIGHT")

  -- tracks: three hoverable slot frames each
  row.slots = {}
  for _, tk in ipairs(TRACKS) do
    row.slots[tk] = {}
    for j = 1, 3 do
      local sf = CreateFrame("Frame", nil, row)
      sf:SetSize(SLOT_W, ROW_H)
      sf:SetPoint("LEFT", COLS_X[tk] - ROW_INSET + (j - 1) * SLOT_W, 0)
      sf:EnableMouse(true)
      sf.text = sf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      sf.text:SetPoint("RIGHT", -SLOT_PAD, 0)
      sf.text:SetJustifyH("RIGHT")
      row.slots[tk][j] = sf
    end
  end

  f.rows[i] = row
  return row
end

function Roster:Refresh()
  local f = self.frame
  local chars = ns.db.global.characters
  local attn = attentionMap()
  local keys = sortedKeys(attn)
  local currentKey = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
  f.countdown:SetText(resetText())

  for i, key in ipairs(keys) do
    local char = chars[key]
    local dim = not char.eligible
    local row = acquireRow(f, i)

    setRowIcon(row.icon, char)
    row.nameText:SetText(dim and ("|cff6a6453%s|r"):format(char.name or "?")
      or ("|c%s%s|r"):format(classColor(char.class), char.name or "?"))
    row.ilvlText:SetText(("|cff%s%d|r"):format(dim and "6a6453" or "ffd100", char.ilvl or 0))

    row.nameFrame:SetScript("OnEnter", function(self)
      row.hl:Show()
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(("|c%s%s-%s|r"):format(classColor(char.class), char.name or "?", char.realm or "?"))
      if char.spec then GameTooltip:AddLine(char.spec, 0.8, 0.8, 0.8) end
      GameTooltip:AddLine((ns.L.ROSTER_EQUIPPED):format(char.ilvl or 0), 1, 0.82, 0)
      GameTooltip:AddLine(ns.L.ROSTER_SCANNED .. ago(char.lastScan), 0.6, 0.6, 0.6)
      if dim then GameTooltip:AddLine(ns.L.ROSTER_INELIGIBLE, 0.6, 0.5, 0.4) end
      GameTooltip:Show()
    end)
    row.nameFrame:SetScript("OnLeave", function() row.hl:Hide(); GameTooltip:Hide() end)

    local period = ns.Derived.currentPeriod(char)
    for _, tk in ipairs(TRACKS) do
      local track = period and period.tracks[tk]
      for j = 1, 3 do
        local sf = row.slots[tk][j]
        local tier = track and track[j]
        if tier then
          sf.text:SetText(slotText(tier, dim))
          sf:EnableMouse(true)
          sf:SetScript("OnEnter", function(self)
            row.hl:Show()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            fillSlotTooltip(GameTooltip, tk, tier, j)
            GameTooltip:Show()
          end)
          sf:SetScript("OnLeave", function() row.hl:Hide(); GameTooltip:Hide() end)
        else
          sf.text:SetText(j == 1 and "|cff6a6453-|r" or "")
          sf:EnableMouse(false)
          sf:SetScript("OnEnter", nil)
          sf:SetScript("OnLeave", nil)
        end
      end
    end

    if i % 2 == 0 then row.stripe:Show() else row.stripe:Hide() end
    local sev = attn[key]
    local gold = GLOW_COLOR.current
    if key == currentKey and (sev == "red" or sev == "amber") then
      setGlow(row.glow, GLOW_COLOR[sev], GLOW_ALPHA[sev], gold, GLOW_ALPHA.current)
    elseif key == currentKey then
      setGlow(row.glow, gold, GLOW_ALPHA.current, gold, GLOW_ALPHA.current)
    elseif sev == "red" or sev == "amber" then
      setGlow(row.glow, GLOW_COLOR[sev], GLOW_ALPHA[sev], GLOW_COLOR[sev], GLOW_ALPHA[sev])
    else
      row.glow:Hide()
    end
    row:Show()
  end
  for i = #keys + 1, #f.rows do f.rows[i]:Hide() end

  f:SetHeight(-ROW0_Y + math.max(#keys, 1) * ROW_H + 14)
end

function Roster:Toggle()
  if not self.frame then self.frame = self:CreateFrame() end
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    self:Refresh()
    self.frame:Show()
  end
end
