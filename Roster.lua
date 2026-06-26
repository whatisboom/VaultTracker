local ADDON, ns = ...
local Roster = {}
ns.Roster = Roster

local function classColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  return c and c.colorStr or "ffffffff"
end

-- A character is "active" in the roster if it's tracked, or has confirmed banked loot
-- (which surfaces regardless of eligibility unless it's "off"). Inactive rows dim.
local function isActive(char)
  return ns.Derived.effectiveTracked(char)
    or (char.hasPendingLoot and char.trackTier ~= "off")
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
-- name and ilvl are fixed; the track group shifts right by BANKED_GAP to make room
-- for an optional Banked column (only shown when some character has banked loot).
local COLS_X = { name = 40, ilvl = 160 }
local TRACKS = { "raid", "dungeon", "world" }
local TRACK_LABEL = { raid = ns.L.TRACK_RAID, dungeon = ns.L.TRACK_DUNGEON, world = ns.L.TRACK_WORLD }
local HEADERS = {
  { key = "name", text = ns.L.ROSTER_COL_NAME }, { key = "ilvl", text = ns.L.ROSTER_COL_ILVL },
  { key = "banked", text = ns.L.ROSTER_COL_BANKED },
  { key = "raid", text = ns.L.TRACK_RAID }, { key = "dungeon", text = ns.L.TRACK_DUNGEON }, { key = "world", text = ns.L.TRACK_WORLD },
}
local ROW_INSET = 8
local ROW_H     = 22
local ICON_X    = 16
local NAME_W    = 116
local SLOT_W    = 40
local SLOT_PAD  = 6                  -- right-edge padding for right-aligned slot numbers
local ILVL_R    = COLS_X.ilvl + 30   -- ilvl column right edge (frame-relative)
local BANKED_W  = 78                 -- banked cell width
local BANKED_R  = 278                -- banked column right edge (frame-relative), when shown
local BANKED_GAP = 84                -- track group's rightward shift when banked column is shown
local RAID_X0   = 208                -- raid group's left x with no banked column
local HEAD_Y    = -42
local ROW0_Y    = -64

-- Frame-relative geometry for a given banked-column visibility. Track group shifts;
-- the first separator brackets ilvl|raid or banked|raid depending on the column.
local function geometry(showBanked)
  local raid = RAID_X0 + (showBanked and BANKED_GAP or 0)
  local dungeon, world = raid + 122, raid + 244
  return {
    showBanked = showBanked,
    raid = raid, dungeon = dungeon, world = world,
    frameW = world + 3 * SLOT_W + 16,
    seps = {
      ((showBanked and BANKED_R or ILVL_R) + raid) / 2,
      (raid + 3 * SLOT_W + dungeon) / 2,
      (dungeon + 3 * SLOT_W + world) / 2,
    },
  }
end

-- Row background highlight: per-severity colour and intensity (alpha). The current
-- character glows a cool blue ("you are here"), deliberately outside the warm
-- red/amber warning family so it never reads as an alert. When the logged-in
-- character also needs attention, the row fades from its attention colour to blue.
local GLOW_COLOR = {
  red     = { 0.85, 0.12, 0.12 },
  amber   = { 0.85, 0.65, 0.12 },
  current = { 0.25, 0.60, 1.0  },  -- cool blue, distinct from the warm warnings
}
local GLOW_ALPHA = { red = 0.14, amber = 0.10, current = 0.18 }

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
  tex:SetDesaturated(not isActive(char))
  tex:Show()
end

-- The raid activity's raidString is a localized template carrying a %d for the
-- slot's boss-kill threshold (e.g. "Defeat %d Midnight Season 1 Bosses"). Fill it
-- with the threshold; return verbatim when there's no %d (or formatting fails) so an
-- unexpected template can never error or show a raw placeholder.
local function raidText(tier)
  local s = tier.raidString
  if s and s:find("%d", 1, true) then
    local ok, out = pcall(string.format, s, tier.threshold)
    if ok then return out end
  end
  return s
end

-- Tooltip content for one slot. World omits a "source" line until `level` is verified.
local function fillSlotTooltip(tt, tk, tier, idx)
  tt:AddLine((ns.L.ROSTER_SLOT):format(TRACK_LABEL[tk], idx), 1, 0.82, 0)
  if tier.progress >= tier.threshold then
    if tk == "dungeon" and (tier.level or 0) > 0 then
      tt:AddLine((ns.L.ROSTER_MPLUS):format(tier.level), 1, 1, 1)
    elseif tk == "raid" and tier.raidString then
      tt:AddLine(raidText(tier), 1, 1, 1)
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
      tt:AddLine(ns.L.ROSTER_THISWEEK .. raidText(tier), 0.7, 0.7, 0.7)
    end
  end
  tt:AddLine(ns.L.ROSTER_RIGHTCLICK, 0.4, 0.4, 0.4)
end

-- Tooltip for the Banked column: a title, an optional note (the inferred case),
-- then one line per claimable slot with its ilvl.
local function fillBankedTooltip(tt, period, title, note)
  tt:AddLine(title, 1, 0.82, 0)
  if note then tt:AddLine(note, 0.85, 0.65, 0.2) end
  if period then
    for _, tk in ipairs(TRACKS) do
      local track = period.tracks[tk]
      if track then
        for idx, tier in ipairs(track) do
          if tier.progress >= tier.threshold and (tier.rewardIlvl or 0) > 0 then
            tt:AddDoubleLine((ns.L.ROSTER_SLOT):format(TRACK_LABEL[tk], idx),
              (ns.L.ROSTER_REWARD):format(tier.rewardIlvl), 1, 1, 1, 0.4, 0.85, 0.4)
          end
        end
      end
    end
  end
  tt:AddLine(ns.L.ROSTER_RIGHTCLICK, 0.4, 0.4, 0.4)
end

-- The Banked-column state for one character: "confirmed" (real pending loot),
-- "likely" (inferred from a stale alt), or nil. Returns the ilvl range and the
-- period to detail in the hover.
local function bankedCell(char, realWeekId)
  -- "off" silences everywhere, including the Banked column (even when Show all
  -- reveals the dimmed row).
  if char.trackTier == "off" then return nil end
  -- Confirmed = actual unclaimed loot (hasPendingLoot), shown even with no cached
  -- range detail (n may be 0). Likely = inferred from a stale alt.
  if char.hasPendingLoot then
    local lo, hi, n = ns.Derived.bankedRange(char)
    return "confirmed", lo, hi, n, ns.Derived.bankedPeriod(char)
  end
  if realWeekId and ns.Derived.likelyBanked(char, realWeekId) then
    local p = ns.Derived.currentPeriod(char)
    local lo, hi, n = ns.Derived.periodRange(p)
    return "likely", lo, hi, n, p
  end
  return nil
end

local function attentionMap()
  local m = {}
  for _, e in ipairs(ns.Attention.build(ns.db.global.characters, ns.db.global.settings,
      C_DateAndTime.GetSecondsUntilWeeklyReset(), time())) do
    m[e.key] = e.severity
  end
  return m
end

local function sortedKeys(attn)
  local chars = ns.db.global.characters
  -- Only confirmed banked loot (red, no deadline) floats to the top. Amber soft
  -- states (untouched / close-to-unlock / likely-banked) glow in place rather than
  -- reordering the roster; everything else sorts by ilvl then name.
  local function rank(key)
    if attn[key] == "red" then return 0 end
    return 1
  end
  local show = ns.db.global.settings.showIgnored
  local keys = {}
  for key, char in pairs(chars) do
    if show or isActive(char) then keys[#keys + 1] = key end
  end
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
  f:SetSize(geometry(false).frameW, 120)
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

  -- Header fontstrings are created once and (re)positioned by applyChrome, since the
  -- track columns shift when the optional Banked column appears.
  f.headerFS = {}
  for _, h in ipairs(HEADERS) do
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetText(h.text)
    f.headerFS[h.key] = fs
  end

  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(1, 1, 1, 0.10)
  rule:SetPoint("TOPLEFT", 14, HEAD_Y - 16)
  rule:SetPoint("TOPRIGHT", -14, HEAD_Y - 16)
  rule:SetHeight(1)
  f.rule = rule

  -- Vertical separators bracketing the three track groups. On their own layer above
  -- the rows so the row stripe/glow doesn't wash them out. Positioned by applyChrome.
  local sepLayer = CreateFrame("Frame", nil, f)
  sepLayer:SetAllPoints()
  sepLayer:SetFrameLevel(f:GetFrameLevel() + 5)
  f.seps = {}
  for i = 1, 3 do
    local sep = sepLayer:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.14)
    sep:SetWidth(1)
    f.seps[i] = sep
  end

  -- "Show all" toggle at the bottom: reveals hidden / not-yet-qualifying rows (greyed).
  -- Mirrors the same setting in the options panel; state re-synced in Refresh.
  local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  cb:SetSize(20, 20)
  cb:SetPoint("BOTTOMLEFT", 12, 8)
  cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 1, 0)
  cb.label:SetText(ns.L.OPT_SHOWIGNORED)
  cb:SetScript("OnClick", function(self)
    ns.db.global.settings.showIgnored = self:GetChecked() and true or false
    ns.Roster:Refresh()
  end)
  f.showAllCheck = cb

  -- Fresh-install / empty-roster message, shown in the row area when no rows render
  -- (no characters tracked yet, or all hidden by the filter). Hidden otherwise.
  f.emptyTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.emptyTitle:SetPoint("TOP", 0, ROW0_Y - 16)
  f.emptyTitle:SetText(ns.L.ROSTER_EMPTY_TITLE)
  f.emptyTitle:Hide()
  f.emptyBody = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.emptyBody:SetPoint("TOP", f.emptyTitle, "BOTTOM", 0, -8)
  f.emptyBody:SetWidth(geometry(false).frameW - 48)
  f.emptyBody:SetJustifyH("CENTER")
  f.emptyBody:SetText(ns.L.ROSTER_EMPTY_BODY)
  f.emptyBody:Hide()

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
  row:SetSize(geometry(false).frameW - ROW_INSET * 2, ROW_H)  -- width re-applied by positionRow
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
  row.nameFrame:SetPropagateMouseClicks(true)  -- right-click reaches the row's menu
  row.nameText = row.nameFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.nameText:SetPoint("LEFT")
  row.nameText:SetJustifyH("LEFT")

  row.ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.ilvlText:SetPoint("RIGHT", row, "LEFT", ILVL_R - ROW_INSET, 0)
  row.ilvlText:SetJustifyH("RIGHT")

  -- banked: a hoverable, right-aligned cell for the banked-loot range/count
  row.bankedFrame = CreateFrame("Frame", nil, row)
  row.bankedFrame:SetSize(BANKED_W, ROW_H)
  row.bankedFrame:SetPoint("RIGHT", row, "LEFT", BANKED_R - ROW_INSET, 0)
  row.bankedFrame:SetPropagateMouseClicks(true)  -- right-click reaches the row's menu
  row.bankedText = row.bankedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.bankedText:SetPoint("RIGHT")
  row.bankedText:SetJustifyH("RIGHT")

  -- tracks: three hoverable slot frames each (positioned by positionRow)
  row.slots = {}
  for _, tk in ipairs(TRACKS) do
    row.slots[tk] = {}
    for j = 1, 3 do
      local sf = CreateFrame("Frame", nil, row)
      sf:SetSize(SLOT_W, ROW_H)
      sf:EnableMouse(true)
      sf:SetPropagateMouseClicks(true)  -- right-click reaches the row's menu
      sf.text = sf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      sf.text:SetPoint("RIGHT", -SLOT_PAD, 0)
      sf.text:SetJustifyH("RIGHT")
      row.slots[tk][j] = sf
    end
  end

  f.rows[i] = row
  return row
