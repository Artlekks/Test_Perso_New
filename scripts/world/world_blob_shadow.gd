@tool
extends MeshInstance3D
class_name WorldBlobShadow

## Place under ActorRoot/ShadowAnchor, never under the animated sprite.
## Width/depth are world units; actor scale, facing and billboarding are ignored.
## Runtime receivers. Author category size on the presentation profile's
## shadow_family_resource; editing this nested renderer is not persistent tuning.
@export_storage var width: float = 0.30:
	set(value):
		width = maxf(value, 0.01)
		_apply_style()
@export_storage var depth: float = 0.30:
	set(value):
		depth = maxf(value, 0.01)
		_apply_style()
@export_storage var opacity: float = 0.65:
	set(value):
		opacity = clampf(value, 0.0, 1.0)
		_apply_style()
@export_storage var ground_offset: float = 0.006:
	set(value):
		ground_offset = maxf(value, 0.001)
		update_ground_transform()

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
	(material_override as ShaderMaterial).set_shader_parameter("opacity", opacity)


func update_ground_transform() -> void:
	if not is_inside_tree():
		return
	var anchor := get_parent() as Node3D
	if anchor == null:
		return
	var foot_position := anchor.global_position
	# GroundPresentation is a world-aligned copy of the authoritative actor root.
	var presentation := anchor.get_parent() as Node3D
	if presentation != null:
		foot_position = presentation.global_position
	var ground_y: float = foot_position.y
	global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(foot_position.x, ground_y + ground_offset, foot_position.z)
	)
