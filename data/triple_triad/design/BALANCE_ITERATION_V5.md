# Triple Triad Balance Iteration V5

## Why V5 changes the measurement

V4 showed that small card substitutions could invert adjacent-rung results because
the old ladder check combined two different host environments. Each directed
matchup used the host NPC's authored region and rule set, so the number called
"ladder strength" mixed three variables:

1. deck + AI strength,
2. regional modifiers,
3. special rules.

That is useful for encounter flavor, but it is not a clean power-ladder metric.

## V5 policy

- Live scoring is unchanged. V4's global first-player decisive win rate was
  already close to 50%, so no initiative bonus is added.
- Beach Trader, Dock Bruiser and Tide Oracle return to their V3 authored deck
  baselines. Their content revisions are advanced so existing saves migrate.
- The simulator still runs the normal authored host-vs-challenger suite.
- `authored_home_ladder_checks` preserves the old two-home-environment view.
- `neutral_ladder_checks` runs every adjacent rung in both ownership
  orientations using Basic rules and no region modifiers.
- `ladder_checks` now points to the neutral benchmark and is the value to use
  when tuning the progression curve.

The next balance change should be based on the neutral ladder result. Home rules
may intentionally create favorable or unfavorable matchups as long as the
underlying progression remains sane and no encounter becomes unplayable.
