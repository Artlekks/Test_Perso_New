# Deck Ownership & Save Durability v1

Date: 2026-10-09. Scope: card/deck ownership, acquisition/result commits, recovery and canonical reset. No session-composition refactor, card balancing, match-rule changes, UI redesign, fishing changes or economy-balance changes.

## Authoritative model and audited boundaries

| State/path | Owner and readers | Persistent/transient boundary |
| --- | --- | --- |
| `user://triple_triad_collection.cfg` (version 3) | `TripleTriadCollection`: initialize, owns/get_quantity, acquire/remove/set_quantity, save_state | Only this backend serializes player quantities. Snapshots are copied dictionaries. A stale backend cannot checkpoint over a newer canonical file. |
| `user://triple_triad_decks.cfg` (version 2) | New `TripleTriadDeckStore`: load/save_config, profile_count, active_profile, audit_profiles; used by DeckSetup, StateAPI and SaveIntegrity | Canonical ordered card IDs, active profile, profile count and existing sort metadata. Five initial slots, up to 50; existing sixth/seventh/etc profiles retained. |
| DeckSetup `_cards` / `_deck` | Derived owned-card catalogue / editable draft; normal commit calls DeckStore | Never a second collection store. Confirmation refuses a failed save. Empty/short decks remain empty/short; no silent replacement cards. |
| LiveMatch active deck, initial hands; match board/owner state | LiveMatchController copies arrays on install/read; match simulation tracks match ownership | Capture/placement is match-local. It cannot mutate persistent collection quantities or saved deck arrays. Card definitions remain authored Resources. |
| Developer fallback five-card deck | DeveloperPlaytestService.card_test_deck -> DeckSetup.developer_test_deck -> `_developer_test_match` | Existing practice-save guards preserved. `_finish_match` bypasses persistence and `_begin_result_transition` closes practice. DEV OFF clears temporary deck and session. Explicit test-loadout command is the deliberate persistent exception. |
| Won/lost card | MatchResolutionController -> resolution journal -> CardEconomy -> Collection / OpponentCollection | Exactly one selected transfer per pending result. Repeated callbacks reconcile original absolute quantities; callbacks after journal completion cannot transfer again. Draw transfers nothing. |
| Card Maker | FishingCardMakerService.make_card -> world gateway claim_world_source_card -> existing delivery ledger -> AcquisitionService.grant_card -> Collection | Existing fish-debit/delivery recovery retained. Grant success now requires durable ownership/history, with intended quantities recorded before commit. No recipe, cost or reward changes. |
| Salvaged starter case | World gateway claim_acquisition_bundle -> AcquisitionService.claim_bundle -> Collection | Claimed/unlock state plus pending intended ownership stored atomically in acquisition state. Interrupted ownership/history commits are replayed to absolute quantities/counts. |
| Acquisition history (version 1) | AcquisitionTracker, reconcile_card_history | Metadata, not ownership. Journal recovery never derives another +1 from committed ownership/history. |
| StateAPI collection/deck snapshots | Read-only copies, normal facade invalidation preserved | Shared profile policy replaces six-profile reconstruction. No newly introduced cache or session service. |
| Reset/new-game | CampaignQAHarness.apply_scenario(fresh), reset_decks_only, `_delete_with_backup` | Existing canonical user paths retained. Deletes primary, `.bak`, `.tmp`, `.bak.tmp`. Deletion failure is reported instead of fake success. Live callers still follow the existing required scene reload. |

The bootstrap still composes scene-owned backends. This pass does not relocate unrelated session services. Canonical disk state and revision checks prevent stale backend instances from becoming competing persistent writers.

## Root causes and fixes

