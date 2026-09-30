TRIPLE TRIAD PUBLIC API + OPPONENT RECORDS PASS

This is the final planned feature/backend layer before the full backend audit.

Persistent opponent records
===========================
New save:
    user://triple_triad_encounter_records.cfg

Per opponent:
- matches / player wins / player losses / draws
- beaten_before
- first win timestamp
- last result / last played timestamp
- cards won from that NPC
- cards lost to that NPC
- stolen cards recovered
- exact cards/quantities currently stolen from the player

Records update only after real match/ownership actions succeed.
QA/debug-profile matches do not change encounter records.

Public state API
================
New:
    res://scripts/triple_triad/triple_triad_state_api.gd

TripleTriadGame now exposes:
    get_state_api()
    get_player_snapshot()
    get_collection_snapshot()
    get_deck_profiles_snapshot()
    get_opponent_snapshot(opponent_id)
    get_opponents_snapshot()
    get_global_triple_triad_snapshot()

Future UI should consume these snapshots instead of reaching into backend
objects or reading save files itself.

The snapshots expose:
- player Duel Rank / points / progress / deck budget / W-L-D
- collection quantities + card stats + future rarity/rank fields
- all six deck profiles, legality and invalid reasons
- opponent availability, Duel Rank, native/preferred cards
- persistent NPC current collection/deck/priorities
- per-NPC records and stolen-player cards
- acquisition history
- runtime active-opponent/phase information

State-change signal
===================
TripleTriadGame emits:
    backend_state_changed(reason)

Current reasons:
    match_result
    card_transfer
    deck_selected

Save integrity
==============
Encounter records are now part of the protected semantic backup set.

NEXT
====
Run the requested FULL BACKEND AUDIT and fix all findings in one backend-freeze
patch. After the audit/freeze, move to the redesigned visual/UI integration.
