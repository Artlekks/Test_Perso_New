@tool
class_name NlkAreaEmitterGizmo
extends RefCounted

var _rid: RID
var _mesh: ArrayMesh
var _material: StandardMaterial3D


func setup(node: Node3D) -> void:
	if _rid.is_valid():
		return

	node.visibility_changed.connect(
		func(): RenderingServer.instance_set_visible(_rid, node.visible)
	)

	_create_mesh(node)
	_update_instance(node)


func update(node: Node3D) -> void:
	if not _rid.is_valid():
		setup(node)

	var is_selected := (
		node in EditorInterface.get_selection().get_selected_nodes()
	)

	var color := Color.CORNFLOWER_BLUE
	if not is_selected:
		color.a = 0.2

	_material.albedo_color = color

	@warning_ignore("unsafe_property_access")
	var transform := (
		node.global_transform
		* Transform3D.IDENTITY.scaled_local(node.area)
	)

	RenderingServer.instance_set_transform(_rid, transform)


func dispose() -> void:
	if _rid.is_valid():
		RenderingServer.free_rid(_rid)
		_rid = RID()


func _create_mesh(node: Node3D) -> void:
	var vertices := PackedVector3Array(
		[
			Vector3(-0.5, -0.5, -0.5),
			Vector3(0.5, -0.5, -0.5),
			Vector3(0.5, 0.5, -0.5),
			Vector3(-0.5, 0.5, -0.5),
			Vector3(-0.5, -0.5, 0.5),
			Vector3(0.5, -0.5, 0.5),
			Vector3(0.5, 0.5, 0.5),
			Vector3(-0.5, 0.5, 0.5),
		],
	)

	var indices := PackedInt32Array(
		[
			0,
			1,
			1,
			2,
			2,
			3,
			3,
			0,
			4,
			5,
			5,
			6,
			6,
			7,
			7,
			4,
			0,
			4,
			1,
			5,
			2,
			6,
			3,
			7,
		],
	)

	_mesh = ArrayMesh.new()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	_mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_LINES,
		arrays,
	)

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_mesh.surface_set_material(0, _material)

	_rid = RenderingServer.instance_create()

	RenderingServer.instance_set_scenario(
		_rid,
		node.get_world_3d().scenario,
	)

	RenderingServer.instance_set_visible(_rid, node.visible)

	RenderingServer.instance_geometry_set_cast_shadows_setting(
		_rid,
		RenderingServer.SHADOW_CASTING_SETTING_OFF,
	)

	RenderingServer.instance_set_base(_rid, _mesh)


func _update_instance(node: Node3D) -> void:
	RenderingServer.instance_set_transform(
		_rid,
		node.global_transform,
	)
