extends Resource
class_name TripleTriadRankDefinition

@export_category("Identity")
@export var rank_id: StringName = &""
@export var display_name: String = ""

@export_category("Threshold")
## Inclusive lower bound for this card-player rank.
@export_range(0, 9999, 1)
var min_points: int = 0

@export_category("Deck")
## Added to the game's base deck-point budget while this rank is active.
@export_range(0, 50, 1)
var deck_budget_bonus: int = 0


func is_valid_definition() -> bool:
	return (
		rank_id != &""
		and not display_name.strip_edges().is_empty()
		and min_points >= 0
		and deck_budget_bonus >= 0
	)
