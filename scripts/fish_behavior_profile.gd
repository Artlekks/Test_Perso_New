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

## Human-facing design identity used by QA/debug tooling. This does not drive
## mechanics directly; the authored values below remain authoritative.
@export var personality_name: String = "STEADY"

## Relative roster difficulty for design/debug visibility. Runtime difficulty is
## still produced by FishData stats + this profile, so this never double-scales.
@export_range(1, 5, 1)
var difficulty_tier: int = 1

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

## Hook-set personality is separate from fight personality, but AUTO deliberately
## derives a useful first-pass behavior from the existing archetype so the full
## roster gains bite variety without rewriting every fish resource.
enum BiteTimingStyle {
	AUTO,
	STRIKE,
	NIBBLE,
	LOAD,
	FEINT,
}

@export_enum("Auto", "Strike", "Nibble", "Load", "Feint")
var bite_timing_style: int = BiteTimingStyle.AUTO

## Scales only the tentative pre-hook delay. The total authored bite window still
## comes from bite_window_multiplier below, so this cannot silently inflate the
## complete reaction window.
@export_range(0.50, 1.50, 0.05)
var bite_commit_delay_multiplier: float = 1.0

## Multiplies this species' effective attraction weight after lure/depth/tech
## compatibility has been evaluated. This is behavior personality, not spawn rate.
@export_range(0.25, 2.0, 0.05)
var bite_aggression_multiplier: float = 1.0

## Multiplies this species' complete bite opportunity window. Bite Recognition
## then divides that authored total between tentative read time and hook-set time.
@export_range(0.50, 1.50, 0.05)
var bite_window_multiplier: float = 1.0

## Multiplies the delay before the next bite check after this species is missed.
@export_range(0.50, 2.0, 0.05)
var bite_retry_multiplier: float = 1.0

@export_category("Aerial Control")
## AUTO derives the jump response from species rise/vertical personality plus
## the active tackle hook-security context. Explicit overrides are available for
## future species tuning without changing Encounter or the input contract.
enum AerialControlStyle {
	AUTO,
	BOW_LOW,
	HIGH_FOLLOW,
	DISABLED,
}

@export_enum("Auto", "Bow / Low Rod", "High Rod / Follow", "Disabled")
var aerial_control_style: int = AerialControlStyle.AUTO

## Multiplies only the chance that an authored RISE becomes an aerial breach.
## The existing rise_weight still owns how often the species chooses RISE.
@export_range(0.0, 2.0, 0.05)
var aerial_frequency_multiplier: float = 1.0

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


func is_valid_profile() -> bool:
	var action_weight_total := get_total_action_weight()

	return (
		archetype >= FightArchetype.STEADY
		and archetype <= FightArchetype.ERRATIC
		and not get_personality_label().is_empty()
		and difficulty_tier >= 1
		and difficulty_tier <= 5
		and lateral_activity >= 0.0
		and lateral_activity <= 1.0
		and vertical_activity >= 0.0
		and vertical_activity <= 1.0
		and direction_change_min > 0.0
		and direction_change_max >= direction_change_min
		and movement_response_multiplier > 0.0
		and release_reaction_multiplier > 0.0
		and recovery_time_multiplier > 0.0
		and bite_timing_style >= BiteTimingStyle.AUTO
		and bite_timing_style <= BiteTimingStyle.FEINT
		and bite_commit_delay_multiplier > 0.0
		and bite_aggression_multiplier >= 0.0
		and bite_window_multiplier > 0.0
		and bite_retry_multiplier > 0.0
		and aerial_control_style >= AerialControlStyle.AUTO
		and aerial_control_style <= AerialControlStyle.DISABLED
		and aerial_frequency_multiplier >= 0.0
		and fight_intensity_multiplier > 0.0
		and pressure_multiplier > 0.0
		and pull_multiplier > 0.0
		and stamina_recovery_multiplier > 0.0
		and surge_weight >= 0.0
		and side_run_weight >= 0.0
		and dive_weight >= 0.0
		and rise_weight >= 0.0
		and erratic_weight >= 0.0
		and action_weight_total > 0.0
		and thrash_chance >= 0.0
		and thrash_chance <= 1.0
		and thrash_multiplier >= 1.0
	)


