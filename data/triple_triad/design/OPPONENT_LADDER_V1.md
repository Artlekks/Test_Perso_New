# Triple Triad Opponent Ladder V1

This pass turns the prototype NPC layer into five authored gameplay archetypes.
The card roster remains the 179-card Content Balance V1 roster; this document
only describes how those cards are distributed into opponents and progression.

## 1. Beach Trader — beginner balanced

- Required player Duel Rank: 1
- Opponent Duel Rank: 1
- Deck budget: 23
- Progression reward: 2 points
- Region: Prototype Coast
- Rules: Open + Influence
- AI: Balanced
- Preferred deck: Harbor Cat, Dock Guard, Harbor Guard, Saltbeard, Swiftfin
- Normal reward pool: Dock Guard, Saltbeard, Swiftfin
- Purpose: teach basic side comparison, the center +1 coast trait, and one
  readable Influence source without Same/Plus complexity.

## 2. Dock Bruiser — aggressive

- Required player Duel Rank: 1
- Opponent Duel Rank: 2
- Deck budget: 31
- Progression reward: 4 points
- Region: Prototype Coast
- Rules: Open + Same + Combo + Influence
- AI: Aggressive
- Preferred deck: Boru Breaker, Boru Brawler, Baro, Harbor Hound, Chain Guard
- Normal reward pool: Boru Brawler, Baro, Harbor Hound
- Purpose: punish weak exposed edges and introduce Same/Combo through a deck
  that mostly wins by direct pressure rather than Influence.

## 3. Highland Keeper — defensive

- Required player Duel Rank: 2
- Opponent Duel Rank: 3
- Deck budget: 31
- Progression reward: 9 points
- Region: Prototype Highlands
- Rules: Open + Same + Combo + Influence
- AI: Defensive
- Preferred deck: Mire Turtle, Masked Warden, Scrap Beetle, Stonecrest, Cave Bear
- Normal reward pool: Masked Warden, Mire Turtle, Stonecrest
- Purpose: make the +1 corner cells matter and teach the player to attack around
  protected geometry instead of always chasing immediate captures.

## 4. Tide Oracle — Influence/control

- Required player Duel Rank: 3
- Opponent Duel Rank: 4
- Deck budget: 37
- Progression reward: 15 points
- Region: Prototype Coast
- Rules: Open + Plus + Combo + Influence
- AI: Controller
- Preferred deck: Undertow, Wharf Cat, Cira, Gimbal, River Drake
- Normal reward pool: Undertow, Wharf Cat, Cira
- Purpose: all five preferred cards project Influence. Plus replaces Same as the
  primary special-rule puzzle so the opponent feels mechanically distinct.

## 5. Ash Champion — late-game champion

- Required player Duel Rank: 4
- Opponent Duel Rank: 6
- Deck budget: 44
- Progression reward: 20 points
- Region: Prototype Volcanic
- Rules: Open + Same + Plus + Combo + Influence
- AI: Champion
- Preferred deck: Solin, Thornclaw, Merek, Ashmaw, Ryn
- Normal reward pool: Solin, Thornclaw, Merek, Ryn
- Purpose: late-game test using premium Gold cards, low AI randomness, Magma Vein
  edge bonuses, and every currently implemented special rule.

## Reward-pool rule

After a player win, the normal selectable reward cards are the opponent's
`reward_card_ids` that were actually present in that match. Any cards the NPC
previously stole from the player are added to the choices automatically, even if
they are outside the normal reward pool. If authored data ever produces zero
eligible cards, the whole match hand is exposed as a safety fallback so the
mandatory stake screen cannot soft-lock.

## Existing-save migration

Opponent profiles now have `content_revision`. Each NPC save remembers the
authored native-card baseline from the revision it was created with. When the
revision increases, only genuinely new authored native cards are merged and the
preferred baseline deck is refreshed from cards the NPC still owns. Cards already
won away by the player are therefore not silently recreated on later revisions.
Legacy prototype saves have no baseline, so revision 0 -> 1 intentionally seeds
the new V1 authored native collection. Stolen player cards remain untouched.

## Current one-win progression spine

The authored rewards intentionally align the first victory against each unique
opponent with the current Duel Rank thresholds:

- Beach Trader (2) + Dock Bruiser (4) = 6 -> Rank 2
- + Highland Keeper (9) = 15 -> Rank 3
- + Tide Oracle (15) = 30 -> Rank 4
- + Ash Champion (20) = 50 -> Rank 5

Rank 6 remains a mastery/rematch threshold at 80 points for this five-opponent
vertical slice. Future regions can fill the Rank 5 -> Rank 6 content gap without
changing the existing ladder.
