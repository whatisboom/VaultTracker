# VaultTracker Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every user-facing string in VaultTracker behind AceLocale-3.0 (enUS base + empty deDE/frFR stubs) with zero change to English output.

**Architecture:** Vendor AceLocale-3.0. Add `Locales/enUS.lua` (all keys, English as value), empty stubs `deDE.lua`/`frFR.lua`, and `Locale.lua` that publishes `ns.L = GetLocale("VaultTracker")`. Consumers read strings via `ns.L.KEY`, matching the existing `ns.*` namespace convention. Keep the 66-test suite green by adding a tiny `LibStub`/`AceLocale` shim to `tests/run.lua` so it loads the real `enUS.lua`.

**Tech Stack:** Lua, WoW retail addon (Interface 120005), Ace3 (AceLocale-3.0), pure-Lua test runner at `tests/run.lua`.

**Source spec:** `docs/superpowers/specs/2026-06-11-localization-design.md`

**Commit policy (project rule):** Do NOT run `git commit`. Each "Checkpoint" step states what to verify and gives a suggested message; the user stages and commits.

---

## File Structure

- **Create** `Libs/AceLocale-3.0/` — vendored library (untracked, user vets source).
- **Modify** `Libs/embeds.xml` — add one `<Include>`.
- **Create** `Locales/enUS.lua` — every key, English values. Default locale.
- **Create** `Locales/deDE.lua`, `Locales/frFR.lua` — empty stubs.
- **Create** `Locale.lua` — `ns.L = LibStub("AceLocale-3.0"):GetLocale("VaultTracker")`.
- **Modify** `VaultTracker.toc` — load Locales + Locale.lua before logic modules.
- **Modify** `tests/run.lua` — LibStub/AceLocale shim + load enUS/Locale before Format.
- **Modify** `Format.lua`, `Config.lua`, `Roster.lua`, `Broker.lua` — replace string literals with `ns.L.*` lookups.

---

## Task 1: Vendor AceLocale-3.0 and register it in embeds.xml

**Files:**
- Create: `Libs/AceLocale-3.0/` (AceLocale-3.0.lua + AceLocale-3.0.xml from the Ace3 repo)
- Modify: `Libs/embeds.xml`

- [ ] **Step 1: Vendor the library**

Copy `AceLocale-3.0/` from the canonical Ace3 source (same origin as the other vendored Ace libs) into `Libs/AceLocale-3.0/`. It must contain `AceLocale-3.0.lua` and `AceLocale-3.0.xml`. Do not modify the library source.

- [ ] **Step 2: Add the include**

In `Libs/embeds.xml`, add the AceLocale include after the AceConfig line:

```xml
  <Include file="AceConfig-3.0\AceConfig-3.0.xml"/>
  <Include file="AceLocale-3.0\AceLocale-3.0.xml"/>
  <Include file="LibDataBroker-1.1\LibDataBroker-1.1.lua"/>
```

- [ ] **Step 3: Verify the library file loads (syntax)**

Run: `lua -e "assert(loadfile('Libs/AceLocale-3.0/AceLocale-3.0.lua'))"`
Expected: no output, exit 0.

- [ ] **Step 4: Checkpoint**

Verify `Libs/AceLocale-3.0/AceLocale-3.0.xml` and `.lua` exist and `embeds.xml` has the new line.
Suggested message: `chore: vendor AceLocale-3.0`

---

## Task 2: Create the enUS base locale with all keys

**Files:**
- Create: `Locales/enUS.lua`

- [ ] **Step 1: Write the file**

