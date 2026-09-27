extends Node3D

## Articulated pixel presentation for the lure.
##
## IMPORTANT ARCHITECTURE:
## - Parent Bait still owns every real 3D position/physics/reel/fight value.
## - Camera is READ ONLY. This script never changes a camera transform.
## - Fishing controller is not referenced.
## - These Sprite3D pieces are presentation only.
##
## This preserves the previous three-piece lure behavior:
## head responds fastest, middle follows, tail lags behind.

@onready var segment_01: Node3D = $Segment01
@onready var segment_02: Node3D = $Segment02
@onready var segment_03: Node3D = $Segment03

@onready var head_sprite: Sprite3D = $Segment01/Sprite
@onready var middle_sprite: Sprite3D = $Segment02/Sprite
@onready var tail_sprite: Sprite3D = $Segment03/Sprite

@export_category("Directional Response")
@export var motion_threshold: float = 0.015

## Head reacts fastest; tail retains the old delayed articulated feel.
@export var head_turn_speed: float = 14.0
@export var middle_turn_speed: float = 7.5
@export var tail_turn_speed: float = 4.5

## Moving lure still receives a little line influence, keeping it attached to
## Ryu rather than reading like an independent projectile.
@export_range(0.0, 0.75, 0.05)
var line_alignment_weight: float = 0.20

@export_category("Pixel Chain")
## Screen-space piece lengths. The sprite images themselves are 8/7/6 pixels.
@export_range(3.0, 16.0, 0.5)
var head_length_px: float = 8.0
@export_range(3.0, 16.0, 0.5)
var middle_length_px: float = 7.0
@export_range(3.0, 16.0, 0.5)
var tail_length_px: float = 6.0
@export_range(-2.0, 4.0, 0.25)
var segment_gap_px: float = -1.0

## Set to 0 for fully smooth angular response. A small number such as 32 keeps
## a subtle sprite-like stepping without destroying articulation.
@export_range(0, 64, 1)
var rotation_steps: int = 32

@export_category("Surface Attitude")
@export_range(0.01, 1.0, 0.01)
var surface_flatten_depth: float = 0.15
@export_range(0.0, 0.75, 0.05)
var surface_vertical_influence: float = 0.10

@export_category("Underwater Attitude")
@export_range(0.0, 45.0, 1.0)
var max_underwater_pitch_degrees: float = 18.0

@export_category("Depth Readability")
@export_range(0.25, 8.0, 0.05)
var full_depth_visual_fade_distance: float = 2.35
@export_range(0.25, 2.5, 0.05)
var depth_visual_curve_power: float = 0.62
@export_range(0.0, 0.95, 0.01)
var deep_darkening_amount: float = 0.68
@export_range(0.10, 1.0, 0.01)
var deep_alpha_multiplier: float = 0.52

var _bait: Node3D = null
var _previous_world_position: Vector3 = Vector3.ZERO

var _head_direction: Vector3 = Vector3.FORWARD
var _middle_direction: Vector3 = Vector3.FORWARD
var _tail_direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	_bait = get_parent() as Node3D

	if _bait == null:
		set_physics_process(false)
		return

	_previous_world_position = _bait.global_position

	var initial_direction: Vector3 = _get_line_direction()

	if initial_direction.length_squared() < 0.0001:
		initial_direction = Vector3.FORWARD

	initial_direction = _apply_surface_attitude(
		initial_direction,
		_bait.global_position
	)
	initial_direction = _limit_vertical_pitch(initial_direction)

	_head_direction = initial_direction.normalized()
	_middle_direction = _head_direction
	_tail_direction = _head_direction

	_place_pixel_chain()
	_update_depth_readability()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_bait):
		return

	var current_world_position: Vector3 = _bait.global_position
	var world_motion: Vector3 = (
		current_world_position
		- _previous_world_position
	)
	_previous_world_position = current_world_position

	var movement_speed: float = (
		world_motion.length()
		/ maxf(delta, 0.0001)
	)

	var desired_direction: Vector3 = Vector3.ZERO
	var line_direction: Vector3 = _get_line_direction()
	var is_flying: bool = _is_bait_cast_flying()

	if is_flying:
		# Throw: nose follows the actual cast velocity exactly as the old visual.
		var flight_velocity: Vector3 = _get_bait_visual_velocity()

		if flight_velocity.length_squared() > 0.0001:
			desired_direction = flight_velocity.normalized()
		elif movement_speed >= motion_threshold:
			desired_direction = world_motion.normalized()
		else:
			desired_direction = _head_direction

	elif movement_speed >= motion_threshold:
		# Reeling/fight: actual motion leads, fishing line bends the nose back
		# toward Ryu. This restores the old "head turns toward character" feel.
		desired_direction = world_motion.normalized()

		if line_direction.length_squared() > 0.0001:
			desired_direction = (
				desired_direction * (1.0 - line_alignment_weight)
				+ line_direction * line_alignment_weight
			).normalized()

	elif line_direction.length_squared() > 0.0001:
		# When barely moving, point toward the rod/player instead of freezing in
		# one texture orientation.
		desired_direction = line_direction

	else:
		desired_direction = _head_direction

	if desired_direction.length_squared() < 0.0001:
		return

	desired_direction = _apply_surface_attitude(
		desired_direction,
		current_world_position
	)
	desired_direction = _limit_vertical_pitch(desired_direction)

	_head_direction = _follow_direction(
		_head_direction,
		desired_direction,
		head_turn_speed,
		delta
	)

	_middle_direction = _follow_direction(
		_middle_direction,
		_head_direction,
		middle_turn_speed,
		delta
	)

	_tail_direction = _follow_direction(
		_tail_direction,
		_middle_direction,
		tail_turn_speed,
		delta
	)

	_place_pixel_chain()
	_update_depth_readability()


