TRIPLE TRIAD BACKEND QA — BACKEND v1.1.0 / INFLUENCE PROTOTYPE

The QA harness is pure backend regression coverage. It does not read/write or
alter the player's collection, NPC collection, decks, progression, transfer
journal, acquisition history, or encounter records.

In debug builds TripleTriadGame can run it on startup. Gameplay dynamically
loads the harness only when QA is invoked, so release/runtime code has no hard
preload dependency on the QA script.

Current deterministic tests (21)
================================
1. Normal directional capture
2. Same
3. Plus
4. Same -> Combo
5. One Rotate per player
6. Regional cell rank modifier
7. Match-state invariant after placement
8. AI chooses a capture when capture weighting dominates
9. Card Duel Rank gating
10. Opponent-registry duplicate-ID rejection
11. Board rows do not wrap across flat-array boundaries
12. preview_move() does not mutate live state
13. Plus -> Combo
14. Region can disable Rotate
15. Opponent availability unlocks at required Duel Rank
16. Influence can manufacture Same by changing effective values
17. Rotate also rotates the authored Influence pattern
18. Influence modifiers stay frozen for one Same/Combo resolution
19. Captured Influence changes allegiance starting with the next action
20. Stake policy selects strongest card by points -> rank total -> stable ID
21. Unsupported Same Wall / Elemental toggles fail validation

Success output:
    TripleTriad QA: 21/21 backend tests passed.

Manual access:
    TripleTriadGame.run_backend_qa() -> Dictionary

The returned report contains passed/test_count/passed_count/failed_count,
failures and per-test results.
