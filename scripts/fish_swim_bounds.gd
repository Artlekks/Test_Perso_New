extends Area3D
class_name FishSwimBounds

@export_range(0.0, 10.0, 0.05)
var inner_margin: float = 0.35

@export var enabled: bool = true

@onready var bounds_shape: CollisionShape3D = $BoundsShape3D


func constrain_fish_motion(
	current_world_position: Vector3,
	proposed_world_position: Vector3
) -> Vector3:
	if not enabled:
		return proposed_world_position

	var box := _get_box_shape()

	if box == null or bounds_shape == null:
		return proposed_world_position

	var shape_transform := bounds_shape.global_transform
	var inverse_transform := shape_transform.affine_inverse()

	var current_local: Vector3 = (
		inverse_transform * current_world_position
	)

	var proposed_local: Vector3 = (
		inverse_transform * proposed_world_position
	)

	var half_size := box.size * 0.5

	var horizontal_limit_x := maxf(
		half_size.x - inner_margin,
		0.0
	)

	var horizontal_limit_z := maxf(
		half_size.z - inner_margin,
		0.0
	)

	# Once the player has reeled the fish across the shoreline boundary,
	# fish-driven movement must not pull it around on dry land.
	# Player reeling is still allowed to continue toward the player.
	if not _is_inside_horizontal(
		current_local,
		horizontal_limit_x,
		horizontal_limit_z
	):
		proposed_local.x = current_local.x
		proposed_local.z = current_local.z

		var outside_result: Vector3 = (
			shape_transform * proposed_local
		)

		outside_result.y = proposed_world_position.y
		return outside_result

	proposed_local.x = clampf(
		proposed_local.x,
		-horizontal_limit_x,
		horizontal_limit_x
	)

	proposed_local.z = clampf(
		proposed_local.z,
		-horizontal_limit_z,
		horizontal_limit_z
	)

	var result: Vector3 = shape_transform * proposed_local

	# This component owns horizontal swim limits only.
	# Water surface / bottom continue to own vertical limits.
	result.y = proposed_world_position.y

	return result


func contains_horizontal(world_position: Vector3) -> bool:
	if not enabled:
		return true

	var box := _get_box_shape()

	if box == null or bounds_shape == null:
		return true

	var local_position: Vector3 = (
		bounds_shape.global_transform.affine_inverse()
		* world_position
	)

	var half_size := box.size * 0.5

	return _is_inside_horizontal(
		local_position,
		maxf(half_size.x - inner_margin, 0.0),
		maxf(half_size.z - inner_margin, 0.0)
	)


func get_random_horizontal_point(
	world_y: float,
	rng: RandomNumberGenerator = null
) -> Vector3:
	var box := _get_box_shape()

	if box == null or bounds_shape == null:
		return Vector3(global_position.x, world_y, global_position.z)

	var half_size := box.size * 0.5
	var limit_x := maxf(half_size.x - inner_margin, 0.0)
	var limit_z := maxf(half_size.z - inner_margin, 0.0)
	var random_source := rng

	if random_source == null:
		random_source = RandomNumberGenerator.new()
		random_source.randomize()

	var local_point := Vector3(
		random_source.randf_range(-limit_x, limit_x),
		0.0,
		random_source.randf_range(-limit_z, limit_z)
	)

	var world_point := bounds_shape.global_transform * local_point
	world_point.y = world_y
	return world_point


func _is_inside_horizontal(
	local_position: Vector3,
	limit_x: float,
	limit_z: float
) -> bool:
	return (
		absf(local_position.x) <= limit_x
		and absf(local_position.z) <= limit_z
	)


func _get_box_shape() -> BoxShape3D:
	if bounds_shape == null:
		return null

	return bounds_shape.shape as BoxShape3D
