extends CharacterBody3D

@export var move_speed: float = 3.5
@export var camera_reference: Node3D
@export var movement_enabled: bool = true

@onready var sprite_director: Node = $SpriteDirector

@export_category("Fishing Disturbance")
@export_range(1.0, 20.0, 0.5)
var fishing_disturbance_response: float = 8.0

const DIRS := ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]

var last_dir: String = "S"
var _fishing_disturbance: float = 0.0


func _ready() -> void:
	add_to_group("fishing_player")


func _physics_process(delta: float) -> void:
	# Movement is disabled during Fishing,
	# but Ryu still needs to visually react to camera rotation.
	if not movement_enabled:
		velocity = Vector3.ZERO

		if sprite_director.is_locomotion_animation():
			_update_facing_from_world(global_transform.basis.z)
			_play_animation("Idle", last_dir)

		move_and_slide()
		_update_fishing_disturbance(delta)
		return

	var input_vector := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	# Standing still
	if input_vector.length_squared() == 0.0:
		velocity.x = 0.0
		velocity.z = 0.0

		_update_facing_from_world(global_transform.basis.z)
		_play_animation("Idle", last_dir)

		move_and_slide()
		_update_fishing_disturbance(delta)
		return

	# Camera-relative movement
	var camera_basis := Basis()

	if camera_reference != null:
		camera_basis = camera_reference.global_transform.basis

	var camera_forward := -camera_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()

	var camera_right := camera_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()

	var move_direction := (
		camera_right * input_vector.x
		+ camera_forward * -input_vector.y
	).normalized()

	# Snap physical movement to 8 directions
	var yaw := atan2(move_direction.x, move_direction.z)
	var step := PI / 4.0

	yaw = round(yaw / step) * step

	move_direction.x = sin(yaw)
	move_direction.z = cos(yaw)

	rotation.y = yaw


	# Choose sprite according to actual camera angle
	_update_facing_from_world(move_direction)

	velocity.x = move_direction.x * move_speed
	velocity.z = move_direction.z * move_speed

	_play_animation("Walk", last_dir)

	move_and_slide()
	_update_fishing_disturbance(delta)


func _update_fishing_disturbance(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var target := clampf(
		horizontal_speed / maxf(move_speed, 0.01),
		0.0,
		1.0
	)
	var response := clampf(
		1.0 - exp(-fishing_disturbance_response * maxf(delta, 0.0)),
		0.0,
		1.0
	)
	_fishing_disturbance = lerpf(
		_fishing_disturbance,
		target,
		response
	)


func get_fishing_disturbance_strength() -> float:
	return clampf(_fishing_disturbance, 0.0, 1.0)


func get_fishing_disturbance_snapshot() -> Dictionary:
	return {
		"strength": get_fishing_disturbance_strength(),
		"moving": get_fishing_disturbance_strength() > 0.08,
		"position": global_position,
	}


func _update_facing_from_world(world_direction: Vector3) -> void:
	if camera_reference == null:
		return

	var camera_basis := camera_reference.global_transform.basis

	var camera_right := camera_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()

	var camera_down := camera_basis.z
	camera_down.y = 0.0
	camera_down = camera_down.normalized()

	var screen_x := camera_right.dot(world_direction)
	var screen_y := camera_down.dot(world_direction)

	var step := PI / 4.0
	var screen_angle := atan2(screen_x, screen_y)

	screen_angle = round(screen_angle / step) * step

	var index := wrapi(
		int(round(screen_angle / step)),
		0,
		DIRS.size()
	)

	last_dir = DIRS[index]

func _play_animation(base_name: String, direction: String) -> void:
	sprite_director.play_directional(base_name, direction)
	
func restore_exploration_idle() -> void:
	_update_facing_from_world(global_transform.basis.z)
	_play_animation("Idle", last_dir)
