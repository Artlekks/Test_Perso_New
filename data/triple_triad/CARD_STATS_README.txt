Triple Triad card data backend

card_stats.json is now the authoritative portrait-card balance file.
- card_id is stable and must not change when the atlas is repacked.
- display_name can be replaced once portrait identities are assigned.
- level is 1-10.
- points is the deck-budget / strength value used by Rank sorting.
- ranks are top/right/bottom/left and must each be 1-10.
- group and tags are optional metadata for future filters/content rules.

The current 179 cards were seeded with exactly the same generated values they had before this pass, so gameplay balance does not suddenly change. New or missing entries still have a deterministic fallback, but catalog validation reports missing authored portrait stats when require_authored_portrait_stats is enabled.
