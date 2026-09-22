extends Node3D

signal landed(point: Vector3)
signal returned
signal depth_changed(current_depth: float, total_depth: float)
signal snag_risk_changed(value: float)
signal snagged(reason: StringName)

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

@export_category("Fight Micro Movement")
## Small extra left/right correction layered on top of the main fish intent.
## This affects physical bait movement only; it does not feed back into
## stamina, tension, counter-steering, or FishBehavior state.
@export_range(0.0, 0.5, 0.01)
var micro_lateral_strength: float = 0.16
## How often the fish chooses a new tiny correction target.
@export var micro_change_time_min: float = 0.28
@export var micro_change_time_max: float = 0.62
## Higher values make the tiny correction settle faster. Kept deliberately
## soft so it reads as living movement rather than jitter.
@export var micro_response_speed: float = 5.0

@export var twitch_speed: float = 1.8
@export var twitch_deceleration: float = 12.0
@export_category("Fight Distance")
@export var max_extra_fight_distance: float = 3.0

@export_category("Reel Convergence")
## Inside this horizontal distance, lateral freedom begins to fade.
@export var convergence_start_distance: float = 2.2
## Inside this distance, fish pull and player steering can fully converge,
## but only once the fish itself is calm enough.
@export var convergence_full_distance: float = 0.70

## At or above this pull strength, a fighting fish keeps full movement even
## right beside the player. Distance alone can never force convergence.
@export_range(0.0, 1.0, 0.01)
var convergence_block_pull_strength: float = 0.55

## At or below this pull strength, the normal distance-based convergence can
## fully engage. Between this and the block threshold it blends smoothly.
@export_range(0.0, 1.0, 0.01)
var convergence_full_pull_strength: float = 0.12

## A fighting fish cannot complete the final return while its current pull is
## above this value. It can be at the player's feet and still surge away.
@export_range(0.0, 1.0, 0.01)
var fight_return_pull_threshold: float = 0.12

@export_category("Free Reeling")
@export var free_reel_speed_multiplier: float = 2.5

@export_category("Manual Pull")
## One S press queues this much horizontal travel toward the player.
## Kept deliberately small so it reads as a rod jerk, not a teleport.
@export var manual_pull_step_distance: float = 0.14
## How quickly each queued pull step is played out.
@export var manual_pull_speed: float = 1.8
## Lets rapid S taps stack a few pulls without building an unlimited queue.
@export var manual_pull_max_queued_distance: float = 0.42

@export_category("Snag Risk")
@export var bottom_snag_clearance: float = 0.12
@export var snag_build_rate: float = 0.55
@export var snag_recovery_rate: float = 0.80
@export_range(0.0, 1.0, 0.01)
var snag_reel_press_impulse: float = 0.18
@export_range(0.0, 1.0, 0.01)
var snag_twitch_impulse: float = 0.24
@export var snag_threshold: float = 1.0
@export var snag_probe_radius: float = 0.12
@export_flags_3d_physics var snag_collision_mask: int = 8

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
var manual_pull_remaining: float = 0.0

# Physical-only micro movement. These values never leave bait_V2.gd.
var micro_lateral: float = 0.0
var micro_target_lateral: float = 0.0
var micro_time_until_change: float = 0.0
var air_curve_input: float = 0.0
var air_curve_angle: float = 0.0

var air_path: PackedVector3Array = PackedVector3Array()
var air_path_progress: float = 0.0
var air_path_playback_speed: float = 1.0

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

var snag_probe: Area3D = null
var snag_risk: float = 0.0
var snag_triggered: bool = false

func _ready() -> void:
	_ensure_snag_probe()


func _ensure_snag_probe() -> void:
	if is_instance_valid(snag_probe):
		return

	snag_probe = Area3D.new()
	snag_probe.name = "FishingSnagProbe"
	snag_probe.collision_layer = 0
	snag_probe.collision_mask = snag_collision_mask
	snag_probe.monitoring = true
	snag_probe.monitorable = false

	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"

	var sphere := SphereShape3D.new()
	sphere.radius = maxf(snag_probe_radius, 0.01)

	shape_node.shape = sphere
	snag_probe.add_child(shape_node)
	add_child(snag_probe)


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
	air_path = PackedVector3Array()
	air_path_progress = 0.0
	air_path_playback_speed = 1.0
	_reset_micro_movement()
	_reset_snag_state()
	manual_pull_remaining = 0.0
	simulation_frozen = false
	state = State.FLYING

	ripple_view.configure(
		self,
		water_y
	)

	ripple_view.hide_ripple()