```lua
local L = LibStub("AceLocale-3.0"):NewLocale("VaultTracker", "enUS", true)
if not L then return end

-- Options (Config.lua)
L.OPT_MINIMAP            = "Show minimap icon"
L.OPT_HDR_REMINDERS      = "Reminders"
L.OPT_BANKED             = "Unclaimed banked loot"
L.OPT_BANKED_DESC        = "Banked loot has no reset deadline — reminds you whenever any character has unclaimed loot waiting."
L.OPT_WEEKLY             = "Weekly warnings"
L.OPT_THRESHOLD          = "How many days before reset?"
L.OPT_THRESHOLD_DESC     = "How early before weekly reset untouched/incomplete vaults begin counting toward the reminder."
L.OPT_DAYS_1             = "1 day"
L.OPT_DAYS_2             = "2 days"
L.OPT_DAYS_3             = "3 days"
L.OPT_DAYS_4             = "4 days"
L.OPT_DAYS_5             = "5 days"
L.OPT_DAYS_6             = "6 days"
L.OPT_DAYS_7             = "7 days (all week)"
L.OPT_REMIND_ABOUT       = "Remind me about:"
L.OPT_UNTOUCHED          = "Untouched vaults"
L.OPT_INCOMPLETE         = "Incomplete vaults"
L.OPT_HDR_ALERTS         = "Alerts"
L.OPT_CHATSUMMARY        = "Login chat summary"
L.OPT_CHATSUMMARY_DESC   = "Print a who-needs-attention summary to chat on each login/reload."
L.OPT_BANKEDSOUND        = "Sound when banked loot is waiting"
L.OPT_BANKEDSOUND_DESC   = "Play a sound on login/reload if any character has unclaimed banked loot."
L.OPT_SOUND              = "Alert sound"
L.OPT_SOUND_DESC         = "Sound played when banked loot is waiting (LibSharedMedia). Picking one previews it."
L.OPT_PREVIEW            = "Preview"
L.OPT_PREVIEW_DESC       = "Play the selected alert sound again."
L.OPT_SOUNDSCOPE         = "Play the sound for"
L.OPT_SOUNDSCOPE_DESC    = "Alert when any of your characters has banked loot, or only the one you log in on."
L.OPT_SCOPE_ANY          = "Any character (account-wide)"
L.OPT_SCOPE_CURRENT      = "That character only"
L.OPT_HDR_DATA           = "Data"
L.OPT_AUTOPRUNE          = "Auto-remove stale characters"
L.OPT_AUTOPRUNE_DESC     = "Drop characters not scanned within the number of weeks below."
L.OPT_PRUNEWEEKS         = "Weeks before a character is stale"
L.OPT_CLEARCACHE         = "Clear cache"
L.OPT_CLEARCACHE_DESC    = "Wipe all cached characters. They repopulate as you log into them."
L.OPT_CLEARCACHE_CONFIRM = "Wipe all cached characters?"
L.OPT_RESET              = "Reset settings"
L.OPT_RESET_DESC         = "Reset all VaultTracker settings to defaults. Does not touch the character cache."
L.OPT_RESET_CONFIRM      = "Reset all settings to defaults?"

-- Tracks (Roster.lua, also column headers)
L.TRACK_RAID    = "Raid"
L.TRACK_DUNGEON = "Dungeon"
L.TRACK_WORLD   = "World"

-- Roster window (Roster.lua)
L.ROSTER_COL_NAME       = "Character"
L.ROSTER_COL_ILVL       = "ilvl"
L.ROSTER_TITLE          = "VaultTracker — Roster"
L.ROSTER_SLOT           = "%s — Slot %d"
L.ROSTER_MPLUS          = "Mythic+ %d"
L.ROSTER_REWARD         = "Reward: item level %d"
L.ROSTER_REWARD_PENDING = "Reward: pending"
L.ROSTER_PROGRESS       = "Progress: %d / %d"
L.ROSTER_UNLOCK_MORE    = "%d more to unlock"
L.ROSTER_THISWEEK       = "This week: "
L.ROSTER_RESETS         = "Resets in %dd %dh"
L.ROSTER_EQUIPPED       = "Equipped item level %d"
L.ROSTER_SCANNED        = "Last scanned: "
L.ROSTER_INELIGIBLE     = "Not yet eligible (no vault progress)"
L.TIME_NEVER = "never"
L.TIME_M     = "%dm ago"
L.TIME_H     = "%dh ago"
L.TIME_D     = "%dd ago"

-- Broker / minimap tooltip (Broker.lua)
L.BROKER_LABEL   = "Vault"
L.BROKER_NOTHING = "Nothing needs attention."
L.BROKER_RESET   = "Reset in %dh %dm"
L.BROKER_FOOTER  = "Left-click: roster   Right-click: settings"

-- Tooltip reasons + chat summary (Format.lua)
L.REASON_BANKED_BEST = "banked loot · best %d"
L.REASON_BANKED      = "banked loot"
L.REASON_SLOTS       = "%d/%d"
L.REASON_SLOTS_BEST  = "%d/%d · best %d"
L.SUMMARY_DONE       = "All caught up."
L.SUMMARY_LINE       = "%s %s-%s: %s"
```

