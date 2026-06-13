local ADDON, ns = ...
local Config = {}
ns.Config = Config

Config.defaults = {
  global = {
    characters = {},  -- bespoke cache, keyed by "name-realm" (see VaultTracker-spec.md)
    settings = {
      thresholdHours = 48,
      seriousness = "champion",  -- account-default tier line: veteran/champion/hero/myth
      showIgnored = false,       -- roster: reveal untracked/ignored characters (greyed)
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
  local L = ns.L
  return {
    type = "group",
    name = "VaultTracker",
    args = {
      minimap = {
        type = "toggle", order = 0, width = "full", name = L.OPT_MINIMAP,
        get = function() return not s.minimap.hide end,
        set = function(_, v)
          s.minimap.hide = not v
          local DBIcon = LibStub("LibDBIcon-1.0")
          if v then DBIcon:Show("VaultTracker") else DBIcon:Hide("VaultTracker") end
        end,
      },
      trackHeader = { type = "header", order = 0.4, name = L.OPT_HDR_TRACKING },
      seriousness = {
        type = "select", order = 0.5, width = 1.5, name = L.OPT_SERIOUSNESS,
        desc = L.OPT_SERIOUSNESS_DESC,
        values = { veteran = L.TIER_VETERAN, champion = L.TIER_CHAMPION,
                   hero = L.TIER_HERO, myth = L.TIER_MYTH },
        sorting = { "veteran", "champion", "hero", "myth" },
        get = function() return s.seriousness end,
        set = function(_, v) s.seriousness = v; ns.Broker:Update() end,
      },
      showIgnored = {
        type = "toggle", order = 0.6, width = "full", name = L.OPT_SHOWIGNORED,
        desc = L.OPT_SHOWIGNORED_DESC,
        get = function() return s.showIgnored end,
        set = function(_, v)
          s.showIgnored = v
          if ns.Roster.frame and ns.Roster.frame:IsShown() then ns.Roster:Refresh() end
        end,
      },
      remHeader = { type = "header", order = 1, name = L.OPT_HDR_REMINDERS },
      banked = {
        type = "toggle", order = 1.1, width = "full", name = L.OPT_BANKED,
        desc = L.OPT_BANKED_DESC,
        get = function() return s.triggers.banked end,
        set = function(_, v) s.triggers.banked = v; ns.Broker:Update() end,
      },
      beforeReset = {
        type = "group", order = 1.5, inline = true, name = L.OPT_WEEKLY,
        args = {
          thresholdDays = {
            type = "select", order = 4, width = 1.2, name = L.OPT_THRESHOLD,
            desc = L.OPT_THRESHOLD_DESC,
            values = {
              [1] = L.OPT_DAYS_1, [2] = L.OPT_DAYS_2, [3] = L.OPT_DAYS_3, [4] = L.OPT_DAYS_4,
              [5] = L.OPT_DAYS_5, [6] = L.OPT_DAYS_6, [7] = L.OPT_DAYS_7,
            },
            sorting = { 1, 2, 3, 4, 5, 6, 7 },
            get = function() return math.max(1, math.min(7, math.floor(s.thresholdHours / 24 + 0.5))) end,
            set = function(_, v) s.thresholdHours = v * 24; ns.Broker:Update() end,
          },
          remDesc = { type = "description", order = 1, name = L.OPT_REMIND_ABOUT },
          untouched = {
            type = "toggle", order = 2, name = L.OPT_UNTOUCHED,
            get = function() return s.triggers.untouched end,
            set = function(_, v) s.triggers.untouched = v; ns.Broker:Update() end,
          },
          incomplete = {
            type = "toggle", order = 3, name = L.OPT_INCOMPLETE,
            get = function() return s.triggers.incomplete end,
            set = function(_, v) s.triggers.incomplete = v; ns.Broker:Update() end,
          },
        },
      },

      alertHeader = { type = "header", order = 10, name = L.OPT_HDR_ALERTS },
      chatSummary = {
        type = "toggle", order = 11, width = "full", name = L.OPT_CHATSUMMARY,
        desc = L.OPT_CHATSUMMARY_DESC,
        get = function() return s.chatSummary end,
        set = function(_, v) s.chatSummary = v end,
      },
      bankedSound = {
        type = "toggle", order = 12, width = "full", name = L.OPT_BANKEDSOUND,
        desc = L.OPT_BANKEDSOUND_DESC,
        get = function() return s.bankedSound end,
        set = function(_, v) s.bankedSound = v; if v then Config:PlayAlert() end end,
      },
      sound = {
        type = "select", order = 13, width = 1.5, name = L.OPT_SOUND,
        desc = L.OPT_SOUND_DESC,
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
        type = "execute", order = 13.5, width = "half", name = L.OPT_PREVIEW,
        desc = L.OPT_PREVIEW_DESC,
        disabled = function() return not s.bankedSound end,
        func = function() Config:PlayAlert() end,
      },
      soundScope = {
        type = "select", order = 14, width = 1.5, name = L.OPT_SOUNDSCOPE,
        desc = L.OPT_SOUNDSCOPE_DESC,
        disabled = function() return not s.bankedSound end,
        values = { any = L.OPT_SCOPE_ANY, current = L.OPT_SCOPE_CURRENT },
        get = function() return s.soundScope end,
        set = function(_, v) s.soundScope = v end,
      },


      dataHeader = { type = "header", order = 30, name = L.OPT_HDR_DATA },
      autoPrune = {
        type = "toggle", order = 31, width = "full", name = L.OPT_AUTOPRUNE,
        desc = L.OPT_AUTOPRUNE_DESC,
        get = function() return s.autoPrune end,
        set = function(_, v) s.autoPrune = v end,
      },
      pruneWeeks = {
        type = "range", order = 32, name = L.OPT_PRUNEWEEKS,
        min = 1, max = 52, step = 1,
        disabled = function() return not s.autoPrune end,
        get = function() return s.pruneWeeks end,
        set = function(_, v) s.pruneWeeks = v end,
      },
      clearCache = {
        type = "execute", order = 33, name = L.OPT_CLEARCACHE,
        desc = L.OPT_CLEARCACHE_DESC,
        confirm = true, confirmText = L.OPT_CLEARCACHE_CONFIRM,
        func = function() wipe(ns.db.global.characters); ns.Broker:Update() end,
      },
      resetSettings = {
        type = "execute", order = 34, name = L.OPT_RESET,
        desc = L.OPT_RESET_DESC,
        confirm = true, confirmText = L.OPT_RESET_CONFIRM,
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
