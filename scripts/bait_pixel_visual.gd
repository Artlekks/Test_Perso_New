extends Sprite3D

## Presentation-only pixel lure proxy.
##
## The parent Bait node remains the authoritative 3D physics object.
## This node only reads the bait's movement / reel target so the visible sprite
## can face the same way on screen. It never writes to the camera, bait physics,
## fishing state, line system, or catch logic.

@export_category("Pixel Lure")
@export var pixel_visual_enabled: bool = true

## The temporary BOF4 reference sprite points roughly 20 degrees upward from
## screen-right. This offset lets the sprite's nose align to the desired screen
## direction after rotation.
@export_range(-180.0, 180.0, 1.0)
var source_forward_angle_degrees: float = 20.0

## Discrete screen angles keep the lure reading like a sprite rather than a
## freely rotating 3D object. 16 = 22.5-degree steps.
@export_range(4, 32, 1)
var rotation_steps: int = 16

## In flight the lure points along its cast velocity. Once it is in the water,
## it points back toward the rod/reel target, matching the BOF4 visual read.
@export var flying_faces_velocity: bool = true
@export var in_water_faces_reel_target: bool = true

var _bait: Node3D = null
var _last_direction: Vector3 = Vector3.RIGHT


func _ready() -> void:
	_bait = get_parent() as Node3D
	visible = pixel_visual_enabled and texture != null


func _process(_delta: float) -> void:
	visible = pixel_visual_enabled and texture != null

	if not visible or _bait == null:
		return

	var direction: Vector3 = _get_visual_direction()
	if direction.length_squared() < 0.000001:
		return

	_last_direction = direction.normalized()
	_apply_screen_rotation(_last_direction)


func _get_visual_direction() -> Vector3:
	if _bait == null:
		return _last_direction

	if (
		flying_faces_velocity
		and _bait.has_method("is_cast_flying")
		and bool(_bait.is_cast_flying())
		and _bait.has_method("get_visual_velocity")
	):
		var flight_velocity: Vector3 = Vector3(
			_bait.get_visual_velocity()
		)
		if flight_velocity.length_squared() > 0.000001:
			return flight_velocity.normalized()

	if (
		in_water_faces_reel_target
		and _bait.has_method("get_reel_target_node")
	):
		var reel_target: Node3D = (
			_bait.get_reel_target_node()
			as Node3D
		)

		if is_instance_valid(reel_target):
			var line_direction: Vector3 = (
				reel_target.global_position
				- _bait.global_position
			)
			if line_direction.length_squared() > 0.000001:
				return line_direction.normalized()

	return _last_direction


func _apply_screen_rotation(direction: Vector3) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	if camera.is_position_behind(global_position):
		return

	var screen_origin: Vector2 = camera.unproject_position(
		global_position
	)
	var screen_tip: Vector2 = camera.unproject_position(
		global_position + direction * 0.5
	)
	var screen_direction: Vector2 = screen_tip - screen_origin

	if screen_direction.length_squared() < 0.000001:
		return

	# Convert screen Y-down into a conventional Y-up angle.
	var target_angle: float = atan2(
		-screen_direction.y,
		screen_direction.x
	)
	target_angle -= deg_to_rad(source_forward_angle_degrees)

	var step_count: int = maxi(rotation_steps, 1)
	var angle_step: float = TAU / float(step_count)
	target_angle = round(target_angle / angle_step) * angle_step

	rotation.z = target_angle