- [ ] **Step 2: Verify syntax**

Run: `lua -e "assert(loadfile('Locales/enUS.lua'))"`
Expected: no output, exit 0.

- [ ] **Step 3: Checkpoint**

Suggested message: `feat: add enUS base locale`

---

## Task 3: Create the empty locale stubs

**Files:**
- Create: `Locales/deDE.lua`
- Create: `Locales/frFR.lua`

- [ ] **Step 1: Write `Locales/deDE.lua`**

```lua
local L = LibStub("AceLocale-3.0"):NewLocale("VaultTracker", "deDE")
if not L then return end

-- Translations go here, e.g. L.OPT_MINIMAP = "Minimap-Symbol anzeigen"
-- Untranslated keys fall back to enUS automatically.
```

- [ ] **Step 2: Write `Locales/frFR.lua`**

```lua
local L = LibStub("AceLocale-3.0"):NewLocale("VaultTracker", "frFR")
if not L then return end

-- Translations go here, e.g. L.OPT_MINIMAP = "Afficher l'icône de minicarte"
-- Untranslated keys fall back to enUS automatically.
```

- [ ] **Step 3: Verify syntax**

Run: `lua -e "assert(loadfile('Locales/deDE.lua'))" && lua -e "assert(loadfile('Locales/frFR.lua'))"`
Expected: no output, exit 0.

- [ ] **Step 4: Checkpoint**

Suggested message: `feat: add deDE/frFR locale stubs`

---

## Task 4: Create Locale.lua (publish ns.L)

**Files:**
- Create: `Locale.lua`

- [ ] **Step 1: Write the file**

```lua
local ADDON, ns = ...
ns.L = LibStub("AceLocale-3.0"):GetLocale("VaultTracker")
```

- [ ] **Step 2: Verify syntax**

Run: `lua -e "assert(loadfile('Locale.lua'))"`
Expected: no output, exit 0.

- [ ] **Step 3: Checkpoint**

Suggested message: `feat: publish ns.L locale table`

---

## Task 5: Wire load order in the .toc

**Files:**
- Modify: `VaultTracker.toc`

- [ ] **Step 1: Insert the locale files before the logic modules**

Change the file list so it reads:

```
Libs\embeds.xml
Locales\enUS.lua
Locales\deDE.lua
Locales\frFR.lua
Locale.lua
Derived.lua
Attention.lua
Format.lua
Config.lua
Scanner.lua
Broker.lua
Roster.lua
Core.lua
```

- [ ] **Step 2: Checkpoint**

Verify the four new lines sit after `Libs\embeds.xml` and before `Derived.lua`.
Suggested message: `chore: load locale files in toc`

---

## Task 6: Add the test shim so run.lua loads the real locale

This must land BEFORE Format.lua is refactored, so `ns.L` exists when Task 7's code runs.

**Files:**
- Modify: `tests/run.lua:10-20`

- [ ] **Step 1: Add the LibStub/AceLocale shim and load the locale**

Replace the module-loading block (currently lines 10-20) with:

```lua
-- Load a WoW addon module the same way WoW does: chunk(addonName, ns).
local function loadModule(path, ns)
  local chunk = assert(loadfile(path))
  chunk("VaultTracker", ns)
end

-- Minimal LibStub/AceLocale shim so the real locale file loads outside WoW.
local locales = {}
_G.LibStub = function(name)
  if name == "AceLocale-3.0" then
    return {
      NewLocale = function(_, app) locales[app] = locales[app] or {}; return locales[app] end,
      GetLocale = function(_, app) return locales[app] end,
    }
  end
end

local F = dofile("tests/fixtures.lua")
local ns = {}
loadModule("Locales/enUS.lua", ns)
loadModule("Locale.lua", ns)
loadModule("Derived.lua", ns)
loadModule("Attention.lua", ns)
loadModule("Format.lua", ns)
```

- [ ] **Step 2: Run the suite (still passing, Format still uses literals)**

Run: `lua tests/run.lua`
Expected: all 66 pass (no assertion failures). `ns.L` is now populated but unused yet.

