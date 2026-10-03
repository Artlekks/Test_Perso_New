# Tournament Reward World Vertical Slice v1

## Purpose

Expose the existing competitive-progression backend through one real world interaction without creating another tournament system.

## Beach integration

The beach contains a prototype **Regional Championship Registrar**. It is backed directly by `TripleTriadCompetitionInteraction3D` and points at the authored `regional_championship` competition.

The interaction therefore inherits the existing competition rules:

- requires Card Duel Rank 3;
- requires Harbor, Highland, and Mystic circuits to be complete;
- locks the player's five-card tournament deck across rounds;
- resumes an interrupted active championship;
- runs Gearwright, Marsh Keeper, and Tide Oracle as the three authored rounds;
- resolves completion through the existing competition controller;
- grants the next unowned card from `tournament_reward / regional_circuit` through the canonical world gateway;
- keeps tournament reward delivery crash-safe through the competition pending-reward state and world reward ledger.

The object is placeholder world geometry only. Final tournament art, staging, ceremony, dialogue, and location are presentation work, not part of this vertical slice.

## Why no new tournament-reward trigger was added

Tournament rewards are already owned by `TripleTriadCompetitionController.resolve_pending_reward()`. A second trigger or reward NPC would duplicate the transaction path and risk double delivery. The missing piece was only a world-facing tournament entry point.

## QA

Backend QA verifies that:

- the registrar scene exists;
- it uses `triple_triad_competition_interaction_3d.gd`;
- it targets `regional_championship`;
- the authored competition still points at the canonical `regional_circuit` tournament reward source;
- the registrar is actually placed in the beach vertical slice.
