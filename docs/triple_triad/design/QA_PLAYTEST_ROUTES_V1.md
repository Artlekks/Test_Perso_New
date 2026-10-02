# Triple Triad QA Playtest Routes V1

This is the practical test plan for family/friends/kids. The goal is not to
understand the backend. It is to play normally and report anything confusing,
broken, unfair, or impossible.

When something strange happens:
1. Do not reset immediately.
2. Open Shift+F10.
3. Actions -> Capture Diagnostic Report.
4. If you want to keep experimenting, Save QA Snapshot A first.
5. The report is written to `user://triple_triad_qa_report.json`.

## Route A — First discovery

Setup: `Fresh / Undiscovered`

Test:
- player owns zero cards;
- ordinary card players are locked;
- fish normally at Ocean 2;
- first eligible catch discovers the Saltworn Card Case;
- ten starter cards arrive;
- card duels become available;
- Deck #1 can be built without mouse input.

Watch for:
- duplicate starter cases;
- card game opening before discovery;
- fewer than five usable cards;
- confusing unlock feedback.

## Route B — Five-card floor

Setup: `Five-Card Safety`

Test:
- build/use the five-card deck;
- deliberately lose;
- result must say the final playable deck is protected;
- collection must remain at five cards;
- another duel must still be possible.

This rule is deterministic. Fishing RNG is never required to rescue the player.

## Route C — Loss and recovery

Setup: `Six-Card Loss / Recovery`

Test:
- lose one card legitimately;
- collection falls from six unique playable cards to five;
- rematch the same NPC;
- stolen card should be in that opponent's recoverable reward path;
- recover it;
- collection returns to six.

## Route D — Veteran rematch

Setup: `Veteran Rematch Ready`

Test Dock Bruiser:
- NPC prompt should indicate Veteran Rematch;
- evolved deck should differ from baseline;
- AI should still feel aggressive, not generically smarter;
- stolen-card recovery must still override evolution if applicable.

## Route E — Tournament run

Setup: `Regional Championship Ready`

Test:
- enter tournament;
- choose deck once;
- win round 1;
- reward resolves;
- round 2 begins automatically using the same locked deck;
- draw replays the same round;
- loss ends attempt.

## Route F — Tournament reload

Setup: `Regional Round 2 Resume`

Then:
- Shift+F10 -> Actions -> Open / Resume Active Tournament;
- expected round should open immediately;
- locked deck must still be the same five cards.

## Route G — Collection endgame

Setup: `Collection 170 / 179`

Test:
- world progression points toward missing-card acquisition sources;
- source completion diagnostics make sense;
- acquiring one card updates 170 -> 171;
- Masters/Card Master state stays intact.

## Route H — Full completion

Setup: `Full Completion`

Verify:
- 179 / 179;
- Card Master;
- full card-game completion state;
- no missing-card objective remains.

## Safety tools

Shift+F10 Actions:
- Save QA Snapshot A
- Restore QA Snapshot A
- Delete QA Snapshot A
- Capture Diagnostic Report
- Clear Playtest Log
- Reconcile Runtime / Save State
- Run Backend QA

QA snapshots contain Triple Triad state only. Fishing saves are not touched.
