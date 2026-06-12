# VaultTracker Localization — Design

**Date:** 2026-06-11
**Status:** Approved design, pending implementation plan

## Context

Every user-facing string in VaultTracker is currently an inline English literal
spread across `Config.lua`, `Roster.lua`, `Broker.lua`, and `Format.lua`. This
blocks translation and makes wording changes hunt-and-peck. This pass centralizes
all of them behind **AceLocale-3.0** with an English (`enUS`) base and empty stubs
for other languages, so translators can later drop in locale files with zero code
changes. English output must remain byte-identical — this is a refactor, not a
behavior change.

This does **not** build any new feature. Three previously-queued items stay queued
because they are blocked on the running game, not on localization:
- **Champion/Hero "Upgrade Level:" tooltip** — does not exist yet; nothing to localize.
- **Track-header icons** — the *text* labels (Raid/Dungeon/World) ARE localized here;
  only the icon textures wait on a `GetAtlasInfo`-verified Great Vault atlas name.
- **World-slot source label** — no correct string exists until we observe what the
  `level` field means for world/delve slots in-game.

We will not invent guessed strings for blocked items.

## Approach

### Library
Vendor **AceLocale-3.0** (Ace3) under `Libs/AceLocale-3.0/`, add one `<Include>`
to `Libs/embeds.xml` after `AceConfig-3.0`. Untracked on disk like the other libs;
the user vets the source before committing.

### New files
```
Locales/enUS.lua   -- NewLocale("VaultTracker","enUS",true); L.KEY = "English"   (all keys)
Locales/deDE.lua   -- NewLocale("VaultTracker","deDE"); if not L then return end  (empty stub)
Locales/frFR.lua   -- same empty stub
Locale.lua         -- ns.L = LibStub("AceLocale-3.0"):GetLocale("VaultTracker")
```

`.toc` load order (insert before the logic modules):
```
Libs\embeds.xml
Locales\enUS.lua
Locales\deDE.lua
Locales\frFR.lua
Locale.lua
Derived.lua
... (unchanged)
```

Consumers read strings through `ns.L` (e.g. `ns.L.ROSTER_MPLUS`), matching the
existing `ns.Config` / `ns.Derived` namespace convention — `LibStub` is touched in
exactly one place (`Locale.lua`).

### Key scheme: domain + short name, English as the value
AceLocale keys are flat strings (no nesting). Keys are semantic, English supplied
as the value. Format strings stay format strings — the value holds the `%d`/`%s`.

```lua
-- Locales/enUS.lua
local L = LibStub("AceLocale-3.0"):NewLocale("VaultTracker", "enUS", true)
if not L then return end
L.OPT_MINIMAP   = "Show minimap icon"
L.TRACK_RAID    = "Raid"
L.ROSTER_SLOT   = "%s — Slot %d"
L.ROSTER_MPLUS  = "Mythic+ %d"
L.REASON_BANKED_BEST = "banked loot · best %d"
```
Call sites: `(ns.L.ROSTER_MPLUS):format(tier.level)`, `ns.L.ROSTER_REWARD_PENDING`.

### Not localized (intentional)
- Brand name "VaultTracker" where it stands alone (options group title `name`,
  Broker tooltip header line) — proper noun.
- Slash command `"vt"`.
- Texture/atlas/icon escape sequences and paths (`|TInterface\...|t`, ready-check
  texture, class-icon coords).
- Color escape codes (`|cff…|r`) and symbolic markers (`!`, `·`, `—`) — only the
  *words* wrapped by them are localized. The wrapping stays in code; e.g.
  `Format.summary`'s "All caught up." becomes `("|cff888888%s|r"):format(ns.L.SUMMARY_DONE)`.

## Key map (current strings → keys)

### Config.lua — `OPT_*`
| Key | English value |
|---|---|
| `OPT_MINIMAP` | Show minimap icon |
| `OPT_HDR_REMINDERS` | Reminders |
| `OPT_BANKED` / `OPT_BANKED_DESC` | Unclaimed banked loot / Banked loot has no reset deadline — reminds you whenever any character has unclaimed loot waiting. |
| `OPT_WEEKLY` | Weekly warnings |
| `OPT_THRESHOLD` / `OPT_THRESHOLD_DESC` | How many days before reset? / How early before weekly reset untouched/incomplete vaults begin counting toward the reminder. |
| `OPT_DAYS_1` … `OPT_DAYS_6` / `OPT_DAYS_7` | 1 day … 6 days / 7 days (all week) |
| `OPT_REMIND_ABOUT` | Remind me about: |
| `OPT_UNTOUCHED` | Untouched vaults |
| `OPT_INCOMPLETE` | Incomplete vaults |
| `OPT_HDR_ALERTS` | Alerts |
| `OPT_CHATSUMMARY` / `OPT_CHATSUMMARY_DESC` | Login chat summary / Print a who-needs-attention summary to chat on each login/reload. |
| `OPT_BANKEDSOUND` / `OPT_BANKEDSOUND_DESC` | Sound when banked loot is waiting / Play a sound on login/reload if any character has unclaimed banked loot. |
| `OPT_SOUND` / `OPT_SOUND_DESC` | Alert sound / Sound played when banked loot is waiting (LibSharedMedia). Picking one previews it. |
| `OPT_PREVIEW` / `OPT_PREVIEW_DESC` | Preview / Play the selected alert sound again. |
| `OPT_SOUNDSCOPE` / `OPT_SOUNDSCOPE_DESC` | Play the sound for / Alert when any of your characters has banked loot, or only the one you log in on. |
| `OPT_SCOPE_ANY` / `OPT_SCOPE_CURRENT` | Any character (account-wide) / That character only |
| `OPT_HDR_DATA` | Data |
| `OPT_AUTOPRUNE` / `OPT_AUTOPRUNE_DESC` | Auto-remove stale characters / Drop characters not scanned within the number of weeks below. |
| `OPT_PRUNEWEEKS` | Weeks before a character is stale |
| `OPT_CLEARCACHE` / `OPT_CLEARCACHE_DESC` / `OPT_CLEARCACHE_CONFIRM` | Clear cache / Wipe all cached characters. They repopulate as you log into them. / Wipe all cached characters? |
| `OPT_RESET` / `OPT_RESET_DESC` / `OPT_RESET_CONFIRM` | Reset settings / Reset all VaultTracker settings to defaults. Does not touch the character cache. / Reset all settings to defaults? |

