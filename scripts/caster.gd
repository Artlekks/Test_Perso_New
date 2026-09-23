extends Node3D

signal bait_landed(point: Vector3)
signal bait_returned
signal bait_depth_changed(current_depth: float, total_depth: float)
signal bait_distance_changed(distance_meters: float)
signal bait_snag_risk_changed(value: float)
signal bait_snagged(reason: StringName)

@export var bait_scene: PackedScene
@export var spawn_point: Node3D

@export var min_speed: float = 1.0
@export var max_speed: float = 10.0
@export var launch_angle_degrees: float = 45.0
@export var reel_target: Node3D
@export_category("Distance Display")
@export var distance_meter_scale: float = 2.0
@export var cast_gravity: float = 24.0

@export_category("Cast Feel")
## 1.0 = original flight duration.
## Lower values make the bait travel the same path more slowly without
## changing the selected power, trajectory, or landing point.
@export_range(0.5, 1.25, 0.01)
var cast_flight_playback_speed: float = 0.85

@export_category("Pre-Cast Curve")
## Maximum sideways bow while the landing torus is still locked.
@export_range(0.0, 0.75, 0.01)
var max_curve_lateral_ratio: float = 0.32
@export var max_curve_lateral_distance: float = 1.4

## Up to this normalized curve amount, only the arc bends and the torus stays
## fixed. Beyond it, the arc has reached its bend limit and extra input starts
## moving the landing point to the OPPOSITE side.
@export_range(0.1, 0.95, 0.01)
var landing_shift_threshold: float = 0.65

## Maximum opposite-side correction of the landing torus.
@export_range(0.0, 0.5, 0.01)
var max_landing_shift_ratio: float = 0.22
@export var max_landing_shift_distance: float = 1.1

var active_bait: Node3D
var current_bait_depth: float = 0.0
var current_total_depth: float = 0.0
var active_rod_data: RodData = null

func _process(_delta: float) -> void:
	if not is_instance_valid(active_bait):
		return

	if not is_instance_valid(reel_target):
		return

	var bait_flat := Vector2(
		active_bait.global_position.x,
		active_bait.global_position.z
	)

	var target_flat := Vector2(
		reel_target.global_position.x,
		reel_target.global_position.z
	)

	var distance_meters := (
		bait_flat.distance_to(target_flat)
		* distance_meter_scale
	)

	bait_distance_changed.emit(distance_meters)
	
func perform_cast(
	power: float,
	direction: Vector3,
	water_y: float,
	bottom_y: float,
	bait_data: BaitData,
	swim_bounds: Node,
	curve_amount: float = 0.0
) -> Node3D:
	if bait_scene == null or spawn_point == null:
		return null

	if is_instance_valid(active_bait):
		active_bait.queue_free()

	# Never let the next encounter inherit depth information from the
	# previous cast before the new bait emits its first depth update.
	current_bait_depth = 0.0
	current_total_depth = 0.0

	direction.y = 0.0
	direction = direction.normalized()

	var initial_velocity := calculate_initial_velocity(
		power,
		direction
	)

	active_bait = bait_scene.instantiate()
	add_child(active_bait)

	if bait_data != null:
		active_bait.set_data(bait_data)

	active_bait.set_reel_speed_multiplier(
		_get_rod_reel_speed_multiplier()
	)

	active_bait.landed.connect(_on_bait_landed)
	active_bait.depth_changed.connect(_on_bait_depth_changed)
	active_bait.returned.connect(_on_bait_returned)
	active_bait.snag_risk_changed.connect(_on_bait_snag_risk_changed)
	active_bait.snagged.connect(_on_bait_snagged)

	active_bait.set_reel_target(reel_target)
	active_bait.set_swim_bounds(swim_bounds)
	active_bait.gravity = cast_gravity

	active_bait.launch(
		spawn_point.global_position,
		initial_velocity,
		water_y,
		bottom_y
	)

	# Use the exact preview path for every cast, including straight casts.
	# Playback speed changes only how long the bait takes to traverse it;
	# power, arc shape, and landing position remain untouched.
	var air_path := predict_cast(
		power,
		direction,
		water_y,
		curve_amount
	)

	if (
		air_path.size() >= 2
		and active_bait.has_method("set_air_path")
	):
		active_bait.set_air_path(
			air_path,
			cast_flight_playback_speed
		)

	return active_bait

