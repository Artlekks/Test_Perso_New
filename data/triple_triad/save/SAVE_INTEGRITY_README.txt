TRIPLE TRIAD SAVE / INTEGRITY PASS

What this adds
==============
1. Global Triple Triad save-health coordinator:
   res://scripts/triple_triad/triple_triad_save_integrity.gd

2. Protected save files:
   - user://triple_triad_collection.cfg
   - user://triple_triad_opponents.cfg
   - user://triple_triad_decks.cfg
   - user://triple_triad_progression.cfg

3. Semantic .bak backups
   Each healthy ConfigFile is mirrored to "<save>.bak".
   The transaction journal is intentionally NOT backed up because replaying a
   stale transfer journal could duplicate/reverse a later card transaction.

4. Corruption recovery
   Before Triple Triad initializes, a save that exists but cannot be parsed is
   restored from its latest valid .bak when available.

5. Transaction-aware checkpoints
   Card ownership transfers still use triple_triad_transfer_journal.cfg.
   Healthy backups are NOT refreshed while that journal contains a pending
   transaction. CardEconomy recovers the transaction first on the next boot.

6. Player deck validation
   All six saved profiles are checked for:
   - cards the player no longer owns
   - missing/invalid card IDs
   - duplicate card IDs
   - more than five cards
   - current Duel Rank / deck point budget
   - legacy index-based profiles are migrated to stable IDs

7. NPC save validation
   Every persisted opponent is checked for:
   - invalid or zero-quantity cards
   - deck entries the NPC no longer owns
   - duplicate deck entries
   - stale priority/rematch entries
   - deck list capped to five persisted cards

8. Progression validation
   Duel points and W/L/D/match counters are clamped/reconciled before save.

9. Save manifest
   user://triple_triad_save_manifest.cfg records:
   - global schema version
   - checkpoint count
   - last checkpoint reason/time
   - whether repairs were needed
   - whether backups were refreshed
   - whether a transfer was still pending
   - warnings

10. Checkpoint timing
    - on Triple Triad boot
    - immediately after a successful reward/card-loss transfer
    - on clean Triple Triad close

This is intentionally backend-only. It does not change the card UI.
