extends RefCounted
class_name FishingTideSensePolicy

const LEVEL_LOW: StringName = &"low"
const LEVEL_MID: StringName = &"mid"
const LEVEL_HIGH: StringName = &"high"

const FLOW_SLACK: StringName = &"slack"
const FLOW_STEADY: StringName = &"steady"
const FLOW_STRONG: StringName = &"strong"

const FEEDING_SLOW: StringName = &"slow"
const FEEDING_STEADY: StringName = &"steady"
const FEEDING_ACTIVE: StringName = &"active"

const ZONE_SHORE: StringName = &"shore"
const ZONE_MID: StringName = &"mid"
const ZONE_OUTER: StringName = &"outer"

const SPECIES_SHALLOW: StringName = &"shallow"
const SPECIES_MIXED: StringName = &"mixed"
const SPECIES_DEEP: StringName = &"deep"


static func build_read_snapshot(tide_snapshot: Dictionary) -> Dictionary:
	if not bool(tide_snapshot.get("active", false)):
		return {
			"available": false,
			"reason": "tide_not_applicable",
		}

	var water := float(tide_snapshot.get("water_level_ratio", 0.0))
	var flow := float(tide_snapshot.get("flow_strength_ratio", 0.0))
	var bite := float(tide_snapshot.get("bite_activity_multiplier", 1.0))
	var zones: Dictionary = tide_snapshot.get("zone_multipliers", {}) as Dictionary
	var depths: Dictionary = tide_snapshot.get("depth_activity", {}) as Dictionary

	var water_level := _water_level_read(water)
	var current_read := _flow_read(flow)
	var feeding_read := _feeding_read(bite)
	var favored_zone := _favored_zone(zones)
	var species_bias := _species_bias(depths)
	var phase_name := str(tide_snapshot.get("phase_name", "Tide"))
	var movement := StringName(str(tide_snapshot.get("movement", "slack")))
	var next_phase_name := str(tide_snapshot.get("next_phase_name", ""))

	var lines := PackedStringArray()
	lines.append("%s — %s water." % [phase_name, _water_level_text(water_level)])
	lines.append("Tidal flow: %s." % _flow_text(current_read))
	lines.append("Feeding window: %s." % _feeding_text(feeding_read))
	lines.append("Best water: %s." % _zone_text(favored_zone))
	lines.append("Species movement: %s." % _species_text(species_bias))

	return {
		"available": true,
		"phase_id": tide_snapshot.get("phase_id", &"none"),
		"phase_name": phase_name,
		"movement": movement,
		"water_level": water_level,
		"current_strength": current_read,
		"feeding_window": feeding_read,
		"favored_zone": favored_zone,
		"species_bias": species_bias,
		"next_phase_name": next_phase_name,
		"read_lines": lines,
		# Exact values are intentionally tucked under resolved for QA/debug.
		"resolved": {
			"cycle_position": float(tide_snapshot.get("cycle_position", 0.0)),
			"water_level_ratio": water,
			"flow_strength_ratio": flow,
			"current_multiplier": float(tide_snapshot.get("current_multiplier", 1.0)),
			"bite_activity_multiplier": bite,
			"depth_activity": depths.duplicate(true),
			"zone_multipliers": zones.duplicate(true),
			"seconds_to_next_phase": float(tide_snapshot.get("seconds_to_next_phase", 0.0)),
		},
	}


static func _water_level_read(value: float) -> StringName:
	if value < 0.30:
		return LEVEL_LOW
	if value > 0.70:
		return LEVEL_HIGH
	return LEVEL_MID


static func _flow_read(value: float) -> StringName:
	if value < 0.30:
		return FLOW_SLACK
	if value > 0.78:
		return FLOW_STRONG
	return FLOW_STEADY


static func _feeding_read(value: float) -> StringName:
	if value < 0.96:
		return FEEDING_SLOW
	if value > 1.08:
		return FEEDING_ACTIVE
	return FEEDING_STEADY


static func _favored_zone(zones: Dictionary) -> StringName:
	var shore := float(zones.get("shore", 1.0))
	var mid := float(zones.get("mid", 1.0))
	var outer := float(zones.get("outer", 1.0))
	if shore >= mid and shore >= outer:
		return ZONE_SHORE
	if outer >= shore and outer >= mid:
		return ZONE_OUTER
	return ZONE_MID


static func _species_bias(depths: Dictionary) -> StringName:
	var surface := float(depths.get("surface", 1.0))
	var mid := float(depths.get("mid", 1.0))
	var deep := float(depths.get("deep", 1.0))
	if surface > deep + 0.05 and surface >= mid:
		return SPECIES_SHALLOW
	if deep > surface + 0.05 and deep >= mid:
		return SPECIES_DEEP
	return SPECIES_MIXED


static func _water_level_text(value: StringName) -> String:
	match value:
		LEVEL_LOW:
			return "low"
		LEVEL_HIGH:
			return "high"
		_:
			return "mid-level"


static func _flow_text(value: StringName) -> String:
	match value:
		FLOW_SLACK:
			return "slack"
		FLOW_STRONG:
			return "strong"
		_:
			return "steady"


static func _feeding_text(value: StringName) -> String:
	match value:
		FEEDING_SLOW:
			return "slow"
		FEEDING_ACTIVE:
			return "active"
		_:
			return "steady"


static func _zone_text(value: StringName) -> String:
	match value:
		ZONE_SHORE:
			return "shoreline lanes"
		ZONE_OUTER:
			return "outer water"
		_:
			return "mid-water lanes"


static func _species_text(value: StringName) -> String:
	match value:
		SPECIES_SHALLOW:
			return "shallower fish are pushing in"
		SPECIES_DEEP:
			return "deeper fish are favored"
		_:
			return "mixed-depth activity"