- [ ] **Step 3: Checkpoint**

Suggested message: `test: load real enUS locale in test runner`

---

## Task 7: Refactor Format.lua to use ns.L (66 tests are the safety net)

**Files:**
- Modify: `Format.lua:16-49`

- [ ] **Step 1: Run tests to capture the green baseline**

Run: `lua tests/run.lua`
Expected: all 66 pass.

- [ ] **Step 2: Replace the literals in `Format.tooltipReason`**

In `Format.lua`, change the body of `tooltipReason` (lines 18-33):

```lua
  local L = ns.L
  if has(entry.reasons, "banked") then
    local best = Derived.bankedBest(char)
    if best > 0 then return (L.REASON_BANKED_BEST):format(best) end
    return L.REASON_BANKED
  end
  local period = Derived.currentPeriod(char)
  if not period then return "" end
  local unlocked, total = Derived.periodSlots(period)
  if unlocked == 0 then
    return (L.REASON_SLOTS):format(unlocked, total)
  end
  local best = Derived.bestIlvl(period)
  if best > 0 then
    return (L.REASON_SLOTS_BEST):format(unlocked, total, best)
  end
  return (L.REASON_SLOTS):format(unlocked, total)
```

- [ ] **Step 3: Replace the literals in `Format.summary`**

Change the body of `summary` (lines 39-48):

```lua
  local L = ns.L
  if #list == 0 then
    return { ("|cff888888%s|r"):format(L.SUMMARY_DONE) }
  end
  local out = {}
  for _, e in ipairs(list) do
    local marker = (e.severity == "red") and "|cffff5555!|r" or "|cfff2c24a-|r"
    out[#out + 1] = (L.SUMMARY_LINE):format(marker, e.name, e.realm,
      Format.tooltipReason(e, chars[e.key]))
  end
  return out
```

- [ ] **Step 4: Run tests to verify identical output**

Run: `lua tests/run.lua`
Expected: all 66 pass. (Resolved strings are byte-identical to the old literals.)

- [ ] **Step 5: Verify syntax**

Run: `lua -e "assert(loadfile('Format.lua'))"`
Expected: no output, exit 0.

- [ ] **Step 6: Checkpoint**

Suggested message: `refactor: localize Format.lua strings`

---

## Task 8: Refactor Config.lua to use ns.L

**Files:**
- Modify: `Config.lua:37-156`

- [ ] **Step 1: Bind L at the top of `options()`**

In `Config.lua`, after `local s = ns.db.global.settings` (line 38), add:

```lua
  local L = ns.L
```

- [ ] **Step 2: Replace every option string**

Apply these substitutions inside the options table (keep the group `name = "VaultTracker"` as-is — it is the brand name). Each left side is the current literal; replace with the right side:

