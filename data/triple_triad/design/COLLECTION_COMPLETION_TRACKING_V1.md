# Triple Triad Collection Completion & Game Tracking V1

## Final result-screen authored coordinates

- OpponentRowRoot: X 73 / Y 112
- PlayerRowRoot: X 73 / Y 251
- focused TripleTriadCardView Y: 183
- FocusDim alpha: 75 / 255
- FooterHints: X -156 / Y 414 / scale 1.6
- PromptPanel Y: 44
- InfoPanel unchanged

These values are now treated as the authored baseline rather than runtime guesses.

## Three completion states

The backend deliberately separates three ideas:

1. `campaign_complete` — the Masters' Cup has been cleared and Card Master earned.
2. `collection_complete` — all 179 authored unique cards are currently owned.
3. `full_card_game_completion` — both of the above are true.

Losing a unique card to an opponent can therefore make the current collection fall
below 179/179 without revoking the permanent Card Master campaign achievement.

## Collection snapshot

`TripleTriadGame.get_collection_completion_snapshot()` exposes:

- 179-card total
- unique owned / total owned / missing unique
- current completion percentage
- highest unique-card count ever held
- permanent milestones at 25 / 50 / 100 / 150 / 179
- first 179/179 completion timestamp
- rarity completion breakdown
- card-group completion breakdown
- all missing-card diagnostics
- acquisition sources for every missing card
- Duel Rank locks for missing cards
- stolen-card holders for cards currently missing because of a stake loss
- progress for all 23 authored acquisition sources
- opponent defeat completion
- Regional Championship / Masters' Cup / titles / Card Master state
- lifetime matches / wins / losses / draws / win rates
- outstanding stolen cards

Convenience APIs:

`get_missing_card_diagnostics()`
`get_source_completion_snapshot()`

The normal global backend snapshot now also includes `completion` and
`competitive` sections.

## Persistent high-water tracking

`user://triple_triad_completion.cfg` stores only permanent completion history:

- highest unique-card count ever owned
- earned collection milestones
- timestamp of first 179/179 completion

The live collection percentage itself remains derived from the authoritative card
collection, so there is no second ownership database to desynchronize.

The completion save is protected by the existing save-integrity backup system.

## QA

Adds one non-persistent QA test proving that:

- exactly 179 unique authored cards are represented;
- an empty collection reports all 179 as missing;
- every missing card has at least one acquisition source;
- all 23 authored acquisition sources are represented.

Expected backend QA count: 32.
