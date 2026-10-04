extends RefCounted
class_name FishingMasterStructureHunterPolicy

## Structure Hunter teaches the player to read the shape/cover beneath a cast.
## The lesson never changes structure or snag physics. It only watches the same
## local bottom-depth and fishing_snag signals the lure already encounters.

const MIN_TOTAL_DEPTH_METERS: float = 0.30
const REQUIRED_OBSERVATION_SECONDS: float = 1.25
const REQUIRED_HORIZONTAL_TRAVEL_METERS: float = 0.60
const REQUIRED_DEPTH_BREAK_METERS: float = 0.12
const MAX_VALID_SAMPLE_STEP_METERS: float = 1.50


static func horizontal_distance(a: Vector3, b: Vector3) -> float:
	var delta := b - a
	delta.y = 0.0
	return delta.length()


static func get_depth_span(min_depth: float, max_depth: float) -> float:
	if min_depth < 0.0 or max_depth < 0.0:
		return 0.0
	return maxf(max_depth - min_depth, 0.0)


static func advance_trace(
	observation_seconds: float,
	horizontal_travel: float,
	min_total_depth: float,
	max_total_depth: float,
	structure_contact: bool,
	has_previous_position: bool,
	previous_position: Vector3,
	current_position: Vector3,
	total_depth: float,
	direct_structure_contact: bool,
	delta: float
) -> Dictionary:
	var elapsed := maxf(observation_seconds, 0.0)
	var travel := maxf(horizontal_travel, 0.0)
	var min_depth := min_total_depth
	var max_depth := max_total_depth
	var contact := structure_contact or direct_structure_contact
	var valid_water := total_depth >= MIN_TOTAL_DEPTH_METERS
	var step_distance := 0.0
	var accepted_sample := false

	if valid_water:
		if not has_previous_position:
			accepted_sample = true
		else:
			step_distance = horizontal_distance(previous_position, current_position)
			accepted_sample = step_distance <= MAX_VALID_SAMPLE_STEP_METERS

	if accepted_sample:
		elapsed += maxf(delta, 0.0)
		travel += step_distance
		if min_depth < 0.0:
			min_depth = total_depth
		else:
			min_depth = minf(min_depth, total_depth)
		if max_depth < 0.0:
			max_depth = total_depth
		else:
			max_depth = maxf(max_depth, total_depth)

	var depth_span := get_depth_span(min_depth, max_depth)
	return {
		"observation_seconds": elapsed,
		"horizontal_travel": travel,
		"min_total_depth": min_depth,
		"max_total_depth": max_depth,
		"depth_span": depth_span,
		"structure_contact": contact,
		"valid_water": valid_water,
		"sample_accepted": accepted_sample,
		"step_distance": step_distance,
		"complete": is_complete(elapsed, travel, depth_span, contact),
	}


static func is_complete(
	observation_seconds: float,
	horizontal_travel: float,
	depth_span: float,
	structure_contact: bool
) -> bool:
	return (
		observation_seconds >= REQUIRED_OBSERVATION_SECONDS
		and horizontal_travel >= REQUIRED_HORIZONTAL_TRAVEL_METERS
		and (
			depth_span >= REQUIRED_DEPTH_BREAK_METERS
			or structure_contact
		)
	)


static func get_progress_ratio(
	observation_seconds: float,
	horizontal_travel: float,
	depth_span: float,
	structure_contact: bool
) -> float:
	var time_ratio := clampf(
		observation_seconds / maxf(REQUIRED_OBSERVATION_SECONDS, 0.001),
		0.0,
		1.0
	)
	var travel_ratio := clampf(
		horizontal_travel / maxf(REQUIRED_HORIZONTAL_TRAVEL_METERS, 0.001),
		0.0,
		1.0
	)
	var structure_ratio := 1.0 if structure_contact else clampf(
		depth_span / maxf(REQUIRED_DEPTH_BREAK_METERS, 0.001),
		0.0,
		1.0
	)
	return minf(time_ratio, minf(travel_ratio, structure_ratio))
