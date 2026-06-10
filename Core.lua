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
  self:RegisterEvent("WEEKLY_REWARDS_SHOW", "OnVaultEvent")
  -- Re-evaluate each minute so the badge lights up on crossing into the
  -- time window and the reset clock advances.
  self.refreshTimer = self:ScheduleRepeatingTimer(function() ns.Broker:Update() end, 60)
  self:OnVaultEvent()
end

function VaultTracker:OnVaultEvent()
  ns.Scanner:Scan()
  ns.Broker:Update()
end
