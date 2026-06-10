# VaultTracker — Nudge System Design

## Context

`VaultTracker-spec.md` already defines a solid **data layer**: an account-wide
cache (`VaultTrackerDB`, keyed by `name-realm`) of each character's Great Vault
state, scanned via `C_WeeklyRewards` on vault events. What's missing is the
**product** — what the addon does with that cache.

Decision from brainstorming: the product is a **non-intrusive reminder/nudge
system**, surfaced through a **minimap icon** that watches *every* character
while you're logged into any one of them. The full multi-character dashboard
still exists, but demoted to an on-demand left-click view rather than the
primary surface.

This spec covers the product layer (UI, nudge logic, settings, eligibility) and
the small additions it requires to the cached data shape. The existing
data-layer scan logic from `VaultTracker-spec.md` is assumed and reused, not
redesigned.

## What we're building (settled decisions)

- **Primary surface:** minimap icon (LibDBIcon) with a color-coded badge + count.
- **Three nudge triggers:**
  - **Banked loot** — any character has `hasPendingLoot == true` (unclaimed prior-week rewards). *Always* counts; highest severity.
  - **Untouched vault** — an eligible character's current period is `isUntouched` (all 9 tiers progress 0). Counts only inside the time window.
  - **Incomplete vault** — an eligible character started but hasn't unlocked all realistically-reachable slots. Counts only inside the time window.
- **Time window:** untouched/incomplete contribute to the badge only within a configurable number of hours before weekly reset (**default 48h**), via `C_DateAndTime.GetSecondsUntilWeeklyReset()`.
- **Hover (tooltip):** the attention list — each character needing attention, the reason, and time-to-reset where relevant.
- **Left-click:** full roster window — every character, all 3 tracks, slot dots + per-slot reward ilvls (the dashboard).
- **Right-click:** settings panel.
- **Eligibility (key idea):** a character contributes to nudges only after it has demonstrated real vault engagement, signaled by `WEEKLY_REWARDS_UPDATE`. The flag is **sticky for the season** so an eligible character still nudges on a fresh untouched week. Never-engaged alts never get flagged → stay silent. No manual curation required.
- **Framework:** full Ace3 stack.

## Architecture

**Framework:** Ace3 stack + LibDataBroker/LibDBIcon.

