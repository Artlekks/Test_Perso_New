# Triple Triad — Influence Prototype v1

## Candidate core identity

**Directional numbers decide captures. Spatial Influence changes where those
numbers are favorable. Same rewards deliberately manufacturing equality.**

This is a gameplay prototype, not final card-content balance. The goal is to
prove that a 3x3 board can support deeper positional planning without replacing
the immediate readability of Triple-Triad-style four-number combat.

## Candidate baseline ruleset

`basic_rules.tres` currently enables:

- normal directional capture
- Same
- Combo from Same
- Influence
- one Rotate per player when the active region permits it

Plus remains implemented but is an advanced/optional ruleset. Same Wall and
Elemental remain reserved and runtime validation rejects them until implemented.

## Pressure Influence v1

Only one Influence mode exists in this prototype: `pressure`.

- An Influence card projects an authored 1-3 cell pattern from its board cell.
- Patterns are clipped at board edges; they never wrap to another row.
- Rotate rotates both the card's four numbers and its Influence pattern.
- Pressure strength is currently 1 on authored prototype cards.
- Pressure does not stack; the strongest opposing source affecting a cell wins.
- A card standing on an opponent-pressure cell has all four **effective** values
  reduced by that pressure amount, clamped to 1-10.
- Printed card values remain unchanged.
- Influence can therefore manufacture Same. Example: an enemy 6 becomes an
  effective 5, matching the placed card's 5 while another adjacent equality
  supplies the second Same match.
- A newly placed card projects Influence immediately for the placement being
  resolved.
- A card can itself be under previously established enemy pressure when placed.

## Resolution rule: no retroactive board simulation

Placement is the event that resolves combat. Influence changes effective values;
it does **not** continuously replay old comparisons.

For one placement, the Influence field and each occupied card's pressure modifier
are snapshotted before Same / Plus / normal capture / Combo are resolved. If a
card changes owner during that resolution, neither its projected Influence nor
its own pressure modifier changes halfway through the event. After the move is
finished, a captured Influence card projects for its new owner on the **next**
action.

This keeps outcomes deterministic, readable, and previewable while still making
capture of a control card strategically meaningful.

## Placement / preview interaction

Player flow is:

1. select a card from the hand
2. enter board-placement mode
3. move a ghost preview over legal empty cells
4. Rotate if desired
5. inspect projected Influence / effective number changes
6. press K to commit

The temporary implementation uses roughly 72% opacity for the ghost card.
Projected Influence cells receive an amber overlay; projected cells occupied by
an enemy receive a red pressure overlay. Existing board-card number displays use
the hypothetical effective values while previewing.

`TripleTriadMatch.preview_move()` is authoritative. Preview and commit use the
same capture/Influence resolver; UI presentation must not reimplement gameplay
math.

The final redesigned UI can replace these temporary overlays. The public card
snapshot already exposes authored Influence mode/strength/offsets for the user's
planned lower information panel / mini-grid diagram.

## Stake / match-flow decisions locked in this pass

- Deck setup can be cancelled freely before the live match begins.
- Once the deal has finished, abandoning the live match is surrender.
- Surrender resolves as an opponent win and follows the normal lost-card flow.
- A win reward is mandatory; Back cannot bypass card acquisition.
- On a loss/surrender the NPC selects the strongest player card by:
  1. highest Card Points (`deck_cost`)
  2. highest four-side rank total
  3. lexicographically lowest stable `card_id` as deterministic tie-breaker
- Rarity is intentionally not part of stake selection yet.

## Temporary authored prototype roster

Twelve cards currently carry pressure patterns. Six of the deterministic
fresh-save starter cards are included so Influence can be tested immediately.
These assignments are temporary and should be replaced when final card identity,
rarity and balance authoring begins.

## Explicitly deferred

- final rarity/tier scheme and portrait identity assignment
- final Influence distribution across the 179-card roster
- positive support/buff Influence
- stronger pressure / stacking rules
- Reversal/Disruption that deliberately rechecks an old clash
- Same Wall / Elemental
- campaign save-slot namespacing until the RPG has a save-slot service
- final Influence art, colors, card iconography and lower-panel layout

## Prototype success criteria

Playtesting should answer:

- Does Influence change where the player wants to place cards?
- Does it create deliberate Same setups rather than random arithmetic noise?
- Is a 3x3 board still readable at a glance?
- Does Rotate become more strategically valuable without becoming mandatory?
- Do tactically useful low-stat cards remain desirable?
- Can the player predict the committed result from the preview?
- Does the system remain fun when Same + Combo are baseline and Plus is absent?

Do not expand the mechanic vocabulary until this core loop is proven.


## Runtime UI contract — v1.2

The gameplay prototype now exposes an explicit runtime snapshot for the new UI.
Presentation code should not inspect `TripleTriadMatch` internals or recalculate
Influence. `TripleTriadGame.get_runtime_ui_snapshot()` is the UI-facing source.

It contains the selected card, its current rotation, a rotation-aware Influence
mini-grid, player/opponent hand data respecting the Open rule, board Influence
state, source attribution, effective ranks, and the authoritative placement
preview. `runtime_state_changed(snapshot)` is emitted after the existing
input-driven `_refresh_views()` path; there is still no per-frame backend work.

Placement previews now expose three distinct Influence views:

- `influence_before`: field before the ghost card is placed
- `influence_resolution`: frozen field used for this placement's capture rules
- `influence_next_action`: field after ownership changes, for the following turn
- `influence_deltas`: only cells whose effective state changes in the preview

This makes the current rule — captured control cards switch allegiance on the
next action, never mid-resolution — directly explainable by the UI without a
second gameplay implementation.
