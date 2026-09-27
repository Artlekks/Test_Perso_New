extends StaticBody3D
class_name FishingShoreBoundary

## Absolute land-side limit for a hooked fish/lure during retrieval.
##
## FishSwimBounds owns normal fish roaming. This component owns a different
## rule: once a fish is hooked, player-driven retrieval may leave the roaming
## volume as it approaches shore, but it must never cross onto dry land.
##
## The box's local Z axis is treated as the shoreline normal. The plane is
## intentionally infinite along local X so a fish cannot slip around the end
## of the gameplay blocker when running hard left/right.
@export_enum("Negative Local Z:-1", "Positive Local Z:1")
var water_side_sign: int = -1

## Tiny local-space gap on the water side so the fish visual does not sit
## exactly inside the collision plane. This is local to the CollisionShape3D,
## so parent scaling is respected automatically.
@export_range(0.0, 0.25, 0.005)
var water_clearance: float = 0.01


func constrain_water_motion(
	_current_world_position: Vector3,
	proposed_world_position: Vector3
) -> Vector3:
	var shape_node := _get_box_collision_shape()

	if shape_node == null:
		return proposed_world_position

	var box := shape_node.shape as BoxShape3D

	if box == null:
		return proposed_world_position

	var shape_transform := shape_node.global_transform
	var local_position: Vector3 = (
		shape_transform.affine_inverse()
		* proposed_world_position
	)

	var water_sign := -1 if water_side_sign < 0 else 1
	var water_limit := (
		box.size.z * 0.5
		+ maxf(water_clearance, 0.0)
	)

	if water_sign < 0:
		local_position.z = minf(
			local_position.z,
			-water_limit
		)
	else:
		local_position.z = maxf(
			local_position.z,
			water_limit
		)

	var result: Vector3 = shape_transform * local_position

	# This component owns the horizontal shore plane only. Bait depth remains
	# owned by the water/bottom simulation.
	result.y = proposed_world_position.y
	return result


func get_water_side_projection(
	world_position: Vector3
) -> Vector3:
	return constrain_water_motion(
		world_position,
		world_position
	)


func _get_box_collision_shape() -> CollisionShape3D:
	var shape_node := get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D

	if shape_node == null:
		return null

	if not (shape_node.shape is BoxShape3D):
		return null

	return shape_node
