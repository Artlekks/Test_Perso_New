extends Resource
class_name TripleTriadQAProfile

enum StartingOwner {
	RANDOM,
	PLAYER,
	OPPONENT,
}

@export var profile_name: String = "Card QA Profile"
@export var sort_order: int = 100
@export_multiline var purpose: String = ""

@export_category("Match Configuration")
@export var region_profile: Resource
@export var ai_profile: Resource
## Optional. When empty, the selected region's rule set remains authoritative.
@export var rule_set_override: Resource
@export_range(0, 50, 1) var deck_budget_override: int = 0
@export_range(1, 10, 1) var min_card_level: int = 1
@export_range(1, 10, 1) var max_card_level: int = 3
@export_enum("Random", "Player", "Opponent") var starting_owner: int = StartingOwner.RANDOM

@export_category("Repeatability")
## Zero preserves normal random hands. A positive value gives repeatable QA hands.
@export_range(0, 2147483647, 1) var hand_seed: int = 0
