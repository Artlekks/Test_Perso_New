extends RefCounted
class_name FishingMasterTideReaderPolicy

## Teaching policy for Master Tide Reader.
##
## Tide Sense is a synthesis lesson: Read Current teaches passive drift and
## Weather Sense teaches the water column. Tide Reader asks the player to put
## those together under the *real* coastal tide that is already running.

const MIN_TOTAL_DEPTH_METERS: float = 0.30
const MIN_CURRENT_SPEED: float = 0.015
const MIN_TIDE_FLOW_RATIO: float = 0.18
const REQUIRED_HOLD_SECONDS: float = 1.35
const REQUIRED_ALONG_CURRENT_DRIFT_METERS: float = 0.04

const INCOMING_MAX_DEPTH_RATIO: float = 0.40
const OUTGOING_MIN_DEPTH_RATIO: float = 0.60

const TARGET_NONE: StringName = &"none"
const TARGET_SHALLOW: StringName = &"shallow"
const TARGET_DEEP: StringName = &"deep"


static func get_target_band(movement: StringName) -> StringName:
	match movement:
		&"incoming":
			return TARGET_SHALLOW
		&"outgoing":
			return TARGET_DEEP
	return TARGET_NONE


static func is_moving_tide(
	movement: StringName,
	flow_strength_ratio: float
) -> bool:
	return (
		(movement == &"incoming" or movement == &"outgoing")
		and flow_strength_ratio >= MIN_TIDE_FLOW_RATIO
	)


static func get_depth_ratio(current_depth: float, total_depth: float) -> float:
	if total_depth < MIN_TOTAL_DEPTH_METERS:
		return 0.0
	return clampf(current_depth / maxf(total_depth, 0.001), 0.0, 1.0)


static func is_target_depth(
	movement: StringName,
	current_depth: float,
	total_depth: float
) -> bool:
	if total_depth < MIN_TOTAL_DEPTH_METERS:
		return false
	var ratio := get_depth_ratio(current_depth, total_depth)
	match get_target_band(movement):
		TARGET_SHALLOW:
			return ratio <= INCOMING_MAX_DEPTH_RATIO
		TARGET_DEEP:
			return ratio >= OUTGOING_MIN_DEPTH_RATIO
	return false


static func get_along_current_drift(
	previous_position: Vector3,
	current_position: Vector3,
	current_velocity: Vector3
) -> float:
	if current_velocity.length() < MIN_CURRENT_SPEED:
		return 0.0
	var direction := current_velocity.normalized()
	var displacement := current_position - previous_position
	return maxf(displacement.dot(direction), 0.0)


static func advance_observation(
	observation_seconds: float,
	along_current_drift_meters: float,
	movement: StringName,
	flow_strength_ratio: float,
	current_velocity: Vector3,
	previous_position: Vector3,
	current_position: Vector3,
	current_depth: float,
	total_depth: float,
	is_reeling: bool,
	delta: float
) -> Dictionary:
	var elapsed := maxf(observation_seconds, 0.0)
	var drift := maxf(along_current_drift_meters, 0.0)
	var moving_tide := is_moving_tide(movement, flow_strength_ratio)
	var valid_water := total_depth >= MIN_TOTAL_DEPTH_METERS
	var active_current := current_velocity.length() >= MIN_CURRENT_SPEED
	var correct_depth := (
		valid_water
		and is_target_depth(movement, current_depth, total_depth)
	)
	var valid_read := (
		moving_tide
		and active_current
		and correct_depth
		and not is_reeling
	)

	if valid_read:
		elapsed += maxf(delta, 0.0)
		drift += get_along_current_drift(
			previous_position,
			current_position,
			current_velocity
		)
	else:
		# The lesson is one continuous read. Do not bank partial progress through
		# the wrong depth, slack water, shelter or active reeling.
		elapsed = 0.0
		drift = 0.0

	return {
		"observation_seconds": elapsed,
		"along_current_drift_meters": drift,
		"moving_tide": moving_tide,
		"valid_water": valid_water,
		"active_current": active_current,
		"correct_depth": correct_depth,
		"reeling": is_reeling,
		"depth_ratio": get_depth_ratio(current_depth, total_depth),
		"target_band": get_target_band(movement),
		"complete": is_complete(elapsed, drift),
	}


static func is_complete(
	observation_seconds: float,
	along_current_drift_meters: float
) -> bool:
	return (
		observation_seconds >= REQUIRED_HOLD_SECONDS
		and along_current_drift_meters >= REQUIRED_ALONG_CURRENT_DRIFT_METERS
	)


static func get_progress_ratio(
	observation_seconds: float,
	along_current_drift_meters: float
) -> float:
	var time_ratio := clampf(
		maxf(observation_seconds, 0.0)
		/ maxf(REQUIRED_HOLD_SECONDS, 0.001),
		0.0,
		1.0
	)
	var drift_ratio := clampf(
		maxf(along_current_drift_meters, 0.0)
		/ maxf(REQUIRED_ALONG_CURRENT_DRIFT_METERS, 0.001),
		0.0,
		1.0
	)
	return minf(time_ratio, drift_ratio)


static func get_target_label(movement: StringName) -> String:
	match get_target_band(movement):
		TARGET_SHALLOW:
			return "SHALLOW WATER"
		TARGET_DEEP:
			return "DEEP WATER"
	return "MOVING WATER"


static func get_movement_label(movement: StringName) -> String:
	match movement:
		&"incoming":
			return "INCOMING TIDE"
		&"outgoing":
			return "OUTGOING TIDE"
		&"slack":
			return "SLACK WATER"
	return "NO TIDE"