end

-- (Re)position the frame chrome for a layout: frame width, headers (the Banked
-- header is shown only when geo.showBanked), and the three group separators.
local function applyChrome(f, geo, empty)
  f:SetWidth(geo.frameW)
  local h = f.headerFS
  h.name:ClearAllPoints();  h.name:SetPoint("TOPLEFT", COLS_X.name, HEAD_Y); h.name:SetShown(not empty)
  h.ilvl:ClearAllPoints();  h.ilvl:SetPoint("TOPRIGHT", f, "TOPLEFT", ILVL_R, HEAD_Y); h.ilvl:SetJustifyH("RIGHT"); h.ilvl:SetShown(not empty)
  if geo.showBanked and not empty then
    h.banked:ClearAllPoints()
    h.banked:SetPoint("TOPRIGHT", f, "TOPLEFT", BANKED_R, HEAD_Y); h.banked:SetJustifyH("RIGHT")
    h.banked:Show()
  else
    h.banked:Hide()
  end
  for _, tk in ipairs(TRACKS) do
    h[tk]:ClearAllPoints(); h[tk]:SetPoint("TOP", f, "TOPLEFT", geo[tk] + SLOT_W * 1.5, HEAD_Y); h[tk]:SetShown(not empty)
  end
  -- The header rule and group separators are grid chrome; with no rows there is
  -- nothing to delimit, so hide them and let the empty message stand alone.
  f.rule:SetShown(not empty)
  for i, x in ipairs(geo.seps) do
    local sep = f.seps[i]
    sep:ClearAllPoints()
    sep:SetPoint("TOP", f, "TOPLEFT", x, HEAD_Y + 6)
    sep:SetPoint("BOTTOM", f, "BOTTOMLEFT", x, 32)  -- stop above the "Show all" checkbox
    sep:SetShown(not empty)
  end
