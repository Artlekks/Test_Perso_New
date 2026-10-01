TRIPLE TRIAD PUBLIC API + OPPONENT RECORDS — BACKEND v1.1.0

The public state API is the supported read boundary for the redesigned UI.
Presentation code should consume snapshots/signals instead of reading save files
or reaching into collection/progression/opponent internals directly.

Public TripleTriadGame queries
==============================
    get_state_api()
    get_player_snapshot()
    get_collection_snapshot()
    get_deck_profiles_snapshot()
    get_opponent_snapshot(opponent_id)
    get_opponents_snapshot()
    get_global_triple_triad_snapshot()
    get_backend_health()

The state API exposes API_SCHEMA_VERSION = 2. TripleTriadGame exposes backend
version 1.1.0.

Card snapshots now include an `influence` Dictionary:
    mode      "none" or prototype "pressure"
    strength  current prototype uses 1
    offsets   authored [x, y] cells relative to the unrotated card

The future UI can render the mini Influence diagram from this payload without
knowing how Influence is resolved in a match.

Persistent opponent records
===========================
user://triple_triad_encounter_records.cfg stores per-opponent matches, W/L/D,
first win, last result/time, cards won/lost, exact stolen-card quantities and
stolen cards recovered.

State-change signal
===================
    backend_state_changed(reason)

Current reasons:
    match_result
    card_transfer
    deck_selected

The v1 backend freeze audit remains in:
    res://data/triple_triad/audit/BACKEND_FREEZE_AUDIT.md

The post-freeze Influence prototype contract is documented in:
    res://data/triple_triad/design/INFLUENCE_PROTOTYPE_V1.md


RUNTIME UI CONTRACT (backend 1.2.0 / persistent API schema 3)
==============================================================
TripleTriadGame additionally exposes `get_runtime_ui_snapshot()` and emits
`runtime_state_changed(snapshot)`. This contract is ephemeral match state, not
persistent save state. It is intended for the redesigned match UI.

The selected-card Influence payload includes `display_name`, `description`,
rotation-aware offsets and a generic mini-grid payload. Influence board cells
include source attribution and effective ranks, so presentation code never needs
to duplicate resolver math.
