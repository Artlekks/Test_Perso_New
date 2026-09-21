extends Node3D

signal landed(point: Vector3)
signal returned
signal depth_changed(current_depth: float, total_depth: float)

@onready var ripple_view: Node3D = $RippleView
@export var gravity: float = 24.0
@export var return_distance: float = 0.5
@export var data: BaitData
@export var floor_collision_mask: int = 2048
@export var floor_ray_depth: float = 100.0
@export var fight_reel_multiplier: float = 0.2
@export_category("Fight Steering")
@export_range(0.0, 1.0, 0.05)
var min_fight_steer_authority: float = 0.20
@export var max_fish_pull_speed: float = 1.5
@export var fish_vertical_speed: float = 0.8
@export var twitch_speed: float = 1.8
@export var twitch_deceleration: float = 12.0
@export_category("Fight Distance")
@export var max_extra_fight_distance: float = 3.0
@export_category("Free Reeling")
@export var free_reel_speed_multiplier: float = 2.5
@export_category("Air Curve")
@export var air_curve_speed_degrees: float = 35.0
@export var max_air_curve_degrees: float = 30.0

var twitch_velocity: Vector3 = Vector3.ZERO
var fight_max_distance: float = 0.0
var fish_depth_intent: float = 0.0
var fish_pull_strength: float = 0.0
var fight_mode: bool = false
var reel_steering: float = 0.0
var fight_resistance: float = 1.0
var fish_lateral: float = 0.0
var reel_speed_multiplier: float = 1.0
var air_curve_input: float = 0.0
var air_curve_angle: float = 0.0

enum State {
	IDLE,
	FLYING,
	SINKING,
	IN_WATER
}

var state: int = State.IDLE

var velocity: Vector3 = Vector3.ZERO

var water_y: float = 0.0
var bottom_y: float = 0.0

var reel_target: Node3D = null
var reeling: bool = false
var simulation_frozen: bool = false
var swim_bounds: Node = null

func launch(
	start_position: Vector3,
	initial_velocity: Vector3,
	surface_y: float,
	water_bottom_y: float
) -> void:
	global_position = start_position
	velocity = initial_velocity
	water_y = surface_y
	bottom_y = water_bottom_y
	air_curve_input = 0.0
	air_curve_angle = 0.0
	state = State.FLYING

	ripple_view.configure(
		self,
		water_y
	)

	ripple_view.hide_ripple()

func set_air_curve(value: float) -> void:
	air_curve_input = clampf(value, -1.0, 1.0)

func _update_air_curve(delta: float) -> void:
	if absf(air_curve_input) < 0.01:
		return

	var horizontal_velocity := Vector3(
		velocity.x,
		0.0,
		velocity.z
	)

	if horizontal_velocity.length_squared() < 0.001:
		return

	var max_angle := deg_to_rad(max_air_curve_degrees)

	var requested_change := (
		deg_to_rad(air_curve_speed_degrees)
		* air_curve_input
		* delta
	)

	var new_angle := clampf(
		air_curve_angle + requested_change,
		-max_angle,
		max_angle
	)

	var applied_change := new_angle - air_curve_angle
	air_curve_angle = new_angle

	horizontal_velocity = horizontal_velocity.rotated(
		Vector3.UP,
		applied_change
	)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	
func set_reel_target(target: Node3D) -> void:
	reel_target = target


func get_water_surface_y() -> float:
	return water_y


func get_reel_target_node() -> Node3D:
	return reel_target


func set_swim_bounds(bounds: Node) -> void:
	swim_bounds = bounds


func set_reeling(active: bool) -> void:
	reeling = active

	if fight_mode:
		return

	if not reeling and state == State.IN_WATER:
		var target_y := _get_sink_target_y()

		if not is_equal_approx(global_position.y, target_y):
			state = State.SINKING

func set_reel_steering(value: float) -> void:
	reel_steering = clampf(value, -1.0, 1.0)