func _place_pixel_chain() -> void:
	if not is_instance_valid(_bait):
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	if camera.is_position_behind(_bait.global_position):
		return

	var front_screen: Vector2 = camera.unproject_position(
		_bait.global_position
	)

	var camera_local_position: Vector3 = (
		camera.global_transform.affine_inverse()
		* _bait.global_position
	)
	var depth: float = maxf(-camera_local_position.z, 0.01)

	front_screen = _place_pixel_segment(
		segment_01,
		head_sprite,
		front_screen,
		_head_direction,
		head_length_px,
		camera,
		depth
	)

	front_screen = _place_pixel_segment(
		segment_02,
		middle_sprite,
		front_screen,
		_middle_direction,
		middle_length_px,
		camera,
		depth
	)

	_place_pixel_segment(
		segment_03,
		tail_sprite,
		front_screen,
		_tail_direction,
		tail_length_px,
		camera,
		depth
	)


func _place_pixel_segment(
	segment: Node3D,
	sprite: Sprite3D,
	front_joint_screen: Vector2,
	world_direction: Vector3,
	length_px: float,
	camera: Camera3D,
	depth: float
) -> Vector2:
	if (
		not is_instance_valid(segment)
		or not is_instance_valid(sprite)
		or world_direction.length_squared() < 0.0001
	):
		return front_joint_screen

	var direction_screen: Vector2 = _project_direction_to_screen(
		camera,
		world_direction
	)

	if direction_screen.length_squared() < 0.0001:
		return front_joint_screen

	direction_screen = direction_screen.normalized()

	var center_screen: Vector2 = (
		front_joint_screen
		- direction_screen * (length_px * 0.5)
	)

	# Segment transform is written in WORLD space with identity basis. This
	# prevents parent Bait scaling/rotation from turning the pixel cards into 3D.
	var center_world: Vector3 = camera.project_position(
		center_screen,
		depth
	)
	segment.global_transform = Transform3D(
		Basis.IDENTITY,
		center_world
	)

	var target_angle: float = atan2(
		-direction_screen.y,
		direction_screen.x
	)

	if rotation_steps > 0:
		var angle_step: float = TAU / float(rotation_steps)
		target_angle = round(target_angle / angle_step) * angle_step

	sprite.rotation = Vector3(
		0.0,
		0.0,
		target_angle
	)

	return (
		center_screen
		- direction_screen
		* (length_px * 0.5 + segment_gap_px)
	)


func _project_direction_to_screen(
	camera: Camera3D,
	world_direction: Vector3
) -> Vector2:
	var origin_world: Vector3 = _bait.global_position
	var tip_world: Vector3 = (
		origin_world
		+ world_direction.normalized() * 0.5
	)

	var origin_screen: Vector2 = camera.unproject_position(
		origin_world
	)
	var tip_screen: Vector2 = camera.unproject_position(
		tip_world
	)

	return tip_screen - origin_screen


func _follow_direction(
	current: Vector3,
	target_direction: Vector3,
	speed: float,
	delta: float
) -> Vector3:
	if target_direction.length_squared() < 0.0001:
		return current

	if current.length_squared() < 0.0001:
		return target_direction.normalized()

	var follow_weight: float = clampf(
		1.0 - exp(-speed * delta),
		0.0,
		1.0
	)

	return current.slerp(
		target_direction.normalized(),
		follow_weight
	).normalized()


