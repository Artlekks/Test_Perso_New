# Triple Triad Balance Simulator V1

`triple_triad_balance_simulator.gd` runs real AI-vs-AI matches through the same
`TripleTriadMatch` resolver and `TripleTriadAI` used by gameplay.

## What it simulates

The five registry opponents are run in ordered host/challenger matchups. The host
supplies its real region and rule set, matching the conditions the player would
face when challenging that NPC. Starting owner alternates every game.

The report contains:

- overall first-player win rate and draw rate,
- captures per game,
- Same and Plus trigger frequency,
- Influence placements and affected-cell frequency,
- per-opponent wins/losses/draws and average scores,
- authored deck cost, total printed strength, Influence-card count, and
  rank-total-per-cost efficiency,
- ordered matchup win rates,
- per-card deck win rate, play rate, captures per placement, Same/Plus triggers,
  and Influence targets per placement.

## Running it

The `TripleTriadGame` script exposes:

`run_balance_simulation(games_per_matchup := 40, seed := 1337)`

It writes a JSON report to:

`user://triple_triad_balance_report.json`

For an automatic development run, enable `run_balance_simulation_on_startup` on
the TripleTriadGame node. The default sample is 40 games per ordered matchup,
which is 800 complete matches for a five-opponent registry. Keep it disabled for
normal play because it is intentionally CPU-heavy.

The simulator never touches player collections, progression, opponent saves, or
card-transfer journals.