func set_air_path(
	points: PackedVector3Array,
	playback_speed: float = 1.0
) -> void:
	air_path = points
	air_path_progress = 0.0
	air_path_playback_speed = maxf(
		playback_speed,
		0.01
	)

	if not air_path.is_empty():
		global_position = air_path[0]


func configure_air_curve(
	curve_speed_degrees: float,
	curve_limit_degrees: float
) -> void:
	air_curve_speed_degrees = maxf(
		curve_speed_degrees,
		0.0
	)
	max_air_curve_degrees = maxf(
		curve_limit_degrees,
		0.0
	)


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
	var was_reeling := reeling
	reeling = active

	if fight_mode:
		return

	if reeling and not was_reeling:
		_apply_snag_input_impulse(snag_reel_press_impulse)

	if snag_triggered:
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

	if (
		(state == State.SINKING or state == State.IN_WATER)
		and not fight_mode
	):
		_update_snag_risk(delta)

		if snag_triggered:
			return
	
	if fight_mode and fish_pull_strength > 0.0:
		_update_micro_movement(delta)
		_update_fish_pull(delta)

	# S-pull is a short, discrete retrieve impulse layered on top of the
	# normal water simulation. It is intentionally separate from K reeling:
	# repeated taps can therefore retrieve in visible little increments.
	if manual_pull_remaining > 0.0:
		if _update_manual_pull(delta):
			return
	
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
	if air_path.size() >= 2:
		_update_flying_path(delta)
		return

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


func _update_flying_path(delta: float) -> void:
	if air_path.size() < 2:
		air_path = PackedVector3Array()
		air_path_progress = 0.0
		return

	var last_index := air_path.size() - 1
	var previous_position := global_position

	# Prediction points are authored at the project's physics tick rate.
	# Advancing fractionally lets us slow the throw without changing the
	# trajectory itself or introducing visible frame stepping.
	air_path_progress += (
		delta
		* float(Engine.physics_ticks_per_second)
		* air_path_playback_speed
	)

	if air_path_progress >= float(last_index):
		global_position = air_path[last_index]

		if delta > 0.0:
			velocity = (
				(global_position - previous_position)
				/ delta
			)

		global_position.y = water_y
		air_path = PackedVector3Array()
		air_path_progress = 0.0

		landed.emit(global_position)
		state = State.SINKING
		return

	var lower_index := int(
		floor(air_path_progress)
	)
	var upper_index := mini(
		lower_index + 1,
		last_index
	)
	var fraction := (
		air_path_progress
		- float(lower_index)
	)

	var next_position := air_path[
		lower_index
	].lerp(
		air_path[upper_index],
		fraction
	)

	if delta > 0.0:
		velocity = (
			(next_position - previous_position)
			/ delta
		)

	global_position = next_position


func _reset_snag_state() -> void:
	snag_risk = 0.0
	snag_triggered = false
	snag_risk_changed.emit(0.0)


func _is_bottom_snag_hazard() -> bool:
	if state != State.SINKING and state != State.IN_WATER:
		return false

	var bottom_gap := global_position.y - bottom_y
	return bottom_gap <= maxf(bottom_snag_clearance, 0.0)


func _get_obstacle_snag_multiplier() -> float:
	if not is_instance_valid(snag_probe):
		return 0.0

	var strongest := 0.0

	for area in snag_probe.get_overlapping_areas():
		if not area.is_in_group("fishing_snag"):
			continue

		var multiplier := 1.0

		if area.has_method("get_snag_risk_multiplier"):
			multiplier = float(
				area.get_snag_risk_multiplier()
			)

		strongest = maxf(
			strongest,
			maxf(multiplier, 0.0)
		)

	return strongest


func _get_current_snag_multiplier() -> float:
	var multiplier := 0.0

	if _is_bottom_snag_hazard():
		var bottom_multiplier := 1.0

		if (
			data != null
			and data.has_method(
				"get_bottom_snag_multiplier"
			)
		):
			bottom_multiplier *= float(
				data.get_bottom_snag_multiplier()
			)

		multiplier = maxf(
			multiplier,
			bottom_multiplier
		)

	var obstacle_multiplier := (
		_get_obstacle_snag_multiplier()
	)

	if (
		obstacle_multiplier > 0.0
		and data != null
		and data.has_method(
			"get_obstacle_snag_multiplier"
		)
	):
		obstacle_multiplier *= float(
			data.get_obstacle_snag_multiplier()
		)

	return maxf(
		multiplier,
		obstacle_multiplier
	)


func _get_current_snag_reason() -> StringName:
	if _get_obstacle_snag_multiplier() > 0.0:
		return &"obstacle"

	if _is_bottom_snag_hazard():
		return &"bottom"

	return &"unknown"


