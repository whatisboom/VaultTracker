local ADDON, ns = ...

local VaultTracker = LibStub("AceAddon-3.0"):NewAddon("VaultTracker",
  "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0")
ns.addon = VaultTracker

function VaultTracker:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("VaultTrackerDB", ns.Config.defaults, true)
  ns.db = self.db
  ns.Config:Setup(self)
  ns.Broker:Setup(self)
end

function VaultTracker:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnVaultEvent")
  self:RegisterEvent("WEEKLY_REWARDS_UPDATE", "OnVaultEvent")
  self:RegisterEvent("WEEKLY_REWARDS_ITEM_CHANGED", "OnVaultEvent")
  -- Re-evaluate each minute so the badge lights up on crossing into the
  -- time window and the reset clock advances.
  self.refreshTimer = self:ScheduleRepeatingTimer(function() ns.Broker:Update() end, 60)
  self:OnVaultEvent()
  self:Prune()
  -- Announce a beat after login so the summary reflects loaded data.
  self:ScheduleTimer("SessionAnnounce", 3)
end

function VaultTracker:Prune()
  local s = ns.db.global.settings
  if not s.autoPrune then return end
  for key in pairs(ns.Derived.staleKeys(ns.db.global.characters, time(), s.pruneWeeks)) do
    ns.db.global.characters[key] = nil
  end
end

function VaultTracker:SessionAnnounce()
  local s = ns.db.global.settings
  local chars = ns.db.global.characters
  if s.chatSummary then
    local list = ns.Attention.build(chars, s, C_DateAndTime.GetSecondsUntilWeeklyReset())
    local lines = ns.Format.summary(list, chars)
    for i, line in ipairs(lines) do
      if i == 1 then self:Print(line) else print(line) end
    end
  end
  if s.bankedSound then
    local play = false
    if s.soundScope == "current" then
      local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
      play = chars[key] and chars[key].hasPendingLoot or false
    else
      for _, char in pairs(chars) do
        if char.hasPendingLoot then play = true; break end
      end
    end
    if play then ns.Config:PlayAlert() end
  end
end

function VaultTracker:Rescan()
  ns.Scanner:Scan()
  ns.Broker:Update()
end

function VaultTracker:CancelDelayedRescans()
  if self.delayed then
    for _, t in ipairs(self.delayed) do self:CancelTimer(t) end
    self.delayed = nil
  end
end

function VaultTracker:OnVaultEvent()
  self:Rescan()
  -- Reward hyperlinks and the item info behind them load async, so the ilvl is
  -- often not ready the instant the event fires. Re-scan a couple times shortly
  -- after so earned-slot reward ilvls resolve and get cached.
  self:CancelDelayedRescans()
  self.delayed = {
    self:ScheduleTimer("Rescan", 2),
    self:ScheduleTimer("Rescan", 5),
  }
end
