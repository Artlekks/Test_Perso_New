# Card Maker World Vertical Slice V1

## Purpose

Expose the existing Card Maker backend to normal exploration without moving any economy or card-acquisition logic into the UI.

## Runtime ownership

- `FishingCardMakerService` remains authoritative for eligibility, fish/Zenny costs, crash recovery, and the final mapped card grant.
- `FishingCardMakerMenu` is presentation/input only. It renders recipe snapshots and asks the service to execute the selected recipe.
- `FishingCardMakerNPC` is only a world interaction adapter. It resolves `FishingSessionServices`, binds the Card Maker service, and opens the menu.
- Triple Triad continues to receive the card through the existing canonical world-acquisition gateway.

## Player flow

1. Approach the Card Maker NPC on the beach and press K.
2. W/S selects one of the five authored fish-card recipes.
3. First creation displays the matching fish requirement plus the 75z fee.
4. Once the card is owned, the same entry becomes a duplicate print and displays the 150z fee with no additional fish requirement.
5. K opens a confirmation panel. The default choice is No.
6. I cancels confirmation or closes the menu.

The menu is intentionally a readable placeholder. It uses the project placeholder palette rather than introducing final art before the gameplay flow is validated.

## Acceptance

- Locked Card Maker clearly explains that the Saltworn Card Case must be found first.
- Missing fish, insufficient Zenny, and Duel Rank gates are surfaced from service result codes.
- A successful first creation consumes one fish + 75z and grants the mapped card.
- A duplicate print consumes 150z and no fish.
- Failed card-side grants preserve the existing service rollback behavior.
- Closing the menu restores the previous SceneTree pause state.
