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
# Full low-to-low cycle in in-game minutes. One game minute is currently
# five real seconds, so a full ocean tide lasts about 62 real minutes.
const GAME_CYCLE_MINUTES: float = 745.0
const CLOCK_START_MINUTE: int = 480


var auto_advance: bool = true
var cycle_duration_seconds: float = DEFAULT_CYCLE_SECONDS

var _spot: FishingSpotData = null
var _cycle_position: float = DEFAULT_START_POSITION
var _last_emit_bucket: int = -1
var _game_clock_sync_enabled: bool = false
var _clock_service: Node = null
var _last_game_minute: int = -1


func _ready() -> void:
	_last_emit_bucket = _get_emit_bucket()
	set_process(auto_advance)
	# Only the real session-owned tide service uses the world clock.
	# Standalone legacy QA fixtures retain manual tide positioning.
	var parent: Node = get_parent()
	if parent != null and parent.name == "FishingSessionServices":
		enable_game_clock_sync()


func _process(delta: float) -> void:
	if _game_clock_sync_enabled:
		# GameClock is added deferred by WorldLocations: session services can
		# initialize before it exists. Retry binding without creating duplicates.
		if not is_instance_valid(_clock_service):
			var clock: Node = get_node_or_null("/root/GameClock")
			if clock != null:
				set_clock_service(clock)
		return
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



func enable_game_clock_sync() -> void:
	## Production mode: a single authoritative clock drives tide and fish activity.
	## Legacy manual advancement remains available for standalone QA fixtures.
	_game_clock_sync_enabled = true
	set_process(true)
	var clock: Node = get_node_or_null("/root/GameClock")
	if clock != null:
		set_clock_service(clock)


func set_clock_service(clock: Node) -> void:
	## Explicit injection supports isolated tests without creating a second clock.
	if is_instance_valid(_clock_service):
		var old_callback := Callable(self, "_on_game_clock_changed")
		if _clock_service.has_signal("clock_changed") and _clock_service.is_connected("clock_changed", old_callback):
			_clock_service.disconnect("clock_changed", old_callback)
	_clock_service = clock if is_instance_valid(clock) and clock.has_method("get_snapshot") else null
	_game_clock_sync_enabled = _clock_service != null
	_last_game_minute = -1
	if _clock_service != null:
		var callback := Callable(self, "_on_game_clock_changed")
		if _clock_service.has_signal("clock_changed") and not _clock_service.is_connected("clock_changed", callback):
			_clock_service.connect("clock_changed", callback)
		_on_game_clock_changed(_clock_service.call("get_snapshot") as Dictionary)
	set_process(_game_clock_sync_enabled or auto_advance)


func _on_game_clock_changed(snapshot: Dictionary) -> void:
	if not _game_clock_sync_enabled:
		return
	var minute: int = maxi(0, int(snapshot.get("total_minutes", CLOCK_START_MINUTE)))
	if minute == _last_game_minute:
		return
	_last_game_minute = minute
	# Absolute minute -> deterministic tide: persisted day/time reproduces the
	# same phase on restart. Do NOT advance a second independent realtime timer.
	var next_position := wrapf(
		DEFAULT_START_POSITION + float(minute - CLOCK_START_MINUTE) / GAME_CYCLE_MINUTES,
		0.0, 1.0
	)
	var changed: bool = _get_emit_bucket() != mini(EMIT_BUCKET_COUNT - 1, int(floor(next_position * EMIT_BUCKET_COUNT)))
	_cycle_position = next_position
	_last_emit_bucket = _get_emit_bucket()
	if changed:
		_emit_changed()


func get_preview_snapshot(spot: FishingSpotData) -> Dictionary:
	## Read-only location preview, including when fishing has not started.
	## Never calls set_spot(): active fishing and mastery remain untouched.
	if spot == null or int(spot.water_type) != int(FishingSpotData.WaterType.OCEAN):
		return {"active": false, "phase_name": "No Tide", "phase_id": &"none"}
	return {
		"active": true,
		"spot_id": str(spot.spot_id),
		"phase_id": get_phase_id(),
		"phase_name": get_phase_name(),
		"movement": get_movement_id(),
		"water_level_ratio": get_water_level_ratio(),
		"flow_strength_ratio": get_flow_strength_ratio(),
		"cycle_position": _cycle_position,
	}

func set_auto_advance(enabled: bool) -> void:
	auto_advance = enabled
	set_process(_game_clock_sync_enabled or auto_advance)


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
	if _game_clock_sync_enabled and is_instance_valid(_clock_service):
		# Public time-to-next-phase remains in real seconds for existing readers.
		return maxf(distance, 0.0) * GAME_CYCLE_MINUTES * 5.0
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
	return get_current_multiplier_for_spot(_spot)


func get_current_multiplier_for_spot(spot: FishingSpotData) -> float:
	## Same ocean physics for a read-only exploration preview. Rivers/lakes
	## are unaffected, and the active fishing spot is never overwritten.
	if spot == null or int(spot.water_type) != int(FishingSpotData.WaterType.OCEAN):
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
