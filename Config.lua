local ADDON, ns = ...
local Config = {}
ns.Config = Config

Config.defaults = {
  global = {
    characters = {},  -- bespoke cache, keyed by "name-realm" (see VaultTracker-spec.md)
    settings = {
      thresholdHours = 48,
      triggers = { banked = true, untouched = true, incomplete = true },
      minimap = { hide = false },
    },
  },
}

local function options()
  local s = ns.db.global.settings
  return {
    type = "group",
    name = "VaultTracker",
    args = {
      thresholdHours = {
        type = "range", order = 1, name = "Remind hours before reset",
        desc = "Untouched/incomplete vaults only nudge within this many hours of weekly reset.",
        min = 1, max = 168, step = 1,
        get = function() return s.thresholdHours end,
        set = function(_, v) s.thresholdHours = v; ns.Broker:Update() end,
      },
      banked = {
        type = "toggle", order = 2, name = "Nudge: unclaimed banked loot",
        get = function() return s.triggers.banked end,
        set = function(_, v) s.triggers.banked = v; ns.Broker:Update() end,
      },
      untouched = {
        type = "toggle", order = 3, name = "Nudge: untouched vault",
        get = function() return s.triggers.untouched end,
        set = function(_, v) s.triggers.untouched = v; ns.Broker:Update() end,
      },
      incomplete = {
        type = "toggle", order = 4, name = "Nudge: incomplete vault",
        get = function() return s.triggers.incomplete end,
        set = function(_, v) s.triggers.incomplete = v; ns.Broker:Update() end,
      },
      minimap = {
        type = "toggle", order = 5, name = "Show minimap icon",
        get = function() return not s.minimap.hide end,
        set = function(_, v)
          s.minimap.hide = not v
          local DBIcon = LibStub("LibDBIcon-1.0")
          if v then DBIcon:Show("VaultTracker") else DBIcon:Hide("VaultTracker") end
        end,
      },
    },
  }
end

function Config:Setup(addon)
  local AC = LibStub("AceConfig-3.0")
  AC:RegisterOptionsTable("VaultTracker", options)
  self.dialog = LibStub("AceConfigDialog-3.0")
  self.dialog:AddToBlizOptions("VaultTracker", "VaultTracker")
  addon:RegisterChatCommand("vt", function() Config:Open() end)
end

function Config:Open()
  self.dialog:Open("VaultTracker")
end