func _change_snag_risk(amount: float) -> void:
	if snag_triggered:
		return

	var threshold := maxf(snag_threshold, 0.01)
	var previous := snag_risk
	snag_risk = clampf(
		snag_risk + amount,
		0.0,
		threshold
	)

	if not is_equal_approx(previous, snag_risk):
		snag_risk_changed.emit(snag_risk / threshold)

	if snag_risk >= threshold:
		_trigger_snag_miss(
			_get_current_snag_reason()
		)


func _apply_snag_input_impulse(amount: float) -> void:
	if fight_mode or snag_triggered:
		return

	var hazard_multiplier := (
		_get_current_snag_multiplier()
	)

	if hazard_multiplier <= 0.0:
		return

	_change_snag_risk(
		maxf(amount, 0.0)
		* hazard_multiplier
	)


func _update_snag_risk(delta: float) -> void:
	if snag_triggered:
		return

	var hazard_multiplier := (
		_get_current_snag_multiplier()
	)

	if hazard_multiplier > 0.0 and reeling:
		_change_snag_risk(
			maxf(snag_build_rate, 0.0)
			* hazard_multiplier
			* delta
		)
		return

	if snag_risk > 0.0:
		_change_snag_risk(
			-maxf(snag_recovery_rate, 0.0)
			* delta
		)


func _trigger_snag_miss(reason: StringName) -> void:
	if snag_triggered:
		return

	snag_triggered = true
	reeling = false
	reel_steering = 0.0
	twitch_velocity = Vector3.ZERO
	_reset_micro_movement()
	simulation_frozen = true
	hide_ripple()

	snagged.emit(reason)

	# Reuse the existing return cleanup path. This ends the attempt and
	# returns fishing to AIM without touching the cast/input state machine.
	returned.emit()


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

	# Being close is not enough during a fight. A fish that is still actively
	# pulling can remain right beside the player and surge away again.
	if distance <= return_distance:
		if fight_mode and not _can_finish_fight_return():
			return

		global_position.x = target_position.x
		global_position.z = target_position.z
		reel_steering = 0.0
		fish_lateral = 0.0
		_reset_micro_movement()
		reeling = false
		returned.emit()
		return

	var forward := to_target.normalized()
	var side := Vector3.UP.cross(forward).normalized()

	# Near the player, lateral authority progressively disappears. Far away,
	# steering is unchanged; close in, the reel direction becomes purely
	# toward the target.
	var convergence := _get_reel_convergence(distance)
	var steering_fade := 1.0 - convergence

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
		if fight_mode and not _can_finish_fight_return():
			# Hold the fish at the edge of the final return radius instead of
			# declaring victory. Its next active pull can still move it away.
			var hold_distance := minf(
				return_distance,
				distance
			)

			if distance > 0.0001:
				global_position += (
					forward
					* maxf(distance - hold_distance, 0.0)
				)

			_emit_depth()
			return

		global_position.x = target_position.x
		global_position.z = target_position.z
		reel_steering = 0.0
		fish_lateral = 0.0
		_reset_micro_movement()

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
	
func queue_manual_pull() -> void:
	# Manual rod pulls are currently a free-lure interaction only. Fight
	# movement remains owned by the existing reel/resistance simulation so
	# this input cannot bypass fish balance.
	if fight_mode:
		return

	if state != State.SINKING and state != State.IN_WATER:
		return

	if reel_target == null:
		return

	_apply_snag_input_impulse(snag_reel_press_impulse)

	if snag_triggered:
		return

	manual_pull_remaining = minf(
		manual_pull_remaining + maxf(manual_pull_step_distance, 0.0),
		maxf(manual_pull_max_queued_distance, 0.0)
	)


func _update_manual_pull(delta: float) -> bool:
	if fight_mode:
		manual_pull_remaining = 0.0
		return false

	if reel_target == null:
		manual_pull_remaining = 0.0
		return false

	if state != State.SINKING and state != State.IN_WATER:
		manual_pull_remaining = 0.0
		return false

	var target_position := reel_target.global_position
	var to_target := Vector3(
		target_position.x - global_position.x,
		0.0,
		target_position.z - global_position.z
	)
	var distance := to_target.length()

	if distance <= return_distance:
		global_position.x = target_position.x
		global_position.z = target_position.z
		manual_pull_remaining = 0.0
		reeling = false
		returned.emit()
		return true

	if distance <= 0.0001:
		manual_pull_remaining = 0.0
		return false

	var available_distance := maxf(
		distance - return_distance,
		0.0
	)
	var move_distance := minf(
		minf(
			maxf(manual_pull_speed, 0.0) * delta,
			manual_pull_remaining
		),
		available_distance
	)

	if move_distance <= 0.0:
		manual_pull_remaining = 0.0
		return false

	global_position += to_target.normalized() * move_distance
	manual_pull_remaining = maxf(
		manual_pull_remaining - move_distance,
		0.0
	)

	_emit_depth()

	# A manual pull can finish the retrieve exactly like normal K reeling.
	var remaining_flat := Vector2(
		target_position.x - global_position.x,
		target_position.z - global_position.z
	).length()

	if remaining_flat <= return_distance:
		global_position.x = target_position.x
		global_position.z = target_position.z
		manual_pull_remaining = 0.0
		reeling = false
		returned.emit()
		return true

	return false


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
		
