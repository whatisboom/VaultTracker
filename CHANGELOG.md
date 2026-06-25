# Changelog

All notable changes to VaultTracker are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-06-24

### Added
- **Banked-loot detail.** Unclaimed Great Vault rewards now show how many items are
  waiting and their item-level range (e.g. "3 items 626–639") in the minimap tooltip,
  the login summary, and a new **Banked** column in the roster window.
- **"Likely banked" hint.** A character you haven't logged into since the weekly reset
  is flagged as probably having loot waiting, clearly marked as unconfirmed until you
  log in to it.
- **Actionable reminders.** The login summary now tells you what to *do* —
  "1 more Mythic+", "2 more world activities" — instead of a bare slot count, and only
  when a vault slot is genuinely close to unlocking and the reward is worth your tier.
  New **Nudge distance** setting controls how close "close" is.
- **Show all characters** checkbox on the roster window, mirroring the options panel.
- **Right-click anywhere on a roster row** to open per-character settings (previously
  only the character name), with a hint on every row tooltip.

### Changed
- **Tracking is now sticky.** A character stays tracked once it has earned a qualifying
  reward, instead of dropping off during a week it does nothing; it resets at the M+
  season rollover. Changing the account threshold now asks whether to re-check existing
  characters or keep them.
- **Unclaimed loot is never missed.** Confirmed banked loot now surfaces regardless of
  whether a character meets your tracking threshold — except characters you've hidden.
- **"Hide" replaces "ignore."** A character you turn off now reads **Hidden**; one that
  simply hasn't earned enough reads **No qualifying reward yet** (previously both showed
  "Ignored"). The reveal option is now **Show all characters**.
- **Roster ordering and highlight.** Only unclaimed loot floats to the top; other
  reminders glow in place instead of reshuffling the list. The current character is
  highlighted in blue (was gold) so it reads apart from the warning colors.

### Fixed
- The banked-loot item-level range no longer disappears after the weekly reset — last
  week's snapshot is retained instead of being discarded by an early post-reset scan.
- A logged-in character with unclaimed loot is no longer shown as untracked and silent.
- Hidden characters no longer show banked info in the roster when **Show all** is on.

## [0.2.2] - 2026-06-15

### Changed
- Updated for WoW 12.0.7 (Interface 120007).

## [0.2.1] - 2026-06-15

### Fixed
- Raid vault tooltips now fill in the boss count instead of printing a literal
  `%d` (e.g. "Defeat 4 Midnight Season 1 Bosses").

### Changed
- Display name is now "Vault Tracker" across the options panel, roster window
  title, and broker tooltip.

## [0.2.0] - 2026-06-13

Seriousness-based tracking: a character now counts only once it earns rewards you
actually care about, expressed in the game's own upgrade tiers.

### Added
- **Seriousness gate.** A character is tracked once its best earned Great Vault
  reward reaches a tier line — Veteran < Champion < Hero < Myth. New account-wide
  **"Track characters from"** setting (default **Champion**), so trivial world-quest
  progress no longer pulls every alt into the roster and nudges.
- **Per-character tier line.** Right-click a roster row to set that character to
  **Auto / Veteran / Champion / Hero / Myth / Off**. "Off" silences it everywhere
  (roster, badge, sound), including banked-loot nudges.
- **Show ignored characters** option to reveal untracked/ignored characters in the
  roster, greyed.
- **Max-level only.** Only max-level characters are cached. Characters left below the
  cap after an expansion raises it are cleaned up automatically.
- Shared countdown formatter for the minimap reset tooltip ("6d 6h 30m", dropping
  leading zero units).

### Changed
- Reward tiers are read directly from each earned vault reward (locale-safe), so the
  gate uses the game's real upgrade track — no item-level guesswork.
- Banked-loot nudges now respect tracking: an ignored character stays silent.
- Roster polish: right-aligned item levels and slot counts, vertical separators
  between the three track groups, and a gold highlight on the current character.

### Removed
- The old "any progress = eligible" model and the "Not yet eligible" roster line.

### Migration
- Existing characters are grandfathered as tracked under the default tier and
  self-correct to their true tier on that character's next login. Use **Clear cache**
  for a clean reset.

## [0.1.0] - 2026-06-12

### Added
- First release. Account-wide Great Vault tracker: minimap nudge badge and tooltip,
  per-character roster window, and weekly reminders. Fully localized via
  AceLocale-3.0 (enUS base).

[0.3.0]: https://github.com/whatisboom/VaultTracker/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/whatisboom/VaultTracker/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/whatisboom/VaultTracker/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/whatisboom/VaultTracker/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/whatisboom/VaultTracker/releases/tag/v0.1.0