- **AceAddon-3.0** — addon skeleton & lifecycle (`OnInitialize`, `OnEnable`); embeds AceEvent, AceConsole, AceTimer.
- **AceDB-3.0** — SavedVariables. The bespoke cache lives **untouched** under the free-form account-wide `global` scope (`self.db.global.characters`, keyed by `name-realm`, exactly the spec's shape). Settings live in their own account-wide scope (see below). AceDB does *not* reshape the cache.
- **AceConfig-3.0 / AceConfigDialog-3.0** — settings panel (Blizzard options entry + `/vt` slash command), driven by an options table.
- **AceEvent-3.0** — vault events (`PLAYER_ENTERING_WORLD`, `WEEKLY_REWARDS_UPDATE`, optionally `WEEKLY_REWARDS_SHOW`).
- **AceTimer-3.0** — periodic re-evaluation so the badge lights up when you cross into the time window mid-session.
- **AceGUI-3.0** — the roster window.
- **LibDataBroker-1.1 + LibDBIcon-1.0** — minimap button, tooltip (`OnTooltipShow`), click handlers.

**Module boundaries (one purpose each):**

| Module | Responsibility | Depends on |
|---|---|---|
| `Scanner` | Read `C_WeeklyRewards`, write cache entries (existing spec logic). Sets the sticky eligibility flag. | cache (`db.global`) |
| `Attention` | Pure function: cache + settings + seconds-to-reset → attention list (who, which trigger, severity). No UI, no API. | cache, settings |
| `Broker` | Owns the LDB object + LibDBIcon button. Renders badge count/color and tooltip from `Attention`. Wires clicks. | Attention, Roster, Config |
| `Roster` | AceGUI window: render every character's tracks/slots from the cache. | cache |
| `Config` | AceConfig options table + AceDB settings defaults. | settings |
| `Core` | AceAddon bootstrap, event registration, AceTimer tick → refresh Broker. | all |

`Attention` is deliberately a **pure, UI-free** unit so it's testable in
isolation (feed it a cache table + a fake "seconds to reset" and assert the
attention list) — and so Broker/Roster never duplicate trigger logic.

## Data shape additions

The spec's per-character entry gains two fields; nothing else changes:

```
VaultTrackerDB.characters["Veyra-Fenris"] = {
  ... (all existing spec fields: name, realm, class, spec, ilvl,
       lastScan, hasPendingLoot, currentWeekId, periods) ...
  eligible   = true,          -- sticky: set once real vault engagement is observed
  eligibleAt = 1780999200,    -- weekId/season marker, so eligibility can reset at season close
}
```

Plus a settings table (AceDB, account-wide so it matches the account-wide cache):

```
settings = {
  thresholdHours = 48,                 -- time window for untouched/incomplete
  triggers = { banked=true, untouched=true, incomplete=true },
  minimap = { hide=false },            -- LibDBIcon state
}
```

## Eligibility rule (precise)

- On a scan, if `WEEKLY_REWARDS_UPDATE` has fired for this character indicating a live vault (the activities query returns real tiers for the current period), set `eligible = true`, stamp `eligibleAt`.
- The flag is **sticky within a season** — an eligible character whose current week is untouched (progress 0) is still eligible, so the "untouched" nudge can fire. (Eligibility is about "is this a character I actually play the vault on," not "did they progress this week.")
- Only `eligible` characters contribute untouched/incomplete to the badge. Banked-loot nudges fire for any character with `hasPendingLoot` regardless (you must claim it no matter what).
- Eligibility may reset at season close (tied to `eligibleAt` vs. current season); season-boundary pruning is shared with the spec's existing "open question" about season-end expiry.

## Badge logic

- **Count** = number of distinct characters in the attention list.
- **Color/severity:** red if any banked-loot character exists; else amber if any time-window untouched/incomplete; else neutral/hidden.
- LibDBIcon shows an icon; the numeric badge is a small `FontString` overlaid on the LibDBIcon button (LibDBIcon has no native badge), updated by `Broker` on each refresh.
- Refresh triggers: vault events, AceTimer tick (e.g. every 60s, to catch crossing into the time window and the reset clock advancing), and after a manual scan.

## Settings panel (AceConfig)

- `thresholdHours` slider/input (default 48).
- Three toggles: enable banked / untouched / incomplete nudges.
- Show/hide minimap icon (LibDBIcon).
- Opened via right-click on the minimap icon and `/vt config`.

## Roster window (AceGUI, left-click)

Lists every cached character (eligible first, then others greyed), each showing:
name-realm (class-colored), equipped ilvl, pending-loot flag, and the 3 tracks
with slot dots (filled/empty by `slotsUnlocked`) and per-slot reward ilvls
(distinct per slot, per the spec's `slotIlvls` rule). Stale entries (cache from a
prior `currentWeekId`) are marked so prior-week state isn't misread as current —
a passive indicator only, **not** a nudge (stale-scan was explicitly excluded as
a trigger).

## File structure

```
VaultTracker.toc            -- load order, SavedVariables: VaultTrackerDB; embeds Libs
Libs/                       -- Ace3, LibDataBroker-1.1, LibDBIcon-1.0 (+ embeds.xml)
Core.lua                    -- AceAddon bootstrap, events, timer
Scanner.lua                 -- existing-spec scan logic + eligibility flag
Attention.lua               -- pure trigger logic (cache+settings+reset -> list)
Broker.lua                  -- LDB object, LibDBIcon button, badge, tooltip, clicks
Roster.lua                  -- AceGUI dashboard
Config.lua                  -- AceConfig options + AceDB defaults
```

(Module split is for clarity; some may be merged during implementation if a file
stays trivially small.)

## Verification

WoW addons can't be unit-tested headlessly without a Lua harness, so verify in
two layers:

1. **Pure logic — `Attention`** can be exercised outside the game: run it under
   plain Lua with hand-built cache tables and a stubbed "seconds to reset",
   asserting the attention list for each scenario (banked only; untouched inside
   vs. outside the window; incomplete; ineligible alt stays silent; sticky
   eligibility on an untouched week). This is where the real test value is.
2. **In-game smoke test** (`/reload` in WoW):
   - Fresh character with vault activity → `eligible` set, appears in roster.
   - Set `thresholdHours` high → untouched/incomplete appear immediately; set low → they drop off; badge count/color update on the AceTimer tick.
   - Character with banked loot → red badge regardless of window.
   - Right-click → settings; left-click → roster; hover → attention tooltip.
   - Never-engaged bank alt → never raises the badge.

## Open questions carried from the data spec

- `GetExampleRewardItemHyperlinks` exact-vs-illustrative ilvl (affects slot ilvl display fidelity in the roster).
- Season-end pruning / eligibility reset boundary.
- Whether current-period tiers are readable while `hasPendingLoot` is true.

These affect display fidelity and pruning, not the nudge architecture.
