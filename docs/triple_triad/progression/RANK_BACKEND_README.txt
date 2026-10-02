TRIPLE TRIAD RANK BACKEND + BUGFIX

Bug fixes
---------
1. Fixed triple_triad_progression.gd parse errors:
   PackedInt32Array(...) constructors were incorrectly used as const expressions.
   The hard-coded arrays have now been removed entirely.

2. Fixed triple_triad_ai.gd parse error:
   plus_trigger_weight had lost its function indentation in the previous patch.

Next backend step: data-driven card-player ranks
------------------------------------------------
The Triple Triad rank architecture now mirrors the fishing progression architecture:
- TripleTriadRankDefinition resource
- TripleTriadProgressionCatalog resource
- authored progression resource at:
  res://data/triple_triad/progression/all_progression.tres
- rank validation
- rank IDs + display names
- editable thresholds
- editable deck-budget bonus per rank
- current-rank progress ratio
- points to next rank
- crossed-rank reporting for future rank-up UI
- persistent win/loss/draw/match totals
- automatic migration from progression save version 1 to version 2

Current placeholder curve is deliberately identical to the previous prototype:
Rank 1: 0 points, +0 budget
Rank 2: 6 points, +2 budget
Rank 3: 15 points, +4 budget
Rank 4: 30 points, +6 budget
Rank 5: 50 points, +8 budget
Rank 6: 80 points, +10 budget

The display names/thresholds are data now, so the final UI/rank naming can be
designed later without rewriting progression code.
