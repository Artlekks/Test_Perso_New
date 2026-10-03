# Playable Campaign Progression Director v1

## Purpose

The Campaign Progression Director is a read-only composition layer for the current playable 0-12h campaign spine. It does not grant rewards, unlock content, mutate economy values, or persist its own progression state.

It reads the systems that already own their data and produces one stable snapshot containing:

- current campaign phase and target milestone;
- milestone completion/deficit data;
- actual fishing/card/tackle facts;
- system availability/engagement summaries;
- high-priority runtime blockers such as pending world-reward recovery;
- one deterministic next-objective suggestion.

## Runtime inputs

FishingSessionServices supplies fishing progress, inventory, unlock state, Prepared Bait, and Card Maker services. Triple Triad is discovered lazily from the current scene and queried only through its public facade methods.

The director remains safe during FishingSessionServices' pre-SceneTree bootstrap: it simply reports the card backend as unavailable until the persistent services are attached and the scene is live.

## Campaign phases

- `fresh_start`
- `starter_case_search`
- `first_fishing_trip`
- `learn_loop`
- `connected_systems`
- `specialization`
- `campaign_foundation_complete`

Milestone completion uses the minimum targets from `playable_campaign_loop_v1.json`. The upper ranges remain design envelopes rather than gates, so exceeding a target cannot regress the player.

## Objective priority

An active tournament always wins priority. Otherwise the director chooses an objective appropriate to the current phase. In Connected Systems, ready one-shot rewards are surfaced before generic collection grind, then tackle/journal/card deficits are considered.

## QA

`PlayableCampaignProgressionDirectorQA` covers fresh save, non-eligible first catch, starter-case advancement, H1/H4/H12 phase transitions, Harbor Request priority, active tournament priority, and pending world-reward recovery visibility.