func _apply_surface_attitude(
	direction: Vector3,
	world_position: Vector3
) -> Vector3:
	if (
		_bait == null
		or not _bait.has_method("get_water_surface_y")
	):
		return direction.normalized()

	var water_y: float = float(
		_bait.get_water_surface_y()
	)

	var depth_below_surface: float = maxf(
		water_y - world_position.y,
		0.0
	)

	var depth_blend: float = clampf(
		depth_below_surface
		/ maxf(surface_flatten_depth, 0.001),
		0.0,
		1.0
	)

	if depth_blend >= 1.0:
		return direction.normalized()

	var horizontal: Vector3 = Vector3(
		direction.x,
		0.0,
		direction.z
	)

	if horizontal.length_squared() < 0.0001:
		var line_direction: Vector3 = _get_line_direction()
		horizontal = Vector3(
			line_direction.x,
			0.0,
			line_direction.z
		)

	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3(
			_head_direction.x,
			0.0,
			_head_direction.z
		)

	if horizontal.length_squared() < 0.0001:
		return direction.normalized()

	horizontal = horizontal.normalized()

	var surface_direction: Vector3 = Vector3(
		horizontal.x,
		direction.y * surface_vertical_influence,
		horizontal.z
	).normalized()

	return surface_direction.slerp(
		direction.normalized(),
		depth_blend
	).normalized()


func _limit_vertical_pitch(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.0001:
		return direction

	var normalized: Vector3 = direction.normalized()
	var horizontal: Vector3 = Vector3(
		normalized.x,
		0.0,
		normalized.z
	)

	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3(
			_head_direction.x,
			0.0,
			_head_direction.z
		)

	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3.FORWARD

	horizontal = horizontal.normalized()

	var max_vertical: float = tan(
		deg_to_rad(max_underwater_pitch_degrees)
	)

	var limited_y: float = clampf(
		normalized.y,
		-max_vertical,
		max_vertical
	)

	return Vector3(
		horizontal.x,
		limited_y,
		horizontal.z
	).normalized()


func _get_line_direction() -> Vector3:
	if _bait == null:
		return Vector3.ZERO

	if not _bait.has_method("get_reel_target_node"):
		return Vector3.ZERO

	var reel_target: Node3D = (
		_bait.get_reel_target_node()
		as Node3D
	)

	if not is_instance_valid(reel_target):
		return Vector3.ZERO

	var direction: Vector3 = (
		reel_target.global_position
		- _bait.global_position
	)

	if direction.length_squared() < 0.0001:
		return Vector3.ZERO

	return direction.normalized()


func _is_bait_cast_flying() -> bool:
	if (
		_bait == null
		or not _bait.has_method("is_cast_flying")
	):
		return false

	return bool(_bait.is_cast_flying())


func _get_bait_visual_velocity() -> Vector3:
	if (
		_bait == null
		or not _bait.has_method("get_visual_velocity")
	):
		return Vector3.ZERO

	return Vector3(
		_bait.get_visual_velocity()
	)


func _update_depth_readability() -> void:
	if not is_instance_valid(_bait):
		return

	var base_color: Color = _get_lure_visual_tint()
	var color: Color = base_color

	if _bait.has_method("get_water_surface_y"):
		var water_surface_y: float = float(
			_bait.get_water_surface_y()
		)

		var depth_below_surface: float = maxf(
			water_surface_y - _bait.global_position.y,
			0.0
		)

		var normalized_depth: float = clampf(
			depth_below_surface
			/ maxf(full_depth_visual_fade_distance, 0.001),
			0.0,
			1.0
		)

		var depth_blend: float = pow(
			normalized_depth,
			maxf(depth_visual_curve_power, 0.01)
		)

		var darkness: float = 1.0 - deep_darkening_amount
		var deep_color: Color = Color(
			base_color.r * darkness,
			base_color.g * darkness,
			base_color.b * darkness,
			base_color.a * deep_alpha_multiplier
		)

		color = base_color.lerp(
			deep_color,
			depth_blend
		)

	head_sprite.modulate = color
	middle_sprite.modulate = color
	tail_sprite.modulate = color


func _get_lure_visual_tint() -> Color:
	if not is_instance_valid(_bait):
		return Color.WHITE

	# BaitData is already the single source of truth on the parent Bait node.
	# Presentation reads that resource directly instead of maintaining another
	# lure-family lookup table in this controller.
	var bait_data: BaitData = _bait.get("data") as BaitData

	if bait_data == null:
		return Color.WHITE

	return bait_data.visual_tint
