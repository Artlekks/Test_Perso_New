# Playable Campaign World Staging & Guidance V1

## Purpose

This pass turns the campaign read model into a small amount of real player-facing sequencing without making the Director a gameplay owner.

The underlying NPCs, world rewards, Card Maker, competition service and saves are unchanged. The presentation layer only decides when prototype interactions should advertise/accept input and when a major progression transition deserves a short existing HUD banner.

## Interaction staging

The world objects remain physically present. Their interactions are staged as follows:

- Fresh Start / Starter Case Search: fishing, economy and gathering remain the focus; card-system interaction prompts are suppressed.
- Learn Loop: the Beach Trader card interaction becomes active after the Saltworn Card Case unlocks Triple Triad.
- Connected Systems: Card Maker, Harbor Request Board and Harbor Lockbox interactions become active.
- Specialization: the Regional Championship registrar can participate in the wider card progression.

The registrar is always re-enabled if the backend says the Regional Championship is already available or active. Campaign presentation must never strand an in-progress tournament.

This staging is presentation-only. It does not rewrite backend availability, acquisition rules, ranks, rewards or saves.

## Guidance

There is no permanent objective HUD. The controller reuses `FishingInfoView` for a few short messages when the live campaign actually changes:

- Saltworn Card Case / card-duel discovery;
- Connected Systems opening;
- Specialization opening;
- campaign-foundation completion;
- a Harbor Request becoming ready;
- a Card Maker recipe becoming the current useful objective;
- an active competition needing continuation.

The controller intentionally baselines the first fully-live Triple Triad snapshot after scene/session bootstrap. This prevents an existing save from replaying old discovery banners every time the scene reloads.

## Ownership

- `PlayableCampaignProgressionDirector`: read-only campaign state.
- `PlayableCampaignPresentationPolicy`: pure interaction/message decisions.
- `PlayableCampaignPresentationController`: applies presentation state to the live beach scene.
- Existing gameplay services: continue to own all real unlock/reward/save behavior.

## QA

`PlayableCampaignPresentationQA` validates nine presentation rules including fresh-save suppression, Learn Loop introduction, Connected Systems reveal, Specialization reveal, tournament safety overrides, starter-case messaging and ready-request feedback.
