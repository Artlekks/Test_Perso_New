extends RefCounted
class_name FishingWeatherSensePolicy

## Pure interpretation layer for Weather Sense.
##
## The existing FishingEnvironmentService remains authoritative for weather/time
## mechanics. This policy only turns those already-resolved multipliers into
## player-facing fishing information, so learning Weather Sense never buffs the
## weather itself.

const ACTIVITY_QUIET: StringName = &"quiet"
const ACTIVITY_NORMAL: StringName = &"normal"
const ACTIVITY_ACTIVE: StringName = &"active"
const ACTIVITY_VERY_ACTIVE: StringName = &"very_active"

const DEPTH_EVEN: StringName = &"even"
const DEPTH_SURFACE: StringName = &"surface"
const DEPTH_MID: StringName = &"mid"
const DEPTH_DEEP: StringName = &"deep"

const SPECIMEN_NORMAL: StringName = &"normal"
const SPECIMEN_PROMISING: StringName = &"promising"
const SPECIMEN_EXCELLENT: StringName = &"excellent"

const FIGHT_NORMAL: StringName = &"normal"
const FIGHT_DEMANDING: StringName = &"demanding"
const FIGHT_HARSH: StringName = &"harsh"

const TIER_COMMON: StringName = &"common_fish"
const TIER_BALANCED: StringName = &"balanced"
const TIER_TROPHY: StringName = &"trophy_fish"

const DEPTH_EVEN_TOLERANCE: float = 0.055


static func classify_activity(multiplier: float) -> StringName:
	var value := maxf(multiplier, 0.0)
	if value < 0.93:
		return ACTIVITY_QUIET
	if value < 1.08:
		return ACTIVITY_NORMAL
	if value < 1.24:
		return ACTIVITY_ACTIVE
	return ACTIVITY_VERY_ACTIVE


static func classify_favored_depth(
	surface_multiplier: float,
	mid_multiplier: float,
	deep_multiplier: float
) -> StringName:
	var surface := maxf(surface_multiplier, 0.0)
	var mid := maxf(mid_multiplier, 0.0)
	var deep := maxf(deep_multiplier, 0.0)
	var strongest := maxf(surface, maxf(mid, deep))
	var weakest := minf(surface, minf(mid, deep))

	if strongest - weakest <= DEPTH_EVEN_TOLERANCE:
		return DEPTH_EVEN
	if is_equal_approx(strongest, surface):
		return DEPTH_SURFACE
	if is_equal_approx(strongest, deep):
		return DEPTH_DEEP
	return DEPTH_MID


static func classify_specimen_outlook(
	quality_bonus_chance: float,
	quality_bonus_rolls: int
) -> StringName:
	var chance := clampf(quality_bonus_chance, 0.0, 1.0)
	var rolls := maxi(quality_bonus_rolls, 0)
	if rolls <= 0 or chance < 0.04:
		return SPECIMEN_NORMAL
	if chance < 0.15:
		return SPECIMEN_PROMISING
	return SPECIMEN_EXCELLENT


static func classify_fight_outlook(
	fish_pressure_multiplier: float,
	line_tolerance_multiplier: float,
	hook_off_delay_multiplier: float,
	counter_steer_multiplier: float
) -> StringName:
	var pressure := maxf(fish_pressure_multiplier, 0.01)
	var player_margin := (
		maxf(line_tolerance_multiplier, 0.01)
		+ maxf(hook_off_delay_multiplier, 0.01)
		+ maxf(counter_steer_multiplier, 0.01)
	) / 3.0
	var danger_ratio := pressure / maxf(player_margin, 0.01)

	if danger_ratio < 1.045:
		return FIGHT_NORMAL
	if danger_ratio < 1.18:
		return FIGHT_DEMANDING
	return FIGHT_HARSH


static func classify_tier_bias(
	tier_multipliers: PackedFloat32Array
) -> StringName:
	if tier_multipliers.size() < 5:
		return TIER_BALANCED

	var low_average := (
		maxf(float(tier_multipliers[0]), 0.0)
		+ maxf(float(tier_multipliers[1]), 0.0)
	) * 0.5
	var high_average := (
		maxf(float(tier_multipliers[3]), 0.0)
		+ maxf(float(tier_multipliers[4]), 0.0)
	) * 0.5
	var ratio := high_average / maxf(low_average, 0.01)

	if ratio >= 1.15:
		return TIER_TROPHY
	if ratio <= 0.90:
		return TIER_COMMON
	return TIER_BALANCED


