TRIPLE TRIAD BACKEND QA PASS

This is the backend freeze-preparation pass.

Automatic debug QA
==================
In debug builds, TripleTriadGame now runs a pure backend QA suite on startup.
It does NOT read/write/alter the player's collection, NPC collection, deck,
progression, transfer journal or acquisition-history saves.

Current deterministic tests
===========================
1. Normal directional capture
2. Same
3. Plus
4. Same -> Combo chain
5. One Rotate per player
6. Regional cell rank modifier
7. Match-state invariant after placement
8. AI chooses a capture when capture weighting dominates
9. Card Duel Rank gating
10. Opponent-registry duplicate-ID rejection

Success output:
    TripleTriad QA: 10/10 backend tests passed.

Failure output names the exact failing test and reason.

Manual access
=============
TripleTriadGame exposes:
    run_backend_qa() -> Dictionary

The return report contains:
- passed
- test_count
- passed_count
- failed_count
- failures
- per-test results

The exported flag run_backend_qa_on_startup can disable automatic debug startup
execution if desired later.

Also included
=============
- Latest Plus-enabled match script
- Corrected Plus-aware AI script
- Plus-aware AI profile

No UI/card visuals are changed by this patch.