func predict_cast(
	power: float,
	direction: Vector3,
	water_y: float,
	curve_amount: float = 0.0
) -> PackedVector3Array:
	var points := _predict_straight_cast(
		power,
		direction,
		water_y
	)

	var clamped_curve := clampf(
		curve_amount,
		-1.0,
		1.0
	)

	if (
		absf(clamped_curve) < 0.01
		or points.size() < 3
	):
		return points

	var start_point: Vector3 = points[0]
	var straight_landing: Vector3 = points[
		points.size() - 1
	]

	var flat_forward := Vector3(
		straight_landing.x - start_point.x,
		0.0,
		straight_landing.z - start_point.z
	)

	var cast_distance := flat_forward.length()

	if cast_distance < 0.001:
		return points

	flat_forward /= cast_distance

	# This is the same lateral basis used by the fixed-landing pass.
	# The sign of curve_amount decides which side the arc initially bows.
	var side := Vector3.UP.cross(
		flat_forward
	).normalized()

	var threshold := clampf(
		landing_shift_threshold,
		0.01,
		0.99
	)
	var curve_abs := absf(clamped_curve)
	var curve_sign := signf(clamped_curve)

	# PHASE 1: from straight to the bend limit.
	# The torus is completely frozen in this range.
	var bend_fraction := clampf(
		curve_abs / threshold,
		0.0,
		1.0
	)
	var bend_strength := (
		curve_sign * bend_fraction
	)

	var max_bow := minf(
		cast_distance * max_curve_lateral_ratio,
		max_curve_lateral_distance
	)

	# PHASE 2: once the bend limit is reached, extra input shifts the
	# landing torus to the OPPOSITE side. Smoothstep avoids a visible snap
	# when crossing the threshold.
	var excess := 0.0

	if curve_abs > threshold:
		excess = clampf(
			(curve_abs - threshold)
			/ (1.0 - threshold),
			0.0,
			1.0
		)

	var eased_excess := (
		excess * excess
		* (3.0 - 2.0 * excess)
	)

	var max_landing_shift := minf(
		cast_distance * max_landing_shift_ratio,
		max_landing_shift_distance
	)

	var landing_shift := (
		-side
		* curve_sign
		* max_landing_shift
		* eased_excess
	)

	var last_index := points.size() - 1

	for i in range(1, points.size()):
		var t := float(i) / float(last_index)

		# Move progressively toward the corrected landing position.
		# At t=1 this is exactly the torus offset.
		points[i] += landing_shift * t

		if i == last_index:
			continue

		# The actual draw/fade bow is zero at launch and landing and
		# strongest near the middle of the cast.
		var bow := sin(PI * t)
		points[i] += (
			side
			* max_bow
			* bend_strength
			* bow
		)

	return points


func _predict_straight_cast(
	power: float,
	direction: Vector3,
	water_y: float
) -> PackedVector3Array:
	var points := PackedVector3Array()
	if spawn_point == null:
		return points

	var predicted_position := spawn_point.global_position
	var velocity := calculate_initial_velocity(power, direction)
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	points.append(predicted_position)

	for i in range(300):
		velocity.y -= cast_gravity * step
		var next_position := predicted_position + velocity * step

		if predicted_position.y >= water_y and next_position.y <= water_y:
			next_position.y = water_y
			points.append(next_position)
			break

		points.append(next_position)
		predicted_position = next_position

	return points

func calculate_initial_velocity(
	power: float,
	direction: Vector3
) -> Vector3:
	direction.y = 0.0
	direction = direction.normalized()

	var speed := lerpf(
		min_speed,
		max_speed,
		clampf(power, 0.0, 1.0)
	)

	if active_rod_data != null:
		speed *= active_rod_data.cast_speed_multiplier

	var angle := deg_to_rad(launch_angle_degrees)

	return Vector3(
		direction.x * speed * cos(angle),
		speed * sin(angle),
		direction.z * speed * cos(angle)
	)
	
func _on_bait_landed(point: Vector3) -> void:
	bait_landed.emit(point)


