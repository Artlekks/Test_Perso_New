extends Resource

## Design/QA policy for the fishing difficulty curve.
##
## This resource NEVER modifies a fish at runtime. It defines the fairness and
## progression envelope that automated tests use to reject future data changes
## which would make early fishing too punishing or endgame fish mathematically
## unreasonable. Runtime mechanics remain owned by fish/rod/tension data.

@export_category("Tier Identity")
@export var tier_labels: PackedStringArray = PackedStringArray([
	"INTRODUCTORY",
	"FOUNDATION",
	"INTERMEDIATE",
	"ADVANCED",
	"ENDGAME",
])

@export_category("Reaction Window")
## Minimum actual hook-input window in seconds after species multipliers.
@export var minimum_bite_window_seconds: PackedFloat32Array = PackedFloat32Array([
	0.70,
	0.68,
	0.58,
	0.52,
	0.60,
])

@export_category("Fight Duration")
## Upper bound for ideal continuous SAFE-zone reel time at an average specimen.
## Recovery/decision time is intentionally excluded: this is an endurance sanity
## limit, not a target duration for every player's real fight.
@export var max_average_active_reel_seconds: PackedFloat32Array = PackedFloat32Array([
	3.00,
	6.00,
	10.00,
	20.00,
	27.00,
])

## Same envelope for the largest authored king specimen.
@export var max_king_active_reel_seconds: PackedFloat32Array = PackedFloat32Array([
	4.50,
	8.50,
	14.50,
	30.00,
	38.50,
])

@export_category("Equipment Curve")
## RodData.PowerTier expected when this tier becomes normal progression.
## Tier 1/2 intentionally remain fully supported by the Wooden Rod.
@export var recommended_rod_power_tier: PackedInt32Array = PackedInt32Array([
	0,
	0,
	1,
	2,
	3,
])

@export_range(1, 5, 1)
var starter_rod_supported_through_fish_tier: int = 2

@export_category("Failure Fairness")
## Even the weakest rod must give the player readable overload reaction time.
@export var minimum_line_break_grace_seconds: float = 1.00

## Slack should be a sustained mistake, not a one-frame zero-tension failure.
@export var minimum_hook_off_grace_seconds: float = 0.50

@export_category("Reference Runtime")
## Mirrors Encounter's authored baseline and is used only by the audit maths.
@export var reference_stamina_drain_per_second: float = 30.0
@export var reference_bite_window_seconds: float = 0.80


func is_valid_policy() -> bool:
	var count := 5
	return (
		tier_labels.size() == count
		and minimum_bite_window_seconds.size() == count
		and max_average_active_reel_seconds.size() == count
		and max_king_active_reel_seconds.size() == count
		and recommended_rod_power_tier.size() == count
		and reference_stamina_drain_per_second > 0.0
		and reference_bite_window_seconds > 0.0
		and minimum_line_break_grace_seconds > 0.0
		and minimum_hook_off_grace_seconds >= 0.0
	)


func get_tier_index(fish_tier: int) -> int:
	return clampi(fish_tier, 1, 5) - 1


func get_tier_label(fish_tier: int) -> String:
	return tier_labels[get_tier_index(fish_tier)]


func get_minimum_bite_window_seconds(fish_tier: int) -> float:
	return float(minimum_bite_window_seconds[get_tier_index(fish_tier)])


func get_max_active_reel_seconds(fish_tier: int, is_king: bool) -> float:
	var index := get_tier_index(fish_tier)
	if is_king:
		return float(max_king_active_reel_seconds[index])
	return float(max_average_active_reel_seconds[index])


func get_recommended_rod_power_tier(fish_tier: int) -> int:
	return int(recommended_rod_power_tier[get_tier_index(fish_tier)])


func starter_rod_should_support(fish_tier: int) -> bool:
	return fish_tier <= starter_rod_supported_through_fish_tier
