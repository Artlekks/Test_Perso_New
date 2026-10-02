# Triple Triad World Interaction Layer V1

This pass turns the backend into reusable exploration-facing components without
changing card rules, balance, or card-game UI.

## World progression director

`TripleTriadGame.get_world_progression_snapshot()` gives the current high-level
card-game objective. It can report discovery, regional circuits, tournament
qualification, an active tournament, Masters' Cup progression, collection
cleanup, or full completion.

`world_progression_changed(snapshot)` is emitted after authoritative backend
state changes.

## Reusable 3D content

- `TripleTriadWorldRewardTrigger3D.tscn`:
  one-shot or repeatable mapped card-cache / world-reward interaction.
- `TripleTriadCompetitionInteraction3D.tscn`:
  starts or resumes Regional Championship / Masters' Cup.
- `TripleTriadQuestRewardAdapter`:
  attach to an existing quest node and call `grant_reward()`.

Ordinary world content should never grant card ids directly. It should use the
mapped acquisition source id so the existing rank gates, one-shot ledger,
completion tracking, and save integrity remain authoritative.

Expected backend QA count: 34.
