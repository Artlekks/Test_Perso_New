extends Resource

@export var opponent_id: StringName = &"opponent"
@export var display_name: String = "Card Player"
@export var ai_profile: Resource
@export var region_profile: Resource
@export_range(1, 10, 1) var min_card_level: int = 1
@export_range(1, 10, 1) var max_card_level: int = 3
# 0 means: use the region's budget.
@export_range(0, 50, 1) var deck_budget_override: int = 0