func _get_fight_calm_factor() -> float:
	if not fight_mode:
		return 1.0

	var full_pull := clampf(
		convergence_full_pull_strength,
		0.0,
		1.0
	)

	var block_pull := clampf(
		convergence_block_pull_strength,
		full_pull + 0.01,
		1.0
	)

	if fish_pull_strength <= full_pull:
		return 1.0

	if fish_pull_strength >= block_pull:
		return 0.0

	var t := inverse_lerp(
		block_pull,
		full_pull,
		fish_pull_strength
	)

	# Smoothstep: active thrashing keeps freedom, then convergence fades in
	# naturally as the current pull dies down.
	return t * t * (3.0 - 2.0 * t)


func _can_finish_fight_return() -> bool:
	if not fight_mode:
		return true

	return (
		fish_pull_strength
		<= clampf(
			fight_return_pull_threshold,
			0.0,
			1.0
		)
	)


func _get_reel_convergence(distance: float) -> float:
	var start_distance := maxf(
		convergence_start_distance,
		return_distance + 0.01
	)

	var full_distance := clampf(
		convergence_full_distance,
		return_distance,
		start_distance - 0.01
	)

	var distance_convergence := 0.0

	if distance <= full_distance:
		distance_convergence = 1.0
	elif distance < start_distance:
		var t := inverse_lerp(
			start_distance,
			full_distance,
			distance
		)

		distance_convergence = (
			t * t * (3.0 - 2.0 * t)
		)

	# The old pass used distance alone. Now distance only says how much
	# convergence is AVAILABLE; the fish's current pull decides how much is
	# actually allowed. A hard-thrashing fish therefore keeps full freedom
	# even very close to the player.
	return (
		distance_convergence
		* _get_fight_calm_factor()
	)


func set_fight_mode(active: bool) -> void:
	fight_mode = active
	manual_pull_remaining = 0.0
	_reset_micro_movement()

	if fight_mode:
		_choose_micro_target()
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

func _reset_micro_movement() -> void:
	micro_lateral = 0.0
	micro_target_lateral = 0.0
	micro_time_until_change = 0.0


func _choose_micro_target() -> void:
	# A restrained random target gives the fish tiny corrections without
	# producing an obvious repeating sine-wave pattern.
	micro_target_lateral = randf_range(-1.0, 1.0)
	micro_time_until_change = randf_range(
		maxf(micro_change_time_min, 0.05),
		maxf(
			micro_change_time_max,
			micro_change_time_min + 0.05
		)
	)


func _update_micro_movement(delta: float) -> void:
	micro_time_until_change -= delta

	if micro_time_until_change <= 0.0:
		_choose_micro_target()

	# Frame-rate-independent smoothing. The target changes irregularly, but
	# the physical response glides toward it instead of snapping.
	var response := 1.0 - exp(
		-maxf(micro_response_speed, 0.0) * delta
	)

	micro_lateral = lerpf(
		micro_lateral,
		micro_target_lateral,
		response
	)


func _update_fish_pull(delta: float) -> void:
	if reel_target == null:
		return

	var away := global_position - reel_target.global_position
	away.y = 0.0

	var distance := away.length()

	if distance <= 0.0001:
		return

	var convergence := _get_reel_convergence(distance)
	var lateral_freedom := 1.0 - convergence

	away /= distance

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

	# Dive / rise intentionally has no primary horizontal movement.

	# Add only a small physical correction. Because the final movement is
	# already multiplied by fish_pull_strength below, exhausted/spent fish
	# naturally receive much less micro movement than resisting fish.
	var micro_side_amount := (
		micro_lateral
		* micro_lateral_strength
	)

	if absf(micro_side_amount) > 0.001:
		horizontal_direction += side * micro_side_amount

	if horizontal_direction.length_squared() > 0.0:
		var fish_step := (
			horizontal_direction.normalized()
			* max_fish_pull_speed
			* fish_pull_strength
			* lateral_freedom
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

	_apply_snag_input_impulse(
		snag_twitch_impulse
	)

	if snag_triggered:
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
