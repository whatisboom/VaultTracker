# Configurable Options — Backlog

**Date:** 2026-06-13
**Status:** Backlog only — nothing committed, nothing to implement. A holding pen for
"this is hardcoded today; we *could* make it a user setting." Each entry records the
current value, where it lives, why someone might want a knob, and an honest lean on
whether it's worth one.

## Context

As the UI matures, more behavior is governed by constants chosen by feel (row glow
colours/intensity, separators, badge colours, sort order). Some are genuine user
preferences; most are dev-tuning values that should stay constants. This doc keeps
the distinction explicit so we don't reflexively turn every constant into an option
(option sprawl is its own cost) but also don't lose the ideas.

**Already configurable** (not repeated below): `thresholdHours`, trigger toggles,
`minimap.hide`, sounds (`bankedSound`/`soundScope`/`sound`), `chatSummary`,
`autoPrune`/`pruneWeeks` — all in `Config.defaults.global.settings` (Config.lua:8).

## Lean key

- **Setting** — plausible real user preference; worth an option if asked.
- **Constant** — keep hardcoded; expose only if a concrete user actually wants it.
- **Tuning** — internal feel value; almost certainly never a setting.

---

## Roster visuals

| Idea | Current (Roster.lua) | Why a user might want it | Lean |
|---|---|---|---|
| Toggle current-character highlight | always on; gold glow | some may find the gold band distracting | **Setting** |
| Current-char highlight colour | `GLOW_COLOR.current` = gold `ffd100` | personal taste / colourblind | Constant |
| Glow intensities | `GLOW_ALPHA` `{red .14, amber .10, current .14}` | "too loud / too subtle" | Tuning |
| Attention glow colours | `GLOW_COLOR.red/amber` | colourblind palettes | Constant (revisit if accessibility pass) |
| Track separators on/off + intensity | always on, white `0.14` | declutter | Tuning (toggle is **Constant** at most) |
| Row stripe / hover intensity | `0.025` / `0.07` | — | Tuning |
| Number alignment | right-aligned | — | Tuning (don't expose) |

Note: a single **"reduce visual noise"** toggle (drop stripes + separators + dim the
glows) would be a cleaner user-facing option than individual alpha sliders, if we ever
want one knob here.

## Broker / minimap badge

| Idea | Current (Broker.lua) | Why | Lean |
|---|---|---|---|
| Badge severity colours | `COLORS` `{red, amber, none}` (Broker.lua:5) | match UI theme / colourblind | Constant |
| What the badge text shows | count of attention chars | show worst-severity only, or hide count | **Setting** (if requested) |
| Tooltip verbosity | fixed layout | terse vs. full | Constant |

## Roster behaviour

| Idea | Current | Why | Lean |
|---|---|---|---|
| Sort order | attention rank → ilvl → name (`sortedKeys`, Roster.lua) | sort by name, by ilvl, by last-scan | **Setting** (low cost, real preference) |
| Per-track column visibility | all three shown | hide tracks you ignore | **Setting** |
| Window position persistence | movable, not saved across sessions (verify) | remember placement | **Setting** (verify current behaviour first) |
| Window scale | fixed | readability on high-DPI | Constant |

## Display format

| Idea | Current (Roster.lua `slotText`) | Why | Lean |
|---|---|---|---|
| Earned-slot rendering | ilvl when known, else ready-check icon | always show fraction, or always ilvl | Constant |
| Earned ilvl colour | green `38d13e` | taste | Tuning |

## Already specced / deferred — cross-references (do not duplicate here)

- **Eligibility / opt-in knobs** — `minLevel` (level floor) and `trackBarOverride`
  (reward-ilvl bar) are designed in
  [`2026-06-12-character-opt-in-design.md`](./2026-06-12-character-opt-in-design.md).
  This is the home for the "filter trivial world progress" idea we keep circling back
  to; it's already an account-wide auto baseline + manual raise. Not yet implemented.
- **Per-character controls** — manual mute / ignore / include / override eligibility
  per character. Deferred (its own brainstorm); explicitly out-of-scope of the opt-in
  spec, which only adds a single account-wide bar.

## Guidance for later

When promoting an entry to a real setting: add it to
`Config.defaults.global.settings` (Config.lua:8) with a sane default that preserves
today's behaviour, wire the AceConfig option + localized name/desc keys
(`Locales/enUS.lua`), and read it where the constant is used. Prefer **one meaningful
toggle** over a cluster of micro-sliders. Default every new option to the current
look so existing users see no change.
