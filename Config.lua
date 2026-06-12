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
      chatSummary = false,   -- print a who-needs-attention summary on login/reload
      bankedSound = false,   -- sound on login/reload if banked loot is waiting
      soundScope = "any",    -- "any" = any character account-wide; "current" = logged-in char only
      sound = "None",        -- LibSharedMedia "sound" key to play (pick a real one)
      autoPrune = false,     -- auto-remove characters not scanned in pruneWeeks
      pruneWeeks = 4,
    },
  },
}

local function deepcopy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = (type(v) == "table") and deepcopy(v) or v end
  return c
end

local LSM = LibStub("LibSharedMedia-3.0")

-- Play the configured alert sound via LibSharedMedia (file-based; the dropdown
-- lists whatever sounds are registered on this client).
function Config:PlayAlert()
  local path = LSM:Fetch("sound", ns.db.global.settings.sound)
  if path then PlaySoundFile(path, "Master") end
end

local function options()
  local s = ns.db.global.settings
  return {
    type = "group",
    name = "VaultTracker",
    args = {
      minimap = {
        type = "toggle", order = 0, width = "full", name = "Show minimap icon",
        get = function() return not s.minimap.hide end,
        set = function(_, v)
          s.minimap.hide = not v
          local DBIcon = LibStub("LibDBIcon-1.0")
          if v then DBIcon:Show("VaultTracker") else DBIcon:Hide("VaultTracker") end
        end,
      },
      remHeader = { type = "header", order = 1, name = "Reminders" },
      banked = {
        type = "toggle", order = 1.1, width = "full", name = "Unclaimed banked loot",
        desc = "Banked loot has no reset deadline — reminds you whenever any character has unclaimed loot waiting.",
        get = function() return s.triggers.banked end,
        set = function(_, v) s.triggers.banked = v; ns.Broker:Update() end,
      },
      beforeReset = {
        type = "group", order = 1.5, inline = true, name = "Weekly warnings",
        args = {
          thresholdDays = {
            type = "select", order = 4, width = 1.2, name = "How many days before reset?",
            desc = "How early before weekly reset untouched/incomplete vaults begin counting toward the reminder.",
            values = {
              [1] = "1 day",  [2] = "2 days", [3] = "3 days", [4] = "4 days",
              [5] = "5 days", [6] = "6 days", [7] = "7 days (all week)",
            },
            sorting = { 1, 2, 3, 4, 5, 6, 7 },
            get = function() return math.max(1, math.min(7, math.floor(s.thresholdHours / 24 + 0.5))) end,
            set = function(_, v) s.thresholdHours = v * 24; ns.Broker:Update() end,
          },
          remDesc = { type = "description", order = 1, name = "Remind me about:" },
          untouched = {
            type = "toggle", order = 2, name = "Untouched vaults",
            get = function() return s.triggers.untouched end,
            set = function(_, v) s.triggers.untouched = v; ns.Broker:Update() end,
          },
          incomplete = {
            type = "toggle", order = 3, name = "Incomplete vaults",
            get = function() return s.triggers.incomplete end,
            set = function(_, v) s.triggers.incomplete = v; ns.Broker:Update() end,
          },
        },
      },

      alertHeader = { type = "header", order = 10, name = "Alerts" },
      chatSummary = {
        type = "toggle", order = 11, width = "full", name = "Login chat summary",
        desc = "Print a who-needs-attention summary to chat on each login/reload.",
        get = function() return s.chatSummary end,
        set = function(_, v) s.chatSummary = v end,
      },
      bankedSound = {
        type = "toggle", order = 12, width = "full", name = "Sound when banked loot is waiting",
        desc = "Play a sound on login/reload if any character has unclaimed banked loot.",
        get = function() return s.bankedSound end,
        set = function(_, v) s.bankedSound = v; if v then Config:PlayAlert() end end,
      },
      sound = {
        type = "select", order = 13, width = 1.5, name = "Alert sound",
        desc = "Sound played when banked loot is waiting (LibSharedMedia). Picking one previews it.",
        disabled = function() return not s.bankedSound end,
        values = function()
          local v = {}
          for _, key in ipairs(LSM:List("sound")) do v[key] = key end
          return v
        end,
        get = function() return s.sound end,
        set = function(_, v) s.sound = v; Config:PlayAlert() end,
      },
      soundPreview = {
        type = "execute", order = 13.5, width = "half", name = "Preview",
        desc = "Play the selected alert sound again.",
        disabled = function() return not s.bankedSound end,
        func = function() Config:PlayAlert() end,
      },
      soundScope = {
        type = "select", order = 14, width = 1.5, name = "Play the sound for",
        desc = "Alert when any of your characters has banked loot, or only the one you log in on.",
        disabled = function() return not s.bankedSound end,
        values = { any = "Any character (account-wide)", current = "That character only" },
        get = function() return s.soundScope end,
        set = function(_, v) s.soundScope = v end,
      },


      dataHeader = { type = "header", order = 30, name = "Data" },
      autoPrune = {
        type = "toggle", order = 31, width = "full", name = "Auto-remove stale characters",
        desc = "Drop characters not scanned within the number of weeks below.",
        get = function() return s.autoPrune end,
        set = function(_, v) s.autoPrune = v end,
      },
      pruneWeeks = {
        type = "range", order = 32, name = "Weeks before a character is stale",
        min = 1, max = 52, step = 1,
        disabled = function() return not s.autoPrune end,
        get = function() return s.pruneWeeks end,
        set = function(_, v) s.pruneWeeks = v end,
      },
      clearCache = {
        type = "execute", order = 33, name = "Clear cache",
        desc = "Wipe all cached characters. They repopulate as you log into them.",
        confirm = true, confirmText = "Wipe all cached characters?",
        func = function() wipe(ns.db.global.characters); ns.Broker:Update() end,
      },
      resetSettings = {
        type = "execute", order = 34, name = "Reset settings",
        desc = "Reset all VaultTracker settings to defaults. Does not touch the character cache.",
        confirm = true, confirmText = "Reset all settings to defaults?",
        func = function() Config:ResetSettings() end,
      },
    },
  }
end

function Config:ResetSettings()
  local s = ns.db.global.settings
  wipe(s)
  for k, v in pairs(deepcopy(Config.defaults.global.settings)) do s[k] = v end
  ns.Broker:Update()
  local DBIcon = LibStub("LibDBIcon-1.0")
  if s.minimap.hide then DBIcon:Hide("VaultTracker") else DBIcon:Show("VaultTracker") end
end

function Config:Setup(addon)
  local AC = LibStub("AceConfig-3.0")
  AC:RegisterOptionsTable("VaultTracker", options)
  local dialog = LibStub("AceConfigDialog-3.0")
  -- AddToBlizOptions returns the frame and the Settings category ID; keep the ID
  -- so we open WoW's native AddOns settings panel rather than Ace's floating window.
  local _, categoryID = dialog:AddToBlizOptions("VaultTracker", "VaultTracker")
  self.blizCategory = categoryID
  addon:RegisterChatCommand("vt", function() Config:Open() end)
end

function Config:Open()
  Settings.OpenToCategory(self.blizCategory)
end
