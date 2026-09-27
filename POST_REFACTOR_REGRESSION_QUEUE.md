# Architecture Cleanup Complete — Post-Pass Regression Queue

Passes 1–5 are complete.

## Completed

1. **Production hygiene**
   - automatic QA save reset/seed removed
   - full-tackle QA default OFF
   - duplicate UI assets removed

2. **Single source of truth**
   - FishData owns stable identity/manual/source data
   - JournalService is the Data-menu view-model source
   - FishingMenu no longer contains a second fish database

3. **Menu modularity**
   - Equip/Data/Hints/Help implementations split into controller modules

4. **System ownership**
   - persistent services grouped under FishingSessionServices
   - debug/QA subsystem moved under FishingDebugController

5. **Safe performance**
   - ambient shadows share one cached bait lookup
   - hidden menu stops repainting Time every frame

## Next phase: regression + gameplay polish

The first queued issue is the camera/framing behavior noted during Pass 2:

When camera follow has moved far toward a bait/fish and the action returns close
to the fisherman, the fisherman can remain away from his intended bottom-left
screen composition. Starting the next cycle restores the normal composition too
abruptly.

This was intentionally not modified during architecture cleanup so we can now
debug it against a stable architecture baseline and determine whether it was
pre-existing or introduced by the recent cast-camera work.

Other future polish:
- pixelized/low-resolution bait presentation;
- sound pass;
- final feedback polish;
- optional profiling-driven camera projection consolidation.
