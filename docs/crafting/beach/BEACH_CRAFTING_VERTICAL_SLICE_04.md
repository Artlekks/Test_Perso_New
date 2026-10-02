# Beach Crafting Vertical Slice 0.4 — Fishing Feel Validation

## Goal

Before adding more recipes or economy depth, prove that the three crafting
properties are perceptible in the production fishing game:

- Buoyancy
- Handling
- Attraction

Attraction was already perceptible in live play. This pass makes the other
properties testable under controlled conditions.

## Live QA HUD

Debug builds only.

Press `F8` while playing to toggle the Beach Crafting Feel QA HUD.

It shows:
- equipped lure
- crafted B/H/A scores
- actual steering strength
- actual attraction reference
- live lure depth / total water depth
- authored target depth
- nearest visible fish distance
- fish pre-bite state
- whether that fish is currently interested in the bait

The HUD does not change production fishing behavior.

## Controlled isolated pairs

While the F8 HUD is open:

`1` — Float / Sink
- same Handling
- same Attraction
- only Buoyancy differs

`2` — Heavy / Responsive
- same Buoyancy
- same Attraction
- only Handling differs

`3` — Subtle / Flash
- same Buoyancy
- same Handling
- only Attraction differs

The first use creates the six QA lure instances if they do not already exist.
The suite is idempotent: repeated use reuses the existing QA lures rather than
adding duplicates.

A lure swap changes the equipped loadout for the next cast. Recast after a swap.

Use the existing F10 Fishing QA menu to force the same fish / spot / shadow
conditions, then use F8 + 1/2/3 to compare the isolated lure property.

## Crafting NPC shortcut

In the crafting menu, debug key `T` pre-creates the complete Feel QA suite.
`F8` then opens the live telemetry.

## Automated QA

Four tests are added to the previous 10:

11. Buoyancy pair isolates depth.
12. Handling pair isolates steering.
13. Attraction pair isolates attraction.
14. Crafted-lure JSON record round-trip reconstructs the exact physical values.

Expected startup line:

`Beach Crafting QA: 14/14 tests passed (36 recipe combinations).`

## Decision rule

Do not add recipe/content volume yet.

If Float/Sink, Heavy/Responsive, and Subtle/Flash are reliably distinguishable
during controlled fishing tests, the three-property model is validated and
0.5 can move into economy/progression.

If one pair is not perceptible, tune the corresponding fishing response first.