static func get_activity_text(activity: StringName) -> String:
	match activity:
		ACTIVITY_QUIET:
			return "Fish activity is subdued."
		ACTIVITY_ACTIVE:
			return "Fish are moving and feeding actively."
		ACTIVITY_VERY_ACTIVE:
			return "The water is unusually active."
		_:
			return "Fish activity is steady."


static func get_depth_text(depth_band: StringName) -> String:
	match depth_band:
		DEPTH_SURFACE:
			return "Surface water has the strongest activity."
		DEPTH_MID:
			return "Mid-water has the strongest activity."
		DEPTH_DEEP:
			return "Deeper water has the strongest activity."
		_:
			return "Activity is spread fairly evenly through the water."


static func get_specimen_text(outlook: StringName) -> String:
	match outlook:
		SPECIMEN_PROMISING:
			return "Conditions are promising for better specimens."
		SPECIMEN_EXCELLENT:
			return "Conditions strongly favor exceptional specimens."
		_:
			return "Specimen quality looks ordinary."


static func get_fight_text(outlook: StringName) -> String:
	match outlook:
		FIGHT_DEMANDING:
			return "Hooked fish should fight a little harder than usual."
		FIGHT_HARSH:
			return "Expect harsh fights and smaller safety margins."
		_:
			return "Fight conditions are stable."


static func get_tier_text(tier_bias: StringName) -> String:
	match tier_bias:
		TIER_COMMON:
			return "Ordinary schooling fish have the stronger presence."
		TIER_TROPHY:
			return "Higher-tier fish are unusually active."
		_:
			return "Species activity is broadly balanced."


static func build_read_snapshot(
	condition_ids: PackedStringArray,
	condition_names: PackedStringArray,
	bite_activity_multiplier: float,
	surface_multiplier: float,
	mid_multiplier: float,
	deep_multiplier: float,
	quality_bonus_chance: float,
	quality_bonus_rolls: int,
	fish_pressure_multiplier: float,
	line_tolerance_multiplier: float,
	hook_off_delay_multiplier: float,
	counter_steer_multiplier: float,
	tier_multipliers: PackedFloat32Array
) -> Dictionary:
	var activity := classify_activity(bite_activity_multiplier)
	var depth_band := classify_favored_depth(
		surface_multiplier,
		mid_multiplier,
		deep_multiplier
	)
	var specimen := classify_specimen_outlook(
		quality_bonus_chance,
		quality_bonus_rolls
	)
	var fight := classify_fight_outlook(
		fish_pressure_multiplier,
		line_tolerance_multiplier,
		hook_off_delay_multiplier,
		counter_steer_multiplier
	)
	var tier_bias := classify_tier_bias(tier_multipliers)

	var read_lines := PackedStringArray([
		get_activity_text(activity),
		get_depth_text(depth_band),
		get_specimen_text(specimen),
		get_fight_text(fight),
		get_tier_text(tier_bias),
	])

	return {
		"available": true,
		"condition_ids": condition_ids.duplicate(),
		"condition_names": condition_names.duplicate(),
		"activity": activity,
		"favored_depth": depth_band,
		"specimen_outlook": specimen,
		"fight_outlook": fight,
		"tier_bias": tier_bias,
		"read_lines": read_lines,
		# Raw resolved values are included for QA/debug only. Gameplay presentation
		# should prefer the qualitative fields above.
		"resolved": {
			"bite_activity_multiplier": bite_activity_multiplier,
			"surface_activity_multiplier": surface_multiplier,
			"mid_activity_multiplier": mid_multiplier,
			"deep_activity_multiplier": deep_multiplier,
			"quality_bonus_roll_chance": quality_bonus_chance,
			"quality_bonus_rolls": quality_bonus_rolls,
			"fish_pressure_multiplier": fish_pressure_multiplier,
			"line_tolerance_multiplier": line_tolerance_multiplier,
			"hook_off_delay_multiplier": hook_off_delay_multiplier,
			"counter_steer_multiplier": counter_steer_multiplier,
			"tier_selection_multipliers": tier_multipliers.duplicate(),
		},
	}
