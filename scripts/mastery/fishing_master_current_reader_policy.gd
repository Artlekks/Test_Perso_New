extends RefCounted
class_name FishingMasterCurrentReaderPolicy

## The lesson is deliberately about observing real water physics rather than
## receiving a hidden current buff. The lure must passively drift with moving
## water for long enough and far enough to demonstrate the read.

const MIN_CURRENT_SPEED: float = 0.015
const REQUIRED_OBSERVATION_SECONDS: float = 2.0
const REQUIRED_ALONG_CURRENT_DRIFT_METERS: float = 0.05


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
	current_velocity: Vector3,
	previous_position: Vector3,
	current_position: Vector3,
	is_reeling: bool,
	delta: float
) -> Dictionary:
	var elapsed := maxf(observation_seconds, 0.0)
	var drift := maxf(along_current_drift_meters, 0.0)
	var speed := current_velocity.length()
	var active_water := speed >= MIN_CURRENT_SPEED

	if active_water and not is_reeling:
		elapsed += maxf(delta, 0.0)
		drift += get_along_current_drift(
			previous_position,
			current_position,
			current_velocity
		)

	return {
		"observation_seconds": elapsed,
		"along_current_drift_meters": drift,
		"current_speed": speed,
		"active_water": active_water,
		"reeling": is_reeling,
		"complete": is_complete(elapsed, drift),
	}


static func is_complete(
	observation_seconds: float,
	along_current_drift_meters: float
) -> bool:
	return (
		observation_seconds >= REQUIRED_OBSERVATION_SECONDS
		and along_current_drift_meters >= REQUIRED_ALONG_CURRENT_DRIFT_METERS
	)


static func get_progress_ratio(
	observation_seconds: float,
	along_current_drift_meters: float
) -> float:
	var time_ratio := clampf(
		observation_seconds / maxf(REQUIRED_OBSERVATION_SECONDS, 0.001),
		0.0,
		1.0
	)
	var drift_ratio := clampf(
		along_current_drift_meters / maxf(REQUIRED_ALONG_CURRENT_DRIFT_METERS, 0.001),
		0.0,
		1.0
	)
	return minf(time_ratio, drift_ratio)
