extends Node3D
class_name BeachFishingCritter

## Crab-style ambient critter using the user's directional sheet.
## The sheet contains eight single-frame idles plus two authored diagonal walk
## strips: NW and SW. NE/SE reuse those strips mirrored horizontally.

@export_range(0.1, 2.0, 0.05) var roam_half_width: float = 0.55
@export_range(0.1, 2.0, 0.05) var roam_half_depth: float = 0.32
@export_range(0.05, 1.0, 0.01) var move_speed: float = 0.22
@export_range(0.2, 4.0, 0.05) var idle_time_min: float = 0.65
@export_range(0.2, 4.0, 0.05) var idle_time_max: float = 1.75
@export_range(0.2, 4.0, 0.05) var walk_time_min: float = 0.55
@export_range(0.2, 4.0, 0.05) var walk_time_max: float = 1.30
@export_range(0.15, 2.0, 0.05) var idle_turn_interval: float = 0.70

@onready var animated_sprite: AnimatedSprite3D = $GroundPresentation/VisualAnchor/AnimatedSprite3D
@onready var proximity_area: Area3D = $ProximityArea
var _avoidance_cooldown: float = 0.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _home_position: Vector3 = Vector3.ZERO
var _base_y: float = 0.0
var _walking: bool = false
var _state_time_left: float = 0.0
var _turn_time_left: float = 0.0
var _walk_direction: Vector2 = Vector2(-1.0, -1.0).normalized()
var _last_facing: Vector2 = Vector2(0.0, 1.0)


func _ready() -> void:
	_rng.randomize()
	_home_position = position
	_base_y = position.y
	_start_idle()


func _physics_process(delta: float) -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return

	_state_time_left -= delta
	_avoidance_cooldown = maxf(0.0, _avoidance_cooldown - delta)
	if _avoidance_cooldown <= 0.0:
		for body in proximity_area.get_overlapping_bodies():
			if not body.is_in_group("fishing_player"):
				continue
			var away: Vector3 = global_position - body.global_position
			if get_parent() is Node3D:
				away = (get_parent() as Node3D).global_basis.inverse() * away
			var best := Vector2.ZERO
			var score := -INF
			for candidate in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
				var probe: Vector3 = position + Vector3(candidate.x, 0, candidate.y) * 0.05
				if absf(probe.x - _home_position.x) > roam_half_width or absf(probe.z - _home_position.z) > roam_half_depth:
					continue
				var value: float = candidate.dot(Vector2(away.x, away.z))
				if value > score:
					score = value
					best = candidate.normalized()
			if not best.is_zero_approx():
				_walking = true
				_walk_direction = best
				_last_facing = best
				_state_time_left = walk_time_min
				_play_walk(best)
			_avoidance_cooldown = 0.6
			break

	if _walking:
		_update_walk(delta)
		if _state_time_left <= 0.0:
			_start_idle()
		return

	_turn_time_left -= delta
	if _turn_time_left <= 0.0:
		_turn_time_left = idle_turn_interval
		# The sheet has all eight authored idle directions, so let the crab
		# occasionally look around while resting instead of wasting those frames.
		_last_facing = _random_eight_way_direction()
		_play_idle(_last_facing)

	if _state_time_left <= 0.0:
		_start_walk()


func _update_walk(delta: float) -> void:
	var step: float = maxf(move_speed, 0.0) * maxf(delta, 0.0)
	var min_x: float = _home_position.x - roam_half_width
	var max_x: float = _home_position.x + roam_half_width
	var min_z: float = _home_position.z - roam_half_depth
	var max_z: float = _home_position.z + roam_half_depth

	var desired := position + Vector3(_walk_direction.x * step, 0.0, _walk_direction.y * step)
	var bounded := Vector3(clampf(desired.x, min_x, max_x), _base_y, clampf(desired.z, min_z, max_z))
	var hit_edge := not desired.is_equal_approx(bounded)
	position = bounded
	if hit_edge:
		_start_idle()


func _start_idle() -> void:
	_walking = false
	_state_time_left = _rng.randf_range(idle_time_min, idle_time_max)
	_turn_time_left = minf(idle_turn_interval, _state_time_left)
	_play_idle(_last_facing)


func _start_walk() -> void:
	_walking = true
	_state_time_left = _rng.randf_range(walk_time_min, walk_time_max)
	_walk_direction = _choose_diagonal_direction()
	_last_facing = _walk_direction
	_play_walk(_walk_direction)


func _choose_diagonal_direction() -> Vector2:
	var x_sign: float = -1.0 if _rng.randi_range(0, 1) == 0 else 1.0
	var z_sign: float = -1.0 if _rng.randi_range(0, 1) == 0 else 1.0

	# If a random direction points straight out of the small roaming rectangle,
	# turn it inward before walking. The authored sheet only has diagonal walks,
	# so both axes always remain active.
	if position.x <= _home_position.x - roam_half_width + 0.03:
		x_sign = 1.0
	elif position.x >= _home_position.x + roam_half_width - 0.03:
		x_sign = -1.0

	if position.z <= _home_position.z - roam_half_depth + 0.03:
		z_sign = 1.0
	elif position.z >= _home_position.z + roam_half_depth - 0.03:
		z_sign = -1.0

	return Vector2(x_sign, z_sign).normalized()


func _random_eight_way_direction() -> Vector2:
	var directions: Array[Vector2] = [
		Vector2(0.0, -1.0),
		Vector2(1.0, -1.0).normalized(),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0).normalized(),
		Vector2(0.0, 1.0),
		Vector2(-1.0, 1.0).normalized(),
		Vector2(-1.0, 0.0),
		Vector2(-1.0, -1.0).normalized(),
	]
	return directions[_rng.randi_range(0, directions.size() - 1)]


func _play_idle(direction: Vector2) -> void:
	$GroundPresentation.set_local_directional_pose("idle", Vector3(direction.x, 0, direction.y))


func _play_walk(direction: Vector2) -> void:
	$GroundPresentation.set_local_directional_pose("walk", Vector3(direction.x, 0, direction.y))
