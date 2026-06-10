# Great Vault Tracker — Data Planning

A WoW addon that caches each character's Great Vault state to a shared
account-wide SavedVariables table. Each character can only scan itself (the API
exposes vault data for the logged-in character only), so the table is a cache of
per-character snapshots, CraftSim-style. The cache is best-effort and
self-correcting: the API is the source of truth, the cache trails it and
re-syncs on the next scan. If state was changed elsewhere (claimed on another
computer, SavedVariables wiped), the next scan reconciles by overwriting.

This doc defines the stored data shape and the derived values computed from it.

---

## Two orthogonal states

Current-period progress and banked unclaimed loot are independent axes; the game
models them separately:

- **Current period** — the vault you're actively filling this week. Governed by
  `weekId` rolling forward at reset. Always present in the cache, overwritten
  each scan.
- **Banked periods** — vaults from prior weeks that were never claimed. Loot
  persists across resets until collected (or until season close). Governed by
  the pending-loot flag.

`HasAvailableRewards()` reports ONLY on banked periods. A fresh current period
with nothing banked returns `false` even while you're racking up activities for
it. So `hasPendingLoot == false` unambiguously means "no banked periods exist"
— it is never confused with "current period not started."

## Events that trigger a scan

- `PLAYER_ENTERING_WORLD` — initial scan on login.
- `WEEKLY_REWARDS_UPDATE` — primary trigger; fires when vault data changes or
  the vault UI opens. Re-scan and write.
- `WEEKLY_REWARDS_SHOW` — optional; vault UI opened, data is fresh.

## Track enums

The three tracks map to `Enum.WeeklyRewardChestThresholdType`:
- Raid    → `.Raid`
- Dungeon → `.Activities`  (M+ / Heroic / Timewalking)
- World   → `.World`       (includes Delves)

`C_WeeklyRewards.GetActivities(trackType)` returns the tiers for a track. Each
tier carries `threshold`, `progress`, `level`, and `id`. The reward ilvl for a
tier comes from resolving `tier.id` via `GetExampleRewardItemHyperlinks` →
`GetDetailedItemLevelInfo`.

Pending loot: `C_WeeklyRewards.HasAvailableRewards()` → boolean, TRUE when one
or more banked (prior-period) vaults are unclaimed.

## Data shape (SavedVariables)

`VaultTrackerDB` keyed by `"name-realm"`. Raw scanned values only — nothing
derived is stored. No per-period "claimed" flag: a period's presence in
`periods` IS its unclaimed state.

```
VaultTrackerDB = {
  ["Veyra-Fenris"] = {
    name      = "Veyra",
    realm     = "Fenris",
    class     = "PRIEST",        -- locale-independent token (UnitClassBase)
    spec      = "Shadow",
    ilvl      = 148,             -- equipped item level, floored
    lastScan  = 1781046243,      -- epoch of this scan
    hasPendingLoot = false,      -- HasAvailableRewards(): any banked vaults?
    currentWeekId  = 1780999200, -- period the current-period snapshot reflects
    periods = {
      -- current period: always present, overwritten each scan
      [1780999200] = {
        tracks = {
          raid    = { {threshold=2, progress=2, level=0, rewardIlvl=259},
                      {threshold=4, progress=0, level=0, rewardIlvl=0},
                      {threshold=6, progress=0, level=0, rewardIlvl=0} },
          dungeon = { {threshold=1, progress=0, level=0, rewardIlvl=0},
                      {threshold=4, progress=0, level=0, rewardIlvl=0},
                      {threshold=8, progress=0, level=0, rewardIlvl=0} },
          world   = { {threshold=2, progress=2, level=0, rewardIlvl=272},
                      {threshold=4, progress=2, level=0, rewardIlvl=0},
                      {threshold=8, progress=2, level=0, rewardIlvl=0} },
        },
      },
      -- banked prior period(s): present only while unclaimed
      [1780394400] = { tracks = { raid={...}, dungeon={...}, world={...} } },
    },
  },
  -- one entry per character
}
```

Rules:
- Tiers sorted ascending by threshold, so index 1/2/3 = slot 1/2/3.
- `rewardIlvl = 0` / nil = not resolvable (slot not unlocked, or couldn't read).
- A character's current-period snapshot is overwritten wholesale on each scan —
  never merged.
- `periods` is keyed by `weekId` (period-start epoch).

## Banked-period lifecycle

- On reset, the period that was current becomes a banked period (it stays in
  `periods` under its own `weekId`; a new current-period entry is written under
  the new `currentWeekId`).
- **Deletion rule:** when a scan returns `HasAvailableRewards() == false`, delete
  every period in `periods` older than `currentWeekId`. No pending loot means
  nothing is banked — clear them regardless of how they were claimed.
- A banked period only has detail for weeks the character was actually scanned
  during. Gaps (didn't log in) leave no snapshot; you'll know loot is banked via
  the flag but have no slot detail for unobserved weeks.
- Pruning beyond the deletion rule (e.g. season-end expiry) is an open question.

## Derived values (computed from the raw data, never stored)

Per track (3 tiers):
- **slotsUnlocked** = count of tiers where `progress >= threshold`.
- **xToNext** = for the lowest unmet tier, `threshold - progress`; nil if maxed.
- **slotIlvls** = the per-tier `rewardIlvl` values in slot order. DISTINCT per
  slot — do not collapse to one value. The vault fills each slot from run
  history, so one M+11 plus seven M+2 can unlock all three dungeon slots while
  only one slot offers the +11 reward and the others offer the +2-level reward.

Per character:
- **bestIlvl** = max `rewardIlvl` across all unlocked tiers in a period. Summary
  only — "single best slot claimable," never a per-slot value.
- **isMaxed** = all 9 tiers of the current period unlocked.
- **isUntouched** = all 9 tiers of the current period at progress 0.
- **hasPendingLoot** = stored directly.

## Open questions / caveats

- `GetExampleRewardItemHyperlinks` is named "Example" — confirm during testing
  whether it returns the exact ilvl for a filled slot vs. an illustrative one.
  If only illustrative for unfilled slots, per-tier `level` (tied to the actual
  filling run) is the more trustworthy signal.
- Minor: confirm a scan can read current-period tiers while `hasPendingLoot` is
  true. The default UI gates current-vault visibility behind claiming the
  pending one, but that may be a UX choice rather than an API limit (the two
  states are orthogonal). Data shape works either way.
