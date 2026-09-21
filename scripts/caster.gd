extends Node3D

signal bait_landed(point: Vector3)
signal bait_returned
signal bait_depth_changed(current_depth: float, total_depth: float)
signal bait_distance_changed(distance_meters: float)

@export var bait_scene: PackedScene
@export var spawn_point: Node3D

@export var min_speed: float = 1.0
@export var max_speed: float = 10.0
@export var launch_angle_degrees: float = 45.0
@export var reel_target: Node3D
@export_category("Distance Display")
@export var distance_meter_scale: float = 2.0
@export var cast_gravity: float = 24.0

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
	swim_bounds: Node
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

	active_bait.set_reel_target(reel_target)
	active_bait.set_swim_bounds(swim_bounds)
	active_bait.gravity = cast_gravity
	
	active_bait.launch(
		spawn_point.global_position,
		initial_velocity,
		water_y,
		bottom_y
	)
	return active_bait

func predict_cast(
	power: float,
	direction: Vector3,
	water_y: float
) -> PackedVector3Array:
	var points := PackedVector3Array()

	if spawn_point == null:
		return points

	var predicted_position := spawn_point.global_position
	var velocity := calculate_initial_velocity(
		power,
		direction
	)

	var step := 1.0 / float(Engine.physics_ticks_per_second)

	points.append(predicted_position)

	for i in range(300):
		# Same integration order as bait_V2.gd.
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
	current_bait_depth = current_depth
	current_total_depth = total_depth

	bait_depth_changed.emit(
		current_depth,
		total_depth
	)

func _on_bait_returned() -> void:
	if is_instance_valid(active_bait):
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

func cancel_bait() -> void:
	if is_instance_valid(active_bait):
		active_bait.queue_free()

	active_bait = null
	current_bait_depth = 0.0
	current_total_depth = 0.0
	bait_distance_changed.emit(0.0)

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