func get_resolved_bite_timing_style() -> int:
	if bite_timing_style != BiteTimingStyle.AUTO:
		return bite_timing_style

	match archetype:
		FightArchetype.DARTING, FightArchetype.AGGRESSIVE:
			return BiteTimingStyle.STRIKE
		FightArchetype.HEAVY:
			return BiteTimingStyle.LOAD
		FightArchetype.ERRATIC:
			return BiteTimingStyle.FEINT
		_:
			return BiteTimingStyle.NIBBLE


func get_bite_timing_style_label() -> String:
	match get_resolved_bite_timing_style():
		BiteTimingStyle.STRIKE:
			return "STRIKE"
		BiteTimingStyle.LOAD:
			return "LOAD"
		BiteTimingStyle.FEINT:
			return "FEINT"
		_:
			return "NIBBLE"


func get_total_action_weight() -> float:
	return (
		maxf(surge_weight, 0.0)
		+ maxf(side_run_weight, 0.0)
		+ maxf(dive_weight, 0.0)
		+ maxf(rise_weight, 0.0)
		+ maxf(erratic_weight, 0.0)
	)


func get_action_distribution() -> Dictionary:
	var total := get_total_action_weight()

	if total <= 0.0:
		return {
			"surge": 0.0,
			"side_run": 0.0,
			"dive": 0.0,
			"rise": 0.0,
			"erratic": 0.0,
		}

	return {
		"surge": maxf(surge_weight, 0.0) / total,
		"side_run": maxf(side_run_weight, 0.0) / total,
		"dive": maxf(dive_weight, 0.0) / total,
		"rise": maxf(rise_weight, 0.0) / total,
		"erratic": maxf(erratic_weight, 0.0) / total,
	}


func get_dominant_action_label() -> String:
	var weights := {
		"SURGE": maxf(surge_weight, 0.0),
		"SIDE RUN": maxf(side_run_weight, 0.0),
		"DIVE": maxf(dive_weight, 0.0),
		"RISE": maxf(rise_weight, 0.0),
		"ERRATIC": maxf(erratic_weight, 0.0),
	}
	var dominant := "SURGE"
	var dominant_weight := -1.0

	for action_name in weights:
		var weight := float(weights[action_name])
		if weight > dominant_weight:
			dominant = str(action_name)
			dominant_weight = weight

	return dominant


func get_personality_label() -> String:
	if not personality_name.strip_edges().is_empty():
		return personality_name.strip_edges()

	return "%s / %s" % [
		get_archetype_label(),
		get_dominant_action_label(),
	]


func get_personality_signature() -> String:
	var distribution := get_action_distribution()
	return "%s|T%d|%s|%s|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f" % [
		get_archetype_label(),
		difficulty_tier,
		get_personality_label(),
		get_dominant_action_label(),
		float(distribution.get("surge", 0.0)),
		float(distribution.get("side_run", 0.0)),
		float(distribution.get("dive", 0.0)),
		float(distribution.get("rise", 0.0)),
		float(distribution.get("erratic", 0.0)),
		thrash_chance,
	]


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
		"%s | T%d %s / %s | bite %s %.2f window %.2f retry %.2f | "
		+ "fight %.2f pressure %.2f pull %.2f recover %.2f"
	) % [
		get_archetype_label(),
		difficulty_tier,
		get_personality_label(),
		get_dominant_action_label(),
		get_bite_timing_style_label(),
		bite_aggression_multiplier,
		bite_window_multiplier,
		bite_retry_multiplier,
		fight_intensity_multiplier,
		pressure_multiplier,
		pull_multiplier,
		stamina_recovery_multiplier,
	]
