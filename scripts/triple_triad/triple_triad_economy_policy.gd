extends Resource
class_name TripleTriadEconomyPolicy

@export_category("Stake Safety")
## A player must always retain at least one legal five-card deck.
@export_range(5, 20, 1) var minimum_playable_unique_cards: int = 5
@export var protect_minimum_playable_collection: bool = true

@export_category("Recovery")
## Stolen cards are promoted into the opponent's persistent collection/deck so
## the player can win them back in a later rematch.
@export var stolen_cards_recoverable: bool = true
