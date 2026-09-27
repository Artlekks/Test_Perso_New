extends Resource
class_name FishSpawnEntry

@export_category("Species")
@export var fish: FishData

## Base population weight at this fishing spot. This is spot rarity/abundance,
## not species attraction. Lure/depth/behavior multipliers are applied later.
@export_range(0.0, 100.0, 0.1)
var weight: float = 1.0

@export_category("Population Channels")
## Allows a fish to exist in the spot population but be excluded from random
## bite selection without deleting the authored entry.
@export var enabled_for_bites: bool = true

## Allows the visible ambient-shadow system to use this species.
@export var enabled_for_ambient: bool = true

## Spot-local bite weighting layered on top of the base population weight.
@export_range(0.0, 4.0, 0.05)
var bite_weight_multiplier: float = 1.0

## Spot-local ambient presentation weighting. This does not alter bite odds.
@export_range(0.0, 4.0, 0.05)
var ambient_weight_multiplier: float = 1.0

@export_category("Optional Spot Depth Override")
## Leave false for normal FishData preferred depth. Use only when a particular
## location needs a species to occupy a different depth band.
@export var use_depth_override: bool = false

@export_range(0.0, 1.0, 0.01)
var depth_override_min: float = 0.0

@export_range(0.0, 1.0, 0.01)
var depth_override_max: float = 1.0

@export_category("Strategy Metadata")
## These are recommendations/debug metadata, not hard gameplay gates.
@export_range(0, 5, 1)
var recommended_min_tech_level: int = 0

@export_range(0, 3, 1)
var recommended_min_lure_level: int = 0

@export_range(0.0, 50.0, 0.5)
var recommended_min_cast_distance_m: float = 0.0

@export var hotspot_tag: StringName = &""

@export_multiline var strategy_note: String = ""


func get_base_bite_weight() -> float:
	if not enabled_for_bites or fish == null:
		return 0.0

	return (
		maxf(weight, 0.0)
		* maxf(bite_weight_multiplier, 0.0)
	)


func get_ambient_weight() -> float:
	if not enabled_for_ambient or fish == null:
		return 0.0

	return (
		maxf(weight, 0.0)
		* maxf(ambient_weight_multiplier, 0.0)
	)


func get_bite_selection_weight(
	bait: BaitData,
	current_depth: float,
	total_depth: float,
	is_reeling: bool = false
) -> float:
	var base_weight: float = get_base_bite_weight()

	if base_weight <= 0.0:
		return 0.0

	var lure_multiplier: float = (
		fish.get_lure_match_multiplier(
			bait,
			is_reeling
		)
	)
	var depth_multiplier: float = get_depth_match_multiplier(
		current_depth,
		total_depth
	)
	var behavior_multiplier: float = (
		fish.get_bite_aggression_multiplier()
	)

	return (
		base_weight
		* lure_multiplier
		* depth_multiplier
		* behavior_multiplier
	)


func get_depth_match_multiplier(
	current_depth: float,
	total_depth: float
) -> float:
	if fish == null:
		return 0.0

	if not use_depth_override:
		return fish.get_depth_match_multiplier(
			current_depth,
			total_depth
		)

	if total_depth <= 0.0:
		return 1.0

	var depth_ratio: float = clampf(
		current_depth / total_depth,
		0.0,
		1.0
	)

	var band_min: float = clampf(
		minf(
			depth_override_min,
			depth_override_max
		),
		0.0,
		1.0
	)
	var band_max: float = clampf(
		maxf(
			depth_override_min,
			depth_override_max
		),
		0.0,
		1.0
	)

	if (
		depth_ratio >= band_min
		and depth_ratio <= band_max
	):
		return 1.0

	var distance_from_band: float = 0.0

	if depth_ratio < band_min:
		distance_from_band = (
			band_min - depth_ratio
		)
	else:
		distance_from_band = (
			depth_ratio - band_max
		)

	var falloff: float = maxf(
		fish.depth_falloff_width,
		0.01
	)
	var t: float = clampf(
		distance_from_band / falloff,
		0.0,
		1.0
	)
	var eased: float = t * t * (3.0 - 2.0 * t)

	return lerpf(
		1.0,
		clampf(
			fish.out_of_depth_multiplier,
			0.0,
			1.0
		),
		eased
	)


func get_debug_summary() -> String:
	if fish == null:
		return "EMPTY"

	var extras: Array[String] = []

	if recommended_min_tech_level > 0:
		extras.append(
			"Tech%d+" % recommended_min_tech_level
		)

	if recommended_min_lure_level > 0:
		extras.append(
			"Lure%d+" % recommended_min_lure_level
		)

	if recommended_min_cast_distance_m > 0.0:
		extras.append(
			"Cast%.0fm+" % recommended_min_cast_distance_m
		)

	if hotspot_tag != &"":
		extras.append(
			"@%s" % String(hotspot_tag)
		)

	var extra_text: String = ""
	if not extras.is_empty():
		extra_text = " | " + " ".join(extras)

	return "%s w%.1f bite%.2f amb%.2f%s" % [
		fish.fish_name,
		weight,
		bite_weight_multiplier,
		ambient_weight_multiplier,
		extra_text,
	]
