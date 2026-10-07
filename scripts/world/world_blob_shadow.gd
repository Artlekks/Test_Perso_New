@tool
extends MeshInstance3D
class_name WorldBlobShadow

## Place under ActorRoot/ShadowAnchor, never under the animated sprite.
## Width/depth are world units; actor scale, facing and billboarding are ignored.
@export_range(0.01, 4.0, 0.01) var width: float = 0.26:
	set(value):
		width = maxf(value, 0.01)
		_apply_style()
@export_range(0.01, 4.0, 0.01) var depth: float = 0.30:
	set(value):
		depth = maxf(value, 0.01)
		_apply_style()
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.65:
	set(value):
		opacity = clampf(value, 0.0, 1.0)
		_apply_style()
@export_range(0.001, 0.05, 0.001) var ground_offset: float = 0.006:
	set(value):
		ground_offset = maxf(value, 0.001)
		update_ground_transform()

## Optional horizontal ground plane. Without one, use the physical anchor's Y.
## The beach presentation controller supplies beach/Beach at runtime.
@export var ground_reference: Node3D

var _style_is_unique: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 250
	# Remain in the actor's lifecycle/hierarchy but opt out of its transform.
	top_level = true
	_apply_style()
	update_ground_transform()


func _process(_delta: float) -> void:
	update_ground_transform()


func _apply_style() -> void:
	if not is_node_ready() or not (mesh is PlaneMesh):
		return
	if not _style_is_unique:
		mesh = mesh.duplicate()
		material_override = (mesh as PlaneMesh).material.duplicate()
		_style_is_unique = true
	(mesh as PlaneMesh).size = Vector2(width, depth)
	(material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, opacity)


func update_ground_transform() -> void:
	if not is_inside_tree():
		return
	var anchor := get_parent() as Node3D
	if anchor == null:
		return
	var foot_position := anchor.global_position
	# Treat ShadowAnchor.position as one fixed, world-aligned stance offset.
	# A nonzero authored offset must not orbit the root when the actor turns.
	var actor := anchor.get_parent() as Node3D
	if actor != null:
		foot_position = actor.global_position + anchor.position
	var ground_y: float = foot_position.y
	if is_instance_valid(ground_reference):
		ground_y = ground_reference.global_position.y
	global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(foot_position.x, ground_y + ground_offset, foot_position.z)
	)
