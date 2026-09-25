extends Node

signal aim_changed(world_direction: Vector3)

@export var turn_speed_degrees: float = 60.0
@export var max_aim_angle_degrees: float = 60.0

var active: bool = false

var center_yaw: float = 0.0
var aim_offset: float = 0.0


func _process(delta: float) -> void:
	if not active:
		return

	var input := -Input.get_axis("ds_left", "ds_right")

	if is_zero_approx(input):
		return

	aim_offset += deg_to_rad(turn_speed_degrees) * input * delta

	var max_angle := deg_to_rad(max_aim_angle_degrees)

	aim_offset = clamp(
		aim_offset,
		-max_angle,
		max_angle
	)

	_emit_aim()


func start(initial_direction: Vector3) -> void:
	center_yaw = atan2(
		initial_direction.x,
		initial_direction.z
	)

	aim_offset = 0.0
	active = true

	_emit_aim()


func stop() -> void:
	active = false


func _emit_aim() -> void:
	var aim_yaw := center_yaw + aim_offset

	var direction := Vector3(
		sin(aim_yaw),
		0.0,
		cos(aim_yaw)
	)

	aim_changed.emit(direction)

func resume() -> void:
	active = true
	_emit_aim()
	
func get_direction() -> Vector3:
	var aim_yaw := center_yaw + aim_offset

	return Vector3(
		sin(aim_yaw),
		0.0,
		cos(aim_yaw)
	).normalized()
