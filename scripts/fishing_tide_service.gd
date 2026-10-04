extends Node
class_name FishingTideService

## Tide is world state, not a mastery bonus.
##
## Ocean spots move through one continuous cycle:
## low slack -> incoming -> high slack -> outgoing -> low slack.
## Tide Sense only reveals what this service is already doing.

signal tide_changed(snapshot: Dictionary)

const PHASE_LOW_SLACK: StringName = &"low_slack"
const PHASE_INCOMING: StringName = &"incoming"
const PHASE_HIGH_SLACK: StringName = &"high_slack"
const PHASE_OUTGOING: StringName = &"outgoing"

const DEFAULT_CYCLE_SECONDS: float = 720.0
const DEFAULT_START_POSITION: float = 0.22
const EMIT_BUCKET_COUNT: int = 40

var auto_advance: bool = true
var cycle_duration_seconds: float = DEFAULT_CYCLE_SECONDS

var _spot: FishingSpotData = null
var _cycle_position: float = DEFAULT_START_POSITION
var _last_emit_bucket: int = -1


func _ready() -> void:
	_last_emit_bucket = _get_emit_bucket()
	set_process(auto_advance)


func _process(delta: float) -> void:
	if not auto_advance or cycle_duration_seconds <= 0.0:
		return
	var old_phase := get_phase_id()
	var old_bucket := _get_emit_bucket()
	_cycle_position = wrapf(
		_cycle_position + maxf(delta, 0.0) / cycle_duration_seconds,
		0.0,
		1.0
	)
	var new_phase := get_phase_id()
	var new_bucket := _get_emit_bucket()
	if is_active() and (old_phase != new_phase or old_bucket != new_bucket):
		_last_emit_bucket = new_bucket
		_emit_changed()


func set_auto_advance(enabled: bool) -> void:
	auto_advance = enabled
	set_process(auto_advance)


func set_cycle_duration(seconds: float) -> void:
	cycle_duration_seconds = maxf(seconds, 1.0)


func set_spot(spot: FishingSpotData) -> void:
	_spot = spot
	_emit_changed()


func get_spot() -> FishingSpotData:
	return _spot


func is_active() -> bool:
	return (
		_spot != null
		and int(_spot.water_type) == int(FishingSpotData.WaterType.OCEAN)
	)


func set_cycle_position(normalized_position: float) -> void:
	_cycle_position = wrapf(normalized_position, 0.0, 1.0)
	_last_emit_bucket = _get_emit_bucket()
	_emit_changed()


func get_cycle_position() -> float:
	return _cycle_position


func get_phase_id() -> StringName:
	var p := _cycle_position
	if p < 0.08 or p >= 0.92:
		return PHASE_LOW_SLACK
	if p < 0.42:
		return PHASE_INCOMING
	if p < 0.58:
		return PHASE_HIGH_SLACK
	return PHASE_OUTGOING


func get_phase_name() -> String:
	match get_phase_id():
		PHASE_LOW_SLACK:
			return "Low Slack"
		PHASE_INCOMING:
			return "Incoming Tide"
		PHASE_HIGH_SLACK:
			return "High Slack"
		PHASE_OUTGOING:
			return "Outgoing Tide"
		_:
			return "Unknown Tide"


func get_next_phase_id() -> StringName:
	match get_phase_id():
		PHASE_LOW_SLACK:
			return PHASE_INCOMING
		PHASE_INCOMING:
			return PHASE_HIGH_SLACK
		PHASE_HIGH_SLACK:
			return PHASE_OUTGOING
		PHASE_OUTGOING:
			return PHASE_LOW_SLACK
		_:
			return PHASE_LOW_SLACK


func get_next_phase_name() -> String:
	match get_next_phase_id():
		PHASE_LOW_SLACK:
			return "Low Slack"
		PHASE_INCOMING:
			return "Incoming Tide"
		PHASE_HIGH_SLACK:
			return "High Slack"
		PHASE_OUTGOING:
			return "Outgoing Tide"
		_:
			return "Unknown Tide"


func get_time_to_next_phase_seconds() -> float:
	var distance := 0.0
	match get_phase_id():
		PHASE_LOW_SLACK:
			if _cycle_position >= 0.92:
				distance = (1.0 - _cycle_position) + 0.08
			else:
				distance = 0.08 - _cycle_position
		PHASE_INCOMING:
			distance = 0.42 - _cycle_position
		PHASE_HIGH_SLACK:
			distance = 0.58 - _cycle_position
		PHASE_OUTGOING:
			distance = 0.92 - _cycle_position
	return maxf(distance, 0.0) * maxf(cycle_duration_seconds, 1.0)


func get_water_level_ratio() -> float:
	# 0.0 at low tide, 1.0 at high tide.
	return 0.5 - 0.5 * cos(_cycle_position * TAU)