```
"Show minimap icon"                          -> L.OPT_MINIMAP
name = "Reminders"                           -> name = L.OPT_HDR_REMINDERS
"Unclaimed banked loot"                      -> L.OPT_BANKED
"Banked loot has no reset deadline …waiting."-> L.OPT_BANKED_DESC
"Weekly warnings"                            -> L.OPT_WEEKLY
"How many days before reset?"                -> L.OPT_THRESHOLD
"How early before weekly reset …reminder."   -> L.OPT_THRESHOLD_DESC
values = { [1]="1 day", ... [7]="7 days (all week)" }
                                             -> values = {
                                                  [1] = L.OPT_DAYS_1, [2] = L.OPT_DAYS_2, [3] = L.OPT_DAYS_3,
                                                  [4] = L.OPT_DAYS_4, [5] = L.OPT_DAYS_5, [6] = L.OPT_DAYS_6,
                                                  [7] = L.OPT_DAYS_7,
                                                }
"Remind me about:"                           -> L.OPT_REMIND_ABOUT
"Untouched vaults"                           -> L.OPT_UNTOUCHED
"Incomplete vaults"                          -> L.OPT_INCOMPLETE
name = "Alerts"                              -> name = L.OPT_HDR_ALERTS
"Login chat summary"                         -> L.OPT_CHATSUMMARY
"Print a who-needs-attention summary …reload."-> L.OPT_CHATSUMMARY_DESC
"Sound when banked loot is waiting"          -> L.OPT_BANKEDSOUND
"Play a sound on login/reload …banked loot." -> L.OPT_BANKEDSOUND_DESC
"Alert sound"                                -> L.OPT_SOUND
"Sound played when banked loot …previews it."-> L.OPT_SOUND_DESC
name = "Preview"                             -> name = L.OPT_PREVIEW
"Play the selected alert sound again."       -> L.OPT_PREVIEW_DESC
"Play the sound for"                         -> L.OPT_SOUNDSCOPE
"Alert when any of your characters …log in on."-> L.OPT_SOUNDSCOPE_DESC
values = { any = "Any character (account-wide)", current = "That character only" }
                                             -> values = { any = L.OPT_SCOPE_ANY, current = L.OPT_SCOPE_CURRENT }
name = "Data"                                -> name = L.OPT_HDR_DATA
"Auto-remove stale characters"               -> L.OPT_AUTOPRUNE
"Drop characters not scanned …weeks below."  -> L.OPT_AUTOPRUNE_DESC
"Weeks before a character is stale"          -> L.OPT_PRUNEWEEKS
"Clear cache"                                -> L.OPT_CLEARCACHE
"Wipe all cached characters. They repopulate…"-> L.OPT_CLEARCACHE_DESC
confirmText = "Wipe all cached characters?"  -> confirmText = L.OPT_CLEARCACHE_CONFIRM
"Reset settings"                             -> L.OPT_RESET
"Reset all VaultTracker settings to defaults…"-> L.OPT_RESET_DESC
confirmText = "Reset all settings to defaults?"-> confirmText = L.OPT_RESET_CONFIRM
```

Do NOT change: the `name = "VaultTracker"` group title, the `RegisterChatCommand("vt", …)` keyword, or any `values` built from `LSM:List("sound")`.

- [ ] **Step 3: Verify syntax**

Run: `lua -e "assert(loadfile('Config.lua'))"`
Expected: no output, exit 0. (Full behavior is confirmed in-game in Task 11.)

- [ ] **Step 4: Checkpoint**

Suggested message: `refactor: localize Config.lua strings`

---

## Task 9: Refactor Roster.lua to use ns.L

**Files:**
- Modify: `Roster.lua` (TRACK_LABEL/HEADERS at 26-30, `ago` at 40-46, `fillSlotTooltip` at 64-84, `resetText` at 115-118, title at 139, character tooltip at 248-250)

- [ ] **Step 1: Localize TRACK_LABEL and HEADERS**

`TRACK_LABEL` and `HEADERS` are built at file load (module top), before `ns.L` is guaranteed populated only if load order is correct — and it is (Locale.lua loads before Roster.lua). Replace lines 26-30:

```lua
local TRACK_LABEL = { raid = ns.L.TRACK_RAID, dungeon = ns.L.TRACK_DUNGEON, world = ns.L.TRACK_WORLD }
local HEADERS = {
  { key = "name", text = ns.L.ROSTER_COL_NAME }, { key = "ilvl", text = ns.L.ROSTER_COL_ILVL },
  { key = "raid", text = ns.L.TRACK_RAID }, { key = "dungeon", text = ns.L.TRACK_DUNGEON }, { key = "world", text = ns.L.TRACK_WORLD },
}
```

- [ ] **Step 2: Localize `ago()` (lines 41-45)**

```lua
local function ago(ts)
  if not ts then return ns.L.TIME_NEVER end
  local s = time() - ts
  if s < 3600 then return (ns.L.TIME_M):format(math.max(1, math.floor(s / 60))) end
  if s < 86400 then return (ns.L.TIME_H):format(math.floor(s / 3600)) end
  return (ns.L.TIME_D):format(math.floor(s / 86400))
end
```

- [ ] **Step 3: Localize `fillSlotTooltip()` (lines 65-82)**

```lua
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
```

- [ ] **Step 4: Localize `resetText()` (line 117)**

```lua
  return (ns.L.ROSTER_RESETS):format(math.floor(secs / 86400), math.floor((secs % 86400) / 3600))
```

- [ ] **Step 5: Localize the window title (line 139)**

```lua
  title:SetText(ns.L.ROSTER_TITLE)
```

- [ ] **Step 6: Localize the character tooltip (lines 248-250)**

