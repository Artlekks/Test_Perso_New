Triple Triad card data backend

card_stats.json is the authoritative portrait-card balance file.
- card_id is stable and must not change when the atlas is repacked.
- display_name can be replaced once portrait identities are assigned.
- level is 1-10.
- points is the deck-budget / strength value used by Rank sorting.
- ranks are top/right/bottom/left and must each be 1-10.
- group and tags are optional metadata for future filters/content rules.
- schema 3 adds optional Influence data without changing stable card IDs or saves.

Influence prototype entry:
    "influence": {
        "mode": "pressure",
        "strength": 1,
        "offsets": [[0, -1], [1, 0]]
    }

Offsets are authored relative to the card in its unrotated orientation. Rotate
rotates both directional numbers and the Influence pattern. Cards without an
Influence entry behave exactly as before.

The current 179 cards retain their existing balance values. Twelve temporary
prototype cards have pressure patterns purely for gameplay testing; these are
not final lore/rarity/character assignments. Six of the deterministic 10-card
fresh-save starter collection currently have Influence so the mechanic can be
playtested immediately.
