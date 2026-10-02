# Triple Triad UI Visual Pass 02

This pass applies the supplied `CardGame_Background(2).png` and
`Atlas_Colors.png` without changing Triple Triad gameplay rules.

## Live match changes

- The supplied 640x480 background is now the single authored match backdrop.
  Its baked card backs are used for both hands and all empty board cells.
- The previous extra slot-guide overlay is no longer used.
- Scaled hand cards now use a zero pivot so their visible 74x88 footprint aligns
  exactly with the baked back slots (the previous centered pivot shifted them
  inward by about 20 px).
- Opponent score is displayed in the upper-left red banner; player score is in
  the upper-right blue banner. Bitmap digits scale down automatically for a
  two-digit score.
- The old beige InfoPanel is disabled.
- Runtime turn state is shown in the authored top-center banner.
- The region trait (`High Tide...`) is centered in the narrow black/gold box
  directly beneath the turn banner.

## Lower card information area

During player card/cell selection the lower panel now shows:

- full selected card in the left square,
- card name above the gold divider,
- short Influence description below the divider,
- rotation-aware 3x3 Influence pattern in the right box.

The pattern updates immediately when Rotate changes the selected card.

## Card visuals

- `Atlas_Colors.png` replaces the portrait atlas without changing atlas slots or
  stable card IDs.
- The supplied tint groups are mirrored into authored rarity data so the shared
  CardView automatically renders the matching Gold/Silver/Bronze frame.
- Full player/opponent ownership outlines are disabled. Selection is still shown
  by the existing hand arrow / board-cell selection treatment.
- `TripleTriadCardView.tscn` remains untouched; the user's manually tuned number
  positions are preserved.
