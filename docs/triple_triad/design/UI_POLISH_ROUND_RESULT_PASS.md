TRIPLE TRIAD UI POLISH / ROUND / RESULT PASS

Changes:
- Restored the original untinted mugshot atlas. Atlas_Colors remains an authoring
  reference only; rarity IDs in card_stats.json still drive Bronze/Silver/Gold.
- Shifted both side hands exactly 1 logical pixel left.
- Reduced top score digits to ~85% of their previous size.
- Shifted red score left/down and blue score right/down.
- Added Round N in the small top dark strip. Current behavior starts at Round 1;
  a draw/redeal advances to Round 2, Round 3, etc.
- The lower selected-card panel no longer flashes empty after placement. As soon
  as the played card leaves the hand, the panel advances to the next remaining
  player card and stays populated through the opponent turn.
- Result screen now dims the board and strengthens the centered YOU WIN / YOU LOSE
  / YOU SURRENDER / DRAW text.
- Runtime UI snapshot schema is now 2 and exposes round_number.
- Backend version bumped to 1.2.2.

Intentionally untouched:
- Center 3x3 placement/grid coordinates.
- Lower info box coordinates.
- Card number layout / TripleTriadCardView.tscn.
- Side-hand background art itself; user is authoring a revised texture.
- Existing Bronze/Silver/Gold assignment derived from Atlas_Colors.
