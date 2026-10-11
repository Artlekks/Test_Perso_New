extends RefCounted
## Landscape-only lateral continuation of the authored beach/sea geometry.
## Reuses actual vertex heights, UVs and materials; never inserts a flat plane
## through sloped water. Scene-owned visuals only, with no physics or actors.
static func ensure(game: Node, wide: bool) -> void:
	if not game.is_inside_tree(): return
	var world := game.get_node_or_null("World")
	var beach := game.get_node_or_null("World/beach") as Node3D
	if world == null or beach == null: return
	var fill := world.get_node_or_null("MobileLandscapeGroundExtension") as Node3D
	if fill == null:
		if not wide: return
		fill = Node3D.new()
		fill.name = "MobileLandscapeGroundExtension"
		world.add_child(fill)
		fill.global_transform = beach.global_transform
		for id in ["Beach","Sea"]:
			var source := beach.get_node_or_null(id) as MeshInstance3D
			if source == null: continue
			for tile in [-2,-1,1,2]:
				var extension := MeshInstance3D.new()
				extension.name = "%s_%s" % [id,tile]
				extension.mesh = source.mesh
				extension.material_override = source.material_override
				extension.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				fill.add_child(extension)
				extension.transform = source.transform
				extension.position.x += source.basis.x.x*source.get_aabb().size.x*tile
		# Continue only the flat inland boundary. This strip shares the authored
		# land-edge height/material and never reaches into the sloping shoreline.
		var land := beach.get_node("Beach") as MeshInstance3D
		var bounds := land.get_aabb()
		var authored := land.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = authored[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = authored[Mesh.ARRAY_TEX_UV]
		var left_uv := Vector2.ZERO
		var right_uv := Vector2.ZERO
		for index in range(points.size()):
			if not is_equal_approx(points[index].z,bounds.end.z): continue
			if is_equal_approx(points[index].x,bounds.position.x): left_uv = uv[index]
			if is_equal_approx(points[index].x,bounds.end.x): right_uv = uv[index]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(bounds.position.x,0,bounds.end.z),Vector3(bounds.end.x,0,bounds.end.z),
			Vector3(bounds.position.x,0,bounds.end.z+32),Vector3(bounds.end.x,0,bounds.end.z+32)])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([left_uv,right_uv,left_uv,right_uv])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1,1,2,3])
		var inland := ArrayMesh.new()
		inland.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var inland_material := ShaderMaterial.new()
		inland_material.shader = preload("res://assets/models/shaders/mobile_inland_continuation.gdshader")
		inland_material.set_shader_parameter("frame_strip",land.material_override.get_shader_parameter("frame_strip"))
		inland_material.set_shader_parameter("frame_count",land.material_override.get_shader_parameter("frame_count"))
		inland_material.set_shader_parameter("animation_fps",land.material_override.get_shader_parameter("animation_fps"))
		inland_material.set_shader_parameter("land_edge_z",bounds.end.z)
		for tile in [-2,-1,0,1,2]:
			var extension := MeshInstance3D.new()
			extension.name = "Inland_%s" % tile
			extension.mesh = inland
			extension.material_override = inland_material
			extension.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fill.add_child(extension)
			extension.transform = land.transform
			extension.position.x += land.basis.x.x*bounds.size.x*tile
	fill.visible = wide
