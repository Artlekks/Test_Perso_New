@tool
extends Resource
class_name NPCColliderProfile
@export var family: StringName = &"humanoid_standard"
@export var radius: float = 0.18
@export var height: float = 0.52
@export var hard_blocking: bool = true

func make_shape() -> CapsuleShape3D:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.0)
	return shape

