extends Node3D


@onready var ripple_sprite: AnimatedSprite3D = $RippleSprite

@export var surface_offset: float = 0.02


var follow_target: Node3D = null
var surface_y: float = 0.0
var active: bool = false


func _ready() -> void:
	top_level = true
	visible = false
	set_process(false)


func configure(
	target: Node3D,
	water_surface_y: float
) -> void:
	follow_target = target
	surface_y = water_surface_y

	_update_position()


func show_ripple() -> void:
	if not is_instance_valid(follow_target):
		return

	active = true
	visible = true
	set_process(true)

	_update_position()
	ripple_sprite.play(&"Ripple")


func hide_ripple() -> void:
	active = false
	visible = false
	set_process(false)

	ripple_sprite.stop()


func _process(_delta: float) -> void:
	if not active:
		return

	if not is_instance_valid(follow_target):
		hide_ripple()
		return

	_update_position()


func _update_position() -> void:
	if not is_instance_valid(follow_target):
		return

	var target_position: Vector3 = follow_target.global_position
	var visual_surface_y: float = surface_y + surface_offset
	var camera: Camera3D = get_viewport().get_camera_3d()

	# The ripple is a SURFACE effect, but the lure can be metres underwater.
	# Matching X/Z directly creates a large perspective offset on screen. Project
	# the lure head's screen position back onto the water plane instead, exactly
	# like the fight splash/fish-shadow presentation anchors.
	if camera == null:
		global_position = Vector3(
			target_position.x,
			visual_surface_y,
			target_position.z
		)
		return

	var screen_position: Vector2 = camera.unproject_position(target_position)
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)

	if absf(ray_direction.y) <= 0.00001:
		global_position = Vector3(
			target_position.x,
			visual_surface_y,
			target_position.z
		)
		return

	var distance_along_ray: float = (visual_surface_y - ray_origin.y) / ray_direction.y

	if distance_along_ray < 0.0:
		global_position = Vector3(
			target_position.x,
			visual_surface_y,
			target_position.z
		)
		return

	var projected: Vector3 = ray_origin + ray_direction * distance_along_ray
	projected.y = visual_surface_y
	global_position = projected