```lua
      GameTooltip:AddLine((ns.L.ROSTER_EQUIPPED):format(char.ilvl or 0), 1, 0.82, 0)
      GameTooltip:AddLine(ns.L.ROSTER_SCANNED .. ago(char.lastScan), 0.6, 0.6, 0.6)
      if dim then GameTooltip:AddLine(ns.L.ROSTER_INELIGIBLE, 0.6, 0.5, 0.4) end
```

Do NOT change: the `READY_CHECK` texture, the `"|cff…—|r"` em-dash slot placeholder (line 272), `"?"` name fallbacks, or color escape codes.

- [ ] **Step 7: Verify syntax**

Run: `lua -e "assert(loadfile('Roster.lua'))"`
Expected: no output, exit 0.

- [ ] **Step 8: Checkpoint**

Suggested message: `refactor: localize Roster.lua strings`

---

## Task 10: Refactor Broker.lua to use ns.L

**Files:**
- Modify: `Broker.lua` (LDB text at 17 + 70, tooltip at 94-112)

- [ ] **Step 1: Localize the LDB default text (line 17)**

```lua
    text = ns.L.BROKER_LABEL,
```

- [ ] **Step 2: Localize the Update fallback text (line 70)**

```lua
  self.obj.text = hasAttention and tostring(s.count) or ns.L.BROKER_LABEL
```

- [ ] **Step 3: Localize the tooltip (lines 98, 110, 112)**

Line 98:
```lua
    tt:AddLine(ns.L.BROKER_NOTHING, 0.6, 0.6, 0.6)
```
Line 110:
```lua
  tt:AddLine((ns.L.BROKER_RESET):format(math.floor(secs / 3600), math.floor((secs % 3600) / 60)),
    0.5, 0.5, 0.5)
```
Line 112:
```lua
  tt:AddLine(ns.L.BROKER_FOOTER, 0.4, 0.4, 0.4)
```

Do NOT change: `tt:AddLine("VaultTracker")` header (line 94 — brand name), the `"|cffff5555!|r"`/`"|cfff2c24a·|r"` markers, the placeholder icon path (line 18), or the `VAULT_ATLASES` table.

- [ ] **Step 4: Verify syntax**

Run: `lua -e "assert(loadfile('Broker.lua'))"`
Expected: no output, exit 0.

- [ ] **Step 5: Checkpoint**

Suggested message: `refactor: localize Broker.lua strings`

---

## Task 11: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full unit suite**

Run: `lua tests/run.lua`
Expected: all 66 pass.

- [ ] **Step 2: Syntax-check every new and touched Lua file**

Run:
```bash
for f in Locales/enUS.lua Locales/deDE.lua Locales/frFR.lua Locale.lua Format.lua Config.lua Roster.lua Broker.lua; do
  lua -e "assert(loadfile('$f'))" && echo "ok $f"
done
```
Expected: `ok` for all eight.

- [ ] **Step 3: In-game smoke test (user)**

`/reload` in WoW and confirm, all reading identically in English:
- Settings panel (`/vt`): every option name/description, the days dropdown, sound scope values, and the two confirm dialogs.
- Roster window: title, column headers, slot tooltips (M+, raid string, reward/pending, progress), character tooltip (equipped ilvl, last scanned, ineligible note).
- Minimap tooltip: header, "Nothing needs attention." (when idle), reset line, footer.
- Login chat summary (enable it): "All caught up." and per-character lines.
- No Lua errors on load (missing-key references would error loudly).

- [ ] **Step 4: Final checkpoint**

Suggested message: `feat: complete localization pass (AceLocale-3.0)`

---

## Self-Review notes

- **Spec coverage:** Library (T1), enUS keys (T2), stubs (T3), ns.L publish (T4), toc order (T5), test shim (T6), and all four consumers Format/Config/Roster/Broker (T7-T10) each have a task. Every key in the spec's key map appears in T2 and is consumed in T7-T10.
- **Not-localized list honored:** brand name, `/vt`, textures/atlases, color/symbol escapes are explicitly excluded in T8-T10 "Do NOT change" notes.
- **Type/name consistency:** key names in enUS.lua (T2) match the `ns.L.*` references in T7-T10 exactly.
- **Ordering:** test shim (T6) precedes the Format refactor (T7) so `ns.L` exists before tests exercise it.
