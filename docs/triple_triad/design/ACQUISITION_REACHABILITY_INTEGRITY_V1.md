# Acquisition Reachability Integrity v1

The canonical world acquisition map now has a regression guard that verifies every authored acquisition source terminates in a real gameplay delivery owner.

## Supported source families

- `starter_bundle` -> starter/discovery bundle flow
- `opponent_win` -> match resolution/reward transfer
- `fishing_salvage` -> fishing salvage bridge
- `treasure_cache` -> world reward gateway
- `quest_reward` -> quest reward adapter/world gateway
- `tournament_reward` -> competition/world gateway
- `card_maker` -> fishing Card Maker service

The five world-facing/economy claim types remain direct-claimable through the canonical acquisition validation layer. Starter bundles and opponent wins remain owned by their dedicated systems instead of bypassing those flows.

## Regression contract

The audit fails when:

- a new source type has no registered runtime owner;
- a source's direct-claim ownership disagrees with its delivery route;
- an authored source contains no cards;
- a Card Maker recipe source maps to anything other than one card;
- any canonical card lacks a gameplay delivery route;
- a source references a card outside the canonical catalog.

Current canonical result: **179 cards / 29 sources / 7 source families**.

Expected Triple Triad backend QA after this pass: **96/96**.