func _on_bait_depth_changed(
	current_depth: float,
	total_depth: float
) -> void:
	# queue_free() is deferred until the end of the frame. During a quick
	# cancel the old lure can otherwise emit one final depth update after
	# bait_returned, which makes the depth meter slide back in. Once there is
	# no active lure, ignore any such stale signal.
	if not is_instance_valid(active_bait):
		return

	current_bait_depth = current_depth
	current_total_depth = total_depth

	bait_depth_changed.emit(
		current_depth,
		total_depth
	)

func _on_bait_snag_risk_changed(value: float) -> void:
	bait_snag_risk_changed.emit(clampf(value, 0.0, 1.0))


func _on_bait_snagged(reason: StringName) -> void:
	bait_snagged.emit(reason)


func _on_bait_returned() -> void:
	if is_instance_valid(active_bait):
		# Stop the lure immediately before queue_free(). Deletion itself is
		# deferred, so this prevents a final process tick from producing HUD
		# updates after the return/cancel signal has already started hiding UI.
		active_bait.process_mode = Node.PROCESS_MODE_DISABLED
		active_bait.queue_free()

	active_bait = null
	current_bait_depth = 0.0
	current_total_depth = 0.0
	bait_distance_changed.emit(0.0)
	bait_returned.emit()


func set_reeling(active: bool) -> void:
	if is_instance_valid(active_bait):
		active_bait.set_reeling(active)


func set_reel_steering(value: float) -> void:
	if is_instance_valid(active_bait):
		active_bait.set_reel_steering(value)

func twitch_bait(direction: float) -> void:
	if is_instance_valid(active_bait):
		active_bait.twitch_side(direction)


func pull_bait_toward_player() -> void:
	if is_instance_valid(active_bait):
		active_bait.queue_manual_pull()
		
func set_fight_mode(active: bool) -> void:
	if is_instance_valid(active_bait):
		active_bait.set_fight_mode(active)

func set_fight_resistance(value: float) -> void:
	if is_instance_valid(active_bait):
		active_bait.set_fight_resistance(value)

func set_fish_pull_strength(value: float) -> void:
	if is_instance_valid(active_bait):
		active_bait.set_fish_pull_strength(value)

func set_fish_lateral(value: float) -> void:
	if is_instance_valid(active_bait):
		active_bait.set_fish_lateral(value)

func set_fish_depth_intent(value: float) -> void:
	if is_instance_valid(active_bait):
		active_bait.set_fish_depth_intent(value)

func get_current_bait_depth() -> float:
	return current_bait_depth

func get_current_total_depth() -> float:
	return current_total_depth


func get_active_bait_surface_position() -> Vector3:
	if not is_instance_valid(active_bait):
		return global_position

	if active_bait.has_method("get_surface_position"):
		return active_bait.get_surface_position()

	return active_bait.global_position

func cancel_bait() -> void:
	if is_instance_valid(active_bait):
		active_bait.queue_free()

	active_bait = null
	current_bait_depth = 0.0
	current_total_depth = 0.0
	bait_distance_changed.emit(0.0)


func cancel_bait_to_aim() -> void:
	# Immediate player-requested abandon of an unhooked cast. Reuse the
	# exact same signal path as a lure that was physically reeled home so
	# Encounter, HUD and Fishing state all reset consistently.
	if not is_instance_valid(active_bait):
		return

	_on_bait_returned()


func set_reel_speed_multiplier(value: float) -> void:
	if is_instance_valid(active_bait):
		active_bait.set_reel_speed_multiplier(
			value * _get_rod_reel_speed_multiplier()
		)


func set_rod_data(rod_data: RodData) -> void:
	active_rod_data = rod_data

	if is_instance_valid(active_bait):
		active_bait.set_reel_speed_multiplier(
			_get_rod_reel_speed_multiplier()
		)


func _get_rod_reel_speed_multiplier() -> float:
	if active_rod_data == null:
		return 1.0

	return maxf(
		active_rod_data.reel_speed_multiplier,
		0.0
	)

func set_air_curve(value: float) -> void:
	if is_instance_valid(active_bait):
		active_bait.set_air_curve(value)

func set_bait_frozen(active: bool) -> void:
	if is_instance_valid(active_bait):
		active_bait.set_simulation_frozen(active)

func show_bait_ripple() -> void:
	if is_instance_valid(active_bait):
		active_bait.show_ripple()


func hide_bait_ripple() -> void:
	if is_instance_valid(active_bait):
		active_bait.hide_ripple()
