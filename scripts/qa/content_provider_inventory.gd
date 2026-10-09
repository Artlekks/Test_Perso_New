extends SceneTree
## Read-only off-tree inventory; no provider _ready or session/save side effects.
func _initialize() -> void:
	var world = load("res://scripts/world/world_location_service.gd").new()
	for location in world.get_all_locations():
		var scene = load(location.scene_path).instantiate()
		print("LOCATION ", location.location_id)
		walk(scene, scene)
		scene.free()
	world.free()
	quit()

func walk(node: Node, scene: Node) -> void:
	if node.get_script() != null:
		var script_path: String = node.get_script().resource_path
		if node.has_method("interact_from_world") or script_path.contains("fish_zone"):
			var row := {"path": String(scene.get_path_to(node)), "script": script_path, "refs": {}}
			for property in node.get_property_list():
				var key := String(property.name)
				if key.ends_with("_id") or key.ends_with("_profile") or key == "economy_context" or key == "fishing_spot":
					var value = node.get(key)
					row.refs[key] = value.resource_path if value is Resource else str(value)
			if node.has_method("get_technique_id"): row.refs.technique_id = String(node.get_technique_id())
			if node.has_method("get_teacher_id"): row.refs.teacher_id = String(node.get_teacher_id())
			print(JSON.stringify(row))
	for child in node.get_children(): walk(child, scene)
