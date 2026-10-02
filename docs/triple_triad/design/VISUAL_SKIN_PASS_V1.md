# Triple Triad Visual Skin Pass — first authored UI integration

This pass integrates the first supplied visual assets without making content
decisions that have not been authored yet.

## Used now

- `CardGame_Background.png` becomes the live match background.
- `CardGame_Slot_Guides.png` is derived from the supplied
  `CardGame_Frame_Front` and keeps only the hand/board slot guides. The unused
  yellow lower placeholder is intentionally removed.
- `Card_Back.png` is derived from one complete center card in the supplied
  `CardGame_Back` layout and becomes the real reusable hidden-card/reward-flip
  back.
- The live match layout is aligned to the authored 640x480 art:
  - board origin: `(210, 107)`
  - card footprint: `74x88`
  - opponent hand: `(42, 95)`
  - player hand: `(526, 95)`
  - hand overlap step: `47`

## Bronze / Silver / Gold

The supplied frames are installed and `TripleTriadCardView` now knows how to
render them from `card.rarity_id`.

No card is silently assigned a tier in this pass.

Current backend data still uses the temporary `standard` rarity, so the rarity
overlay stays hidden until the actual Bronze/Silver/Gold assignments are
authored. Once a card's `rarity_id` is set to `bronze`, `silver`, or `gold`, the
correct frame appears automatically everywhere the shared CardView is used.

## Deliberately untouched

`actors/TripleTriadCardView.tscn` is not modified. The manually tuned bitmap
number layout remains the source of truth. Complete CardViews are scaled at the
presentation layer to fit the new 74x88 UI art.

The lower information/influence panel is not filled in here; the v1.2 runtime
UI contract already exposes the data needed for that next visual pass.
