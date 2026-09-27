extends Resource
class_name FishBehaviorProfile

enum FightArchetype {
	STEADY,
	DARTING,
	AGGRESSIVE,
	HEAVY,
	ERRATIC,
}

@export_category("Identity")
@export_enum("Steady", "Darting", "Aggressive", "Heavy", "Erratic")
var archetype: int = FightArchetype.STEADY
@export var profile_name: String = "STEADY"

@export_category("Movement")
@export_range(0.0, 1.0, 0.05)
var lateral_activity: float = 1.0

@export_range(0.0, 1.0, 0.05)
var vertical_activity: float = 1.0

@export var direction_change_min: float = 0.8
@export var direction_change_max: float = 2.0

## Scales how sharply this archetype reaches each newly-selected movement target.
## This changes feel/cadence, not the authored fish strength stat.
@export_range(0.5, 2.0, 0.05)
var movement_response_multiplier: float = 1.0

## Scales the movement reaction generated when the player releases K.
@export_range(0.5, 2.0, 0.05)
var release_reaction_multiplier: float = 1.0

## Multiplies the species' authored recovery window between resistance rounds.
@export_range(0.5, 2.0, 0.05)
var recovery_time_multiplier: float = 1.0

@export_category("Bite Behavior")
## Multiplies this species' effective attraction weight after lure/depth/tech
## compatibility has been evaluated. This is behavior personality, not spawn rate.
@export_range(0.25, 2.0, 0.05)
var bite_aggression_multiplier: float = 1.0

## Multiplies the base hook-input window after this species commits to a bite.
@export_range(0.50, 1.50, 0.05)
var bite_window_multiplier: float = 1.0

## Multiplies the delay before the next bite check after this species is missed.
@export_range(0.50, 2.0, 0.05)
var bite_retry_multiplier: float = 1.0

@export_category("Fight Output")
## Multiplies movement intensity without changing FishData stamina/strength.
@export_range(0.50, 1.50, 0.05)
var fight_intensity_multiplier: float = 1.0

## Multiplies the pressure channel that feeds the tension system.
@export_range(0.50, 1.50, 0.05)
var pressure_multiplier: float = 1.0

## Multiplies the pull signal used by the hooked-bait/fight presentation.
@export_range(0.50, 1.50, 0.05)
var pull_multiplier: float = 1.0

## Multiplies stamina recovery while the player is not reeling.
@export_range(0.50, 1.50, 0.05)
var stamina_recovery_multiplier: float = 1.0

@export_category("Behavior Weights")
@export_range(0.0, 5.0, 0.1)
var surge_weight: float = 1.0

@export_range(0.0, 5.0, 0.1)
var side_run_weight: float = 1.0

@export_range(0.0, 5.0, 0.1)
var dive_weight: float = 1.0

@export_range(0.0, 5.0, 0.1)
var rise_weight: float = 1.0

@export_range(0.0, 5.0, 0.1)
var erratic_weight: float = 1.0

@export_category("Thrashing")
@export_range(0.0, 1.0, 0.05)
var thrash_chance: float = 0.20

@export_range(1.0, 2.0, 0.05)
var thrash_multiplier: float = 1.35


func get_archetype_label() -> String:
	if not profile_name.is_empty():
		return profile_name

	match archetype:
		FightArchetype.DARTING:
			return "DARTING"
		FightArchetype.AGGRESSIVE:
			return "AGGRESSIVE"
		FightArchetype.HEAVY:
			return "HEAVY"
		FightArchetype.ERRATIC:
			return "ERRATIC"
		_:
			return "STEADY"


func get_debug_summary() -> String:
	return (
		"%s | bite %.2f window %.2f retry %.2f | "
		+ "fight %.2f pressure %.2f pull %.2f recover %.2f"
	) % [
		get_archetype_label(),
		bite_aggression_multiplier,
		bite_window_multiplier,
		bite_retry_multiplier,
		fight_intensity_multiplier,
		pressure_multiplier,
		pull_multiplier,
		stamina_recovery_multiplier,
	]