end

-- (Re)position a row's slot frames for the active layout and toggle its banked cell.
local function positionRow(row, geo)
  row:SetWidth(geo.frameW - ROW_INSET * 2)
  for _, tk in ipairs(TRACKS) do
    for j = 1, 3 do
      local sf = row.slots[tk][j]
      sf:ClearAllPoints()
      sf:SetPoint("LEFT", geo[tk] - ROW_INSET + (j - 1) * SLOT_W, 0)
    end
  end
  if geo.showBanked then row.bankedFrame:Show() else row.bankedFrame:Hide() end
end

function Roster:Refresh()
  local f = self.frame
  local chars = ns.db.global.characters
  local attn = attentionMap()
  local keys = sortedKeys(attn)
  local currentKey = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
  f.countdown:SetText(resetText())
  f.showAllCheck:SetChecked(ns.db.global.settings.showIgnored and true or false)

  -- The Banked column appears only when some shown character has banked loot
  -- (confirmed) or is inferred to (a stale alt with unlocked slots last week).
  local secs = C_DateAndTime.GetSecondsUntilWeeklyReset()
  local realWeekId = secs and ns.Derived.periodKey(time(), secs) or nil
  local showBanked = false
  for _, key in ipairs(keys) do
    if bankedCell(chars[key], realWeekId) then showBanked = true; break end
  end
  local geo = geometry(showBanked)
  applyChrome(f, geo, #keys == 0)

  for i, key in ipairs(keys) do
    local char = chars[key]
    local dim = not isActive(char)
    local row = acquireRow(f, i)
    positionRow(row, geo)

    setRowIcon(row.icon, char)
    row.nameText:SetText(dim and ("|cff6a6453%s|r"):format(char.name or "?")
      or ("|c%s%s|r"):format(classColor(char.class), char.name or "?"))
    row.ilvlText:SetText(("|cff%s%d|r"):format(dim and "6a6453" or "ffd100", char.ilvl or 0))

    local kind, blo, bhi, bn, bperiod = bankedCell(char, realWeekId)
    if kind then
      local core = ns.Format.bankedColumn(blo, bhi, bn)
      local txt, color, title, note
      if kind == "confirmed" then
        txt, color, title = core or ns.L.ROSTER_BANKED_YES, dim and "6a6453" or "f2c24a", ns.L.ROSTER_BANKED_TITLE
      else  -- likely (inferred): muted amber, "?" prefix, "log in to confirm" note
        txt = ns.L.ROSTER_MAYBE_PREFIX .. (core or "")
        color, title, note = dim and "6a6453" or "b9952f", ns.L.ROSTER_MAYBE_TITLE, ns.L.ROSTER_MAYBE_NOTE
      end
      row.bankedText:SetText(("|cff%s%s|r"):format(color, txt))
      row.bankedFrame:EnableMouse(true)
      row.bankedFrame:SetScript("OnEnter", function(self)
        row.hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        fillBankedTooltip(GameTooltip, bperiod, title, note)
        GameTooltip:Show()
      end)
      row.bankedFrame:SetScript("OnLeave", function() row.hl:Hide(); GameTooltip:Hide() end)
    else
      row.bankedText:SetText(("|cff%s%s|r"):format(dim and "5a5444" or "6a6453", ns.L.ROSTER_BANKED_NONE))
      row.bankedFrame:EnableMouse(false)
      row.bankedFrame:SetScript("OnEnter", nil)
      row.bankedFrame:SetScript("OnLeave", nil)
    end

    row.nameFrame:SetScript("OnEnter", function(self)
      row.hl:Show()
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(("|c%s%s-%s|r"):format(classColor(char.class), char.name or "?", char.realm or "?"))
      if char.spec then GameTooltip:AddLine(char.spec, 0.8, 0.8, 0.8) end
      GameTooltip:AddLine((ns.L.ROSTER_EQUIPPED):format(char.ilvl or 0), 1, 0.82, 0)
      GameTooltip:AddLine(ns.L.ROSTER_SCANNED .. ago(char.lastScan), 0.6, 0.6, 0.6)
      -- Distinguish "you hid it" from "it just hasn't qualified yet".
      if char.trackTier == "off" then
        GameTooltip:AddLine(ns.L.ROSTER_HIDDEN, 0.6, 0.5, 0.4)
      elseif not ns.Derived.effectiveTracked(char) then
        GameTooltip:AddLine(ns.L.ROSTER_NOREWARD, 0.6, 0.5, 0.4)
      end
      GameTooltip:AddLine(ns.L.ROSTER_RIGHTCLICK, 0.4, 0.4, 0.4)
      GameTooltip:Show()
    end)
    row.nameFrame:SetScript("OnLeave", function() row.hl:Hide(); GameTooltip:Hide() end)

    -- Right-click anywhere on the row to set this character's tier line (Auto / tiers
    -- / Off), written to chars[key].trackTier. Refresh re-applies the tracked gate.
    -- Child frames (name/banked/slots) propagate their clicks down to the row (set in
    -- acquireRow), so the whole row is the target, not just the name.
    row:SetScript("OnMouseUp", function(_, button)
      if button ~= "RightButton" then return end
      MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(ns.L.ROSTER_TRACKTIER)
        local function opt(label, value)
          root:CreateRadio(label, function() return char.trackTier == value end, function()
            char.trackTier = value
            -- A per-character override re-evaluates that character's eligibility now
            -- (non-sticky): tracked iff its earned tier meets the new line.
            char.eligible = ns.Derived.qualifies(char.bestTier or 0,
              ns.Derived.effectiveLine(value, ns.db.global.settings.seriousness))
            ns.Broker:Update()
            ns.Roster:Refresh()
          end)
        end
        opt(ns.L.ROSTER_TRACK_AUTO, nil)
        opt(ns.L.TIER_VETERAN,  "veteran")
        opt(ns.L.TIER_CHAMPION, "champion")
        opt(ns.L.TIER_HERO,     "hero")
        opt(ns.L.TIER_MYTH,     "myth")
        root:CreateDivider()
        opt(ns.L.ROSTER_TRACK_OFF, "off")
      end)
    end)

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
    local cur = GLOW_COLOR.current
    if key == currentKey and (sev == "red" or sev == "amber") then
      setGlow(row.glow, GLOW_COLOR[sev], GLOW_ALPHA[sev], cur, GLOW_ALPHA.current)
    elseif key == currentKey then
      setGlow(row.glow, cur, GLOW_ALPHA.current, cur, GLOW_ALPHA.current)
    elseif sev == "red" or sev == "amber" then
      setGlow(row.glow, GLOW_COLOR[sev], GLOW_ALPHA[sev], GLOW_COLOR[sev], GLOW_ALPHA[sev])
    else
      row.glow:Hide()
    end
    row:Show()
  end
  for i = #keys + 1, #f.rows do f.rows[i]:Hide() end

  local empty = #keys == 0
  f.emptyTitle:SetShown(empty)
  f.emptyBody:SetShown(empty)
  -- Give the empty message room to breathe (title + wrapped body); otherwise size
  -- to the rows, with a one-row floor for the checkbox.
  local bodyRows = empty and 4 or #keys
  f:SetHeight(-ROW0_Y + math.max(bodyRows, 1) * ROW_H + 34)  -- bottom room for the checkbox
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
