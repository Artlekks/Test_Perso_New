extends Resource

## Data-only definition for a temporary fishing-session modifier.
##
## The same modifier service can later consume weather, food, NPC, difficulty,
## event or equipment sources. Fish consumables are only one producer.

enum Polarity {
	POSITIVE,
	NEGATIVE,
	MIXED,
	NEUTRAL,
}

@export_category("Identity")
@export var effect_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var stacking_group: StringName = &""
@export var polarity: Polarity = Polarity.POSITIVE

@export_category("Lifetime")
## Zero means an immediate-only effect (for example dispelling active buffs).
@export_range(0.0, 3600.0, 1.0)
var duration_seconds: float = 300.0

@export_category("Fish Activity / Specimen Quality")
@export_range(0.25, 3.0, 0.01)
var bite_attraction_multiplier: float = 1.0

## Chance for each additional natural specimen roll. The largest candidate wins.
## This does not alter the authored species distribution or guarantee a record.
@export_range(0.0, 0.75, 0.01)
var quality_bonus_roll_chance: float = 0.0

@export_range(0, 2, 1)
var quality_bonus_rolls: int = 0

@export_category("Fight Assistance / Risk")
## Multiplies safe-reel stamina drain. >1 exhausts the fish faster.
@export_range(0.50, 1.75, 0.01)
var stamina_drain_multiplier: float = 1.0

## Multiplies the continuous-slack grace period before Hook Off.
@export_range(0.50, 2.0, 0.01)
var hook_off_delay_multiplier: float = 1.0

## Multiplies line-break grace.
@export_range(0.50, 2.0, 0.01)
var line_tolerance_multiplier: float = 1.0

## Multiplies the player's counter-steering effectiveness.
@export_range(0.50, 2.0, 0.01)
var counter_steer_multiplier: float = 1.0

## Multiplies fish pressure after species/specimen/tackle resolution.
## <1 calms the fight, >1 creates a risk/reward frenzy.
@export_range(0.50, 1.75, 0.01)
var fish_pressure_multiplier: float = 1.0

@export_category("Immediate Cleanup")
@export var clear_positive_modifiers: bool = false
@export var clear_negative_modifiers: bool = false

@export_category("Reference")
@export_multiline var legacy_bof4_effect: String = ""


func is_valid_definition() -> bool:
	if effect_id == &"":
		return false
	if stacking_group == &"":
		return false
	if duration_seconds < 0.0:
		return false
	if quality_bonus_rolls < 0 or quality_bonus_rolls > 2:
		return false
	if quality_bonus_roll_chance < 0.0 or quality_bonus_roll_chance > 0.75:
		return false
	return true


func has_runtime_modifier() -> bool:
	return (
		duration_seconds > 0.0
		and (
			absf(bite_attraction_multiplier - 1.0) > 0.0001
			or quality_bonus_roll_chance > 0.0
			or quality_bonus_rolls > 0
			or absf(stamina_drain_multiplier - 1.0) > 0.0001
			or absf(hook_off_delay_multiplier - 1.0) > 0.0001
			or absf(line_tolerance_multiplier - 1.0) > 0.0001
			or absf(counter_steer_multiplier - 1.0) > 0.0001
			or absf(fish_pressure_multiplier - 1.0) > 0.0001
		)
	)
