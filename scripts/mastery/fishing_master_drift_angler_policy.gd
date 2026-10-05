extends RefCounted
class_name FishingMasterDriftAnglerPolicy

## Drift Casting lesson policy.
##
## The player must place the lure ACROSS or UPSTREAM of the live flow, then let
## the water carry it. Throwing straight downstream is not compensation; it is
## simply following the current. The lesson never modifies current physics.

const MIN_CURRENT_SPEED: float = 0.015
const MIN_CAST_DISTANCE_METERS: float = 0.35
const MAX_DOWNSTREAM_ALIGNMENT: float = 0.55
const UPSTREAM_ALIGNMENT_THRESHOLD: float = -0.15
const REQUIRED_OBSERVATION_SECONDS: float = 1.50
const REQUIRED_ALONG_CURRENT_DRIFT_METERS: float = 0.055
const REQUIRED_CROSS_TRACK_DRIFT_METERS: float = 0.025


static func horizontal(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


static func get_cast_alignment(
	player_position: Vector3,
	landing_position: Vector3,
	current_velocity: Vector3
) -> float:
	var cast_vector: Vector3 = horizontal(landing_position - player_position)
	var current_vector: Vector3 = horizontal(current_velocity)
	if cast_vector.length() < 0.0001 or current_vector.length() < MIN_CURRENT_SPEED:
		return 1.0
	return cast_vector.normalized().dot(current_vector.normalized())


static func evaluate_cast(
	player_position: Vector3,
	landing_position: Vector3,
	current_velocity: Vector3
) -> Dictionary:
	var cast_vector: Vector3 = horizontal(landing_position - player_position)
	var current_vector: Vector3 = horizontal(current_velocity)
	var cast_distance: float = cast_vector.length()
	var current_speed: float = current_vector.length()
	var active_water: bool = current_speed >= MIN_CURRENT_SPEED
	var long_enough: bool = cast_distance >= MIN_CAST_DISTANCE_METERS
	var alignment: float = get_cast_alignment(
		player_position,
		landing_position,
		current_velocity
	)
	var compensated: bool = (
		active_water
		and long_enough
		and alignment <= MAX_DOWNSTREAM_ALIGNMENT
	)
	return {
		"active_water": active_water,
		"long_enough": long_enough,
		"cast_distance": cast_distance,
		"current_speed": current_speed,
		"alignment": alignment,
		"upstream_cast": alignment <= UPSTREAM_ALIGNMENT_THRESHOLD,
		"compensated_cast": compensated,
	}


static func get_along_current_step(
	previous_position: Vector3,
	current_position: Vector3,
	current_velocity: Vector3
) -> float:
	var current_vector: Vector3 = horizontal(current_velocity)
	if current_vector.length() < MIN_CURRENT_SPEED:
		return 0.0
	var displacement: Vector3 = horizontal(current_position - previous_position)
	return maxf(displacement.dot(current_vector.normalized()), 0.0)


static func get_cross_track_drift(
	player_position: Vector3,
	landing_position: Vector3,
	current_position: Vector3
) -> float:
	var cast_vector: Vector3 = horizontal(landing_position - player_position)
	if cast_vector.length() < 0.0001:
		return 0.0
	var cast_direction: Vector3 = cast_vector.normalized()
	var displacement: Vector3 = horizontal(current_position - landing_position)
	var parallel: Vector3 = cast_direction * displacement.dot(cast_direction)
	return (displacement - parallel).length()


static func advance_observation(
	observation_seconds: float,
	along_current_drift_meters: float,
	max_cross_track_drift_meters: float,
	player_position: Vector3,
	landing_position: Vector3,
	previous_position: Vector3,
	current_position: Vector3,
	current_velocity: Vector3,
	cast_alignment: float,
	is_reeling: bool,
	delta: float
) -> Dictionary:
	var elapsed: float = maxf(observation_seconds, 0.0)
	var along_drift: float = maxf(along_current_drift_meters, 0.0)
	var cross_drift: float = maxf(max_cross_track_drift_meters, 0.0)
	var current_speed: float = horizontal(current_velocity).length()
	var active_water: bool = current_speed >= MIN_CURRENT_SPEED
	var upstream_cast: bool = cast_alignment <= UPSTREAM_ALIGNMENT_THRESHOLD

	if is_reeling:
		return {
			"observation_seconds": 0.0,
			"along_current_drift_meters": 0.0,
			"max_cross_track_drift_meters": 0.0,
			"active_water": active_water,
			"upstream_cast": upstream_cast,
			"reeling": true,
			"reset": true,
			"complete": false,
		}

	if active_water:
		elapsed += maxf(delta, 0.0)
		along_drift += get_along_current_step(
			previous_position,
			current_position,
			current_velocity
		)
		cross_drift = maxf(
			cross_drift,
			get_cross_track_drift(
				player_position,
				landing_position,
				current_position
			)
		)

	return {
		"observation_seconds": elapsed,
		"along_current_drift_meters": along_drift,
		"max_cross_track_drift_meters": cross_drift,
		"active_water": active_water,
		"upstream_cast": upstream_cast,
		"reeling": false,
		"reset": false,
		"complete": is_complete(
			elapsed,
			along_drift,
			cross_drift,
			upstream_cast
		),
	}


static func is_complete(
	observation_seconds: float,
	along_current_drift_meters: float,
	cross_track_drift_meters: float,
	upstream_cast: bool
) -> bool:
	var geometry_complete: bool = (
		upstream_cast
		or cross_track_drift_meters >= REQUIRED_CROSS_TRACK_DRIFT_METERS
	)
	return (
		observation_seconds >= REQUIRED_OBSERVATION_SECONDS
		and along_current_drift_meters >= REQUIRED_ALONG_CURRENT_DRIFT_METERS
		and geometry_complete
	)


static func get_progress_ratio(
	observation_seconds: float,
	along_current_drift_meters: float,
	cross_track_drift_meters: float,
	upstream_cast: bool
) -> float:
	var time_ratio: float = clampf(
		observation_seconds / REQUIRED_OBSERVATION_SECONDS,
		0.0,
		1.0
	)
	var drift_ratio: float = clampf(
		along_current_drift_meters / REQUIRED_ALONG_CURRENT_DRIFT_METERS,
		0.0,
		1.0
	)
	var geometry_ratio: float = 1.0 if upstream_cast else clampf(
		cross_track_drift_meters / REQUIRED_CROSS_TRACK_DRIFT_METERS,
		0.0,
		1.0
	)
	return minf(time_ratio, minf(drift_ratio, geometry_ratio))