1. **P1 â€” incompatible deck reconstruction.** DeckSetup allowed 5â€“50 profiles; StateAPI and SaveIntegrity iterated six and clamped active index to five. Integrity stamped deck version 1 while UI wrote version 2. Fix: one DeckStore count/active/schema policy; the existing complete ID/ownership/rank/cost/five-card sanitizer moved into it. Both UI and integrity use that sanitizer. Profile 7 and legacy profile 50 are covered.
2. **P1 â€” successful-looking failed ownership writes.** Collection.acquire/remove/set_quantity ignored `_save` errors; AcquisitionService ignored collection/state errors and recorded successful grants/claims. Fix: direct writes roll back live quantities on failure. Acquisitions commit a recoverable absolute ownership/history intent before collection/history, then clear intent only on success. A failed grant returns `save_failed`; unresolved intent blocks another grant.
3. **P1 â€” corrupt save silently replaced by new-game defaults.** Collection.initialize treated every load error like file-not-found and seeded/re-saved. Fix: missing file alone is a fresh save. Truncated/invalid primary can recover a committed backup. Unrecoverable payload, invalid quantity/version or newer collection schema remains untouched and blocks writes. Unknown validly typed card IDs are sanitized against the catalogue as before.
4. **P1 â€” result retry could transfer twice.** MatchResolutionController recomputed desired quantities from current ownership; Journal.record_selection overwrote the prior selection and reset committed flags. Fix: retained selection is immutable; identical result retry reconciles original absolute counts. A different selection is rejected. A callback after journal clear is rejected. Ownership transfer requires a pending result when the production resolution journal exists.
5. **P1 â€” stale backend overwrites.** A previously loaded Collection could re-save obsolete quantities after another backend committed newer ownership. Fix: hash revision checked against the canonical file before commit; mismatch returns ERR_BUSY without overwriting. Acquisition state uses the same stale-writer check, and acquisition/transfer entry validates the collection before journaling stale quantities. This is not a cross-process locking service; the project remains a single-process writer.
6. **P2 â€” direct/truncating multi-file writes.** Collection, decks, opponent ownership, acquisition history/state and transfer/result journals used direct ConfigFile.save. Fix: shared ConfigStore stages a same-directory file, reloads and compares it, then renames over primary. Committed backups are refreshed through separate staging. `.tmp` is never promoted as recovery truth. Integrity no longer edits collection files behind the backend.
7. **P2 â€” reset ignored deletion failure/staging.** Reset removed primary/backup only and unconditionally reported success. Fix: delete all four canonical artifacts and propagate the real deletion result.

## Compatibility, corruption and failure behavior

No save-version bump or replacement combined-save file. Collection v3, decks v2, acquisition/history v1 and existing transfer/result versions remain. Current saves load directly. Legacy deck-index entries convert through the existing legacy catalogue mapping into ordered IDs; valid profiles through 50 remain. Deck repair keeps the first valid unique owned/rank-usable/budget-legal five entries, in authored/saved order; invalid/missing/duplicate references are removed, never auto-filled. Existing ownership duplicate policy is preserved (multiple copies may be owned; a deck still uses unique card IDs).

Acquisition v1 gains an **optional additive `pending` section** containing intended quantities and history. Existing saves omit it and need no migration. Loading a pending transaction first applies validated absolute quantities/history and commits them, then clears intent. Once cleared, loading again does not grant another card. Older engine/project builds do not understand that pending extension; do not downgrade during an unfinished acquisition.

Syntax-invalid/zero-byte primary with a valid backup recovers; unrecoverable or unsupported payload fails closed without seeding/overwriting it. Invalid pending quantity types are rejected before live mutation. Future versions are not downgraded. Interrupted transfer journals force both player and opponent to intended quantities; no extra increment/decrement. Revision conflict requires reloading the canonical backend rather than overwriting newer data.

Same-filesystem replacement was exercised on Windows by repeated saves. This is practical atomic publication, not a claim of guaranteed durability under OS/device power loss: storage flush semantics and browser IndexedDB persistence are outside this fixture. A failed redundant backup refresh warns; committed primary remains successful.

## QA actually executed

Godot executable: `C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe`. Native suites use disposable custom userdata. Invoked with PowerShell Start-Process -WindowStyle Hidden -Wait -PassThru and redirected stdout/stderr. Commands below show equivalent Godot arguments from the project directory.

| Command | Result |
| --- | --- |
| `--headless --path . --script scripts/qa/deck_ownership_durability_qa.gd` | **91/91**, exit 0. Exact edits/order/collection, 12 save/reload cycles, profile 7/50, duplicate/invalid IDs, ownership loss/short deck, Developer ON/OFF/restart, failed-write rollback, zero-byte/staged/corrupt/future saves, real win/loss and result retries/late callbacks, draw, half-transfer recovery, Card Maker grant/history, interrupted acquisition/history, stale writers and canonical fresh reset. |
| `--headless --path . --script scripts/qa/developer_playtest_qa.gd` | **89/89**. Actual zero-owned borrowed match, practice result/close, DEV OFF and complete save-byte equality. Existing Triple Triad backend **101/101** also runs. |
| `--headless --path . --script scripts/qa/fishing_save_recovery_runner.gd` | **23/23**, teardown **0 orphans**, exit 0. Boot includes Triple Triad **101/101**, Card Maker **10/10**, Campaign **14/14**, Fresh Save **55/55**, Fight **24/24**, Presentation **10/10**, Stability **27/27**. |
| `--headless --path . --script scripts/qa/early_tackle_acquisition_qa.gd` | **61 checks, 0 failures**, exit 0. |
| `--headless --path . --script scripts/qa/fishing_fight_camera_tracking_qa.gd -- --regressions` | Camera **168/168**; full fishing **22950/22950**, exit 0. |
| `--rendering-method gl_compatibility --path . --script scripts/qa/runtime_lifecycle_qa.gd` | See final execution record below. |
| Same lifecycle command plus `-- --mobile` | See final execution record below. |
| `--headless --editor --import --path .` | exit 0; new script UID files generated, no script errors. |
| `git diff --check` | Clean. |

