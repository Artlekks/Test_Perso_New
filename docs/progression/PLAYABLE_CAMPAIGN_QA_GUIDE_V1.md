# Playable Campaign QA / Developer Guide v1

## Purpose

This debug-only overlay turns the campaign progression director into a practical playtest guide. It is intentionally read-only until the user explicitly applies a QA preset.

## Input

- `F10`: unchanged; opens the existing fishing QA menu while fishing.
- `Shift+F10`: opens the whole-campaign guide while exploring/fishing.
- `W/S`: select LIVE or a campaign checkpoint.
- `K`: inspect/apply. Destructive presets require a second `K` confirmation.
- `R`: refresh the LIVE snapshot from the progression director.
- `I`, `Esc`, or `Shift+F10`: close.

Inside an active Triple Triad session, `Shift+F10` remains owned by the existing card-specific Campaign QA harness so its match-safe tools are not disturbed.

## Checkpoints

The guide exposes the canonical playable-campaign spine:

1. Fresh Start
2. After First Fishing Trip
3. Hour 1 / Learn Loop
4. Hour 4 / Connected Systems
5. Hour 12 / Specialization

Each preset resets the current fishing/economy/card progression to a representative deterministic state, writes it through the existing system APIs / canonical Triple Triad QA harness, then reloads the scene. These are developer playtest states, not shipped save migrations.

## Safety

Preset application is intentionally destructive and requires two confirms. LIVE mode never mutates data. Normal F10 behavior is preserved.