func _physics_process(delta: float) -> void:
	if simulation_frozen:
		return

	if state == State.SINKING or state == State.IN_WATER:
		_update_bottom_from_world()
	
	if fight_mode and fish_pull_strength > 0.0:
		_update_fish_pull(delta)
	
	match state:
		State.FLYING:
			_update_flying(delta)

		State.SINKING, State.IN_WATER:
			if reeling:
				_update_reeling(delta)
			elif not fight_mode:
				_update_sinking(delta)
	
	if twitch_velocity.length_squared() > 0.001:
		global_position += twitch_velocity * delta

		twitch_velocity = twitch_velocity.move_toward(
			Vector3.ZERO,
			twitch_deceleration * delta
		)
	
	_enforce_fight_distance()
	
func _update_flying(delta: float) -> void:
	_update_air_curve(delta)
	
	velocity.y -= gravity * delta

	var previous_position := global_position
	var next_position := previous_position + velocity * delta

	if previous_position.y >= water_y and next_position.y <= water_y:
		next_position.y = water_y
		global_position = next_position

		landed.emit(global_position)

		state = State.SINKING
		return

	global_position = next_position


func _update_sinking(delta: float) -> void:
	if data == null:
		return

	var target_y := _get_sink_target_y()
	var previous_y := global_position.y

	global_position.y = move_toward(
		global_position.y,
		target_y,
		data.sink_speed * delta
	)

	if not is_equal_approx(previous_y, global_position.y):
		_emit_depth()

	if is_equal_approx(global_position.y, target_y):
		state = State.IN_WATER
	else:
		state = State.SINKING


func _get_sink_target_y() -> float:
	if data == null:
		return bottom_y

	var depth_ratio := clampf(data.sink_depth, 0.0, 1.0)

	return lerpf(
		water_y,
		bottom_y,
		depth_ratio
	)

func _update_reeling(delta: float) -> void:
	if data == null or reel_target == null:
		return

	var target_position := reel_target.global_position

	var to_target := Vector3(
		target_position.x - global_position.x,
		0.0,
		target_position.z - global_position.z
	)

	var distance := to_target.length()

	# Close enough: finish the reel immediately.
	if distance <= return_distance:
		reeling = false
		returned.emit()
		return

	var forward := to_target.normalized()
	var side := Vector3.UP.cross(forward).normalized()

	# Steering gradually disappears as the bait approaches Ryu.
	var steering_fade := clampf(distance / 2.0, 0.0, 1.0)

	var steering_strength := data.reel_steer_strength

	if fight_mode:
		var steer_authority := lerpf(
			min_fight_steer_authority,
			1.0,
			1.0 - fight_resistance
		)

		steering_strength *= steer_authority

	var reel_direction := (
		forward
		+ side * reel_steering * steering_strength * steering_fade
	).normalized()

	var reel_speed := data.reel_speed * reel_speed_multiplier
	
	if not fight_mode:
		reel_speed *= free_reel_speed_multiplier
	
	if fight_mode:
		var multiplier := lerpf(
			1.0,
			fight_reel_multiplier,
			fight_resistance
		)

		reel_speed *= multiplier

	var move_distance := reel_speed * delta

	# Never step past the target.
	if move_distance >= distance:
		global_position.x = target_position.x
		global_position.z = target_position.z

		reeling = false
		returned.emit()
		return

	global_position += reel_direction * move_distance

	if not fight_mode:
		global_position.y = move_toward(
			global_position.y,
			water_y,
			data.reel_rise_speed * delta
		)

	_emit_depth()
	
func set_data(new_data: BaitData) -> void:
	data = new_data

func set_simulation_frozen(active: bool) -> void:
	simulation_frozen = active
	
func _emit_depth() -> void:
	var current_depth := water_y - global_position.y
	var total_depth := water_y - bottom_y

	depth_changed.emit(current_depth, total_depth)

func _update_bottom_from_world() -> void:
	var ray_from := Vector3(
		global_position.x,
		water_y + 0.5,
		global_position.z
	)

	var ray_to := Vector3(
		global_position.x,
		water_y - floor_ray_depth,
		global_position.z
	)

	var query := PhysicsRayQueryParameters3D.create(
		ray_from,
		ray_to,
		floor_collision_mask
	)

	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return

	var hit_position: Vector3 = hit["position"]
	bottom_y = hit_position.y

	if global_position.y < bottom_y:
		global_position.y = bottom_y
		
