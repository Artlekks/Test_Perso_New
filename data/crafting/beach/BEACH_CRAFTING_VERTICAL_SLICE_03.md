# Beach Crafting Vertical Slice 0.3 — Gathering + Feedback + A/B QA

## What changed

This pass moves the system from backend-only crafting into a playable beach loop.

### Authored beach visit

`BeachCraftingVerticalSliceWorld.tscn` contains:
- the placeholder crafter NPC
- one deterministic 10-node gathering circuit

The current Ocean-2 beach prototype receives this scene automatically through
`FishingSessionServices` after the fishing loadout binds. This deliberately
avoids overwriting the user's manually edited `FishingTestScene_V2.tscn`.

The bootstrap only injects when the current scene contains `World/beach`, and
it refuses to create a duplicate root.

### One visit = one gathering circuit

The ten nodes are:
- 3 Driftwood
- 2 Shell
- 2 Iron Scrap
- 2 Seaweed Fibre
- 1 Sea Glass

Each yields one material and is depleted until the beach scene is reloaded or
re-entered. That is the explicit V0.3 replenishment rule.

A complete visit therefore gives enough deterministic material for this
three-craft test plan:

1. Surface: Driftwood + Shell + Seaweed Fibre
2. Sinker: Shell + Iron Scrap + Sea Glass
3. Minnow: Driftwood + Iron Scrap + Seaweed Fibre

No RNG is required for the core crafting loop.

### Gathering feedback

Each gather now gives a screen message:
`+1 Driftwood    TOTAL 3`

For the authored circuit it also shows:
`BEACH VISIT   3 / 10 NODES`

Depleted placeholder meshes disappear so the beach visually records what has
already been collected during that visit.

### Crafting readability

Craft previews now explain the score in words:
- Buoyancy: Deep sink / Sinking / Neutral / Buoyant / High float
- Handling: Heavy / Slower control / Balanced / Responsive / Very responsive
- Attraction: Subtle / Normal / Noticeable / High visibility

The menu shows:
- owned count beside every selected material
- exact cost and whether it is affordable
- comparison against the currently equipped lure for depth, steering and
  attraction

### Controlled A/B test

Debug-only crafting menu key:
`T`

It creates:
- `[QA A] Float / Control Minnow`
- `[QA B] Deep / Flash Minnow`

A is equipped immediately. Both are real crafted lure records and enter the
normal fishing inventory/catalog, so the existing F10 `LURE` row can swap
between them while the same forced fish/environment is held constant.

This is intentional: the subjective "does it feel different?" test should use
the production fishing path, not a separate simulator.

### Automated QA

Beach Crafting QA now adds three tests:
- deterministic beach circuit supports three starter crafts
- A/B Minnows separate depth, handling and attraction in the intended direction
- every valid preview exposes readable qualitative property labels

Expected total:
`Beach Crafting QA: 10/10 tests passed (36 recipe combinations).`

## Still deliberately deferred

- production gather art
- shovel animation hookup
- day/night or timed respawn
- gathering skill/levels
- material rarity rolls
- recipe discovery
- crafting skill/failure
- cooking / rod / reel crafting
