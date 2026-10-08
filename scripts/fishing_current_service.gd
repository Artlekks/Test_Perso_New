extends Node
class_name FishingCurrentService

signal current_profile_changed(snapshot: Dictionary)

@export_range(0.1, 10.0, 0.1) var direction_response := 2.0

func smooth_current_velocity(previous: Vector3, position: Vector3, delta: float) -> Vector3:
	var target := sample_current_velocity(position)
	var response := 1.0 - exp(-direction_response * maxf(delta, 0.0))
	if previous.length_squared() < 0.0000001 or target.length_squared() < 0.0000001:
		return previous.lerp(target, response)
	var heading := lerp_angle(atan2(previous.z, previous.x), atan2(target.z, target.x), response)
	return Vector3(cos(heading), 0.0, sin(heading)) * lerpf(previous.length(), target.length(), response)

var _spot: FishingSpotData = null
var _swim_bounds: FishSwimBounds = null
var _tide_service: Node = null


func set_spot(spot: FishingSpotData) -> void:
	_spot = spot
	current_profile_changed.emit(get_snapshot())


func set_tide_service(service: Node) -> void:
	var callback := Callable(self, "_on_tide_changed")
	if (
		_tide_service != null
		and _tide_service.has_signal("tide_changed")
		and _tide_service.is_connected("tide_changed", callback)
	):
		_tide_service.disconnect("tide_changed", callback)

	_tide_service = service
	if (
		_tide_service != null
		and _tide_service.has_signal("tide_changed")
		and not _tide_service.is_connected("tide_changed", callback)
	):
		_tide_service.connect("tide_changed", callback)
	current_profile_changed.emit(get_snapshot())


func set_swim_bounds(bounds: FishSwimBounds) -> void:
	_swim_bounds = bounds
	current_profile_changed.emit(get_snapshot())


func get_spot() -> FishingSpotData:
	return _spot


func get_swim_bounds() -> FishSwimBounds:
	return _swim_bounds


func sample_current_velocity(
	world_position: Vector3,
	time_seconds: float = -1.0
) -> Vector3:
	if _spot == null:
		return Vector3.ZERO

	var uv := Vector2(0.5, 0.5)
	if _swim_bounds != null:
		uv = _swim_bounds.world_to_normalized_uv(world_position)

	var flat := sample_current_at_uv(uv, time_seconds)
	return Vector3(flat.x, 0.0, flat.y)


func sample_current_at_uv(
	uv: Vector2,
	time_seconds: float = -1.0
) -> Vector2:
	if _spot == null:
		return Vector2.ZERO

	var direction_2d: Vector2 = _spot.current_direction
	var velocity := Vector2.ZERO
	if (
		direction_2d.length_squared() > 0.000001
		and _spot.current_speed > 0.0
	):
		velocity = direction_2d.normalized() * _spot.current_speed

	for field in _spot.current_fields:
		if field == null or not field.is_valid_definition():
			continue
		velocity = field.apply_to_velocity(velocity, uv)

	var phase_time: float = time_seconds
	if phase_time < 0.0:
		phase_time = float(Time.get_ticks_msec()) / 1000.0

	if _spot.current_gust_strength > 0.0 and velocity.length_squared() > 0.000001:
		var period := maxf(_spot.current_gust_period_seconds, 0.25)
		var phase := (
			phase_time / period * TAU
			+ uv.x * 2.17
			+ uv.y * 1.31
		)
		var multiplier := 1.0 + sin(phase) * _spot.current_gust_strength
		velocity *= maxf(multiplier, 0.05)

	if (
		_tide_service != null
		and _tide_service.has_method("get_current_multiplier")
	):
		velocity *= maxf(
			float(_tide_service.call("get_current_multiplier")),
			0.05
		)

	return velocity


func project_drift_path(
	world_start: Vector3,
	duration_seconds: float = 2.4,
	step_seconds: float = 0.4,
	time_seconds: float = -1.0
) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.append(world_start)
	if _spot == null:
		return points

	var step := maxf(step_seconds, 0.05)
	var duration := maxf(duration_seconds, 0.0)
	var elapsed := 0.0
	var position := world_start
	var base_time := time_seconds
	if base_time < 0.0:
		base_time = float(Time.get_ticks_msec()) / 1000.0

	while elapsed + 0.0001 < duration:
		var dt := minf(step, duration - elapsed)
		var velocity := sample_current_velocity(position, base_time + elapsed)
		var proposed := position + velocity * dt
		if _swim_bounds != null:
			proposed = _swim_bounds.constrain_fish_motion(position, proposed)
		position = proposed
		points.append(position)
		elapsed += dt

	return points


func get_dominant_field_id_at_uv(uv: Vector2) -> StringName:
	if _spot == null:
		return &""
	var best_id: StringName = &""
	var best_weight := 0.0
	for field in _spot.current_fields:
		if field == null or not field.is_valid_definition():
			continue
		var weight := field.get_weight(uv)
		if weight > best_weight:
			best_weight = weight
			best_id = field.field_id
	return best_id


func get_snapshot() -> Dictionary:
	if _spot == null:
		return {
			"spot_id": "",
			"active": false,
			"direction": Vector2.ZERO,
			"speed": 0.0,
			"gust_strength": 0.0,
			"field_count": 0,
		}
	var tide_snapshot: Dictionary = {}
	if _tide_service != null and _tide_service.has_method("get_snapshot"):
		tide_snapshot = _tide_service.call("get_snapshot") as Dictionary
	return {
		"spot_id": str(_spot.spot_id),
		"active": (
			(_spot.current_speed > 0.0 and _spot.current_direction.length_squared() > 0.000001)
			or _spot.get_valid_current_field_count() > 0
		),
		"direction": _spot.current_direction.normalized() if _spot.current_direction.length_squared() > 0.000001 else Vector2.ZERO,
		"speed": _spot.current_speed,
		"gust_strength": _spot.current_gust_strength,
		"visual_strength": _spot.current_visual_strength,
		"field_count": _spot.get_valid_current_field_count(),
		"tide": tide_snapshot,
	}


func _on_tide_changed(_snapshot: Dictionary) -> void:
	current_profile_changed.emit(get_snapshot())
