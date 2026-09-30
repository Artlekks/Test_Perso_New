TRIPLE TRIAD PROGRESSION + PLUS PASS

Progression
-----------
- Existing player deck budget remains the baseline (currently 30).
- Rank thresholds: 0, 6, 15, 30, 50, 80 progression points.
- Rank budget bonuses: +0, +2, +4, +6, +8, +10.
- Default win reward: 3 points.
- Losses/draws award 0 progression points but are recorded in stats.
- Each opponent can override the win reward with progression_points_on_win.
- QA/debug matches do not alter permanent progression.
- Save file: user://triple_triad_progression.cfg

Plus
----
- Plus compares the sums of touching values around the newly placed card.
- If two or more adjacent sums match, Plus triggers.
- Enemy cards participating in matching sums flip.
- Cards flipped by Plus can seed Combo.
- Same and Plus can trigger on the same placement.
- AI preview/scoring now understands Plus.
- data/triple_triad/plus_rules.tres is provided for testing/authoring.
- The existing default rule resource is NOT changed automatically.