### Roster.lua — `ROSTER_*`, `TRACK_*`, `TIME_*`
| Key | English value |
|---|---|
| `TRACK_RAID` / `TRACK_DUNGEON` / `TRACK_WORLD` | Raid / Dungeon / World |
| `ROSTER_COL_NAME` / `ROSTER_COL_ILVL` | Character / ilvl |
| `ROSTER_TITLE` | VaultTracker — Roster |
| `ROSTER_SLOT` | %s — Slot %d |
| `ROSTER_MPLUS` | Mythic+ %d |
| `ROSTER_REWARD` | Reward: item level %d |
| `ROSTER_REWARD_PENDING` | Reward: pending |
| `ROSTER_PROGRESS` | Progress: %d / %d |
| `ROSTER_UNLOCK_MORE` | %d more to unlock |
| `ROSTER_THISWEEK` | This week: |
| `ROSTER_RESETS` | Resets in %dd %dh |
| `ROSTER_EQUIPPED` | Equipped item level %d |
| `ROSTER_SCANNED` | Last scanned: |
| `ROSTER_INELIGIBLE` | Not yet eligible (no vault progress) |
| `TIME_NEVER` | never |
| `TIME_M` / `TIME_H` / `TIME_D` | %dm ago / %dh ago / %dd ago |

(Track column headers reuse `TRACK_RAID/DUNGEON/WORLD`; the `HEADERS` table's `text`
entries become locale lookups.)

### Broker.lua — `BROKER_*`
| Key | English value |
|---|---|
| `BROKER_LABEL` | Vault |
| `BROKER_NOTHING` | Nothing needs attention. |
| `BROKER_RESET` | Reset in %dh %dm |
| `BROKER_FOOTER` | Left-click: roster   Right-click: settings |

### Format.lua — `REASON_*`, `SUMMARY_*`
| Key | English value |
|---|---|
| `REASON_BANKED_BEST` | banked loot · best %d |
| `REASON_BANKED` | banked loot |
| `REASON_SLOTS` | %d/%d |
| `REASON_SLOTS_BEST` | %d/%d · best %d |
| `SUMMARY_DONE` | All caught up. |
| `SUMMARY_LINE` | %s %s-%s: %s |

## Test strategy

`tests/run.lua` builds a bare `ns = {}` and loads `Derived`, `Attention`, `Format`.
`Format.lua` will now reference `ns.L`, and its assertions check real English output
(e.g. `"banked loot · best 639"`, `"All caught up."`). A key-returning dummy would
break those assertions, so instead the runner loads the real `Locales/enUS.lua`:

Add a ~12-line `LibStub`/`AceLocale` shim at the top of `run.lua` so the locale file
can execute outside WoW:
```lua
local locales = {}
_G.LibStub = function(name)
  if name == "AceLocale-3.0" then
    return {
      NewLocale = function(_, app) locales[app] = locales[app] or {}; return locales[app] end,
      GetLocale = function(_, app) return locales[app] end,
    }
  end
end
```
Then `loadModule("Locales/enUS.lua", ns)` and `loadModule("Locale.lua", ns)` before
`Format.lua`, giving the tests the real `ns.L`. Single source of truth, no duplicated
strings, **all 66 assertions unchanged**. (Only `enUS` is loaded in tests; the deDE/frFR
stubs are not needed there.)

## Verification

1. `lua tests/run.lua` → 66 pass.
2. `lua -e "assert(loadfile('X.lua'))"` on every new and touched file (syntax).
3. User `/reload`s in-game and confirms the native settings panel, roster window,
   minimap tooltip, and login chat summary read identically in English.

## Out of scope (stays queued)

Champion/Hero "Upgrade Level:" tooltip (unbuilt), track-header *icon textures*
(need verified atlas), world-slot source label (need `level` meaning), per-character
control options.
