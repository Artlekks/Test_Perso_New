# Beach Crafting Vertical Slice 0.1

## Goal

Prove one loop:

Explore beach -> gather understandable materials -> craft a lure -> feel the
difference during fishing.

Gathering is intentionally deterministic. Crafting is where the decision lives.

## Materials

- Driftwood: +2 Buoyancy, +1 Handling
- Shell: +1 Handling, +1 Attraction
- Sea Glass: +2 Attraction
- Iron Scrap: -2 Buoyancy, -1 Handling
- Seaweed Fibre: +2 Handling

Gather nodes are one-shot per scene load in V0.1. They are not yet a final
respawn/economy design.

Reusable actor:
`res://actors/BeachGatheringNode3D.tscn`

Preconfigured drag/drop actors:
- DriftwoodGatherNode.tscn
- ShellGatherNode.tscn
- SeaGlassGatherNode.tscn
- IronScrapGatherNode.tscn
- SeaweedGatherNode.tscn

## Recipes

### Beach Minnow
Template: existing Floater behavior.

Body:
- Driftwood
- Shell

Core:
- Iron Scrap
- Shell

Accent (optional):
- Sea Glass
- Seaweed Fibre

### Beach Surface Lure
Template: existing Popper behavior.
Baseline: +1 Buoyancy, +1 Handling.
Its core may be Fibre, Shell, or Iron Scrap, so even a surface recipe can be made slightly heavier.

### Beach Sinker
Template: existing Hanger/suspending-minnow behavior.
Baseline: -2 Buoyancy, -1 Handling.
Iron Scrap is required as its core.

## Runtime mapping

Crafting does not add a second fishing physics system.

The three crafting properties are converted into the fishing variables that
already exist:

Buoyancy:
- modifies sink depth
- modifies sink speed

Handling:
- modifies reel steering strength
- slightly modifies reel speed

Attraction:
- duplicates the lure's existing action profile
- multiplies idle/reeling attraction values

This means crafted lures immediately participate in current fish compatibility,
movement, bite, lure action, snag, fight, inventory and loadout systems.

## Crafted lure instances

Each craft creates a stable unique id such as:
`crafted_beach_minnow_001`

Crafted lure definitions are persisted in:
`user://beach_crafted_lures.json`

Material quantities are persisted in:
`user://beach_gathering_inventory.json`

On session startup, saved crafted lures are reconstructed as runtime BaitData
resources and registered into the existing lure catalog before loadout/save
integrity is resolved.

## Crafter NPC

Reusable placeholder:
`res://actors/BeachCrafterNPC.tscn`

For now it deliberately reuses the existing beach merchant sprite art. Replace
the art later without changing the crafting backend.

Controls:
- W/S: recipe
- A/D: material for active slot
- J: Body / Core / Accent slot
- K: craft
- I: back
- Debug builds only: R grants +10 of all five materials

The crafted lure goes into the existing FishingInventory and can be equipped
through the normal lure/loadout path.

## What V0.1 deliberately does not solve

- crafting skill/levels
- recipe discovery
- cooking
- rod/reel crafting
- material quality
- gathering skill
- respawn timing
- production art/animations
- shops buying materials
- global non-fishing item inventory
- crafting failure chance

The next design question is experiential:
Can two material variants of the same recipe be identified by feel while
fishing without reading their stats?