func set_fight_mode(active: bool) -> void:
	fight_mode = active

	if fight_mode:
		if reel_target != null:
			var offset := global_position - reel_target.global_position
			offset.y = 0.0

			fight_max_distance = (
				offset.length()
				+ max_extra_fight_distance
			)

		if state == State.SINKING:
			state = State.IN_WATER
	else:
		fight_max_distance = 0.0

func _enforce_fight_distance() -> void:
	if not fight_mode:
		return

	if reel_target == null:
		return

	if fight_max_distance <= 0.0:
		return

	var offset := global_position - reel_target.global_position
	offset.y = 0.0

	var distance := offset.length()

	if distance <= fight_max_distance:
		return

	var clamped := (
		reel_target.global_position
		+ offset.normalized() * fight_max_distance
	)

	global_position.x = clamped.x
	global_position.z = clamped.z
	
func set_fight_resistance(value: float) -> void:
	fight_resistance = clampf(value, 0.0, 1.0)

func set_fish_pull_strength(value: float) -> void:
	fish_pull_strength = clampf(value, 0.0, 1.0)

func _update_fish_pull(delta: float) -> void:
	if reel_target == null:
		return

	var away := global_position - reel_target.global_position
	away.y = 0.0

	if away.length_squared() == 0.0:
		return

	away = away.normalized()

	var side := Vector3.UP.cross(away).normalized()

	var has_lateral := absf(fish_lateral) > 0.05
	var has_vertical := absf(fish_depth_intent) > 0.05

	var horizontal_direction := Vector3.ZERO

	# No sideways or vertical intent = surge directly away.
	if not has_lateral and not has_vertical:
		horizontal_direction = away

	# Side run = move sideways instead of constantly escaping.
	elif has_lateral and not has_vertical:
		horizontal_direction = side * fish_lateral

	# Erratic movement = sideways + a small amount away.
	elif has_lateral and has_vertical:
		horizontal_direction = (
			side * fish_lateral
			+ away * 0.15
		).normalized()

	# Dive / rise intentionally has no horizontal movement.

	if horizontal_direction.length_squared() > 0.0:
		var fish_step := (
			horizontal_direction.normalized()
			* max_fish_pull_speed
			* fish_pull_strength
			* delta
		)

		var proposed_position := global_position + fish_step

		if (
			swim_bounds != null
			and swim_bounds.has_method("constrain_fish_motion")
		):
			proposed_position = swim_bounds.constrain_fish_motion(
				global_position,
				proposed_position
			)

		global_position.x = proposed_position.x
		global_position.z = proposed_position.z

	global_position.y += (
		fish_depth_intent
		* fish_vertical_speed
		* fish_pull_strength
		* delta
	)

	global_position.y = clampf(
		global_position.y,
		bottom_y,
		water_y
	)

	_emit_depth()
			
func set_fish_lateral(value: float) -> void:
	fish_lateral = clampf(value, -1.0, 1.0)

func set_fish_depth_intent(value: float) -> void:
	fish_depth_intent = clampf(value, -1.0, 1.0)

func twitch_side(direction: float) -> void:
	if fight_mode:
		return

	if state != State.SINKING and state != State.IN_WATER:
		return

	if reel_target == null:
		return

	var toward_player := reel_target.global_position - global_position
	toward_player.y = 0.0

	if toward_player.length_squared() == 0.0:
		return

	var forward := toward_player.normalized()
	var side := Vector3.UP.cross(forward).normalized()

	twitch_velocity = (
		side
		* clampf(direction, -1.0, 1.0)
		* twitch_speed
	)

func set_reel_speed_multiplier(value: float) -> void:
	reel_speed_multiplier = maxf(value, 0.0)

func show_ripple() -> void:
	ripple_view.show_ripple()


func hide_ripple() -> void:
	ripple_view.hide_ripple()