func get_flow_strength_ratio() -> float:
	# Strongest halfway between high/low; near zero at both slack waters.
	return absf(sin(_cycle_position * TAU))


func get_movement_id() -> StringName:
	var phase := get_phase_id()
	if phase == PHASE_LOW_SLACK or phase == PHASE_HIGH_SLACK:
		return &"slack"
	if _cycle_position < 0.5:
		return &"incoming"
	return &"outgoing"


func get_current_multiplier() -> float:
	if not is_active():
		return 1.0
	return lerpf(0.62, 1.25, get_flow_strength_ratio())


func get_depth_activity_profile() -> Dictionary:
	if not is_active():
		return {
			"surface": 1.0,
			"mid": 1.0,
			"deep": 1.0,
		}

	var water := get_water_level_ratio()
	var flow := get_flow_strength_ratio()
	var incoming := _cycle_position < 0.5
	var surface := 0.90 + 0.20 * water
	var mid := 0.98 + 0.08 * flow
	var deep := 1.12 - 0.12 * water
	if incoming:
		surface += 0.12 * flow
	else:
		deep += 0.08 * flow
	return {
		"surface": clampf(surface, 0.75, 1.25),
		"mid": clampf(mid, 0.75, 1.25),
		"deep": clampf(deep, 0.75, 1.25),
	}


func get_zone_multipliers() -> Dictionary:
	## These are productive/fishable-water multipliers, not collision geometry.
	## High/incoming water opens shoreline feeding lanes; outgoing/low water
	## makes outer water comparatively more productive.
	if not is_active():
		return {
			"shore": 1.0,
			"mid": 1.0,
			"outer": 1.0,
		}

	var water := get_water_level_ratio()
	var flow := get_flow_strength_ratio()
	var incoming := _cycle_position < 0.5
	var shore := 0.78 + 0.42 * water
	var mid := 0.98 + 0.10 * flow
	var outer := 1.12 - 0.16 * water
	if incoming:
		shore += 0.14 * flow
	else:
		shore -= 0.04 * flow
		outer += 0.06 * flow
	return {
		"shore": clampf(shore, 0.70, 1.30),
		"mid": clampf(mid, 0.80, 1.25),
		"outer": clampf(outer, 0.80, 1.30),
	}


func get_bite_activity_multiplier(depth_ratio: float = 0.5) -> float:
	if not is_active():
		return 1.0
	var flow := get_flow_strength_ratio()
	var water := get_water_level_ratio()
	var base := 0.92 + 0.17 * flow + 0.03 * water
	var depth_multiplier := _sample_depth_profile(
		get_depth_activity_profile(),
		clampf(depth_ratio, 0.0, 1.0)
	)
	return clampf(base * depth_multiplier, 0.72, 1.35)


func get_species_selection_multiplier(fish: FishData) -> float:
	if not is_active() or fish == null:
		return 1.0
	var preferred_depth := clampf(
		(
			float(fish.preferred_depth_min)
			+ float(fish.preferred_depth_max)
		) * 0.5,
		0.0,
		1.0
	)
	return clampf(
		_sample_depth_profile(get_depth_activity_profile(), preferred_depth),
		0.75,
		1.25
	)


func get_snapshot() -> Dictionary:
	var active := is_active()
	var depth_profile := get_depth_activity_profile()
	var zones := get_zone_multipliers()
	return {
		"active": active,
		"spot_id": str(_spot.spot_id) if _spot != null else "",
		"phase_id": get_phase_id() if active else &"none",
		"phase_name": get_phase_name() if active else "No Tide",
		"next_phase_id": get_next_phase_id() if active else &"none",
		"next_phase_name": get_next_phase_name() if active else "",
		"movement": get_movement_id() if active else &"none",
		"cycle_position": _cycle_position,
		"water_level_ratio": get_water_level_ratio() if active else 0.0,
		"flow_strength_ratio": get_flow_strength_ratio() if active else 0.0,
		"current_multiplier": get_current_multiplier(),
		"bite_activity_multiplier": get_bite_activity_multiplier(0.5),
		"depth_activity": depth_profile,
		"zone_multipliers": zones,
		"seconds_to_next_phase": get_time_to_next_phase_seconds() if active else 0.0,
	}


func _sample_depth_profile(profile: Dictionary, depth_ratio: float) -> float:
	var surface := float(profile.get("surface", 1.0))
	var mid := float(profile.get("mid", 1.0))
	var deep := float(profile.get("deep", 1.0))
	if depth_ratio <= 0.5:
		return lerpf(surface, mid, depth_ratio * 2.0)
	return lerpf(mid, deep, (depth_ratio - 0.5) * 2.0)


func _get_emit_bucket() -> int:
	return clampi(
		int(floor(_cycle_position * float(EMIT_BUCKET_COUNT))),
		0,
		EMIT_BUCKET_COUNT - 1
	)


func _emit_changed() -> void:
	tide_changed.emit(get_snapshot())