The corruption fixture deliberately feeds `[broken` to ConfigFile and receives the expected parser ERROR, then verifies the original bytes remain and ownership commits are refused. Deliberate failed-write fixtures and stale-owner fixtures emit expected warnings. These are injected failures with passing assertions, not startup errors. The existing defensive precomposition Triple Triad warning remains. Economy remains **22/24** with the two known H12 balance warnings unchanged.

Rendered lifecycle engine shader-cache `_save_to_cache` write diagnostics remain the previously classified isolated-runtime environment issue. No project script errors or leaked-object/resource shutdown warnings are accepted as green. Physical iPhone save/reload durability and forced OS power loss were not tested; no claim that headless or native mobile-harness tests prove those.

## Files changed

Modified runtime files under `scripts/triple_triad/`:
- triple_triad_collection.gd
- triple_triad_deck_setup.gd
- triple_triad_state_api.gd
- triple_triad_save_integrity.gd
- triple_triad_acquisition_service.gd
- triple_triad_acquisition_tracker.gd
- triple_triad_card_economy.gd
- triple_triad_opponent_collection.gd
- triple_triad_match_resolution_controller.gd
- triple_triad_match_resolution_journal.gd
- triple_triad_campaign_qa_harness.gd

Added:
- scripts/triple_triad/triple_triad_config_store.gd and .uid
- scripts/triple_triad/triple_triad_deck_store.gd and .uid
- scripts/qa/deck_ownership_durability_qa.gd and .uid
- docs/architecture/deck_ownership_save_durability_v1.md

Generated Web artifacts: export/index.html and export/index.pck. Existing index.js/wasm remain the same engine export. Linux Web validation and final lifecycle results appended below after completion. HTTPS was not restarted.


## Final lifecycle execution record

- Desktop Compatibility: **1826/1826 assertions**, exit 0, no project script errors or leak shutdown warnings. Across six cycles: structural nodes 2053, resources 2260, services 1, orphan nodes 0, timers 4/active 1, tweens 0; subscribed connections 171. Total object counts include changing ambient actors and actual owned catches.
- Mobile portrait harness rendered with Compatibility: **1052/1052 assertions**, exit 0. Structural nodes 2267, resources 2263, services 1, orphans 0, timers 4/active 1, tweens 0; subscribed connections 42. **This run is NOT fully clean:** a tide-change callback hit `FishShadowPresence._spawn_one_shadow` at `scripts/fish_shadow_presence.gd:629`, passing a previously freed bait object to `FishShadowActor.set_ambient_bait`. Trace: tide service -> environment service -> Fishing environment sync -> FishZone -> FishShadowPresence population rebuild. Those fishing files are unchanged by this pass. The previous rendered mobile run did not log it, so it is intermittent; this audit does not claim an untouched baseline reproduction. It requires a separate fishing lifecycle fix and was not hidden or repaired under this card-only scope.
- Both lifecycle runs additionally completed full fishing regression **22950/22950**.
- Final card-focused runners after stale-owner safeguards: durability **91/91**; Developer **89/89**; recovery **23/23** with zero orphan teardown; Triple Triad **101/101**, Card Maker **10/10**, Campaign **14/14**, Fresh Save **55/55**; camera **168/168**, full fishing **22950/22950**. Logs: `build/mobile-web/deck-finalship-*.stdout/.stderr`; lifecycle logs: `build/mobile-web/deck-shipped-lifecycle-*.stdout/.stderr` (ignored build outputs).

The mobile lifecycle SCRIPT ERROR is an outstanding, out-of-scope verification finding. Card ownership/durability assertions are green; project-wide lifecycle cleanliness is not claimed.

## Final Web publication

`& .\tools\mobile\build_mobile_playtest.ps1` completed using the existing Linux/WSL Godot 4.7.2 builder and unchanged `Mobile Portrait Web Playtest` preset. Published PCK **32,025,204 bytes**; `project.binary` **9,944 bytes**, valid **ECFG** header. Export validated before publication. Safari can refresh at the existing HTTPS address; server/certificates were not touched. No physical Safari persistence acceptance is claimed.
# Morning Stability v1 interaction update

Deck selection is slot-first. Confirming a filled or empty slot identifies that
exact edit target while the collection has its own selector. Independent sibling
yellow outlines at z=1000 render above card images, dimming and cost overlays.
Confirming the source card again removes only deck membership; Back cancels
unchanged. Short decks preserve exact replacement of filled slots. The existing
compact save format packs remaining cards left after removal; trailing slots are
empty. All six profiles, ownership and legality continue through the existing backend.

Modal close arms the shared ModalInputGate before restoring pause ownership.
Exploration requires release and a fresh press; queued/held closing K/I/C input
cannot start fishing. Match hand cards keep 116Ã—132 dimensions and existing
animation speed, with a 39.6-pixel vertical step (30% of height).
