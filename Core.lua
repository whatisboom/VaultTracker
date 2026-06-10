local ADDON, ns = ...

local VaultTracker = LibStub("AceAddon-3.0"):NewAddon("VaultTracker",
  "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0")
ns.addon = VaultTracker

function VaultTracker:OnInitialize()
  self:Print("VaultTracker loaded.")
end
